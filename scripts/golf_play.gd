extends Node3D
## Plays a ported Open-Golf level. Loads a .level file via GolfLevelData +
## GolfLevelBuilder, then drives it through the same state machine / camera rig /
## aiming used by the original (begin fly-in -> waiting -> aiming -> watching ->
## celebration). Set `level_path` (or call load_level) to choose the hole.
##
## Controls:
##   Mouse: press on the ball's ring and drag back (slingshot) to aim, release to hit.
##   Keyboard fallback: Left/Right rotate camera, Up/Down power, Space hit, R reset.

@export var level_path: String = "res://assets/levels/level-1.level"

const BALL_MESH := preload("res://assets/models/golf_ball.obj")
const BALL_RADIUS := 0.12
const LEVEL_COUNT := 20
const FINISH_ADVANCE_DELAY := 2.5

# Left-click drag (outside the ball's aim ring) pans/orbits the camera around the
# ball. Radians per pixel — horizontal orbit and vertical tilt.
const PAN_SENSITIVITY := 0.0025
const PAN_PITCH_SENSITIVITY := 0.0025

var _level_index: int = 1
var _finish_timer: float = 0.0

# Scoring (per-hole par + persisted best, plus running session totals).
var _par: int = 3
var _best: int = -1
var _scored: bool = false
var _is_new_best: bool = false
var _total_strokes: int = 0
var _total_par: int = 0
var _summary_shown: bool = false
var _paused: bool = false
var _pause_menu: Control

const MENU_SCENE := "res://scenes/level_select.tscn"

enum State { BEGIN, WAITING, AIMING, WATCHING, CELEBRATION, FINISHED }

var _world: GolfCollisionWorld
var _physics: GolfPhysics
var _camera: GolfCamera
var _ball_mi: MeshInstance3D
var _aim: GolfAim
var _aim_line: GolfAimLine
var _overlay: GolfAimOverlay
var _stat_line: Label
var _status_label: Label
var _audio: GolfAudio
var _level_root: Node3D
var _ui_layer: CanvasLayer

# In-level highscores board overlay (top players for the current hole).
var _board_overlay: Control
var _board_list: VBoxContainer
var _board_status: Label

var _ball_start: Vector3 = Vector3.ZERO
var _hole_pos: Vector3 = Vector3.ZERO
var _begin_cam_pos: Vector3 = Vector3(6, 5, -4)
var _movers: Array = []

var _state: int = State.BEGIN
var _stroke_count: int = 0
var _kb_power: float = 0.55

var _mouse_was_down: bool = false
var _aim_circle_radius: float = 60.0
var _aim_is_keyboard: bool = false
var _panning: bool = false

func _ready() -> void:
    _build_environment()
    _build_ui()
    _level_index = _index_from_path(level_path)
    load_level(level_path)

func _index_from_path(path: String) -> int:
    var digits := ""
    for c in path.get_file():
        if c.is_valid_int():
            digits += c
    return clampi(int(digits) if not digits.is_empty() else 1, 1, LEVEL_COUNT)

## Load a level by its 1-based index (1..LEVEL_COUNT).
func load_level_index(idx: int) -> void:
    _level_index = clampi(idx, 1, LEVEL_COUNT)
    load_level("res://assets/levels/level-%d.level" % _level_index)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_N, KEY_BRACKETRIGHT:
                load_level_index(_level_index + 1)
            KEY_P, KEY_BRACKETLEFT:
                load_level_index(_level_index - 1)
            KEY_ESCAPE, KEY_M:
                _toggle_pause()

    # Left-click drag OUTSIDE the ball's aim ring orbits the camera around the
    # ball (horizontal pan + vertical tilt). Pressing ON the ring still starts
    # aiming, so the two don't conflict. Panning turns off auto-rotate so the
    # chosen view sticks.
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            if not _paused and _camera != null and _physics != null \
                    and (_state == State.WAITING or _state == State.WATCHING):
                var ball_screen := _camera.unproject_position(_physics.ball_draw_pos)
                if event.position.distance_to(ball_screen) > _aim_circle_radius:
                    _panning = true
        else:
            _panning = false

    if event is InputEventMouseMotion and _panning and _camera != null:
        _camera.auto_rotate = false
        _camera.angle -= event.relative.x * PAN_SENSITIVITY
        _camera.pitch = clampf(
            _camera.pitch + event.relative.y * PAN_PITCH_SENSITIVITY,
            GolfCamera.PITCH_MIN, GolfCamera.PITCH_MAX)

