class_name GolfCollisionWorld
extends RefCounted
## Holds the static collision triangles of a level and answers ball/ray queries.
## This replaces Open-Golf's BVH with a simple AABB broadphase, which is
## equivalent in behaviour for hand-authored maps (just less scalable).

const EPS := 0.001

# Parallel arrays, one entry per triangle.
var _a: PackedVector3Array = PackedVector3Array()
var _b: PackedVector3Array = PackedVector3Array()
var _c: PackedVector3Array = PackedVector3Array()
var _aabb_min: PackedVector3Array = PackedVector3Array()
var _aabb_max: PackedVector3Array = PackedVector3Array()
var _materials: Array[GolfMaterial] = []

## Rebuild from every GolfSurface found under root (or in the "golf_surface" group).
func build_from_scene(root: Node) -> void:
	_clear()
	var surfaces: Array[Node] = []
	_collect_surfaces(root, surfaces)
	for node in surfaces:
		var surface := node as GolfSurface
		var tris: PackedVector3Array = surface.get_world_triangles()
		var mat: GolfMaterial = surface.get_material()
		for i in range(0, tris.size() - 2, 3):
			_add_triangle(tris[i], tris[i + 1], tris[i + 2], mat)

func triangle_count() -> int:
	return _a.size()

func _clear() -> void:
	_a = PackedVector3Array()
	_b = PackedVector3Array()
	_c = PackedVector3Array()
	_aabb_min = PackedVector3Array()
	_aabb_max = PackedVector3Array()
	_materials = []

func _collect_surfaces(node: Node, out: Array[Node]) -> void:
	if node is GolfSurface:
		out.append(node)
	for child in node.get_children():
		_collect_surfaces(child, out)

func _add_triangle(a: Vector3, b: Vector3, c: Vector3, mat: GolfMaterial) -> void:
	_a.append(a)
	_b.append(b)
	_c.append(c)
	_aabb_min.append(Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z))))
	_aabb_max.append(Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z))))
	_materials.append(mat)

## Append ball-vs-triangle contacts to `contacts`. Port of golf_bvh_ball_test
## for static geometry (surface velocity is zero).
func ball_test(bp: Vector3, br: float, contacts: Array) -> void:
	var lo := bp - Vector3(br, br, br)
	var hi := bp + Vector3(br, br, br)
	var out_type: Array = [GolfMath.ContactType.FACE]
	for i in _a.size():
		# Broadphase: skip triangles whose AABB can't be within br of the ball.
		if _aabb_max[i].x < lo.x or _aabb_min[i].x > hi.x: continue
		if _aabb_max[i].y < lo.y or _aabb_min[i].y > hi.y: continue
		if _aabb_max[i].z < lo.z or _aabb_min[i].z > hi.z: continue

		var a := _a[i]
		var b := _b[i]
		var c := _c[i]
		var cp := GolfMath.closest_point_on_triangle(bp, a, b, c, out_type)
		var dist := bp.distance_to(cp)
		if dist < br:
			var mat: GolfMaterial = _materials[i]
			var contact := GolfContact.make(a, b, c, Vector3.ZERO, bp, br, cp, dist,
				mat.restitution, mat.friction, mat.vel_scale, out_type[0],
				mat.is_water, mat.water_dir, mat.is_out_of_bounds)
			contacts.append(contact)

## Raycast against all triangles. Returns nearest hit distance along dir, or -1.
## Fills out_normal (single-element array) with the hit triangle's normal.
func ray_test(origin: Vector3, dir: Vector3, out_normal: Array) -> float:
	var best_t := -1.0
	for i in _a.size():
		var t := _ray_triangle(origin, dir, _a[i], _b[i], _c[i])
		if t > 0.0 and (best_t < 0.0 or t < best_t):
			best_t = t
			out_normal[0] = (_b[i] - _a[i]).cross(_c[i] - _a[i]).normalized()
	return best_t

func _ray_triangle(ro: Vector3, rd: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	# Moller-Trumbore.
	var e1 := b - a
	var e2 := c - a
	var p := rd.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 0.0000001:
		return -1.0
	var inv := 1.0 / det
	var tvec := ro - a
	var u := tvec.dot(p) * inv
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := tvec.cross(e1)
	var v := rd.dot(q) * inv
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := e2.dot(q) * inv
	if t < 0.0:
		return -1.0
	return t
