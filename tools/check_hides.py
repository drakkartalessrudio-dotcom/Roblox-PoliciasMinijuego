#!/usr/bin/env python3
"""Revisa los escondites (zonas `hide`) de un nivel de Levels.json.

Comprueba la regla de densidad del GDD («Escondites cada ≤ 60 studs»):
  - cobertura: % de puntos transitables con un escondite a ≤ 60 studs (mínimo 95 %)
  - peor punto: la mayor distancia de un punto transitable al escondite más cercano (máximo 85 studs)
y que cada escondite esté bien puesto: tipo válido, mínimo 5 contenedores, no dentro de una Guarida,
y a ≥ 12 studs de un cop_spawn o un guard_post.

Los puntos transitables son los de una malla de 5 studs que no caen dentro de un prop `edificio-*`
(huella del edificio) y que no están en la franja exterior junto al muro del límite.

Uso: python tools/check_hides.py [src/shared/Levels.json] [id-del-nivel ...]
Sin ids revisa solo `barrio-papa`. Devuelve 1 si algo falla.
"""
import json
import math
import sys

MIN_COVERAGE = 95.0
MAX_WORST = 85.0
RANGE = 60.0
GRID = 5
EDGE_MARGIN = 10  # franja exterior que no se cuenta (la acera de afuera mide ~2 studs)
MIN_CONTAINERS = 5
MIN_FROM_COPS = 12.0


def inside(box, x, z):
    pos, size = box["position"], box["size"]
    return abs(x - pos[0]) <= size[0] / 2 and abs(z - pos[2]) <= size[2] / 2


def check(level):
    pieces = level["pieces"]
    hides = [p for p in pieces if p.get("kind") == "zone" and p.get("name") == "hide"]
    errors, notes = [], []
    if not hides:
        return ["no tiene zonas `hide`"], notes

    kinds = [h.get("hideKind", "bush") for h in hides]
    for h, k in zip(hides, kinds):
        if k not in ("bush", "container"):
            errors.append(f"{h['id']}: hideKind '{k}' no existe (bush | container)")
    containers = kinds.count("container")
    if containers < MIN_CONTAINERS:
        errors.append(f"solo {containers} contenedores (mínimo {MIN_CONTAINERS})")

    guaridas = [p for p in pieces if p.get("kind") == "zone" and p.get("name") == "guarida"]
    cops = [p for p in pieces if p.get("kind") == "zone" and p.get("name") in ("cop_spawn", "guard_post")]
    for h in hides:
        x, _, z = h["position"]
        if any(inside(g, x, z) for g in guaridas):
            errors.append(f"{h['id']}: está dentro de una Guarida")
        for c in cops:
            d = math.hypot(x - c["position"][0], z - c["position"][2])
            if d < MIN_FROM_COPS:
                errors.append(f"{h['id']}: a {d:.1f} studs de {c['id']} (mínimo {MIN_FROM_COPS:g})")

    ground = next((p for p in pieces if p["id"] == "suelo"), None)
    if ground is None:
        return errors + ["no hay pieza `suelo` para medir el área"], notes
    half_x = ground["size"][0] / 2 - EDGE_MARGIN
    half_z = ground["size"][2] / 2 - EDGE_MARGIN
    buildings = [p for p in pieces if p["id"].startswith("edificio")]
    points = []
    x = -half_x
    while x <= half_x:
        z = -half_z
        while z <= half_z:
            if not any(inside(b, x + ground["position"][0], z + ground["position"][2]) for b in buildings):
                points.append((x + ground["position"][0], z + ground["position"][2]))
            z += GRID
        x += GRID
    spots = [(h["position"][0], h["position"][2]) for h in hides]
    distances = [min(math.hypot(px - sx, pz - sz) for sx, sz in spots) for px, pz in points]
    coverage = 100.0 * sum(1 for d in distances if d <= RANGE) / len(distances)
    worst = max(distances)
    notes.append(f"{len(hides)} escondites ({containers} contenedores): cobertura a {RANGE:g} studs {coverage:.1f} %, peor punto {worst:.1f} studs")
    if coverage < MIN_COVERAGE:
        errors.append(f"cobertura {coverage:.1f} % (mínimo {MIN_COVERAGE:g} %)")
    if worst > MAX_WORST:
        errors.append(f"peor punto a {worst:.1f} studs (máximo {MAX_WORST:g})")
    return errors, notes


def main():
    args = sys.argv[1:]
    path = args[0] if args else "src/shared/Levels.json"
    ids = args[1:] or ["barrio-papa"]
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    levels = {level["id"]: level for level in data["levels"]}
    failed = False
    for level_id in ids:
        if level_id not in levels:
            print(f"ERROR {level_id}: no existe en {path}")
            failed = True
            continue
        errors, notes = check(levels[level_id])
        for note in notes:
            print(f"INFO  {level_id}: {note}")
        for error in errors:
            print(f"ERROR {level_id}: {error}")
            failed = True
    print("Resultado:", "con errores" if failed else "ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
