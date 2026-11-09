"""Vehicle rig: merge layers into one skinned mesh, one bone per MOVING part, socket bones, rigid weights.

Bone rules
  b_root (origin) -> b_body (all static parts) -> b_<part> for every part with "motion".
  A moving part's bone parents to the bone of its nearest moving ancestor ('parent' chain), else b_body
  (e.g. b_susp_FL -> b_steer_FL -> b_wheel_FL; b_gear_L -> b_gear_door_L).
  Static parts are weighted 100 % to the bone of their nearest moving ancestor, else b_body.
  Sockets (Seat_Driver, Exhaust_L, Muzzle, Headlight_L, Enter_L, Camera...) are non-deforming bones.
Bone orientation
  Named axis (X/Y/Z): bone along +Y, roll 0 -> bone-local axes == vehicle axes.
  Vector axis [x, y, z] (swept hinge lines: ailerons, raked doors): bone Y points along the hinge, and the motion
  is keyed on the bone's local Y (rotation or translation).
"""
import json
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from .common import LAYER_NAMES, SLOT_ORDER, Views, cm, get_collection, log, objects_in_layers, remove_object

AXIS_INDEX = {"X": 0, "Y": 1, "Z": 2}


def parts_by_id(spec):
    return {p["id"]: p for p in spec.get("parts", []) if p.get("enabled", True) is not False}


def moving(part):
    return bool(part and part.get("motion"))


def bone_of(spec, pid, parts=None):
    parts = parts or parts_by_id(spec)
    seen = 0
    p = parts.get(pid)
    while p is not None and seen < 50:
        if moving(p):
            return "b_" + p["id"]
        p = parts.get(p.get("parent"))
        seen += 1
    return "b_body"


def parent_bone(spec, part, parts=None):
    parts = parts or parts_by_id(spec)
    par = part.get("parent")
    return bone_of(spec, par, parts) if par else "b_body"


def _part_objects(pid):
    return [o for o in objects_in_layers() if o.get("veh_spec_part") == pid]


def _bbox(objs):
    """World bbox from EVALUATED objects (modifiers applied); ignores non-finite corners."""
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    pts = []
    for o in objs:
        ev = o.evaluated_get(dg)
        for c in ev.bound_box:
            p = ev.matrix_world @ Vector(c)
            if all(math.isfinite(v) and abs(v) < 1e12 for v in p):
                pts.append(p)
    if not pts:
        return Vector(), Vector()
    return Vector(map(min, *pts)), Vector(map(max, *pts))


def axis_vector(m):
    ax = m.get("axis", "X")
    if isinstance(ax, (list, tuple)):
        return Vector(ax).normalized()
    return Vector({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[ax])


def key_index(m):
    """Channel index keyed on the bone: named axis -> that axis; vector axis -> local Y (1)."""
    ax = m.get("axis", "X")
    return 1 if isinstance(ax, (list, tuple)) else AXIS_INDEX[ax]


def pivot(spec, part, views=None):
    """World pivot: motion.pivot_3d [x,y,z] cm, or side 'pivot' [x,z] + pivot_y_cm (default part y_cm),
    or the part's bbox center (wheels: the hub)."""
    m = part["motion"]
    views = views or Views(spec)
    if "pivot_3d" in m:
        return Vector([cm(v) for v in m["pivot_3d"]])
    if "pivot" in m:
        x, z = views.to_xz(m["pivot"], part.get("space", spec.get("default_space", "cm")))
        y = m.get("pivot_y_cm", part.get("y_cm", part.get("center_cm", [0, 0, 0])[1]))
        return Vector((x, cm(y), z))
    lo, hi = _bbox(_part_objects(part["id"]))
    return (lo + hi) / 2


def motion_value(part, v):
    """Normalized v (0..1) -> radians (rotate) or BU (translate)."""
    m = part["motion"]
    a = m.get("min", 0.0) + (m.get("max", 0.0) - m.get("min", 0.0)) * v
    return math.radians(a) if m["type"] == "rotate" else cm(a)


def rest_value(part):
    """Normalized value of the modeled pose (0 deg / 0 cm), e.g. 0.5 for steering -35..35."""
    m = part["motion"]
    lo, hi = m.get("min", 0.0), m.get("max", 0.0)
    return 0.0 if hi == lo else min(max((0.0 - lo) / (hi - lo), 0.0), 1.0)


def motion_matrix(spec, part, v, views=None):
    m = part["motion"]
    ax = axis_vector(m)
    val = motion_value(part, v)
    if m["type"] == "rotate":
        p = pivot(spec, part, views)
        return Matrix.Translation(p) @ Matrix.Rotation(val, 4, ax) @ Matrix.Translation(-p)
    return Matrix.Translation(ax * val)


def chain_matrix(spec, pid, values, parts=None, views=None):
    """World matrix of part 'pid' given normalized values for moving parts (parents first)."""
    parts = parts or parts_by_id(spec)
    chain = []
    p = parts.get(pid)
    while p is not None and len(chain) < 50:
        if moving(p):
            chain.append(p)
        p = parts.get(p.get("parent"))
    M = Matrix.Identity(4)
    for q in reversed(chain):  # root-most first
        M = M @ motion_matrix(spec, q, values.get(q["id"], rest_value(q)), views)
    return M


def origin_point(spec):
    """Asset origin: origin_cm [x,y,z]; or socket 'origin_socket'; default = ground point under the bbox center."""
    if spec.get("origin_cm"):
        return Vector([cm(v) for v in spec["origin_cm"]])
    name = spec.get("origin_socket")
    if name:
        for s in spec.get("sockets", []):
            if s["name"] == name:
                return socket_point(spec, s)
    lo, hi = _bbox(objects_in_layers())
    return Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))


