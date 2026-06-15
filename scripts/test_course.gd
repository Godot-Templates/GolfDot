extends Node3D
## Phase 2 + 3 harness: a small course driven by the ported game loop -
## camera rig (GolfCamera), aiming (GolfAim) with reflective preview line, and
## the Open-Golf state machine (begin fly-in -> waiting -> aiming -> watching ->
## celebration).
##
## Controls:
##   Mouse: press on the ball's ring and drag back (slingshot) to aim, release to hit.
##   Keyboard fallback: Left/Right rotate camera, Up/Down power, Space hit, R reset.

const BALL_MESH := preload("res://Open-Golf/data/models/golf_ball.obj")
const HOLE_MESH := preload("res://Open-Golf/data/models/hole.obj")

const HOLE_SCALE := 0.4
const BALL_RADIUS := 0.12
const BALL_START := Vector3(0, BALL_RADIUS, -8)
const HOLE_POS := Vector3(0, 0, 0)
const BEGIN_CAM_POS := Vector3(6.0, 4.5, -4.0)

enum State { BEGIN, WAITING, AIMING, WATCHING, CELEBRATION, FINISHED }

const DEBUG_AIM_PREVIEW := false  # set true to hold a persistent aim line for verification

var _world: GolfCollisionWorld
var _physics: GolfPhysics
var _camera: GolfCamera
var _ball_mi: MeshInstance3D
var _aim: GolfAim
var _aim_line: GolfAimLine
var _overlay: GolfAimOverlay
var _label: Label

var _state: int = State.BEGIN
var _stroke_count: int = 0
var _kb_power: float = 0.55

var _mouse_was_down: bool = false
var _aim_circle_radius: float = 60.0
var _aim_is_keyboard: bool = false

func _ready() -> void:
    _build_environment()
    _build_course()
    _build_camera_zone()
    _build_hole()
    _build_ball()
    _build_aim_visuals()
    _build_ui()

    _world = GolfCollisionWorld.new()
    _world.build_from_scene(self)

    _physics = GolfPhysics.new()
    _physics.ball_radius = BALL_RADIUS
    _physics.world = _world
    for hole in _find_holes(self):
        _physics.holes.append(hole)
    _physics.place_ball(BALL_START)

    _aim = GolfAim.new()

    # Collect camera zones for the rig.
    for z in get_tree().get_nodes_in_group("golf_camera_zone"):
        if z is GolfCameraZone:
            _camera.camera_zones.append(z)

    # Kick off the begin-level fly-in.
    var start_angle := _camera.get_camera_zone_angle(BALL_START, HOLE_POS)
    _camera.start_begin_animation(BEGIN_CAM_POS, HOLE_POS, BALL_START, start_angle)

    print("Collision triangles baked: ", _world.triangle_count())

func _physics_process(delta: float) -> void:
    match _state:
        State.BEGIN:
            if _camera.update_begin_animation(delta):
                _state = State.WAITING
        State.WAITING:
            _physics.update(delta)
            _camera.update_follow(_physics.ball_draw_pos, HOLE_POS, delta)
            _handle_waiting_input(delta)
        State.AIMING:
            _physics.update(delta)
            _update_aiming(delta)
        State.WATCHING:
            _physics.update(delta)
            _camera.update_follow(_physics.ball_draw_pos, HOLE_POS, delta)
            _update_watching()
        State.CELEBRATION:
            if _camera.update_celebration(delta):
                _state = State.FINISHED
        State.FINISHED:
            pass
    _update_ball_transform()
    _update_label()

# --- State: waiting for aim --------------------------------------------------

func _handle_waiting_input(delta: float) -> void:
    if DEBUG_AIM_PREVIEW and not _aim_is_keyboard:
        _aim_is_keyboard = true
        _kb_power = 0.7
        _aim.aim_delta = Vector2(0, 1)
        _aim.power = _kb_power
        _state = State.AIMING
        return

    # Keyboard fallback.
    if Input.is_action_pressed("ui_left"):
        _camera.auto_rotate = false
        _camera.angle -= 1.5 * delta
    if Input.is_action_pressed("ui_right"):
        _camera.auto_rotate = false
        _camera.angle += 1.5 * delta
    if Input.is_action_just_pressed("ui_up"):
        _kb_power = minf(_kb_power + 0.1, 1.0)
    if Input.is_action_just_pressed("ui_down"):
        _kb_power = maxf(_kb_power - 0.1, 0.1)
    if Input.is_action_just_pressed("ui_accept"):
        # Begin keyboard aiming (hold to preview the aim line, release to hit).
        _aim_is_keyboard = true
        _aim.aim_delta = Vector2(0, 1)
        _aim.power = _kb_power
        _state = State.AIMING
        return
    if Input.is_physical_key_pressed(KEY_R):
        _reset_ball()

    # Mouse: start aiming if pressed within the ball's aim ring.
    _update_aim_circle_radius()
    var mouse := get_viewport().get_mouse_position()
    var ball_screen := _camera.unproject_position(_physics.ball_draw_pos)
    var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    var just_pressed := down and not _mouse_was_down
    _mouse_was_down = down

    if just_pressed and mouse.distance_to(ball_screen) <= _aim_circle_radius:
        _aim.reset()
        _state = State.AIMING

    _overlay.update_aim(false, ball_screen, mouse, _aim_circle_radius, Color.GREEN)

