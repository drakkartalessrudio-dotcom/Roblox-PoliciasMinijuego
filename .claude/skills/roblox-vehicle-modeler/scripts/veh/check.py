"""Motion check: move every moving part (with everything it carries) to 0.5 and 1.0 of its range and flag
NEW contacts with other parts (none at rest) or clear increases of existing contacts (triangle-pair overlaps).
Contacts listed in motion.allow_contact (e.g. the slide cocking the hammer) are reported as expected, not as errors."""
import bmesh
import bpy
from mathutils.bvhtree import BVHTree

from .common import log, objects_in_layers
from .rig import bone_of, motion_matrix, parts_by_id, rest_value


def _bm(obj, dg, M=None):
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), depsgraph=dg)
    me.transform(obj.matrix_world if M is None else M @ obj.matrix_world)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    return bm


def _carried(spec, pid, parts):
    """Parts that move with 'pid' (itself + parts whose driving bone chain passes through b_pid)."""
    out = []
    for q in parts:
        cur = q
        for _ in range(50):
            if cur == pid:
                out.append(q)
                break
            nxt = parts[cur].get("parent") if cur in parts else None
            if not nxt:
                break
            cur = nxt
    return out


def motion_check(spec, samples=(0.0, 0.5, 1.0)):
    parts = parts_by_id(spec)
    objs = objects_in_layers()
    dg = bpy.context.evaluated_depsgraph_get()
    static_cache = {}
    report = {}
    for pid, p in parts.items():
        if not p.get("motion"):
            continue
        carried = set(_carried(spec, pid, parts))
        mov = [o for o in objs if o.get("veh_spec_part") in carried]
        others = [o for o in objs if o.get("veh_spec_part") not in carried]
        if not mov:
            continue
        for o in others:
            if o.name not in static_cache:
                bm = _bm(o, dg)
                static_cache[o.name] = BVHTree.FromBMesh(bm)
                bm.free()

        def hits(v):
            res = {}
            M = motion_matrix(spec, p, v)
            for m in mov:
                bm = _bm(m, dg, M)
                tree = BVHTree.FromBMesh(bm)
                bm.free()
                for o in others:
                    n = len(tree.overlap(static_cache[o.name]))
                    if n:
                        res[o.get("veh_spec_part")] = res.get(o.get("veh_spec_part"), 0) + n
            return res

        rv = rest_value(p)
        base = hits(rv)
        allowed = set(p["motion"].get("allow_contact", []))
        new, expected = {}, {}
        for v in [x for x in samples if abs(x - rv) > 1e-6]:
            for other, n in hits(v).items():
                b = base.get(other, 0)
                # flag NEW contact (none at rest) or a clear increase of an existing contact
                if (b == 0 and n > 0) or (n - b > max(20, 0.5 * b)):
                    (expected if other in allowed else new).setdefault(other, {})[str(v)] = {"rest": b, "moved": n}
        report[pid] = {"bone": bone_of(spec, pid, parts), "carries": sorted(carried - {pid}),
                       "rest_contacts": base, "new_intersections": new,
                       "expected_contacts": expected}
    bad = [k for k, v in report.items() if v["new_intersections"]]
    log(f"Motion check: {len(report)} moving parts; with new intersections: {bad or 'none'}")
    return report