def socket_point(spec, s, views=None):
    if "at_3d" in s:
        return Vector([cm(v) for v in s["at_3d"]])
    views = views or Views(spec)
    x, z = views.to_xz(s["at"], s.get("space", spec.get("default_space", "cm")))
    return Vector((x, cm(s.get("y_cm", 0.0)), z))


# ----------------------------------------------------------------------------- merge

def merge(spec):
    asset = spec.get("asset", "Vehicle")
    name = f"SK_{asset}"
    for o in [o for o in bpy.data.objects if o.name == name or o.name.startswith(name + "_LOD")]:
        remove_object(o)
    parts = parts_by_id(spec)
    objs = [o for o in objects_in_layers() if o.type == "MESH" and o.get("veh_spec_part") in parts
            and not o.hide_render]
    if not objs:
        raise RuntimeError("No parts in LAYERS to merge.")
    org = origin_point(spec)
    dg = bpy.context.evaluated_depsgraph_get()
    slot_index = {s: i for i, s in enumerate(SLOT_ORDER)}
    bm = bmesh.new()
    ranges = {}
    for o in objs:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        if any(not math.isfinite(c) or abs(c) > 1e7 for v in me.vertices for c in v.co):
            bev = o.modifiers.get("VEH_Bevel")
            log(f"WARNING: {o.name} evaluated to invalid coordinates; retrying with a sharp-miter bevel.")
            bpy.data.meshes.remove(me)
            if bev is not None:
                bev.miter_outer = "MITER_SHARP"
            dg = bpy.context.evaluated_depsgraph_get()
            dg.update()
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(Matrix.Translation(-org) @ o.matrix_world)
        while len(me.uv_layers) > 1:
            me.uv_layers.remove(me.uv_layers[-1])
        if not me.uv_layers:
            me.uv_layers.new(name="UVMap")
        me.uv_layers[0].name = "UVMap"
        local = [m.name.split(".")[0] if m else "MI_Body" for m in me.materials]
        mi = [0] * len(me.polygons)
        me.polygons.foreach_get("material_index", mi)
        me.polygons.foreach_set("material_index", [slot_index.get(local[i] if i < len(local) else "MI_Body", 0)
                                                   for i in mi])
        start = len(bm.verts)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        lay = bm.verts.layers.int.get("veh_layer") or bm.verts.layers.int.new("veh_layer")
        li = LAYER_NAMES.index(o.get("veh_layer", "L1_Body")) if o.get("veh_layer") in LAYER_NAMES else 1
        bm.verts.ensure_lookup_table()
        for i in range(start, len(bm.verts)):
            bm.verts[i][lay] = li
        bone = bone_of(spec, o["veh_spec_part"], parts)
        ranges.setdefault(bone, []).append((start, len(bm.verts)))
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons, quad_method="BEAUTY", ngon_method="BEAUTY")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for s in SLOT_ORDER:
        me.materials.append(bpy.data.materials.get(s))
    obj = bpy.data.objects.new(name, me)
    get_collection("EXPORT").objects.link(obj)
    obj["veh_role"] = "export"
    for bone, rs in ranges.items():
        vg = obj.vertex_groups.new(name=bone)
        for a, b in rs:
            vg.add(list(range(a, b)), 1.0, "REPLACE")
    used = sorted({p.material_index for p in me.polygons})
    if used != list(range(len(SLOT_ORDER))):
        remap = {old: new for new, old in enumerate(used)}
        idx = [remap[p.material_index] for p in me.polygons]
        keep = [me.materials[i] for i in used]
        me.materials.clear()
        for m in keep:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", idx)
    report = {"tris": sum(len(p.vertices) - 2 for p in me.polygons), "verts": len(me.vertices),
              "slots": [m.name for m in me.materials], "bones_weighted": sorted(ranges),
              "origin_cm": [round(v / cm(1), 2) for v in org]}
    log(f"Merged {name}: {report}")
    return obj, report


def _uv_buf(obj):
    uvl = obj.data.uv_layers.active or (obj.data.uv_layers[0] if obj.data.uv_layers else None)
    if uvl is None:
        return None
    buf = [0.0] * (2 * len(uvl.data))
    uvl.data.foreach_get("uv", buf)
    return buf


