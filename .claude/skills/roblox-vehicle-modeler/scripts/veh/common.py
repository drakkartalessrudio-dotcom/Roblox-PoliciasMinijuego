"""Shared utilities: units, collections, spec loading (+ L/R mirroring), logging, view coordinate mapping.

Vehicle space (Blender): +X = forward (nose / bow / front bumper), +Z = up, +Y = vehicle's LEFT (port) side.
Units in the spec are cm (1 BU = 1 cm, scene unit scale 0.01, like Unreal). Origin = ground point under the
vehicle's center (default) or the socket named by 'origin_socket'.
Views: side [x, z] (looking at the LEFT side), top [x, y], front [y, z]; each may be in cm or image px (calib).
"""
import copy
import json
import os

import bpy

LAYER_NAMES = [
    "L0_Structure",   # chassis / hull / fuselage core volume
    "L1_Body",        # body panels, fenders, nacelles, superstructure, armor plates (static)
    "L2_Openings",    # MOVING panels: doors, hood, trunk, hatches, canopy, ramps, bomb bays
    "L3_Running",     # wheels, tires, suspension, tracks, rotors, propellers, landing gear, screws
    "L4_Controls",    # steering, control surfaces, rudders, turrets, guns, cranes, wipers
    "L5_Interior",    # cockpit, seats, dashboard, controls, cargo bay
    "L6_Glass",       # windows, windshield, canopy glass, lamp covers
    "L7_Lights",      # headlights, tail lights, nav/strobe lights, displays (emissive)
    "L8_Details",     # mirrors, antennas, exhausts, rivets, handles, vents, decals, damage pieces
]
SLOT_ORDER = ["MI_Body", "MI_Trim", "MI_Glass", "MI_Lights"]
DEFAULT_LAYER_MATERIAL = {ln: "MI_Body" for ln in LAYER_NAMES}
DEFAULT_LAYER_MATERIAL.update({"L3_Running": "MI_Trim", "L5_Interior": "MI_Trim", "L8_Details": "MI_Trim",
                               "L6_Glass": "MI_Glass", "L7_Lights": "MI_Lights"})
VIEW_AXES = {"side": ("x", "z"), "top": ("x", "y"), "front": ("y", "z")}

_LOG = []


def log(msg):
    print("[veh] " + str(msg))
    _LOG.append(str(msg))


def pop_log():
    out = list(_LOG)
    _LOG.clear()
    return out


def cm(v=1.0):
    scale = bpy.context.scene.unit_settings.scale_length or 1.0
    return v * 0.01 / scale


# ----------------------------------------------------------------------------- spec + mirroring

def mirror_id(pid):
    """wheel_FL -> wheel_FR, door_L -> door_R, aileron_L -> aileron_R, gear -> gear_R."""
    head, sep, tail = pid.rpartition("_")
    if sep and tail.endswith("L"):
        return f"{head}_{tail[:-1]}R"
    return pid + "_R"


def _neg_y(points, index):
    return [[(-v if i == index else v) for i, v in enumerate(p)] for p in points]


def _mirror_motion(m, ids=()):
    m = copy.deepcopy(m)
    if m.get("allow_contact"):
        m["allow_contact"] = [mirror_id(x) if x in ids else x for x in m["allow_contact"]]
    ax = m.get("axis", "X")
    if isinstance(ax, (list, tuple)):
        m["axis"] = [ax[0], -ax[1], ax[2]]
        if m["type"] == "rotate":
            m["min"], m["max"] = -m.get("min", 0.0), -m.get("max", 0.0)
    elif m["type"] == "rotate" and ax in ("X", "Z"):
        m["min"], m["max"] = -m.get("min", 0.0), -m.get("max", 0.0)
    elif m["type"] == "translate" and ax == "Y":
        m["min"], m["max"] = -m.get("min", 0.0), -m.get("max", 0.0)
    if "pivot_y_cm" in m:
        m["pivot_y_cm"] = -m["pivot_y_cm"]
    if "pivot_3d" in m:
        m["pivot_3d"] = [m["pivot_3d"][0], -m["pivot_3d"][1], m["pivot_3d"][2]]
    return m


def mirror_part(p, ids):
    q = copy.deepcopy(p)
    q.pop("mirror", None)
    q["id"] = mirror_id(p["id"])
    q["mirrored_from"] = p["id"]
    if q.get("parent") in ids:
        q["parent"] = mirror_id(q["parent"])
    if q.get("from") in ids:
        q["from"] = mirror_id(q["from"])
    if q.get("role", "").endswith("_L"):
        q["role"] = q["role"][:-2] + "_R"
    for k in ("y_cm", "y_from_cm"):
        if k in q:
            q[k] = -q[k]
    for k in ("center_cm", "pivot_cm"):
        if k in q:
            q[k] = [q[k][0], -q[k][1], q[k][2]]
    if "top" in q:
        q["top"] = _neg_y(q["top"], 1)
    if "front" in q:
        q["front"] = _neg_y(q["front"], 0)
    if "path_3d" in q:
        q["path_3d"] = _neg_y(q["path_3d"], 1)
    if "poly" in q and q.get("type") == "panel" and q.get("view") in ("top", "front") \
            and not isinstance(q["poly"], str):
        q["poly"] = _neg_y(q["poly"], 1 if q["view"] == "top" else 0)
    if "planform" in q and q.get("plane", "top") == "top":
        q["planform"] = _neg_y(q["planform"], 1)
    if "dihedral_deg" in q:
        q["dihedral_deg"] = -q["dihedral_deg"]  # rotation about X flips sign when mirrored
    if "rotate_xyz_deg" in q:
        rx, ry, rz = q["rotate_xyz_deg"]
        q["rotate_xyz_deg"] = [-rx, ry, -rz]
    if q.get("motion"):
        q["motion"] = _mirror_motion(q["motion"], ids)
    if q.get("description"):
        import re
        sw = {"left": "right", "Left": "Right", "LEFT": "RIGHT", "port": "starboard", "Port": "Starboard"}
        q["description"] = re.sub(r"\b(left|Left|LEFT|port|Port)\b", lambda m: sw[m.group(1)], q["description"]) \
            + f" (mirror of {p['id']})"
    return q


