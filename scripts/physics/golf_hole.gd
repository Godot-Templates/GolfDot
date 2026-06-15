@tool
class_name GolfHole
extends Node3D
## Marks a hole (cup). The solver pulls the ball toward it when near, uses the
## optional cup mesh for the "catch" collision, and detects when the ball sinks.
## `radius` corresponds to the hole entity's transform.scale.x in Open-Golf.

@export var radius: float = 0.4
## Optional cup collision mesh (e.g. hole.obj). When the ball is within `radius`
## the solver collides only against these triangles, matching Open-Golf's
## close_hole special case.
@export var cup_mesh: MeshInstance3D

func get_hole_position() -> Vector3:
	return global_transform.origin

## Cup triangles in world space (flat, 3 verts per tri), or empty.
func get_cup_triangles() -> PackedVector3Array:
	if cup_mesh == null or cup_mesh.mesh == null:
		return PackedVector3Array()
	var local: PackedVector3Array = cup_mesh.mesh.get_faces()
	var xform: Transform3D = cup_mesh.global_transform
	var out := PackedVector3Array()
	out.resize(local.size())
	for i in local.size():
		out[i] = xform * local[i]
	return out
