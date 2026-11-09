"""Procedural part generators for vehicles (blueprint driven: side / top / front views).

Part types
  hull     intersection of the side, top (and optional front) silhouettes: car bodies, fuselages, boat hulls,
           tank hulls, superstructures. The classic blueprint blockout.
  panel    a piece cut out of another part (door, hood, trunk, hatch, canopy frame, ramp): source ∩ prism of an
           outline; the source gets a recess (Boolean difference, non-destructive) and the panel a gap.
           cut_only: true -> only the recess (wheel wells, cockpits, gear bays, cargo beds, intakes).
  profile  side outline extruded along Y (fins, fenders, frames, brackets, struts).
  wing     top-view planform with thickness, tip taper and dihedral (wings, stabilizers, hydrofoils, spoilers);
           plane 'side' for vertical fins.
  lathe    revolved profile around an axis (fuselage sections, nacelles, exhausts, floats, drums, tanks).
  wheel    tire + rim (cars, trucks, landing gear, tank road wheels).
  cylinder, box, tube (swept path: exhausts, rails, cables, roll cages, skids, tracks), ai_part (GLB/FBX/OBJ).
Every object gets: veh_part, veh_spec_part, veh_layer.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import materials
from .common import DEFAULT_LAYER_MATERIAL, Views, cm, get_collection, log, resolve_path

TYPE_LAYER = {"hull": "L0_Structure", "panel": "L2_Openings", "profile": "L1_Body", "wing": "L1_Body",
              "lathe": "L1_Body", "wheel": "L3_Running", "cylinder": "L8_Details", "box": "L8_Details",
              "tube": "L8_Details", "ai_part": "L8_Details"}
AXIS = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1)),
        "-X": Vector((-1, 0, 0)), "-Y": Vector((0, -1, 0)), "-Z": Vector((0, 0, -1))}
ROLE_LAYER = {"door": "L2_Openings", "hatch": "L2_Openings", "hood": "L2_Openings", "trunk": "L2_Openings",
              "canopy": "L2_Openings", "ramp": "L2_Openings", "wheel": "L3_Running", "suspension": "L3_Running",
              "rotor": "L3_Running", "tail_rotor": "L3_Running", "prop": "L3_Running", "gear": "L3_Running",
              "steer": "L4_Controls", "aileron_L": "L4_Controls", "aileron_R": "L4_Controls",
              "elevator": "L4_Controls", "rudder": "L4_Controls", "flap": "L4_Controls", "turret": "L4_Controls",
              "gun": "L4_Controls", "steering_wheel": "L5_Interior"}
BIG = 1.0e5  # cm, "infinite" prism depth


def signed_area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                     for i in range(len(poly)))


def offset_poly(poly, d):
    """Offset a simple polygon inward by d (positive = shrink). Miter, clamped."""
    if d == 0:
        return poly
    if signed_area(poly) < 0:
        poly = poly[::-1]
    n = len(poly)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % n])
        e1, e2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n1, n2 = Vector((-e1.y, e1.x)), Vector((-e2.y, e2.x))  # inward normals for CCW
        b = (n1 + n2)
        if b.length < 1e-9:
            b = n1
        b.normalize()
        cos = max(b.dot(n1), 0.3)
        q = p1 + b * (d / cos)
        out.append((q.x, q.y))
    return out


def box_uv(bm, scale):
    uvl = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            c = l.vert.co
            u, v = [(c.y, c.z), (c.x, c.z), (c.x, c.y)][ax]
            l[uvl].uv = (u / scale, v / scale)


def prism(poly2d, view, depth_from, depth_to):
    """bmesh prism: a 2D outline in a view, extruded along the view's missing axis between two depths (BU)."""
    bm = bmesh.new()

    def P(u, v, w):
        return {"side": (u, w, v), "top": (u, v, w), "front": (w, u, v)}[view]

    poly = poly2d if signed_area(poly2d) > 0 else poly2d[::-1]
    a = [bm.verts.new(P(u, v, depth_from)) for u, v in poly]
    b = [bm.verts.new(P(u, v, depth_to)) for u, v in poly]
    n = len(poly)
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def bm_to_object(bm, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def boolean_mesh(base_obj, others, op):
    """Evaluate base_obj with Boolean modifiers (EXACT) against others; returns a new bmesh."""
    for i, o in enumerate(others):
        m = base_obj.modifiers.new(f"_bool{i}", "BOOLEAN")
        m.operation = op
        m.object = o
        m.solver = "EXACT"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base_obj.evaluated_get(dg), depsgraph=dg)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    return bm


