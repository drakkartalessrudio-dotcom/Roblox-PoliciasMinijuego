"""Blender preview materials. Names = slot names the engine will see (max 4 slots, fixed order)."""
import bpy

from .common import SLOT_ORDER, log

DEFAULTS = {
    "MI_Body": {"base_color": [0.32, 0.36, 0.30], "metallic": 0.6, "roughness": 0.45},   # paint / hull
    "MI_Trim": {"base_color": [0.05, 0.05, 0.055], "metallic": 0.2, "roughness": 0.7},   # rubber, plastic, raw metal
    "MI_Glass": {"color": [0.55, 0.7, 0.8], "alpha": 0.25, "roughness": 0.03},
    "MI_Lights": {"color": [1.0, 0.85, 0.6], "strength": 12.0},
}


def _set(node, value, *names):
    for n in names:
        if n in node.inputs:
            node.inputs[n].default_value = value
            return


def ensure_materials(spec=None):
    cfg = {k: dict(v) for k, v in DEFAULTS.items()}
    for k, v in ((spec or {}).get("materials") or {}).items():
        cfg.setdefault(k, {}).update(v)
    out = {}
    for name in SLOT_ORDER:
        c = cfg[name]
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) \
            or mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        col = c.get("base_color") or c.get("color")
        _set(bsdf, (*col, 1.0), "Base Color")
        if name in ("MI_Body", "MI_Trim"):
            _set(bsdf, c.get("metallic", 0.5), "Metallic")
            _set(bsdf, c.get("roughness", 0.5), "Roughness")
            mat.diffuse_color = (*col, 1.0)
        elif name == "MI_Lights":
            _set(bsdf, (*col, 1.0), "Emission Color", "Emission")
            _set(bsdf, c.get("strength", 12.0), "Emission Strength")
            mat.diffuse_color = (*col, 1.0)
        else:
            _set(bsdf, c.get("roughness", 0.03), "Roughness")
            _set(bsdf, c.get("alpha", 0.25), "Alpha")
            _set(bsdf, 1.0, "Transmission Weight", "Transmission")
            if hasattr(mat, "surface_render_method"):
                mat.surface_render_method = "BLENDED"
            mat.diffuse_color = (*col, 0.4)
        out[name] = mat
    log("Preview materials ready: " + ", ".join(out))
    return out


def assign(obj, slot_name):
    mat = bpy.data.materials.get(slot_name) or ensure_materials()[slot_name]
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0
