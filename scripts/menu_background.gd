class_name MenuBackground
extends SubViewportContainer
## Living backdrop for the main menu: renders a real ported golf hole into a
## SubViewport and very slowly orbits a Camera3D around it, crossfading to the
## next hole every few seconds. Deliberately gentle (slow drift, long fades) so
## it never competes with the menu for attention.
##
## Input is ignored (mouse_filter = IGNORE) so the menu buttons drawn on top
## still receive clicks. No physics/collision world is built — purely visual.

# Holes to cycle through. Chosen for varied, photogenic layouts.
const LEVELS: Array[int] = [1, 4, 7, 11, 15, 18]
const DISPLAY_TIME := 16.0   ## seconds a hole stays on screen before swapping
const FADE_TIME := 1.4       ## crossfade-to-black duration on each side of a swap
const ORBIT_SPEED := 0.05    ## radians/sec horizontal drift — intentionally slow

var _viewport: SubViewport
var _camera: Camera3D
var _level_root: Node3D
var _slot: int = 0
var _elapsed: float = 0.0
var _orbit_angle: float = 0.0
var _orbit_radius: float = 6.0
var _orbit_height: float = 4.0
var _look_target: Vector3 = Vector3.ZERO
var _swapping: bool = false

func _ready() -> void:
    # Fill the parent; the scene already anchors this full-rect, but set it here
    # too so the node works if instanced standalone. With stretch=true the
    # SubViewport is automatically resized to match this container.
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    stretch = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    _viewport = SubViewport.new()
    _viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _viewport.msaa_3d = Viewport.MSAA_2X
    # Own World3D so the menu's 3D scene renders in isolation inside this viewport.
    _viewport.own_world_3d = true
    add_child(_viewport)

    # Same lighting/sky as the playable scene so the holes read correctly.
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -35, 0)
    light.shadow_enabled = true
    _viewport.add_child(light)

    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.4, 0.6, 0.85)
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.6, 0.6, 0.6)
    env.environment = e
    _viewport.add_child(env)

    _camera = Camera3D.new()
    _camera.fov = 50.0
    _viewport.add_child(_camera)
    _camera.make_current()

    _load_slot(0)

## Build the hole at the given slot and frame the camera on it.
func _load_slot(slot: int) -> void:
    _slot = slot
    if _level_root != null:
        _level_root.queue_free()
    _level_root = Node3D.new()
    _viewport.add_child(_level_root)

    var idx: int = LEVELS[slot % LEVELS.size()]
    var data: GolfLevelData = GolfLevelData.load_from("res://assets/levels/level-%d.level" % idx)
    if data == null:
        return
    var res: Dictionary = GolfLevelBuilder.build(data, _level_root)
    var ball_start: Vector3 = res["ball_start"]
    var hole_pos: Vector3 = res["hole_pos"]
    var begin_cam: Vector3 = res["begin_cam_pos"]

    # Frame on the midpoint between tee and hole, using the level's own cinematic
    # "begin" camera position to derive a sensible orbit radius/height.
    _look_target = (ball_start + hole_pos) * 0.5 + Vector3.UP * 0.3
    var off: Vector3 = begin_cam - _look_target
    _orbit_radius = maxf(Vector2(off.x, off.z).length(), 3.5)
    _orbit_height = maxf(off.y, 2.5)
    _orbit_angle = atan2(off.z, off.x)
    _elapsed = 0.0
    _update_camera()

func _update_camera() -> void:
    if _camera == null:
        return
    var pos := _look_target + Vector3(
        cos(_orbit_angle) * _orbit_radius,
        _orbit_height,
        sin(_orbit_angle) * _orbit_radius)
    _camera.global_position = pos
    _camera.look_at(_look_target, Vector3.UP)

func _process(delta: float) -> void:
    _orbit_angle += ORBIT_SPEED * delta
    _update_camera()

    _elapsed += delta
    if not _swapping and _elapsed >= DISPLAY_TIME:
        _swapping = true
        var tw := create_tween()
        tw.tween_property(self, "modulate:a", 0.0, FADE_TIME)
        tw.tween_callback(_advance)
        tw.tween_property(self, "modulate:a", 1.0, FADE_TIME)
        tw.tween_callback(func() -> void: _swapping = false)

func _advance() -> void:
    _load_slot((_slot + 1) % LEVELS.size())
