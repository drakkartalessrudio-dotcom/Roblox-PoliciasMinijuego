"""Helpers to write Roblox car specs from a few silhouettes (pure Python, no Blender).

Vehicle space: +X forward, +Y left, +Z up, cm. The left side is modelled and `mirror: true` makes the right.

    from rbx import specgen
    spec = specgen.car({...})                     # see `car` for the keys
    specgen.write(spec, "Tier 1 Sedan/")          # <folder>/<asset>.spec.json

`car` builds: the single-mesh body (side ∩ top ∩ front), window panels, wheel arches and wheels (tire + rim), the nine
Roblox sockets and the `roblox` block. `extras` are extra parts (bumpers, grille, lights, mirrors…) made with `box`/`cyl`.
"""
from __future__ import annotations

import json
import math
import os

GUIDE_DECISIONS = [
    "Follows the Roblox vehicle art guide: semi-cartoon low-poly, native materials, flat colours, no textures.",
    "Single Chassis mesh (mirrors embedded), separate Windows, Trim, Lights, Tire_xx + Rim_xx per wheel.",
    "No spoiler, no decals, no liveries (tuning base). Doors, hood and trunk are fixed.",
    "Sockets follow the guide section 3.1 naming; wheels pivot at the hub.",
]


def circle(cx: float, cz: float, r: float, n: int = 14) -> list[list[float]]:
    return [[round(cx + r * math.cos(2 * math.pi * i / n), 1), round(cz + r * math.sin(2 * math.pi * i / n), 1)]
            for i in range(n)]


def rgb(h: str) -> list[float]:
    return [round(int(h[i:i + 2], 16) / 255, 4) for i in (1, 3, 5)]


def rb(h: str) -> list[int]:
    return [int(h[i:i + 2], 16) for i in (1, 3, 5)]


def roblox_block(body: str, body_type: str = "car", trim="#8E9399", rim="#9AA0A6", lights="#F2E27A", glass="#2B3A44",
                 bumper=None, roof=None, neon="#35E8F2", bed=None, tire="#1C1C20", seat: dict | None = None) -> dict:
    """The `roblox` block of a spec: body type, Roblox material + colour per piece kind, optional driver seat."""
    block: dict = {
        "bodyType": body_type,
        "materials": {
            "Chassis": {"material": "SmoothPlastic", "color": rb(body)},
            "Windows": {"material": "Glass", "color": rb(glass), "transparency": 0.35},
            "Trim": {"material": "SmoothPlastic", "color": rb(trim)},
            "Lights": {"material": "Neon", "color": rb(lights)},
            "Bumpers": {"material": "SmoothPlastic", "color": rb(bumper or trim)},
            "Roof": {"material": "SmoothPlastic", "color": rb(roof or body)},
            "Bed": {"material": "SmoothPlastic", "color": rb(bed or body)},
            "Neon": {"material": "Neon", "color": rb(neon)},
            "Tire": {"material": "SmoothPlastic", "color": rb(tire)},
            "Rim": {"material": "Metal", "color": rb(rim)},
        },
    }
    if seat:
        block["seat"] = seat
    return block


def preview(body: str, trim="#8E9399", glass="#2B3A44", lights="#F2E27A") -> dict:
    """Blender preview materials (renders only; the Roblox colours come from `roblox.materials`)."""
    return {
        "MI_Body": {"base_color": rgb(body), "metallic": 0.0, "roughness": 0.35},
        "MI_Trim": {"base_color": rgb(trim), "metallic": 0.0, "roughness": 0.5},
        "MI_Glass": {"color": rgb(glass), "alpha": 0.55},
        "MI_Lights": {"color": rgb(lights), "strength": 6.0},
    }


def box(id_, desc, center, size, layer, material=None, rot=None, mirror=False, bevel=0.8) -> dict:
    d = {"id": id_, "type": "box", "layer": layer, "description": desc, "center_cm": center, "size_cm": size,
         "bevel_cm": bevel, "bevel_segments": 1}
    if material:
        d["material"] = material
    if rot:
        d["rotate_xyz_deg"] = rot
    if mirror:
        d["mirror"] = True
    return d


def cyl(id_, desc, center, r, length, layer, material=None, axis="X", mirror=False) -> dict:
    d = {"id": id_, "type": "cylinder", "layer": layer, "description": desc, "center_cm": center, "radius_cm": r,
         "length_cm": length, "axis": axis, "bevel_cm": 0.0}
    if material:
        d["material"] = material
    if mirror:
        d["mirror"] = True
    return d


