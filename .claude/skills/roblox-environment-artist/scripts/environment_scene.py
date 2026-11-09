"""Geometría del pase de arte, sin ejecutar Roblox.

Arma las mismas piezas que crea EnvironmentLoader en el juego: las piezas del nivel
con su estilo final, sus adornos, los props, el terreno y las luces. La usan
check_environment.py (presupuesto, terreno, caras superpuestas y superficies sin
tratar) y preview_environment.py (imágenes de vista previa).

Si cambia la geometría de un adorno en EnvironmentLoader.luau, cambia aquí también:
las pruebas comparan los conteos de piezas con los del ejemplo.
"""
from __future__ import annotations

import colorsys
import math
from dataclasses import dataclass, field

IDENTITY = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
LOCKED = {"hazard": "hazard", "checkpoint": "interactive", "goal": "goal", "collectible": "reward"}
WALKABLE = {"platform", "spawn", "checkpoint", "goal"}
DEFAULT_COLOR = "#A3A2A5"
DEFAULT_PILLAR_DEPTH = 20.0
MAX_VARIATION = 0.15
EDGE = 0.02  # los adornos de superficie se separan de los bordes para no compartir plano con otras piezas

# Adorno → tipos de pieza que lo admiten y campos propios.
DRESSINGS = {
    "trim": ({"platform", "spawn", "checkpoint", "goal", "wall", "prop"}, {"width"}),
    "rock": ({"platform", "spawn", "checkpoint", "goal", "wall", "prop"}, set()),
    "pillar": ({"platform", "spawn", "checkpoint", "goal", "wall", "prop"}, set()),
    "base": ({"platform", "spawn", "checkpoint", "goal", "wall", "prop"}, {"depth"}),
    "border": (WALKABLE, {"width", "inset"}),
    "grid": (WALKABLE, {"spacing", "width"}),
    "checker": (WALKABLE, {"spacing"}),
    "baseboard": ({"wall", "prop"}, {"height"}),
    "cornice": ({"wall", "prop"}, {"height"}),
    "band": ({"wall", "prop"}, {"height", "at"}),
    "pilasters": ({"wall", "prop"}, {"width", "spacing"}),
}
BLOCK_ONLY = {"trim", "border", "grid", "checker", "base", "baseboard", "cornice", "band", "pilasters"}
SURFACE_DRESSINGS = {"border", "grid", "checker", "baseboard", "cornice", "band", "pilasters"}

# Colores aproximados del terreno de Roblox por defecto, solo para la vista previa.
TERRAIN_COLORS = {
    "Asphalt": "#737B6B", "Basalt": "#1E1E25", "Brick": "#8A563E", "Cobblestone": "#847B5A",
    "Concrete": "#7F6640", "CrackedLava": "#E89C4A", "Glacier": "#65B0EA", "Grass": "#6A7F3F",
    "Ground": "#665C3B", "Ice": "#81C2E0", "LeafyGrass": "#73844A", "Limestone": "#CEAD94",
    "Mud": "#3A2E24", "Pavement": "#94948C", "Rock": "#666C6F", "Salt": "#C6BDB5",
    "Sand": "#8F7E5F", "Sandstone": "#895A47", "Slate": "#3F7F6B", "Snow": "#C3C7DA",
    "Water": "#0C545C", "WoodPlanks": "#8B6D4F",
}


def matmul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def apply(m, v):
    return (m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
            m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
            m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2])


