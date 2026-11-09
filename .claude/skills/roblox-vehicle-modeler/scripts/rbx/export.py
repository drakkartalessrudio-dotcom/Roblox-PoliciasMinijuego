"""Roblox export of a `veh` vehicle (runs inside Blender).

    pieces (Chassis, Windows, Trim, Lights, Bumpers, Tire_xx, Rim_xx, Roof, Bed, Neon)
      -> one flat-colour mesh each, in studs, in the Roblox model frame yawed 180 degrees (Studio's importer yaws it back: nose = -Z, up = +Y, right = +X)
      -> `<Asset>_Roblox.fbx` with clean nodes (no rotation, no scale), then re-read and compared with the manifest
      -> `<Asset>.manifest.json` (schema 2, see references/manifest-format.md)

Wheels: each Tire/Rim is centred on its hub (vertices local, node translation = hub) so it spins on its own axis.
"""
from __future__ import annotations

import json
import os

import bmesh
import bpy

from . import frame, groups, manifest as manifest_mod

K = 1.0 / frame.STUD_CM  # cm -> studs
VERIFY_TOLERANCE = 0.02  # studs


def _eval_mesh(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, depsgraph=dg)
    me.transform(ob.matrix_world)
    return me


def collect_pieces(veh, prepared_spec: dict) -> dict:
    """{piece name: bmesh in vehicle space (cm), triangulated}."""
    override = {p["id"]: p.get("rbx_group") for p in prepared_spec.get("parts", []) if p.get("rbx_group")}
    by_piece: dict[str, list] = {}
    for ob in veh.objects_in_layers():
        if ob.hide_render:
            continue
        material = ob.data.materials[0].name if ob.data.materials and ob.data.materials[0] else ""
        piece = groups.piece_of(
            ob["veh_layer"], ob["veh_spec_part"], ob["veh_part"], material, override.get(ob["veh_spec_part"])
        )
        by_piece.setdefault(piece, []).append(_eval_mesh(ob))
    out = {}
    for piece, meshes in by_piece.items():
        bm = bmesh.new()
        for me in meshes:
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        out[piece] = bm
    return out


def recenter(pieces: dict) -> list[float]:
    """Moves every piece so the origin is the ground under the centre of the car (x, y); z = 0 stays on the ground.
    Specs usually model from the rear bumper (x = 0), and the Roblox side wants the pivot in the middle.
    Returns the offset (cm, vehicle space) that was subtracted, to apply the same shift to the sockets."""
    los, his = [], []
    for bm in pieces.values():
        lo, hi = _bbox(bm)
        los.append(lo)
        his.append(hi)
    lo = [min(c[i] for c in los) for i in range(3)]
    hi = [max(c[i] for c in his) for i in range(3)]
    offset = [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, 0.0]
    for bm in pieces.values():
        for v in bm.verts:
            v.co = [v.co[i] - offset[i] for i in range(3)]
    return offset


def _bbox(bm):
    xs = [v.co for v in bm.verts]
    lo = [min(c[i] for c in xs) for i in range(3)]
    hi = [max(c[i] for c in xs) for i in range(3)]
    return lo, hi


def measure(pieces: dict) -> dict:
    """Vehicle-space measurements in studs: {piece: {tris, center, size}}."""
    measured = {}
    for name, bm in pieces.items():
        lo, hi = _bbox(bm)
        measured[name] = {
            "tris": len(bm.faces),
            "center": [(lo[i] + hi[i]) / 2 * K for i in range(3)],
            "size": [(hi[i] - lo[i]) * K for i in range(3)],
        }
    return measured


def measure_sockets(prepared_spec: dict, offset_cm: list[float]) -> dict:
    sockets = {}
    for s in prepared_spec.get("sockets", []):
        p = s.get("at_3d") or [s["at"][0], s.get("y_cm", 0), s["at"][1]]
        sockets[s["name"]] = [(p[i] - offset_cm[i]) * K for i in range(3)]
    return sockets


def _assign_material(ob, asset: str, kind: str, info: dict):
    """One flat-colour material per piece so the FBX imports already coloured (Luau re-applies Color/Material)."""
    name = f"{asset}_{kind}"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    lin = [(c / 255.0) ** 2.2 for c in info["color"]]
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.25 if info["material"] in ("Glass", "Metal") else 0.6
    bsdf.inputs["Metallic"].default_value = 0.8 if info["material"] == "Metal" else 0.0
    bsdf.inputs["Alpha"].default_value = 1.0 - info["transparency"]
    if info["material"] == "Neon":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    mat.diffuse_color = (*lin, 1.0 - info["transparency"])
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.material_index = 0


def _build_objects(asset: str, pieces: dict, measured: dict, manifest: dict) -> list:
    """Scene objects in studs and in the Blender scene frame that the exporter turns into the Roblox frame."""
    objects = []
    for name, bm in pieces.items():
        center_v = measured[name]["center"]  # studs, vehicle space
        is_wheel = name.startswith(("Tire_", "Rim_"))
        origin_cm = [c / K for c in center_v] if is_wheel else [0.0, 0.0, 0.0]
        for v in bm.verts:
            local = [(v.co[i] - origin_cm[i]) * K for i in range(3)]
            v.co = frame.point_to_blender_export(local)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        if is_wheel:
            ob.location = frame.point_to_blender_export(center_v)
        _assign_material(ob, asset, groups.kind_of(name), manifest["parts"][name])
        objects.append(ob)
    return objects


