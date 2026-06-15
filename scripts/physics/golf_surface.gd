@tool
class_name GolfSurface
extends MeshInstance3D
## A piece of golf course collision geometry. Attach a GolfMaterial to control
## how the ball bounces/rolls/sinks on it. The GolfCollisionWorld bakes this
## mesh's triangles (in world space) into the physics solver.

@export var golf_material: GolfMaterial

func _ready() -> void:
	add_to_group("golf_surface")

## Returns this surface's triangles in WORLD space as a flat PackedVector3Array
## (3 verts per triangle), or empty if there is no mesh.
func get_world_triangles() -> PackedVector3Array:
	if mesh == null:
		return PackedVector3Array()
	var local: PackedVector3Array = mesh.get_faces()
	var xform: Transform3D = global_transform
	var out := PackedVector3Array()
	out.resize(local.size())
	for i in local.size():
		out[i] = xform * local[i]
	return out

func get_material() -> GolfMaterial:
	if golf_material != null:
		return golf_material
	return GolfMaterial.new()
