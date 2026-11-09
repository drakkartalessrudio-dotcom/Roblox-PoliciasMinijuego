#!/usr/bin/env python3
"""Valida src/shared/Levels.json (formato de niveles de la fábrica, schemaVersion 1).

Uso:
    python validate_levels.py <ruta/Levels.json>
    python validate_levels.py <ruta/Levels.json> --json     # resultado como JSON
    python validate_levels.py <ruta/Levels.json> --quiet    # solo errores, avisos y resumen

Revisa la estructura de los datos y, para cada salto del recorrido (path), si es
posible con la física declarada (walkSpeed, jumpHeight, gravity):

  - altura: el salto sube como máximo jumpHeight - heightMargin;
  - distancia: alcance = walkSpeed * tiempo en el aire + edgeAllowance, donde el
    tiempo en el aire es el que tarda el personaje en volver a la altura destino.

Un salto es "imposible" (error) si no cumple altura o distancia, y "exigente"
(aviso) si usa más de demandingRatio de la capacidad. Las piezas con movimiento
lineal se evalúan en sus dos extremos ("timing" si solo uno es alcanzable).
El modelo es una aproximación: calibra validation.* con pruebas en Studio.

Sale con código 1 si hay errores, 2 si no puede leer el archivo y 0 si no hay errores.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

SCHEMA_VERSION = 1
KINDS = {"spawn", "platform", "checkpoint", "goal", "truss", "wall", "hazard", "collectible", "zone", "prop"}
STANDABLE = {"spawn", "platform", "checkpoint", "goal"}
PATH_KINDS = STANDABLE | {"truss"}
START_KINDS = {"spawn", "platform", "checkpoint"}
MOTION_KINDS = {"platform", "hazard", "wall", "prop"}
LAYOUTS = {"linear", "arena", "hub", "plots", "free"}
SHAPES = {"Block", "Ball", "Cylinder"}
AXES = {"X", "Y", "Z"}
MATERIALS = {
    "Plastic", "SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Marble", "Slate", "Concrete",
    "Granite", "Brick", "Pebble", "Cobblestone", "Rock", "Sandstone", "Basalt", "CrackedLava",
    "Limestone", "Pavement", "CorrodedMetal", "DiamondPlate", "Foil", "Metal", "Grass",
    "LeafyGrass", "Sand", "Fabric", "Snow", "Mud", "Ground", "Asphalt", "Salt", "Ice",
    "Glacier", "Glass", "ForceField", "Cardboard", "Carpet", "CeramicTiles", "ClayRoofTiles",
    "RoofShingles", "Leather", "Plaster", "Rubber",
}
ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")
COLOR_RE = re.compile(r"^#?[0-9A-Fa-f]{6}$")
MAX_PART_SIZE = 2048.0
DEFAULT_RULES = {
    "demandingRatio": 0.8,
    "onboardingRatio": 0.6,
    "edgeAllowance": 1.0,
    "heightMargin": 0.5,
    "maxJumpsBetweenCheckpoints": 10,
}
DEFAULT_MAX_PARTS = 2000
WALK_GAP = 0.5


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    physics: dict = field(default_factory=dict)
    levels: list[dict] = field(default_factory=list)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")

    def as_dict(self) -> dict:
        return {"errors": self.errors, "warnings": self.warnings, "physics": self.physics, "levels": self.levels}


@dataclass
class Box:
    """Caja alineada con los ejes: centro y semiejes."""
    cx: float
    cy: float
    cz: float
    ex: float
    ey: float
    ez: float

    @property
    def top(self) -> float:
        return self.cy + self.ey

    @property
    def bottom(self) -> float:
        return self.cy - self.ey

    def gap_xz(self, other: "Box") -> float:
        dx = max(0.0, (self.cx - self.ex) - (other.cx + other.ex), (other.cx - other.ex) - (self.cx + self.ex))
        dz = max(0.0, (self.cz - self.ez) - (other.cz + other.ez), (other.cz - other.ez) - (self.cz + self.ez))
        return math.hypot(dx, dz)

    def overlaps_xz(self, other: "Box", eps: float = 0.01) -> bool:
        return (abs(self.cx - other.cx) < self.ex + other.ex - eps
                and abs(self.cz - other.cz) < self.ez + other.ez - eps)

    def overlaps(self, other: "Box", eps: float = 0.01) -> bool:
        return self.overlaps_xz(other, eps) and abs(self.cy - other.cy) < self.ey + other.ey - eps

    def touches(self, other: "Box", eps: float = 0.01) -> bool:
        """Se tocan o se superponen (incluye caras en contacto)."""
        return (abs(self.cx - other.cx) <= self.ex + other.ex + eps
                and abs(self.cy - other.cy) <= self.ey + other.ey + eps
                and abs(self.cz - other.cz) <= self.ez + other.ez + eps)

    def shifted(self, dx: float, dy: float, dz: float) -> "Box":
        return Box(self.cx + dx, self.cy + dy, self.cz + dz, self.ex, self.ey, self.ez)


@dataclass
class Piece:
    level_index: int
    data: dict
    box: Box
    variants: list[Box]
    approximate: bool

    @property
    def id(self) -> str:
        return self.data["id"]

    @property
    def kind(self) -> str:
        return self.data["kind"]

    @property
    def motion_type(self) -> str | None:
        motion = self.data.get("motion")
        return motion.get("type") if isinstance(motion, dict) else None


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def read_vec3(value, where: str, name: str, result: Result) -> tuple[float, float, float] | None:
    if not isinstance(value, list) or len(value) != 3 or not all(is_number(v) for v in value):
        result.error(where, f"'{name}' debe ser una lista de 3 números")
        return None
    return float(value[0]), float(value[1]), float(value[2])


def rotation_matrix(rx: float, ry: float, rz: float) -> list[list[float]]:
    """Misma orientación que CFrame.Angles(rx, ry, rz) en Roblox: R = Rx * Ry * Rz."""
    ax, ay, az = (math.radians(v) for v in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    rot_x = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rot_y = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rot_z = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    return mul(rot_x, mul(rot_y, rot_z))


def is_truss_size(size) -> bool:
    """TrussPart: dos ejes de 2 studs y el tercero par, de 2 a 512."""
    ordered = sorted(size)
    return (abs(ordered[0] - 2) < 1e-6 and abs(ordered[1] - 2) < 1e-6
            and abs(ordered[2] / 2 - round(ordered[2] / 2)) < 1e-6 and 2 <= ordered[2] <= 512)


def make_box(center, size, rotation) -> tuple[Box, bool]:
    half = [s / 2 for s in size]
    if rotation is None or all(abs(r) < 1e-9 for r in rotation):
        return Box(*center, *half), False
    matrix = rotation_matrix(*rotation)
    extents = [sum(abs(matrix[i][j]) * half[j] for j in range(3)) for i in range(3)]
    aligned = all(min(abs(r) % 90, 90 - abs(r) % 90) < 1e-6 for r in rotation)
    return Box(*center, *extents), not aligned


def merge_rules(data: dict, result: Result) -> dict:
    rules = dict(DEFAULT_RULES)
    custom = data.get("validation", {})
    if not isinstance(custom, dict):
        result.error("validation", "debe ser un objeto")
        return rules
    for key, value in custom.items():
        if key not in DEFAULT_RULES:
            result.warn("validation", f"regla desconocida '{key}' (se ignora)")
        elif not is_number(value) or value < 0:
            result.error("validation", f"'{key}' debe ser un número positivo")
        else:
            rules[key] = float(value)
    return rules


def read_physics(data: dict, result: Result) -> dict | None:
    physics = data.get("physics")
    if not isinstance(physics, dict):
        result.error("physics", "falta el objeto physics con walkSpeed, jumpHeight y gravity")
        return None
    clean = {}
    for key in ("walkSpeed", "jumpHeight", "gravity"):
        value = physics.get(key)
        if not is_number(value) or value <= 0:
            result.error("physics", f"'{key}' debe ser un número mayor que 0")
        else:
            clean[key] = float(value)
    return clean if len(clean) == 3 else None


def capability(physics: dict, rules: dict) -> dict:
    gravity, height, speed = physics["gravity"], physics["jumpHeight"], physics["walkSpeed"]
    launch = math.sqrt(2 * gravity * height)
    usable = height - rules["heightMargin"]
    flat_reach = speed * (2 * launch / gravity) + rules["edgeAllowance"]
    return {"launchSpeed": launch, "usableHeight": usable, "flatReach": flat_reach}


def reach_for(dy: float, physics: dict, rules: dict) -> float | None:
    """Distancia horizontal alcanzable para subir dy (negativo = bajar). None si no llega en altura."""
    gravity, height, speed = physics["gravity"], physics["jumpHeight"], physics["walkSpeed"]
    if dy > height - rules["heightMargin"]:
        return None
    launch = math.sqrt(2 * gravity * height)
    disc = launch * launch - 2 * gravity * dy
    time_in_air = (launch + math.sqrt(max(disc, 0.0))) / gravity
    return speed * time_in_air + rules["edgeAllowance"]


def check_piece(piece: dict, level_index: int, where: str, origin, result: Result) -> Piece | None:
    if not isinstance(piece, dict):
        result.error(where, "cada pieza debe ser un objeto")
        return None
    piece_id = piece.get("id")
    if not isinstance(piece_id, str) or not ID_RE.match(piece_id):
        result.error(where, "'id' debe ser texto con letras, números, _ o -")
        return None
    where = f"{where} '{piece_id}'"
    kind = piece.get("kind")
    if kind not in KINDS:
        result.error(where, f"'kind' debe ser uno de: {', '.join(sorted(KINDS))}")
        return None
    position = read_vec3(piece.get("position"), where, "position", result)
    size = read_vec3(piece.get("size"), where, "size", result)
    if position is None or size is None:
        return None
    if any(s <= 0 or s > MAX_PART_SIZE for s in size):
        result.error(where, f"cada eje de 'size' debe estar entre 0 y {MAX_PART_SIZE:g} studs")
        return None
    rotation = None
    if "rotation" in piece:
        rotation = read_vec3(piece["rotation"], where, "rotation", result)
        if rotation is None:
            return None
    if "material" in piece and piece["material"] not in MATERIALS:
        result.warn(where, f"material '{piece['material']}' no está en la lista conocida; el juego usará el material por defecto si no existe")
    if "color" in piece and (not isinstance(piece["color"], str) or not COLOR_RE.match(piece["color"])):
        result.error(where, "'color' debe ser un hexadecimal como #FF8800")
    if "transparency" in piece and (not is_number(piece["transparency"]) or not 0 <= piece["transparency"] <= 1):
        result.error(where, "'transparency' debe estar entre 0 y 1")
    if "collide" in piece and not isinstance(piece["collide"], bool):
        result.error(where, "'collide' debe ser true o false")
    if "shape" in piece:
        if piece["shape"] not in SHAPES:
            result.error(where, f"'shape' debe ser uno de: {', '.join(sorted(SHAPES))}")
        elif kind in {"spawn", "truss"}:
            result.warn(where, f"'shape' no se aplica a piezas {kind}")
        elif piece["shape"] == "Ball" and len(set(size)) > 1:
            result.warn(where, "una esfera usa un tamaño uniforme; size debería tener los tres ejes iguales")
    if kind == "truss" and not is_truss_size(size):
        result.error(where, "un TrussPart mide 2 x 2 x N studs, con N par de 2 a 512; Roblox cambia cualquier otro tamaño")
    if kind == "spawn" and "enabled" in piece and not isinstance(piece["enabled"], bool):
        result.error(where, "'enabled' debe ser true o false")
    if kind == "checkpoint":
        order = piece.get("order")
        if not isinstance(order, int) or isinstance(order, bool) or order < 1:
            result.error(where, "un checkpoint necesita 'order' entero desde 1")
    if kind == "hazard" and "damage" in piece and (not is_number(piece["damage"]) or piece["damage"] <= 0):
        result.error(where, "'damage' debe ser un número mayor que 0")
    if kind == "collectible" and "value" in piece and not is_number(piece["value"]):
        result.error(where, "'value' debe ser un número")
    if kind == "zone" and (not isinstance(piece.get("name"), str) or not piece["name"].strip()):
        result.error(where, "una zona necesita 'name'")

    center = (origin[0] + position[0], origin[1] + position[1], origin[2] + position[2])
    box, approximate = make_box(center, size, rotation)
    variants = [box]
    motion = piece.get("motion")
    if motion is not None:
        if kind not in MOTION_KINDS:
            result.error(where, f"'motion' solo se admite en piezas {', '.join(sorted(MOTION_KINDS))}")
        elif not isinstance(motion, dict) or motion.get("type") not in {"linear", "spin"}:
            result.error(where, "'motion.type' debe ser 'linear' o 'spin'")
        elif motion["type"] == "linear":
            offset = read_vec3(motion.get("offset"), where, "motion.offset", result)
            period = motion.get("period")
            if not is_number(period) or period <= 0:
                result.error(where, "'motion.period' debe ser un número de segundos mayor que 0")
            if offset is not None:
                if math.hypot(*offset) < 0.01:
                    result.error(where, "'motion.offset' no puede ser nulo")
                else:
                    variants.append(box.shifted(*offset))
        else:
            if motion.get("axis", "Y") not in AXES:
                result.error(where, "'motion.axis' debe ser X, Y o Z")
            rpm = motion.get("rpm")
            if not is_number(rpm) or rpm == 0:
                result.error(where, "'motion.rpm' debe ser un número distinto de 0")
    return Piece(level_index, piece, box, variants, approximate)


def classify_link(source: Piece, target: Piece, physics: dict, rules: dict) -> dict:
    link = {"from": source.id, "to": target.id}
    if "spin" in (source.motion_type, target.motion_type):
        link.update({"class": "unchecked", "detail": "pieza giratoria: validar en Studio"})
        return link

    usable = physics["jumpHeight"] - rules["heightMargin"]
    candidates = []
    for source_box in source.variants:
        for target_box in target.variants:
            gap = source_box.gap_xz(target_box)
            if target.kind == "truss":
                # Se alcanza la escalera en cualquier altura entre su base y su tope.
                dy = max(0.0, target_box.bottom - source_box.top)
            else:
                dy = target_box.top - source_box.top
            reach = reach_for(dy, physics, rules)
            feasible = reach is not None and gap <= reach
            ratio = max(gap / reach if reach else math.inf, max(dy, 0.0) / usable if usable > 0 else math.inf)
            candidates.append({"gap": gap, "dy": dy, "reach": reach, "ratio": ratio, "feasible": feasible,
                               "overlap": source_box.overlaps_xz(target_box)})
    feasible = [c for c in candidates if c["feasible"]]
    best = min(feasible or candidates, key=lambda c: c["ratio"])
    link.update({"gap": round(best["gap"], 2), "dy": round(best["dy"], 2),
                 "reach": round(best["reach"], 2) if best["reach"] else None,
                 "ratio": round(best["ratio"], 3) if math.isfinite(best["ratio"]) else None})
    if not feasible:
        link["class"] = "impossible"
    elif "truss" in (source.kind, target.kind):
        link["class"] = "climb"
    elif best["gap"] <= WALK_GAP and -2.0 <= best["dy"] <= 1.0:
        link["class"] = "walk"
    elif len(feasible) < len(candidates):
        link["class"] = "timing"
    elif best["ratio"] > rules["demandingRatio"]:
        link["class"] = "demanding"
    else:
        link["class"] = "ok"
    link["ceiling"] = link["class"] != "climb" and best["overlap"] and best["dy"] > 1.0
    return link


def check_level(level, index: int, physics: dict | None, rules: dict, result: Result) -> tuple[list[Piece], dict]:
    where = f"levels[{index}]"
    if not isinstance(level, dict):
        result.error(where, "cada nivel debe ser un objeto")
        return [], {}
    level_id = level.get("id")
    if not isinstance(level_id, str) or not ID_RE.match(level_id):
        result.error(where, "'id' debe ser texto con letras, números, _ o -")
        level_id = f"#{index + 1}"
    where = f"nivel '{level_id}'"
    if not isinstance(level.get("name"), str) or not level["name"].strip():
        result.warn(where, "falta 'name'")
    layout = level.get("layout")
    if layout not in LAYOUTS:
        result.error(where, f"'layout' debe ser uno de: {', '.join(sorted(LAYOUTS))}")
    place = level.get("place")
    if place is not None and (not isinstance(place, str) or not ID_RE.match(place)):
        result.error(where, "'place' debe ser la clave de un place del GDD (letras, números, _ o -)")
        place = None
    difficulty = level.get("difficulty")
    if difficulty is None:
        if layout == "linear":
            result.warn(where, "falta 'difficulty' (1 a 10) para comparar con la curva medida")
    elif not is_number(difficulty) or not 1 <= difficulty <= 10:
        result.error(where, "'difficulty' debe estar entre 1 y 10")
    origin = (0.0, 0.0, 0.0)
    if "origin" in level:
        origin = read_vec3(level["origin"], where, "origin", result) or origin

    pieces: list[Piece] = []
    by_id: dict[str, Piece] = {}
    raw_pieces = level.get("pieces")
    if not isinstance(raw_pieces, list) or not raw_pieces:
        result.error(where, "'pieces' debe ser una lista no vacía")
        raw_pieces = []
    for piece_index, raw in enumerate(raw_pieces):
        piece = check_piece(raw, index, f"{where} pieces[{piece_index}]", origin, result)
        if piece is None:
            continue
        if piece.id in by_id:
            result.error(where, f"id de pieza repetido: '{piece.id}'")
            continue
        by_id[piece.id] = piece
        pieces.append(piece)

    summary = {"index": index + 1, "id": level_id, "name": level.get("name"), "place": place, "layout": layout,
               "declaredDifficulty": difficulty, "expectedSeconds": level.get("expectedSeconds"),
               "jumps": 0, "demanding": 0, "timing": 0, "unchecked": 0, "maxRatio": None, "links": []}

    start = level.get("start")
    if not isinstance(start, str) or start not in by_id:
        result.error(where, "'start' debe ser el id de una pieza del nivel")
    elif by_id[start].kind not in START_KINDS:
        result.error(where, f"'start' debe ser una pieza {', '.join(sorted(START_KINDS))}")

    orders: dict[int, str] = {}
    for piece in pieces:
        if piece.kind == "checkpoint" and isinstance(piece.data.get("order"), int):
            order = piece.data["order"]
            if order in orders:
                result.error(where, f"checkpoints '{orders[order]}' y '{piece.id}' repiten order {order}")
            orders[order] = piece.id
    if orders and sorted(orders) != list(range(1, len(orders) + 1)):
        result.warn(where, f"los order de checkpoints deberían ser consecutivos desde 1 (hay {sorted(orders)})")

    hazards = [p for p in pieces if p.kind == "hazard"]
    for piece in pieces:
        if piece.kind in {"spawn", "checkpoint", "goal"}:
            for hazard in hazards:
                pairs = [(v, h) for v in piece.variants for h in hazard.variants]
                if any(v.overlaps(h) for v, h in pairs):
                    result.error(where, f"'{piece.id}' ({piece.kind}) se superpone con el peligro '{hazard.id}'")
                elif any(v.touches(h) for v, h in pairs):
                    result.warn(where, f"'{piece.id}' ({piece.kind}) está en contacto con el peligro '{hazard.id}'")

    path = level.get("path")
    if layout == "linear" and not path:
        result.error(where, "un nivel linear necesita 'path' con el recorrido")
    if path is not None:
        if not isinstance(path, list) or not all(isinstance(p, str) for p in path):
            result.error(where, "'path' debe ser una lista de ids")
            path = []
        missing = [p for p in path if p not in by_id]
        if missing:
            result.error(where, f"'path' menciona piezas inexistentes: {', '.join(missing)}")
        if len(set(path)) != len(path):
            result.warn(where, "'path' repite piezas")
        steps = [by_id[p] for p in path if p in by_id]
        for piece in steps:
            if piece.kind not in PATH_KINDS:
                result.error(where, f"'{piece.id}' ({piece.kind}) no puede estar en el recorrido")
        if path and isinstance(start, str) and path[0] != start:
            result.error(where, f"'path' debe empezar en start ('{start}')")
        if layout == "linear":
            goals = [p for p in pieces if p.kind == "goal"]
            if not goals:
                result.error(where, "un nivel linear necesita una pieza goal")
            elif steps and steps[-1].kind != "goal":
                result.warn(where, "el recorrido no termina en la pieza goal")
            for checkpoint_id in orders.values():
                if checkpoint_id not in path:
                    result.warn(where, f"el checkpoint '{checkpoint_id}' no está en el recorrido")
        if physics and all(p.kind in PATH_KINDS for p in steps):
            check_path(steps, index, where, physics, rules, summary, result)

        if layout == "linear" and steps:
            lowest = min(p.box.top for p in steps)
            footprint = Box((min(p.box.cx - p.box.ex for p in steps) + max(p.box.cx + p.box.ex for p in steps)) / 2, 0,
                            (min(p.box.cz - p.box.ez for p in steps) + max(p.box.cz + p.box.ez for p in steps)) / 2,
                            (max(p.box.cx + p.box.ex for p in steps) - min(p.box.cx - p.box.ex for p in steps)) / 2, 0,
                            (max(p.box.cz + p.box.ez for p in steps) - min(p.box.cz - p.box.ez for p in steps)) / 2)
            if not any(h.box.top < lowest and h.box.overlaps_xz(footprint) for h in hazards):
                result.warn(where, "no hay un peligro debajo del recorrido; si el jugador cae, tarda en reaparecer")
    return pieces, summary


def check_path(steps: list[Piece], index: int, where: str, physics: dict, rules: dict, summary: dict, result: Result) -> None:
    jumps_since_respawn = 0
    for piece in steps:
        if piece.approximate:
            result.warn(where, f"'{piece.id}' tiene una rotación no múltiplo de 90°: la validación de sus saltos es aproximada")
        if piece.data.get("shape") in {"Ball", "Cylinder"}:
            result.warn(where, f"'{piece.id}' no es un bloque: la validación de sus saltos es aproximada")
    for source, target in zip(steps, steps[1:]):
        link = classify_link(source, target, physics, rules)
        summary["links"].append(link)
        label = f"{source.id} → {target.id}"
        kind = link["class"]
        if kind == "impossible":
            if link["reach"] is None:
                result.error(where, f"salto imposible {label}: sube {link['dy']} studs y el salto útil es {physics['jumpHeight'] - rules['heightMargin']:.2f}")
            else:
                result.error(where, f"salto imposible {label}: distancia {link['gap']} studs, alcance {link['reach']} con subida {link['dy']}")
        elif kind == "demanding":
            result.warn(where, f"salto exigente {label}: usa {link['ratio']:.0%} de la capacidad (distancia {link['gap']}, subida {link['dy']})")
        elif kind == "unchecked":
            summary["unchecked"] += 1
            result.warn(where, f"salto {label} sin validar: {link['detail']}")
        if link.get("ceiling"):
            result.warn(where, f"{label}: el destino está sobre el origen en planta; puede bloquear el salto con la cabeza")
        if kind in {"ok", "demanding", "timing", "impossible"}:
            summary["jumps"] += 1
            jumps_since_respawn += 1
            if link["ratio"] is not None:
                summary["maxRatio"] = max(summary["maxRatio"] or 0.0, link["ratio"])
        if kind == "demanding":
            summary["demanding"] += 1
        if kind == "timing":
            summary["timing"] += 1
        if index == 0 and kind in {"ok", "demanding", "timing"} and link["ratio"] is not None and link["ratio"] > rules["onboardingRatio"]:
            result.warn(where, f"primer nivel: {label} usa {link['ratio']:.0%} de la capacidad; el onboarding debería enseñar con saltos cómodos (≤ {rules['onboardingRatio']:.0%})")
        if target.kind == "checkpoint":
            jumps_since_respawn = 0
        elif jumps_since_respawn > rules["maxJumpsBetweenCheckpoints"]:
            result.warn(where, f"más de {int(rules['maxJumpsBetweenCheckpoints'])} saltos seguidos sin checkpoint (hasta '{target.id}')")
            jumps_since_respawn = 0


def validate(data) -> Result:
    result = Result()
    if not isinstance(data, dict):
        result.error("raíz", "el archivo debe contener un objeto JSON")
        return result
    if data.get("schemaVersion") != SCHEMA_VERSION:
        result.error("schemaVersion", f"debe ser {SCHEMA_VERSION}")
    rules = merge_rules(data, result)
    physics = read_physics(data, result)
    if physics:
        result.physics = {**physics, **{k: round(v, 3) for k, v in capability(physics, rules).items()}}
        if result.physics["usableHeight"] <= 0:
            result.error("physics", "jumpHeight es menor que validation.heightMargin: ningún salto sube")
    defaults = data.get("defaults", {})
    if not isinstance(defaults, dict):
        result.error("defaults", "debe ser un objeto")
    else:
        if "material" in defaults and defaults["material"] not in MATERIALS:
            result.warn("defaults", f"material '{defaults['material']}' no está en la lista conocida")
        if "color" in defaults and (not isinstance(defaults["color"], str) or not COLOR_RE.match(defaults["color"])):
            result.error("defaults", "'color' debe ser un hexadecimal como #A3A2A5")

    levels = data.get("levels")
    if not isinstance(levels, list) or not levels:
        result.error("levels", "debe ser una lista no vacía de niveles")
        return result

    all_pieces: list[Piece] = []
    seen_ids: set[str] = set()
    level_boxes: list[tuple[str, str | None, Box]] = []
    for index, level in enumerate(levels):
        pieces, summary = check_level(level, index, physics, rules, result)
        if summary:
            if summary["id"] in seen_ids:
                result.error(f"nivel '{summary['id']}'", "id de nivel repetido")
            seen_ids.add(summary["id"])
            result.levels.append(summary)
        all_pieces.extend(pieces)
        solid = [p.box for p in pieces if p.kind != "zone"]
        if solid:
            low = [min(b.cx - b.ex for b in solid), min(b.cy - b.ey for b in solid), min(b.cz - b.ez for b in solid)]
            high = [max(b.cx + b.ex for b in solid), max(b.cy + b.ey for b in solid), max(b.cz + b.ez for b in solid)]
            level_boxes.append((summary.get("id", f"#{index + 1}"), summary.get("place"),
                                Box(*[(lo + hi) / 2 for lo, hi in zip(low, high)], *[(hi - lo) / 2 for lo, hi in zip(low, high)])))

    # Cada place es un mundo aparte: los spawns y la superposición se revisan por place.
    places = {summary.get("place") for summary in result.levels} or {None}
    for place in places:
        level_indexes = {summary["index"] - 1 for summary in result.levels if summary.get("place") == place}
        enabled_spawns = [p for p in all_pieces if p.level_index in level_indexes and p.kind == "spawn" and p.data.get("enabled", True)]
        label = f"place '{place}'" if place else "levels"
        if not enabled_spawns:
            if len(places) == 1:
                result.error("levels", "no hay ningún spawn habilitado; los jugadores no tendrían dónde aparecer")
            else:
                result.warn(label, "no tiene ningún spawn habilitado; quien llegue aparece en el origen si el código no lo ubica")
        elif len(enabled_spawns) > 1:
            result.warn(label, f"hay {len(enabled_spawns)} spawns habilitados; cada jugador aparece en uno al azar")

    for i, (first_id, first_place, first) in enumerate(level_boxes):
        for second_id, second_place, second in level_boxes[i + 1:]:
            if first_place == second_place and first.overlaps(second):
                result.warn("levels", f"los niveles '{first_id}' y '{second_id}' se superponen en el espacio")

    budget = data.get("budget", {})
    max_parts = DEFAULT_MAX_PARTS
    if isinstance(budget, dict) and "maxParts" in budget:
        if isinstance(budget["maxParts"], int) and not isinstance(budget["maxParts"], bool) and budget["maxParts"] > 0:
            max_parts = budget["maxParts"]
        else:
            result.error("budget", "'maxParts' debe ser un entero mayor que 0")
    if len(all_pieces) > max_parts:
        result.warn("budget", f"{len(all_pieces)} piezas superan el presupuesto de {max_parts}")
    return result


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def format_report(path: Path, result: Result, quiet: bool) -> str:
    lines = [f"Validación de niveles: {path}"]
    if not quiet and result.physics:
        p = result.physics
        lines.append(f"Física: walkSpeed {p['walkSpeed']:g}, jumpHeight {p['jumpHeight']:g}, gravity {p['gravity']:g}"
                     f" → alcance en plano {p['flatReach']:.2f} studs, subida útil {p['usableHeight']:.2f} studs")
    if not quiet and result.levels:
        for level in result.levels:
            lines.append(f"Nivel {level['index']} '{level['id']}' ({level['name']}) · {level['layout']} · dificultad declarada {level['declaredDifficulty']}")
            for link in level["links"]:
                ratio = f"{link['ratio']:.0%}" if link.get("ratio") is not None else "-"
                gap = link.get("gap", "-")
                dy = link.get("dy", "-")
                lines.append(f"  {link['from']} → {link['to']}: {link['class']} (distancia {gap}, subida {dy}, uso {ratio})")
        lines.append("")
        lines.append("| # | id | dificultad declarada | saltos | exigentes | timing | uso máximo |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")
        for level in result.levels:
            peak = f"{level['maxRatio']:.0%}" if level["maxRatio"] is not None else "-"
            lines.append(f"| {level['index']} | {level['id']} | {level['declaredDifficulty']} | {level['jumps']} | {level['demanding']} | {level['timing']} | {peak} |")
        lines.append("")
    lines.extend(f"ERROR {e}" for e in result.errors)
    lines.extend(f"WARN  {w}" for w in result.warnings)
    lines.append(f"Resultado: {len(result.errors)} errores, {len(result.warnings)} advertencias")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Valida Levels.json del contrato de la fábrica.")
    parser.add_argument("levels", type=Path, help="ruta a src/shared/Levels.json")
    parser.add_argument("--json", action="store_true", help="imprime el resultado como JSON")
    parser.add_argument("--quiet", action="store_true", help="solo errores, advertencias y resumen")
    args = parser.parse_args(argv)
    try:
        data = load(args.levels)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(f"ERROR no se pudo leer {args.levels}: {exc}")
        return 2
    result = validate(data)
    if args.json:
        print(json.dumps(result.as_dict(), ensure_ascii=False, indent=2))
    else:
        print(format_report(args.levels, result, args.quiet))
    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
