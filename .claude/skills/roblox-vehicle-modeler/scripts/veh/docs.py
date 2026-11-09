"""Living vehicle document: <asset>_PARTS.md + <asset>_history.json next to the spec.

Regenerated on setup / build / finalize. Written so ANOTHER agent can understand every layer and part,
which parts MOVE (bone, axis, range, role), the bone tree, sockets and animations, how to export to each engine,
and exactly how to change one part or animation without breaking the final asset.
"""
import datetime
import json
import os

from .common import DEFAULT_LAYER_MATERIAL, LAYER_NAMES, SLOT_ORDER, log

LAYER_ROLE = {
    "L0_Structure": "Core volume: chassis / hull / fuselage (bone b_body). Panels are cut from it.",
    "L1_Body": "Static body panels, fenders, nacelles, superstructure, wings, armor.",
    "L2_Openings": "MOVING panels: doors, hood, trunk, hatches, canopy, ramps. Each has a hinge bone.",
    "L3_Running": "Wheels, suspension, tracks, rotors, propellers, landing gear. Spin / travel bones.",
    "L4_Controls": "Steering, control surfaces, rudders, turrets, guns, wipers. Each has a bone.",
    "L5_Interior": "Cockpit / cabin: seats, dashboard, steering wheel, sticks, pedals.",
    "L6_Glass": "Windows, windshield, canopy glass, lamp covers (MI_Glass).",
    "L7_Lights": "Head/tail/brake/nav/strobe lights and displays (MI_Lights, emissive).",
    "L8_Details": "Mirrors, antennas, exhausts, handles, vents, rivets, plates, decals.",
}
SLOT_INFO = {
    "MI_Body": ("M_V_Body", "Opaque. Paint / hull / fuselage: BC/N/ORM + paint tint, dirt, wear and damage masks."),
    "MI_Trim": ("M_V_Trim", "Opaque. Rubber, plastic, raw metal, interior; tiling + trim sheet."),
    "MI_Glass": ("M_V_Glass", "Translucent glass (tint, dirt, cracks mask)."),
    "MI_Lights": ("M_V_Lights", "Emissive lights; per-light masks driven at runtime (brake, reverse, turn, nav)."),
}
PARAM_KEYS = ("role", "radius_cm", "width_cm", "thickness_cm", "y_cm", "y_from_cm", "z_from_cm", "center_cm",
              "length_cm", "size_cm", "axis", "gap_cm", "dihedral_deg", "bevel_cm", "segments", "file", "material",
              "mirrored_from")


def _paths(spec):
    d = spec.get("_dir") or os.getcwd()
    a = spec.get("asset", "Vehicle")
    return spec.get("doc_path") or os.path.join(d, f"{a}_PARTS.md"), os.path.join(d, f"{a}_history.json")