## (Re)load a level by res:// path and reset the state machine.
func load_level(path: String) -> void:
    level_path = path
    if _level_root != null:
        _level_root.queue_free()
    _level_root = Node3D.new()
    _level_root.name = "Level"
    add_child(_level_root)

    var data := GolfLevelData.load_from(path)
    if data == null:
        push_error("golf_play: failed to load %s" % path)
        return
    var res := GolfLevelBuilder.build(data, _level_root)
    _ball_start = res["ball_start"]
    _hole_pos = res["hole_pos"]
    _begin_cam_pos = res["begin_cam_pos"]
    _movers = res["movers"]

    # Build collision after nodes are in the tree (world transforms are valid).
    # Mover surfaces are baked dynamically, so exclude them from the static set.
    var mover_surfaces: Array = []
    for mv in _movers:
        mover_surfaces.append_array(mv["surfaces"])
    _world = GolfCollisionWorld.new()
    _world.build_from_scene(_level_root, mover_surfaces)
    for mv in _movers:
        _world.register_mover(mv["node"], mv["surfaces"], mv["base_transform"], mv["movement"])

    _physics = GolfPhysics.new()
    _physics.ball_radius = BALL_RADIUS
    _physics.world = _world
    for hole in res["holes"]:
        _physics.holes.append(hole)
    # The ball-start entity sits at ground level; the ball's center must rest at
    # ground + radius or it spawns half-buried (the solver won't lift a resting
    # ball). Snap to whatever surface is directly below the spawn.
    _ball_start = _snap_ball_to_floor(_ball_start)
    _physics.place_ball(_ball_start)

    _aim = GolfAim.new()
    if _audio != null:
        _audio.queue_free()
    _audio = GolfAudio.new()
    add_child(_audio)
    _physics.impact_sound.connect(_audio.play_impact)

    # Collect camera zones from THIS level's subtree only. Using the global
    # group is unsafe here: the previous level's _level_root is queue_free()'d
    # (deferred), so its zones are still in the group this frame and would leave
    # the camera holding freed references next frame.
    _camera.camera_zones.clear()
    _collect_camera_zones(_level_root)

    if _ball_mi != null:
        _ball_mi.queue_free()
    _build_ball()

    _stroke_count = 0
    _finish_timer = 0.0
    _par = GolfScores.get_par(_level_index)
    _best = GolfScores.get_best(_level_index)
    _scored = false
    _is_new_best = false
    _summary_shown = false
    _set_paused(false)
    _state = State.BEGIN
    var start_angle := _camera.get_camera_zone_angle(_ball_start, _hole_pos)
    _camera.start_begin_animation(_begin_cam_pos, _hole_pos, _ball_start, start_angle)
    print("Level %s baked %d collision triangles, %d movers" % [path, _world.triangle_count(), _movers.size()])

func _physics_process(delta: float) -> void:
    if _physics == null or _paused:
        return
    match _state:
        State.BEGIN:
            # Open-Golf runs physics in every state above the main menu (game.c),
            # so movers animate during the fly-in.
            _physics.update(delta)
            if _camera.update_begin_animation(delta):
                _state = State.WAITING
        State.WAITING:
            _physics.update(delta)
            _camera.update_follow(_physics.ball_draw_pos, _hole_pos, delta)
            _handle_waiting_input(delta)
        State.AIMING:
            _physics.update(delta)
            _update_aiming(delta)
        State.WATCHING:
            _physics.update(delta)
            _camera.update_follow(_physics.ball_draw_pos, _hole_pos, delta)
            _update_watching()
        State.CELEBRATION:
            if _camera.update_celebration(delta):
                _state = State.FINISHED
        State.FINISHED:
            if _level_index >= LEVEL_COUNT:
                # Finished the last hole: show the round summary (once).
                if not _summary_shown:
                    _show_round_summary()
            else:
                # Auto-advance to the next hole after a short delay.
                _finish_timer += delta
                if _finish_timer >= FINISH_ADVANCE_DELAY:
                    load_level_index(_level_index + 1)
                    return
    _audio.set_water(_physics.ball_is_in_water)
    _update_ball_transform()
    _update_label()

# --- State: waiting for aim --------------------------------------------------

