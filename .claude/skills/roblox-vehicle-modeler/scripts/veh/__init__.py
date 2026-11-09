"""veh — vehicle builder (land / sea / air): blueprint-driven layered parts + moving-part rig + simple animations
+ skeletal and rigid exports for Unreal / UEFN / Unity / Godot + living parts document.

    import sys, importlib; sys.path.insert(0, r"<skill folder>/scripts")
    import veh; importlib.reload(veh)
    veh.setup(SPEC); veh.build(SPEC); veh.review(SPEC, RENDERS, "blockout"); veh.finalize(SPEC, EXPORT, RENDERS)
"""
import importlib
import json
import os
import sys

_SUB = ("common", "materials", "generators", "rig", "anim", "check", "render", "export", "docs")
_m = {}
for _n in _SUB:
    _full = f"{__name__}.{_n}"
    _m[_n] = importlib.reload(sys.modules[_full]) if _full in sys.modules else importlib.import_module(_full)
common, materials, generators = _m["common"], _m["materials"], _m["generators"]
_rig, _anim, _check, _render, _export, docs = (_m[k] for k in ("rig", "anim", "check", "render", "export", "docs"))

from .common import load_spec, log, objects_in_layers, pop_log, save_version  # noqa: E402,F401

__version__ = "1.0.0"


def _spec(s):
    return load_spec(s) if isinstance(s, str) else common.prepare(s)


def _doc(spec, kind, data):
    try:
        docs.record(spec, kind, data)
        return docs.write_doc(spec)
    except Exception as e:  # noqa
        log(f"Document not updated: {e}")
        return None


def setup(spec_path):
    """Units (1 BU = 1 cm), collections, preview materials, blueprint reference images (side/top/front)."""
    import bpy
    spec = _spec(spec_path)
    common.ensure_units()
    common.ensure_collections()
    materials.ensure_materials(spec)
    ids = {p["id"] for p in spec.get("parts", [])}
    foreign = sorted({o.get("veh_spec_part") for o in objects_in_layers()} - ids)
    if foreign:
        log(f"WARNING: LAYERS holds parts that are not in this spec ({', '.join(foreign[:8])}...). "
            "Collections are shared by the whole .blend: use ONE .blend per vehicle (or clear_parts first).")
    for view, vd in (spec.get("views") or {}).items():
        if vd and vd.get("image") and vd.get("calib"):
            _ref_image(spec, view, vd)
    _doc(spec, "setup", {"blend": bpy.data.filepath})
    return {"log": pop_log(), "document": docs._paths(spec)[0]}


def _ref_image(spec, view, vd):
    """Image empty aligned to the calibrated blueprint, placed behind the vehicle (1000 cm)."""
    import bpy
    from mathutils import Matrix, Vector
    img = bpy.data.images.load(common.resolve_path(spec, vd["image"]), check_existing=True)
    W, H = img.size
    views = common.Views(spec)
    depth = -common.cm(vd.get("ref_depth_cm", 1000))

    def P(px, py):
        u, v = views.to2(view, [px, py], "px")
        return Vector({"side": (u, depth, v), "top": (u, v, depth), "front": (depth, u, v)}[view])

    w0, h0 = (1.0, H / W) if W >= H else (W / H, 1.0)
    X = (P(W, H / 2) - P(0, H / 2)) / w0
    Y = (P(W / 2, 0) - P(W / 2, H)) / h0
    Z = X.cross(Y).normalized()
    M = Matrix((X, Y, Z)).transposed().to_4x4()
    M.translation = P(W / 2, H / 2)
    name = f"REF_{view}"
    e = bpy.data.objects.get(name) or bpy.data.objects.new(name, None)
    e.empty_display_type = "IMAGE"
    e.data = img
    e.empty_display_size = 1.0
    e.use_empty_image_alpha = True
    e.color[3] = 0.5
    e.matrix_world = M
    if e.name not in common.get_collection("REF").objects:
        common.get_collection("REF").objects.link(e)


def clear_parts(ids=None):
    n = 0
    for o in objects_in_layers():
        if ids is None or o.get("veh_spec_part") in ids:
            common.remove_object(o)
            n += 1
    return n


def stats():
    import bpy
    dg = bpy.context.evaluated_depsgraph_get()
    out = {}
    for o in objects_in_layers():
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        out[o["veh_layer"]] = out.get(o["veh_layer"], 0) + sum(len(p.vertices) - 2 for p in me.polygons)
        ev.to_mesh_clear()
    out["TOTAL"] = sum(out.values())
    return out


def _with_dependents(spec, only):
    """A rebuilt source also rebuilds the panels cut from it (and their mirrored copies)."""
    if not only:
        return only
    out = list(only)
    changed = True
    while changed:
        changed = False
        for p in spec.get("parts", []):
            if p.get("type") == "panel" and p.get("from") in out and p["id"] not in out:
                out.append(p["id"])
                changed = True
    return out