def car(c: dict) -> dict:
    """c: asset, tier, class, brief, dims (L, W, H cm), tri_budget, side/top/front silhouettes, windows, wheel_x
    (front, rear), wheel_r, wheel_w, wheel_y, front_x, rear_x, bumper_z, sock_spoiler, sock_roof, extras,
    preview_materials, roblox (see `roblox_block`); optional mass, bevel, rim_ratio, arch_gap, wheel_segments,
    decisions."""
    wf, wr = c["wheel_x"]
    R, W, yw = c["wheel_r"], c["wheel_w"], c["wheel_y"]
    high = c["tri_budget"] >= 6000
    parts = [{
        "id": "body", "type": "hull",
        "description": "Single-mesh chassis: side ∩ top ∩ front silhouettes (mirrors embedded).",
        "side": c["side"], "top": c["top"], "top_half": True, "front": c["front"], "front_half": True,
        "bevel_cm": max(c.get("bevel", 2.0), 4.0) if high else c.get("bevel", 2.0),
        "bevel_segments": 3 if high else 1,  # high-budget tiers get a rounder body
    }]
    for i, w in enumerate(c["windows"]):
        if w["view"] == "top":  # leave A/C pillars: glass narrower than the body
            w = {**w, "poly": [[x, round(y * 0.86, 1)] for x, y in w["poly"]]}
        parts.append({
            "id": w.get("id", f"window_{i}"), "type": "panel", "from": "body", "mirror": w["mirror"],
            "layer": "L6_Glass", "material": "MI_Glass", "description": w["desc"], "view": w["view"], "poly": w["poly"],
            **({"y_from_cm": w["y_from"]} if w["view"] == "side" else {"z_from_cm": w["z_from"]}),
            "gap_cm": 0.4, "bevel_cm": 0,
        })
    for tag, x in (("F", wf), ("R", wr)):
        parts.append({
            "id": f"well_{tag}L", "type": "panel", "from": "body", "cut_only": True, "mirror": True,
            "description": f"{tag}-left wheel arch (recess only).", "view": "side",
            "poly": circle(x, R, R + c.get("arch_gap", 5)), "y_from_cm": yw - W / 2 - 4,
        })
        parts.append({
            "id": f"wheel_{tag}L", "type": "wheel", "role": "wheel", "mirror": True,
            "description": f"{tag}-left wheel: TireMesh + RimMesh (guide 2.2).", "driven": tag == "R",
            "center_cm": [x, yw, R], "radius_cm": R, "width_cm": W, "rim_ratio": c.get("rim_ratio", 0.6),
            "rim_dish": 0.12, "segments": c.get("wheel_segments", 12), "bevel_cm": 0.0,
            "motion": {"type": "rotate", "axis": "Y", "min": 0, "max": 360},
        })
    parts += c["extras"]

    length, width, height = c["dims"]
    sockets = [
        {"name": f"Socket_Wheel_{t}", "at_3d": [x, s * yw, R], "description": f"Wheel hub {t}."}
        for t, x, s in (("FL", wf, 1), ("FR", wf, -1), ("RL", wr, 1), ("RR", wr, -1))
    ] + [
        {"name": "Socket_Spoiler", "at_3d": c["sock_spoiler"], "description": "Universal spoiler base (guide 5.2)."},
        {"name": "Socket_Exhaust", "at_3d": [c["rear_x"], -width * 0.28, 36], "description": "Exhaust tip (rear, right)."},
        {"name": "Socket_FrontBumper", "at_3d": [c["front_x"], 0, c["bumper_z"]], "description": "Front bumper / splitter."},
        {"name": "Socket_RearBumper", "at_3d": [c["rear_x"], 0, c["bumper_z"]], "description": "Rear bumper / diffuser."},
        {"name": "Socket_RoofExtra", "at_3d": c["sock_roof"], "description": "Roof rack, lightbar, horns."},
    ]
    return {
        "asset": c["asset"], "tier": c["tier"], "vehicle_class": c["class"], "brief": c["brief"],
        "dimensions_cm": {"length": length, "width": width, "height": height, "wheelbase": wf - wr, "wheel_radius": R},
        "mass_kg": c.get("mass", 1200), "tri_budget": c["tri_budget"],
        "layer_notes": {
            "L0_Structure": "Chassis monocoque", "L6_Glass": "Windows mesh (tintable)",
            "L7_Lights": "Lights mesh (Neon)", "L3_Running": "Tire + Rim per wheel", "L8_Details": "Bumpers, grille, trim",
        },
        "decisions": GUIDE_DECISIONS + c.get("decisions", []),
        "materials": c["preview_materials"], "roblox": c["roblox"],
        "lod_drop_layers": {}, "motion_check": False, "auto_unwrap": False,
        "default_space": "cm", "views": {"side": {}, "top": {}, "front": {}},
        "parts": parts, "sockets": sockets,
        "animations": [{"name": "Drive", "preset": "drive_loop", "description": "Wheels roll (reference only)."}],
    }


def write(spec: dict, folder: str) -> str:
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{spec['asset']}.spec.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(spec, fh, indent=1, ensure_ascii=False)
    return path
