"""Axis conventions of the Roblox vehicle pipeline (pure Python, no Blender).

Vehicle space (the `veh` library and every spec): +X forward (nose), +Y left, +Z up. Units: cm in the spec.

Roblox model frame (what the FBX holds and what the manifest reports): +X right, +Y up, +Z back, so the nose points
to -Z. This is the frame `VehicleRig` expects from a Chassis part (front = -Z, right = +X), so no yaw is applied in
Luau and the chassis `LookVector` points where the car drives. Units: studs (1 stud = 0.28 m). Origin: ground under
the centre of the car.

    vehicle (vx, vy, vz)  ->  roblox (rx, ry, rz) = (-vy, vz, -vx)

The Blender FBX exporter used by the pipeline (axis_forward '-Z', axis_up 'Y') writes the file as
(x, z, -y) of the Blender scene. Studio's FBX importer then turns the model 180 degrees about Y (measured on the
imported .rbxm: Tire_FL arrives at (+x, +z) when the file holds it at (-x, -z)). So the FILE frame is the Roblox frame
yawed 180 degrees, (rx, ry, rz) -> (-rx, ry, -rz), and the geometry is rotated -90 degrees about Z before exporting:

    vehicle (vx, vy, vz)  ->  blender scene (bx, by, bz) = (vy, -vx, vz)
                              file = (bx, bz, -by) = (vy, vz, vx) = yawed roblox frame
    Studio import (yaw 180)   ->  (-vy, vz, -vx) = roblox frame, nose at -Z
"""
from __future__ import annotations

STUD_CM = 28.0  # 1 stud = 0.28 m

FRAME_NAME = "roblox-model"
FRAME_DESCRIPTION = (
    "studs (1 stud = 0.28 m); Roblox model frame: +X right, +Y up, +Z back (nose = -Z); "
    "origin = ground under the centre of the car"
)


def cm_to_studs(value: float) -> float:
    return value / STUD_CM


def point_to_roblox(point):
    """Vehicle space -> Roblox model frame (any unit)."""
    vx, vy, vz = point
    return (-vy, vz, -vx)


def size_to_roblox(size):
    """Vehicle-space bounding-box size (sx forward, sy lateral, sz up) -> Roblox (width, height, length)."""
    sx, sy, sz = size
    return (sy, sz, sx)


def point_to_blender_export(point):
    """Vehicle space -> Blender scene coordinates that the FBX exporter turns into the Roblox frame."""
    vx, vy, vz = point
    return (vy, -vx, vz)


def point_to_file(point):
    """Roblox model frame -> the frame stored in the FBX (Studio's importer yaws it 180 degrees back)."""
    rx, ry, rz = point
    return (-rx, ry, -rz)


def point_from_roblox(point):
    """Roblox model frame -> vehicle space (inverse of point_to_roblox)."""
    rx, ry, rz = point
    return (-rz, -rx, ry)


def wheel_side(name: str) -> int:
    """-1 for left wheels (FL, RL), +1 for right wheels (FR, RR), in the Roblox frame (right = +X)."""
    return -1 if name.endswith("L") else 1