def angles(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0):
    """Como CFrame.Angles(rx, ry, rz) en grados: R = Rx * Ry * Rz."""
    ax, ay, az = (math.radians(v) for v in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    return matmul(((1, 0, 0), (0, cx, -sx), (0, sx, cx)), matmul(((cy, 0, sy), (0, 1, 0), (-sy, 0, cy)), ((cz, -sz, 0), (sz, cz, 0), (0, 0, 1))))


@dataclass(frozen=True)
class Frame:
    rotation: tuple = IDENTITY
    position: tuple = (0.0, 0.0, 0.0)

    def __mul__(self, other: "Frame") -> "Frame":
        moved = apply(self.rotation, other.position)
        return Frame(matmul(self.rotation, other.rotation), tuple(p + m for p, m in zip(self.position, moved)))

    def point(self, local) -> tuple:
        moved = apply(self.rotation, local)
        return tuple(p + m for p, m in zip(self.position, moved))


def translate(x: float, y: float, z: float) -> Frame:
    return Frame(IDENTITY, (float(x), float(y), float(z)))


def rotate(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> Frame:
    return Frame(angles(rx, ry, rz), (0.0, 0.0, 0.0))


@dataclass
class Solid:
    """Una pieza del mundo. shape: Block, Wedge, Ball o Cylinder (cilindro sobre su eje X, como en Roblox)."""
    shape: str
    frame: Frame
    size: tuple
    color: str
    material: str
    layer: str  # level, dressing, prop, asset o terrain
    source: str
    level: str
    kind: str = ""
    transparency: float = 0.0
    collide: bool = False
    place: str = ""  # place del nivel en juegos con varios places; "" es el de inicio

    def aabb(self) -> tuple[tuple, tuple]:
        half = [s / 2 for s in self.size]
        rot = self.frame.rotation
        extent = [sum(abs(rot[i][j]) * half[j] for j in range(3)) for i in range(3)]
        center = self.frame.position
        return (tuple(c - e for c, e in zip(center, extent)), tuple(c + e for c, e in zip(center, extent)))

    def axis_aligned(self) -> bool:
        return all(min(abs(v), abs(abs(v) - 1)) < 1e-6 for row in self.frame.rotation for v in row)


@dataclass
class Light:
    position: tuple
    color: str
    range: float
    brightness: float
    shadows: bool
    level: str
    source: str


@dataclass
class Scene:
    solids: list[Solid] = field(default_factory=list)
    lights: list[Light] = field(default_factory=list)


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value == value and abs(value) != float("inf")


def vec3(value):
    if isinstance(value, list) and len(value) == 3 and all(is_number(v) for v in value):
        return float(value[0]), float(value[1]), float(value[2])
    return None


class Palette:
    """Resuelve referencias del tema: rol ("hazard"), nombre de la paleta ("lava") o hexadecimal."""

    def __init__(self, theme: dict):
        theme = theme if isinstance(theme, dict) else {}
        self.palette = theme.get("palette", {}) if isinstance(theme.get("palette"), dict) else {}
        self.roles = theme.get("roles", {}) if isinstance(theme.get("roles"), dict) else {}
        self.materials = theme.get("materials", {}) if isinstance(theme.get("materials"), dict) else {}
        lighting = theme.get("lighting", {}) if isinstance(theme.get("lighting"), dict) else {}
        self.presets = lighting.get("presets", {}) if isinstance(lighting.get("presets"), dict) else {}

    def hex(self, reference) -> str | None:
        if not isinstance(reference, str):
            return None
        if reference.startswith("#") and len(reference) == 7:
            return reference.upper()
        swatch = self.roles.get(reference, reference)
        value = self.palette.get(swatch)
        return value.upper() if isinstance(value, str) else None

    def role_hex(self, role: str) -> str | None:
        return self.hex(role) if role in self.roles else None

    def material(self, reference, fallback: str = "SmoothPlastic") -> str:
        if isinstance(reference, str) and reference in self.materials and isinstance(self.materials[reference], str):
            return self.materials[reference]
        return reference if isinstance(reference, str) else fallback


def hash_unit(text: str) -> float:
    """El mismo número estable entre -1 y 1 que usa EnvironmentLoader para variar el brillo."""
    value = 7
    for byte in text.encode("utf-8"):
        value = (value * 31 + byte) % 1000003
    return (value % 2001) / 1000 - 1


def vary(hex_color: str, amount: float, key: str) -> str:
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    v = min(max(v * (1 + amount * hash_unit(key)), 0.0), 1.0)
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return "#" + "".join(f"{round(c * 255):02X}" for c in (r, g, b))


def resolved_style(environment: dict, level_env: dict, piece: dict) -> dict:
    """Estilo final de una pieza: tipo global → tipo del nivel → moving → pieza."""
    style: dict = {}
    global_pieces = environment.get("pieces", {}) if isinstance(environment.get("pieces"), dict) else {}
    level_pieces = level_env.get("pieces", {}) if isinstance(level_env.get("pieces"), dict) else {}
    kind = piece.get("kind")
    for source in (global_pieces.get(kind), level_pieces.get(kind)):
        if isinstance(source, dict):
            style.update(source)
    if piece.get("motion") is not None and kind != "hazard":
        for source in (global_pieces.get("moving"), level_pieces.get("moving")):
            if isinstance(source, dict):
                style.update(source)
    overrides = level_env.get("overrides", {}) if isinstance(level_env.get("overrides"), dict) else {}
    if isinstance(overrides.get(piece.get("id")), dict):
        style.update(overrides[piece["id"]])
    return style


def dressing_spec(value) -> dict:
    return value if isinstance(value, dict) else {"color": value}


def number(spec: dict, key: str, default: float) -> float:
    value = spec.get(key)
    return float(value) if is_number(value) and value > 0 else default


def wall_faces(size_x: float, size_z: float):
    """Caras laterales a adornar: (eje normal, signo, largo, medio espesor, extender esquinas)."""
    if size_x >= size_z * 2:
        return [("z", 1, size_x, size_z / 2, False), ("z", -1, size_x, size_z / 2, False)]
    if size_z >= size_x * 2:
        return [("x", 1, size_z, size_x / 2, False), ("x", -1, size_z, size_x / 2, False)]
    return [("x", 1, size_z, size_x / 2, True), ("x", -1, size_z, size_x / 2, True),
            ("z", 1, size_x, size_z / 2, False), ("z", -1, size_x, size_z / 2, False)]


def face_box(axis: str, sign: int, half: float, protrude: float, along: float, y: float, length: float, height: float):
    """Centro y tamaño locales de una tira pegada a una cara lateral."""
    offset = sign * (half + protrude / 2)
    if axis == "z":
        return (along, y, offset), (length, height, protrude)
    return (offset, y, along), (protrude, height, length)


def dressing_parts(name: str, value, size: tuple, dressings: dict) -> list[tuple[tuple, tuple, tuple]]:
    """Piezas locales de un adorno de bloque: (centro, tamaño, giro en grados)."""
    spec = dressing_spec(value)
    x, y, z = size
    top, bottom = y / 2, -y / 2
    parts: list[tuple[tuple, tuple, tuple]] = []
    if name == "trim":
        width = number(spec, "width", min(max(min(x, z) * 0.08, 0.2), 0.5))
        height = 0.1
        level = top + height / 2
        parts += [((0, level, z / 2 - EDGE - width / 2), (x - 2 * EDGE, height, width), (0, 0, 0)),
                  ((0, level, -z / 2 + EDGE + width / 2), (x - 2 * EDGE, height, width), (0, 0, 0)),
                  ((x / 2 - EDGE - width / 2, level, 0), (width, height, z - 2 * EDGE - 2 * width), (0, 0, 0)),
                  ((-x / 2 + EDGE + width / 2, level, 0), (width, height, z - 2 * EDGE - 2 * width), (0, 0, 0))]
    elif name == "border":
        inset = max(min(number(spec, "inset", 2.0), min(x, z) / 4), EDGE)
        width = number(spec, "width", min(max(min(x, z) * 0.03, 0.4), 1.5))
        height = 0.08
        level = top + height / 2
        ax, az = x / 2 - inset, z / 2 - inset
        if 2 * az - 2 * width > 0 and 2 * ax > 0:
            parts += [((0, level, az - width / 2), (2 * ax, height, width), (0, 0, 0)),
                      ((0, level, -az + width / 2), (2 * ax, height, width), (0, 0, 0)),
                      ((ax - width / 2, level, 0), (width, height, 2 * az - 2 * width), (0, 0, 0)),
                      ((-ax + width / 2, level, 0), (width, height, 2 * az - 2 * width), (0, 0, 0))]
    elif name == "grid":
        spacing = max(number(spec, "spacing", 8.0), 2.0)
        width = number(spec, "width", 0.15)
        height = 0.05
        level = top + height / 2
        for k in range(1, max(0, math.ceil(x / spacing - 1e-9))):
            parts.append(((-x / 2 + k * spacing, level, 0), (width, height, z - 2 * EDGE), (0, 0, 0)))
        for k in range(1, max(0, math.ceil(z / spacing - 1e-9))):
            parts.append(((0, level, -z / 2 + k * spacing), (x - 2 * EDGE, height, width), (0, 0, 0)))
    elif name == "checker":
        spacing = max(number(spec, "spacing", 8.0), 2.0)
        count_x, count_z = max(1, math.floor(x / spacing)), max(1, math.floor(z / spacing))
        tile_x, tile_z = x / count_x, z / count_z
        height = 0.04
        for i in range(count_x):
            for j in range(count_z):
                if (i + j) % 2 == 0:
                    parts.append(((-x / 2 + tile_x * (i + 0.5), top + height / 2, -z / 2 + tile_z * (j + 0.5)),
                                  (tile_x - 2 * EDGE, height, tile_z - 2 * EDGE), (0, 0, 0)))
    elif name == "base":
        depth = number(spec, "depth", 4.0)
        parts.append(((0, bottom - depth / 2, 0), (max(x - 0.1, 0.05), depth, max(z - 0.1, 0.05)), (0, 0, 0)))
    elif name == "rock":
        height = min(max(min(x, z) * 0.5, 1.0), 6.0)
        parts += [((0, bottom - height / 2, 0), (x * 0.85, height, z * 0.85), (0, 0, 0)),
                  ((0, bottom - height * 1.4, 0), (x * 0.55, height * 0.8, z * 0.55), (0, 15, 0))]
    elif name in {"baseboard", "cornice", "band"}:
        protrude = {"baseboard": 0.2, "cornice": 0.3, "band": 0.1}[name]
        if name == "baseboard":
            height = number(spec, "height", min(max(y * 0.06, 0.4), 1.2))
            level = bottom + height / 2
        elif name == "cornice":
            height = number(spec, "height", 0.6)
            level = top - EDGE - height / 2
        else:
            height = number(spec, "height", 0.5)
            at = spec.get("at", 0.62)
            level = bottom + y * (float(at) if is_number(at) and 0 < at < 1 else 0.62)
        for axis, sign, length, half, extend in wall_faces(x, z):
            center, box = face_box(axis, sign, half, protrude, 0.0, level, length + 2 * protrude if extend else length - 2 * EDGE, height)
            parts.append((center, box, (0, 0, 0)))
    elif name == "pilasters":
        width = number(spec, "width", 1.2)
        spacing = number(spec, "spacing", 12.0)
        protrude = 0.25
        cornice = dressings.get("cornice")
        cap = number(dressing_spec(cornice), "height", 0.6) if cornice is not None else 0.05
        low, high = bottom + 0.02, top - cap
        if high > low:
            for axis, sign, length, half, _extend in wall_faces(x, z):
                if length <= 2 * width + 0.1:
                    spots = [0.0]
                else:
                    count = max(2, math.floor((length - width - 0.1) / spacing) + 1)
                    first, last = -length / 2 + width / 2 + 0.05, length / 2 - width / 2 - 0.05
                    spots = [first + (last - first) * k / (count - 1) for k in range(count)]
                for along in spots:
                    center, box = face_box(axis, sign, half, protrude, along, (low + high) / 2, width, high - low)
                    parts.append((center, box, (0, 0, 0)))
    return parts


class SceneBuilder:
    """Arma la escena de uno o todos los niveles con el estilo de Environment.json."""

    def __init__(self, environment: dict, theme: dict, levels_data: dict):
        self.env = environment if isinstance(environment, dict) else {}
        self.palette = Palette(theme)
        self.levels_data = levels_data if isinstance(levels_data, dict) else {}
        defaults = self.levels_data.get("defaults", {}) if isinstance(self.levels_data.get("defaults"), dict) else {}
        self.default_color = defaults.get("color", DEFAULT_COLOR) if isinstance(defaults.get("color"), str) else DEFAULT_COLOR
        if not self.default_color.startswith("#"):
            self.default_color = "#" + self.default_color
        self.default_material = defaults.get("material", "SmoothPlastic")
        self.prefabs = self.env.get("prefabs", {}) if isinstance(self.env.get("prefabs"), dict) else {}
        self.assets = self.env.get("assets", {}) if isinstance(self.env.get("assets"), dict) else {}

    def color(self, reference, fallback: str = DEFAULT_COLOR) -> str:
        return self.palette.hex(reference) or fallback

    def levels(self):
        raw = self.levels_data.get("levels", [])
        return [level for level in raw if isinstance(level, dict)] if isinstance(raw, list) else []

    def level_env(self, level_id: str) -> dict:
        levels = self.env.get("levels", {})
        value = levels.get(level_id) if isinstance(levels, dict) else None
        return value if isinstance(value, dict) else {}

    def build(self, only_level: str | None = None) -> Scene:
        scene = Scene()
        for level in self.levels():
            level_id = str(level.get("id"))
            if only_level is not None and level_id != only_level:
                continue
            self.build_level(level, scene)
        return scene

    def piece_frame(self, origin, piece: dict) -> Frame | None:
        position = vec3(piece.get("position"))
        if position is None:
            return None
        rotation = vec3(piece.get("rotation")) or (0.0, 0.0, 0.0)
        return translate(*(o + p for o, p in zip(origin, position))) * rotate(*rotation)

    def place_of(self, level_id: str) -> str:
        level = next((item for item in self.levels() if str(item.get("id")) == level_id), {})
        return level.get("place") if isinstance(level.get("place"), str) else ""

    def build_level(self, level: dict, scene: Scene) -> None:
        level_id = str(level.get("id"))
        start = len(scene.solids)
        level_env = self.level_env(level_id)
        origin = vec3(level.get("origin", [0, 0, 0])) or (0.0, 0.0, 0.0)
        pieces = [p for p in level.get("pieces", []) if isinstance(p, dict)]
        hazards = []
        for piece in pieces:
            frame, size = self.piece_frame(origin, piece), vec3(piece.get("size"))
            if piece.get("kind") == "hazard" and frame is not None and size is not None:
                hazards.append((frame.position, size))
        for piece in pieces:
            self.add_piece(piece, level_id, origin, level_env, hazards, scene)
        for index, prop in enumerate(level_env.get("props", []) if isinstance(level_env.get("props"), list) else []):
            if isinstance(prop, dict):
                self.add_prop(prop, level_id, origin, scene)
        for index, fill in enumerate(level_env.get("terrain", []) if isinstance(level_env.get("terrain"), list) else []):
            if isinstance(fill, dict):
                self.add_terrain(fill, index, level_id, origin, scene)
        for spec in level_env.get("lights", []) if isinstance(level_env.get("lights"), list) else []:
            position = vec3(spec.get("position")) if isinstance(spec, dict) else None
            if position is not None:
                scene.lights.append(Light(tuple(o + p for o, p in zip(origin, position)), self.color(spec.get("color", "text"), "#FFFFFF"),
                                          float(spec.get("range", 12)) if is_number(spec.get("range")) else 12.0,
                                          float(spec.get("brightness", 1)) if is_number(spec.get("brightness")) else 1.0,
                                          spec.get("shadows") is True, level_id, f"{level_id}/{spec.get('id', 'luz')}"))
        place = level.get("place") if isinstance(level.get("place"), str) else ""
        for solid in scene.solids[start:]:
            solid.place = place

    def add_piece(self, piece: dict, level_id: str, origin, level_env: dict, hazards, scene: Scene) -> None:
        kind = piece.get("kind")
        frame, size = self.piece_frame(origin, piece), vec3(piece.get("size"))
        if frame is None or size is None or kind == "zone":
            return
        style = resolved_style(self.env, level_env, piece)
        material = self.palette.material(piece.get("material"), self.default_material) if piece.get("material") else self.default_material
        color = piece.get("color") if isinstance(piece.get("color"), str) else self.default_color
        color = color.upper() if color.startswith("#") else "#" + color.upper()
        if self.env:
            if "material" in style:
                material = self.palette.material(style["material"])
            if "materialVariant" in style:
                asset = self.assets.get(style["materialVariant"]) if isinstance(style["materialVariant"], str) else None
                if isinstance(asset, dict) and isinstance(asset.get("base"), str):
                    material = asset["base"]
            locked = LOCKED.get(kind)
            if locked:
                color = self.palette.role_hex(locked) or color
            elif "color" in style:
                color = self.color(style["color"], color)
                amount = style.get("variation")
                if is_number(amount) and amount > 0:
                    color = vary(color, min(amount, MAX_VARIATION), f"{level_id}/{piece.get('id')}")
        shape = "Block" if kind in {"spawn", "truss"} else piece.get("shape", "Block")
        transparency = piece.get("transparency", 0)
        transparency = float(transparency) if is_number(transparency) else 0.0
        collide = piece.get("collide", kind not in {"collectible", "zone"})
        scene.solids.append(Solid(shape, frame, size, color, material, "level", f"{level_id}/{piece.get('id')}", level_id,
                                  kind=kind or "", transparency=transparency, collide=collide is True))
        dressings = style.get("dressing")
        if not isinstance(dressings, dict) or piece.get("motion") is not None:
            return
        block = shape == "Block" and kind != "truss"
        for name, value in dressings.items():
            if name not in DRESSINGS or kind not in DRESSINGS[name][0] or (name in BLOCK_ONLY and not block):
                continue
            spec = dressing_spec(value)
            look_color = self.color(spec.get("color", "surfaceAlt"), "#C8C8C8")
            look_material = self.palette.material(spec["material"]) if "material" in spec else material
            source = f"{level_id}/{piece.get('id')}/{name}"
            if name == "pillar":
                bottom = frame.position[1] - size[1] / 2
                floor = None
                for position, hazard_size in hazards:
                    top = position[1] + hazard_size[1] / 2
                    if (abs(frame.position[0] - position[0]) <= hazard_size[0] / 2 and abs(frame.position[2] - position[2]) <= hazard_size[2] / 2
                            and top < bottom):
                        floor = top if floor is None else max(floor, top)
                depth = bottom - floor if floor is not None else DEFAULT_PILLAR_DEPTH
                if depth > 0.5:
                    width = max(min(size[0], size[2]) * 0.3, 0.6)
                    scene.solids.append(Solid("Block", translate(frame.position[0], bottom - depth / 2, frame.position[2]),
                                              (width, depth, width), look_color, look_material, "dressing", source, level_id))
                continue
            for center, box, rotation in dressing_parts(name, value, size, dressings):
                part_frame = frame * translate(*center) * rotate(*rotation)
                scene.solids.append(Solid("Block", part_frame, box, look_color, look_material, "dressing", source, level_id))

    def prop_box(self, prop: dict):
        prefab = self.prefabs.get(prop.get("prefab")) if isinstance(prop.get("prefab"), str) else None
        asset = self.assets.get(prop.get("asset")) if isinstance(prop.get("asset"), str) else None
        fallback = vec3(prefab.get("size")) if isinstance(prefab, dict) else (vec3(asset.get("size")) if isinstance(asset, dict) else None)
        return vec3(prop.get("size")) or fallback

    def add_prop(self, prop: dict, level_id: str, origin, scene: Scene) -> None:
        position, box = vec3(prop.get("position")), self.prop_box(prop)
        if position is None or box is None:
            return
        yaw = prop.get("yaw", 0)
        frame = translate(*(o + p for o, p in zip(origin, position))) * rotate(0, float(yaw) if is_number(yaw) else 0.0, 0)
        collide = prop.get("collide") is True
        source = f"{level_id}/prop:{prop.get('id')}"
        if isinstance(prop.get("asset"), str):
            scene.solids.append(Solid("Block", frame, box, "#C9C3D6", "SmoothPlastic", "asset", source, level_id, collide=collide))
            return
        prefab = self.prefabs.get(prop.get("prefab"))
        if not isinstance(prefab, dict):
            return
        slots = {**(prefab.get("colors") if isinstance(prefab.get("colors"), dict) else {}),
                 **(prop.get("colors") if isinstance(prop.get("colors"), dict) else {})}
        for part in prefab.get("parts", []) if isinstance(prefab.get("parts"), list) else []:
            if not isinstance(part, dict):
                continue
            center = vec3(part.get("center", [0, 0, 0])) or (0.0, 0.0, 0.0)
            fraction = vec3(part.get("size")) or (1.0, 1.0, 1.0)
            extent = [f * b for f, b in zip(fraction, box)]
            shape = part.get("shape", "Block")
            orientation = IDENTITY
            if shape == "Ball":
                diameter = min(extent)
                size = (diameter, diameter, diameter)
            elif shape == "Cylinder":
                axis = part.get("axis", "Y")
                if axis == "X":
                    size = (extent[0], min(extent[1], extent[2]), min(extent[1], extent[2]))
                elif axis == "Z":
                    size = (extent[2], min(extent[0], extent[1]), min(extent[0], extent[1]))
                    orientation = angles(0, 90, 0)
                else:
                    size = (extent[1], min(extent[0], extent[2]), min(extent[0], extent[2]))
                    orientation = angles(0, 0, 90)
            else:
                size = tuple(extent)
            rotation = vec3(part.get("rotation", [0, 0, 0])) or (0.0, 0.0, 0.0)
            part_frame = frame * translate(*(c * b for c, b in zip(center, box))) * rotate(*rotation) * Frame(orientation)
            reference = slots.get(part.get("color", "secondary"), part.get("color", "secondary"))
            transparency = part.get("transparency", 0)
            scene.solids.append(Solid(shape, part_frame, size, self.color(reference, "#C8C8C8"), self.palette.material(part.get("material", "SmoothPlastic")),
                                      "prop", source, level_id, transparency=float(transparency) if is_number(transparency) else 0.0, collide=collide))
            light = part.get("light")
            if isinstance(light, dict):
                light_ref = slots.get(light.get("color", "light"), light.get("color", "light"))
                scene.lights.append(Light(part_frame.position, self.color(light_ref, "#FFFFFF"),
                                          float(light.get("range", 12)) if is_number(light.get("range")) else 12.0,
                                          float(light.get("brightness", 1)) if is_number(light.get("brightness")) else 1.0,
                                          light.get("shadows") is True, level_id, source))

    def add_terrain(self, fill: dict, index: int, level_id: str, origin, scene: Scene) -> None:
        material = fill.get("material")
        position = vec3(fill.get("position"))
        if not isinstance(material, str) or position is None or material == "Air":
            return
        center = tuple(o + p for o, p in zip(origin, position))
        rotation = vec3(fill.get("rotation", [0, 0, 0])) or (0.0, 0.0, 0.0)
        colors = self.env.get("terrainColors", {}) if isinstance(self.env.get("terrainColors"), dict) else {}
        color = self.color(colors.get(material), TERRAIN_COLORS.get(material, "#6A7F3F"))
        shape = fill.get("shape", "Block")
        source = f"{level_id}/terreno#{index}:{material}"
        if shape in {"Block", "Wedge"}:
            size = vec3(fill.get("size"))
            if size is None:
                return
            scene.solids.append(Solid(shape, translate(*center) * rotate(*rotation), size, color, material, "terrain", source, level_id, collide=True))
        elif shape == "Ball":
            radius = fill.get("radius")
            if is_number(radius) and radius > 0:
                scene.solids.append(Solid("Ball", translate(*center), (2 * radius,) * 3, color, material, "terrain", source, level_id, collide=True))
        elif shape == "Cylinder":
            radius, height = fill.get("radius"), fill.get("height")
            if is_number(radius) and is_number(height) and radius > 0 and height > 0:
                # FillCylinder pone la altura sobre el eje Y del CFrame; el cilindro de la escena va sobre X.
                frame = translate(*center) * rotate(*rotation) * rotate(0, 0, 90)
                scene.solids.append(Solid("Cylinder", frame, (height, 2 * radius, 2 * radius), color, material, "terrain", source, level_id, collide=True))
