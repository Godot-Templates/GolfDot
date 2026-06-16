class_name GolfTransformUtil
extends RefCounted
## Faithful ports of Open-Golf's transform + movement math (src/common/level.c):
##   golf_transform_get_model_mat, golf_transform_apply_movement,
##   golf_entity_get_world_transform.
## A "transform" here is a Dictionary {position: Vector3, scale: Vector3, rotation: Quaternion}.

# --- Movement type tags (mirror golf_movement_type_t) ---
enum Movement { NONE, LINEAR, SPINNER, PENDULUM, RAMP }

## Build a Transform3D from a transform dict (T * R * S), matching
## golf_transform_get_model_mat.
static func to_transform3d(t: Dictionary) -> Transform3D:
	var basis := Basis(t["rotation"] as Quaternion).scaled(t["scale"] as Vector3)
	return Transform3D(basis, t["position"] as Vector3)

## Port of golf_transform_apply_movement: returns a new transform dict with the
## movement applied at time t. `m` is a movement dict (see GolfLevelData).
static func apply_movement(t: Dictionary, m: Dictionary, time: float) -> Dictionary:
	var type: int = m.get("type", Movement.NONE)
	if type == Movement.NONE:
		return t
	var l: float = m["length"]
	var tt: float = fmod(m["t0"] + time, l)
	var out := t.duplicate()
	match type:
		Movement.LINEAR:
			var p0: Vector3 = m["p0"]
			var p1: Vector3 = m["p1"]
			var p: Vector3 = t["position"]
			if tt < 0.5 * l:
				p += p0.lerp(p1, tt / (0.5 * l))
			else:
				p += p0.lerp(p1, (l - tt) / (0.5 * l))
			out["position"] = p
		Movement.SPINNER:
			var a: float = 2.0 * PI * (tt / l)
			var r := Quaternion(Vector3(0, 1, 0), a)
			out["rotation"] = r * (t["rotation"] as Quaternion)
		Movement.PENDULUM:
			var a: float = 2.0 * (tt / l)
			if a >= 1.0:
				a = 2.0 - a
			var theta: float = m["theta0"] * cos(PI * a)
			var r := Quaternion((m["axis"] as Vector3).normalized(), theta)
			out["rotation"] = r * (t["rotation"] as Quaternion)
		Movement.RAMP:
			var theta0: float = 2.0 * PI * (m["theta0"] / 360.0)
			var theta1: float = 2.0 * PI * (m["theta1"] / 360.0)
			var transition_length: float = m["transition_length"]
			var axis: Vector3 = m["axis"]
			var theta := 0.0
			var s1 := transition_length
			var s2 := 0.5 * l - transition_length
			var s3 := 0.5 * l + transition_length
			var s4 := l - transition_length
			if tt < s1:
				theta = theta0
			elif tt < s2:
				theta = theta0 + ((tt - s1) / (s2 - s1)) * (theta1 - theta0)
			elif tt < s3:
				theta = theta1
			elif tt < s4:
				theta = theta1 + ((tt - s3) / (s4 - s3)) * (theta0 - theta1)
			else:
				theta = theta0
			var r := Quaternion(axis.normalized(), theta)
			out["rotation"] = r * (t["rotation"] as Quaternion)
	return out

## Port of golf_entity_get_world_transform: compose one level of parenting.
## parent_transform is a transform dict, or the identity if no parent.
static func world_transform(local: Dictionary, parent: Dictionary) -> Dictionary:
	var p_rot: Quaternion = parent["rotation"]
	var p_scale: Vector3 = parent["scale"]
	var p_pos: Vector3 = parent["position"]

	var rotation: Quaternion = p_rot * (local["rotation"] as Quaternion)
	var l_scale: Vector3 = local["scale"]
	var scale := Vector3(p_scale.x * l_scale.x, p_scale.y * l_scale.y, p_scale.z * l_scale.z)

	var position: Vector3 = Basis(p_rot) * (local["position"] as Vector3)
	position = Vector3(position.x * p_scale.x, position.y * p_scale.y, position.z * p_scale.z)
	position += p_pos
	return {"position": position, "scale": scale, "rotation": rotation}

static func identity_transform() -> Dictionary:
	return {"position": Vector3.ZERO, "scale": Vector3.ONE, "rotation": Quaternion.IDENTITY}