def remove_temp(*objs):
    for o in objs:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)


def add_modifiers(obj, bevel, segments=2, angle=35.0):
    if bevel > 0:
        b = obj.modifiers.new("VEH_Bevel", "BEVEL")
        b.width = bevel
        b.segments = segments
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(angle)
        b.harden_normals = True
        b.miter_outer = "MITER_ARC"
    w = obj.modifiers.new("VEH_WeightedNormal", "WEIGHTED_NORMAL")
    w.keep_sharp = True


class Builder:
    def __init__(self, spec):
        self.spec = spec
        self.views = Views(spec)
        self.parts = {p["id"]: p for p in spec.get("parts", [])}

    # ---------- helpers
    def space(self, part):
        return part.get("space", self.spec.get("default_space", "cm"))

    def v2(self, part, view, pts):
        return [self.views.to2(view, p, self.space(part)) for p in pts]

    def L(self, part, key, default):
        """Lengths are always in cm (independent of the point space)."""
        return cm(part.get(key, default))

    def c3(self, part):
        """3D center: center_cm [x,y,z] or side 'center' [x,z] + y_cm."""
        if "center_cm" in part:
            return Vector([cm(v) for v in part["center_cm"]])
        x, z = self.views.to_xz(part["center"], self.space(part))
        return Vector((x, cm(part.get("y_cm", 0.0)), z))

    def layer(self, part):
        if "layer" in part:
            return part["layer"]
        if part.get("role") in ROLE_LAYER:
            return ROLE_LAYER[part["role"]]
        if part.get("motion"):
            return "L2_Openings" if part.get("type") == "panel" else "L4_Controls"
        return TYPE_LAYER.get(part.get("type", "profile"), "L1_Body")

    def region_poly(self, ref):
        import json
        view_key, rid = ref.split(":")
        path = resolve_path(self.spec, self.spec["views"][view_key]["regions"])
        with open(path, "r", encoding="utf-8") as f:
            regs = {str(r["id"]): r for r in json.load(f)["regions"]}
        return regs[str(rid)]["polygon_px"]

    def outline(self, part, view, key):
        """Outline in BU for a view. Accepts points, 'view:region' refs (px) and *_half (mirrored across y=0)."""
        val = part.get(key)
        if isinstance(val, str):
            pts = self.views_px(view, self.region_poly(val))
        else:
            pts = self.v2(part, view, val)
        if part.get(key + "_half"):
            # half outline on the +Y side (top: [x, y>=0]; front: [y>=0, z]) -> mirror to a full outline
            eps = cm(0.01)
            if view == "top":
                pts = pts + [(u, -v) for u, v in reversed(pts) if abs(v) > eps]
            elif view == "front":
                pts = pts + [(-u, v) for u, v in reversed(pts) if abs(u) > eps]
        return pts

    def views_px(self, view, pts):
        return [self.views.to2(view, p, "px") for p in pts]

    def new_object(self, part, bm, suffix="", material=None):
        layer = self.layer(part)
        name = f"{layer[:2]}_{part['id']}{suffix}"
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
        bm.normal_update()
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        if not me.uv_layers:
            me.uv_layers.new(name="UVMap")
        for p in me.polygons:
            p.use_smooth = True
        obj = bpy.data.objects.new(name, me)
        get_collection(layer, get_collection("LAYERS")).objects.link(obj)
        obj["veh_part"] = part["id"] + suffix
        obj["veh_spec_part"] = part["id"]
        obj["veh_layer"] = layer
        materials.assign(obj, material or part.get("material", DEFAULT_LAYER_MATERIAL[layer]))
        add_modifiers(obj, self.L(part, "bevel_cm", 0.3), part.get("bevel_segments", 2))
        return obj

    def finish(self, bm):
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=cm(0.001))
        bmesh.ops.dissolve_degenerate(bm, dist=cm(0.001), edges=bm.edges[:])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        ngons = [f for f in bm.faces if len(f.verts) > 4]
        if ngons:
            bmesh.ops.triangulate(bm, faces=ngons, quad_method="BEAUTY", ngon_method="BEAUTY")
        box_uv(bm, cm(100))
        return bm

    # ---------- types
    def hull(self, part):
        side = self.outline(part, "side", "side")
        top = self.outline(part, "top", "top")
        front = self.outline(part, "front", "front") if part.get("front") else None
        m = cm(20)  # prisms only need to pass the other silhouettes by a margin (huge prisms break EXACT)
        xs = [u for u, _ in side] + [u for u, _ in top]
        ys = [v for _, v in top] + ([u for u, _ in front] if front else [])
        zs = [v for _, v in side] + ([v for _, v in front] if front else [])
        base = bm_to_object(prism(side, "side", min(ys) - m, max(ys) + m), "_hull_side")
        others = [bm_to_object(prism(top, "top", min(zs) - m, max(zs) + m), "_hull_top")]
        if front:
            others.append(bm_to_object(prism(front, "front", min(xs) - m, max(xs) + m), "_hull_front"))
        bm = boolean_mesh(base, others, "INTERSECT")
        remove_temp(base, *others)
        if not bm.verts:
            raise RuntimeError("hull: empty intersection (check that side/top/front outlines overlap)")
        return [self.new_object(part, self.finish(bm))]

    def _panel_prisms(self, part, sobj=None):
        view = part.get("view", "side")
        poly = self.outline(part, view, "poly")
        key = {"side": "y_from_cm", "top": "z_from_cm", "front": "x_from_cm"}[view]
        axis = {"side": 1, "top": 2, "front": 0}[view]
        val = part.get(key, 0.0)
        # depth limit = the source's bounds + margin (never 'infinite': huge prisms break the EXACT solver)
        if sobj is not None and len(sobj.data.vertices):
            vals = [v.co[axis] for v in sobj.data.vertices]
            lo, hi = min(vals) - cm(10), max(vals) + cm(10)
        else:
            lo, hi = -cm(BIG), cm(BIG)
        start = cm(val)
        end = lo if (val < 0 or (val == 0 and part.get("negative"))) else hi
        if part.get("through"):  # both sides (rudders, cabin window bands, centerline hatches)
            start, end = lo, hi
        gap = self.L(part, "gap_cm", 0.4)
        return view, prism(offset_poly(poly, gap), view, start, end), prism(poly, view, start, end)

    def panel(self, part):
        src = self.parts.get(part.get("from"))
        sobj = next((o for o in bpy.data.objects if o.get("veh_part") == part.get("from")), None)
        if src is None or sobj is None:
            raise RuntimeError(f"panel: source part '{part.get('from')}' must be built first")
        view, inner, outer = self._panel_prisms(part, sobj)
        bm = None
        if part.get("cut_only"):  # recess only: wheel wells, cockpits, gear bays, cargo beds
            inner.free()
        else:
            tmp = bpy.data.objects.new("_panel_src", sobj.data.copy())  # base mesh, no cuts / modifiers
            bpy.context.scene.collection.objects.link(tmp)
            cutter_in = bm_to_object(inner, "_panel_in")
            bm = boolean_mesh(tmp, [cutter_in], "INTERSECT")
            remove_temp(tmp, cutter_in)
            if not bm.verts:
                outer.free()
                raise RuntimeError("panel: empty (outline does not touch the source, or wrong *_from_cm side)")
        if part.get("cut", True) or part.get("cut_only"):
            name = f"CUT_{part['id']}"
            old = bpy.data.objects.get(name)
            if old:
                remove_temp(old)
            me = bpy.data.meshes.new(name)
            outer.to_mesh(me)
            outer.free()
            cut = bpy.data.objects.new(name, me)
            get_collection("CUTTERS").objects.link(cut)
            cut.display_type = "WIRE"
            cut.hide_render = True
            cut["veh_cutter_for"] = part["from"]
        else:
            outer.free()
        if bm is None:
            return []
        return [self.new_object(part, self.finish(bm))]

    def profile(self, part):
        poly = self.outline(part, "side", "poly")
        t = self.L(part, "thickness_cm", 2.0)
        y0 = cm(part.get("y_cm", 0.0))
        bm = prism(poly, "side", y0 - t / 2, y0 + t / 2)
        return [self.new_object(part, self.finish(bm))]

    def wing(self, part):
        plane = part.get("plane", "top")
        view = "top" if plane == "top" else "side"
        poly = self.outline(part, view, "planform")
        t = self.L(part, "thickness_cm", 12.0)
        tip_ratio = part.get("tip_thickness_ratio", 0.5)
        if view == "top":
            z0 = cm(part.get("z_cm", 0.0))
            bm = prism(poly, "top", z0 - t / 2, z0 + t / 2)
            span_axis, base_c = 1, z0
        else:
            y0 = cm(part.get("y_cm", 0.0))
            bm = prism(poly, "side", y0 - t / 2, y0 + t / 2)
            span_axis, base_c = 2, y0
        thick_axis = 2 if view == "top" else 1
        vals = [abs(v.co[span_axis]) if view == "top" else v.co[span_axis] for v in bm.verts]
        root = min(vals) if view == "top" else min(vals)
        tip = max(vals)
        rng = max(tip - root, 1e-9)
        for v, s in zip(bm.verts, vals):
            k = 1.0 - (1.0 - tip_ratio) * (s - root) / rng
            v.co[thick_axis] = base_c + (v.co[thick_axis] - base_c) * k
        d = math.radians(part.get("dihedral_deg", 0.0))
        if d and view == "top":
            ry = min((v.co.y for v in bm.verts), key=abs)
            piv = Vector((0, ry, base_c))
            M = Matrix.Translation(piv) @ Matrix.Rotation(d, 4, "X") @ Matrix.Translation(-piv)
            bmesh.ops.transform(bm, matrix=M, verts=bm.verts[:])
        return [self.new_object(part, self.finish(bm))]

    def _revolve(self, prof, center, axis, segs, caps=True):
        """prof: [(t, r)] in BU along the axis; returns bmesh revolved around 'axis' through 'center'."""
        rs = list(prof)
        if caps:
            if rs[0][1] > 0:
                rs.insert(0, (rs[0][0], 0.0))
            if rs[-1][1] > 0:
                rs.append((rs[-1][0], 0.0))
        a = AXIS[axis]
        perp = Vector((0, 0, 1)) if axis in ("X", "Y", "-X", "-Y") else Vector((1, 0, 0))
        bm = bmesh.new()
        vs = [bm.verts.new(center + a * t + perp * r) for t, r in rs]
        edges = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
        bmesh.ops.spin(bm, geom=vs + edges, cent=center, axis=a, dvec=(0, 0, 0), angle=2 * math.pi, steps=segs,
                       use_merge=True, use_duplicate=False)
        return bm

    def lathe(self, part):
        prof = [(cm(t), cm(r)) for t, r in part["profile"]]
        bm = self._revolve(prof, self.c3(part), part.get("axis", "X"), int(part.get("segments", 24)),
                           part.get("caps", True))
        return [self.new_object(part, self.finish(bm))]

    def wheel(self, part):
        c = self.c3(part)
        R = self.L(part, "radius_cm", 33.0)
        W = self.L(part, "width_cm", 22.0)
        rr = R * part.get("rim_ratio", 0.62)
        b = min(W * 0.18, (R - rr) * 0.35)
        segs = int(part.get("segments", 32))
        tire = [(-W / 2, rr), (-W / 2, R - b), (-W / 2 + b, R), (W / 2 - b, R), (W / 2, R - b), (W / 2, rr),
                (-W / 2, rr)]
        bm_t = self._revolve(tire, c, "Y", segs, caps=False)
        dish = W * part.get("rim_dish", 0.25)
        rim = [(-W / 2 + dish, 0), (-W / 2 + dish, rr * 0.28), (-W / 2 + dish * 0.6, rr * 0.35),
               (-W / 2 + dish * 0.6, rr * 0.92), (-W / 2 + 0.02 * W, rr), (W / 2 - 0.05 * W, rr),
               (W / 2 - 0.05 * W, 0)]
        side = 1 if c.y >= 0 else -1  # rim face looks outward (+Y on the left side)
        rim = [(-t * side, r) for t, r in rim]
        bm_r = self._revolve(rim, c, "Y", segs, caps=True)
        objs = [self.new_object(part, self.finish(bm_t), "_tire", part.get("tire_material", "MI_Trim")),
                self.new_object(part, self.finish(bm_r), "_rim", part.get("rim_material", "MI_Trim"))]
        return objs

    def cylinder(self, part):
        c = self.c3(part)
        r = self.L(part, "radius_cm", 2.0)
        Ln = self.L(part, "length_cm", 10.0)
        ax = part.get("axis", "Y")
        vec = Vector(ax).normalized() if isinstance(ax, list) else AXIS[ax]
        rot = Vector((0, 0, 1)).rotation_difference(vec).to_matrix().to_4x4()
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=int(part.get("segments", 16)), radius1=r,
                              radius2=self.L(part, "radius2_cm", part.get("radius_cm", 2.0)), depth=Ln,
                              matrix=Matrix.Translation(c) @ rot)
        return [self.new_object(part, self.finish(bm))]

    def box(self, part):
        c = self.c3(part)
        sx, sy, sz = (cm(v) for v in part.get("size_cm", [10, 10, 10]))
        rx, ry, rz = part.get("rotate_xyz_deg", [0, part.get("rotate_deg", 0.0), 0])
        R = (Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(ry), 4, "Y") @
             Matrix.Rotation(math.radians(rx), 4, "X"))
        bm = bmesh.new()
        r = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=r["verts"])
        bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ R, verts=bm.verts[:])
        return [self.new_object(part, self.finish(bm))]

    def tube(self, part):
        if "path_3d" in part:
            pts = [Vector([cm(v) for v in p]) for p in part["path_3d"]]
        else:
            y = cm(part.get("y_cm", 0.0))
            pts = [Vector((x, y, z)) for x, z in self.v2(part, "side", part["path"])]
        closed = part.get("closed", False)
        if "section_cm" in part:
            w, h = (cm(v) for v in part["section_cm"])
            sec = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
        else:
            r = self.L(part, "radius_cm", 1.0)
            n = int(part.get("sides", 10))
            sec = [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]
        bm = bmesh.new()
        rings = []
        N = len(pts)
        for i, p in enumerate(pts):
            if closed:
                t = (pts[(i + 1) % N] - pts[i - 1]).normalized()
            else:
                t = (pts[min(i + 1, N - 1)] - pts[max(i - 1, 0)]).normalized()
            up = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((0, 0, 1))
            u = (up - t * up.dot(t)).normalized()
            v = t.cross(u).normalized()
            rings.append([bm.verts.new(p + u * a + v * b) for a, b in sec])
        k = len(sec)
        last = N if closed else N - 1
        for i in range(last):
            r0, r1 = rings[i], rings[(i + 1) % N]
            for j in range(k):
                bm.faces.new((r0[j], r1[j], r1[(j + 1) % k], r0[(j + 1) % k]))
        if not closed:
            bm.faces.new(rings[0][::-1])
            bm.faces.new(rings[-1])
        return [self.new_object(part, self.finish(bm))]

    def ai_part(self, part):
        fp = resolve_path(self.spec, part["file"])
        before = set(bpy.data.objects)
        ext = os.path.splitext(fp)[1].lower()
        if ext in (".glb", ".gltf"):
            bpy.ops.import_scene.gltf(filepath=fp)
        elif ext == ".fbx":
            bpy.ops.import_scene.fbx(filepath=fp)
        else:
            bpy.ops.wm.obj_import(filepath=fp)
        new = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in new if o.type == "MESH"]
        for o in meshes:
            o.data.transform(o.matrix_world)
            o.parent = None
            o.matrix_world = Matrix.Identity(4)
        for o in new:
            if o.type != "MESH":
                bpy.data.objects.remove(o, do_unlink=True)
        lo, hi = Vector((1e18,) * 3), Vector((-1e18,) * 3)
        for o in meshes:
            for v in o.data.vertices:
                lo = Vector(map(min, lo, v.co))
                hi = Vector(map(max, hi, v.co))
        size = max(hi - lo) or 1.0
        s = self.L(part, "size_cm", 50.0) / size
        align = AXIS[part.get("front_axis", "X")].rotation_difference(Vector((1, 0, 0))).to_matrix().to_4x4()
        M = Matrix.Translation(self.c3(part)) @ align @ Matrix.Scale(s, 4) @ Matrix.Translation(-(lo + hi) / 2)
        out = []
        for i, o in enumerate(meshes):
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bmesh.ops.transform(bm, matrix=M, verts=bm.verts[:])
            sub = dict(part)
            for key, layer in (part.get("part_map") or {}).items():
                if key.lower() in o.name.lower():
                    sub["layer"] = layer
            bpy.data.objects.remove(o, do_unlink=True)
            out.append(self.new_object(sub, bm, suffix=f"_{i:02d}" if len(meshes) > 1 else ""))
        log(f"AI part {part['id']}: {len(out)} sub-parts")
        return out

    def build(self, part):
        t = part.get("type", "profile")
        if t not in TYPE_LAYER:
            raise ValueError(f"Unknown part type: {t} (valid: {', '.join(TYPE_LAYER)})")
        objs = getattr(self, t)(part)
        for o in objs:
            o["veh_spec_part"] = part["id"]
            o["veh_role"] = part.get("role", "")
        return objs


def apply_cuts(spec):
    """Make sure every source part has a Boolean DIFFERENCE for each panel cutter (recess for doors/hatches)."""
    n = 0
    for cut in [o for o in bpy.data.objects if o.get("veh_cutter_for")]:
        pid = cut.name[4:]
        if pid not in {p["id"] for p in spec.get("parts", [])}:
            continue
        for src in [o for o in bpy.data.objects if o.get("veh_part") == cut["veh_cutter_for"]]:
            m = src.modifiers.get(cut.name) or src.modifiers.new(cut.name, "BOOLEAN")
            m.operation = "DIFFERENCE"
            m.solver = "EXACT"
            m.object = cut
            idx = list(src.modifiers).index(m)
            first_non_bool = next((i for i, mm in enumerate(src.modifiers) if mm.type != "BOOLEAN"), idx)
            if idx > first_non_bool:
                src.modifiers.move(idx, first_non_bool)
            bev = src.modifiers.get("VEH_Bevel")
            if bev is not None:
                bev.miter_outer = "MITER_SHARP"  # ARC miters after an EXACT boolean can explode (Blender 5.x)
            n += 1
    return n
