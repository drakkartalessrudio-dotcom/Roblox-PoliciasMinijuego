"""Review renders: vehicle views (side, front, rear, top, three-quarter) and animation frame strips."""
import os

import bpy
from mathutils import Vector

from .common import log, objects_in_layers

DIRS = {
    "side_left": Vector((0, 1, 0)),     # camera on the vehicle's left (+Y)
    "side_right": Vector((0, -1, 0)),
    "front": Vector((1, 0, 0)),
    "rear": Vector((-1, 0, 0)),
    "top": Vector((0, 0, 1)),
    "bottom": Vector((0, 0, -1)),
    "three_quarter": Vector((1, 0.9, 0.55)).normalized(),        # front-left, from above
    "three_quarter_rear": Vector((-1, -0.9, 0.55)).normalized(),  # rear-right, from above
}
VIEWS = ("side_left", "front", "top", "three_quarter", "three_quarter_rear")


def _targets(final):
    if final:
        return [o for o in bpy.data.objects if o.get("veh_role") == "export" and o.type == "MESH"
                and not any(o.name.endswith(f"_LOD{i}") for i in range(1, 10))]
    return [o for o in objects_in_layers() if not o.hide_render]


def _setup(scene, engine):
    scene.render.engine = engine
    if engine == "BLENDER_WORKBENCH":
        sh = scene.display.shading
        sh.light = "STUDIO"
        sh.color_type = "MATERIAL"
        sh.show_cavity = True
        sh.cavity_type = "BOTH"
    else:
        scene.cycles.samples = 16
        scene.cycles.device = "CPU"


def _points(targets):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in targets:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    return pts


def render_views(spec, out_dir, prefix="view", views=VIEWS, res=1000, final=False, points=None):
    """points: optional fixed world points to frame (keeps the same framing across animation frames)."""
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    targets = _targets(final)
    if not targets:
        raise RuntimeError("Nothing to render.")
    keep = set(targets)
    rig = [o for o in bpy.data.objects if o.get("veh_role") == "rig"]
    hidden = []
    for o in scene.objects:
        if o not in keep and o not in rig and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    pts = points or _points(targets)
    lo, hi = Vector(map(min, *pts)), Vector(map(max, *pts))
    center, size = (lo + hi) / 2, max(hi - lo)
    cam = bpy.data.objects.get("VEH_ReviewCam")
    if cam is None:
        cam = bpy.data.objects.new("VEH_ReviewCam", bpy.data.cameras.new("VEH_ReviewCam"))
        scene.collection.objects.link(cam)
    if cam.name not in scene.objects:  # camera left over from another scene -> link it here
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.clip_start = size * 0.01
    cam.data.clip_end = size * 10
    scene.camera = cam
    scene.render.resolution_x = res
    scene.render.resolution_y = int(res * 0.6)
    files = []
    for v in views:
        d = DIRS[v]
        pos = center + d * size * 3  # d = direction from the vehicle to the camera
        cam.location = pos
        q = (center - pos).to_track_quat("-Z", "Y")
        cam.rotation_euler = q.to_euler()
        right, up = q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0))
        w = max(p.dot(right) for p in pts) - min(p.dot(right) for p in pts)
        h = max(p.dot(up) for p in pts) - min(p.dot(up) for p in pts)
        aspect = scene.render.resolution_y / scene.render.resolution_x
        cam.data.ortho_scale = max(w, h / aspect, size * 0.05) * 1.1
        fp = os.path.join(out_dir, f"{prefix}_{v}.png")
        scene.render.filepath = fp
        for eng in ("BLENDER_WORKBENCH", "CYCLES"):
            try:
                _setup(scene, eng)
                bpy.ops.render.render(write_still=True)
                files.append(fp)
                break
            except Exception as e:  # noqa
                log(f"Render with {eng} failed: {e}")
    for o in hidden:
        o.hide_render = False
    log(f"Renders: {len(files)} in {out_dir}")
    return files


def render_animation(spec, arm, name, out_dir, frames=None, view="three_quarter"):
    """Render key frames of one animation (default: 5 evenly spaced) from the final mesh."""
    from .anim import play
    act = play(spec, arm, name, 0)
    if act is None:
        raise RuntimeError(f"No action for animation {name}")
    a, b = (int(x) for x in act.frame_range)
    frames = frames or sorted({a + round((b - a) * t / 4) for t in range(5)})
    pts = []
    for f in frames:  # union of all frames -> fixed framing
        bpy.context.scene.frame_set(f)
        pts += _points(_targets(True))
    files = []
    for f in frames:
        bpy.context.scene.frame_set(f)
        files += render_views(spec, out_dir, prefix=f"anim_{name}_f{f:03d}", views=(view,), res=800, final=True,
                              points=pts)
    arm.animation_data.action = None
    bpy.context.scene.frame_set(0)
    return files