def fix_uvs(obj, fallback=None):
    """Replace NaN/inf UVs (smart_project on degenerate faces) with the pre-unwrap box UVs (or 0) so the
    FBX export does not fail and those faces keep usable UVs."""
    bad = 0
    for uvl in obj.data.uv_layers:
        n = len(uvl.data)
        buf = [0.0] * (2 * n)
        uvl.data.foreach_get("uv", buf)
        fb = fallback if fallback is not None and len(fallback) == len(buf) else None
        clean = [v if math.isfinite(v) else ((fb[i] if math.isfinite(fb[i]) else 0.0) if fb else 0.0)
                 for i, v in enumerate(buf)]
        bad += sum(1 for a, b in zip(buf, clean) if a != b or not math.isfinite(a))
        uvl.data.foreach_set("uv", clean)
    if bad:
        log(f"Fixed {bad} invalid UV values on {obj.name}")
    return bad


def unwrap_per_slot(obj, angle=66.0, margin=0.003):
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    vl.objects.active = obj
    obj.select_set(True)
    ok = 0
    before = _uv_buf(obj)
    try:
        with bpy.context.temp_override(active_object=obj, object=obj, selected_objects=[obj]):
            bpy.ops.object.mode_set(mode="EDIT")
            for i in range(len(obj.data.materials)):
                bpy.ops.mesh.select_all(action="DESELECT")
                obj.active_material_index = i
                bpy.ops.object.material_slot_select()
                bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin,
                                         scale_to_bounds=False, correct_aspect=True)
                ok += 1
            bpy.ops.object.mode_set(mode="OBJECT")
        fix_uvs(obj, before)
    except Exception as e:  # noqa
        try:
            bpy.ops.object.mode_set(mode="OBJECT")
        except Exception:  # noqa
            pass
        log(f"Auto UV failed ({e}); keeping per-part box UVs.")
    return ok


# ----------------------------------------------------------------------------- armature

def build_armature(spec, mesh_obj=None):
    asset = spec.get("asset", "Vehicle")
    name = f"{asset}_Rig"
    old = bpy.data.objects.get(name)
    if old:
        remove_object(old)
    parts = parts_by_id(spec)
    views = Views(spec)
    org = origin_point(spec)
    Lb = cm(spec.get("bone_length_cm", 20.0))
    arm_data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, arm_data)
    get_collection("EXPORT").objects.link(arm)
    arm["veh_role"] = "rig"
    vl = bpy.context.view_layer
    vl.objects.active = arm
    arm.select_set(True)
    with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=[arm]):
        bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def add(bname, head, parent, deform=True, direction=None):
        b = eb.new(bname)
        b.head = head
        b.tail = head + (direction or Vector((0, 1, 0))) * Lb
        b.roll = 0.0
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
        return b

    add("b_root", Vector(), None)
    add("b_body", Vector(), "b_root")
    order, done = [], set()

    def visit(p):
        if p["id"] in done:
            return
        par = parts.get(p.get("parent"))
        if par is not None:
            visit(par)
        done.add(p["id"])
        order.append(p)

    for p in parts.values():
        visit(p)
    tree = {}
    for p in order:
        if moving(p):
            pb = parent_bone(spec, p, parts)
            ax = p["motion"].get("axis", "X")
            direction = axis_vector(p["motion"]) if isinstance(ax, (list, tuple)) else None
            add("b_" + p["id"], pivot(spec, p, views) - org, pb, direction=direction)
            tree["b_" + p["id"]] = pb
    sockets = {}
    for s in spec.get("sockets", []):
        pb = bone_of(spec, s["parent"], parts) if s.get("parent") else "b_body"
        add(s["name"], socket_point(spec, s, views) - org, pb, deform=False)
        sockets[s["name"]] = pb
    with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=[arm]):
        bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    if mesh_obj is not None:
        mesh_obj.parent = arm
        mod = next((m for m in mesh_obj.modifiers if m.type == "ARMATURE"), None) or \
            mesh_obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    arm["veh_tree"] = json.dumps(tree)
    arm["veh_sockets"] = json.dumps(sockets)
    log(f"Rig {name}: {len(arm_data.bones)} bones ({len(tree)} moving, {len(sockets)} sockets)")
    return arm, {"moving_bones": tree, "sockets": sockets}


def set_pose(spec, arm, values):
    """values: {part_id: v 0..1}. Applies motion to pose bones (others untouched)."""
    parts = parts_by_id(spec)
    for pid, v in values.items():
        p = parts[pid]
        pb = arm.pose.bones.get("b_" + pid)
        if pb is None:
            continue
        i = key_index(p["motion"])
        val = motion_value(p, v)
        if p["motion"]["type"] == "rotate":
            pb.rotation_euler[i] = val
        else:
            pb.location[i] = val


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