# --- State: aiming -----------------------------------------------------------

func _update_aiming(delta: float) -> void:
    if _aim_is_keyboard:
        _update_aiming_keyboard(delta)
        return

    var mouse := get_viewport().get_mouse_position()
    var ball_screen := _camera.unproject_position(_physics.ball_draw_pos)
    var viewport_h := float(get_viewport().get_visible_rect().size.y)

    _aim.update_from_drag(ball_screen, mouse, viewport_h)
    _aim.apply_camera_rotation(_camera, delta)
    _camera.update_follow(_physics.ball_draw_pos, HOLE_POS, delta)

    # Reflective aim-line preview.
    if _aim.power > 0.0:
        var pts := _aim.compute_aim_line(_physics.ball_pos, _camera.angle, _world)
        _aim_line.set_points(pts, _aim.get_power_color())
    else:
        _aim_line.clear()
    _overlay.update_aim(true, ball_screen, mouse, _aim_circle_radius, _aim.get_power_color())

    # Release to hit (or cancel if no power).
    var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    var just_released := (not down) and _mouse_was_down
    _mouse_was_down = down
    if just_released:
        if _aim.power > 0.0:
            _hit_ball()
        else:
            _state = State.WAITING
            _aim_line.clear()
            _overlay.update_aim(false, ball_screen, mouse, _aim_circle_radius, Color.GREEN)

func _update_aiming_keyboard(delta: float) -> void:
    # Left/Right rotate the shot, Up/Down adjust power while holding Space.
    if Input.is_action_pressed("ui_left"):
        _camera.auto_rotate = false
        _camera.angle -= 1.5 * delta
    if Input.is_action_pressed("ui_right"):
        _camera.auto_rotate = false
        _camera.angle += 1.5 * delta
    if Input.is_action_just_pressed("ui_up"):
        _kb_power = minf(_kb_power + 0.1, 1.0)
    if Input.is_action_just_pressed("ui_down"):
        _kb_power = maxf(_kb_power - 0.1, 0.1)

    _aim.aim_delta = Vector2(0, 1)
    _aim.power = _kb_power
    _camera.update_follow(_physics.ball_draw_pos, HOLE_POS, delta)

    var pts := _aim.compute_aim_line(_physics.ball_pos, _camera.angle, _world)
    _aim_line.set_points(pts, _aim.get_power_color())

    if not DEBUG_AIM_PREVIEW and Input.is_action_just_released("ui_accept"):
        _aim_is_keyboard = false
        _hit_ball()

# --- State: watching ball ----------------------------------------------------

func _update_watching() -> void:
    if _physics.ball_is_in_hole:
        _physics.ball_vel = Vector3.ZERO
        _physics.ball_is_moving = false
        _camera.start_celebration(_physics.ball_draw_pos)
        _state = State.CELEBRATION
    elif _physics.ball_is_out_of_bounds:
        _physics.place_ball(BALL_START)
        _camera.auto_rotate = false
        _state = State.WAITING
    elif not _physics.ball_is_moving:
        _state = State.WAITING

# --- Actions -----------------------------------------------------------------

func _hit_ball() -> void:
    _stroke_count += 1
    var dir := _aim.get_aim_direction(_camera.angle)
    var speed := _aim.get_launch_speed()
    _camera.auto_rotate = true
    _physics.launch(dir * speed)
    _aim_line.clear()
    _overlay.active = false
    _overlay.queue_redraw()
    _state = State.WATCHING

func _reset_ball() -> void:
    _physics.place_ball(BALL_START)
    _state = State.WAITING

# --- Visual updates ----------------------------------------------------------

func _update_ball_transform() -> void:
    var b := Basis(_physics.ball_orientation).scaled(Vector3.ONE * BALL_RADIUS)
    _ball_mi.transform = Transform3D(b, _physics.ball_draw_pos)

func _update_aim_circle_radius() -> void:
    var ball_screen := _camera.unproject_position(_physics.ball_draw_pos)
    var right := _camera.global_transform.basis.x
    var edge := _camera.unproject_position(_physics.ball_draw_pos + right * (2.0 * BALL_RADIUS))
    var r := ball_screen.distance_to(edge)
    _aim_circle_radius = r if r > 16.0 else 60.0

