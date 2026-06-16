class_name GolfLevelData
extends RefCounted
## Parses an Open-Golf ".level" JSON file into typed Godot data structures.
## Mirrors the loader in src/common/data.c (_golf_data_load_level). Internal
## "data/..." asset paths are remapped to "res://assets/...".
##
## After load(), use:
##   materials      : Dictionary name -> material dict {friction,restitution,vel_scale,type,texture_path,color}
##   lightmaps      : Dictionary name -> {resolution,width,height,time_length,repeats,num_samples,images:Array[Image]}
##   entities       : Array of entity dicts (see _parse_entity)

const ASSET_PREFIX := "res://assets/"
## Open-Golf stores "float arrays" as int32 scaled by this (json.c PRECISION).
const FLOAT_ARRAY_PRECISION := 100000.0

var source_path: String = ""
var materials: Dictionary = {}
var lightmaps: Dictionary = {}
var entities: Array = []

## Load and parse a .level file. Returns null on failure.
static func load_from(res_path: String) -> GolfLevelData:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		push_error("GolfLevelData: cannot open %s" % res_path)
		return null
	var json_text := f.get_as_text()
	f.close()
	var root: Variant = JSON.parse_string(json_text)
	if typeof(root) != TYPE_DICTIONARY:
		push_error("GolfLevelData: invalid JSON in %s" % res_path)
		return null

	var data := GolfLevelData.new()
	data.source_path = res_path
	data._parse(root as Dictionary)
	return data

func _parse(root: Dictionary) -> void:
	for m in root.get("materials", []):
		_parse_material(m)
	for li in root.get("lightmap_images", []):
		_parse_lightmap(li)
	for e in root.get("entities", []):
		entities.append(_parse_entity(e))

## Remap an internal "data/..." path to "res://assets/...".
static func remap_path(p: String) -> String:
	if p.begins_with("data/"):
		return ASSET_PREFIX + p.substr(5)
	return p

func _parse_material(m: Dictionary) -> void:
	var entry := {
		"name": m.get("name", "default"),
		"friction": float(m.get("friction", 0.3)),
		"restitution": float(m.get("restitution", 0.4)),
		"vel_scale": float(m.get("vel_scale", 1.0)),
		"type": m.get("type", "environment"),
		"texture_path": "",
		"color": Color(1, 1, 1, 1),
	}
	if m.has("texture"):
		entry["texture_path"] = remap_path(m["texture"])
	if m.has("color"):
		var c: Array = m["color"]
		entry["color"] = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
	materials[entry["name"]] = entry

func _parse_lightmap(li: Dictionary) -> void:
	var images: Array[Image] = []
	var width := 0
	var height := 0
	for b64 in li.get("datas", []):
		var bytes := Marshalls.base64_to_raw(b64)
		var img := Image.new()
		if img.load_png_from_buffer(bytes) == OK:
			width = img.get_width()
			height = img.get_height()
			images.append(img)
	lightmaps[li.get("name", "main")] = {
		"resolution": int(li.get("resolution", 0)),
		"width": width,
		"height": height,
		"time_length": float(li.get("time_length", 0.0)),
		"repeats": bool(li.get("repeats", false)),
		"num_samples": images.size(),
		"images": images,
	}

func _parse_entity(e: Dictionary) -> Dictionary:
	var ent := {
		"name": e.get("name", ""),
		"type": e.get("type", ""),
		"parent_idx": int(e.get("parent_idx", -1)),
		"transform": _parse_transform(e.get("transform", {})),
	}
	if e.has("movement"):
		ent["movement"] = _parse_movement(e["movement"])
	else:
		ent["movement"] = {"type": GolfTransformUtil.Movement.NONE}
	if e.has("lightmap_section"):
		ent["lightmap_section"] = _parse_lightmap_section(e["lightmap_section"])

	match ent["type"]:
		"model":
			ent["model_path"] = remap_path(e.get("model", ""))
			ent["uv_scale"] = float(e.get("uv_scale", 1.0))
			ent["ignore_physics"] = bool(e.get("ignore_physics", false))
		"camera_zone":
			ent["towards_hole"] = bool(e.get("towards_hole", false))
		"geo", "water":
			ent["geo"] = _parse_geo(e.get("geo", {}))
			ent["is_water"] = ent["type"] == "water"
	return ent

