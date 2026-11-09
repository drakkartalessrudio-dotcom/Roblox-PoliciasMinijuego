"""Builds the Roblox vehicle manifest (schema 2) from measured pieces (pure Python, no Blender).

The manifest is the contract between the modeling pipeline and the Luau side (`VehicleAssembler`, `VehicleBody`):
everything the game needs to assemble and drive the car, in the Roblox model frame and in studs.
See references/manifest-format.md.
"""
from __future__ import annotations

from . import frame, groups

SCHEMA = 2
DEFAULT_SEAT_SIZE = (2.0, 0.6, 2.0)


def _r(value: float) -> float:
    return round(float(value), 4)


def _vec(values) -> list[float]:
    return [_r(v) for v in values]


def piece_entry(name: str, measured: dict, roblox_materials: dict) -> dict:
    """measured: {tris, center:[x,y,z], size:[sx,sy,sz]} in studs and VEHICLE space."""
    kind = groups.kind_of(name)
    material = roblox_materials.get(kind, {})
    return {
        "kind": kind,
        "material": material.get("material", "SmoothPlastic"),
        "color": list(material.get("color", [128, 128, 128])),
        "transparency": material.get("transparency", 0),
        "center": _vec(frame.point_to_roblox(measured["center"])),
        "size": _vec(frame.size_to_roblox(measured["size"])),
        "tris": int(measured["tris"]),
    }


def wheel_rig(pieces: dict, spec_parts: list[dict]) -> dict:
    """Per-wheel data from the Tire_xx pieces (Roblox frame)."""
    driven = {}
    for part in spec_parts:
        pid = part.get("id", "")
        if part.get("type") == "wheel" and pid.startswith("wheel_"):
            driven[pid.split("_", 1)[1]] = bool(part.get("driven", True))
            # a mirrored part also exists on the other side
            if part.get("mirror"):
                other = pid.split("_", 1)[1]
                driven[other[:-1] + "R"] = bool(part.get("driven", True))
    wheels = {}
    for tag in groups.WHEELS:
        tire = pieces.get(f"Tire_{tag}")
        if not tire:
            continue
        width, height, length = tire["size"]
        wheels[tag] = {
            "hub": list(tire["center"]),
            "radius": _r((height + length) / 4),  # tire diameter lies in Y (up) and Z (length)
            "width": _r(width),                   # axle runs along X
            "steer": tag.startswith("F"),
            "drive": driven.get(tag, tag.startswith("R")),
        }
    return wheels


def seat_rig(pieces: dict, wheels: dict, override: dict | None) -> dict:
    """Driver seat (left-hand drive) from the glass box, unless the spec gives `roblox.seat`."""
    if override and override.get("position"):
        position = [float(v) for v in override["position"]]
        source = "spec"
    else:
        windows = pieces.get("Windows") or pieces.get("Chassis")
        wx, wy, wz = windows["center"]
        sx, sy, sz = windows["size"]
        radius = max((w["radius"] for w in wheels.values()), default=1.2)
        front = wz - sz / 2  # -Z is the nose, so the windshield is at the smallest z
        position = [-0.25 * sx, radius + 0.4, front + 0.42 * sz]
        source = "derived from the Windows piece"
    size = list(override.get("size", DEFAULT_SEAT_SIZE)) if override else list(DEFAULT_SEAT_SIZE)
    return {"position": _vec(position), "size": _vec(size), "side": "left", "source": source}


def build(asset: str, spec: dict, measured_pieces: dict, measured_sockets: dict, fbx_name: str) -> dict:
    """measured_pieces: {name: {tris, center, size}} in studs and vehicle space; sockets in studs, vehicle space."""
    roblox = spec.get("roblox", {})
    materials = roblox.get("materials", {})
    pieces = {name: piece_entry(name, m, materials) for name, m in sorted(measured_pieces.items())}
    sockets = {name: _vec(frame.point_to_roblox(p)) for name, p in sorted(measured_sockets.items())}
    wheels = wheel_rig(pieces, spec.get("parts", []))
    chassis = pieces.get("Chassis")
    dims = spec.get("dimensions_cm", {})
    stud = frame.STUD_CM

    rig: dict = {"wheels": wheels}
    if wheels:
        hubs = [w["hub"] for w in wheels.values()]
        rig["wheelRadius"] = _r(sum(w["radius"] for w in wheels.values()) / len(wheels))
        if "FL" in wheels and "FR" in wheels:
            rig["trackWidth"] = _r(abs(wheels["FR"]["hub"][0] - wheels["FL"]["hub"][0]))
        if "FL" in wheels and "RL" in wheels:
            rig["wheelbase"] = _r(abs(wheels["RL"]["hub"][2] - wheels["FL"]["hub"][2]))
        rig["axleHeight"] = _r(sum(h[1] for h in hubs) / len(hubs))
    rig["seat"] = seat_rig(pieces, wheels, roblox.get("seat"))
    if chassis:
        cx, cy, cz = chassis["center"]
        sx, sy, sz = chassis["size"]
        rig["groundClearance"] = _r(cy - sy / 2)
        rig["collision"] = {"center": _vec(chassis["center"]), "size": _vec(chassis["size"]), "fidelity": "Box"}
    if spec.get("mass_kg"):
        rig["massKg"] = spec["mass_kg"]

    total = sum(p["tris"] for p in pieces.values())
    return {
        "schema": SCHEMA,
        "asset": asset,
        "tier": spec.get("tier"),
        "bodyType": roblox.get("bodyType", "car"),
        "class": spec.get("vehicle_class"),
        "units": frame.FRAME_DESCRIPTION,
        "frame": frame.FRAME_NAME,
        "fbx": fbx_name,
        "tris": {"total": total, "budget": spec.get("tri_budget")},
        "dimensions": {k: _r(v / stud) for k, v in dims.items()},
        "parts": pieces,
        "sockets": sockets,
        "rig": rig,
    }