func _handle_waiting_input(delta: float) -> void:
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
        _aim_is_keyboard = true
        _aim.aim_delta = Vector2(0, 1)
        _aim.power = _kb_power
        _state = State.AIMING
        return
    if Input.is_physical_key_pressed(KEY_R):
        _reset_ball()

    _update_aim_circle_radius()
    var mouse := get_viewport().get_mouse_position()
    var ball_screen := _camera.unproject_position(_physics.ball_draw_pos)
    var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    var just_pressed := down and not _mouse_was_down
    _mouse_was_down = down

    if just_pressed and mouse.distance_to(ball_screen) <= _aim_circle_radius:
        _aim.reset()
        _aim_is_keyboard = false
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
    _camera.update_follow(_physics.ball_draw_pos, _hole_pos, delta)

    if _aim.power > 0.0:
        var pts := _aim.compute_aim_line(_physics.ball_pos, _camera.angle, _world)
        _aim_line.set_points(pts, _aim.get_power_color())
    else:
        _aim_line.clear()
    _overlay.update_aim(true, ball_screen, mouse, _aim_circle_radius, _aim.get_power_color())

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
    _camera.update_follow(_physics.ball_draw_pos, _hole_pos, delta)

    var pts := _aim.compute_aim_line(_physics.ball_pos, _camera.angle, _world)
    _aim_line.set_points(pts, _aim.get_power_color())

    if Input.is_action_just_released("ui_accept"):
        _aim_is_keyboard = false
        _hit_ball()

# --- State: watching ball ----------------------------------------------------

func _update_watching() -> void:
    if _physics.ball_is_in_hole:
        _physics.ball_vel = Vector3.ZERO
        _physics.ball_is_moving = false
        _audio.play_in_hole()
        _record_hole_score()
        _camera.start_celebration(_physics.ball_draw_pos)
        _state = State.CELEBRATION
    elif _physics.ball_is_out_of_bounds:
        # Re-spot at the lie the stroke was taken from (Open-Golf resets to
        # ball.start_pos), not the tee.
        _audio.play_out_of_bounds()
        _physics.place_ball(_physics.ball_start_pos)
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
    _audio.play_hit()
    _aim_line.clear()
    _overlay.active = false
    _overlay.queue_redraw()
    _state = State.WATCHING

## Persist the best score for this hole and accumulate the running session
## totals. Guarded so a hole is only counted once.
func _record_hole_score() -> void:
    if _scored:
        return
    _scored = true
    _is_new_best = GolfScores.record(_level_index, _stroke_count)
    _best = GolfScores.get_best(_level_index)
    _total_strokes += _stroke_count
    _total_par += _par
    _submit_to_leaderboard()

## Publish this hole's best to the global durable leaderboard, plus the full
## 20-hole course total once every hole has a local best. Reached via the node
## tree so it degrades cleanly if the autoload is absent.
func _submit_to_leaderboard() -> void:
    var lb := get_node_or_null("/root/Leaderboard")
    if lb == null:
        return
    var pname := PlayerProfile.get_player_name()
    lb.submit_hole(_level_index, pname, _best)
    var total := 0
    for i in range(1, LEVEL_COUNT + 1):
        var b := GolfScores.get_best(i)
        if b < 0:
            return
        total += b
    lb.submit_total(pname, total)

func _reset_ball() -> void:
    _physics.place_ball(_ball_start)
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
    var best_str := "--" if _best < 0 else str(_best)
    _stat_line.text = "Hole %d/%d    Par %d    Strokes %d    Best %s" % [
        _level_index, LEVEL_COUNT, _par, _stroke_count, best_str]

    if _state == State.CELEBRATION or _state == State.FINISHED:
        var tag := "   ★ NEW BEST!" if _is_new_best else ""
        _status_label.text = "IN THE HOLE!  %d strokes (%s)%s" % [
            _stroke_count, _par_term(_stroke_count, _par), tag]
        _status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
    elif _total_par > 0:
        _status_label.text = "Total %d  (%s vs par)" % [_total_strokes, _par_term(_total_strokes, _total_par)]
        _status_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.85))
    else:
        _status_label.text = ""

## Format strokes relative to par as golf shorthand (E, -1, +2, ...).
func _par_term(strokes: int, par: int) -> String:
    var d := strokes - par
    if d == 0:
        return "E"
    return ("+%d" % d) if d > 0 else str(d)

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

func _build_ball() -> void:
    _ball_mi = MeshInstance3D.new()
    _ball_mi.name = "Ball"
    _ball_mi.mesh = BALL_MESH
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color.WHITE
    _ball_mi.material_override = mat
    add_child(_ball_mi)

