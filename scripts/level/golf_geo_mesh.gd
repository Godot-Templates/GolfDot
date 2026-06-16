class_name GolfGeoMesh
extends RefCounted
## Ports _golf_geo_generate_model_data (src/common/level.c): turns a parsed geo
## (points + faces) into per-material triangle data with generated texture UVs
## and lightmap UV2s. Faces are grouped by material, fan-triangulated, and UVs
## are generated per the face's uv_gen_type.
##
## build_surfaces() returns an Array of dicts, one per material group:
##   { material_name, positions:PackedVector3Array, normals:PackedVector3Array,
##     uvs:PackedVector2Array, uv2s:PackedVector2Array, water_dirs:PackedVector3Array }
## Triangle vertices are emitted in the SAME order Open-Golf bakes them, so the
## flat lightmap_section UV array lines up index-for-index with uv2s.

# uv_gen_type strings -> behaviour
const UV_MANUAL := "manual"
const UV_GROUND := "ground"
const UV_WALL_SIDE := "wall-side"
const UV_WALL_TOP := "wall-top"

## Build per-material triangle groups. `lightmap_uvs` is the flat per-model-vertex
## UV2 array from the entity's lightmap_section (may be empty).
static func build_groups(geo: Dictionary, lightmap_uvs: PackedVector2Array) -> Array:
	var points: PackedVector3Array = geo["points"]
	var faces: Array = geo["faces"]

	# Group faces by material. The baked lightmap UV array is laid out in the
	# SAME order Open-Golf's hashmap (src/common/map.c) iterates its material
	# keys, so we must replicate that iteration order (NOT first-seen) for UV2 to
	# line up per-vertex. Insertion order into the map == first-seen face order.
	var first_seen: Array[String] = []
	var by_material: Dictionary = {}
	for face in faces:
		var mat: String = face["material_name"]
		if not by_material.has(mat):
			by_material[mat] = []
			first_seen.append(mat)
		(by_material[mat] as Array).append(face)
	var order: Array = _map_iteration_order(first_seen)

	var groups: Array = []
	var vertex_cursor := 0
	for mat in order:
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var water_dirs := PackedVector3Array()
		for face in by_material[mat]:
			_emit_face(face, points, positions, normals, uvs, water_dirs)
		# Pull the matching slice of lightmap UV2s for this group.
		var count := positions.size()
		for i in count:
			var gi := vertex_cursor + i
			if gi < lightmap_uvs.size():
				uv2s.append(lightmap_uvs[gi])
			else:
				uv2s.append(Vector2.ZERO)
		vertex_cursor += count
		groups.append({
			"material_name": mat,
			"positions": positions,
			"normals": normals,
			"uvs": uvs,
			"uv2s": uv2s,
			"water_dirs": water_dirs,
		})
	return groups

static func _emit_face(face: Dictionary, points: PackedVector3Array,
		positions: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, water_dirs: PackedVector3Array) -> void:
	var idxs: PackedInt32Array = face["idxs"]
	var face_uvs: PackedVector2Array = face["uvs"]
	var uv_gen: String = face["uv_gen_type"]
	var water_dir: Vector3 = face["water_dir"]
	if idxs.size() < 3:
		return
	var idx0 := idxs[0]
	# Fan triangulation: (0, i, i+1).
	for i in range(1, idxs.size() - 1):
		var idx1 := idxs[i]
		var idx2 := idxs[i + 1]
		var p0 := points[idx0]
		var p1 := points[idx1]
		var p2 := points[idx2]
		var tc0 := _uv_at(face_uvs, 0)
		var tc1 := _uv_at(face_uvs, i)
		var tc2 := _uv_at(face_uvs, i + 1)
		match uv_gen:
			UV_GROUND:
				tc0 = Vector2(0.5 * p0.x, 0.5 * p0.z)
				tc1 = Vector2(0.5 * p1.x, 0.5 * p1.z)
				tc2 = Vector2(0.5 * p2.x, 0.5 * p2.z)
			UV_WALL_SIDE, UV_WALL_TOP:
				var dirs := _guess_wall_dir(p0, p1, p2)
				var long_dir: Vector3 = dirs[0]
				var short_dir: Vector3 = dirs[1]
				tc0 = Vector2(p0.dot(short_dir), 0.5 * p0.dot(long_dir))
				tc1 = Vector2(p1.dot(short_dir), 0.5 * p1.dot(long_dir))
				tc2 = Vector2(p2.dot(short_dir), 0.5 * p2.dot(long_dir))
			_:
				pass  # manual: use stored uvs
		var n := (p1 - p0).cross(p2 - p0).normalized()
		positions.append(p0)
		positions.append(p1)
		positions.append(p2)
		normals.append(n)
		normals.append(n)
		normals.append(n)
		uvs.append(tc0)
		uvs.append(tc1)
		uvs.append(tc2)
		water_dirs.append(water_dir)

