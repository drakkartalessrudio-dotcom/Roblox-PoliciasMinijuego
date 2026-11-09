#!/usr/bin/env python3
"""Revisa el pase de arte de un juego de la fábrica (src/shared/Environment.json).

Uso:
    python check_environment.py <carpeta-del-juego>
    python check_environment.py <carpeta-del-juego> --json

Comprueba:
  - el formato de Environment.json: estilos por tipo de pieza (color, material,
    adornos, texturas y variantes de material), prefabs, props, terreno, luces,
    sonidos y assets del usuario, y que sus niveles existan en Levels.json;
  - los colores: solo nombres de la paleta o roles de Theme.json, nunca
    hexadecimales; peligros, checkpoints, metas y coleccionables con el color de
    su rol; ningún otro color se confunde con el peligro (ΔE con visión normal y
    con daltonismo);
  - que la decoración no cambie el juego: nada en el aire de los saltos del
    recorrido, nada sólido (props con colisión o terreno) al alcance de un salto
    ni en la caída desde una pieza pisable, agua solo lejos de lo jugable;
  - que la decoración no engañe: props sin colisión con forma de escalón al
    alcance, o que tapan gran parte de una superficie;
  - que se vea bien: el terreno a 4 studs o más de toda pieza (sus vóxeles
    redondean los bordes y asoman), sin caras superpuestas en el mismo plano
    (z-fighting) y sin superficies grandes de plástico liso sin tratar;
  - el presupuesto de piezas y luces (heurístico: Roblox no publica uno);
  - los assets del usuario: origen y licencia, archivos que existen, IDs
    declarados en el GDD y carpetas mapeadas en default.project.json;
  - que design/ENVIRONMENT.md describa cada nivel.

Usa los scripts de roblox-level-designer (geometría y saltos) y
roblox-art-director (colores y daltonismo), instalados al lado de este skill.
Sale con código 1 si hay errores.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import environment_scene as es  # noqa: E402

SKILLS_DIR = Path(__file__).resolve().parents[2]
LEVEL_VALIDATOR = SKILLS_DIR / "roblox-level-designer" / "scripts" / "validate_levels.py"
ART_CHECKER = SKILLS_DIR / "roblox-art-director" / "scripts" / "check_art.py"

SCHEMA_VERSION = 1
LOCKED = es.LOCKED
GAMEPLAY_ROLES = {"hazard": "peligro", "interactive": "checkpoint o interactivo", "goal": "meta", "reward": "recompensa"}
STYLE_KEYS = {"color", "material", "variation", "dressing", "texture", "materialVariant"}
DRESSING_COMMON = {"color", "material"}
PREFAB_SHAPES = {"Block", "Ball", "Cylinder", "Wedge"}
TERRAIN_SHAPES = {"Block", "Ball", "Cylinder", "Wedge"}
TERRAIN_MATERIALS = {
    "Asphalt", "Basalt", "Brick", "Cobblestone", "Concrete", "CrackedLava", "Glacier", "Grass", "Ground",
    "Ice", "LeafyGrass", "Limestone", "Mud", "Pavement", "Rock", "Salt", "Sand", "Sandstone", "Slate",
    "Snow", "Water", "WoodPlanks", "Air",
}
LIGHT_TYPES = {"Point", "Spot", "Surface"}
FACES = {"Top", "Bottom", "Front", "Back", "Left", "Right"}
ASSET_KINDS = {"model": "file", "materialVariant": "file", "texture": "id", "sound": "id", "animation": "id"}
MODEL_EXTENSIONS = {".rbxm", ".rbxmx"}
MAX_LIGHT_RANGE = 60.0
MAX_VARIATION = es.MAX_VARIATION
MAX_GRID_LINES = 200
MAX_CHECKER_TILES = 400
DEFAULT_BUDGET = {"maxParts": 3000, "maxLights": 24, "maxShadowLights": 2}
CLEARANCE = 6.0         # alto del personaje con margen, por encima de la altura de salto
LINEAR_FALL = 50.0      # caída que se revisa debajo de un recorrido sin peligro debajo
CORRIDOR_MARGIN = 2.0   # ancho extra del aire de un salto (cuerpo del personaje)
CONTAIN_TOLERANCE = 0.05
VOXEL = 4.0             # el terreno de Roblox se arma con vóxeles de 4 × 4 × 4 studs
LARGE_SURFACE = 300.0   # studs² a partir de los que una superficie lisa se ve como blockout
FLAT_MATERIALS = {"SmoothPlastic", "Plastic"}
PLANE_TOLERANCE = 0.005
MIN_OVERLAP = 0.01
MAX_ZFIGHT_MESSAGES = 10
ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")
HEX_RE = re.compile(r"^#?[0-9A-Fa-f]{6}$")
ASSET_ID_RE = re.compile(r"^rbxassetid://(\d+)$")
ASSET_RE = re.compile(r"rbxassetid://|rbxasset://|roblox\.com/asset", re.IGNORECASE)


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    levels: list[dict] = field(default_factory=list)
    totals: dict = field(default_factory=dict)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")

    def note(self, where: str, message: str) -> None:
        self.notes.append(f"{where}: {message}")


def load_sibling(path: Path, name: str):
    """Carga el script de otro skill instalado al lado, o None si no está."""
    if not path.exists():
        return None
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module  # dataclasses necesita el módulo registrado al cargarse
    try:
        spec.loader.exec_module(module)
    except Exception:
        del sys.modules[name]
        raise
    return module


is_number = es.is_number
vec3 = es.vec3


def boxes_overlap(first: tuple, second: tuple, eps: float = 0.01) -> bool:
    (low1, high1), (low2, high2) = first, second
    return all(low1[i] < high2[i] - eps and low2[i] < high1[i] - eps for i in range(3))


class Checker:
    def __init__(self, environment: dict, theme: dict, levels_data: dict, levels_module, art_module, game: Path | None = None):
        self.env = environment
        self.theme_data = theme if isinstance(theme, dict) else {}
        self.theme = es.Palette(self.theme_data)
        self.levels_data = levels_data
        self.vl = levels_module
        self.art = art_module
        self.game = game
        self.result = Result()
        self.material_names = set(levels_module.MATERIALS) | set(getattr(art_module, "MATERIALS", set()))
        validation = self.theme_data.get("validation", {}) if isinstance(self.theme_data.get("validation"), dict) else {}
        self.min_delta = float(validation.get("minDeltaE", art_module.DEFAULT_VALIDATION["minDeltaE"]))
        self.hazard_hex = self.theme.role_hex("hazard")
        self.reported: set[tuple] = set()
        assets = environment.get("assets", {}) if isinstance(environment, dict) else {}
        self.assets = assets if isinstance(assets, dict) else {}

    # Colores y materiales -------------------------------------------------

    def color(self, reference, where: str) -> str | None:
        if isinstance(reference, str) and HEX_RE.match(reference):
            self.result.error(where, f"color {reference!r}: usa un nombre de la paleta o un rol de Theme.json, no un hexadecimal")
            return None
        value = self.theme.hex(reference)
        if value is None:
            self.result.error(where, f"el color {reference!r} no es un rol ni un nombre de la paleta de Theme.json; pídelo al art director")
        return value

    def material(self, reference, where: str) -> None:
        if not isinstance(reference, str) or (reference not in self.material_names and reference not in self.theme.materials):
            self.result.error(where, f"material {reference!r}: usa un Enum.Material o un rol de Theme.materials")

    def confusion(self, hex_value: str) -> tuple[float, str] | None:
        """Peor ΔE contra el peligro si se confunden, o None."""
        if not self.hazard_hex or hex_value == self.hazard_hex:
            return (0.0, "normal") if hex_value == self.hazard_hex else None
        distances = self.art.delta_e(self.art.hex_to_rgb(hex_value), self.art.hex_to_rgb(self.hazard_hex))
        worst = min(distances, key=distances.get)
        return (distances[worst], worst) if distances[worst] < self.min_delta else None

    def decoration_color(self, reference, where: str) -> None:
        value = self.color(reference, where)
        if value is None:
            return
        key = ("deco", reference, where.split(" ")[0])
        if key in self.reported:
            return
        for role, meaning in GAMEPLAY_ROLES.items():
            if self.theme.role_hex(role) == value:
                self.reported.add(key)
                self.result.warn(where, f"la decoración usa {reference!r}, el color de {meaning}: el jugador lo puede leer como parte del juego")
                return
        confused = self.confusion(value)
        if confused:
            self.reported.add(key)
            self.result.warn(where, f"{reference!r} se confunde con el peligro en {confused[1]} (ΔE {confused[0]:.1f}); la decoración no debe parecer peligrosa")

    def asset_of(self, name, kind: str, where: str) -> dict | None:
        asset = self.assets.get(name) if isinstance(name, str) else None
        if not isinstance(asset, dict) or asset.get("kind") != kind:
            self.result.error(where, f"{name!r} no está declarado en 'assets' como {kind}")
            return None
        return asset

    # Estilos de piezas ----------------------------------------------------

    def style(self, kind: str, style, where: str) -> None:
        if not isinstance(style, dict):
            self.result.error(where, "el estilo debe ser un objeto")
            return
        for key in style:
            if key not in STYLE_KEYS:
                self.result.warn(where, f"campo desconocido {key!r}: el loader solo cambia {', '.join(sorted(STYLE_KEYS))}")
        if "material" in style:
            self.material(style["material"], where)
        if "materialVariant" in style:
            self.asset_of(style["materialVariant"], "materialVariant", where)
        if "texture" in style:
            self.texture(style["texture"], where)
        if "color" in style:
            value = self.color(style["color"], where)
            locked = LOCKED.get(kind)
            if value and locked and value != self.theme.role_hex(locked):
                self.result.error(where, f"las piezas {kind} siempre usan el color del rol {locked!r}; el loader ignora otro color")
            elif value and not locked:
                confused = self.confusion(value)
                if confused:
                    message = f"{style['color']!r} se confunde con el peligro en {confused[1]} (ΔE {confused[0]:.1f})"
                    if kind in {"platform", "spawn", "truss", "moving"}:
                        self.result.error(where, message + "; el jugador no sabría dónde puede pisar")
                    else:
                        self.result.warn(where, message)
        if "variation" in style:
            variation = style["variation"]
            if not is_number(variation) or not 0 <= variation <= MAX_VARIATION:
                self.result.error(where, f"'variation' debe estar entre 0 y {MAX_VARIATION}")
            elif kind in LOCKED and variation > 0:
                self.result.warn(where, f"las piezas {kind} no varían de color; se ignora 'variation'")
        if "dressing" in style:
            self.dressing(kind, style["dressing"], where)

    def dressing(self, kind: str, dressing, where: str) -> None:
        if not isinstance(dressing, dict):
            self.result.error(where, "'dressing' debe ser un objeto adorno → color o { color, material, ... }")
            return
        if kind == "moving":
            self.result.warn(where, "las piezas que se mueven no llevan adornos; se ignora 'dressing'")
        for name, value in dressing.items():
            if name not in es.DRESSINGS:
                self.result.error(where, f"adorno desconocido {name!r}: usa {', '.join(es.DRESSINGS)}")
                continue
            kinds, extra = es.DRESSINGS[name]
            if kind != "moving" and kind not in kinds:
                self.result.warn(where, f"las piezas {kind} no llevan el adorno {name!r}; se ignora")
            spec = value if isinstance(value, dict) else {"color": value}
            for key, field_value in spec.items():
                if key not in DRESSING_COMMON | extra:
                    self.result.warn(f"{where} dressing.{name}", f"campo desconocido {key!r}")
                elif key == "at" and (not is_number(field_value) or not 0 < field_value < 1):
                    self.result.error(f"{where} dressing.{name}", "'at' es la altura relativa del muro: entre 0 y 1")
                elif key in extra - {"at"} and (not is_number(field_value) or field_value <= 0):
                    self.result.error(f"{where} dressing.{name}", f"'{key}' debe ser un número mayor que 0")
            self.decoration_color(spec.get("color", "surfaceAlt"), f"{where} dressing.{name}")
            if "material" in spec:
                self.material(spec["material"], f"{where} dressing.{name}")

    def texture(self, value, where: str) -> None:
        spec = value if isinstance(value, dict) else {"asset": value}
        self.asset_of(spec.get("asset"), "texture", where)
        tile = spec.get("studsPerTile", 8)
        if not ((is_number(tile) and tile > 0) or (isinstance(tile, list) and len(tile) == 2 and all(is_number(t) and t > 0 for t in tile))):
            self.result.error(where, "'studsPerTile' debe ser un número o [u, v] mayores que 0")
        faces = spec.get("faces")
        if faces is not None and (not isinstance(faces, list) or not faces or any(face not in FACES for face in faces)):
            self.result.error(where, f"'faces' debe ser una lista de: {', '.join(sorted(FACES))}")
        if "color" in spec:
            self.color(spec["color"], where)
        transparency = spec.get("transparency", 0)
        if not is_number(transparency) or not 0 <= transparency <= 1:
            self.result.error(where, "'transparency' de la textura debe estar entre 0 y 1")

    # Prefabs --------------------------------------------------------------

    def part_extents(self, part: dict, box: tuple[float, float, float]):
        """Semiejes de la parte (en studs) alineados con la caja, antes de su rotación."""
        size = vec3(part.get("size")) or (1.0, 1.0, 1.0)
        extent = [s * b for s, b in zip(size, box)]
        shape = part.get("shape", "Block")
        if shape == "Ball":
            diameter = min(extent)
            return [diameter, diameter, diameter]
        if shape == "Cylinder":
            axis = "XYZ".index(part.get("axis", "Y")) if part.get("axis", "Y") in ("X", "Y", "Z") else 1
            diameter = min(e for i, e in enumerate(extent) if i != axis)
            return [extent[i] if i == axis else diameter for i in range(3)]
        return extent

    def prefab(self, name: str, prefab, where: str) -> None:
        if not isinstance(prefab, dict):
            self.result.error(where, "cada prefab debe ser un objeto")
            return
        box = vec3(prefab.get("size"))
        if box is None or any(b <= 0 for b in box):
            self.result.error(where, "'size' debe ser una lista de 3 números mayores que 0 (la caja del prop en studs)")
            box = (4.0, 4.0, 4.0)
        colors = prefab.get("colors", {})
        if not isinstance(colors, dict):
            self.result.error(where, "'colors' debe ser un objeto ranura → color")
            colors = {}
        parts = prefab.get("parts")
        if not isinstance(parts, list) or not parts:
            self.result.error(where, "'parts' debe ser una lista no vacía")
            return
        for index, part in enumerate(parts):
            part_where = f"{where} parts[{index}]"
            if not isinstance(part, dict):
                self.result.error(part_where, "cada parte debe ser un objeto")
                continue
            if part.get("shape", "Block") not in PREFAB_SHAPES:
                self.result.error(part_where, f"'shape' debe ser uno de: {', '.join(sorted(PREFAB_SHAPES))}")
            center = vec3(part.get("center", [0, 0, 0]))
            size = vec3(part.get("size"))
            if center is None or any(abs(c) > 0.5 for c in center):
                self.result.error(part_where, "'center' debe ser una lista de 3 números entre -0.5 y 0.5 (fracción de la caja)")
                continue
            if size is None or any(s <= 0 or s > 1 for s in size):
                self.result.error(part_where, "'size' debe ser una lista de 3 fracciones de la caja, mayores que 0 y hasta 1")
                continue
            if part.get("axis", "Y") not in ("X", "Y", "Z"):
                self.result.error(part_where, "'axis' debe ser X, Y o Z")
            rotation = vec3(part.get("rotation", [0, 0, 0]))
            if rotation is None:
                self.result.error(part_where, "'rotation' debe ser una lista de 3 ángulos en grados")
                rotation = (0.0, 0.0, 0.0)
            extents = self.part_extents(part, box)
            aabb, _ = self.vl.make_box([c * b for c, b in zip(center, box)], extents, list(rotation))
            for axis, (half, b) in enumerate(zip((aabb.ex, aabb.ey, aabb.ez), box)):
                if abs((aabb.cx, aabb.cy, aabb.cz)[axis]) + half > b / 2 * (1 + CONTAIN_TOLERANCE) + 1e-6:
                    self.result.warn(part_where, f"se sale de la caja del prefab en el eje {'XYZ'[axis]}; el validador usa la caja para medir el prop")
                    break
            self.material(part.get("material", "SmoothPlastic"), part_where)
            if "transparency" in part and (not is_number(part["transparency"]) or not 0 <= part["transparency"] <= 0.9):
                self.result.error(part_where, "'transparency' debe estar entre 0 y 0.9")
            slot = part.get("color", "secondary")
            if not isinstance(slot, str):
                self.result.error(part_where, "'color' debe ser una ranura o un color de la paleta")
            elif slot not in colors and self.theme.hex(slot) is None:
                self.result.error(part_where, f"la ranura {slot!r} no tiene color en 'colors' ni es un color del tema")
            if "light" in part:
                self.light(part["light"], f"{part_where} light", slots=colors)

    def light(self, spec, where: str, slots: dict | None = None) -> tuple[int, int]:
        """Valida una luz y devuelve (luces, luces con sombra)."""
        if not isinstance(spec, dict):
            self.result.error(where, "la luz debe ser un objeto")
            return 0, 0
        if spec.get("type", "Point") not in LIGHT_TYPES:
            self.result.error(where, f"'type' debe ser uno de: {', '.join(sorted(LIGHT_TYPES))}")
        reference = spec.get("color", "light" if slots is not None else "text")
        if slots is not None and isinstance(reference, str):
            reference = slots.get(reference, reference)
        self.color(reference, where)
        if "brightness" in spec and (not is_number(spec["brightness"]) or not 0 <= spec["brightness"] <= 10):
            self.result.error(where, "'brightness' debe estar entre 0 y 10")
        if "range" in spec:
            if not is_number(spec["range"]) or spec["range"] <= 0:
                self.result.error(where, "'range' debe ser un número mayor que 0")
            elif spec["range"] > MAX_LIGHT_RANGE:
                self.result.warn(where, f"Roblox limita el alcance de una luz a {MAX_LIGHT_RANGE:g} studs")
        if "face" in spec and spec["face"] not in FACES:
            self.result.error(where, f"'face' debe ser uno de: {', '.join(sorted(FACES))}")
        shadows = spec.get("shadows", False)
        if not isinstance(shadows, bool):
            self.result.error(where, "'shadows' debe ser true o false")
            shadows = False
        return 1, int(shadows)

    # Assets del usuario ---------------------------------------------------

    def check_assets(self) -> None:
        raw = self.env.get("assets", {})
        if not isinstance(raw, dict):
            self.result.error("assets", "debe ser un objeto nombre → asset")
            return
        kinds_used = set()
        for name, asset in raw.items():
            where = f"assets.{name}"
            if not ID_RE.match(str(name)):
                self.result.error(where, "el nombre usa letras, números, _ o -")
            if not isinstance(asset, dict):
                self.result.error(where, "cada asset debe ser un objeto")
                continue
            kind = asset.get("kind")
            if kind not in ASSET_KINDS:
                self.result.error(where, f"'kind' debe ser uno de: {', '.join(sorted(ASSET_KINDS))}")
                continue
            kinds_used.add(kind)
            for key in ("source", "license"):
                if not isinstance(asset.get(key), str) or not asset[key].strip():
                    self.result.error(where, f"falta '{key}': de dónde salió el asset y con qué licencia se usa (lo confirma el usuario)")
            if ASSET_KINDS[kind] == "file":
                file = asset.get("file")
                if not isinstance(file, str) or Path(file).suffix.lower() not in MODEL_EXTENSIONS:
                    self.result.error(where, "'file' debe ser la ruta de un .rbxm o .rbxmx dentro del juego (por ejemplo assets/models/Fuente.rbxm)")
                elif self.game is not None and not (self.game / file).is_file():
                    self.result.error(where, f"no existe el archivo {file}")
            else:
                if not isinstance(asset.get("id"), str) or not ASSET_ID_RE.match(asset["id"]):
                    self.result.error(where, "'id' debe tener la forma rbxassetid://123456 y venir del usuario; nunca lo inventes ni lo busques por tu cuenta")
            if kind == "model":
                size = asset.get("size")
                if size is not None and (vec3(size) is None or any(s <= 0 for s in vec3(size))):
                    self.result.error(where, "'size' debe ser la caja del modelo en studs: 3 números mayores que 0")
            if kind == "materialVariant" and (not isinstance(asset.get("base"), str) or asset["base"] not in self.material_names):
                self.result.error(where, "'base' debe ser el Enum.Material sobre el que está hecha la variante")
        if kinds_used & {"texture", "sound", "animation"}:
            self.result.note("assets", "un asset restringido solo se ve o se oye si la experiencia tiene permiso para usarlo; el usuario lo otorga en Creator Hub")
        if "animation" in kinds_used:
            self.result.note("assets", "una animación solo se reproduce si es de la cuenta o del grupo dueño de la experiencia; pruébala en una experiencia publicada")

    # Niveles --------------------------------------------------------------

    def walkable_boxes(self, pieces, layout: str):
        hazards = [h for h in pieces if h.kind == "hazard"]
        jump = self.physics["jumpHeight"]
        reach = self.capability["flatReach"]
        entries = []
        for piece in pieces:
            if piece.kind not in self.vl.STANDABLE and piece.kind != "truss":
                continue
            for box in piece.variants:
                top = box.top + jump + CLEARANCE
                below = [v.top for h in hazards for v in h.variants if v.top <= box.bottom + 0.01 and v.overlaps_xz(box)]
                if below:
                    low = max(below)
                elif layout == "linear":
                    low = box.bottom - LINEAR_FALL
                else:
                    low = box.bottom
                reach_box = self.vl.Box(box.cx, (low + top) / 2, box.cz, box.ex + reach, (top - low) / 2, box.ez + reach)
                clearance = self.vl.Box(box.cx, (box.top + top) / 2, box.cz, box.ex, (top - box.top) / 2, box.ez)
                entries.append((piece, box, reach_box, clearance))
        return entries

    def corridors(self, steps):
        jump = self.physics["jumpHeight"]
        boxes = []
        for source, target in zip(steps, steps[1:]):
            for a in source.variants:
                for b in target.variants:
                    ranges = []
                    for center_a, half_a, center_b, half_b in ((a.cx, a.ex, b.cx, b.ex), (a.cz, a.ez, b.cz, b.ez)):
                        a0, a1, b0, b1 = center_a - half_a, center_a + half_a, center_b - half_b, center_b + half_b
                        if a1 < b0:
                            low, high = a1, b0
                        elif b1 < a0:
                            low, high = b1, a0
                        else:
                            low, high = max(a0, b0), min(a1, b1)
                        ranges.append((low - CORRIDOR_MARGIN, high + CORRIDOR_MARGIN))
                    (x0, x1), (z0, z1) = ranges
                    y0, y1 = min(a.top, b.top), max(a.top, b.top) + jump + CLEARANCE
                    boxes.append((f"{source.id} → {target.id}",
                                  self.vl.Box((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2)))
        return boxes

    def item_box(self, center, size, rotation):
        box, _ = self.vl.make_box(center, size, rotation)
        return box

    def space(self, level: dict, pieces) -> dict:
        """Zonas jugables de un nivel: alcance y espacio libre de cada pieza pisable y aire de los saltos."""
        layout = level.get("layout", "free")
        by_id = {p.id: p for p in pieces}
        path = level.get("path") if isinstance(level.get("path"), list) else []
        steps = [by_id[p] for p in path if p in by_id]
        return {"walkables": self.walkable_boxes(pieces, layout),
                "corridors": self.corridors(steps) if layout == "linear" else []}

    def problems(self, space: dict, label: str, box, solid: bool, water: bool, is_prop: bool) -> list[tuple[str, str]]:
        """Problemas de un elemento de decoración: lista de ("error" | "warn", mensaje)."""
        blocked = next((name for name, corridor in space["corridors"] if box.overlaps(corridor)), None)
        if blocked:
            return [("error", f"{label} invade el aire del salto {blocked}; muévelo fuera de la trayectoria")]
        reach = self.capability["flatReach"]
        near = next((piece for piece, _, reach_box, _ in space["walkables"] if box.overlaps(reach_box)), None)
        if near is not None and (solid or water):
            if water:
                return [("error", f"{label} está al alcance de '{near.id}': el agua hace nadar y cambia el movimiento")]
            if is_prop:
                return [("error", f"{label} tiene colisión al alcance de '{near.id}' ({reach:.1f} studs o en su caída): puede servir de atajo o atajar una caída; sácalo del alcance o usa collide false")]
            return [("error", f"{label} está al alcance de '{near.id}' ({reach:.1f} studs o en su caída): el terreno siempre tiene colisión y cambia el recorrido")]
        if not is_prop or solid:
            return []
        usable = self.physics["jumpHeight"] - self.rules["heightMargin"]
        for piece, piece_box, reach_box, clearance in space["walkables"]:
            if box.overlaps(clearance):
                overlap_x = max(0.0, min(box.cx + box.ex, piece_box.cx + piece_box.ex) - max(box.cx - box.ex, piece_box.cx - piece_box.ex))
                overlap_z = max(0.0, min(box.cz + box.ez, piece_box.cz + piece_box.ez) - max(box.cz - box.ez, piece_box.cz - piece_box.ez))
                area = 4 * piece_box.ex * piece_box.ez
                if area > 0 and overlap_x * overlap_z / area > 0.25 and box.bottom <= piece_box.top + 1:
                    return [("warn", f"{label} tapa más de un cuarto de la superficie de '{piece.id}'; el jugador no ve dónde pisa")]
            if box.overlaps(reach_box) and box.ex >= 1 and box.ez >= 1 and -1 <= box.top - piece_box.top <= usable:
                return [("warn", f"{label} no tiene colisión pero parece pisable desde '{piece.id}' (su parte de arriba está a la altura de un salto); el jugador puede intentar saltar ahí y caer. Si debe ser un obstáculo, pídeselo al level designer")]
        return []

    def check_space(self, level: dict, pieces, items, where: str) -> None:
        space = self.space(level, pieces)
        for label, box, solid, water, is_prop in items:
            for severity, message in self.problems(space, label, box, solid, water, is_prop):
                (self.result.error if severity == "error" else self.result.warn)(where, message)

    def prepare(self) -> bool:
        """Lee la física de Levels.json. False si no se puede medir nada."""
        physics = self.vl.read_physics(self.levels_data, self.vl.Result())
        if physics is None:
            self.result.error("Levels.json", "no tiene physics válida; corre validate_levels.py")
            return False
        self.rules = self.vl.merge_rules(self.levels_data, self.vl.Result())
        self.physics = physics
        self.capability = self.vl.capability(physics, self.rules)
        return True

    def check_level(self, level_id: str, level_env, level: dict, index: int, prefabs: dict) -> None:
        where = f"levels.{level_id}"
        if not isinstance(level_env, dict):
            self.result.error(where, "debe ser un objeto")
            return
        pieces, _ = self.vl.check_level(level, index, self.physics, self.rules, self.vl.Result())
        by_id = {p.id: p for p in pieces}
        origin = vec3(level.get("origin", [0, 0, 0])) or (0.0, 0.0, 0.0)

        level_pieces = level_env.get("pieces", {})
        if not isinstance(level_pieces, dict):
            self.result.error(where, "'pieces' debe ser un objeto tipo → estilo")
        else:
            for kind, style in level_pieces.items():
                if kind not in self.vl.KINDS and kind != "moving":
                    self.result.error(f"{where}.pieces", f"tipo de pieza desconocido {kind!r}")
                else:
                    self.style(kind, style, f"{where}.pieces.{kind}")
        overrides = level_env.get("overrides", {})
        if not isinstance(overrides, dict):
            self.result.error(where, "'overrides' debe ser un objeto id de pieza → estilo")
        else:
            for piece_id, style in overrides.items():
                if piece_id not in by_id:
                    self.result.error(f"{where}.overrides", f"no existe la pieza {piece_id!r} en el nivel")
                else:
                    self.style(by_id[piece_id].kind, style, f"{where}.overrides.{piece_id}")

        items = []  # (descripción, caja, sólido, es agua, es prop)
        props = level_env.get("props", [])
        if not isinstance(props, list):
            self.result.error(where, "'props' debe ser una lista")
            props = []
        seen: set[str] = set()
        for index_prop, prop in enumerate(props):
            prop_where = f"{where}.props[{index_prop}]"
            if not isinstance(prop, dict):
                self.result.error(prop_where, "cada prop debe ser un objeto")
                continue
            prop_id = prop.get("id")
            if not isinstance(prop_id, str) or not ID_RE.match(prop_id):
                self.result.error(prop_where, "'id' debe ser texto con letras, números, _ o -")
                continue
            prop_where = f"{where}.props '{prop_id}'"
            if prop_id in seen or prop_id in by_id:
                self.result.error(prop_where, "id repetido en el nivel (props y piezas comparten nombres en el juego)")
            seen.add(prop_id)
            prefab, asset = None, None
            if "asset" in prop:
                asset = self.asset_of(prop.get("asset"), "model", prop_where)
                if asset is None:
                    continue
                if "prefab" in prop:
                    self.result.error(prop_where, "usa 'prefab' o 'asset', no los dos")
            else:
                prefab = prefabs.get(prop.get("prefab"))
                if not isinstance(prefab, dict):
                    self.result.error(prop_where, f"no existe el prefab {prop.get('prefab')!r} en 'prefabs'")
                    continue
            if "animation" in prop:
                if asset is None:
                    self.result.error(prop_where, "'animation' solo se usa con modelos del usuario ('asset')")
                else:
                    self.asset_of(prop.get("animation"), "animation", prop_where)
            position = vec3(prop.get("position"))
            if position is None:
                self.result.error(prop_where, "'position' debe ser una lista de 3 números (centro de la caja)")
                continue
            default_size = prefab.get("size") if prefab is not None else asset.get("size")
            size = vec3(prop.get("size", default_size))
            if size is None or any(s <= 0 for s in size):
                if asset is not None:
                    self.result.error(prop_where, "un modelo del usuario necesita 'size' (en el prop o en su asset): la caja en la que el loader lo encaja y que mide el validador")
                else:
                    self.result.error(prop_where, "'size' debe ser una lista de 3 números mayores que 0")
                continue
            yaw = prop.get("yaw", 0)
            if not is_number(yaw):
                self.result.error(prop_where, "'yaw' debe ser un ángulo en grados")
                yaw = 0
            collide = prop.get("collide", False)
            if not isinstance(collide, bool):
                self.result.error(prop_where, "'collide' debe ser true o false")
                collide = False
            if prefab is not None:
                colors = prop.get("colors", {})
                if not isinstance(colors, dict):
                    self.result.error(prop_where, "'colors' debe ser un objeto ranura → color")
                    colors = {}
                slots = {**(prefab.get("colors") or {}), **colors}
                for part in prefab.get("parts", []):
                    if isinstance(part, dict):
                        reference = slots.get(part.get("color", "secondary"), part.get("color", "secondary"))
                        self.decoration_color(reference, f"{where}.props '{prop_id}'")
            center = [o + p for o, p in zip(origin, position)]
            items.append((f"prop '{prop_id}'", self.item_box(center, list(size), [0.0, float(yaw), 0.0]), collide, False, True))

        terrain = level_env.get("terrain", [])
        if not isinstance(terrain, list):
            self.result.error(where, "'terrain' debe ser una lista")
            terrain = []
        for index_fill, fill in enumerate(terrain):
            fill_where = f"{where}.terrain[{index_fill}]"
            if not isinstance(fill, dict):
                self.result.error(fill_where, "cada relleno debe ser un objeto")
                continue
            shape = fill.get("shape", "Block")
            material = fill.get("material")
            if shape not in TERRAIN_SHAPES:
                self.result.error(fill_where, f"'shape' debe ser uno de: {', '.join(sorted(TERRAIN_SHAPES))}")
                continue
            if material not in TERRAIN_MATERIALS:
                self.result.error(fill_where, f"material de terreno {material!r}: usa uno de {', '.join(sorted(TERRAIN_MATERIALS))}")
                continue
            position = vec3(fill.get("position"))
            if position is None:
                self.result.error(fill_where, "'position' debe ser una lista de 3 números")
                continue
            rotation = vec3(fill.get("rotation", [0, 0, 0])) or (0.0, 0.0, 0.0)
            center = [o + p for o, p in zip(origin, position)]
            if shape in {"Block", "Wedge"}:
                size = vec3(fill.get("size"))
                if size is None or any(s <= 0 for s in size):
                    self.result.error(fill_where, "'size' debe ser una lista de 3 números mayores que 0")
                    continue
                box = self.item_box(center, list(size), list(rotation))
            else:
                radius = fill.get("radius")
                height = fill.get("height", 0)
                if not is_number(radius) or radius <= 0 or (shape == "Cylinder" and (not is_number(height) or height <= 0)):
                    self.result.error(fill_where, "una esfera necesita 'radius' y un cilindro 'radius' y 'height' mayores que 0")
                    continue
                if shape == "Ball":
                    box = self.vl.Box(*center, radius, radius, radius)
                else:
                    box = self.item_box(center, [2 * radius, height, 2 * radius], list(rotation))
            if material != "Air":
                items.append((f"terreno {material} #{index_fill}", box, True, material == "Water", False))

        lights = level_env.get("lights", [])
        if not isinstance(lights, list):
            self.result.error(where, "'lights' debe ser una lista")
            lights = []
        for index_light, spec in enumerate(lights):
            light_where = f"{where}.lights[{index_light}]"
            if not isinstance(spec, dict) or vec3(spec.get("position")) is None:
                self.result.error(light_where, "cada luz necesita 'position'")
                continue
            self.light(spec, light_where)

        sounds = level_env.get("sounds", [])
        if not isinstance(sounds, list):
            self.result.error(where, "'sounds' debe ser una lista")
            sounds = []
        for index_sound, spec in enumerate(sounds):
            sound_where = f"{where}.sounds[{index_sound}]"
            if not isinstance(spec, dict):
                self.result.error(sound_where, "cada sonido debe ser un objeto")
                continue
            self.asset_of(spec.get("asset"), "sound", sound_where)
            if "position" in spec and vec3(spec["position"]) is None:
                self.result.error(sound_where, "'position' debe ser una lista de 3 números (o no ponerla: sonido de ambiente para todo el nivel)")
            volume = spec.get("volume", 0.5)
            if not is_number(volume) or not 0 <= volume <= 3:
                self.result.error(sound_where, "'volume' debe estar entre 0 y 3")
            if "range" in spec and (not is_number(spec["range"]) or spec["range"] <= 0):
                self.result.error(sound_where, "'range' debe ser un número mayor que 0")

        self.check_space(level, pieces, items, where)

    # Escena: presupuesto, terreno, caras superpuestas y superficies -------

    def check_scene(self, scene: es.Scene) -> None:
        by_level: dict[str, dict] = {}
        for level in es.SceneBuilder(self.env, self.theme_data, self.levels_data).levels():
            by_level[str(level.get("id"))] = {"id": str(level.get("id")), "pieces": 0, "dressingParts": 0, "props": 0,
                                              "propParts": 0, "terrain": 0, "lights": 0, "shadowLights": 0}
        prop_ids: dict[str, set] = defaultdict(set)
        dressing_counts: dict[str, int] = defaultdict(int)
        for solid in scene.solids:
            summary = by_level.get(solid.level)
            if summary is None:
                continue
            if solid.layer == "level":
                summary["pieces"] += 1
            elif solid.layer == "dressing":
                summary["dressingParts"] += 1
                dressing_counts[solid.source] += 1
            elif solid.layer in {"prop", "asset"}:
                summary["propParts"] += 1
                prop_ids[solid.level].add(solid.source)
            elif solid.layer == "terrain":
                summary["terrain"] += 1
        for level_id, ids in prop_ids.items():
            by_level[level_id]["props"] = len(ids)
        for light in scene.lights:
            if light.level in by_level:
                by_level[light.level]["lights"] += 1
                by_level[light.level]["shadowLights"] += int(light.shadows)
        for level_id, summary in by_level.items():
            env_levels = self.env.get("levels", {}) if isinstance(self.env.get("levels"), dict) else {}
            level_env = env_levels.get(level_id, {}) if isinstance(env_levels.get(level_id), dict) else {}
            fills = level_env.get("terrain", []) if isinstance(level_env.get("terrain"), list) else []
            summary["terrain"] = len(fills)
        self.result.levels = list(by_level.values())

        for source, count in dressing_counts.items():
            name = source.rsplit("/", 1)[-1]
            if name == "grid" and count > MAX_GRID_LINES:
                self.result.error(source, f"{count} líneas de baldosas superan {MAX_GRID_LINES}; sube 'spacing'")
            if name == "checker" and count > MAX_CHECKER_TILES:
                self.result.error(source, f"{count} baldosas superan {MAX_CHECKER_TILES}; sube 'spacing'")

        self.check_terrain_clearance(scene)
        self.check_zfighting(scene)

    def check_terrain_clearance(self, scene: es.Scene) -> None:
        pieces = [s for s in scene.solids if s.layer == "level" and s.transparency < 0.95]
        boxes = [(s, s.aabb()) for s in pieces]
        for fill in (s for s in scene.solids if s.layer == "terrain"):
            low, high = fill.aabb()
            grown = (tuple(v - VOXEL for v in low), tuple(v + VOXEL for v in high))
            close = [s.source for s, box in boxes if s.place == fill.place and boxes_overlap(grown, box)]
            if close:
                shown = ", ".join(f"'{name}'" for name in close[:3]) + (f" y {len(close) - 3} más" if len(close) > 3 else "")
                self.result.error(fill.source, f"el terreno se arma con vóxeles de 4 studs y redondea sus bordes: a menos de 4 studs de {shown} "
                                               "puede asomar a través de la pieza (se ve como manchas en el piso) o taparla. Deja 4 studs de "
                                               "separación con el borde en un múltiplo de 4 y tapa el hueco con el adorno 'base'")

    def check_zfighting(self, scene: es.Scene) -> None:
        faces: dict[tuple, list] = defaultdict(list)
        candidates = [s for s in scene.solids
                      if s.shape == "Block" and s.layer != "terrain" and s.transparency < 0.95 and s.axis_aligned()]
        boxes = [s.aabb() for s in candidates]
        for index, (low, high) in enumerate(boxes):
            for axis in range(3):
                for side, plane in ((-1, low[axis]), (1, high[axis])):
                    if axis == 1 and side == -1:
                        continue  # las caras de abajo casi nunca se ven
                    faces[(axis, side, round(plane / 0.01))].append((index, plane))
        found: dict[tuple, tuple] = {}
        for (axis, side, bucket), items in faces.items():
            neighbours = items + faces.get((axis, side, bucket + 1), [])
            for position, (first, plane_a) in enumerate(items):
                for second, plane_b in neighbours[position + 1:]:
                    if first == second or abs(plane_a - plane_b) > PLANE_TOLERANCE:
                        continue
                    a, b = candidates[first], candidates[second]
                    if a.place != b.place or a.source == b.source or (a.color == b.color and a.material == b.material):
                        continue
                    (low_a, high_a), (low_b, high_b) = boxes[first], boxes[second]
                    others = [i for i in range(3) if i != axis]
                    overlap = 1.0
                    for i in others:
                        overlap *= max(0.0, min(high_a[i], high_b[i]) - max(low_a[i], low_b[i]))
                    if overlap <= MIN_OVERLAP:
                        continue
                    region = [(max(low_a[i], low_b[i]), min(high_a[i], high_b[i])) for i in others]
                    same_place = [box if candidate.place == a.place else ((0, 0, 0), (0, 0, 0)) for candidate, box in zip(candidates, boxes)]
                    if self.face_hidden(same_place, (first, second), axis, side, plane_a, others, region):
                        continue
                    key = tuple(sorted((a.source, b.source)))
                    if key not in found:
                        found[key] = (a, b, axis, side, plane_a)
        per_level: dict[str, list] = defaultdict(list)
        for a, b, axis, side, plane in found.values():
            per_level[a.level].append((a, b, axis, side, plane))
        for level_id, pairs in per_level.items():
            for a, b, axis, side, plane in pairs[:MAX_ZFIGHT_MESSAGES]:
                face = f"de arriba (y = {plane:.2f})" if axis == 1 else f"lateral ({'XYZ'[axis].lower()} = {plane:.2f})"
                owner = ("son geometría del nivel: pídele al level designer que separe una de las dos al menos 0,05 studs"
                         if a.layer == "level" and b.layer == "level" else "separa la decoración al menos 0,05 studs o usa el mismo color y material")
                self.result.warn(f"levels.{level_id}", f"'{a.source}' y '{b.source}' tienen la cara {face} en el mismo plano: "
                                                       f"en Roblox se ve parpadeo o manchas (z-fighting); {owner}")
            if len(pairs) > MAX_ZFIGHT_MESSAGES:
                self.result.warn(f"levels.{level_id}", f"y {len(pairs) - MAX_ZFIGHT_MESSAGES} pares más de caras superpuestas")

    @staticmethod
    def face_hidden(boxes, skip, axis: int, side: int, plane: float, others, region) -> bool:
        """True si otra pieza opaca tapa toda la zona que comparten las dos caras (por ejemplo, la esquina de otro muro)."""
        for index, (low, high) in enumerate(boxes):
            if index in skip:
                continue
            in_front = (low[axis] <= plane + 0.001 and high[axis] >= plane + 0.01) if side > 0 else \
                       (high[axis] >= plane - 0.001 and low[axis] <= plane - 0.01)
            if in_front and all(low[i] <= start + 1e-6 and high[i] >= end - 1e-6 for i, (start, end) in zip(others, region)):
                return True
        return False

    def check_surfaces(self, level: dict, level_env: dict) -> None:
        defaults = self.levels_data.get("defaults", {}) if isinstance(self.levels_data.get("defaults"), dict) else {}
        flat = []
        for piece in level.get("pieces", []) if isinstance(level.get("pieces"), list) else []:
            if not isinstance(piece, dict):
                continue
            kind, size = piece.get("kind"), vec3(piece.get("size"))
            if size is None or kind not in es.WALKABLE | {"wall"} or piece.get("shape", "Block") != "Block":
                continue
            transparency = piece.get("transparency", 0)
            if is_number(transparency) and transparency >= 0.95:
                continue
            area = max(size[0], size[2]) * size[1] if kind == "wall" else size[0] * size[2]
            if area < LARGE_SURFACE:
                continue
            style = es.resolved_style(self.env, level_env, piece)
            material = self.theme.material(style["material"]) if "material" in style else piece.get("material", defaults.get("material", "SmoothPlastic"))
            dressing = style.get("dressing") if isinstance(style.get("dressing"), dict) else {}
            surface = {name for name in dressing if name in es.SURFACE_DRESSINGS and kind in es.DRESSINGS[name][0]}
            treated = material not in FLAT_MATERIALS or "texture" in style or "materialVariant" in style or surface
            if not treated:
                flat.append(str(piece.get("id")))
        if flat:
            shown = ", ".join(flat[:5]) + (f" y {len(flat) - 5} más" if len(flat) > 5 else "")
            self.result.warn(f"levels.{level.get('id')}", f"{len(flat)} superficies grandes de plástico liso sin tratar ({shown}): se ven como blockout. "
                                                         "Dales un material con textura, un adorno de superficie (border, grid o checker en pisos; "
                                                         "baseboard, cornice, pilasters o band en muros) o una textura del usuario")

    # Todo el archivo ------------------------------------------------------

    def run(self) -> Result:
        env = self.env
        if not isinstance(env, dict):
            self.result.error("Environment.json", "debe contener un objeto JSON")
            return self.result
        if env.get("schemaVersion") != SCHEMA_VERSION:
            self.result.error("schemaVersion", f"debe ser {SCHEMA_VERSION}")
        if not self.prepare():
            return self.result
        self.check_assets()

        lighting = env.get("lighting", {})
        if not isinstance(lighting, dict):
            self.result.error("lighting", "debe ser un objeto")
            lighting = {}
        preset = lighting.get("preset", "default")
        if preset not in self.theme.presets:
            self.result.error("lighting.preset", f"Theme.json no tiene el preset {preset!r}; pídelo al art director")
        by_place = lighting.get("places", {})
        if not isinstance(by_place, dict):
            self.result.error("lighting.places", "debe ser un objeto place → preset")
        else:
            for place, name in by_place.items():
                if name not in self.theme.presets:
                    self.result.error(f"lighting.places.{place}", f"Theme.json no tiene el preset {name!r}; pídelo al art director")
        clouds = lighting.get("clouds")
        if clouds is not None:
            if not isinstance(clouds, dict):
                self.result.error("lighting.clouds", "debe ser un objeto")
            else:
                for key in ("cover", "density"):
                    if key in clouds and (not is_number(clouds[key]) or not 0 <= clouds[key] <= 1):
                        self.result.error("lighting.clouds", f"'{key}' debe estar entre 0 y 1")
                if "color" in clouds:
                    self.color(clouds["color"], "lighting.clouds")

        terrain_colors = env.get("terrainColors", {})
        if not isinstance(terrain_colors, dict):
            self.result.error("terrainColors", "debe ser un objeto material → color")
        else:
            for material, reference in terrain_colors.items():
                if material not in TERRAIN_MATERIALS or material in {"Water", "Air"}:
                    self.result.error("terrainColors", f"{material!r} no es un material de terreno con color propio")
                else:
                    self.color(reference, f"terrainColors.{material}")

        pieces = env.get("pieces", {})
        if not isinstance(pieces, dict):
            self.result.error("pieces", "debe ser un objeto tipo → estilo")
        else:
            for kind, style in pieces.items():
                if kind not in self.vl.KINDS and kind != "moving":
                    self.result.error("pieces", f"tipo de pieza desconocido {kind!r}")
                else:
                    self.style(kind, style, f"pieces.{kind}")

        prefabs = env.get("prefabs", {})
        if not isinstance(prefabs, dict):
            self.result.error("prefabs", "debe ser un objeto nombre → prefab")
            prefabs = {}
        for name, prefab in prefabs.items():
            self.prefab(name, prefab, f"prefabs.{name}")

        raw_levels = self.levels_data.get("levels", []) if isinstance(self.levels_data.get("levels"), list) else []
        levels_by_id = {level.get("id"): (level, index) for index, level in enumerate(raw_levels) if isinstance(level, dict)}
        env_levels = env.get("levels", {})
        if not isinstance(env_levels, dict):
            self.result.error("levels", "debe ser un objeto id de nivel → pase de arte")
            env_levels = {}
        for level_id, (level, index) in levels_by_id.items():
            level_env = env_levels.get(level_id, {})
            if level_id in env_levels:
                self.check_level(level_id, level_env, level, index, prefabs)
            self.check_surfaces(level, level_env if isinstance(level_env, dict) else {})
        for level_id in env_levels:
            if level_id not in levels_by_id:
                self.result.error(f"levels.{level_id}", "no existe ese nivel en Levels.json")

        scene = es.SceneBuilder(env, self.theme_data, self.levels_data).build()
        self.check_scene(scene)

        budget = dict(DEFAULT_BUDGET)
        custom = env.get("budget", {})
        if not isinstance(custom, dict):
            self.result.error("budget", "debe ser un objeto")
        else:
            for key, value in custom.items():
                if key not in DEFAULT_BUDGET:
                    self.result.warn("budget", f"campo desconocido {key!r}")
                elif not isinstance(value, int) or isinstance(value, bool) or value < 0:
                    self.result.error("budget", f"'{key}' debe ser un entero positivo")
                else:
                    budget[key] = value
        parts = sum(s["pieces"] + s["dressingParts"] + s["propParts"] for s in self.result.levels)
        lights = sum(s["lights"] for s in self.result.levels)
        shadow_lights = sum(s["shadowLights"] for s in self.result.levels)
        self.result.totals = {"parts": parts, "lights": lights, "shadowLights": shadow_lights, "budget": budget}
        if parts > budget["maxParts"]:
            self.result.warn("budget", f"{parts} piezas entre niveles y decoración superan el presupuesto de {budget['maxParts']}")
        if lights > budget["maxLights"]:
            self.result.warn("budget", f"{lights} luces superan el presupuesto de {budget['maxLights']}; usa menos luces o de menor alcance")
        if shadow_lights > budget["maxShadowLights"]:
            self.result.warn("budget", f"{shadow_lights} luces con sombra superan el presupuesto de {budget['maxShadowLights']}; son las más caras en celulares")
        return self.result


def siblings():
    levels_module = load_sibling(LEVEL_VALIDATOR, "factory_validate_levels")
    art_module = load_sibling(ART_CHECKER, "factory_check_art")
    return levels_module, art_module


def make_checker(environment, theme: dict, levels_data: dict, game: Path | None = None) -> Checker | None:
    levels_module, art_module = siblings()
    if levels_module is None or art_module is None:
        return None
    return Checker(environment, theme, levels_data, levels_module, art_module, game)


def validate(environment, theme: dict, levels_data: dict, game: Path | None = None) -> Result:
    checker = make_checker(environment, theme, levels_data, game)
    if checker is None:
        result = Result()
        result.error("skills", "check_environment.py necesita roblox-level-designer y roblox-art-director instalados al lado")
        return result
    return checker.run()


def inline_json(item) -> str:
    if isinstance(item, dict):
        if not item:
            return "{}"
        return "{ " + ", ".join(f"{json.dumps(k, ensure_ascii=False)}: {inline_json(v)}" for k, v in item.items()) + " }"
    if isinstance(item, list):
        return "[" + ", ".join(inline_json(v) for v in item) + "]"
    return json.dumps(item, ensure_ascii=False)


def has_object_list(item) -> bool:
    if isinstance(item, list):
        return any(isinstance(v, dict) for v in item) or any(has_object_list(v) for v in item)
    if isinstance(item, dict):
        return any(has_object_list(v) for v in item.values())
    return False


def format_json(value, indent: int = 0) -> str:
    """JSON legible y estable: valores cortos en una línea y un objeto de lista por línea."""
    compact = inline_json(value)
    if not isinstance(value, (dict, list)) or (indent > 0 and len(compact) + indent <= 110 and not has_object_list(value)):
        return compact
    pad = " " * (indent + 2)
    if isinstance(value, list):
        if not value:
            return "[]"
        lines = [inline_json(v) if isinstance(v, dict) and not has_object_list(v) else format_json(v, indent + 2) for v in value]
        return "[\n" + ",\n".join(pad + line for line in lines) + "\n" + " " * indent + "]"
    if not value:
        return "{}"
    lines = [f"{json.dumps(k, ensure_ascii=False)}: {format_json(v, indent + 2)}" for k, v in value.items()]
    return "{\n" + ",\n".join(pad + line for line in lines) + "\n" + " " * indent + "}"


def read_json(path: Path, result: Result):
    if not path.exists():
        result.error(path.name, "no existe")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        result.error(path.name, f"JSON inválido: {exc}")
        return None


def ids_outside_assets(value, path: tuple = ()) -> list[str]:
    """Rutas con IDs de assets fuera de la sección 'assets'."""
    if path[:1] == ("assets",):
        return []
    if isinstance(value, dict):
        return [hit for key, item in value.items() for hit in ids_outside_assets(item, path + (str(key),))]
    if isinstance(value, list):
        return [hit for index, item in enumerate(value) for hit in ids_outside_assets(item, path + (str(index),))]
    if isinstance(value, str) and ASSET_RE.search(value):
        return [".".join(path)]
    return []


def project_path(project: dict, *names: str) -> str | None:
    node = project.get("tree", {}) if isinstance(project, dict) else {}
    for name in names:
        node = node.get(name) if isinstance(node, dict) else None
    return node.get("$path") if isinstance(node, dict) else None


def check_game_assets(game: Path, environment: dict, result: Result) -> None:
    assets = environment.get("assets", {}) if isinstance(environment.get("assets"), dict) else {}
    gdd = game / "GDD.md"
    gdd_text = gdd.read_text(encoding="utf-8") if gdd.exists() else ""
    folders: dict[str, set] = defaultdict(set)
    for name, asset in assets.items():
        if not isinstance(asset, dict):
            continue
        match = ASSET_ID_RE.match(asset.get("id", "")) if isinstance(asset.get("id"), str) else None
        if match and match.group(1) not in gdd_text:
            result.error(f"assets.{name}", f"el ID {match.group(1)} no está en la sección Assets y servicios del GDD; agrégalo con su origen y licencia")
        file = asset.get("file")
        if isinstance(file, str):
            folders[asset.get("kind")].add(Path(file).parent.as_posix())
            if Path(file).name not in gdd_text:
                result.warn(f"assets.{name}", f"{Path(file).name} no aparece en la sección Assets y servicios del GDD")
    try:
        project = json.loads((game / "default.project.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        project = {}
    for kind, service, child, label in (("model", "ServerStorage", "EnvironmentAssets", "ServerStorage.EnvironmentAssets"),
                                         ("materialVariant", "MaterialService", None, "MaterialService")):
        wanted = folders.get(kind)
        if not wanted:
            continue
        if len(wanted) > 1:
            result.error("assets", f"los archivos {kind} están en varias carpetas ({', '.join(sorted(wanted))}); ponlos todos en una")
            continue
        folder = next(iter(wanted))
        mapped = project_path(project, service, child) if child else project_path(project, service)
        if mapped is None or Path(mapped).as_posix().rstrip("/") != folder:
            result.error("default.project.json", f"falta mapear {folder} a {label} (\"$path\": \"{folder}\"); es tarea del builder")


def check_game(game: Path) -> Result:
    shared = game / "src" / "shared"
    result = Result()
    environment = read_json(shared / "Environment.json", result)
    theme = read_json(shared / "Theme.json", result)
    levels_data = read_json(shared / "Levels.json", result)
    if result.errors:
        for line in list(result.errors):
            if "Theme.json" in line:
                result.errors.append("Theme.json: el pase de arte necesita la dirección de arte (roblox-art-director)")
            elif "Levels.json" in line:
                result.errors.append("Levels.json: el pase de arte necesita los niveles como datos (roblox-level-designer)")
        return result
    result = validate(environment, theme if isinstance(theme, dict) else {}, levels_data if isinstance(levels_data, dict) else {}, game)
    if isinstance(environment, dict):
        for path in ids_outside_assets(environment):
            result.error(f"Environment.json {path}", "tiene un ID de asset fuera de 'assets': declara cada asset del usuario en 'assets' con su origen y licencia y úsalo por nombre")
        check_game_assets(game, environment, result)
    doc = game / "design" / "ENVIRONMENT.md"
    if not doc.exists():
        result.error("design/ENVIRONMENT.md", "no existe")
    elif isinstance(environment, dict) and isinstance(environment.get("levels"), dict):
        text = doc.read_text(encoding="utf-8")
        for level_id in environment["levels"]:
            if level_id not in text:
                result.warn("design/ENVIRONMENT.md", f"no describe el nivel {level_id!r}")
    return result


def format_result(game: Path, result: Result) -> str:
    lines = [f"Pase de arte: {game}"]
    for level in result.levels:
        lines.append(f"  {level['id']}: {level['pieces']} piezas, {level['dressingParts']} de adornos, "
                     f"{level['props']} props ({level['propParts']} piezas), {level['terrain']} rellenos de terreno, "
                     f"{level['lights']} luces")
    if result.totals:
        budget = result.totals["budget"]
        lines.append(f"  Total: {result.totals['parts']}/{budget['maxParts']} piezas, {result.totals['lights']}/{budget['maxLights']} luces, "
                     f"{result.totals['shadowLights']}/{budget['maxShadowLights']} con sombra")
    lines += [f"ERROR {line}" for line in result.errors]
    lines += [f"WARN  {line}" for line in result.warnings]
    lines += [f"NOTA  {line}" for line in result.notes]
    lines.append(f"Resultado: {len(result.errors)} errores, {len(result.warnings)} advertencias")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Revisa el pase de arte de un juego de la fábrica.")
    parser.add_argument("game", type=Path, help="carpeta del juego (la que contiene GDD.md)")
    parser.add_argument("--json", action="store_true", help="imprime el resultado como JSON")
    args = parser.parse_args(argv)
    if not args.game.is_dir():
        print(f"ERROR no existe la carpeta {args.game}")
        return 2
    result = check_game(args.game.resolve())
    if args.json:
        print(json.dumps({"errors": result.errors, "warnings": result.warnings, "notes": result.notes, "levels": result.levels,
                          "totals": result.totals}, ensure_ascii=False, indent=2))
    else:
        print(format_result(args.game, result))
    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
