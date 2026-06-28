class_name GolfCamera
extends Camera3D
## Faithful port of Open-Golf's camera rig (game.c). The camera orbits the ball
## at a fixed offset, smoothly follows, auto-rotates toward camera zones, and
## plays the begin-level fly-in and hole celebration animations.

# Ported from data/config/game.cfg
const CAM_AUTO_ROTATE_SPEED := 0.03
const BEGIN_LENGTH0 := 1.0
const BEGIN_LENGTH1 := 2.0
const CELEBRATION_LENGTH := 1.0

# The orbit offset rotated by `angle` each frame (game.c:830).
const CAM_OFFSET := Vector3(2.6, 1.5, 0)
const LOOK_AT_OFFSET := Vector3(0, 0.3, 0)

# Orbit distance + pitch derived from CAM_OFFSET, so the default view matches the
# original rig. `pitch` is the camera's elevation angle above the ball (radians),
# adjustable via the pan controls and clamped to keep the ball in frame.
const CAM_DISTANCE := 3.0017  # CAM_OFFSET.length()
const PITCH_MIN := 0.12
const PITCH_MAX := 1.35

var angle: float = 0.0
var pitch: float = 0.5236  # atan2(1.5, 2.6) — matches CAM_OFFSET's elevation
var auto_rotate: bool = true

## The orbit offset for the current angle + pitch (replaces the fixed CAM_OFFSET).
func get_orbit_offset() -> Vector3:
    var horiz := cos(pitch) * CAM_DISTANCE
    var vert := sin(pitch) * CAM_DISTANCE
    return Vector3(horiz, vert, 0).rotated(Vector3.UP, angle)

# Internal world-space position/direction (mirrors graphics->cam_pos/cam_dir).
var _cam_pos: Vector3 = Vector3.ZERO
var _cam_dir: Vector3 = Vector3.FORWARD

# Begin animation state.
var _begin_t: float = 0.0
var _begin_pos0: Vector3
var _begin_dir0: Vector3
var _begin_pos1: Vector3
var _begin_dir1: Vector3

# Celebration state.
var _celebration_t: float = 0.0
var _celeb_pos0: Vector3
var _celeb_dir0: Vector3
var _celeb_pos1: Vector3
var _celeb_dir1: Vector3

## Camera zones present in the level (GolfCameraZone nodes).
var camera_zones: Array[GolfCameraZone] = []

func _apply() -> void:
    # Push internal pos/dir to the actual Camera3D transform.
    global_position = _cam_pos
    if _cam_dir.length() > 0.0001:
        look_at(_cam_pos + _cam_dir, Vector3.UP)

# --- Follow camera (waiting / aiming / watching) ----------------------------

func update_follow(ball_draw_pos: Vector3, hole_pos: Vector3, _dt: float) -> void:
    if auto_rotate:
        var zone_angle := get_camera_zone_angle(ball_draw_pos, hole_pos)
        var delta_angle := zone_angle - angle
        delta_angle = atan2(sin(delta_angle), cos(delta_angle))
        angle += delta_angle * CAM_AUTO_ROTATE_SPEED

    var cam_delta := get_orbit_offset()
    var wanted_pos := ball_draw_pos + cam_delta
    _cam_pos += (wanted_pos - _cam_pos) * 0.5
    _cam_dir = (ball_draw_pos + LOOK_AT_OFFSET - _cam_pos).normalized()
    _apply()

## Port of _golf_game_get_camera_zone_angle (game.c:75).
func get_camera_zone_angle(ball_draw_pos: Vector3, hole_pos: Vector3) -> float:
    var zone := _find_camera_zone(ball_draw_pos)
    if zone == null:
        return angle
    var zone_dir: Vector3
    if zone.towards_hole:
        zone_dir = hole_pos - ball_draw_pos
        zone_dir.y = 0
        zone_dir = zone_dir.normalized()
    else:
        zone_dir = zone.global_transform.basis.x.normalized()
    var zone_angle := acos(clampf(zone_dir.x, -1.0, 1.0))
    if zone_dir.z > 0:
        zone_angle *= -1.0
    zone_angle += PI
    return zone_angle

func _find_camera_zone(pos: Vector3) -> GolfCameraZone:
    for zone in camera_zones:
        if is_instance_valid(zone) and zone.contains_point(pos):
            return zone
    return null

# --- Begin-level fly-in (game.c:774 / start_level) --------------------------

func start_begin_animation(begin_pos: Vector3, hole_pos: Vector3, ball_draw_pos: Vector3, start_angle: float) -> void:
    angle = start_angle
    _begin_t = 0.0
    _begin_pos0 = begin_pos
    _begin_dir0 = (hole_pos - begin_pos).normalized()
    var cam_delta := get_orbit_offset()
    _begin_pos1 = ball_draw_pos + cam_delta
    _begin_dir1 = (ball_draw_pos + LOOK_AT_OFFSET - _begin_pos1).normalized()
    _cam_pos = _begin_pos0
    _cam_dir = _begin_dir0
    _apply()

## Returns true when the animation has finished.
func update_begin_animation(dt: float) -> bool:
    var done := false
    var t := _begin_t
    if t >= BEGIN_LENGTH0:
        t -= BEGIN_LENGTH0
        var a := sin(0.5 * PI * t / BEGIN_LENGTH1)
        _cam_pos = _begin_pos0.lerp(_begin_pos1, a)
        _cam_dir = (_begin_dir0 * (1.0 - a) + _begin_dir1 * a).normalized()
        if t >= BEGIN_LENGTH1:
            done = true
            _cam_pos = _begin_pos1
            _cam_dir = _begin_dir1
    _begin_t += dt
    _apply()
    return done

## Instantly complete the begin fly-in, snapping to the final follow view. Used
## when the player skips the cutscene (restart-hole / R key).
func finish_begin_animation() -> void:
    _begin_t = BEGIN_LENGTH0 + BEGIN_LENGTH1
    _cam_pos = _begin_pos1
    _cam_dir = _begin_dir1
    _apply()

# --- Celebration (game.c:800) -----------------------------------------------

func start_celebration(ball_draw_pos: Vector3) -> void:
    _celebration_t = 0.0
    _celeb_pos0 = _cam_pos
    _celeb_dir0 = _cam_dir
    _celeb_pos1 = _cam_pos + _cam_dir * -1.5
    _celeb_dir1 = (ball_draw_pos - _celeb_pos1).normalized()

func update_celebration(dt: float) -> bool:
    var done := false
    var a := sin(0.5 * PI * _celebration_t / CELEBRATION_LENGTH)
    _cam_pos = _celeb_pos0 + (_celeb_pos1 - _celeb_pos0) * a
    _cam_dir = _celeb_dir0 + (_celeb_dir1 - _celeb_dir0) * a
    if _celebration_t >= CELEBRATION_LENGTH:
        done = true
    _celebration_t += dt
    _apply()
    return done