# --- FBX re-read ------------------------------------------------------------------------------------------------

def _fbx_pieces(path: str) -> dict:
    """{name: {'bbox': (lo, hi) in the file frame, 'rotation': [...], 'scaling': [...]}} read from the raw FBX."""
    from io_scene_fbx import parse_fbx

    root, _version = parse_fbx.parse(path)
    objects = next(e for e in root.elems if e.id == b"Objects")
    connections = next(e for e in root.elems if e.id == b"Connections")
    geometry, models = {}, {}
    for e in objects.elems:
        if e.id == b"Geometry":
            verts = next(c for c in e.elems if c.id == b"Vertices").props[0]
            geometry[e.props[0]] = list(verts)
        elif e.id == b"Model":
            name = e.props[1].split(b"\x00")[0].decode()
            props = {"Lcl Translation": [0.0, 0.0, 0.0], "Lcl Rotation": [0.0, 0.0, 0.0], "Lcl Scaling": [1.0, 1.0, 1.0]}
            p70 = next((c for c in e.elems if c.id == b"Properties70"), None)
            for pe in (p70.elems if p70 else []):
                key = pe.props[0].decode() if pe.props else ""
                if key in props:
                    props[key] = [float(x) for x in pe.props[4:7]]
            models[e.props[0]] = (name, props)
    result = {}
    for c in connections.elems:
        if c.id == b"C" and c.props[0] == b"OO" and c.props[1] in geometry and c.props[2] in models:
            name, props = models[c.props[2]]
            v = geometry[c.props[1]]
            t = props["Lcl Translation"]
            lo = [min(v[i::3]) + t[i] for i in range(3)]
            hi = [max(v[i::3]) + t[i] for i in range(3)]
            result[name] = {"bbox": (lo, hi), "rotation": props["Lcl Rotation"], "scaling": props["Lcl Scaling"]}
    return result


def verify_fbx(path: str, manifest: dict) -> list[str]:
    """Problems found comparing the written FBX with the manifest (empty = the file matches)."""
    try:
        found = _fbx_pieces(path)
    except Exception as exc:  # noqa: BLE001 - the FBX reader is Blender's own add-on; report, do not crash
        return [f"could not re-read the FBX to verify its axes: {exc}"]
    problems = []
    for name, info in manifest["parts"].items():
        piece = found.get(name)
        if not piece:
            problems.append(f"FBX has no piece '{name}'")
            continue
        if any(abs(a) > 1e-3 for a in piece["rotation"]) or any(abs(s - 1) > 1e-3 for s in piece["scaling"]):
            problems.append(f"{name}: node has rotation {piece['rotation']} / scaling {piece['scaling']} (must be identity)")
        lo, hi = piece["bbox"]
        center = [(lo[i] + hi[i]) / 2 for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        expected = frame.point_to_file(info["center"])
        for axis in range(3):
            if abs(center[axis] - expected[axis]) > VERIFY_TOLERANCE:
                problems.append(f"{name}: centre {['x', 'y', 'z'][axis]} is {center[axis]:.3f} in the file, expected {expected[axis]:.3f} (manifest {info['center'][axis]} yawed 180)")
            if abs(size[axis] - info["size"][axis]) > VERIFY_TOLERANCE:
                problems.append(f"{name}: size {['x', 'y', 'z'][axis]} is {size[axis]:.3f} in the file, manifest says {info['size'][axis]}")
    return problems


# --- entry point ------------------------------------------------------------------------------------------------

def export_roblox(veh, spec_path: str, export_dir: str, asset: str | None = None) -> dict:
    """Writes the FBX and the manifest into `export_dir`. Returns the manifest (with `verify` problems, if any)."""
    with open(spec_path, encoding="utf-8") as fh:
        spec = json.load(fh)
    asset = asset or spec["asset"]
    prepared = veh.common.prepare(json.loads(json.dumps(spec)))
    os.makedirs(export_dir, exist_ok=True)

    pieces = collect_pieces(veh, prepared)
    offset_cm = recenter(pieces)
    measured = measure(pieces)
    fbx_name = f"{asset}_Roblox.fbx"
    manifest = manifest_mod.build(asset, spec, measured, measure_sockets(prepared, offset_cm), fbx_name)

    objects = _build_objects(asset, pieces, measured, manifest)
    scene = bpy.context.scene
    previous_scale = scene.unit_settings.scale_length
    scene.unit_settings.scale_length = 1.0  # 1 Blender unit = 1 stud; veh works in cm, so restore afterwards
    try:
        bpy.ops.object.select_all(action="DESELECT")
        for ob in objects:
            ob.select_set(True)
        fbx_path = os.path.join(export_dir, fbx_name)
        bpy.ops.export_scene.fbx(
            filepath=fbx_path, use_selection=True, object_types={"MESH"},
            global_scale=1.0, apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS",
            bake_space_transform=True, axis_forward="-Z", axis_up="Y",
            mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
        )
    finally:
        scene.unit_settings.scale_length = previous_scale
        for ob in objects:
            bpy.data.objects.remove(ob, do_unlink=True)

    manifest["verify"] = verify_fbx(fbx_path, manifest)
    manifest_path = os.path.join(export_dir, f"{asset}.manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, ensure_ascii=False)
    return manifest
