"""Which Roblox piece each Blender object belongs to (pure Python).

Roblox pieces (one MeshPart each): Chassis, Windows, Trim, Lights, Bumpers, Tire_FL/FR/RL/RR, Rim_FL/FR/RL/RR and the
optional Roof, Bed and Neon. A spec part can force its piece with `"rbx_group": "<Piece>"`.
"""
from __future__ import annotations

OPTIONAL_PIECES = ("Roof", "Bed", "Neon")
WHEELS = ("FL", "FR", "RL", "RR")
REQUIRED_PIECES = (
    "Chassis", "Windows",
    "Tire_FL", "Tire_FR", "Tire_RL", "Tire_RR",
    "Rim_FL", "Rim_FR", "Rim_RL", "Rim_RR",
)
REQUIRED_SOCKETS = (
    "Socket_Spoiler",
    "Socket_Wheel_FL", "Socket_Wheel_FR", "Socket_Wheel_RL", "Socket_Wheel_RR",
    "Socket_Exhaust",
    "Socket_FrontBumper", "Socket_RearBumper",
    "Socket_RoofExtra",
)
NATIVE_MATERIALS = ("SmoothPlastic", "Plastic", "Metal", "Glass", "Neon", "Foil", "Concrete", "Wood", "Fabric")


def piece_of(layer: str, spec_part: str, veh_part: str, material_name: str = "", override: str | None = None) -> str:
    """layer: veh layer (e.g. 'L6_Glass'); spec_part: id in the spec; veh_part: generated object id;
    material_name: preview material slot (e.g. 'MI_Trim'); override: the part's `rbx_group`, if any."""
    if override:
        return override
    if layer == "L6_Glass":
        return "Windows"
    if spec_part == "bed":
        return "Bed"
    if spec_part.startswith("roof_cap"):
        return "Roof"
    if spec_part.startswith("neon"):
        return "Neon"
    if spec_part.startswith("bumper"):
        return "Bumpers"
    if layer == "L7_Lights":
        return "Lights"
    if spec_part.startswith("wheel_"):
        return ("Tire_" if veh_part.endswith("_tire") else "Rim_") + spec_part.split("_", 1)[1]
    if material_name == "MI_Trim":
        return "Trim"
    return "Chassis"


def kind_of(piece: str) -> str:
    """'Tire_FL' -> 'Tire', 'Chassis' -> 'Chassis'."""
    return piece.split("_", 1)[0]