func _parse_transform(t: Dictionary) -> Dictionary:
	var pos: Array = t.get("position", [0, 0, 0])
	var scl: Array = t.get("scale", [1, 1, 1])
	var rot: Array = t.get("rotation", [0, 0, 0, 1])
	return {
		"position": Vector3(pos[0], pos[1], pos[2]),
		"scale": Vector3(scl[0], scl[1], scl[2]),
		"rotation": Quaternion(rot[0], rot[1], rot[2], rot[3]),
	}

func _parse_movement(m: Dictionary) -> Dictionary:
	var type_str: String = m.get("type", "none")
	var out := {"t0": float(m.get("t0", 0.0)), "length": float(m.get("length", 1.0))}
	match type_str:
		"linear":
			out["type"] = GolfTransformUtil.Movement.LINEAR
			out["p0"] = _v3(m.get("p0", [0, 0, 0]))
			out["p1"] = _v3(m.get("p1", [0, 0, 0]))
		"spinner":
			out["type"] = GolfTransformUtil.Movement.SPINNER
		"pendulum":
			out["type"] = GolfTransformUtil.Movement.PENDULUM
			out["theta0"] = float(m.get("theta0", 0.0))
			out["axis"] = _v3(m.get("axis", [0, 1, 0]))
		"ramp":
			out["type"] = GolfTransformUtil.Movement.RAMP
			out["theta0"] = float(m.get("theta0", 0.0))
			out["theta1"] = float(m.get("theta1", 0.0))
			out["transition_length"] = float(m.get("transition_length", 0.0))
			out["axis"] = _v3(m.get("axis", [0, 1, 0]))
		_:
			out["type"] = GolfTransformUtil.Movement.NONE
	return out

func _parse_lightmap_section(s: Dictionary) -> Dictionary:
	# Open-Golf encodes float arrays as int32 / PRECISION (golf_json's
	# get/set_float_array), saved with min=0,max=1 -> value = int32 / 100000.
	var uvs := PackedVector2Array()
	var b64: String = s.get("uvs", "")
	if not b64.is_empty():
		var ints := Marshalls.base64_to_raw(b64).to_int32_array()
		@warning_ignore("integer_division")
		uvs.resize(ints.size() / 2)
		for i in uvs.size():
			uvs[i] = Vector2(ints[i * 2] / FLOAT_ARRAY_PRECISION, ints[i * 2 + 1] / FLOAT_ARRAY_PRECISION)
	return {"lightmap_name": s.get("lightmap_name", "main"), "uvs": uvs}

func _parse_geo(g: Dictionary) -> Dictionary:
	# Points: flat [x,y,z,...] -> PackedVector3Array.
	var flat: Array = g.get("p", [])
	var points := PackedVector3Array()
	@warning_ignore("integer_division")
	points.resize(flat.size() / 3)
	for i in points.size():
		points[i] = Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])

	var faces: Array = []
	for fc in g.get("faces", []):
		var idxs: Array = fc.get("idxs", [])
		var raw_uvs: Array = fc.get("uvs", [])
		var uvs := PackedVector2Array()
		@warning_ignore("integer_division")
		uvs.resize(raw_uvs.size() / 2)
		for i in uvs.size():
			uvs[i] = Vector2(raw_uvs[i * 2], raw_uvs[i * 2 + 1])
		faces.append({
			"material_name": fc.get("material_name", "default"),
			"idxs": PackedInt32Array(idxs),
			"uv_gen_type": fc.get("uv_gen_type", "manual"),
			"uvs": uvs,
			"water_dir": _v3(fc.get("water_dir", [0, 0, 0])),
		})
	return {"points": points, "faces": faces}

static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
