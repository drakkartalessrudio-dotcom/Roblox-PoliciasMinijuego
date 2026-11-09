#!/usr/bin/env python3
"""Segment a reference image into candidate layer regions (plates, lights, plasma, mechanics).

Does NOT run inside Blender. Requires: python 3.9+, numpy, opencv-python(-headless).
Optional: ultralytics ('sam' mode: Segment Anything 2 / FastSAM).

Outputs in --out:
  grid.png      original image with a pixel grid (to read coordinates and calibration points)
  overlay.png   colored, numbered regions (Claude reviews them and assigns them to layers in the spec)
  regions.json  {"image", "size", "regions": [{id, polygon_px, bbox, area_px, mean_rgb, brightness,
                 saturation, tag}]}

Usage:
  python segment_reference.py ref_front.png --out seg_front [--mode color|sam|both] [--roi x0 y0 x1 y1]
"""
import argparse
import json
import os
import sys

try:
    import cv2
    import numpy as np
except ImportError:
    sys.exit("Missing OpenCV/numpy:  pip install opencv-python-headless numpy")


def load(path):
    img = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if img is None:
        sys.exit(f"Could not read {path}")
    alpha = None
    if img.ndim == 3 and img.shape[2] == 4:
        alpha = img[:, :, 3]
        img = img[:, :, :3]
    elif img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    return img, alpha


def foreground_mask(img, alpha, roi):
    h, w = img.shape[:2]
    m = np.zeros((h, w), np.uint8)
    if roi:
        x0, y0, x1, y1 = roi
        m[y0:y1, x0:x1] = 255
    else:
        m[:] = 255
    if alpha is not None:
        m &= (alpha > 20).astype(np.uint8) * 255
    else:
        # remove uniform background (corner color)
        corners = np.concatenate([img[:8, :8].reshape(-1, 3), img[:8, -8:].reshape(-1, 3),
                                  img[-8:, :8].reshape(-1, 3), img[-8:, -8:].reshape(-1, 3)]).astype(np.float32)
        bg = np.median(corners, axis=0)
        if corners.std(axis=0).max() < 12:
            d = np.linalg.norm(img.astype(np.float32) - bg, axis=2)
            m &= (d > 18).astype(np.uint8) * 255
    return m


def masks_color(img, fg, k, min_area):
    """Color regions (k-means in Lab) split by edges (the seams between plates)."""
    h, w = img.shape[:2]
    smooth = cv2.bilateralFilter(img, 9, 40, 9)
    lab = cv2.cvtColor(smooth, cv2.COLOR_BGR2LAB).reshape(-1, 3).astype(np.float32)
    sel = fg.reshape(-1) > 0
    data = lab[sel]
    if len(data) < k:
        return []
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5)
    _, labels, _ = cv2.kmeans(data, k, None, crit, 3, cv2.KMEANS_PP_CENTERS)
    full = np.full(h * w, -1, np.int32)
    full[sel] = labels.reshape(-1)
    full = full.reshape(h, w)
    gray = cv2.cvtColor(smooth, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 40, 110)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8))
    out = []
    for c in range(k):
        m = ((full == c) & (edges == 0)).astype(np.uint8) * 255
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        n, lab_cc, stats, _ = cv2.connectedComponentsWithStats(m, 8)
        for i in range(1, n):
            if stats[i, cv2.CC_STAT_AREA] >= min_area:
                out.append(((lab_cc == i).astype(np.uint8) * 255, "color"))
    return out


