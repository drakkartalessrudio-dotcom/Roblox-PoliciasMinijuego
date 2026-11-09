#!/usr/bin/env python3
"""Tools for regions.json (output of segment_reference.py).

  python regions_tool.py list   seg_front/regions.json
  python regions_tool.py merge  seg_front/regions.json 4 5 6        -> new region = union
  python regions_tool.py add    seg_front/regions.json "x,y x,y x,y ..."   -> hand-drawn polygon
  python regions_tool.py mirror seg_front/regions.json 4 --axis-x 400 -> mirrored region (symmetry)

Each operation appends a region with a new id and redraws overlay.png.
"""
import json
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from segment_reference import draw_overlay  # noqa: E402


def load(p):
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def save(p, d):
    with open(p, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=1)
    ip = d["image"]
    if not os.path.isabs(ip):
        ip = os.path.join(os.path.dirname(os.path.abspath(p)), ip)
    img = cv2.imread(ip)
    if img is not None:
        cv2.imwrite(os.path.join(os.path.dirname(p), "overlay.png"), draw_overlay(img, d["regions"]))


def new_region(d, poly, tag, note):
    pts = np.array(poly, np.int32)
    x, y, w, h = cv2.boundingRect(pts)
    M = cv2.moments(pts)
    cx = M["m10"] / M["m00"] if M["m00"] else x + w / 2
    cy = M["m01"] / M["m00"] if M["m00"] else y + h / 2
    rid = max([r["id"] for r in d["regions"]] + [-1]) + 1
    r = {"id": rid, "polygon_px": pts.tolist(), "bbox": [x, y, x + w, y + h], "centroid": [round(cx, 1), round(cy, 1)],
         "area_px": int(cv2.contourArea(pts)), "tag": tag, "source": note}
    d["regions"].append(r)
    return r


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, path = sys.argv[1], sys.argv[2]
    d = load(path)
    by_id = {str(r["id"]): r for r in d["regions"]}
    if cmd == "list":
        for r in d["regions"]:
            print(r["id"], r.get("tag"), r["bbox"], r.get("area_px"))
        return
    if cmd == "merge":
        W, H = d["size"]
        m = np.zeros((H, W), np.uint8)
        for i in sys.argv[3:]:
            cv2.fillPoly(m, [np.array(by_id[i]["polygon_px"], np.int32)], 255)
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
        cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        if len(cnts) > 1:
            print(f"WARNING: regions do not touch ({len(cnts)} islands); keeping only the largest. "
                  "For separate pieces use separate parts in the spec.")
        c = max(cnts, key=cv2.contourArea)
        poly = cv2.approxPolyDP(c, max(1.5, 0.004 * cv2.arcLength(c, True)), True).reshape(-1, 2)
        r = new_region(d, poly, "panel", "merge:" + "+".join(sys.argv[3:]))
    elif cmd == "add":
        poly = [[int(float(v)) for v in p.split(",")] for p in sys.argv[3].split()]
        r = new_region(d, poly, sys.argv[4] if len(sys.argv) > 4 else "manual", "manual")
    elif cmd == "mirror":
        src = by_id[sys.argv[3]]
        ax = float(sys.argv[sys.argv.index("--axis-x") + 1])
        poly = [[int(round(2 * ax - x)), y] for x, y in src["polygon_px"]][::-1]
        r = new_region(d, poly, src.get("tag", "panel"), f"mirror:{src['id']}")
    else:
        sys.exit(__doc__)
    save(path, d)
    print(json.dumps({"new_region": r["id"], "bbox": r["bbox"], "source": r["source"]}))


if __name__ == "__main__":
    main()