def prepare(spec):
    """Expand 'mirror': true parts/sockets into right-side copies (idempotent)."""
    if spec.get("_prepared"):
        return spec
    parts = spec.get("parts", [])
    ids = {p["id"] for p in parts if p.get("mirror")}
    out = []
    for p in parts:
        out.append(p)
        if p.get("mirror"):
            out.append(mirror_part(p, ids))
    spec["parts"] = out
    socks = []
    for s in spec.get("sockets", []):
        socks.append(s)
        if s.get("mirror"):
            t = copy.deepcopy(s)
            t.pop("mirror")
            t["name"] = mirror_id(s["name"])
            if "y_cm" in t:
                t["y_cm"] = -t["y_cm"]
            if "at_3d" in t:
                t["at_3d"] = [t["at_3d"][0], -t["at_3d"][1], t["at_3d"][2]]
            if t.get("parent") in ids:
                t["parent"] = mirror_id(t["parent"])
            socks.append(t)
    spec["sockets"] = socks
    spec["_prepared"] = True
    return spec


def load_spec(path):
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    spec["_dir"] = os.path.dirname(os.path.abspath(path))
    spec["_file"] = os.path.abspath(path)
    return prepare(spec)


def resolve_path(spec, p):
    if not p:
        return None
    return p if os.path.isabs(p) else os.path.join(spec.get("_dir", ""), p)


# ----------------------------------------------------------------------------- collections

def get_collection(name, parent=None):
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    parent = parent or bpy.context.scene.collection
    if col.name not in [c.name for c in parent.children]:
        for c in [bpy.context.scene.collection] + list(bpy.data.collections):
            if c is not parent and col.name in [x.name for x in c.children]:
                c.children.unlink(col)
        parent.children.link(col)
    return col


def ensure_collections():
    get_collection("REF")
    layers = get_collection("LAYERS")
    for n in LAYER_NAMES:
        get_collection(n, layers)
    cut = get_collection("CUTTERS")
    cut.hide_render = True
    cut.hide_viewport = True
    get_collection("HIGH")
    get_collection("EXPORT")


def remove_object(obj):
    data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if data is not None and getattr(data, "users", 1) == 0:
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        elif isinstance(data, bpy.types.Armature):
            bpy.data.armatures.remove(data)


def objects_in_layers():
    out = []
    layers = bpy.data.collections.get("LAYERS")
    if layers:
        for col in layers.children:
            out += [o for o in col.objects if "veh_part" in o]
    return out


def ensure_units():
    """Vehicles are authored in cm: scene unit scale 0.01 (1 BU = 1 cm), like Unreal."""
    us = bpy.context.scene.unit_settings
    if abs((us.scale_length or 1.0) - 0.01) > 1e-9:
        if not objects_in_layers():
            us.system = "METRIC"
            us.scale_length = 0.01
            log("Scene unit scale set to 0.01 (1 BU = 1 cm).")
        else:
            log("WARNING: scene unit scale is not 0.01; keeping it (parts already exist).")
    bpy.context.scene.unit_settings.length_unit = "CENTIMETERS"


# ----------------------------------------------------------------------------- views

class Views:
    """Maps 2D view points to vehicle space (BU).

    side [x, z], top [x, y], front [y, z]. space 'cm' or 'px' (needs views.<name>.calib =
    {"a_px": [..], "a_cm": [u, v], "b_px": [..], "b_cm": [u, v], "flip_x": false} with u, v in that view's
    axes; flip_x for images mirrored horizontally, e.g. a side blueprint with the nose pointing left).
    """

    def __init__(self, spec):
        self.T = {}
        for name, vd in (spec.get("views") or {}).items():
            cal = (vd or {}).get("calib")
            if cal:
                fx = -1 if cal.get("flip_x") else 1  # e.g. side blueprint with the nose pointing LEFT
                a_px = complex(fx * cal["a_px"][0], -cal["a_px"][1])
                b_px = complex(fx * cal["b_px"][0], -cal["b_px"][1])
                a_cm, b_cm = complex(*cal["a_cm"]), complex(*cal["b_cm"])
                self.T[name] = (a_px, a_cm, (b_cm - a_cm) / (b_px - a_px), fx)

    def to2(self, view, pt, space):
        if space == "cm":
            return cm(pt[0]), cm(pt[1])
        if space == "px":
            if view not in self.T:
                raise RuntimeError(f"space 'px' needs views.{view}.calib in the spec.")
            a_px, a_cm, k, fx = self.T[view]
            w = a_cm + (complex(fx * pt[0], -pt[1]) - a_px) * k
            return cm(w.real), cm(w.imag)
        raise ValueError(f"Unknown space: {space}")

    def to_xz(self, pt, space):
        return self.to2("side", pt, space)


def save_version(base_name=None):
    fp = bpy.data.filepath
    if not fp:
        log("Unsaved file: no version created (save the .blend first).")
        return None
    folder = os.path.dirname(fp)
    stem = base_name or os.path.splitext(os.path.basename(fp))[0].split("_v")[0]
    i = 1
    while os.path.exists(os.path.join(folder, f"{stem}_v{i:03d}.blend")):
        i += 1
    cand = os.path.join(folder, f"{stem}_v{i:03d}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=cand, copy=True)
    log(f"Version saved: {cand}")
    return cand
