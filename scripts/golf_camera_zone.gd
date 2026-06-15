@tool
class_name GolfCameraZone
extends Node3D
## A volume that steers the auto-rotating camera. When the ball is inside, the
## camera turns to either face the hole (towards_hole) or along the zone's local
## +X axis. Mirrors golf_camera_zone_entity_t.
##
## The zone is an axis-after-rotation box of half-extents = scale (the box spans
## position +/- scale along each local axis), matching Open-Golf's transform.scale
## semantics for camera zones.

@export var towards_hole: bool = true
## Half-extents of the zone box in local space (before the node's own scale).
@export var half_extents: Vector3 = Vector3(3.0, 2.0, 3.0)

func _ready() -> void:
	add_to_group("golf_camera_zone")

## True if a world-space point lies within this zone's box.
func contains_point(world_point: Vector3) -> bool:
	var local: Vector3 = global_transform.affine_inverse() * world_point
	return absf(local.x) <= half_extents.x \
		and absf(local.y) <= half_extents.y \
		and absf(local.z) <= half_extents.z