func _update_label() -> void:
    var names: Array[String] = ["BEGIN", "WAITING", "AIMING", "WATCHING", "CELEBRATION", "FINISHED"]
    var state_name: String = names[_state]
    _label.text = "State: %s   Strokes: %d\nPower: %.2f   CamAngle: %d deg\nMouse: press ring + drag back, release to hit\nKeys: Left/Right aim  Up/Down power  Space hit  R reset" % [
        state_name, _stroke_count, (_aim.power if _state == State.AIMING else _kb_power), int(rad_to_deg(_camera.angle))]

# --- Scene construction -----------------------------------------------------

func _build_environment() -> void:
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -35, 0)
    light.shadow_enabled = true
    add_child(light)

    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.4, 0.6, 0.85)
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.6, 0.6, 0.6)
    env.environment = e
    add_child(env)

    _camera = GolfCamera.new()
    add_child(_camera)

func _build_course() -> void:
    var grass := _make_material(0.3, 0.4, 1.0)
    var wall_side := _make_material(0.0, 1.0, 0.8)

    var green := Color(0.30, 0.62, 0.30)
    _add_box(Vector3(-2.75, -0.25, -3), Vector3(4.5, 0.5, 14), grass, green)
    _add_box(Vector3(2.75, -0.25, -3), Vector3(4.5, 0.5, 14), grass, green)
    _add_box(Vector3(0, -0.25, -5.25), Vector3(1.0, 0.5, 9.5), grass, green)
    _add_box(Vector3(0, -0.25, 2.25), Vector3(1.0, 0.5, 3.5), grass, green)

    var wall_col := Color(0.55, 0.4, 0.25)
    _add_box(Vector3(-5.1, 0.3, -3), Vector3(0.4, 0.8, 14), wall_side, wall_col)
    _add_box(Vector3(5.1, 0.3, -3), Vector3(0.4, 0.8, 14), wall_side, wall_col)
    _add_box(Vector3(0, 0.3, 4.2), Vector3(10.6, 0.8, 0.4), wall_side, wall_col)
    _add_box(Vector3(0, 0.3, -10.2), Vector3(10.6, 0.8, 0.4), wall_side, wall_col)

    var ramp := _add_box(Vector3(2.5, 0.2, -3), Vector3(2.0, 0.3, 2.0), grass, Color(0.35, 0.55, 0.35))
    ramp.rotation_degrees = Vector3(18, 0, 0)

func _build_camera_zone() -> void:
    var zone := GolfCameraZone.new()
    zone.name = "CameraZone"
    zone.towards_hole = true
    zone.half_extents = Vector3(5.0, 2.0, 8.0)
    zone.position = Vector3(0, 0, -3)
    add_child(zone)

func _build_hole() -> void:
    var hole := GolfHole.new()
    hole.name = "Hole"
    hole.radius = HOLE_SCALE
    hole.position = HOLE_POS
    add_child(hole)

    var cup := MeshInstance3D.new()
    cup.mesh = HOLE_MESH
    cup.scale = Vector3.ONE * HOLE_SCALE
    hole.add_child(cup)
    hole.cup_mesh = cup

func _build_ball() -> void:
    _ball_mi = MeshInstance3D.new()
    _ball_mi.mesh = BALL_MESH
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color.WHITE
    _ball_mi.material_override = mat
    add_child(_ball_mi)

func _build_aim_visuals() -> void:
    _aim_line = GolfAimLine.new()
    add_child(_aim_line)

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    _overlay = GolfAimOverlay.new()
    layer.add_child(_overlay)
    _label = Label.new()
    _label.position = Vector2(16, 16)
    _label.add_theme_color_override("font_color", Color.BLACK)
    layer.add_child(_label)

# --- Helpers ----------------------------------------------------------------

func _make_material(friction: float, restitution: float, vel_scale: float) -> GolfMaterial:
    var m := GolfMaterial.new()
    m.friction = friction
    m.restitution = restitution
    m.vel_scale = vel_scale
    return m

func _add_box(center: Vector3, size: Vector3, mat: GolfMaterial, color: Color) -> GolfSurface:
    var s := GolfSurface.new()
    var box := BoxMesh.new()
    box.size = size
    s.mesh = box
    s.golf_material = mat
    var vis := StandardMaterial3D.new()
    vis.albedo_color = color
    s.material_override = vis
    s.position = center
    add_child(s)
    return s

func _find_holes(node: Node) -> Array[GolfHole]:
    var out: Array[GolfHole] = []
    if node is GolfHole:
        out.append(node)
    for c in node.get_children():
        out.append_array(_find_holes(c))
    return out
