class_name GolfAim
extends RefCounted
## Port of Open-Golf's aiming math: drag -> aim_delta + power (ui.c:537-602),
## power -> launch speed (game.c:998-1021), and the reflective aim-line preview
## (game.c:184-239).

# Ported from data/config/game.cfg
const REFERENCE_WIDTH := 720.0
const AIM_MIN_LENGTH := 100.0
const AIM_MAX_LENGTH := 420.0

const AIM_GREEN_POWER := 0.4
const AIM_YELLOW_POWER := 0.65
const AIM_RED_POWER := 0.9
const AIM_GREEN_SPEED := 2.0
const AIM_YELLOW_SPEED := 8.0
const AIM_RED_SPEED := 16.0
const AIM_DARK_RED_SPEED := 20.0

const AIM_LINE_MIN_LENGTH := 1.0
const AIM_LINE_MAX_LENGTH := 4.0
const MAX_AIM_LINE_POINTS := 5

const AIM_ROTATE_MIN_ANGLE := 0.3
const AIM_ROTATE_MAX_ANGLE := 1.5
const AIM_ROTATE_SPEED := 1.3

const COLOR_GREEN := Color(0.2, 0.9, 0.3)
const COLOR_YELLOW := Color(0.7, 0.8, 0.2)
const COLOR_RED := Color(0.8, 0.6, 0.1)
const COLOR_DARK_RED := Color(0.9, 0.2, 0.1)

# State (mirrors game.aim_line)
var power: float = 0.0
var aim_delta: Vector2 = Vector2.ZERO   # screen-space, y-down
var aimer_angle: float = 0.0

## Update aim_delta / power / aimer_angle from the current drag.
## ball_screen and mouse are screen-space (y-down); viewport_height in pixels.
func update_from_drag(ball_screen: Vector2, mouse: Vector2, viewport_height: float) -> void:
	var to_mouse := mouse - ball_screen
	var aimer_length := to_mouse.length()
	var delta := to_mouse.normalized() if aimer_length > 0.0001 else Vector2(0, 1)

	var vert_scale := 1.777 * (REFERENCE_WIDTH / viewport_height)
	aimer_length *= vert_scale
	if aimer_length > AIM_MAX_LENGTH:
		aimer_length = AIM_MAX_LENGTH

	power = (aimer_length - AIM_MIN_LENGTH) / (AIM_MAX_LENGTH - AIM_MIN_LENGTH)
	aim_delta = delta

	# Angle measured from straight-down (screen +Y), used for camera rotation.
	aimer_angle = acos(clampf(delta.dot(Vector2(0, 1)), -1.0, 1.0))
	if delta.x > 0:
		aimer_angle *= -1.0

func reset() -> void:
	power = 0.0
	aim_delta = Vector2.ZERO
	aimer_angle = 0.0

## Rotate the camera while aiming (ui.c:586-601). Mutates camera.angle.
func apply_camera_rotation(camera: GolfCamera, dt: float) -> void:
	if power <= 0.0:
		return
	if aimer_angle > AIM_ROTATE_MIN_ANGLE:
		var a := 1.0 - (AIM_ROTATE_MAX_ANGLE - aimer_angle) / (AIM_ROTATE_MAX_ANGLE - AIM_ROTATE_MIN_ANGLE)
		a = minf(a, 1.0)
		camera.auto_rotate = false
		camera.angle -= AIM_ROTATE_SPEED * a * dt
	if aimer_angle < -AIM_ROTATE_MIN_ANGLE:
		var a := 1.0 + (-AIM_ROTATE_MAX_ANGLE - aimer_angle) / (AIM_ROTATE_MAX_ANGLE - AIM_ROTATE_MIN_ANGLE)
		a = minf(a, 1.0)
		camera.auto_rotate = false
		camera.angle += AIM_ROTATE_SPEED * a * dt

## World-space launch direction (game.c:181-182 / 995-996).
func get_aim_direction(cam_angle: float) -> Vector3:
	var d := Vector3(aim_delta.x, 0, aim_delta.y)
	return d.rotated(Vector3.UP, cam_angle - 0.5 * PI).normalized()

## Power -> launch speed (game.c:998-1021).
func get_launch_speed() -> float:
	var p := power
	if p < AIM_GREEN_POWER:
		var a := p / AIM_GREEN_POWER
		return AIM_GREEN_SPEED + (AIM_YELLOW_SPEED - AIM_GREEN_SPEED) * a
	elif p < AIM_YELLOW_POWER:
		var a := (p - AIM_GREEN_POWER) / (AIM_YELLOW_POWER - AIM_GREEN_POWER)
		return AIM_YELLOW_SPEED + (AIM_RED_SPEED - AIM_YELLOW_SPEED) * a
	elif p < AIM_RED_POWER:
		var a := (p - AIM_YELLOW_POWER) / (AIM_RED_POWER - AIM_YELLOW_POWER)
		return AIM_RED_SPEED + (AIM_DARK_RED_SPEED - AIM_RED_SPEED) * a
	return AIM_DARK_RED_SPEED

func get_power_color() -> Color:
	if power < AIM_GREEN_POWER:
		return COLOR_GREEN
	elif power < AIM_YELLOW_POWER:
		return COLOR_YELLOW
	elif power < AIM_RED_POWER:
		return COLOR_RED
	return COLOR_DARK_RED

## Reflective aim-line preview points (game.c:184-239).
func compute_aim_line(ball_pos: Vector3, cam_angle: float, world: GolfCollisionWorld) -> PackedVector3Array:
	var points := PackedVector3Array()
	var cur_point := ball_pos
	var cur_dir := get_aim_direction(cam_angle)
	var max_length := AIM_LINE_MIN_LENGTH + power * (AIM_LINE_MAX_LENGTH - AIM_LINE_MIN_LENGTH)
	var t := 0.0
	var out_normal: Array = [Vector3.UP]
	while true:
		if points.size() == MAX_AIM_LINE_POINTS:
			break
		points.append(cur_point)
		if t >= max_length:
			break
		var hit_t := world.ray_test(cur_point, cur_dir, out_normal)
		if hit_t > 0.0:
			if t + hit_t > max_length:
				hit_t = max_length - t
				t = max_length
			var normal: Vector3 = out_normal[0]
			cur_point = cur_point + cur_dir * hit_t
			cur_point = cur_point + cur_dir * -0.095
			cur_dir = GolfMath.reflect_with_restitution(cur_dir, normal, 1.0)
			t += hit_t
		else:
			cur_point = cur_point + cur_dir * (max_length - t)
			t = max_length
	return points
