#!/usr/bin/env python3
"""Vista previa del pase de arte como imágenes PNG, sin abrir Roblox.

Uso:
    python preview_environment.py <carpeta-del-juego>
    python preview_environment.py <carpeta-del-juego> --level plaza --views iso,player --size 960x540 --out <carpeta>

Dibuja cada nivel con lo que arma EnvironmentLoader: piezas con su estilo final,
adornos, props, terreno y luces, con una luz de sol simple y niebla. Genera:
  - iso: vista general desde una esquina, en altura;
  - player: lo que ve el jugador al aparecer, desde la pieza de inicio.

Sirve para revisar composición, siluetas, densidad y color antes de abrir Studio:
mira las imágenes y corrige. No muestra texturas, el detalle de los materiales ni
sombras; los modelos del usuario aparecen como cajas lilas del tamaño declarado.
Por defecto las guarda en <juego>/build/preview/.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import zlib
from array import array
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import environment_scene as es  # noqa: E402

FOV = 50.0
NEAR = 0.3
EYE_HEIGHT = 4.5


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def normalize(v):
    length = math.sqrt(dot(v, v)) or 1.0
    return (v[0] / length, v[1] / length, v[2] / length)


def rgb(hex_color: str) -> tuple[float, float, float]:
    return tuple(int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))


def mesh(solid: es.Solid):
    """Polígonos de una pieza en coordenadas del mundo: lista de (vértices, normal)."""
    sx, sy, sz = (s / 2 for s in solid.size)
    point, rotation = solid.frame.point, solid.frame.rotation
    polygons = []

    def add(local_points, local_normal):
        polygons.append(([point(p) for p in local_points], normalize(es.apply(rotation, local_normal))))

    if solid.shape == "Wedge":
        add([(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz)], (0, -1, 0))
        add([(-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)], (0, 0, 1))
        add([(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, sz), (-sx, sy, sz)], (0, 2 * sz, -2 * sy))
        add([(sx, -sy, -sz), (sx, -sy, sz), (sx, sy, sz)], (1, 0, 0))
        add([(-sx, -sy, -sz), (-sx, -sy, sz), (-sx, sy, sz)], (-1, 0, 0))
    elif solid.shape == "Ball":
        rings, segments = 7, 12
        radius = sx
        for i in range(rings):
            a0, a1 = math.pi * i / rings - math.pi / 2, math.pi * (i + 1) / rings - math.pi / 2
            for j in range(segments):
                b0, b1 = 2 * math.pi * j / segments, 2 * math.pi * (j + 1) / segments
                quad = [(radius * math.cos(a) * math.cos(b), radius * math.sin(a), radius * math.cos(a) * math.sin(b))
                        for a, b in ((a0, b0), (a0, b1), (a1, b1), (a1, b0))]
                middle = ((a0 + a1) / 2, (b0 + b1) / 2)
                add(quad, (math.cos(middle[0]) * math.cos(middle[1]), math.sin(middle[0]), math.cos(middle[0]) * math.sin(middle[1])))
    elif solid.shape == "Cylinder":
        segments = 14
        radius = min(sy, sz)
        ring = [(radius * math.cos(2 * math.pi * j / segments), radius * math.sin(2 * math.pi * j / segments)) for j in range(segments)]
        for j in range(segments):
            (y0, z0), (y1, z1) = ring[j], ring[(j + 1) % segments]
            angle = 2 * math.pi * (j + 0.5) / segments
            add([(-sx, y0, z0), (sx, y0, z0), (sx, y1, z1), (-sx, y1, z1)], (0, math.cos(angle), math.sin(angle)))
        add([(sx, y, z) for y, z in ring], (1, 0, 0))
        add([(-sx, y, z) for y, z in ring], (-1, 0, 0))
    else:
        corners = {(ix, iy, iz): ((sx if ix else -sx), (sy if iy else -sy), (sz if iz else -sz))
                   for ix in (0, 1) for iy in (0, 1) for iz in (0, 1)}
        for axis in range(3):
            for side in (0, 1):
                face = [key for key in corners if key[axis] == side]
                others = [i for i in range(3) if i != axis]
                face.sort(key=lambda k: math.atan2(k[others[1]] - 0.5, k[others[0]] - 0.5))
                normal = [0, 0, 0]
                normal[axis] = 1 if side else -1
                add([corners[k] for k in face], tuple(normal))
    return polygons


class Camera:
    def __init__(self, eye, target, width: int, height: int):
        self.eye = eye
        self.forward = normalize(sub(target, eye))
        self.right = normalize(cross(self.forward, (0.0, 1.0, 0.0)))
        if dot(self.right, self.right) < 1e-9:
            self.right = (1.0, 0.0, 0.0)
        self.up = cross(self.right, self.forward)
        self.width, self.height = width, height
        self.focal = (height / 2) / math.tan(math.radians(FOV) / 2)

    def to_camera(self, p):
        d = sub(p, self.eye)
        return (dot(d, self.right), dot(d, self.up), dot(d, self.forward))

    def project(self, c):
        return (self.width / 2 + c[0] / c[2] * self.focal, self.height / 2 - c[1] / c[2] * self.focal, 1.0 / c[2])


def clip_near(points):
    """Recorta un polígono (en coordenadas de cámara) contra el plano cercano."""
    result = []
    for i, current in enumerate(points):
        previous = points[i - 1]
        inside_current, inside_previous = current[2] >= NEAR, previous[2] >= NEAR
        if inside_current != inside_previous:
            t = (NEAR - previous[2]) / (current[2] - previous[2])
            result.append(tuple(previous[k] + (current[k] - previous[k]) * t for k in range(3)))
        if inside_current:
            result.append(current)
    return result


class Canvas:
    def __init__(self, width: int, height: int, horizon, zenith):
        self.width, self.height = width, height
        self.depth = array("d", bytes(8 * width * height))
        self.pixels = bytearray(3 * width * height)
        for y in range(height):
            t = y / max(height - 1, 1)
            color = bytes(int(255 * (zenith[k] + (horizon[k] - zenith[k]) * min(t * 1.6, 1.0))) for k in range(3))
            self.pixels[y * width * 3:(y + 1) * width * 3] = color * width

    def triangle(self, a, b, c, color: bytes) -> None:
        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = sorted((a, b, c), key=lambda p: p[1])
        if y2 - y0 < 1e-9:
            return
        width, height = self.width, self.height
        depth, pixels = self.depth, self.pixels
        red, green, blue = color[0], color[1], color[2]
        start, end = max(0, math.ceil(y0 - 0.5)), min(height - 1, math.ceil(y2 - 0.5) - 1)
        for y in range(start, end + 1):
            py = y + 0.5
            t = (py - y0) / (y2 - y0)
            xa, za = x0 + (x2 - x0) * t, z0 + (z2 - z0) * t
            if py < y1:
                t2 = (py - y0) / (y1 - y0)
                xb, zb = x0 + (x1 - x0) * t2, z0 + (z1 - z0) * t2
            elif y2 - y1 > 1e-9:
                t2 = (py - y1) / (y2 - y1)
                xb, zb = x1 + (x2 - x1) * t2, z1 + (z2 - z1) * t2
            else:
                xb, zb = x1, z1
            if xa > xb:
                xa, xb, za, zb = xb, xa, zb, za
            first, last = max(0, math.ceil(xa - 0.5)), min(width - 1, math.ceil(xb - 0.5) - 1)
            if first > last:
                continue
            step = (zb - za) / (xb - xa) if xb - xa > 1e-9 else 0.0
            z = za + (first + 0.5 - xa) * step
            row = y * width
            for x in range(first, last + 1):
                index = row + x
                if z > depth[index]:
                    depth[index] = z
                    base = index * 3
                    pixels[base] = red
                    pixels[base + 1] = green
                    pixels[base + 2] = blue
                z += step

    def glow(self, sx: float, sy: float, inverse_depth: float, radius: float, color, strength: float) -> None:
        width, height = self.width, self.height
        cx, cy = int(sx), int(sy)
        if not (0 <= cx < width and 0 <= cy < height) or self.depth[cy * width + cx] > inverse_depth * 1.02:
            return
        r = int(radius)
        for y in range(max(0, cy - r), min(height, cy + r + 1)):
            for x in range(max(0, cx - r), min(width, cx + r + 1)):
                distance = math.hypot(x - sx, y - sy) / max(radius, 1)
                if distance >= 1:
                    continue
                amount = strength * (1 - distance) ** 2
                base = (y * width + x) * 3
                for k in range(3):
                    self.pixels[base + k] = min(255, int(self.pixels[base + k] + 255 * color[k] * amount))

    def png(self) -> bytes:
        width = self.width * 3
        raw = b"".join(b"\x00" + bytes(self.pixels[y * width:(y + 1) * width]) for y in range(self.height))

        def chunk(kind: bytes, data: bytes) -> bytes:
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

        header = struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0)
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")


def lighting(theme: dict, environment: dict) -> dict:
    """Sol, ambiente, cielo y niebla aproximados a partir del preset del tema."""
    palette = es.Palette(theme)
    preset_name = (environment.get("lighting") or {}).get("preset", "default") if isinstance(environment.get("lighting"), dict) else "default"
    preset = palette.presets.get(preset_name, {}) if isinstance(palette.presets.get(preset_name), dict) else {}
    clock = preset.get("clockTime", 14) if es.is_number(preset.get("clockTime")) else 14
    elevation = math.sin((clock - 6) / 12 * math.pi)
    night = elevation <= 0.05
    sun = normalize((-0.45, max(elevation, 0.25), -0.35))
    atmosphere = preset.get("atmosphere") if isinstance(preset.get("atmosphere"), dict) else {}
    horizon_hex = palette.hex(atmosphere.get("color")) or ("#2A2E45" if night else "#CFE3F5")
    horizon = rgb(horizon_hex)
    zenith = tuple(v * 0.35 for v in horizon) if night else (horizon[0] * 0.55, horizon[1] * 0.7, min(1.0, horizon[2] * 1.05))
    density = atmosphere.get("density", 0.25) if es.is_number(atmosphere.get("density")) else 0.25
    return {"sun": sun, "ambient": 0.38 if night else 0.5, "diffuse": 0.45 if night else 0.6,
            "horizon": horizon, "zenith": zenith, "fog": horizon, "fogDensity": 0.0015 + density * 0.004}


def frame_level(scene: es.Scene, level_id: str):
    solids = [s for s in scene.solids if s.level == level_id and s.layer != "terrain"]
    if not solids:
        return None
    lows, highs = zip(*(s.aabb() for s in solids))
    low = tuple(min(v[i] for v in lows) for i in range(3))
    high = tuple(max(v[i] for v in highs) for i in range(3))
    return low, high


def cameras(scene: es.Scene, level: dict, views: list[str], width: int, height: int) -> list[tuple[str, Camera]]:
    level_id = str(level.get("id"))
    bounds = frame_level(scene, level_id)
    if bounds is None:
        return []
    low, high = bounds
    center = tuple((a + b) / 2 for a, b in zip(low, high))
    radius = max(math.dist(low, high) / 2, 10.0)
    result = []
    for view in views:
        if view == "iso":
            direction = normalize((1.0, 0.85, 1.15))
            distance = radius / math.tan(math.radians(FOV) / 2) * 0.95
            eye = tuple(c + d * distance for c, d in zip(center, direction))
            result.append((view, Camera(eye, center, width, height)))
        elif view == "player":
            pieces = {s.source: s for s in scene.solids if s.level == level_id and s.layer == "level"}
            start = pieces.get(f"{level_id}/{level.get('start')}")
            if start is None:
                continue
            top = start.aabb()[1][1]
            eye = (start.frame.position[0], top + EYE_HEIGHT, start.frame.position[2])
            goal = next((s for s in pieces.values() if s.kind == "goal"), None)
            target = goal.frame.position if goal is not None and level.get("layout") == "linear" else center
            if math.dist((eye[0], eye[2]), (target[0], target[2])) < 1:
                target = (eye[0], eye[1], eye[2] - 10)
            result.append((view, Camera(eye, (target[0], eye[1] - 2, target[2]), width, height)))
    return result


def render(scene: es.Scene, camera: Camera, light: dict, place: str | None = None) -> Canvas:
    canvas = Canvas(camera.width, camera.height, light["horizon"], light["zenith"])
    for solid in scene.solids:
        if solid.transparency >= 0.95 or (place is not None and solid.place != place):
            continue
        base = rgb(solid.color)
        unlit = solid.material == "Neon"
        for points, normal in mesh(solid):
            center = tuple(sum(p[i] for p in points) / len(points) for i in range(3))
            if dot(normal, sub(camera.eye, center)) <= 0:
                continue
            camera_points = clip_near([camera.to_camera(p) for p in points])
            if len(camera_points) < 3:
                continue
            intensity = 1.0 if unlit else light["ambient"] + light["diffuse"] * max(0.0, dot(normal, light["sun"]))
            distance = max(camera.to_camera(center)[2], 0.0)
            fog = 0.0 if unlit else 1 - math.exp(-distance * light["fogDensity"])
            shade = bytes(int(255 * min(1.0, (base[k] * intensity) * (1 - fog) + light["fog"][k] * fog)) for k in range(3))
            projected = [camera.project(c) for c in camera_points]
            for i in range(1, len(projected) - 1):
                canvas.triangle(projected[0], projected[i], projected[i + 1], shade)
    places = {s.level: s.place for s in scene.solids}
    for lamp in scene.lights:
        if place is not None and places.get(lamp.level, "") != place:
            continue
        c = camera.to_camera(lamp.position)
        if c[2] <= NEAR:
            continue
        sx, sy, inverse = camera.project(c)
        radius = min(max(lamp.range * camera.focal / c[2] * 0.35, 3.0), 90.0)
        canvas.glow(sx, sy, inverse, radius, rgb(lamp.color), min(0.18 * lamp.brightness, 0.5))
    return canvas


def preview(game: Path, out: Path | None = None, level_filter: str | None = None, views: list[str] | None = None,
            size: tuple[int, int] = (960, 540)) -> list[Path]:
    shared = game / "src" / "shared"
    environment = json.loads((shared / "Environment.json").read_text(encoding="utf-8")) if (shared / "Environment.json").exists() else {}
    theme = json.loads((shared / "Theme.json").read_text(encoding="utf-8"))
    levels_data = json.loads((shared / "Levels.json").read_text(encoding="utf-8"))
    builder = es.SceneBuilder(environment, theme, levels_data)
    scene = builder.build()
    light = lighting(theme, environment)
    out = out or game / "build" / "preview"
    out.mkdir(parents=True, exist_ok=True)
    written = []
    for level in builder.levels():
        if level_filter and str(level.get("id")) != level_filter:
            continue
        place = level.get("place") if isinstance(level.get("place"), str) else ""
        for view, camera in cameras(scene, level, views or ["iso", "player"], *size):
            path = out / f"{level.get('id')}-{view}.png"
            path.write_bytes(render(scene, camera, light, place).png())
            written.append(path)
    return written


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Vista previa del pase de arte en imágenes PNG.")
    parser.add_argument("game", type=Path, help="carpeta del juego")
    parser.add_argument("--level", help="id del nivel (por defecto, todos)")
    parser.add_argument("--views", default="iso,player", help="vistas separadas por coma: iso, player")
    parser.add_argument("--size", default="960x540", help="ancho x alto en píxeles")
    parser.add_argument("--out", type=Path, help="carpeta de salida (por defecto <juego>/build/preview)")
    args = parser.parse_args(argv)
    try:
        width, height = (int(v) for v in args.size.lower().split("x"))
    except ValueError:
        print("ERROR --size debe tener la forma 960x540")
        return 2
    views = [v.strip() for v in args.views.split(",") if v.strip() in {"iso", "player"}]
    paths = preview(args.game, args.out, args.level, views, (width, height))
    for path in paths:
        print(path)
    print(f"{len(paths)} imágenes. No muestran texturas, materiales ni sombras: la prueba final es en Studio.")
    return 0 if paths else 1


if __name__ == "__main__":
    sys.exit(main())
