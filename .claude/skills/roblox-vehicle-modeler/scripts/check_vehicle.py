#!/usr/bin/env python3
"""Validates the manifests (schema 2) of Roblox vehicles produced by build_vehicle.py.

    python check_vehicle.py <manifest.json | folder> [...]  [--spec <spec.json>]  [--strict]

A folder is searched recursively for *.manifest.json. Exit code 1 if there are errors (with --strict, also warnings).
Checks: pieces and sockets, native materials, triangle budget, axes (nose = -Z), wheels on the ground and symmetric,
rim inside tire, driver seat inside the body, origin under the centre, and the FBX re-read result.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REQUIRED_PIECES = (
    "Chassis", "Windows",
    "Tire_FL", "Tire_FR", "Tire_RL", "Tire_RR",
    "Rim_FL", "Rim_FR", "Rim_RL", "Rim_RR",
)
OPTIONAL_PIECES = ("Trim", "Lights", "Bumpers", "Roof", "Bed", "Neon")
REQUIRED_SOCKETS = (
    "Socket_Spoiler",
    "Socket_Wheel_FL", "Socket_Wheel_FR", "Socket_Wheel_RL", "Socket_Wheel_RR",
    "Socket_Exhaust", "Socket_FrontBumper", "Socket_RearBumper", "Socket_RoofExtra",
)
NATIVE_MATERIALS = {"SmoothPlastic", "Plastic", "Metal", "Glass", "Neon", "Foil", "Concrete", "Wood", "Fabric"}
# Triangle ranges of the art guide (section 1.1), by body type. A vehicle may exceed its range only with a budget
# approved in the spec (`tri_budget`) and a decision that says so.
BODY_TYPE_MAX_TRIS = {
    "sedan": 3500, "hatch": 3500, "sports": 3500, "muscle": 3500, "super": 3500, "limo": 3500,
    "suv": 4500, "pickup": 4500, "truck": 6000, "motorcycle": 2200, "car": 3500,
}
WHEEL_TAGS = ("FL", "FR", "RL", "RR")
PIECE_RE = re.compile(r"^(Chassis|Windows|Trim|Lights|Bumpers|Roof|Bed|Neon|(Tire|Rim)_(FL|FR|RL|RR))$")


def _close(a: float, b: float, tol: float) -> bool:
    return abs(a - b) <= tol


def check_manifest(m: dict, spec: dict | None = None) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    err, warn = errors.append, warnings.append

    if m.get("schema") != 2:
        err(f"schema is {m.get('schema')!r}, expected 2")
    if m.get("frame") != "roblox-model":
        err(f"frame is {m.get('frame')!r}, expected 'roblox-model' (nose = -Z)")
    parts = m.get("parts", {})
    sockets = m.get("sockets", {})
    rig = m.get("rig", {})

    # pieces -------------------------------------------------------------------------------------------------
    for name in REQUIRED_PIECES:
        if name not in parts:
            err(f"missing piece {name}")
    for name in parts:
        if not PIECE_RE.match(name):
            err(f"unknown piece name '{name}' (allowed: {', '.join(REQUIRED_PIECES + OPTIONAL_PIECES)})")
    for name, p in parts.items():
        if p.get("material") not in NATIVE_MATERIALS:
            err(f"{name}: material '{p.get('material')}' is not a native Roblox material")
        color = p.get("color", [])
        if len(color) != 3 or not all(isinstance(c, int) and 0 <= c <= 255 for c in color):
            err(f"{name}: color must be [r, g, b] integers 0-255, got {color}")
        if not 0 <= p.get("transparency", 0) <= 1:
            err(f"{name}: transparency {p.get('transparency')} is outside 0-1")
        if p.get("tris", 0) <= 0:
            err(f"{name}: no triangles")
        if any(s <= 0 for s in p.get("size", [0])):
            err(f"{name}: size has a non-positive axis {p.get('size')}")
    for name in REQUIRED_SOCKETS:
        if name not in sockets:
            err(f"missing socket {name}")

    # triangle budget ----------------------------------------------------------------------------------------
    tris = m.get("tris", {})
    total = sum(p.get("tris", 0) for p in parts.values())
    if tris.get("total") != total:
        err(f"tris.total {tris.get('total')} does not match the sum of the pieces ({total})")
    budget = tris.get("budget")
    if budget is None:
        warn("no tri_budget in the spec: set the approved budget")
    elif total > budget:
        err(f"{total} triangles exceed the approved budget of {budget}")
    guide_max = BODY_TYPE_MAX_TRIS.get(m.get("bodyType", "car"), BODY_TYPE_MAX_TRIS["car"])
    if total > guide_max:
        decisions = " ".join((spec or {}).get("decisions", [])).lower()
        if "triangle" in decisions or "tris" in decisions:
            pass  # documented exception
        else:
            warn(f"{total} triangles exceed the guide range for '{m.get('bodyType', 'car')}' ({guide_max}); "
                 "add a decision to the spec explaining the exception")

    # axes and origin ----------------------------------------------------------------------------------------
    chassis = parts.get("Chassis")
    if chassis:
        width, height, length = chassis["size"]
        if length < width:
            err(f"Chassis is wider ({width}) than long ({length}): the length must run along Z")
        cx, cy, cz = chassis["center"]
        if abs(cx) > 0.5:
            warn(f"Chassis is off-centre in X by {cx:.2f} studs")
        if abs(cz) > 0.15 * length:
            warn(f"origin is not under the middle of the car (Chassis centre z = {cz:.2f}, length {length:.2f})")
        if cy - height / 2 < -0.01:
            err("Chassis goes below the ground (y < 0)")
    front, rear = sockets.get("Socket_FrontBumper"), sockets.get("Socket_RearBumper")
    if front and rear and not front[2] < rear[2]:
        err("Socket_FrontBumper is not at a smaller Z than Socket_RearBumper: the nose must point to -Z")

    # wheels -------------------------------------------------------------------------------------------------
    wheels = rig.get("wheels", {})
    for tag in WHEEL_TAGS:
        w = wheels.get(tag)
        tire, rim = parts.get(f"Tire_{tag}"), parts.get(f"Rim_{tag}")
        if not w or not tire or not rim:
            continue
        hub, radius = w["hub"], w["radius"]
        if not 0.6 <= radius <= 3.0:
            err(f"wheel {tag}: radius {radius} is outside 0.6-3.0 studs")
        if not _close(hub[1], radius, 0.2):
            err(f"wheel {tag}: hub height {hub[1]} should equal the radius {radius} (tire resting on the ground)")
        side = -1 if tag.endswith("L") else 1
        if hub[0] * side <= 0:
            err(f"wheel {tag}: hub x = {hub[0]} is on the wrong side (left wheels are -X, right wheels +X)")
        if not (_close(hub[0], tire["center"][0], 0.01) and _close(hub[2], tire["center"][2], 0.01)):
            err(f"wheel {tag}: rig hub does not match the Tire piece centre")
        for axis in (1, 2):
            if not _close(rim["center"][axis], tire["center"][axis], 0.05):
                err(f"wheel {tag}: Rim is not concentric with the Tire on axis {'xyz'[axis]}")
        if rim["size"][1] >= tire["size"][1]:
            err(f"wheel {tag}: Rim ({rim['size'][1]}) is not smaller than the Tire ({tire['size'][1]})")
        if tire["size"][0] > tire["size"][1]:
            err(f"wheel {tag}: tire is wider ({tire['size'][0]}) than tall ({tire['size'][1]}); the axle must run along X")
        socket = sockets.get(f"Socket_Wheel_{tag}")
        if socket and any(not _close(socket[i], hub[i], 0.05) for i in range(3)):
            err(f"Socket_Wheel_{tag} {socket} is not at the hub {hub}")
    if all(t in wheels for t in WHEEL_TAGS):
        for front_tag, rear_tag in (("FL", "RL"), ("FR", "RR")):
            if not wheels[front_tag]["hub"][2] < wheels[rear_tag]["hub"][2]:
                err(f"{front_tag} is not ahead (smaller Z) of {rear_tag}")
        for a, b in (("FL", "FR"), ("RL", "RR")):
            if not _close(wheels[a]["hub"][0], -wheels[b]["hub"][0], 0.05):
                err(f"wheels {a} and {b} are not symmetric in X")
        radii = [w["radius"] for w in wheels.values()]
        if max(radii) - min(radii) > 0.2:
            warn("wheel radii differ by more than 0.2 studs; the arcade suspension assumes one radius")

    # driver seat --------------------------------------------------------------------------------------------
    seat = rig.get("seat")
    if not seat:
        err("rig.seat is missing")
    elif chassis:
        sx, sy, sz = seat["position"]
        cx, cy, cz = chassis["center"]
        w, h, l = chassis["size"]
        if not (abs(sx - cx) <= w / 2 and abs(sz - cz) <= l / 2 and cy - h / 2 <= sy <= cy + h / 2):
            err(f"driver seat {seat['position']} is outside the Chassis box")
        if seat.get("side") == "left" and sx >= 0:
            err("driver seat is declared left-hand drive but x >= 0")

    # FBX re-read --------------------------------------------------------------------------------------------
    for problem in m.get("verify", []) or []:
        err(f"FBX does not match the manifest: {problem}")
    return errors, warnings


def collection_warnings(models: dict) -> list[str]:
    """Cross-checks between vehicles: universal spoiler base per body type (guide 5.2)."""
    by_type: dict[str, list[tuple[str, float, float]]] = {}
    for asset, m in models.items():
        spoiler = m.get("sockets", {}).get("Socket_Spoiler")
        rear = m.get("sockets", {}).get("Socket_RearBumper")
        if spoiler and rear:
            by_type.setdefault(m.get("bodyType", "car"), []).append((asset, spoiler[2] - rear[2], spoiler[1]))
    out = []
    for body_type, items in by_type.items():
        if len(items) < 2:
            continue
        for index, label in ((1, "distance from the rear bumper"), (2, "height")):
            values = [i[index] for i in items]
            if max(values) - min(values) > 1.5:
                out.append(f"body type '{body_type}': Socket_Spoiler {label} varies by "
                           f"{max(values) - min(values):.2f} studs between {', '.join(i[0] for i in items)}; "
                           "a spoiler will not fit all of them without offsets (guide 5.2)")
    return out


def find_manifests(paths: list[str]) -> list[Path]:
    found: list[Path] = []
    for raw in paths:
        p = Path(raw)
        if p.is_dir():
            found += sorted(p.rglob("*.manifest.json"))
        elif p.exists():
            found.append(p)
        else:
            print(f"ERROR: {raw} does not exist", file=sys.stderr)
            sys.exit(2)
    return found


def find_spec(manifest_path: Path, manifest: dict) -> dict | None:
    """The spec next to a manifest (<folder>/Export/<Asset>.manifest.json -> <folder>/<Asset>.spec.json), if any."""
    candidate = manifest_path.parent.parent / f"{manifest.get('asset', '')}.spec.json"
    if candidate.exists():
        try:
            return json.loads(candidate.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
    return None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--spec", help="spec.json to use for every manifest (by default the spec next to each manifest is used)")
    ap.add_argument("--strict", action="store_true", help="warnings also fail")
    args = ap.parse_args(argv)

    manifests = find_manifests(args.paths)
    if not manifests:
        print("ERROR: no *.manifest.json found", file=sys.stderr)
        return 2
    explicit_spec = json.loads(Path(args.spec).read_text(encoding="utf-8")) if args.spec else None
    total_errors = total_warnings = 0
    models = {}
    for path in manifests:
        m = json.loads(path.read_text(encoding="utf-8"))
        models[m.get("asset", path.stem)] = m
        errors, warnings = check_manifest(m, explicit_spec or find_spec(path, m))
        label = m.get("asset", path.name)
        for e in errors:
            print(f"ERROR {label}: {e}")
        for w in warnings:
            print(f"WARN  {label}: {w}")
        total_errors += len(errors)
        total_warnings += len(warnings)
        if not errors and not warnings:
            print(f"OK    {label}: {m['tris']['total']} tris")
    if len(models) > 1:
        for w in collection_warnings(models):
            print(f"WARN  collection: {w}")
            total_warnings += 1
    print(f"{len(manifests)} manifest(s): {total_errors} error(s), {total_warnings} warning(s)")
    return 1 if total_errors or (args.strict and total_warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
