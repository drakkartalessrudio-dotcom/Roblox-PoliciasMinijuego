# Spec reference of the vendored `veh` core (`<Asset>.spec.json`)

> Copied from the vehicle-rig-builder skill. In this skill the rig, animation and engine-export fields (`motion`, `animations`, `lod_*`, `fbx_axis_*`, `export_*`) are accepted but **not used**: the Roblox export has no skeleton, LODs or glTF. The Roblox-only fields (`roblox`, `rbx_group`) are in [spec-format.md](spec-format.md).

## Top level
| Field | Default | Meaning |
|---|---|---|
| `asset` | "Vehicle" | name → `SK_<asset>`, `<asset>_Rig`, `<asset>_Rigid`, `A_<asset>_<Anim>`, `<asset>_PARTS.md`, `<asset>.blend` |
| `vehicle_class` | — | e.g. "land / 4-door sedan (RWD)", "air / helicopter", "sea / patrol boat" (document) |
| `brief`, `layer_notes`, `decisions` | — | approved brief, `{layer: meaning}`, design decisions (document) |
| `dimensions_cm` | — | real-world reference dimensions (document + checklist) |
| `mass_kg` | — | written into the engine section (Chaos / Rigidbody / VehicleBody3D) |
| `default_space` | "cm" | point space of parts: `cm` or `px` (needs that view's `calib`) |
| `views.<side|top|front>` | — | `{"image": "refs/side.png", "regions": "seg_side/regions.json", "calib": {"a_px": [x,y], "a_cm": [u,v], "b_px": [..], "b_cm": [..], "flip_x": false}, "ref_depth_cm": 1000}`. side = [x,z], top = [x,y], front = [y,z]. `flip_x` for blueprints with the nose pointing left |
| `origin_cm` / `origin_socket` | ground under bbox center | asset origin (boats: waterline; aircraft: ground) |
| `parts`, `sockets`, `animations` | [] | see below |
| `materials` | {} | preview overrides: `{"MI_Body": {"base_color": [r,g,b], "metallic", "roughness"}, "MI_Trim": {...}, "MI_Glass": {"color", "alpha"}, "MI_Lights": {"color", "strength"}}` |
| `lod_ratios` | [1, .5, .25, .12] | LOD decimation ratios |
| `lod_drop_layers` | `{"L5_Interior": 2, "L8_Details": 3}` | remove whole layers from LOD n and below |
| `bone_length_cm` | 20 | display length of bones |
| `auto_unwrap`, `motion_check`, `lock_animations` | true, true, false | finalize switches |
| `export_gltf`, `export_rigid`, `save_blend` | true | extra outputs |
| `fbx_axis_forward` / `fbx_axis_up` | "-Z" / "Y" | FBX axes |

## Common part fields
| Field | Meaning |
|---|---|
| `id` | unique, snake_case; left/right pairs end in `_L`/`_FL`/`_RL`… (mirror gives `_R`/`_FR`/`_RR`) |
| `type` | `hull`, `panel`, `profile`, `wing`, `lathe`, `wheel`, `cylinder`, `box`, `tube`, `ai_part` |
| `description` | REQUIRED (document) |
| `role` | semantic role used by animation presets, layers and engine docs: `wheel`, `steer`, `suspension`, `door`, `hood`, `trunk`, `hatch`, `canopy`, `ramp`, `rotor`, `tail_rotor`, `prop`, `gear`, `gear_door`, `aileron_L`, `elevator`, `rudder`, `flap`, `turret`, `gun`, `outboard`, `outboard_tilt`, `steering_wheel`, `sprocket`, `radar`, or your own |
| `mirror` | true → a right-side copy is generated (ids, parents, panels' `from`, y values, top/front points, motion axes and signs, `allow_contact`, roles `*_L`→`*_R`, "left"→"right" in descriptions) |
| `layer` | default from role, then type (`hull` L0, `panel` L2, `wheel` L3, `wing`/`profile`/`lathe` L1, small primitives L8) |
| `parent` | part it moves with |
| `material` | slot override: `MI_Body`, `MI_Trim`, `MI_Glass`, `MI_Lights` |
| `bevel_cm` (0.3), `bevel_segments` (2) | bevel modifier (0 = none) |
| `space`, `enabled` | per-part point space, skip |
| `motion` | makes it a MOVING part (below) |

Positions: most types accept `center_cm: [x, y, z]` (3D) or side `center: [x, z]` + `y_cm`.

## Part types
- **hull** — `side: [[x,z]...]`, `top: [[x,y]...]` (+ `top_half: true` = only y ≥ 0, mirrored), optional `front: [[y,z]...]`
  (+ `front_half`). Result = intersection of the three extrusions (EXACT boolean). Car bodies, fuselages, boat hulls,
  tank hulls, turrets, cabins. Outlines may be `"side:<region id>"` refs (px, needs calib).
- **panel** — piece of another part: `from: <part id>`, `view: side|top|front`, `poly` (outline in that view),
  depth start `y_from_cm` (side; sign = which side), `z_from_cm` (top; upward), `x_from_cm` (front; sign = direction),
  or `through: true` (both sides). `gap_cm` (0.4) shrinks the panel; `cut` (true) gives the source a recess;
  `cut_only: true` = recess only, no panel (wheel wells, cockpits, gear bays, cargo beds). Panels are built after all
  other parts; rebuilding the source rebuilds its panels.
- **profile** — side `poly` extruded along Y: `thickness_cm`, `y_cm`.
- **wing** — `planform` in the top view (`[[x, y]]`, root at the smallest |y|), `z_cm`, `thickness_cm`,
  `tip_thickness_ratio` (0.5), `dihedral_deg`. `plane: "side"` → vertical fin (`planform [[x, z]]`, `y_cm`).
- **lathe** — `center_cm`, `axis` (X/Y/Z), `profile: [[t, r]]` (t along the axis from the center, r radius), `caps`,
  `segments`. Closed loop + `caps: false` for hollow rings (cowlings, nozzles).
- **wheel** — `center_cm`, `radius_cm`, `width_cm`, `rim_ratio` (0.62), `rim_dish`, `segments` (32);
  `tire_material` / `rim_material`. Rim faces outward automatically (+Y on the left, −Y on the right). For physics docs:
  `driven` (default true), `steering` (default: true if a `steer` part is in its parent chain).
- **cylinder** — `center_cm`, `radius_cm`, `radius2_cm` (cone), `length_cm`, `axis` (X/Y/Z or vector).
- **box** — `center_cm`, `size_cm: [sx, sy, sz]`, `rotate_xyz_deg` (or `rotate_deg` around Y).
- **tube** — `path_3d: [[x,y,z]]` (or side `path` + `y_cm`), `radius_cm` + `sides`, or `section_cm: [w, h]`; `closed`.
  Exhausts, rails, roll cages, skids, struts, cables, track bands.
- **ai_part** — `file` (GLB/FBX/OBJ), `center_cm`, `size_cm` (largest dimension), `front_axis`, `part_map`.

## Motion
```json
"motion": {"type": "rotate", "axis": "Z", "min": 0, "max": -65, "pivot": [262, 70], "pivot_y_cm": 88,
           "allow_contact": ["body"]}
"motion": {"type": "rotate", "axis": [7, 215, 0], "min": -20, "max": 20, "pivot_3d": [600, 330, 190]}
```
- `type`: `translate` (cm) or `rotate` (deg). `axis`: X (forward), Y (left), Z (up), or a vector (hinge line).
- Pivot: `pivot_3d` [x,y,z], or side `pivot` [x,z] + `pivot_y_cm` (default the part's y), else bbox center (hubs).
- v = normalized 0..1 between `min` and `max`. The modeled pose is the "rest" value (where 0 falls, e.g. 0.5 for −35..35).
- Sign rules (right-hand rule): around Y, positive moves points ABOVE the pivot forward (wheel rolling forward = +;
  a hood hinged at its rear opens with −; a trunk hinged at its front opens with +); around Z, positive turns +X toward
  +Y (a left door hinged at its front opens with −); around X, positive turns +Y toward +Z.
- `allow_contact`: parts this motion may touch (motion check reports them as expected).

## Animations
```json
{"name": "Drive", "preset": "drive_loop"}
{"name": "Steer", "preset": "boat_rudder", "roles": {"outboard": ["outboard", "steering_wheel"]}}
{"name": "Radar", "length": 60, "tracks": [{"role": "radar", "keys": [[0, 0], [60, 1]], "interp": "LINEAR", "cycle": true}]}
```
Keys `[frame, v]`; v may be `"rest"`. Tracks address a `part` id or a `role` (all parts with it). `cycle` adds a Cycles
modifier and marks the take as a loop. `length` on a preset rescales its timing. Presets (`veh/anim.py`): `idle`,
`drive_loop`, `steer_left_right`, `suspension_bounce`, `doors_open_close`, `hood_trunk`, `hatch_open_close` (hatch,
canopy, ramp), `rotor_spin`, `prop_spin`, `control_check`, `gear_retract`, `gear_extend`, `turret_traverse`,
`boat_rudder` (rudder, outboard), `track_loop` (wheel, sprocket).

## Sockets
`{"name": "Seat_Driver", "at_3d": [x, y, z], "parent": "<part id>", "mirror": true, "description": "..."}`
(or side `at` [x,z] + `y_cm`). Non-deforming bones in the skeletal export, empties in the rigid export.
Typical: `Seat_*`, `Exit_L/R`, `Gunner`, `Muzzle*`, `Exhaust*`, `Headlight_*`, `Wake`, `Spray_*`, `Downwash`,
`Rope_*`, `Camera_Chase`, `Camera_FP`.
