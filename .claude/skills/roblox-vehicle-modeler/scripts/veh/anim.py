"""Simple vehicle animations as Blender Actions (one per animation), ready for retouching.

Spec:
  "animations": [
    {"name": "Drive", "preset": "drive_loop"},                       # every part with role "wheel"
    {"name": "Doors", "preset": "doors_open_close", "length": 50},
    {"name": "Custom", "length": 40, "tracks": [
        {"part": "hood", "keys": [[0, 0], [20, 1], [40, 0]], "interp": "BEZIER"},
        {"role": "wheel", "keys": [[0, 0], [40, 1]], "interp": "LINEAR", "cycle": true}]}
  ]
Key values are NORMALIZED (0 = motion.min, 1 = motion.max). The token "rest" means the modeled pose
(e.g. 0.5 for steering -35..35). Preset tracks address ROLES: every part whose "role" matches gets the track
(mirrored parts inherit the role; *_L roles become *_R). `roles` can remap a preset role to part ids/roles.
Every action has a fake user and a muted NLA track -> one FBX take / AnimSequence / clip per animation.
"""
import bpy

from .common import log
from .rig import key_index, motion_value, parts_by_id, reset_pose, rest_value

R = "rest"
PRESETS = {
    "idle": {"length": 1, "tracks": {}},
    "drive_loop": {"length": 30, "tracks": {"wheel": ([[0, 0], [30, 1]], "LINEAR", True)}},
    "steer_left_right": {"length": 60, "tracks": {
        "steer": ([[0, R], [15, 1], [30, R], [45, 0], [60, R]], "BEZIER", False),
        "steering_wheel": ([[0, R], [15, 1], [30, R], [45, 0], [60, R]], "BEZIER", False)}},
    "suspension_bounce": {"length": 40, "tracks": {
        "suspension": ([[0, R], [8, 1], [18, 0], [28, 0.8], [40, R]], "BEZIER", False)}},
    "doors_open_close": {"length": 60, "tracks": {
        "door": ([[0, 0], [20, 1], [40, 1], [60, 0]], "BEZIER", False)}},
    "hood_trunk": {"length": 60, "tracks": {
        "hood": ([[0, 0], [20, 1], [40, 1], [60, 0]], "BEZIER", False),
        "trunk": ([[0, 0], [20, 1], [40, 1], [60, 0]], "BEZIER", False)}},
    "hatch_open_close": {"length": 60, "tracks": {
        "hatch": ([[0, 0], [20, 1], [40, 1], [60, 0]], "BEZIER", False),
        "canopy": ([[0, 0], [25, 1], [40, 1], [60, 0]], "BEZIER", False),
        "ramp": ([[0, 0], [30, 1], [45, 1], [60, 0]], "BEZIER", False)}},
    "rotor_spin": {"length": 12, "tracks": {
        "rotor": ([[0, 0], [12, 1]], "LINEAR", True),
        "tail_rotor": ([[0, 0], [4, 1]], "LINEAR", True)}},
    "prop_spin": {"length": 8, "tracks": {"prop": ([[0, 0], [8, 1]], "LINEAR", True)}},
    "control_check": {"length": 120, "tracks": {
        "aileron_L": ([[0, R], [15, 1], [30, 0], [45, R]], "BEZIER", False),
        "aileron_R": ([[0, R], [15, 0], [30, 1], [45, R]], "BEZIER", False),
        "elevator": ([[45, R], [60, 1], [75, 0], [90, R]], "BEZIER", False),
        "rudder": ([[90, R], [100, 1], [110, 0], [120, R]], "BEZIER", False),
        "flap": ([[0, 0], [60, 1], [120, 0]], "BEZIER", False)}},
    "gear_retract": {"length": 90, "tracks": {
        "gear_door": ([[0, 0], [15, 1], [75, 1], [90, 0]], "BEZIER", False),
        "gear": ([[10, 0], [70, 1]], "BEZIER", False)}},
    "gear_extend": {"length": 90, "tracks": {
        "gear_door": ([[0, 0], [15, 1], [75, 1], [90, 0]], "BEZIER", False),
        "gear": ([[10, 1], [70, 0]], "BEZIER", False)}},
    "turret_traverse": {"length": 120, "tracks": {
        "turret": ([[0, R], [40, 1], [80, 0], [120, R]], "BEZIER", False),
        "gun": ([[0, R], [20, 1], [60, 0], [100, 1], [120, R]], "BEZIER", False)}},
    "boat_rudder": {"length": 60, "tracks": {
        "rudder": ([[0, R], [15, 1], [30, R], [45, 0], [60, R]], "BEZIER", False),
        "outboard": ([[0, R], [15, 1], [30, R], [45, 0], [60, R]], "BEZIER", False)}},
    "track_loop": {"length": 30, "tracks": {"wheel": ([[0, 0], [30, 1]], "LINEAR", True),
                                            "sprocket": ([[0, 0], [30, 1]], "LINEAR", True)}},
}


