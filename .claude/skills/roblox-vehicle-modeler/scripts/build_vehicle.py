"""Headless build of one Roblox vehicle from its spec.

    blender -b --factory-startup -P build_vehicle.py -- <spec.json> [review|export|all]

Output next to the spec:
    renders/blockout_*.png          review views (side, front, top, 3/4)
    Export/<Asset>_Roblox.fbx       the pieces, in studs, in the Roblox model frame, with clean nodes
    Export/<Asset>.manifest.json    schema 2 manifest (parts, sockets, rig data)
    <Asset>_PARTS.md, <Asset>.blend

The spec is the generic `veh` spec plus a `roblox` block (references/spec-format.md). Exit code 1 if the build has
errors or the written FBX does not match the manifest.
"""
import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import veh  # noqa: E402  (vendored modeling core)
from rbx import docs, export  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not argv:
    print(__doc__)
    sys.exit(2)
SPEC = os.path.abspath(argv[0])
MODE = argv[1] if len(argv) > 1 else "all"
ROOT = os.path.dirname(SPEC)
RENDERS = os.path.join(ROOT, "renders")
EXPORT = os.path.join(ROOT, "Export")
failed = False

with open(SPEC, encoding="utf-8") as fh:
    spec_data = json.load(fh)
if "roblox" not in spec_data:
    print("ERROR: the spec has no 'roblox' block (bodyType, materials). See references/spec-format.md")
    sys.exit(2)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

res = veh.setup(SPEC)
print("SETUP", res["log"])
res = veh.build(SPEC)
print("BUILD errors:", res["errors"])
print("BUILD log:", res["log"])
print("TRIS by layer:", json.dumps(res["stats"]))
failed = failed or bool(res["errors"])

if MODE in ("review", "all"):
    r = veh.review(SPEC, RENDERS, "blockout", ["side_left", "front", "top", "three_quarter", "three_quarter_rear"])
    print("RENDERS", r["renders"], r["log"])

if MODE in ("export", "all"):
    manifest = export.export_roblox(veh, SPEC, EXPORT)
    veh.save_project(SPEC)
    docs.write(spec_data, manifest, SPEC, ROOT)
    print("ROBLOX EXPORT", os.path.join(EXPORT, manifest["fbx"]), "TRIS", manifest["tris"]["total"],
          {n: p["tris"] for n, p in manifest["parts"].items()})
    for problem in manifest["verify"]:
        print("VERIFY ERROR:", problem)
    failed = failed or bool(manifest["verify"])

print("PIPELINE DONE" + (" WITH ERRORS" if failed else ""))
sys.exit(1 if failed else 0)
