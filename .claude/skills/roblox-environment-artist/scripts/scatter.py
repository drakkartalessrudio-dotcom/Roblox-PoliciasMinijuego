#!/usr/bin/env python3
"""Reparte props en un área de un nivel sin romper las reglas del pase de arte.

Uso:
    python scatter.py <carpeta-del-juego> --level nivel-1 --prefab spire --count 8 \\
        --area -40 0 -20 -100 --ground -11 [--jitter 0.3] [--spacing 2] [--seed 1] \\
        [--prefix aguja] [--collide] [--dry-run]
    python scatter.py <carpeta-del-juego> --level plaza --asset pinoUsuario --count 6 ...

El área (x0 z0 x1 z1) y el suelo (--ground, altura de la base de los props) van en
coordenadas del nivel, como las posiciones de Levels.json. Cada candidato recibe un
tamaño (el del prefab ± jitter) y un giro al azar, y se descarta si invade el aire
de un salto, si tiene colisión al alcance de una pieza pisable, si parece pisable,
si atraviesa una pieza del nivel (salvo peligros y zonas) o si queda a menos de
--spacing studs de otro prop. Los props aceptados se agregan a Environment.json.

Si el prefab no está en Environment.json pero sí en la biblioteca del skill
(assets/prefabs.json), se copia con sus colores por defecto: revísalos. Con --asset
se reparten modelos del usuario ya declarados en 'assets' (necesitan 'size').
La misma semilla da el mismo resultado.
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

import check_environment as ce

LIBRARY = Path(__file__).resolve().parents[1] / "assets" / "prefabs.json"
ATTEMPTS_PER_PROP = 40


def scatter(game: Path, level_id: str, prefab_name: str | None, count: int, area: tuple[float, float, float, float],
            ground: float, jitter: float = 0.25, spacing: float = 2.0, seed: int = 1, prefix: str | None = None,
            collide: bool = False, asset_name: str | None = None) -> tuple[dict, list[dict], list[str]]:
    """Devuelve (Environment.json actualizado, props agregados, notas)."""
    shared = game / "src" / "shared"
    environment = json.loads((shared / "Environment.json").read_text(encoding="utf-8"))
    theme = json.loads((shared / "Theme.json").read_text(encoding="utf-8"))
    levels_data = json.loads((shared / "Levels.json").read_text(encoding="utf-8"))
    notes: list[str] = []

    prefabs = environment.setdefault("prefabs", {})
    assets = environment.get("assets", {}) if isinstance(environment.get("assets"), dict) else {}
    if asset_name is not None:
        asset = assets.get(asset_name)
        if not isinstance(asset, dict) or asset.get("kind") != "model" or ce.vec3(asset.get("size")) is None:
            raise SystemExit(f"ERROR {asset_name!r} no es un modelo declarado en 'assets' con 'size'")
        prefab = {"size": asset["size"]}
    else:
        if prefab_name not in prefabs:
            library = json.loads(LIBRARY.read_text(encoding="utf-8"))["prefabs"]
            if prefab_name not in library:
                raise SystemExit(f"ERROR no existe el prefab {prefab_name!r} en Environment.json ni en la biblioteca")
            prefabs[prefab_name] = {key: value for key, value in library[prefab_name].items() if key != "description"}
            notes.append(f"se copió el prefab {prefab_name!r} de la biblioteca con colores {prefabs[prefab_name].get('colors')}; ajústalos a la paleta")
        prefab = prefabs[prefab_name]

    checker = ce.make_checker(environment, theme, levels_data)
    if checker is None:
        raise SystemExit("ERROR scatter.py necesita roblox-level-designer y roblox-art-director instalados al lado")
    if not checker.prepare():
        raise SystemExit("ERROR " + "; ".join(checker.result.errors))
    levels = {level.get("id"): (level, index) for index, level in enumerate(levels_data.get("levels", []))}
    if level_id not in levels:
        raise SystemExit(f"ERROR no existe el nivel {level_id!r} en Levels.json")
    level, index = levels[level_id]
    pieces, _ = checker.vl.check_level(level, index, checker.physics, checker.rules, checker.vl.Result())
    space = checker.space(level, pieces)
    origin = ce.vec3(level.get("origin", [0, 0, 0])) or (0.0, 0.0, 0.0)
    obstacles = [p.box for p in pieces if p.kind not in {"hazard", "zone"}]

    level_env = environment.setdefault("levels", {}).setdefault(level_id, {})
    props = level_env.setdefault("props", [])
    taken = {p.get("id") for p in props if isinstance(p, dict)} | {p.id for p in pieces}
    placed = []
    for prop in props:
        if isinstance(prop, dict) and ce.vec3(prop.get("position")):
            default = prefabs.get(prop.get("prefab"), {}).get("size") or assets.get(prop.get("asset"), {}).get("size")
            size = ce.vec3(prop.get("size", default)) or (4.0, 4.0, 4.0)
            center = [o + p for o, p in zip(origin, ce.vec3(prop["position"]))]
            placed.append(checker.item_box(center, list(size), [0.0, float(prop.get("yaw", 0)), 0.0]))

    base = ce.vec3(prefab.get("size")) or (4.0, 4.0, 4.0)
    x0, z0, x1, z1 = min(area[0], area[2]), min(area[1], area[3]), max(area[0], area[2]), max(area[1], area[3])
    rng = random.Random(seed)
    stem = prefix or asset_name or prefab_name
    added: list[dict] = []
    number = 1
    for _ in range(count * ATTEMPTS_PER_PROP):
        if len(added) == count:
            break
        scale = 1 + rng.uniform(-jitter, jitter)
        size = [round(b * scale, 2) for b in base]
        position = [round(rng.uniform(x0, x1), 1), round(ground + size[1] / 2, 2), round(rng.uniform(z0, z1), 1)]
        yaw = int(round(rng.uniform(0, 360) / 5) * 5) % 360
        box = checker.item_box([o + p for o, p in zip(origin, position)], size, [0.0, float(yaw), 0.0])
        if checker.problems(space, "candidato", box, collide, False, True):
            continue
        if any(box.overlaps(other) for other in obstacles):
            continue
        roomy = checker.vl.Box(box.cx, box.cy, box.cz, box.ex + spacing / 2, box.ey, box.ez + spacing / 2)
        if any(roomy.overlaps(other) for other in placed):
            continue
        while f"{stem}_{number}" in taken:
            number += 1
        source = {"asset": asset_name} if asset_name else {"prefab": prefab_name}
        prop = {"id": f"{stem}_{number}", **source, "position": position, "size": size, "yaw": yaw}
        if collide:
            prop["collide"] = True
        taken.add(prop["id"])
        placed.append(box)
        props.append(prop)
        added.append(prop)
    if len(added) < count:
        notes.append(f"solo entraron {len(added)} de {count}: el área es chica o está muy cerca de lo jugable")
    return environment, added, notes


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Reparte props en un área de un nivel respetando las reglas del pase de arte.")
    parser.add_argument("game", type=Path, help="carpeta del juego")
    parser.add_argument("--level", required=True, help="id del nivel en Levels.json")
    kind = parser.add_mutually_exclusive_group(required=True)
    kind.add_argument("--prefab", help="prefab de Environment.json o de la biblioteca")
    kind.add_argument("--asset", help="modelo del usuario declarado en 'assets' (con 'size')")
    parser.add_argument("--count", type=int, required=True, help="cantidad de props")
    parser.add_argument("--area", type=float, nargs=4, required=True, metavar=("X0", "Z0", "X1", "Z1"), help="rectángulo en coordenadas del nivel")
    parser.add_argument("--ground", type=float, required=True, help="altura de la base de los props, en coordenadas del nivel")
    parser.add_argument("--jitter", type=float, default=0.25, help="variación de tamaño (0.25 = ±25%%)")
    parser.add_argument("--spacing", type=float, default=2.0, help="distancia mínima entre props, en studs")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--prefix", help="prefijo de los ids (por defecto, el nombre del prefab)")
    parser.add_argument("--collide", action="store_true", help="props con colisión (solo lejos de lo jugable)")
    parser.add_argument("--dry-run", action="store_true", help="muestra los props sin escribir el archivo")
    args = parser.parse_args(argv)
    environment, added, notes = scatter(args.game, args.level, args.prefab, args.count, tuple(args.area), args.ground,
                                        args.jitter, args.spacing, args.seed, args.prefix, args.collide, args.asset)
    for prop in added:
        print(ce.inline_json(prop))
    for note in notes:
        print(f"NOTA {note}")
    if not args.dry_run and added:
        path = args.game / "src" / "shared" / "Environment.json"
        path.write_text(ce.format_json(environment) + "\n", encoding="utf-8", newline="\n")
        print(f"Se agregaron {len(added)} props a {path}. Corre check_environment.py y revisa el resultado en Studio.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