func _build_ui() -> void:
    _aim_line = GolfAimLine.new()
    add_child(_aim_line)
    _ui_layer = CanvasLayer.new()
    add_child(_ui_layer)
    _overlay = GolfAimOverlay.new()
    _ui_layer.add_child(_overlay)
    _build_scoreboard()

    # "Menu" button (top-right). Opens the pause overlay (also Esc / M).
    var menu_btn := Button.new()
    menu_btn.text = "Menu (Esc)"
    menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    menu_btn.position = Vector2(-128, 12)
    menu_btn.pressed.connect(_toggle_pause)
    _ui_layer.add_child(menu_btn)

    _build_pause_menu()

## Top-left scoreboard: a single clean stat line on a subtle panel, with a
## small status line below for cross-hole total / celebration.
func _build_scoreboard() -> void:
    var hud := VBoxContainer.new()
    hud.position = Vector2(16, 16)
    hud.add_theme_constant_override("separation", 6)
    _ui_layer.add_child(hud)

    var panel := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0.45)
    sb.set_corner_radius_all(6)
    sb.content_margin_left = 14
    sb.content_margin_right = 14
    sb.content_margin_top = 8
    sb.content_margin_bottom = 8
    panel.add_theme_stylebox_override("panel", sb)
    hud.add_child(panel)

    _stat_line = Label.new()
    _stat_line.add_theme_font_size_override("font_size", 16)
    _stat_line.add_theme_color_override("font_color", Color(0.95, 0.97, 0.95))
    panel.add_child(_stat_line)

    _status_label = Label.new()
    _status_label.add_theme_font_size_override("font_size", 13)
    _status_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.85))
    _status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
    _status_label.add_theme_constant_override("outline_size", 4)
    hud.add_child(_status_label)

    # "Highscores" button sits directly beneath the HUD; opens the per-hole
    # top-players board for the level currently being played.
    var board_btn := Button.new()
    board_btn.text = "Highscores"
    board_btn.custom_minimum_size = Vector2(120, 30)
    board_btn.pressed.connect(_toggle_board)
    hud.add_child(board_btn)

# --- Pause menu --------------------------------------------------------------

func _build_pause_menu() -> void:
    _pause_menu = Control.new()
    _pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
    _pause_menu.visible = false
    _ui_layer.add_child(_pause_menu)

    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.55)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _pause_menu.add_child(dim)

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    _pause_menu.add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(320, 0)
    center.add_child(panel)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 14)
    panel.add_child(vbox)

    var title := Label.new()
    title.text = "Paused"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 30)
    vbox.add_child(title)

    # Volume control (master bus).
    var vol_row := HBoxContainer.new()
    vol_row.add_theme_constant_override("separation", 10)
    vbox.add_child(vol_row)
    var vol_label := Label.new()
    vol_label.text = "Volume"
    vol_row.add_child(vol_label)
    var slider := HSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.01
    slider.custom_minimum_size = Vector2(180, 0)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var bus := AudioServer.get_bus_index("Master")
    slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus))
    slider.value_changed.connect(_on_volume_changed)
    vol_row.add_child(slider)

    var resume := Button.new()
    resume.text = "Resume"
    resume.pressed.connect(_toggle_pause)
    vbox.add_child(resume)

    var restart := Button.new()
    restart.text = "Restart Hole"
    restart.pressed.connect(func() -> void: load_level_index(_level_index))
    vbox.add_child(restart)

    var to_menu := Button.new()
    to_menu.text = "Level Select"
    to_menu.pressed.connect(_go_to_menu)
    vbox.add_child(to_menu)

func _on_volume_changed(value: float) -> void:
    var bus := AudioServer.get_bus_index("Master")
    AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.0001)))
    AudioServer.set_bus_mute(bus, value <= 0.0)

func _toggle_pause() -> void:
    _set_paused(not _paused)

func _set_paused(value: bool) -> void:
    _paused = value
    if _pause_menu != null:
        _pause_menu.visible = value

## Raycast straight down from above `pos` and return a point resting on the
## surface (floor hit + ball radius). Falls back to `pos` if nothing is below.
func _snap_ball_to_floor(pos: Vector3) -> Vector3:
    var origin := pos + Vector3(0, 2.0, 0)
    var normal_out: Array = [Vector3.UP]
    var dist := _world.ray_test(origin, Vector3(0, -1, 0), normal_out)
    if dist > 0.0:
        var floor_y := origin.y - dist
        return Vector3(pos.x, floor_y + BALL_RADIUS, pos.z)
    return pos

## Recursively gather this level's GolfCameraZone nodes.
func _collect_camera_zones(node: Node) -> void:
    if node is GolfCameraZone:
        _camera.camera_zones.append(node)
    for child in node.get_children():
        _collect_camera_zones(child)