def masks_emissive(img, fg, min_area):
    """Bright, saturated areas = light / plasma candidates."""
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    v, s = hsv[:, :, 2], hsv[:, :, 1]
    m = (((v > 200) & (s > 90)) | (v > 245)).astype(np.uint8) * 255
    m &= fg
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab_cc, stats, _ = cv2.connectedComponentsWithStats(m, 8)
    return [((lab_cc == i).astype(np.uint8) * 255, "emissive_candidate")
            for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] >= max(12, min_area // 8)]


def masks_sam(path, fg, min_area, model_name):
    try:
        from ultralytics import SAM, FastSAM
    except ImportError:
        print("ultralytics not installed; skipping SAM mode (pip install ultralytics)")
        return []
    model = FastSAM(model_name) if "fastsam" in model_name.lower() else SAM(model_name)
    res = model(path, verbose=False)
    out = []
    for r in res:
        if r.masks is None:
            continue
        for m in r.masks.data.cpu().numpy():
            m = (cv2.resize(m.astype(np.uint8), (fg.shape[1], fg.shape[0]), interpolation=cv2.INTER_NEAREST) * 255)
            m &= fg
            if int((m > 0).sum()) >= min_area:
                out.append((m, "sam"))
    return out


def dedupe(masks, iou_thr=0.85):
    keep = []
    for m, src in sorted(masks, key=lambda x: -int((x[0] > 0).sum())):
        mb = m > 0
        dup = False
        for k, _ in keep:
            kb = k > 0
            inter = np.logical_and(mb, kb).sum()
            union = np.logical_or(mb, kb).sum()
            if union and inter / union > iou_thr:
                dup = True
                break
        if not dup:
            keep.append((m, src))
    return keep


def describe(img, masks):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    regions = []
    for m, src in masks:
        cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        if not cnts:
            continue
        c = max(cnts, key=cv2.contourArea)
        peri = cv2.arcLength(c, True)
        poly = cv2.approxPolyDP(c, max(1.5, 0.004 * peri), True).reshape(-1, 2)
        if len(poly) < 3:
            continue
        x, y, w, h = cv2.boundingRect(c)
        sel = m > 0
        b, g, r = (float(img[:, :, i][sel].mean()) for i in range(3))
        sat = float(hsv[:, :, 1][sel].mean()) / 255
        val = float(hsv[:, :, 2][sel].mean()) / 255
        tag = src
        if src != "emissive_candidate":
            if val > 0.8 and sat > 0.35:
                tag = "emissive_candidate"
            elif w > 4 * h or h > 4 * w:
                tag = "strip_or_trim"
            elif val < 0.25:
                tag = "dark_detail_or_gap"
            else:
                tag = "panel"
        M = cv2.moments(c)
        cx = M["m10"] / M["m00"] if M["m00"] else x + w / 2
        cy = M["m01"] / M["m00"] if M["m00"] else y + h / 2
        regions.append({
            "polygon_px": poly.tolist(), "bbox": [x, y, x + w, y + h], "centroid": [round(cx, 1), round(cy, 1)],
            "area_px": int(sel.sum()), "mean_rgb": [round(r), round(g), round(b)],
            "brightness": round(val, 3), "saturation": round(sat, 3), "tag": tag, "source": src,
        })
    regions.sort(key=lambda r: (r["bbox"][1] // 40, r["bbox"][0]))
    for i, r in enumerate(regions):
        r["id"] = i
    return regions


def draw_grid(img, step):
    g = img.copy()
    h, w = g.shape[:2]
    for x in range(0, w, step):
        cv2.line(g, (x, 0), (x, h), (0, 255, 255) if x % (step * 5) == 0 else (90, 90, 90), 1)
        cv2.putText(g, str(x), (x + 2, 12), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 255, 255), 1)
    for y in range(0, h, step):
        cv2.line(g, (0, y), (w, y), (0, 255, 255) if y % (step * 5) == 0 else (90, 90, 90), 1)
        cv2.putText(g, str(y), (2, y - 2), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 255, 255), 1)
    return g


def draw_overlay(img, regions):
    ov = (img.astype(np.float32) * 0.45).astype(np.uint8)
    rng = np.random.default_rng(7)
    for r in regions:
        col = tuple(int(c) for c in rng.integers(60, 255, 3))
        pts = np.array(r["polygon_px"], np.int32)
        layer = ov.copy()
        cv2.fillPoly(layer, [pts], col)
        ov = cv2.addWeighted(layer, 0.45, ov, 0.55, 0)
        cv2.polylines(ov, [pts], True, col, 1)
    for r in regions:
        cx, cy = (int(v) for v in r["centroid"])
        label = str(r["id"]) + ("*" if r["tag"] == "emissive_candidate" else "")
        cv2.putText(ov, label, (cx - 6, cy + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 0), 3)
        cv2.putText(ov, label, (cx - 6, cy + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
    return ov


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", default="color", choices=["color", "sam", "both"])
    ap.add_argument("--roi", type=int, nargs=4, metavar=("X0", "Y0", "X1", "Y1"))
    ap.add_argument("--k", type=int, default=6, help="color clusters (color mode)")
    ap.add_argument("--min-area", type=float, default=0.0008, help="minimum area (fraction of the image)")
    ap.add_argument("--sam-model", default="sam2.1_b.pt", help="sam2.1_b.pt, sam_b.pt or FastSAM-s.pt")
    ap.add_argument("--grid", type=int, default=50, help="grid step in px")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    img, alpha = load(a.image)
    h, w = img.shape[:2]
    fg = foreground_mask(img, alpha, a.roi)
    min_area = int(a.min_area * h * w)
    masks = masks_emissive(img, fg, min_area)
    if a.mode in ("color", "both"):
        masks += masks_color(img, fg, a.k, min_area)
    if a.mode in ("sam", "both"):
        masks += masks_sam(a.image, fg, min_area, a.sam_model)
    masks = dedupe(masks)
    regions = describe(img, masks)
    cv2.imwrite(os.path.join(a.out, "grid.png"), draw_grid(img, a.grid))
    cv2.imwrite(os.path.join(a.out, "overlay.png"), draw_overlay(img, regions))
    with open(os.path.join(a.out, "regions.json"), "w", encoding="utf-8") as f:
        try:
            img_ref = os.path.relpath(os.path.abspath(a.image), os.path.abspath(a.out))
        except ValueError:  # different drive on Windows
            img_ref = os.path.abspath(a.image)
        json.dump({"image": img_ref, "size": [w, h], "mode": a.mode, "regions": regions}, f, indent=1)
    tags = {}
    for r in regions:
        tags[r["tag"]] = tags.get(r["tag"], 0) + 1
    print(json.dumps({"regions": len(regions), "per_tag": tags, "output": os.path.abspath(a.out)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
