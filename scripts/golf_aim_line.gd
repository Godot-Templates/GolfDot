class_name GolfAimLine
extends MeshInstance3D
## Renders the reflective aim-line preview as a 3D polyline. Points are computed
## by GolfAim (port of _golf_game_update_state_aiming, game.c:184-239).

var _imesh: ImmediateMesh
var _mat: StandardMaterial3D

func _ready() -> void:
	_imesh = ImmediateMesh.new()
	mesh = _imesh
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color(1, 1, 1)
	_mat.disable_receive_shadows = true
	_mat.no_depth_test = true
	material_override = _mat

func set_points(points: PackedVector3Array, color: Color) -> void:
	_imesh.clear_surfaces()
	if points.size() < 2:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_mat.albedo_color = color
	for p in points:
		_imesh.surface_add_vertex(p + Vector3(0, 0.05, 0))
	_imesh.surface_end()

func clear() -> void:
	if _imesh:
		_imesh.clear_surfaces()