static func _uv_at(arr: PackedVector2Array, i: int) -> Vector2:
	return arr[i] if i < arr.size() else Vector2.ZERO

# --- Replicate Open-Golf's hashmap (src/common/map.c) iteration order ---------

## djb2 hash exactly as map.c's map_hash, masked to 32 bits.
static func _map_hash(s: String) -> int:
	var h := 5381
	for c in s.to_ascii_buffer():
		h = (((h << 5) + h) ^ c) & 0xFFFFFFFF
	return h

## Given material names in insertion (first-seen) order, return the order the
## rxi map_t iterates them (bucket 0..n, head-first chains), faithfully
## simulating power-of-2 bucket growth + rehash.
static func _map_iteration_order(insertion: Array) -> Array:
	var hashes := {}
	for name in insertion:
		hashes[name] = _map_hash(name)
	var nbuckets := 0
	var nnodes := 0
	var buckets: Array = []  # each bucket: Array of names, head-first (index 0 = head)

	for name in insertion:
		if nnodes >= nbuckets:
			var n := (nbuckets << 1) if nbuckets > 0 else 1
			buckets = _map_resize(buckets, nbuckets, n, hashes)
			nbuckets = n
		var b: int = hashes[name] & (nbuckets - 1)
		buckets[b].push_front(name)
		nnodes += 1

	var order: Array = []
	for i in nbuckets:
		for name in buckets[i]:
			order.append(name)
	return order

## Port of map_resize: collect all nodes (buckets high->low, chain head->tail,
## prepending) then re-add (head->tail, prepend into new buckets).
static func _map_resize(buckets: Array, old_n: int, new_n: int, hashes: Dictionary) -> Array:
	var nodes: Array = []
	for i in range(old_n - 1, -1, -1):
		for name in buckets[i]:  # head -> tail
			nodes.push_front(name)
	var new_buckets: Array = []
	new_buckets.resize(new_n)
	for i in new_n:
		new_buckets[i] = []
	for name in nodes:  # head -> tail
		var b: int = hashes[name] & (new_n - 1)
		new_buckets[b].push_front(name)
	return new_buckets

## Faithful port of _golf_geo_face_guess_wall_dir: choose the most-perpendicular
## pair of edges, take the longer as long_dir and shorter as short_dir, then
## flip both to a consistent hemisphere. Returns [long_dir, short_dir].
static func _guess_wall_dir(p0: Vector3, p1: Vector3, p2: Vector3) -> Array:
	var dir0 := p1 - p0
	var dir0_l := dir0.length()
	dir0 = dir0 / dir0_l
	var dir1 := p2 - p0
	var dir1_l := dir1.length()
	dir1 = dir1 / dir1_l
	var dir2 := p2 - p1
	var dir2_l := dir2.length()
	dir2 = dir2 / dir2_l

	var dot0 := absf(dir0.dot(dir1))
	var dot1 := absf(dir0.dot(dir2))
	var dot2 := absf(dir1.dot(dir2))

	var long_dir: Vector3
	var short_dir: Vector3
	if dot0 <= dot1 and dot0 <= dot2:
		if dir0_l <= dir1_l:
			long_dir = dir1; short_dir = dir0
		else:
			long_dir = dir0; short_dir = dir1
	elif dot1 <= dot0 and dot1 <= dot2:
		if dir0_l <= dir2_l:
			long_dir = dir2; short_dir = dir0
		else:
			long_dir = dir0; short_dir = dir2
	else:
		if dir1_l <= dir2_l:
			long_dir = dir2; short_dir = dir1
		else:
			long_dir = dir1; short_dir = dir2

	var d := Vector3(1, 2, 3).normalized()
	if long_dir.dot(d) < 0.0:
		long_dir = -long_dir
	if short_dir.dot(d) < 0.0:
		short_dir = -short_dir
	return [long_dir, short_dir]

## Convenience: build a single ArrayMesh surface from a group dict, with optional
## UV2 inclusion. Returns the ArrayMesh.
static func group_to_mesh(group: Dictionary, include_uv2: bool) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = group["positions"]
	arrays[Mesh.ARRAY_NORMAL] = group["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = group["uvs"]
	if include_uv2 and (group["uv2s"] as PackedVector2Array).size() == (group["positions"] as PackedVector3Array).size():
		arrays[Mesh.ARRAY_TEX_UV2] = group["uv2s"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