def build(spec_path, only=None):
    """Build (or rebuild) parts. only=['id', ...] rebuilds just those parts (+ panels cut from them)."""
    spec = _spec(spec_path)
    common.ensure_units()
    common.ensure_collections()
    materials.ensure_materials(spec)
    only = _with_dependents(spec, only)
    removed = clear_parts(only)
    b = generators.Builder(spec)
    built, errors = {}, {}
    parts = spec.get("parts", [])
    ordered = [p for p in parts if p.get("type") != "panel"] + [p for p in parts if p.get("type") == "panel"]
    for part in ordered:
        if (only and part["id"] not in only) or part.get("enabled", True) is False:
            continue
        try:
            built[part["id"]] = [o.name for o in b.build(part)]
        except Exception as e:  # noqa
            errors[part["id"]] = f"{type(e).__name__}: {e}"
            log(f"ERROR in {part['id']}: {e}")
    cuts = generators.apply_cuts(spec)
    st = stats()
    lg = pop_log()
    doc = _doc(spec, "build", {"only": only, "built": built, "errors": errors, "stats": st, "cuts": cuts,
                               "log": lg})
    return {"removed": removed, "built": built, "errors": errors, "stats": st, "cuts": cuts,
            "log": lg + pop_log(), "document": doc}


def review(spec_path, out_dir, prefix="review", views=None, final=False):
    spec = _spec(spec_path)
    files = _render.render_views(spec, out_dir, prefix, views or _render.VIEWS, final=final)
    return {"renders": files, "log": pop_log()}


def rig(spec_path):
    """Merge layers -> per-slot UVs -> armature with moving-part bones + sockets -> rigid weights."""
    spec = _spec(spec_path)
    obj, qa = _rig.merge(spec)
    if spec.get("auto_unwrap", True):
        _rig.unwrap_per_slot(obj)
    _rig.fix_uvs(obj)
    arm, info = _rig.build_armature(spec, obj)
    return obj, arm, qa, info


def pose(spec_path, values):
    """Preview: veh.pose(SPEC, {"door_FL": 1.0, "steer_FL": 0.0}) on the current rig (others at rest)."""
    import bpy
    spec = _spec(spec_path)
    arm = bpy.data.objects.get(f"{spec.get('asset', 'Vehicle')}_Rig")
    _rig.reset_pose(arm)
    _rig.set_pose(spec, arm, values)
    return {"posed": values}


def animate(spec_path, arm=None):
    import bpy
    spec = _spec(spec_path)
    arm = arm or bpy.data.objects.get(f"{spec.get('asset', 'Vehicle')}_Rig")
    return _anim.build_actions(spec, arm)


def save_project(spec_path):
    """Snapshot of the whole scene as <spec folder>/<asset>.blend (copy: the open file keeps its name)."""
    import bpy
    spec = _spec(spec_path)
    path = spec.get("blend_path") or os.path.join(spec.get("_dir") or os.getcwd(),
                                                  f"{spec.get('asset', 'Vehicle')}.blend")
    if not os.path.isabs(path):
        path = os.path.join(spec.get("_dir", ""), path)
    try:
        bpy.ops.wm.save_as_mainfile(filepath=path, copy=True, compress=True)
        log(f"Project .blend saved: {path}")
        return path
    except Exception as e:  # noqa
        log(f"Could not save the project .blend: {e}")
        return None


def finalize(spec_path, out_dir, render_dir=None):
    """Rig -> animations -> motion check -> LODs -> FBX (+takes) -> glb -> rigid hierarchy -> .blend -> document."""
    import bpy
    spec = _spec(spec_path)
    asset = spec.get("asset", "Vehicle")
    kept = {}
    if spec.get("lock_animations"):
        kept = {a.name: a for a in bpy.data.actions if a.name.startswith(f"A_{asset}_")}
    obj, arm, qa, info = rig(spec)
    if spec.get("lock_animations") and kept:
        anims = {a.name.replace(f"A_{asset}_", ""): {"action": a.name, "frames": int(a.frame_range[1]),
                                                       "parts": [], "locked": True} for a in kept.values()}
        log("Animations locked: existing actions kept.")
    else:
        anims = _anim.build_actions(spec, arm)
    motion = _check.motion_check(spec) if spec.get("motion_check", True) else {}
    lods, lod_report = _export.make_lods(spec, obj)
    files = _export.export_fbx(spec, arm, lods, out_dir)
    if spec.get("export_gltf", True):
        g = _export.export_gltf(spec, arm, obj, out_dir)
        if g:
            files.append(g)
    if spec.get("export_rigid", True):
        files += _export.export_rigid(spec, arm, obj, out_dir)
    renders = []
    if render_dir:
        renders = _render.render_views(spec, render_dir, "final", final=True)
        for a in spec.get("animations", []):
            if a.get("render", True) and a.get("preset") != "idle":
                renders += _render.render_animation(spec, arm, a["name"], render_dir)
    res = {"qa": qa, "rig": info, "animations": anims, "motion_check": motion, "lods": lod_report,
           "fbx": files, "renders": renders}
    if spec.get("save_blend", True):
        res["blend"] = save_project(spec)
    doc = _doc(spec, "finalize", res)
    res.update({"log": pop_log(), "document": doc})
    return res


def document(spec_path):
    spec = _spec(spec_path)
    return {"document": docs.write_doc(spec), "log": pop_log()}


def dump(result):
    return json.dumps(result, indent=1, ensure_ascii=False, default=str)