def _fcurves(action):
    fc = getattr(action, "fcurves", None)
    try:
        if fc is not None and len(fc) >= 0:
            return list(fc)
    except Exception:  # noqa
        pass
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for slot in action.slots:
                cb = strip.channelbag(slot) if hasattr(strip, "channelbag") else None
                if cb:
                    out += list(cb.fcurves)
    return out


def parts_for(spec, role_or_ids, parts=None):
    """A role name, a part id, or a list of them -> moving part ids."""
    parts = parts or parts_by_id(spec)
    items = role_or_ids if isinstance(role_or_ids, list) else [role_or_ids]
    out = []
    for it in items:
        if it in parts and parts[it].get("motion"):
            out.append(it)
        else:
            out += [pid for pid, p in parts.items() if p.get("role") == it and p.get("motion")]
    return list(dict.fromkeys(out))


def _resolve(keys, part):
    rv = rest_value(part)
    return [[f, rv if v == R else v] for f, v in keys]


def expand(spec, anim):
    """Return (length, [(part_id, keys, interp, cycle)])."""
    parts = parts_by_id(spec)
    tracks = []
    length = 0
    if "preset" in anim:
        pre = PRESETS[anim["preset"]]
        roles = anim.get("roles", {})
        for role, (keys, interp, cyc) in pre["tracks"].items():
            for pid in parts_for(spec, roles.get(role, role), parts):
                tracks.append((pid, _resolve(keys, parts[pid]), interp, cyc))
        length = pre["length"]
    for t in anim.get("tracks", []):
        ids = parts_for(spec, t.get("part") or t.get("role"), parts)
        if not ids:
            log(f"WARNING: animation {anim['name']}: '{t.get('part') or t.get('role')}' matches no moving part.")
        for pid in ids:
            tracks.append((pid, _resolve(t["keys"], parts[pid]), t.get("interp", "BEZIER"), t.get("cycle", False)))
            length = max(length, max(k[0] for k in t["keys"]))
    length = anim.get("length", max(length, 1))
    if anim.get("length") and "preset" in anim:  # rescale preset timing to the requested length
        k = anim["length"] / PRESETS[anim["preset"]]["length"]
        tracks = [(pid, [[round(f * k, 3), v] for f, v in keys], i, c) for pid, keys, i, c in tracks]
    if not tracks:  # idle: key every moving part at rest so the take is not empty
        tracks = [(pid, [[0, rest_value(p)], [length, rest_value(p)]], "CONSTANT", False)
                  for pid, p in parts.items() if p.get("motion")]
    return length, tracks


def build_actions(spec, arm):
    asset = spec.get("asset", "Vehicle")
    parts = parts_by_id(spec)
    arm.animation_data_create()
    ad = arm.animation_data
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    summary = {}
    for anim in spec.get("animations", []):
        aname = f"A_{asset}_{anim['name']}"
        old = bpy.data.actions.get(aname)
        if old:
            bpy.data.actions.remove(old)
        act = bpy.data.actions.new(aname)
        act.use_fake_user = True
        ad.action = act
        length, tracks = expand(spec, anim)
        reset_pose(arm)
        for pid, keys, interp, cyc in tracks:
            pb = arm.pose.bones.get("b_" + pid)
            if pb is None:
                continue
            p = parts[pid]
            idx = key_index(p["motion"])
            prop = "rotation_euler" if p["motion"]["type"] == "rotate" else "location"
            for f, v in keys:
                getattr(pb, prop)[idx] = motion_value(p, v)
                pb.keyframe_insert(prop, index=idx, frame=f, group=pb.name)
            for fc in _fcurves(act):
                if fc.data_path == f'pose.bones["{pb.name}"].{prop}' and fc.array_index == idx:
                    for kp in fc.keyframe_points:
                        kp.interpolation = interp
                    if cyc and not any(m.type == "CYCLES" for m in fc.modifiers):
                        fc.modifiers.new("CYCLES")
        act.frame_range = (0, length)
        act.use_cyclic = any(t[3] for t in tracks)
        act["veh_fps"] = anim.get("fps", 30)
        act["veh_description"] = anim.get("description", "")
        tr = ad.nla_tracks.new()
        tr.name = anim["name"]
        tr.strips.new(anim["name"], 0, act)
        tr.mute = True
        summary[anim["name"]] = {"action": aname, "frames": length, "fps": anim.get("fps", 30),
                                 "loop": act.use_cyclic, "parts": list(dict.fromkeys(t[0] for t in tracks))}
        ad.action = None
        reset_pose(arm)
    log(f"Animations: {list(summary)}")
    return summary


def play(spec, arm, name, frame):
    act = bpy.data.actions.get(f"A_{spec.get('asset', 'Vehicle')}_{name}")
    arm.animation_data_create()
    arm.animation_data.action = act
    bpy.context.scene.frame_set(int(frame))
    return act