## Return to the level-select menu.
func _go_to_menu() -> void:
    get_tree().change_scene_to_file(MENU_SCENE)

## Show the end-of-round summary panel (total strokes vs par) after the final
## hole, with options to return to the menu or replay from hole 1.
func _show_round_summary() -> void:
    _summary_shown = true
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_CENTER)
    panel.position = Vector2(-180, -110)
    panel.custom_minimum_size = Vector2(360, 220)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 12)
    panel.add_child(vbox)

    var title := Label.new()
    title.text = "Round Complete!"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    vbox.add_child(title)

    var stats := Label.new()
    stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    stats.text = "Total: %d strokes\nPar: %d\nScore: %s" % [
        _total_strokes, _total_par, _par_term(_total_strokes, _total_par)]
    vbox.add_child(stats)

    var replay := Button.new()
    replay.text = "Play Again (Hole 1)"
    replay.pressed.connect(func() -> void:
        panel.queue_free()
        _total_strokes = 0
        _total_par = 0
        load_level_index(1))
    vbox.add_child(replay)

    var menu := Button.new()
    menu.text = "Back to Menu"
    menu.pressed.connect(_go_to_menu)
    vbox.add_child(menu)

    _ui_layer.add_child(panel)

# --- In-level highscores board ----------------------------------------------

## Show/hide the per-hole top-players board. Built lazily on first open and
## refreshed live from the Leaderboard autoload's `updated` signal.
func _toggle_board() -> void:
    if _board_overlay == null:
        _build_board_overlay()
    _board_overlay.visible = not _board_overlay.visible
    if _board_overlay.visible:
        _refresh_board()

func _build_board_overlay() -> void:
    _board_overlay = Control.new()
    _board_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _board_overlay.visible = false
    _ui_layer.add_child(_board_overlay)

    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.55)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _board_overlay.add_child(dim)

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    _board_overlay.add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(360, 0)
    center.add_child(panel)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 10)
    panel.add_child(vbox)

    var title := Label.new()
    title.text = "Hole Highscores"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 26)
    vbox.add_child(title)

    _board_status = Label.new()
    _board_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _board_status.add_theme_font_size_override("font_size", 13)
    _board_status.modulate = Color(0.7, 0.8, 0.9)
    vbox.add_child(_board_status)

    _board_list = VBoxContainer.new()
    _board_list.add_theme_constant_override("separation", 4)
    _board_list.custom_minimum_size = Vector2(320, 0)
    vbox.add_child(_board_list)

    var close := Button.new()
    close.text = "Close"
    close.pressed.connect(_toggle_board)
    vbox.add_child(close)

    var lb := get_node_or_null("/root/Leaderboard")
    if lb != null and not lb.updated.is_connected(_refresh_board):
        lb.updated.connect(_refresh_board)

## Repopulate the board list with the top players for the current hole.
func _refresh_board() -> void:
    if _board_list == null:
        return
    for c in _board_list.get_children():
        c.queue_free()

    var lb := get_node_or_null("/root/Leaderboard")
    if lb == null:
        _board_status.text = "Leaderboard unavailable."
        return

    _board_status.text = "Hole %d  •  %s" % [
        _level_index, ("Online" if lb.is_online() else "Local only — enable multiplayer for global scores")]

    var board: Array = lb.get_hole_board(_level_index)
    if board.is_empty():
        var empty := Label.new()
        empty.text = "No scores yet — be the first!"
        empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _board_list.add_child(empty)
        return

    var me := PlayerProfile.get_player_name()
    for i in range(board.size()):
        var entry: Dictionary = board[i]
        var row := _make_board_row(i + 1, String(entry["name"]), int(entry["strokes"]), String(entry["name"]) == me)
        _board_list.add_child(row)

## One "rank. name .... strokes" row, highlighting the local player.
func _make_board_row(rank: int, player_name: String, strokes: int, is_me: bool) -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)

    var rank_label := Label.new()
    rank_label.text = "%d." % rank
    rank_label.custom_minimum_size = Vector2(28, 0)
    row.add_child(rank_label)

    var name_label := Label.new()
    name_label.text = player_name + (" (you)" if is_me else "")
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(name_label)

    var score_label := Label.new()
    score_label.text = str(strokes)
    score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    row.add_child(score_label)

    if is_me:
        var hl := Color(0.55, 1.0, 0.6)
        rank_label.add_theme_color_override("font_color", hl)
        name_label.add_theme_color_override("font_color", hl)
        score_label.add_theme_color_override("font_color", hl)
    return row
