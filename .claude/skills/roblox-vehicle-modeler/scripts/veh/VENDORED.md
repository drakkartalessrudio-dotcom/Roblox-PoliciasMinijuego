# Vendored: `veh` (modeling core)

Copy of the `veh` library of the **vehicle-rig-builder** skill (`3D Artist skill/Conveyances/scripts/veh`, version 1.0.0, copied on 2026-10-16). It is the engine-neutral modeling core: blueprint silhouettes, panels with gaps and recesses, wheels, wings, lathes, primitives, review renders.

It is **not kept in sync** with the original: the Roblox skill is self-contained and the two skills evolve separately. The Roblox pipeline only uses `veh.setup`, `veh.build`, `veh.review`, `veh.save_project`, `veh.objects_in_layers` and `veh.common.prepare`. The rig, animation, LOD and engine-export modules (`rig.py`, `anim.py`, `export.py`, `check.py`, most of `docs.py`) come along because `veh/__init__.py` imports them; the Roblox export does not call them.

Local changes against the original: none. If you change something here, list it below.