def _load(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa
        return {"events": [], "last": {}}


def record(spec, kind, data):
    _, hp = _paths(spec)
    h = _load(hp)
    ev = {"time": datetime.datetime.now().isoformat(timespec="seconds"), "kind": kind}
    ev.update(data)
    h["events"] = (h["events"] + [ev])[-200:]
    h["last"][kind] = ev
    try:
        with open(hp, "w", encoding="utf-8") as f:
            json.dump(h, f, indent=1, ensure_ascii=False, default=str)
    except Exception as e:  # noqa
        log(f"Could not save history: {e}")


def _motion_txt(p):
    m = p.get("motion")
    if not m:
        return "—"
    from .rig import rest_value
    unit = "°" if m["type"] == "rotate" else " cm"
    ax = m.get("axis", "X")
    ax = f"hinge {ax}" if isinstance(ax, list) else ax
    piv = m.get("pivot_3d") or m.get("pivot")
    piv = f" about {piv}" if piv else ""
    rv = rest_value(p)
    rest = f", rest v={rv:.2f}" if rv else ""
    return f"**{m['type']} {ax}** {m.get('min', 0)}→{m.get('max', 0)}{unit}{piv}{rest}"


def _scene():
    try:
        import bpy
        from .common import objects_in_layers
        dg = bpy.context.evaluated_depsgraph_get()
        out = {}
        for o in objects_in_layers():
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            t = sum(len(p.vertices) - 2 for p in me.polygons)
            ev.to_mesh_clear()
            d = out.setdefault(o.get("veh_spec_part"), {"objects": [], "tris": 0})
            d["objects"].append(o.name)
            d["tris"] += t
        return out
    except Exception:  # noqa
        return {}


def _wheels(spec):
    """Wheel table for physics setups: role 'wheel' parts (radius/width from the part, steering/driven flags)."""
    from .rig import parts_by_id
    parts = parts_by_id(spec)
    out = []
    for pid, p in parts.items():
        if p.get("role") != "wheel":
            continue
        steer, q = False, parts.get(p.get("parent"))
        while q is not None:
            steer = steer or q.get("role") == "steer"
            q = parts.get(q.get("parent"))
        c = p.get("center_cm") or [p.get("center", [0, 0])[0], p.get("y_cm", 0), p.get("center", [0, 0])[1]]
        out.append({"id": pid, "bone": "b_" + pid, "center_cm": c, "radius_cm": p.get("radius_cm", 33.0),
                    "width_cm": p.get("width_cm", 22.0), "steering": p.get("steering", steer),
                    "driven": p.get("driven", True)})
    return out


def _engines(w, spec, lf, asset):
    """Section 8: per-engine import instructions filled with this vehicle's names (always written)."""
    anims = [f"A_{asset}_{a['name']}" for a in spec.get("animations", [])]
    socks = [s["name"] for s in spec.get("sockets", [])]
    exp = "Export"
    for f in lf.get("fbx") or []:
        exp = os.path.dirname(f)
        break
    A = ", ".join(f"`{a}`" for a in anims) or "—"
    S = ", ".join(f"`{s}`" for s in socks) or "—"
    wheels = _wheels(spec)
    mass = spec.get("mass_kg")
    cls = spec.get("vehicle_class", "")
    w("## 8. Export to game engines")
    w("")
    w(f"Files (folder `{exp}`):")
    w(f"- `SK_{asset}_LOD0.fbx` skeletal mesh + skeleton + one take per animation; `SK_{asset}_LOD1..3.fbx` mesh only "
      "(cm).")
    w(f"- `SK_{asset}.glb` LOD0 + animations (meters).")
    w(f"- `{asset}_Rigid.fbx` (cm) / `{asset}_Rigid.glb` (m): NO skinning — one object per moving part with its pivot "
      "at the hinge/hub, parented like the bones, sockets as empties. Use it for physics vehicles and props.")
    w(f"- Re-generate: `veh.finalize(SPEC, r\"{exp}\")`. Forward = +X in Blender. Animations: {A}. Sockets: {S}. "
      "Slots: " + ", ".join(f"`{x}`" for x in SLOT_ORDER) + " (only used ones are exported)." +
      (f" Mass: {mass} kg." if mass else ""))
    w("")
    if wheels:
        w("**Wheel data** (for the physics setup):")
        w("")
        w("| Wheel | Bone / object | Center (cm) | Radius | Width | Steering | Driven |")
        w("|---|---|---|---|---|---|---|")
        for wh in wheels:
            w(f"| `{wh['id']}` | `{wh['bone']}` / `{wh['id']}` | {wh['center_cm']} | {wh['radius_cm']} | "
              f"{wh['width_cm']} | {'yes' if wh['steering'] else 'no'} | {'yes' if wh['driven'] else 'no'} |")
        w("")
    w("### Unreal Engine 5")
    w(f"1. Import `SK_{asset}_LOD0.fbx`: Skeletal Mesh ON, Skeleton = none, Import Animations ON (one AnimSequence "
      "per take; rename to the `A_...` names), Normals and Tangents, Materials OFF if the masters exist. LOD Settings → "
      "Import LOD 1..3.")
    w("2. Materials: run `scripts/ue_setup_materials.py` (CONFIG → this SK) → `M_V_*` masters + `MI_*` by slot.")
    if wheels:
        w("3. **Drivable (Chaos Vehicles plugin):** Physics Asset: one convex/box body on `b_root` covering the hull "
          "(delete bodies on wheel/steer/suspension bones); Blueprint from `WheeledVehiclePawn`; in "
          "*ChaosWheeledVehicleMovement → Wheel Setups* add one entry per wheel with **Bone Name = `b_<wheel>`** "
          "(table above) and a ChaosVehicleWheel class per axle (Wheel Radius/Width from the table, Affected By "
          "Steering = Steering column, Affected By Engine = Driven). Animation Blueprint for the SK with the "
          "*Wheel Controller* node → it spins, steers and moves the `b_wheel_*` bones; the `b_steer_*` / `b_susp_*` "
          "bones stay at rest in gameplay (they exist for cinematics and the authored animations).")
        w(f"4. Mass {mass or '<set>'} kg, center of mass lowered ~20–30 % of the height; tune torque curve, gears and "
          "suspension in the movement component.")
    else:
        w("3. Non-wheeled (aircraft, boat, helicopter): Pawn/Actor Blueprint with the SK; drive rotors, props and "
          "control surfaces either by playing the AnimSequences or with an AnimBP (*Transform (Modify) Bone* on "
          "`b_<part>` from gameplay values: throttle → prop spin, stick → aileron/elevator, pedals → rudder).")
        w("4. Physics: simple collision bodies on `b_root`; flight/buoyancy is game code (Chaos Modular Vehicle, "
          "Water plugin buoyancy, or custom).")
    w(f"5. Doors/hatches: play `A_{asset}_*` AnimSequences or set the hinge bones from Blueprint. Seat/exit sockets "
      "are bones: attach the driver with `AttachToComponent(…, SocketName)`.")
    w("")
    w("### UEFN (Unreal Editor for Fortnite)")
    w(f"1. Import `SK_{asset}_LOD0.fbx` (Skeletal Mesh + Animation Sequences) or `{asset}_Rigid.fbx` as static "
      "meshes. No Python: materials by hand (paint material with Color param, trim, glass, emissive lights).")
    w("2. Play door/rotor/prop animations with the **Animated Mesh device** or a Level Sequence (Verse can trigger "
      "them). Custom DRIVABLE vehicles are limited in UEFN (driving comes from Fortnite vehicle spawners): use the "
      "model as a prop, set dressing, cinematic or animated set piece unless the current UEFN version allows "
      "custom vehicles — check the latest Epic docs.")
    w("")
    w("### Unity (2022 LTS / Unity 6)")
    w(f"1. **Drivable:** import `{asset}_Rigid.fbx` (Model: Convert Units ON, Bake Axis Conversion ON). Make an empty "
      "root with a **Rigidbody**" + (f" (mass {mass} kg)" if mass else "") + "; put the model under a *Visual* child "
      "rotated so the nose points **+Z** (Unity's forward). Add a MeshCollider (convex) or boxes for the body.")
    if wheels:
        w("2. Per wheel: an empty with a **WheelCollider** at the wheel center (radius/width from the table, in "
          "meters = cm/100); each frame copy `GetWorldPose` to the wheel object of the same name. Steering wheels "
          "= the *Steering* column, motor torque on *Driven*.")
    w(f"3. **Animated / cinematic:** import `SK_{asset}_LOD0.fbx` (Rig: Generic, root `b_root`; one clip per take: "
      f"{A}; loop the spin clips) or `SK_{asset}.glb` with glTFast. LOD Group with LOD1..3.")
    w("4. Materials: URP/HDRP Lit (Body with paint tint, Trim, Glass = Transparent, Lights = Emission with "
      "per-light masks).")
    w("")
    w("### Godot 4.x")
    w(f"1. **Drivable:** import `{asset}_Rigid.glb` (meters). Scene: **VehicleBody3D** root" +
      (f" (mass {mass})" if mass else "") + " → the imported body as child rotated so the nose points **+Z**; a "
      "CollisionShape3D (convex/box) for the hull.")
    if wheels:
        w("2. One **VehicleWheel3D** per wheel at the wheel center; reparent the wheel mesh of the same name under it "
          "(zero its local transform); `wheel_radius` = radius/100, `use_as_steering` = Steering, "
          "`use_as_traction` = Driven; tune suspension travel/stiffness.")
    w(f"3. **Animated:** `SK_{asset}.glb` → AnimationPlayer clips ({A}); loop spin clips in Advanced Import "
      "Settings; Meshes → Generate LODs. Sockets: `BoneAttachment3D` (skeletal) or the empties (rigid).")
    w("4. Materials: StandardMaterial3D/ORMMaterial3D; glass Transparency Alpha; lights Emission.")
    w("")
    w("### Any engine — checklist")
    w("Real size matches `dimensions_cm` · nose points to the engine's forward · wheels touch the ground at rest "
      "(origin on the ground) · pivots of doors/wheels/rotors are on the hinge/hub · glass and light slots got the "
      f"right material · seats/exits sockets line up with the character. Class: {cls or '—'}.")
    w("")


def write_doc(spec):
    from .rig import bone_of, parts_by_id
    doc_path, hist_path = _paths(spec)
    h = _load(hist_path)
    parts = spec.get("parts", [])
    pmap = parts_by_id(spec)
    scene = _scene()
    notes = spec.get("layer_notes", {})
    lb, lf = h["last"].get("build", {}), h["last"].get("finalize", {})
    from .generators import Builder
    layer_of = Builder(spec).layer
    asset = spec.get("asset", "Vehicle")
    spec_file = spec.get("_file", "layer_spec.json")
    children = {}
    for p in parts:
        if p.get("parent"):
            children.setdefault(p["parent"], []).append(p["id"])

    def desc_of(pid):
        out, stack = [], list(children.get(pid, []))
        while stack:
            c = stack.pop(0)
            if c not in out:
                out.append(c)
                stack += children.get(c, [])
        return out

    by_layer = {}
    for p in parts:
        by_layer.setdefault(layer_of(p), []).append(p)
    L = []
    w = L.append
    w(f"# {asset} — vehicle parts document")
    w("")
    w(f"> Auto-generated by the `vehicle-rig-builder` skill (veh) on {datetime.datetime.now():%Y-%m-%d %H:%M}. "
      "**Do not edit by hand** — edit the spec (`brief`, `layer_notes`, `decisions`, part `description`, "
      "`motion`, `animations`) and rebuild.")
    w("")
    w("## 1. Summary")
    w("")
    w(spec.get("brief") or "_(no brief: add `brief` to the spec)_")
    w("")
    w(f"- **Spec (source of truth):** `{spec_file}`")
    org = spec.get("origin_cm") or (f"socket `{spec['origin_socket']}`" if spec.get("origin_socket")
                                    else "ground point under the bounding-box center")
    w(f"- **Class:** {spec.get('vehicle_class', '—')} · **Vehicle space:** +X forward, +Z up, +Y = left (port); "
      f"units cm; origin = {org}.")
    if spec.get("dimensions_cm"):
        w(f"- **Real dimensions (cm):** `{json.dumps(spec['dimensions_cm'])}`")
    for v, vd in (spec.get("views") or {}).items():
        if vd and vd.get("image"):
            w(f"- **Reference `{v}`:** `{vd['image']}` · calib `{vd.get('calib')}`")
    moving = [p["id"] for p in parts if p.get("motion")]
    w(f"- **Parts:** {len(parts)} · **moving:** {len(moving)} ({', '.join(moving) or '—'})")
    if lb.get("stats"):
        w(f"- **Tris per layer:** `{json.dumps(lb['stats'])}`")
    w("")
    w("## 2. How to modify (instructions for agents)")
    w("")
    w("1. Never edit meshes, bones or actions generated from the spec by hand — they are rebuilt.")
    w("2. Shape change → edit the part in the spec → `veh.build(SPEC, only=[part + dependents])` → `veh.review(...)`.")
    w("3. Motion change (axis, pivot, range) or new moving part → edit `motion` → `veh.finalize(SPEC, EXPORT)` "
      "(rebuilds rig, animations, checks, LODs, FBX, .blend).")
    w("4. Animation change → edit `animations` (keys are normalized 0..1 of the motion range) → `veh.finalize`. "
      "If an animator retouched actions in Blender, set `\"lock_animations\": true` so finalize keeps them.")
    w("5. Keep `id`s stable: bones are `b_<id>`, rigid objects `<id>`, actions `A_<asset>_<name>`; renaming breaks "
      "engine references (wheel setups, Blueprints, scripts).")
    w("6. Left/right: edit only the LEFT part (`mirror: true`); its `_R` copy is regenerated (ids *_L → *_R).")
    w("")
    w("```python")
    w("import sys, importlib")
    w("sys.path.insert(0, r\"<skill folder>\\scripts\"); import veh; importlib.reload(veh)")
    w(f"SPEC = r\"{spec_file}\"")
    w("```")
    w("")
    w("## 3. Layers")
    w("")
    w("| Layer | What it is in this vehicle | Material | Parts | Moving | Tris |")
    w("|---|---|---|---|---|---|")
    for ln in LAYER_NAMES:
        ps = by_layer.get(ln, [])
        w(f"| {ln} | {notes.get(ln) or LAYER_ROLE[ln]} | {DEFAULT_LAYER_MATERIAL[ln]} | {len(ps)} | "
          f"{sum(1 for p in ps if p.get('motion'))} | {(lb.get('stats') or {}).get(ln, '—')} |")
    w("")
    for ln in LAYER_NAMES:
        ps = by_layer.get(ln, [])
        if not ps:
            continue
        w(f"### {ln}")
        w("")
        w(f"**Represents:** {notes.get(ln) or LAYER_ROLE[ln]}")
        w("")
        w("| Part | Type | What it is | Parent | Bone | Motion | Key params | Objects (tris) |")
        w("|---|---|---|---|---|---|---|---|")
        for p in ps:
            sc = scene.get(p["id"], {})
            prm = ", ".join(f"{k}={p[k]}" for k in PARAM_KEYS if k in p) or "—"
            w(f"| `{p['id']}` | {p.get('type', 'profile')} | {p.get('description') or '⚠️ _missing description_'} | "
              f"{p.get('parent') or '—'} | `{bone_of(spec, p['id'], pmap)}` | {_motion_txt(p)} | {prm} | "
              f"{', '.join(f'`{o}`' for o in sc.get('objects', [])) or '—'} ({sc.get('tris', '—')}) |")
        w("")
        rebuild = []
        for p in ps:
            for x in [p["id"]] + desc_of(p["id"]):
                if x not in rebuild:
                    rebuild.append(x)
        w("Modify shapes in this layer (includes dependents):")
        w("```python")
        w(f"veh.build(SPEC, only={json.dumps(rebuild)}); veh.review(SPEC, RENDERS, '{ln.lower()}')")
        w("```")
        w("")
    w("## 4. Rig")
    w("")
    w("Named-axis bones point along +Y with zero roll (bone-local axes = vehicle axes); vector-axis bones point "
      "along their hinge and are keyed on local Y. Static parts ride on the bone of their nearest moving ancestor. "
      "The rigid export (`<asset>_Rigid`) has one object per bone below with the same names minus `b_`.")
    w("")
    tree = {}
    for p in parts:
        if p.get("motion"):
            par = p.get("parent")
            tree.setdefault(bone_of(spec, par, pmap) if par else "b_body", []).append(p)

    def walk(b, depth):
        for p in tree.get(b, []):
            w(f"{'  ' * depth}- `b_{p['id']}` — {p.get('description', '')} — {_motion_txt(p)}")
            walk("b_" + p["id"], depth + 1)

    w("- `b_root` (asset origin)")
    w("  - `b_body` — all static parts")
    walk("b_body", 2)
    w("")
    socks = spec.get("sockets", [])
    if socks:
        w("**Sockets** (non-deforming bones; empties in the rigid export):")
        w("")
        w("| Socket | At | On bone | Purpose |")
        w("|---|---|---|---|")
        for s in socks:
            at = s.get("at_3d") or f"{s.get('at')} y={s.get('y_cm', 0)}"
            w(f"| `{s['name']}` | {at} | "
              f"`{bone_of(spec, s['parent'], pmap) if s.get('parent') else 'b_body'}` | {s.get('description', '')} |")
        w("")
    w("## 5. Animations")
    w("")
    anims = (lf.get("animations") or {})
    if spec.get("animations"):
        w("| Animation | Action | Frames @fps | Parts | Description |")
        w("|---|---|---|---|---|")
        for a in spec["animations"]:
            s = anims.get(a["name"], {})
            w(f"| {a['name']} | `A_{asset}_{a['name']}` | {s.get('frames', '?')} @{a.get('fps', 30)} | "
              f"{', '.join(s.get('parts', [])) or a.get('preset', '')} | {a.get('description', '')} |")
        w("")
        w("Retouch in Blender: select the rig → Action Editor/Graph Editor → pick `A_...`; each action also has a "
          "muted NLA track. Then set `lock_animations: true` in the spec before running finalize again.")
    else:
        w("_(no animations in the spec)_")
    w("")
    w("## 6. Materials")
    w("")
    w("| Slot | Unreal master | Behavior | Layers |")
    w("|---|---|---|---|")
    for s in SLOT_ORDER:
        w(f"| `{s}` | `{SLOT_INFO[s][0]}` | {SLOT_INFO[s][1]} | "
          f"{', '.join(ln for ln in LAYER_NAMES if DEFAULT_LAYER_MATERIAL[ln] == s) or 'per-part override'} |")
    w("")
    w("## 7. Motion check, QA and export (last finalize)")
    w("")
    if lf:
        w(f"_Date: {lf['time']}_")
        w("")
        for pid, r in (lf.get("motion_check") or {}).items():
            flag = "⚠️ " if r.get("new_intersections") else "✅ "
            exp = r.get("expected_contacts") or {}
            w(f"- {flag}`{pid}` carries {r.get('carries') or '—'}; new intersections: "
              f"`{json.dumps(r.get('new_intersections'))}`" + (f"; expected (allow_contact): `{sorted(exp)}`" if exp else ""))
        w(f"- **QA:** `{json.dumps(lf.get('qa', {}))}`")
        w(f"- **LODs:** `{json.dumps(lf.get('lods', {}))}`")
        if lf.get("blend"):
            w(f"- **Project .blend:** `{lf['blend']}`")
        for f in lf.get("fbx", []):
            w(f"- FBX: `{f}`")
    else:
        w("_`finalize` has not run yet._")
    w("")
    _engines(w, spec, lf, asset)
    w("## 9. Design decisions")
    w("")
    for d in spec.get("decisions") or ["_(add `decisions` to the spec)_"]:
        w(f"- {d}")
    w("")
    w("## 10. Pending items and warnings")
    w("")
    pend = [f"- Part without `description`: `{p['id']}`" for p in parts if not p.get("description")]
    pend += [f"- Moving part without animation: `{pid}`" for pid in moving
             if not any(pid in (anims.get(a["name"], {}).get("parts") or []) for a in spec.get("animations", []))]
    pend += [f"- {x}" for x in (lb.get("log") or []) if "WARNING" in x or "ERROR" in x]
    if lb.get("errors"):
        pend.append(f"- Build errors: `{json.dumps(lb['errors'])}`")
    for x in pend or ["- None."]:
        w(x)
    w("")
    w("## 11. History")
    w("")
    w("| Date | Action | Detail |")
    w("|---|---|---|")
    for ev in h["events"][-30:]:
        det = {"build": f"built {len(ev.get('built', {}))} · tris {(ev.get('stats') or {}).get('TOTAL', '?')}",
               "finalize": f"LOD0 tris {(ev.get('qa') or {}).get('tris', '?')} · {len(ev.get('fbx', []))} FBX · "
                           f"{len(ev.get('animations') or {})} anims",
               "setup": "scene, units, materials"}.get(ev["kind"], "")
        w(f"| {ev['time']} | {ev['kind']} | {det} |")
    w("")
    try:
        with open(doc_path, "w", encoding="utf-8") as f:
            f.write("\n".join(L))
        log(f"Document updated: {doc_path}")
    except Exception as e:  # noqa
        log(f"Could not write the document: {e}")
    return doc_path
