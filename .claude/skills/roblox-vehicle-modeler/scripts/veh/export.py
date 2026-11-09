"""LODs and FBX export (skeletal mesh + one take per animation) for Unreal."""
import json
import os

import bmesh
import bpy
from mathutils import Matrix

from .common import get_collection, log, remove_object

DEFAULT_LODS = [1.0, 0.5, 0.25, 0.12]


def make_lods(spec, obj):
    ratios = spec.get("lod_ratios", DEFAULT_LODS)
    base = obj.name
    lods, report = [obj], {}
    for i, r in enumerate(ratios[1:], start=1):
        name = f"{base}_LOD{i}"
        old = bpy.data.objects.get(name)
        if old:
            remove_object(old)
        lo = obj.copy()
        lo.data = obj.data.copy()
        lo.name = name
        get_collection("EXPORT").objects.link(lo)
        dropped = _drop_layers(spec, lo, i)
        arm_mods = [(m.name, m.object) for m in lo.modifiers if m.type == "ARMATURE"]
        for m in [m for m in lo.modifiers if m.type == "ARMATURE"]:
            lo.modifiers.remove(m)
        d = lo.modifiers.new("VEH_LOD", "DECIMATE")
        d.ratio = r
        d.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(lo.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        lo.modifiers.clear()
        old_me = lo.data
        lo.data = me
        me.name = name
        bpy.data.meshes.remove(old_me)
        for n, a in arm_mods:
            m = lo.modifiers.new(n, "ARMATURE")
            m.object = a
        lods.append(lo)
        report[name] = sum(len(p.vertices) - 2 for p in me.polygons)
        if dropped:
            report[name + "_dropped_layers"] = dropped
    report[base + "_LOD0"] = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if not base.endswith("_LOD0"):
        obj.name = base + "_LOD0"
    log(f"LODs: {report}")
    return lods, report


DEFAULT_LOD_DROP = {"L5_Interior": 2, "L8_Details": 3}


def _drop_layers(spec, obj, lod):
    """Remove whole layers from a LOD (interior from LOD2, small details from LOD3 by default)."""
    from .common import LAYER_NAMES
    drop = spec.get("lod_drop_layers", DEFAULT_LOD_DROP)
    idx = {LAYER_NAMES.index(k) for k, v in drop.items() if k in LAYER_NAMES and lod >= v}
    attr = obj.data.attributes.get("veh_layer")
    if not idx or attr is None:
        return []
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    lay = bm.verts.layers.int.get("veh_layer")
    dead = [v for v in bm.verts if v[lay] in idx]
    bmesh.ops.delete(bm, geom=dead, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    return sorted(LAYER_NAMES[i] for i in idx)


def export_fbx(spec, arm, meshes, out_dir):
    """LOD0 exports with every animation as its own take; LOD1..n export mesh only (import as LODs in UE)."""
    os.makedirs(out_dir, exist_ok=True)
    original = arm.name
    arm.name = "Armature"  # Unreal skips a root node named 'Armature' -> b_root becomes the root bone
    scale = bpy.context.scene.unit_settings.scale_length
    apply_scale = "FBX_SCALE_NONE" if abs(scale - 0.01) < 1e-6 else "FBX_SCALE_UNITS"
    vl = bpy.context.view_layer
    files = []
    if arm.animation_data:
        arm.animation_data.action = None
    try:
        for i, m in enumerate(meshes):
            for o in vl.objects:
                o.select_set(False)
            arm.select_set(True)
            m.select_set(True)
            vl.objects.active = arm
            fp = os.path.join(out_dir, m.name + ".fbx")
            with bpy.context.temp_override(selected_objects=[arm, m], active_object=arm, object=arm):
                _fbx(spec, fp, apply_scale, i)
            files.append(fp)
    finally:
        arm.name = original
    with open(os.path.join(out_dir, "export_report.json"), "w", encoding="utf-8") as f:
        json.dump({"files": files, "apply_scale_options": apply_scale}, f, indent=1)
    log(f"FBX exported: {files}")
    return files


def _fbx(spec, fp, apply_scale, i):
    bpy.ops.export_scene.fbx(
        filepath=fp, use_selection=True, object_types={"ARMATURE", "MESH"},
        apply_scale_options=apply_scale,
        axis_forward=spec.get("fbx_axis_forward", "-Z"), axis_up=spec.get("fbx_axis_up", "Y"),
        add_leaf_bones=False, use_armature_deform_only=False,  # keep socket bones
        bake_anim=(i == 0 and bool(spec.get("animations"))),
        bake_anim_use_all_actions=True, bake_anim_use_nla_strips=False,
        bake_anim_force_startend_keying=True, bake_anim_simplify_factor=0.0,
        mesh_smooth_type="FACE", use_tspace=True, use_mesh_modifiers=False,
        primary_bone_axis="Y", secondary_bone_axis="X")


def export_gltf(spec, arm, mesh, out_dir):
    """SK_<asset>.glb (LOD0 + every action as a glTF animation) in METERS for Godot / Unity (glTFast) / web.

    glTF has no unit setting: the rig object is temporarily scaled by the scene unit scale (0.01) so the file
    is in meters, then restored. Root node = the rig (b_root at the grip / origin)."""
    os.makedirs(out_dir, exist_ok=True)
    fp = os.path.join(out_dir, f"SK_{spec.get('asset', 'Vehicle')}.glb")
    scale = bpy.context.scene.unit_settings.scale_length or 1.0
    old_scale, old_name = arm.scale.copy(), arm.name
    vl = bpy.context.view_layer
    if arm.animation_data:
        arm.animation_data.action = None
    try:
        arm.scale = old_scale * scale
        arm.name = f"{spec.get('asset', 'Vehicle')}_Rig"
        for o in vl.objects:
            o.select_set(False)
        arm.select_set(True)
        mesh.select_set(True)
        vl.objects.active = arm
        with bpy.context.temp_override(selected_objects=[arm, mesh], active_object=arm, object=arm):
            _gltf(fp)
        log(f"glTF exported: {fp}")
        return fp
    except Exception as e:  # noqa
        log(f"WARNING: glTF export failed: {e}")
        return None
    finally:
        arm.scale = old_scale
        arm.name = old_name


def _gltf(fp):
    bpy.ops.export_scene.gltf(filepath=fp, export_format="GLB", use_selection=True, export_yup=True,
                          export_apply=False, export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=True, export_def_bones=False, export_leaf_bone=False,
                          export_anim_slide_to_zero=True)


# ----------------------------------------------------------------------------- rigid hierarchy

def _rigid_set(spec, arm, mesh, f, tag):
    """One mesh object per bone group (body + every moving part), origin at the pivot, parented like the bones;
    sockets as empties. f = length factor (1 = BU/cm for FBX, scene scale for glb meters)."""
    asset = spec.get("asset", "Vehicle")
    col = get_collection("_RIGID_TMP")
    me = mesh.data
    names = {g.index: g.name for g in mesh.vertex_groups}
    vg_of = [max(v.groups, key=lambda g: g.weight).group if v.groups else -1 for v in me.vertices]
    face_group = [vg_of[p.vertices[0]] for p in me.polygons]
    bones = arm.data.bones
    objs = {}

    def obj_name(bone):
        return f"{asset}_Body" if bone == "b_body" else bone[2:]

    order = [b.name for b in bones]  # parents come first in Blender's bone list order
    for bname in order:
        b = bones[bname]
        if bname == "b_root" or not b.use_deform:
            continue
        gi = next((i for i, n in names.items() if n == bname), None)
        bm = bmesh.new()
        if gi is not None:
            bm.from_mesh(me)
            dead = [fc for fc, g in zip(bm.faces, face_group) if g != gi]
            bmesh.ops.delete(bm, geom=dead, context="FACES")
            loose = [v for v in bm.verts if not v.link_faces]
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        head = b.head_local.copy()
        bmesh.ops.transform(bm, matrix=Matrix.Scale(f, 4) @ Matrix.Translation(-head), verts=bm.verts[:])
        m2 = bpy.data.meshes.new(f"{obj_name(bname)}{tag}")
        bm.to_mesh(m2)
        bm.free()
        m2.validate(clean_customdata=False)
        for mat in me.materials:
            m2.materials.append(mat)
        o = bpy.data.objects.new(obj_name(bname), m2)
        col.objects.link(o)
        par = b.parent.name if b.parent and b.parent.name != "b_root" else None
        if par and par in objs:
            o.parent = objs[par]
            o.location = (head - bones[par].head_local) * f
        else:
            o.location = head * f
        objs[bname] = o
    for b in bones:
        if b.use_deform or b.name == "b_root":
            continue
        e = bpy.data.objects.new(b.name, None)
        e.empty_display_size = 10 * f
        col.objects.link(e)
        par = b.parent.name if b.parent else None
        if par in objs:
            e.parent = objs[par]
            e.location = (b.head_local - bones[par].head_local) * f
        else:
            e.location = b.head_local * f
        objs[b.name] = e
    return list(objs.values())


def _clear_rigid():
    col = bpy.data.collections.get("_RIGID_TMP")
    if not col:
        return
    for o in list(col.objects):
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)
    bpy.data.collections.remove(col)


def export_rigid(spec, arm, mesh, out_dir):
    """<asset>_Rigid.fbx (cm) + <asset>_Rigid.glb (m): separate objects per moving part, pivots at the hinges,
    no skinning — for physics vehicles (Unity WheelCollider, Godot VehicleBody3D/VehicleWheel3D, UEFN props)."""
    os.makedirs(out_dir, exist_ok=True)
    asset = spec.get("asset", "Vehicle")
    files = []
    vl = bpy.context.view_layer
    try:
        _clear_rigid()
        objs = _rigid_set(spec, arm, mesh, 1.0, "_fbx")
        fp = os.path.join(out_dir, f"{asset}_Rigid.fbx")
        for o in vl.objects:
            o.select_set(False)
        for o in objs:
            o.select_set(True)
        with bpy.context.temp_override(selected_objects=objs, active_object=objs[0], object=objs[0]):
            bpy.ops.export_scene.fbx(filepath=fp, use_selection=True, object_types={"MESH", "EMPTY"},
                                     apply_scale_options="FBX_SCALE_NONE", axis_forward="-Z", axis_up="Y",
                                     bake_anim=False, mesh_smooth_type="FACE", use_tspace=True,
                                     use_mesh_modifiers=False)
        files.append(fp)
        _clear_rigid()
        scale = bpy.context.scene.unit_settings.scale_length or 1.0
        objs = _rigid_set(spec, arm, mesh, scale, "_glb")
        for o in vl.objects:
            o.select_set(False)
        for o in objs:
            o.select_set(True)  # the glTF exporter reads the real selection
        fp = os.path.join(out_dir, f"{asset}_Rigid.glb")
        with bpy.context.temp_override(selected_objects=objs, active_object=objs[0], object=objs[0]):
            bpy.ops.export_scene.gltf(filepath=fp, export_format="GLB", use_selection=True, export_yup=True,
                                      export_apply=False, export_animations=False)
        files.append(fp)
        log(f"Rigid hierarchy exported: {files}")
    except Exception as e:  # noqa
        log(f"WARNING: rigid export failed: {e}")
    finally:
        _clear_rigid()
    return files
