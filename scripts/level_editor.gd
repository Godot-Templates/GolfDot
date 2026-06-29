class_name LevelEditor
extends Node3D
## Phase 4 shell for the Godot-native level editor. Provides the dedicated
## workspace, prefab placement/editing, snapping/grid transforms, and JSON
## save/load support for the editor-native .golfedit format.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ORBIT_SENSITIVITY := 0.006
const PAN_SENSITIVITY := 0.012
const ZOOM_STEP := 0.9
const MOVE_SPEED := 6.0
const PITCH_MIN := -1.35
const PITCH_MAX := -0.15
const DISTANCE_MIN := 3.0
const DISTANCE_MAX := 36.0
const RAY_LENGTH := 1000.0
const PIECE_COLLISION_LAYER := 8
const PIECE_COLLISION_MASK := 8
const DEFAULT_MOVE_SNAP := 0.25
const DEFAULT_ROTATE_SNAP := 22.5
const DEFAULT_SCALE_SNAP := 0.25
const GRID_HALF_EXTENTS := 20
const DEFAULT_EDITOR_SAVE_PATH := "user://custom_level.golfedit"
const GOLFEDIT_VERSION := 1
const LEVEL_EXPORT_EXTENSION := ".level"
const MOVEMENT_TYPES := ["none", "linear", "spinner", "pendulum", "ramp"]
const MOVEMENT_LABELS := ["Static", "Linear Mover", "Spinner", "Pendulum", "Ramp Transition"]
const GEO_FACE_NAMES := ["Top", "Bottom", "Back", "Right", "Front", "Left"]
const GEO_FACE_MATERIALS := ["ground", "wall-top", "wall-side", "water"]
const SHAPE_TYPES := ["curved_ramp", "halfpipe", "bump", "circular_platform", "arc"]
const SHAPE_LABELS := ["Curved Ramp", "Halfpipe", "Bump", "Circular Platform", "Arc/Loop Piece"]
const VISUAL_PRESET_LABELS := ["Bright Day", "Soft Overcast", "Sunset", "Night Mini-Golf"]
const VISUAL_PRESET_COLORS := [
    [0.4, 0.6, 0.85, 1.0],
    [0.58, 0.64, 0.70, 1.0],
    [0.95, 0.55, 0.32, 1.0],
    [0.04, 0.07, 0.14, 1.0],
]

@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _ui_root: Control = $UI/Root
@onready var _status_label: Label = $UI/Root/BottomBar/StatusLabel
@onready var _new_button: Button = $UI/Root/TopBar/NewButton
@onready var _load_button: Button = $UI/Root/TopBar/LoadButton
@onready var _save_button: Button = $UI/Root/TopBar/SaveButton
@onready var _export_button: Button = $UI/Root/TopBar/ExportButton
@onready var _play_test_button: Button = $UI/Root/TopBar/PlayTestButton
@onready var _back_button: Button = $UI/Root/TopBar/BackButton
@onready var _palette_box: VBoxContainer = $UI/Root/LeftPalette/Margin/VBox
@onready var _inspector_box: VBoxContainer = $UI/Root/RightInspector/Margin/VBox
@onready var _selection_label: Label = $UI/Root/RightInspector/Margin/VBox/SelectionLabel
@onready var _position_label: Label = $UI/Root/RightInspector/Margin/VBox/PositionLabel
@onready var _snap_label: Label = $UI/Root/RightInspector/Margin/VBox/SnapLabel

var _yaw: float = 0.65
var _pitch: float = -0.72
var _distance: float = 13.0
var _focus_position: Vector3 = Vector3.ZERO
var _orbiting: bool = false
var _panning: bool = false
var _pieces_root: Node3D
var _selected_piece: Node3D = null
var _piece_counter: int = 0
var _materials: Dictionary = {}
var _selected_material: StandardMaterial3D
var _updating_inspector: bool = false
var _inspector_spinboxes: Dictionary = {}
var _pending_pick_position: Vector2 = Vector2.INF

enum TransformMode { MOVE, ROTATE, SCALE }

var _transform_mode: int = TransformMode.MOVE
var _snap_enabled: bool = true
var _move_snap: float = DEFAULT_MOVE_SNAP
var _rotate_snap: float = DEFAULT_ROTATE_SNAP
var _scale_snap: float = DEFAULT_SCALE_SNAP
var _dragging_transform: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_position: Vector3 = Vector3.ZERO
var _drag_start_rotation: Vector3 = Vector3.ZERO
var _drag_start_scale: Vector3 = Vector3.ONE
var _drag_start_plane_point: Vector3 = Vector3.ZERO
var _gizmo_root: Node3D
var _mode_label: Label
var _snap_button: CheckButton
var _shape_generator_box: VBoxContainer
var _visual_box: VBoxContainer
var _shape_type_option: OptionButton
var _shape_width_spinbox: SpinBox
var _shape_length_spinbox: SpinBox
var _shape_height_spinbox: SpinBox
var _shape_segments_spinbox: SpinBox
var _shape_radius_spinbox: SpinBox
var _visual_preset_option: OptionButton
var _visual_sun_spinbox: SpinBox
var _visual_ambient_spinbox: SpinBox
var _visual_shadows_button: CheckButton
var _custom_level_option: OptionButton
var _custom_level_paths: Array[String] = []
var _validation_label: Label
var _editor_world_environment: WorldEnvironment
var _grid_mesh_instance: MeshInstance3D
var _file_path_edit: LineEdit
var _reveal_export_folder_button: Button
var _movement_preview_root: Node3D
var _geometry_overlay_root: Node3D
var _inspector_scroll: ScrollContainer
var _palette_scroll: ScrollContainer
var _geometry_mode: bool = false
var _selected_vertex_index: int = -1
var _selected_face_index: int = 0
var _geometry_undo_stack: Array[Dictionary] = []
var _geometry_mode_button: CheckButton
var _geometry_convert_button: Button
var _geometry_vertex_label: Label
var _geometry_face_option: OptionButton
var _geometry_material_option: OptionButton
var _geometry_detail_controls: Array[Control] = []
var _movement_type_option: OptionButton
var _movement_length_spinbox: SpinBox
var _movement_t0_spinbox: SpinBox
var _movement_offset_spinboxes: Array[SpinBox] = []
var _movement_axis_spinboxes: Array[SpinBox] = []
var _movement_theta0_spinbox: SpinBox
var _movement_theta1_spinbox: SpinBox
var _movement_transition_spinbox: SpinBox
var _movement_offset_label: Label
var _movement_axis_label: Label
var _movement_angle_a_label: Label
var _movement_angle_b_label: Label
var _movement_transition_label: Label
var _duplicate_button: Button
var _delete_button: Button
var _current_file_path: String = DEFAULT_EDITOR_SAVE_PATH
var _dirty: bool = false
var _loading_level: bool = false

func _ready() -> void:
    var backdrop: Node = get_node_or_null("/root/MenuBackdrop")
    if backdrop != null and backdrop.has_method("hide_for_game"):
        backdrop.call("hide_for_game")
    _ui_root.theme = MenuThemeBuilder.build()
    _pieces_root = Node3D.new()
    _pieces_root.name = "EditorPieces"
    add_child(_pieces_root)
    _gizmo_root = Node3D.new()
    _gizmo_root.name = "TransformGizmo"
    add_child(_gizmo_root)
    _movement_preview_root = Node3D.new()
    _movement_preview_root.name = "MovementPreview"
    add_child(_movement_preview_root)
    _geometry_overlay_root = Node3D.new()
    _geometry_overlay_root.name = "GeometryOverlay"
    add_child(_geometry_overlay_root)
    _build_materials()
    _build_grid_reference()
    _build_editor_world_environment()
    _wire_top_bar()
    _wrap_palette_in_scroll()
    _wire_palette_buttons()
    _build_transform_toolbar()
    _wrap_inspector_in_scroll()
    _build_inspector_controls()
    _set_dirty(false)
    _set_status("Ready. Click Play to test.")
    _apply_camera_transform()

func _process(delta: float) -> void:
    _update_keyboard_camera(delta)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mouse_event: InputEventMouseButton = event
        if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
            if _handle_palette_click(mouse_event.position):
                get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
    if _pending_pick_position != Vector2.INF:
        var pick_position: Vector2 = _pending_pick_position
        _pending_pick_position = Vector2.INF
        _pick_piece_at(pick_position)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var key_event: InputEventKey = event
        if key_event.pressed and not key_event.echo:
            if key_event.keycode == KEY_W:
                _set_transform_mode(TransformMode.MOVE)
            elif key_event.keycode == KEY_E:
                _set_transform_mode(TransformMode.ROTATE)
            elif key_event.keycode == KEY_R:
                _set_transform_mode(TransformMode.SCALE)
            elif key_event.keycode == KEY_G:
                _set_snap_enabled(not _snap_enabled)
            elif key_event.keycode == KEY_DELETE or key_event.keycode == KEY_BACKSPACE:
                _delete_selected_piece()
            elif key_event.keycode == KEY_PAGEUP:
                _nudge_selected_piece_height(1.0)
            elif key_event.keycode == KEY_PAGEDOWN:
                _nudge_selected_piece_height(-1.0)
            elif key_event.keycode == KEY_Z and key_event.ctrl_pressed:
                _undo_geometry_edit()
            elif key_event.keycode == KEY_D and key_event.ctrl_pressed:
                _duplicate_selected_piece()
        return

    if event is InputEventMouseButton:
        var mouse_event: InputEventMouseButton = event
        if _is_pointer_over_editor_panel(mouse_event.position):
            return
        match mouse_event.button_index:
            MOUSE_BUTTON_LEFT:
                if mouse_event.pressed:
                    _begin_viewport_transform_or_pick(mouse_event.position)
                else:
                    _end_viewport_transform()
            MOUSE_BUTTON_RIGHT:
                _orbiting = mouse_event.pressed
            MOUSE_BUTTON_MIDDLE:
                _panning = mouse_event.pressed
            MOUSE_BUTTON_WHEEL_UP:
                if mouse_event.pressed:
                    _distance = maxf(DISTANCE_MIN, _distance * ZOOM_STEP)
                    _apply_camera_transform()
            MOUSE_BUTTON_WHEEL_DOWN:
                if mouse_event.pressed:
                    _distance = minf(DISTANCE_MAX, _distance / ZOOM_STEP)
                    _apply_camera_transform()
    elif event is InputEventMouseMotion:
        var motion_event: InputEventMouseMotion = event
        if _orbiting:
            _yaw -= motion_event.relative.x * ORBIT_SENSITIVITY
            _pitch = clampf(_pitch - motion_event.relative.y * ORBIT_SENSITIVITY, PITCH_MIN, PITCH_MAX)
            _apply_camera_transform()
        elif _panning:
            _pan_camera(motion_event.relative)
        elif _dragging_transform:
            _update_viewport_transform(motion_event.position, motion_event.relative)

func _wire_top_bar() -> void:
    _new_button.pressed.connect(_new_level)
    _load_button.pressed.connect(_load_golfedit)
    _save_button.pressed.connect(_save_golfedit)
    _export_button.pressed.connect(_export_level)
    _play_test_button.pressed.connect(_play_test_exported_level)
    _back_button.pressed.connect(_on_back_pressed)

    _file_path_edit = LineEdit.new()
    _file_path_edit.name = "FilePathEdit"
    _file_path_edit.text = _current_file_path
    _file_path_edit.placeholder_text = "user://custom_level.golfedit"
    _file_path_edit.custom_minimum_size = Vector2(110, 36)
    _file_path_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    _file_path_edit.text_submitted.connect(_on_file_path_submitted)
    _file_path_edit.focus_exited.connect(_on_file_path_focus_exited)

    _reveal_export_folder_button = Button.new()
    _reveal_export_folder_button.name = "RevealExportFolderButton"
    _reveal_export_folder_button.text = "Dir"
    _reveal_export_folder_button.tooltip_text = "Open the folder that contains the current .golfedit/.level export. user:// files are outside the project folder."
    _reveal_export_folder_button.pressed.connect(Callable(self, "_reveal_current_file_folder"))

    var top_spacer: Control = $UI/Root/TopBar/TopSpacer
    var top_bar: HBoxContainer = $UI/Root/TopBar
    top_bar.add_child(_file_path_edit)
    top_bar.move_child(_file_path_edit, top_spacer.get_index() + 1)
    top_bar.add_child(_reveal_export_folder_button)
    top_bar.move_child(_reveal_export_folder_button, _file_path_edit.get_index() + 1)

func _build_transform_toolbar() -> void:
    var height_hint: Label = Label.new()
    height_hint.name = "HeightHint"
    height_hint.text = "Height: Shift+drag or PgUp/PgDn"
    height_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    height_hint.add_theme_font_size_override("font_size", 12)
    _palette_box.add_child(height_hint)

    var toolbar: HBoxContainer = HBoxContainer.new()
    toolbar.name = "TransformToolbar"
    toolbar.add_theme_constant_override("separation", 6)
    _palette_box.add_child(toolbar)

    var move_button: Button = Button.new()
    move_button.text = "W Move"
    move_button.pressed.connect(_set_transform_mode.bind(TransformMode.MOVE))
    toolbar.add_child(move_button)

    var rotate_button: Button = Button.new()
    rotate_button.text = "E Rotate"
    rotate_button.pressed.connect(_set_transform_mode.bind(TransformMode.ROTATE))
    toolbar.add_child(rotate_button)

    var scale_button: Button = Button.new()
    scale_button.text = "R Scale"
    scale_button.pressed.connect(_set_transform_mode.bind(TransformMode.SCALE))
    toolbar.add_child(scale_button)

    _snap_button = CheckButton.new()
    _snap_button.name = "SnapButton"
    _snap_button.text = "Snap"
    _snap_button.button_pressed = _snap_enabled
    _snap_button.toggled.connect(_set_snap_enabled)
    _palette_box.add_child(_snap_button)

    _mode_label = Label.new()
    _mode_label.name = "ModeLabel"
    _mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _palette_box.add_child(_mode_label)
    _refresh_mode_label()

func _wire_palette_buttons() -> void:
    _connect_palette_button("PlatformButton", "platform")
    _connect_palette_button("RampButton", "ramp")
    _connect_palette_button("WallButton", "wall")
    _connect_palette_button("WaterButton", "water")
    _connect_palette_button("BallStartButton", "ball_start")
    _connect_palette_button("HoleButton", "hole")

    var prop_button: Button = Button.new()
    prop_button.name = "PropButton"
    prop_button.text = "Prop Marker"
    prop_button.pressed.connect(_add_piece.bind("prop"))
    _palette_box.add_child(prop_button)

    var hint: Label = _palette_box.get_node_or_null("Hint") as Label
    if hint != null:
        hint.visible = false
    _build_shape_generator_palette()
    _build_visual_palette()
    _build_custom_levels_palette()
    _build_validation_palette()

func _build_validation_palette() -> void:
    var box: VBoxContainer = VBoxContainer.new()
    box.name = "ValidationTools"
    box.add_theme_constant_override("separation", 6)
    _palette_box.add_child(box)
    var title_node: Node = _palette_box.get_node_or_null("PaletteTitle")
    if title_node != null:
        _palette_box.move_child(box, title_node.get_index() + 1)

    var title: Label = Label.new()
    title.text = "Validation"
    title.add_theme_font_size_override("font_size", 16)
    box.add_child(title)

    var validate_button: Button = Button.new()
    validate_button.text = "Validate Level"
    validate_button.tooltip_text = "Check whether this custom level is ready to save/export/playtest."
    validate_button.pressed.connect(_validate_level_for_user)
    box.add_child(validate_button)

    _validation_label = Label.new()
    _validation_label.text = "No validation run yet."
    _validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _validation_label.add_theme_font_size_override("font_size", 12)
    box.add_child(_validation_label)

func _build_custom_levels_palette() -> void:
    var box: VBoxContainer = VBoxContainer.new()
    box.name = "CustomLevelTools"
    box.add_theme_constant_override("separation", 6)
    _palette_box.add_child(box)
    var title_node: Node = _palette_box.get_node_or_null("PaletteTitle")
    if title_node != null:
        _palette_box.move_child(box, title_node.get_index() + 1)

    var title: Label = Label.new()
    title.text = "Custom Levels"
    title.add_theme_font_size_override("font_size", 16)
    box.add_child(title)

    _custom_level_option = OptionButton.new()
    box.add_child(_custom_level_option)

    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    box.add_child(row)

    var refresh_button: Button = Button.new()
    refresh_button.text = "Refresh"
    refresh_button.pressed.connect(_refresh_custom_level_list)
    row.add_child(refresh_button)

    var load_button: Button = Button.new()
    load_button.text = "Load Selected"
    load_button.pressed.connect(_load_selected_custom_level)
    row.add_child(load_button)

    _refresh_custom_level_list()

func _build_visual_palette() -> void:
    _visual_box = VBoxContainer.new()
    _visual_box.name = "VisualSettings"
    _visual_box.add_theme_constant_override("separation", 6)
    _palette_box.add_child(_visual_box)
    var title_node: Node = _palette_box.get_node_or_null("PaletteTitle")
    if title_node != null:
        _palette_box.move_child(_visual_box, title_node.get_index() + 1)

    var title: Label = Label.new()
    title.text = "Lighting / Visuals"
    title.add_theme_font_size_override("font_size", 16)
    _visual_box.add_child(title)

    _visual_preset_option = OptionButton.new()
    for i: int in range(VISUAL_PRESET_LABELS.size()):
        _visual_preset_option.add_item(VISUAL_PRESET_LABELS[i], i)
    _visual_preset_option.item_selected.connect(_on_visual_preset_selected)
    _visual_box.add_child(_visual_preset_option)

    _visual_sun_spinbox = _add_palette_spinbox_to(_visual_box, "Sun", 0.0, 4.0, 0.1, 1.0)
    _visual_sun_spinbox.value_changed.connect(_on_visual_value_changed.bind("sun"))
    _visual_ambient_spinbox = _add_palette_spinbox_to(_visual_box, "Ambient", 0.0, 4.0, 0.1, 1.0)
    _visual_ambient_spinbox.value_changed.connect(_on_visual_value_changed.bind("ambient"))
    _visual_shadows_button = CheckButton.new()
    _visual_shadows_button.text = "Realtime Shadows"
    _visual_shadows_button.button_pressed = true
    _visual_shadows_button.toggled.connect(_on_visual_shadows_toggled)
    _visual_box.add_child(_visual_shadows_button)

    var note: Label = Label.new()
    note.text = "No bake required: simple realtime sky/sun."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.add_theme_font_size_override("font_size", 12)
    _visual_box.add_child(note)

func _build_shape_generator_palette() -> void:
    _shape_generator_box = VBoxContainer.new()
    _shape_generator_box.name = "ShapeGenerator"
    _shape_generator_box.add_theme_constant_override("separation", 6)
    _palette_box.add_child(_shape_generator_box)
    var title_node: Node = _palette_box.get_node_or_null("PaletteTitle")
    if title_node != null:
        _palette_box.move_child(_shape_generator_box, title_node.get_index() + 1)

    var title: Label = Label.new()
    title.text = "Procedural Shapes"
    title.add_theme_font_size_override("font_size", 16)
    _shape_generator_box.add_child(title)

    _shape_type_option = OptionButton.new()
    for i: int in range(SHAPE_LABELS.size()):
        _shape_type_option.add_item(SHAPE_LABELS[i], i)
    _shape_generator_box.add_child(_shape_type_option)

    var generate_button: Button = Button.new()
    generate_button.text = "Generate Shape"
    generate_button.tooltip_text = "Creates editable geometry from the selected procedural shape using the parameters below."
    generate_button.pressed.connect(_generate_procedural_shape)
    _shape_generator_box.add_child(generate_button)

    _shape_width_spinbox = _add_palette_spinbox_to(_shape_generator_box, "Width", 1.0, 20.0, 0.25, 4.0)
    _shape_length_spinbox = _add_palette_spinbox_to(_shape_generator_box, "Length", 1.0, 30.0, 0.25, 6.0)
    _shape_height_spinbox = _add_palette_spinbox_to(_shape_generator_box, "Height", -10.0, 10.0, 0.25, 2.0)
    _shape_segments_spinbox = _add_palette_spinbox_to(_shape_generator_box, "Segments", 3.0, 32.0, 1.0, 8.0)
    _shape_radius_spinbox = _add_palette_spinbox_to(_shape_generator_box, "Radius", 0.5, 12.0, 0.25, 2.0)

func _add_palette_spinbox(label_text: String, min_value: float, max_value: float, step: float, default_value: float) -> SpinBox:
    return _add_palette_spinbox_to(_palette_box, label_text, min_value, max_value, step, default_value)

func _add_palette_spinbox_to(parent: Container, label_text: String, min_value: float, max_value: float, step: float, default_value: float) -> SpinBox:
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    parent.add_child(row)
    var label: Label = Label.new()
    label.text = label_text
    label.custom_minimum_size = Vector2(70, 0)
    row.add_child(label)
    var spinbox: SpinBox = SpinBox.new()
    spinbox.min_value = min_value
    spinbox.max_value = max_value
    spinbox.step = step
    spinbox.value = default_value
    spinbox.allow_greater = true
    spinbox.allow_lesser = true
    spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(spinbox)
    return spinbox

func _connect_palette_button(button_name: String, _piece_type: String) -> void:
    var button: Button = _palette_box.get_node(button_name) as Button
    button.disabled = false

func _set_transform_mode(mode: int) -> void:
    _transform_mode = mode
    _refresh_mode_label()
    _update_gizmo_visual()
    _set_status("Transform mode: %s." % _transform_mode_name())

func _set_snap_enabled(enabled: bool) -> void:
    _snap_enabled = enabled
    if _snap_button != null:
        _snap_button.set_pressed_no_signal(_snap_enabled)
    _refresh_mode_label()
    _set_status("Snapping %s." % ("enabled" if _snap_enabled else "disabled"))

func _refresh_mode_label() -> void:
    if _mode_label == null:
        return
    _mode_label.text = "Mode: %s\nSnap: %s\nDrag moves X/Z" % [
        _transform_mode_name(),
        "ON" if _snap_enabled else "OFF",
    ]
    _mode_label.tooltip_text = "Move snap %.2f, rotate snap %.1f°, scale snap %.2f" % [_move_snap, _rotate_snap, _scale_snap]

func _transform_mode_name() -> String:
    match _transform_mode:
        TransformMode.MOVE:
            return "Move"
        TransformMode.ROTATE:
            return "Rotate"
        TransformMode.SCALE:
            return "Scale"
    return "Unknown"

func _handle_palette_click(screen_position: Vector2) -> bool:
    var button_to_type: Dictionary = {
        "PlatformButton": "platform",
        "RampButton": "ramp",
        "WallButton": "wall",
        "WaterButton": "water",
        "BallStartButton": "ball_start",
        "HoleButton": "hole",
        "PropButton": "prop",
    }
    for button_name: String in button_to_type.keys():
        var button: Button = _palette_box.get_node_or_null(button_name) as Button
        if button != null and not button.disabled and button.get_global_rect().has_point(screen_position):
            _add_piece(button_to_type[button_name] as String)
            return true
    return false

func _on_platform_button_pressed() -> void:
    _add_piece("platform")

func _on_ramp_button_pressed() -> void:
    _add_piece("ramp")

func _on_wall_button_pressed() -> void:
    _add_piece("wall")

func _on_water_button_pressed() -> void:
    _add_piece("water")

func _on_ball_start_button_pressed() -> void:
    _add_piece("ball_start")

func _on_hole_button_pressed() -> void:
    _add_piece("hole")

func _build_materials() -> void:
    _materials["platform"] = _make_material(Color(0.25, 0.72, 0.28, 1.0))
    _materials["ramp"] = _make_material(Color(0.35, 0.62, 0.26, 1.0))
    _materials["wall"] = _make_material(Color(0.55, 0.34, 0.18, 1.0))
    _materials["water"] = _make_material(Color(0.08, 0.32, 0.95, 0.68), true)
    _materials["ball_start"] = _make_material(Color(0.95, 0.95, 0.95, 1.0))
    _materials["hole"] = _make_material(Color(0.02, 0.02, 0.025, 1.0))
    _materials["prop"] = _make_material(Color(0.25, 0.75, 0.55, 1.0))
    _selected_material = _make_material(Color(1.0, 0.82, 0.18, 1.0))
    _selected_material.emission_enabled = true
    _selected_material.emission = Color(1.0, 0.65, 0.05, 1.0)

func _make_material(color: Color, transparent: bool = false) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.9
    if transparent:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return material

func _make_unshaded_material(color: Color) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    return material

func _build_editor_world_environment() -> void:
    _editor_world_environment = WorldEnvironment.new()
    _editor_world_environment.name = "EditorWorldEnvironment"
    var env: Environment = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.4, 0.6, 0.85)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.6, 0.6, 0.6)
    env.ambient_light_energy = 1.0
    _editor_world_environment.environment = env
    add_child(_editor_world_environment)

func _build_grid_reference() -> void:
    var vertices: PackedVector3Array = PackedVector3Array()
    for i: int in range(-GRID_HALF_EXTENTS, GRID_HALF_EXTENTS + 1):
        vertices.append(Vector3(i, 0.01, -GRID_HALF_EXTENTS))
        vertices.append(Vector3(i, 0.01, GRID_HALF_EXTENTS))
        vertices.append(Vector3(-GRID_HALF_EXTENTS, 0.01, i))
        vertices.append(Vector3(GRID_HALF_EXTENTS, 0.01, i))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
    _grid_mesh_instance = MeshInstance3D.new()
    _grid_mesh_instance.name = "GridReference"
    _grid_mesh_instance.mesh = mesh
    _grid_mesh_instance.material_override = _make_unshaded_material(Color(0.78, 0.92, 0.78, 0.42))
    add_child(_grid_mesh_instance)

func _wrap_palette_in_scroll() -> void:
    if _palette_box == null or _palette_scroll != null:
        return
    var margin: MarginContainer = _palette_box.get_parent() as MarginContainer
    if margin == null:
        return
    margin.remove_child(_palette_box)
    _palette_scroll = ScrollContainer.new()
    _palette_scroll.name = "PaletteScroll"
    _palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(_palette_scroll)
    _palette_scroll.add_child(_palette_box)
    _palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _palette_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

func _wrap_inspector_in_scroll() -> void:
    if _inspector_box == null or _inspector_scroll != null:
        return
    var margin: MarginContainer = _inspector_box.get_parent() as MarginContainer
    if margin == null:
        return
    margin.remove_child(_inspector_box)
    _inspector_scroll = ScrollContainer.new()
    _inspector_scroll.name = "InspectorScroll"
    _inspector_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(_inspector_scroll)
    _inspector_scroll.add_child(_inspector_box)
    _inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _inspector_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

func _build_inspector_controls() -> void:
    _position_label.visible = false
    _snap_label.visible = false

    _add_inspector_section("Position")
    _add_vector3_editor("position", -100.0, 100.0, 0.25)
    _add_inspector_section("Rotation Degrees")
    _add_vector3_editor("rotation", -360.0, 360.0, 1.0)
    _add_inspector_section("Scale / Size")
    _add_vector3_editor("scale", 0.05, 50.0, 0.25)

    _build_geometry_controls()
    _build_movement_controls()

    var actions: HBoxContainer = HBoxContainer.new()
    actions.add_theme_constant_override("separation", 8)
    _inspector_box.add_child(actions)

    _duplicate_button = Button.new()
    _duplicate_button.text = "Duplicate"
    _duplicate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _duplicate_button.pressed.connect(_duplicate_selected_piece)
    actions.add_child(_duplicate_button)

    _delete_button = Button.new()
    _delete_button.text = "Delete"
    _delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _delete_button.pressed.connect(_delete_selected_piece)
    actions.add_child(_delete_button)

    _refresh_inspector()

func _add_inspector_section(text: String) -> Label:
    var label: Label = Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 14)
    _inspector_box.add_child(label)
    return label

func _add_vector3_editor(property_name: String, min_value: float, max_value: float, step: float) -> void:
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    _inspector_box.add_child(row)
    for axis: int in range(3):
        var spinbox: SpinBox = SpinBox.new()
        spinbox.min_value = min_value
        spinbox.max_value = max_value
        spinbox.step = step
        spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        spinbox.allow_greater = true
        spinbox.allow_lesser = true
        spinbox.prefix = ["X ", "Y ", "Z "][axis]
        spinbox.value_changed.connect(_on_transform_spinbox_changed.bind(property_name, axis))
        row.add_child(spinbox)
        _inspector_spinboxes["%s_%d" % [property_name, axis]] = spinbox

func _build_geometry_controls() -> void:
    _add_inspector_section("Geometry")
    var geometry_hint: Label = Label.new()
    geometry_hint.text = "Workflow: select surface → Convert Selected → Geometry Mode → choose vertex or face. Scroll this panel for all controls."
    geometry_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    geometry_hint.add_theme_font_size_override("font_size", 12)
    _inspector_box.add_child(geometry_hint)
    _geometry_mode_button = CheckButton.new()
    _geometry_mode_button.text = "Geometry Mode"
    _geometry_mode_button.tooltip_text = "Edit individual vertices on converted platform/ramp/wall/water pieces."
    _geometry_mode_button.toggled.connect(_set_geometry_mode)
    _inspector_box.add_child(_geometry_mode_button)

    _geometry_convert_button = Button.new()
    _geometry_convert_button.text = "Convert Selected"
    _geometry_convert_button.tooltip_text = "Convert this piece to editable vertices."
    _geometry_convert_button.pressed.connect(_convert_selected_to_geometry)
    _inspector_box.add_child(_geometry_convert_button)

    var vertex_row: HBoxContainer = HBoxContainer.new()
    vertex_row.add_theme_constant_override("separation", 4)
    _inspector_box.add_child(vertex_row)
    _geometry_detail_controls.append(vertex_row)
    var prev_vertex: Button = Button.new()
    prev_vertex.text = "◀ V"
    prev_vertex.pressed.connect(_select_relative_vertex.bind(-1))
    vertex_row.add_child(prev_vertex)
    var next_vertex: Button = Button.new()
    next_vertex.text = "V ▶"
    next_vertex.pressed.connect(_select_relative_vertex.bind(1))
    vertex_row.add_child(next_vertex)
    _geometry_vertex_label = Label.new()
    _geometry_vertex_label.text = "Vertex: --"
    _geometry_vertex_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vertex_row.add_child(_geometry_vertex_label)

    var nudge_row: HBoxContainer = HBoxContainer.new()
    nudge_row.add_theme_constant_override("separation", 3)
    _inspector_box.add_child(nudge_row)
    _geometry_detail_controls.append(nudge_row)
    var labels: Array[String] = ["X-", "X+", "Y-", "Y+", "Z-", "Z+"]
    var deltas: Array[Vector3] = [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK]
    for i: int in range(labels.size()):
        var button: Button = Button.new()
        button.text = labels[i]
        button.pressed.connect(_nudge_selected_vertex.bind(deltas[i]))
        nudge_row.add_child(button)

    var face_row: HBoxContainer = HBoxContainer.new()
    face_row.add_theme_constant_override("separation", 4)
    _inspector_box.add_child(face_row)
    _geometry_detail_controls.append(face_row)
    _geometry_face_option = OptionButton.new()
    for i: int in range(GEO_FACE_NAMES.size()):
        _geometry_face_option.add_item(GEO_FACE_NAMES[i], i)
    _geometry_face_option.item_selected.connect(_on_geometry_face_selected)
    face_row.add_child(_geometry_face_option)
    _geometry_material_option = OptionButton.new()
    for i: int in range(GEO_FACE_MATERIALS.size()):
        _geometry_material_option.add_item(GEO_FACE_MATERIALS[i], i)
    _geometry_material_option.item_selected.connect(_on_geometry_material_selected)
    face_row.add_child(_geometry_material_option)

    var undo_row: HBoxContainer = HBoxContainer.new()
    undo_row.add_theme_constant_override("separation", 4)
    _inspector_box.add_child(undo_row)
    _geometry_detail_controls.append(undo_row)
    var undo_button: Button = Button.new()
    undo_button.text = "Undo Geo"
    undo_button.pressed.connect(_undo_geometry_edit)
    undo_row.add_child(undo_button)

func _build_movement_controls() -> void:
    _add_inspector_section("Movement")
    _movement_type_option = OptionButton.new()
    _movement_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for i: int in range(MOVEMENT_LABELS.size()):
        _movement_type_option.add_item(MOVEMENT_LABELS[i], i)
    _movement_type_option.item_selected.connect(_on_movement_type_selected)
    _inspector_box.add_child(_movement_type_option)

    _movement_length_spinbox = _add_named_spinbox("Length", 0.1, 60.0, 0.25, 4.0, _on_movement_number_changed.bind("length"))
    _movement_t0_spinbox = _add_named_spinbox("Start", 0.0, 60.0, 0.25, 0.0, _on_movement_number_changed.bind("t0"))
    _movement_offset_label = _add_inspector_section("Linear Offset")
    _movement_offset_spinboxes = _add_movement_vector3_editor("offset", -50.0, 50.0, 0.25)
    _movement_axis_label = _add_inspector_section("Axis")
    _movement_axis_spinboxes = _add_movement_vector3_editor("axis", -1.0, 1.0, 0.1)
    _movement_theta0_spinbox = _add_named_spinbox("Angle A", -360.0, 360.0, 5.0, 25.0, _on_movement_number_changed.bind("theta0"))
    _movement_angle_a_label = _movement_theta0_spinbox.get_parent().get_child(0) as Label
    _movement_theta1_spinbox = _add_named_spinbox("Angle B", -360.0, 360.0, 5.0, -25.0, _on_movement_number_changed.bind("theta1"))
    _movement_angle_b_label = _movement_theta1_spinbox.get_parent().get_child(0) as Label
    _movement_transition_spinbox = _add_named_spinbox("Transition", 0.0, 30.0, 0.25, 0.5, _on_movement_number_changed.bind("transition"))
    _movement_transition_label = _movement_transition_spinbox.get_parent().get_child(0) as Label

func _add_named_spinbox(label_text: String, min_value: float, max_value: float, step: float, default_value: float, callback: Callable) -> SpinBox:
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    _inspector_box.add_child(row)
    var label: Label = Label.new()
    label.text = label_text
    label.custom_minimum_size = Vector2(78, 0)
    row.add_child(label)
    var spinbox: SpinBox = SpinBox.new()
    spinbox.min_value = min_value
    spinbox.max_value = max_value
    spinbox.step = step
    spinbox.value = default_value
    spinbox.allow_greater = true
    spinbox.allow_lesser = true
    spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    spinbox.value_changed.connect(callback)
    row.add_child(spinbox)
    return spinbox

func _add_movement_vector3_editor(property_name: String, min_value: float, max_value: float, step: float) -> Array[SpinBox]:
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    _inspector_box.add_child(row)
    var spinboxes: Array[SpinBox] = []
    for axis: int in range(3):
        var spinbox: SpinBox = SpinBox.new()
        spinbox.min_value = min_value
        spinbox.max_value = max_value
        spinbox.step = step
        spinbox.allow_greater = true
        spinbox.allow_lesser = true
        spinbox.prefix = ["X ", "Y ", "Z "][axis]
        spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        spinbox.value_changed.connect(_on_movement_vector_changed.bind(property_name, axis))
        row.add_child(spinbox)
        spinboxes.append(spinbox)
    return spinboxes

func _add_piece(piece_type: String) -> Node3D:
    _piece_counter += 1
    var piece: Node3D = Node3D.new()
    piece.name = "%s_%02d" % [_piece_display_name(piece_type).replace(" ", ""), _piece_counter]
    piece.set_meta("piece_type", piece_type)
    piece.set_meta("base_material", _materials[piece_type])
    piece.set_meta("movement", _default_movement_data())
    piece.position = _suggest_piece_position()
    piece.scale = _default_scale(piece_type)
    piece.rotation_degrees = _default_rotation_degrees(piece_type)

    var mesh_instance: MeshInstance3D = MeshInstance3D.new()
    mesh_instance.name = "Preview"
    mesh_instance.mesh = _mesh_for_piece(piece_type)
    mesh_instance.material_override = _materials[piece_type]
    piece.add_child(mesh_instance)

    var area: Area3D = Area3D.new()
    area.name = "PickArea"
    area.collision_layer = PIECE_COLLISION_LAYER
    area.collision_mask = 0
    area.set_meta("piece", piece)
    piece.add_child(area)

    var collision_shape: CollisionShape3D = CollisionShape3D.new()
    collision_shape.name = "CollisionShape3D"
    collision_shape.shape = _collision_shape_for_piece(piece_type)
    area.add_child(collision_shape)

    _pieces_root.add_child(piece)
    _select_piece(piece)
    if not _loading_level:
        _set_dirty(true)
        _set_status("Added %s. Use the Inspector to move, rotate, or scale it." % _piece_display_name(piece_type))
    return piece

func _mesh_for_piece(piece_type: String) -> Mesh:
    match piece_type:
        "ball_start":
            var sphere: SphereMesh = SphereMesh.new()
            sphere.radius = 0.5
            sphere.height = 1.0
            return sphere
        "hole":
            var cylinder: CylinderMesh = CylinderMesh.new()
            cylinder.top_radius = 0.5
            cylinder.bottom_radius = 0.5
            cylinder.height = 1.0
            return cylinder
        "prop":
            var prop_sphere: SphereMesh = SphereMesh.new()
            prop_sphere.radius = 0.5
            prop_sphere.height = 1.0
            return prop_sphere
        _:
            var box: BoxMesh = BoxMesh.new()
            box.size = Vector3.ONE
            return box

func _collision_shape_for_piece(piece_type: String) -> Shape3D:
    match piece_type:
        "ball_start", "prop":
            var sphere_shape: SphereShape3D = SphereShape3D.new()
            sphere_shape.radius = 0.55
            return sphere_shape
        "hole":
            var cylinder_shape: CylinderShape3D = CylinderShape3D.new()
            cylinder_shape.radius = 0.55
            cylinder_shape.height = 1.0
            return cylinder_shape
        _:
            var box_shape: BoxShape3D = BoxShape3D.new()
            box_shape.size = Vector3.ONE
            return box_shape

func _default_scale(piece_type: String) -> Vector3:
    match piece_type:
        "platform":
            return Vector3(4.0, 0.25, 4.0)
        "ramp":
            return Vector3(4.0, 0.25, 4.0)
        "wall":
            return Vector3(4.0, 1.0, 0.25)
        "water":
            return Vector3(4.0, 0.05, 4.0)
        "ball_start":
            return Vector3(0.28, 0.28, 0.28)
        "hole":
            return Vector3(0.55, 0.08, 0.55)
        "prop":
            return Vector3(0.7, 0.7, 0.7)
    return Vector3.ONE

func _default_rotation_degrees(piece_type: String) -> Vector3:
    if piece_type == "ramp":
        return Vector3(-12.0, 0.0, 0.0)
    return Vector3.ZERO

func _suggest_piece_position() -> Vector3:
    var pos: Vector3 = _focus_position
    pos.y = 0.5
    var row_index: int = floori(float(_pieces_root.get_child_count()) / 4.0)
    return pos + Vector3(_pieces_root.get_child_count() % 4, 0.0, row_index)

func _piece_display_name(piece_type: String) -> String:
    match piece_type:
        "ball_start":
            return "Ball Start"
        "platform":
            return "Platform"
        "ramp":
            return "Ramp"
        "wall":
            return "Wall"
        "water":
            return "Water"
        "hole":
            return "Hole"
        "prop":
            return "Prop Marker"
    return piece_type.capitalize()

func _default_movement_data() -> Dictionary:
    return {
        "type": "none",
        "length": 4.0,
        "t0": 0.0,
        "offset": [2.0, 0.0, 0.0],
        "axis": [0.0, 1.0, 0.0],
        "theta0": 25.0,
        "theta1": -25.0,
        "transition": 0.5,
    }

func _movement_data(piece: Node3D) -> Dictionary:
    var data: Variant = piece.get_meta("movement", _default_movement_data())
    if typeof(data) != TYPE_DICTIONARY:
        return _default_movement_data()
    return _normalized_movement_data(data as Dictionary)

func _refresh_custom_level_list() -> void:
    if _custom_level_option == null:
        return
    _custom_level_option.clear()
    _custom_level_paths.clear()
    var dir: DirAccess = DirAccess.open("user://")
    if dir == null:
        _custom_level_option.add_item("No user folder", 0)
        return
    dir.list_dir_begin()
    var file_name: String = dir.get_next()
    while not file_name.is_empty():
        if not dir.current_is_dir() and file_name.ends_with(".golfedit"):
            var path: String = "user://" + file_name
            _custom_level_paths.append(path)
            _custom_level_option.add_item(file_name.trim_suffix(".golfedit"), _custom_level_paths.size() - 1)
        file_name = dir.get_next()
    dir.list_dir_end()
    if _custom_level_paths.is_empty():
        _custom_level_option.add_item("No .golfedit saves", 0)

func _load_selected_custom_level() -> void:
    if _custom_level_option == null or _custom_level_paths.is_empty():
        _set_status("No custom .golfedit saves found in user://.")
        return
    var index: int = clampi(_custom_level_option.selected, 0, _custom_level_paths.size() - 1)
    _set_current_file_path(_custom_level_paths[index])
    _load_golfedit()

func _validate_level_for_user() -> void:
    var report: Dictionary = _validation_report()
    var lines: Array[String] = []
    lines.append("✓ One Ball Start" if report["ball_start_ok"] else "✗ Need exactly one Ball Start")
    lines.append("✓ Hole present" if report["hole_ok"] else "✗ Need exactly one Hole")
    lines.append("✓ Playable surface present" if report["surface_ok"] else "✗ Add at least one platform/ramp/wall/water surface")
    lines.append("✓ Spawn appears above a surface" if report["spawn_ok"] else "⚠ Spawn may not be over a surface")
    lines.append("✓ Hole is within testable range" if report["reach_ok"] else "⚠ Hole is very far from spawn")
    var ok: bool = bool(report["export_ok"])
    var text: String = "Validation passed." if ok else "Validation needs attention."
    if _validation_label != null:
        _validation_label.text = text + "\n" + "\n".join(lines)
    _set_status(text)

func _validation_report() -> Dictionary:
    var ball_starts: Array[Node3D] = []
    var holes: Array[Node3D] = []
    var surfaces: Array[Node3D] = []
    for child: Node in _pieces_root.get_children():
        var piece: Node3D = child as Node3D
        if piece == null:
            continue
        var piece_type: String = piece.get_meta("piece_type", "") as String
        match piece_type:
            "ball_start":
                ball_starts.append(piece)
            "hole":
                holes.append(piece)
            "platform", "ramp", "wall", "water":
                surfaces.append(piece)
    var spawn_ok: bool = false
    if ball_starts.size() == 1:
        spawn_ok = _point_has_surface_below(ball_starts[0].position, surfaces)
    var reach_ok: bool = false
    if ball_starts.size() == 1 and holes.size() == 1:
        reach_ok = ball_starts[0].position.distance_to(holes[0].position) <= 80.0
    var export_ok: bool = ball_starts.size() == 1 and holes.size() == 1 and not surfaces.is_empty()
    return {
        "ball_start_ok": ball_starts.size() == 1,
        "hole_ok": holes.size() == 1,
        "surface_ok": not surfaces.is_empty(),
        "spawn_ok": spawn_ok,
        "reach_ok": reach_ok,
        "export_ok": export_ok,
    }

func _point_has_surface_below(point: Vector3, surfaces: Array[Node3D]) -> bool:
    for surface: Node3D in surfaces:
        var min_x: float = surface.position.x - absf(surface.scale.x) * 0.5 - 0.5
        var max_x: float = surface.position.x + absf(surface.scale.x) * 0.5 + 0.5
        var min_z: float = surface.position.z - absf(surface.scale.z) * 0.5 - 0.5
        var max_z: float = surface.position.z + absf(surface.scale.z) * 0.5 + 0.5
        var top_y: float = surface.position.y + absf(surface.scale.y) * 0.5
        if point.x >= min_x and point.x <= max_x and point.z >= min_z and point.z <= max_z and point.y >= top_y - 0.25:
            return true
    return false

func _set_geometry_mode(enabled: bool) -> void:
    _geometry_mode = enabled
    if _geometry_mode_button != null:
        _geometry_mode_button.set_pressed_no_signal(enabled)
    if enabled and _selected_piece != null and not _has_custom_geometry(_selected_piece):
        _set_status("Geometry mode on. Convert selected piece to edit vertices.")
    elif enabled:
        _set_status("Geometry mode on. Select/nudge vertices.")
    else:
        _selected_vertex_index = -1
        _set_status("Builder mode on.")
    _update_geometry_overlay()
    _refresh_geometry_ui()

func _has_custom_geometry(piece: Node3D) -> bool:
    return piece != null and piece.has_meta("custom_geo_points")

func _convert_selected_to_geometry() -> void:
    if _selected_piece == null or not is_instance_valid(_selected_piece):
        _set_status("Select a platform/ramp/wall/water piece first.")
        return
    var piece_type: String = _selected_piece.get_meta("piece_type", "") as String
    if not ["platform", "ramp", "wall", "water"].has(piece_type):
        _set_status("Only surface pieces can be converted to editable geometry.")
        return
    _push_geometry_undo(_selected_piece)
    if not _has_custom_geometry(_selected_piece):
        _selected_piece.set_meta("custom_geo_points", _default_geo_points_for_piece(_selected_piece))
        _selected_piece.set_meta("custom_geo_materials", _default_geo_materials(piece_type == "water"))
        _selected_piece.scale = Vector3.ONE
        _selected_piece.rotation_degrees = Vector3.ZERO
    _selected_vertex_index = 0
    _set_geometry_mode(true)
    _apply_custom_geometry_preview(_selected_piece)
    _refresh_inspector()
    _set_dirty(true)
    _set_status("Converted %s to editable geometry." % _selected_piece.name)

func _default_geo_points_for_piece(piece: Node3D) -> Array:
    var sx: float = maxf(absf(piece.scale.x), 0.05) * 0.5
    var sy: float = maxf(absf(piece.scale.y), 0.05) * 0.5
    var sz: float = maxf(absf(piece.scale.z), 0.05) * 0.5
    var local_points: Array[Vector3] = [
        Vector3(-sx, -sy, -sz), Vector3(sx, -sy, -sz), Vector3(sx, -sy, sz), Vector3(-sx, -sy, sz),
        Vector3(-sx, sy, -sz), Vector3(sx, sy, -sz), Vector3(sx, sy, sz), Vector3(-sx, sy, sz),
    ]
    var piece_basis: Basis = Basis.from_euler(Vector3(deg_to_rad(piece.rotation_degrees.x), deg_to_rad(piece.rotation_degrees.y), deg_to_rad(piece.rotation_degrees.z)))
    var points: Array = []
    for p: Vector3 in local_points:
        points.append(_vector3_to_array(piece_basis * p))
    return points

func _default_geo_materials(is_water: bool) -> Array:
    if is_water:
        return ["water", "water", "water", "water", "water", "water"]
    return ["ground", "wall-top", "wall-side", "wall-side", "wall-side", "wall-side"]

func _on_visual_preset_selected(_index: int) -> void:
    _apply_editor_visual_preview()
    _set_dirty(true)
    _set_status("Updated visual preset. No lightmap bake required.")

func _on_visual_value_changed(_value: float, _kind: String) -> void:
    _apply_editor_visual_preview()
    _set_dirty(true)

func _on_visual_shadows_toggled(_enabled: bool) -> void:
    _apply_editor_visual_preview()
    _set_dirty(true)

func _current_visual_settings() -> Dictionary:
    var preset_index: int = _visual_preset_option.selected if _visual_preset_option != null else 0
    preset_index = clampi(preset_index, 0, VISUAL_PRESET_COLORS.size() - 1)
    var bg: Array = VISUAL_PRESET_COLORS[preset_index]
    var ambient_energy: float = _visual_ambient_spinbox.value if _visual_ambient_spinbox != null else 1.0
    return {
        "preset": VISUAL_PRESET_LABELS[preset_index],
        "background_color": bg,
        "ambient_color": [0.6, 0.6, 0.6, 1.0],
        "ambient_energy": ambient_energy,
        "sun_energy": _visual_sun_spinbox.value if _visual_sun_spinbox != null else 1.0,
        "sun_rotation_degrees": [-55.0, -35.0, 0.0],
        "shadows_enabled": _visual_shadows_button.button_pressed if _visual_shadows_button != null else true,
        "no_bake_required": true,
    }

func _apply_editor_visual_preview() -> void:
    var settings: Dictionary = _current_visual_settings()
    var bg: Array = settings["background_color"] as Array
    if _editor_world_environment != null and _editor_world_environment.environment != null:
        _editor_world_environment.environment.background_color = Color(float(bg[0]), float(bg[1]), float(bg[2]), float(bg[3]))
        _editor_world_environment.environment.ambient_light_energy = float(settings["ambient_energy"])
    var sun: DirectionalLight3D = $Sun as DirectionalLight3D
    if sun != null:
        sun.light_energy = float(settings["sun_energy"])
        sun.shadow_enabled = bool(settings["shadows_enabled"])

func _set_visual_settings(settings: Dictionary) -> void:
    if settings.is_empty():
        return
    if _visual_preset_option != null:
        var preset_name: String = str(settings.get("preset", "Bright Day"))
        _visual_preset_option.select(maxi(VISUAL_PRESET_LABELS.find(preset_name), 0))
    if _visual_sun_spinbox != null:
        _visual_sun_spinbox.value = float(settings.get("sun_energy", 1.0))
    if _visual_ambient_spinbox != null:
        _visual_ambient_spinbox.value = float(settings.get("ambient_energy", 1.0))
    if _visual_shadows_button != null:
        _visual_shadows_button.set_pressed_no_signal(bool(settings.get("shadows_enabled", true)))
    _apply_editor_visual_preview()

func _generate_procedural_shape() -> void:
    var shape_index: int = _shape_type_option.selected if _shape_type_option != null else 0
    var shape_type: String = SHAPE_TYPES[clampi(shape_index, 0, SHAPE_TYPES.size() - 1)]
    var width: float = maxf(_shape_width_spinbox.value, 0.25)
    var length: float = maxf(_shape_length_spinbox.value, 0.25)
    var height: float = _shape_height_spinbox.value
    var segments: int = clampi(roundi(_shape_segments_spinbox.value), 3, 32)
    var radius: float = maxf(_shape_radius_spinbox.value, 0.25)
    var geo: Dictionary = _generate_shape_geometry(shape_type, width, length, height, segments, radius)
    var piece: Node3D = _add_piece("platform")
    piece.name = "%s_%02d" % [SHAPE_LABELS[shape_index].replace("/", "").replace(" ", ""), _piece_counter]
    piece.set_meta("custom_geo_points", geo["points"])
    piece.set_meta("custom_geo_faces", geo["faces"])
    piece.set_meta("custom_geo_materials", geo["materials"])
    piece.scale = Vector3.ONE
    piece.rotation_degrees = Vector3.ZERO
    _apply_custom_geometry_preview(piece)
    _select_piece(piece)
    _set_geometry_mode(true)
    _set_dirty(true)
    _set_status("Generated %s. Use Geometry controls to tweak or Play to test." % SHAPE_LABELS[shape_index])

func _generate_shape_geometry(shape_type: String, width: float, length: float, height: float, segments: int, radius: float) -> Dictionary:
    match shape_type:
        "halfpipe":
            return _generate_halfpipe_geometry(width, length, radius, segments)
        "bump":
            return _generate_bump_geometry(width, length, height, segments)
        "circular_platform":
            return _generate_circular_platform_geometry(radius, maxf(height, 0.2), segments)
        "arc":
            return _generate_arc_geometry(width, radius, height, segments)
        _:
            return _generate_curved_ramp_geometry(width, length, height, segments)

func _generate_curved_ramp_geometry(width: float, length: float, height: float, segments: int) -> Dictionary:
    var points: Array = []
    for i: int in range(segments + 1):
        var t: float = float(i) / float(segments)
        var z: float = lerpf(-length * 0.5, length * 0.5, t)
        var y: float = sin(t * PI * 0.5) * height
        points.append(_vector3_to_array(Vector3(-width * 0.5, y, z)))
        points.append(_vector3_to_array(Vector3(width * 0.5, y, z)))
    var faces: Array = []
    var materials: Array = []
    for i: int in range(segments):
        faces.append([i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2])
        materials.append("ground")
    return {"points": points, "faces": faces, "materials": materials}

func _generate_bump_geometry(width: float, length: float, height: float, segments: int) -> Dictionary:
    var rows: int = segments + 1
    var points: Array = []
    for z_i: int in range(rows):
        var tz: float = float(z_i) / float(segments)
        var z: float = lerpf(-length * 0.5, length * 0.5, tz)
        for x_i: int in range(rows):
            var tx: float = float(x_i) / float(segments)
            var x: float = lerpf(-width * 0.5, width * 0.5, tx)
            var dx: float = (tx - 0.5) * 2.0
            var dz: float = (tz - 0.5) * 2.0
            var y: float = height * maxf(0.0, 1.0 - (dx * dx + dz * dz))
            points.append(_vector3_to_array(Vector3(x, y, z)))
    var faces: Array = []
    var materials: Array = []
    for z_i: int in range(segments):
        for x_i: int in range(segments):
            var a: int = z_i * rows + x_i
            faces.append([a, a + 1, a + rows + 1, a + rows])
            materials.append("ground")
    return {"points": points, "faces": faces, "materials": materials}

func _generate_halfpipe_geometry(width: float, length: float, radius: float, segments: int) -> Dictionary:
    var points: Array = []
    for i: int in range(segments + 1):
        var a: float = lerpf(-PI * 0.5, PI * 0.5, float(i) / float(segments))
        var x: float = sin(a) * width * 0.5
        var y: float = (1.0 - cos(a)) * radius
        points.append(_vector3_to_array(Vector3(x, y, -length * 0.5)))
        points.append(_vector3_to_array(Vector3(x, y, length * 0.5)))
    var faces: Array = []
    var materials: Array = []
    for i: int in range(segments):
        faces.append([i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2])
        materials.append("ground")
    return {"points": points, "faces": faces, "materials": materials}

func _generate_arc_geometry(width: float, radius: float, height: float, segments: int) -> Dictionary:
    var arc_angle: float = PI if height >= 0.0 else PI * 0.5
    var points: Array = []
    for i: int in range(segments + 1):
        var t: float = float(i) / float(segments)
        var a: float = t * arc_angle
        var z: float = cos(a) * radius
        var y: float = sin(a) * radius
        points.append(_vector3_to_array(Vector3(-width * 0.5, y, z)))
        points.append(_vector3_to_array(Vector3(width * 0.5, y, z)))
    var faces: Array = []
    var materials: Array = []
    for i: int in range(segments):
        faces.append([i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2])
        materials.append("ground")
    return {"points": points, "faces": faces, "materials": materials}

func _generate_circular_platform_geometry(radius: float, thickness: float, segments: int) -> Dictionary:
    var points: Array = []
    points.append(_vector3_to_array(Vector3(0, thickness * 0.5, 0)))
    points.append(_vector3_to_array(Vector3(0, -thickness * 0.5, 0)))
    for i: int in range(segments):
        var a: float = TAU * float(i) / float(segments)
        var p: Vector3 = Vector3(cos(a) * radius, thickness * 0.5, sin(a) * radius)
        points.append(_vector3_to_array(p))
        points.append(_vector3_to_array(Vector3(p.x, -thickness * 0.5, p.z)))
    var faces: Array = []
    var materials: Array = []
    for i: int in range(segments):
        var ni: int = (i + 1) % segments
        faces.append([0, 2 + i * 2, 2 + ni * 2])
        materials.append("ground")
        faces.append([1, 3 + ni * 2, 3 + i * 2])
        materials.append("wall-top")
        faces.append([2 + i * 2, 3 + i * 2, 3 + ni * 2, 2 + ni * 2])
        materials.append("wall-side")
    return {"points": points, "faces": faces, "materials": materials}

func _select_relative_vertex(delta: int) -> void:
    if _selected_piece == null or not _has_custom_geometry(_selected_piece):
        return
    var points: Array = _selected_piece.get_meta("custom_geo_points") as Array
    if points.is_empty():
        return
    _selected_vertex_index = posmod(_selected_vertex_index + delta, points.size())
    _refresh_geometry_ui()
    _update_geometry_overlay()

func _nudge_selected_vertex(direction: Vector3) -> void:
    if _selected_piece == null or not _has_custom_geometry(_selected_piece) or _selected_vertex_index < 0:
        _set_status("Convert geometry and select a vertex first.")
        return
    _push_geometry_undo(_selected_piece)
    var points: Array = (_selected_piece.get_meta("custom_geo_points") as Array).duplicate(true)
    var point: Vector3 = _array_to_vector3(points[_selected_vertex_index], Vector3.ZERO)
    var amount: float = _move_snap if _snap_enabled else 0.25
    point += direction * amount
    if _snap_enabled:
        point = _snap_vector3(point, _move_snap)
    points[_selected_vertex_index] = _vector3_to_array(point)
    _selected_piece.set_meta("custom_geo_points", points)
    _apply_custom_geometry_preview(_selected_piece)
    _update_geometry_overlay()
    _set_dirty(true)
    _set_status("Moved vertex %d." % _selected_vertex_index)

func _on_geometry_face_selected(index: int) -> void:
    _selected_face_index = clampi(index, 0, GEO_FACE_NAMES.size() - 1)
    _refresh_geometry_ui()

func _on_geometry_material_selected(index: int) -> void:
    if _selected_piece == null or not _has_custom_geometry(_selected_piece):
        return
    _push_geometry_undo(_selected_piece)
    var materials: Array = (_selected_piece.get_meta("custom_geo_materials") as Array).duplicate(true)
    while materials.size() < 6:
        materials.append("wall-side")
    materials[_selected_face_index] = GEO_FACE_MATERIALS[clampi(index, 0, GEO_FACE_MATERIALS.size() - 1)]
    _selected_piece.set_meta("custom_geo_materials", materials)
    _set_dirty(true)
    _set_status("Set %s face material to %s." % [GEO_FACE_NAMES[_selected_face_index], materials[_selected_face_index]])

func _push_geometry_undo(piece: Node3D) -> void:
    if piece == null or not _has_custom_geometry(piece):
        return
    _geometry_undo_stack.append({
        "piece": piece,
        "points": (piece.get_meta("custom_geo_points") as Array).duplicate(true),
        "materials": (piece.get_meta("custom_geo_materials", []) as Array).duplicate(true),
    })
    if _geometry_undo_stack.size() > 30:
        _geometry_undo_stack.pop_front()

func _remove_geometry_undo_entries_for_piece(piece: Node3D) -> void:
    for i: int in range(_geometry_undo_stack.size() - 1, -1, -1):
        var entry: Dictionary = _geometry_undo_stack[i]
        if entry.get("piece", null) == piece:
            _geometry_undo_stack.remove_at(i)

func _undo_geometry_edit() -> void:
    if _geometry_undo_stack.is_empty():
        _set_status("No geometry undo available.")
        return
    var entry: Dictionary = _geometry_undo_stack.pop_back()
    var piece: Node3D = entry.get("piece", null) as Node3D
    if piece == null or not is_instance_valid(piece):
        return
    piece.set_meta("custom_geo_points", (entry["points"] as Array).duplicate(true))
    piece.set_meta("custom_geo_materials", (entry["materials"] as Array).duplicate(true))
    _select_piece(piece)
    _apply_custom_geometry_preview(piece)
    _update_geometry_overlay()
    _set_dirty(true)
    _set_status("Undid geometry edit.")

func _begin_viewport_transform_or_pick(screen_position: Vector2) -> void:
    if _geometry_mode and _pick_geometry_vertex_at(screen_position):
        return
    var piece: Node3D = _piece_at_screen_position(screen_position)
    if piece == null:
        _select_piece(null)
        return
    _select_piece(piece)
    _dragging_transform = true
    _drag_start_mouse = screen_position
    _drag_start_position = piece.position
    _drag_start_rotation = piece.rotation_degrees
    _drag_start_scale = piece.scale
    _drag_start_plane_point = _screen_to_horizontal_plane(screen_position, _drag_start_position.y)
    _set_status("Dragging %s in %s mode." % [piece.name, _transform_mode_name()])

func _end_viewport_transform() -> void:
    if not _dragging_transform:
        return
    _dragging_transform = false
    _refresh_inspector()
    _set_dirty(true)
    _set_status("Finished %s transform." % _transform_mode_name().to_lower())

func _update_viewport_transform(screen_position: Vector2, relative: Vector2) -> void:
    if _selected_piece == null or not is_instance_valid(_selected_piece):
        _dragging_transform = false
        return
    match _transform_mode:
        TransformMode.MOVE:
            var next_position: Vector3 = _drag_start_position
            if Input.is_key_pressed(KEY_SHIFT):
                var height_delta: float = (_drag_start_mouse.y - screen_position.y) * 0.025
                next_position.y += height_delta
            else:
                var plane_point: Vector3 = _screen_to_horizontal_plane(screen_position, _drag_start_position.y)
                var delta: Vector3 = plane_point - _drag_start_plane_point
                next_position += Vector3(delta.x, 0.0, delta.z)
            if _snap_enabled:
                next_position = _snap_vector3(next_position, _move_snap)
            _selected_piece.position = next_position
        TransformMode.ROTATE:
            var rot: Vector3 = _drag_start_rotation
            rot.y += (screen_position.x - _drag_start_mouse.x) * 0.5
            if _snap_enabled:
                rot.y = snappedf(rot.y, _rotate_snap)
            _selected_piece.rotation_degrees = rot
        TransformMode.SCALE:
            var amount: float = (screen_position.x - _drag_start_mouse.x - relative.y) * 0.01
            var next_scale: Vector3 = _drag_start_scale + Vector3.ONE * amount
            next_scale.x = maxf(0.05, next_scale.x)
            next_scale.y = maxf(0.05, next_scale.y)
            next_scale.z = maxf(0.05, next_scale.z)
            if _snap_enabled:
                next_scale = _snap_vector3(next_scale, _scale_snap)
            _selected_piece.scale = next_scale
    if _gizmo_root != null:
        _gizmo_root.global_position = _selected_piece.global_position
    _refresh_inspector()

func _piece_at_screen_position(screen_position: Vector2) -> Node3D:
    var from: Vector3 = _camera.project_ray_origin(screen_position)
    var to: Vector3 = from + _camera.project_ray_normal(screen_position) * RAY_LENGTH
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
    query.collide_with_areas = true
    query.collide_with_bodies = false
    query.collision_mask = PIECE_COLLISION_MASK
    var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    if result.is_empty():
        return null
    var collider: Object = result.get("collider", null)
    if collider is Area3D:
        var area: Area3D = collider as Area3D
        var piece_object: Variant = area.get_meta("piece", null)
        if not is_instance_valid(piece_object):
            _update_geometry_overlay()
            return null
        return piece_object as Node3D
    return null

func _pick_geometry_vertex_at(screen_position: Vector2) -> bool:
    var from: Vector3 = _camera.project_ray_origin(screen_position)
    var to: Vector3 = from + _camera.project_ray_normal(screen_position) * RAY_LENGTH
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
    query.collide_with_areas = true
    query.collide_with_bodies = false
    query.collision_mask = PIECE_COLLISION_MASK
    var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    if result.is_empty():
        return false
    var collider: Object = result.get("collider", null)
    if collider is Area3D:
        var area: Area3D = collider as Area3D
        if area.has_meta("vertex_index"):
            var piece_object: Variant = area.get_meta("piece", null)
            if not is_instance_valid(piece_object):
                _selected_piece = null
                _selected_vertex_index = -1
                _update_geometry_overlay()
                _refresh_inspector()
                _set_status("Removed stale geometry handles.")
                return true
            _select_piece(piece_object as Node3D)
            _selected_vertex_index = int(area.get_meta("vertex_index", -1))
            _refresh_geometry_ui()
            _update_geometry_overlay()
            _set_status("Selected vertex %d." % _selected_vertex_index)
            return true
    return false

func _screen_to_horizontal_plane(screen_position: Vector2, plane_y: float) -> Vector3:
    var ray_origin: Vector3 = _camera.project_ray_origin(screen_position)
    var ray_dir: Vector3 = _camera.project_ray_normal(screen_position)
    if absf(ray_dir.y) < 0.0001:
        return _drag_start_position
    var t: float = (plane_y - ray_origin.y) / ray_dir.y
    return ray_origin + ray_dir * t

func _snap_vector3(value: Vector3, snap_amount: float) -> Vector3:
    if snap_amount <= 0.0:
        return value
    return Vector3(snappedf(value.x, snap_amount), snappedf(value.y, snap_amount), snappedf(value.z, snap_amount))

func _pick_piece_at(screen_position: Vector2) -> void:
    _select_piece(_piece_at_screen_position(screen_position))

func _select_piece(piece: Node3D) -> void:
    if piece != null and not is_instance_valid(piece):
        piece = null
    if _selected_piece == piece:
        return
    if _selected_piece != null and is_instance_valid(_selected_piece):
        _set_piece_selected_visual(_selected_piece, false)
    _selected_piece = piece
    if _selected_piece != null:
        _set_piece_selected_visual(_selected_piece, true)
        if _has_custom_geometry(_selected_piece) and _selected_vertex_index < 0:
            _selected_vertex_index = 0
        _set_status("Selected %s." % _selected_piece.name)
    else:
        _selected_vertex_index = -1
        _set_status("Selection cleared.")
    _update_gizmo_visual()
    _update_geometry_overlay()
    _refresh_geometry_ui()
    _refresh_inspector()

func _set_piece_selected_visual(piece: Node3D, selected: bool) -> void:
    var mesh_instance: MeshInstance3D = piece.get_node("Preview") as MeshInstance3D
    if selected:
        mesh_instance.material_override = _selected_material
    else:
        mesh_instance.material_override = piece.get_meta("base_material") as Material

func _update_gizmo_visual() -> void:
    if _gizmo_root == null:
        return
    for child: Node in _gizmo_root.get_children():
        child.free()
    if _selected_piece == null or not is_instance_valid(_selected_piece):
        _gizmo_root.visible = false
        return
    _gizmo_root.visible = true
    _gizmo_root.global_position = _selected_piece.global_position
    match _transform_mode:
        TransformMode.MOVE:
            _add_gizmo_axis(Vector3.RIGHT, Color.RED, "X")
            _add_gizmo_axis(Vector3.UP, Color.GREEN, "Y")
            _add_gizmo_axis(Vector3.FORWARD, Color.BLUE, "Z")
        TransformMode.ROTATE:
            _add_gizmo_ring(Color(1.0, 0.75, 0.1, 1.0))
        TransformMode.SCALE:
            _add_gizmo_axis(Vector3.RIGHT, Color(1.0, 0.45, 0.45, 1.0), "ScaleX")
            _add_gizmo_axis(Vector3.UP, Color(0.45, 1.0, 0.45, 1.0), "ScaleY")
            _add_gizmo_axis(Vector3.FORWARD, Color(0.45, 0.6, 1.0, 1.0), "ScaleZ")

func _add_gizmo_axis(direction: Vector3, color: Color, axis_name: String) -> void:
    var axis: MeshInstance3D = MeshInstance3D.new()
    axis.name = axis_name
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = 0.035
    mesh.bottom_radius = 0.035
    mesh.height = 2.0
    axis.mesh = mesh
    axis.material_override = _make_unshaded_material(color)
    axis.position = direction.normalized()
    if direction.is_equal_approx(Vector3.RIGHT):
        axis.rotation_degrees.z = 90.0
    elif direction.is_equal_approx(Vector3.FORWARD):
        axis.rotation_degrees.x = 90.0
    _gizmo_root.add_child(axis)

func _add_gizmo_ring(color: Color) -> void:
    var vertices: PackedVector3Array = PackedVector3Array()
    var steps: int = 64
    var radius: float = 1.4
    for i: int in range(steps):
        var a0: float = TAU * float(i) / float(steps)
        var a1: float = TAU * float(i + 1) / float(steps)
        vertices.append(Vector3(cos(a0) * radius, 0.05, sin(a0) * radius))
        vertices.append(Vector3(cos(a1) * radius, 0.05, sin(a1) * radius))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
    var ring: MeshInstance3D = MeshInstance3D.new()
    ring.name = "RotateRing"
    ring.mesh = mesh
    ring.material_override = _make_unshaded_material(color)
    _gizmo_root.add_child(ring)

func _update_movement_preview() -> void:
    if _movement_preview_root == null:
        return
    for child: Node in _movement_preview_root.get_children():
        child.free()
    if _selected_piece == null or not is_instance_valid(_selected_piece):
        return
    var movement: Dictionary = _movement_data(_selected_piece)
    var type_name: String = str(movement.get("type", "none"))
    if type_name == "none":
        return
    var vertices: PackedVector3Array = PackedVector3Array()
    match type_name:
        "linear":
            var offset: Vector3 = _array_to_vector3(movement.get("offset", [2.0, 0.0, 0.0]), Vector3(2.0, 0.0, 0.0))
            var start: Vector3 = _selected_piece.position
            var end: Vector3 = start + offset
            vertices.append(start)
            vertices.append(end)
            _add_preview_marker(end)
        "spinner", "pendulum", "ramp":
            var radius: float = maxf(maxf(absf(_selected_piece.scale.x), absf(_selected_piece.scale.z)) * 0.75, 0.9)
            var center: Vector3 = _selected_piece.position + Vector3.UP * 0.05
            for i: int in range(64):
                var a0: float = TAU * float(i) / 64.0
                var a1: float = TAU * float(i + 1) / 64.0
                vertices.append(center + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius))
                vertices.append(center + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius))
    if vertices.is_empty():
        return
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
    var preview: MeshInstance3D = MeshInstance3D.new()
    preview.name = "MovementPath"
    preview.mesh = mesh
    preview.material_override = _make_unshaded_material(Color(1.0, 0.85, 0.15, 1.0))
    _movement_preview_root.add_child(preview)

func _add_preview_marker(marker_position: Vector3) -> void:
    var marker: MeshInstance3D = MeshInstance3D.new()
    marker.name = "MovementEnd"
    var sphere: SphereMesh = SphereMesh.new()
    sphere.radius = 0.12
    sphere.height = 0.24
    marker.mesh = sphere
    marker.position = marker_position
    marker.material_override = _make_unshaded_material(Color(1.0, 0.85, 0.15, 1.0))
    _movement_preview_root.add_child(marker)

func _apply_custom_geometry_preview(piece: Node3D) -> void:
    if not _has_custom_geometry(piece):
        return
    var mesh_instance: MeshInstance3D = piece.get_node("Preview") as MeshInstance3D
    var mesh: ArrayMesh = ArrayMesh.new()
    var points: Array = piece.get_meta("custom_geo_points") as Array
    var face_indices: Array = _custom_faces_for_piece(piece)
    var vertices: PackedVector3Array = PackedVector3Array()
    for face_value: Variant in face_indices:
        var face: Array = face_value as Array
        if face.size() < 3:
            continue
        var p0: Vector3 = _array_to_vector3(points[int(face[0])], Vector3.ZERO)
        for i: int in range(1, face.size() - 1):
            var p1: Vector3 = _array_to_vector3(points[int(face[i])], Vector3.ZERO)
            var p2: Vector3 = _array_to_vector3(points[int(face[i + 1])], Vector3.ZERO)
            vertices.append_array([p0, p1, p2])
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh_instance.mesh = mesh

func _update_geometry_overlay() -> void:
    if _geometry_overlay_root == null:
        return
    for child: Node in _geometry_overlay_root.get_children():
        child.free()
    if not _geometry_mode or _selected_piece == null or not _has_custom_geometry(_selected_piece):
        return
    var points: Array = _selected_piece.get_meta("custom_geo_points") as Array
    for i: int in range(points.size()):
        var local_point: Vector3 = _array_to_vector3(points[i], Vector3.ZERO)
        var marker: MeshInstance3D = MeshInstance3D.new()
        marker.name = "Vertex_%02d" % i
        var sphere: SphereMesh = SphereMesh.new()
        sphere.radius = 0.11 if i != _selected_vertex_index else 0.16
        sphere.height = sphere.radius * 2.0
        marker.mesh = sphere
        marker.position = _selected_piece.global_transform * local_point
        marker.material_override = _make_unshaded_material(Color(1.0, 0.3, 0.15, 1.0) if i == _selected_vertex_index else Color(1.0, 0.95, 0.15, 1.0))
        _geometry_overlay_root.add_child(marker)
        var area: Area3D = Area3D.new()
        area.name = "PickArea"
        area.collision_layer = PIECE_COLLISION_LAYER
        area.collision_mask = 0
        area.set_meta("piece", _selected_piece)
        area.set_meta("vertex_index", i)
        marker.add_child(area)
        var shape: CollisionShape3D = CollisionShape3D.new()
        var sphere_shape: SphereShape3D = SphereShape3D.new()
        sphere_shape.radius = 0.22
        shape.shape = sphere_shape
        area.add_child(shape)

func _refresh_geometry_ui() -> void:
    var has_selection: bool = _selected_piece != null and is_instance_valid(_selected_piece)
    var has_geo: bool = has_selection and _has_custom_geometry(_selected_piece)
    for control: Control in _geometry_detail_controls:
        control.visible = has_geo
    if _geometry_mode_button != null:
        _geometry_mode_button.set_pressed_no_signal(_geometry_mode)
    if _geometry_convert_button != null:
        _geometry_convert_button.disabled = not has_selection
    if _geometry_vertex_label != null:
        _geometry_vertex_label.text = "Vertex: %s" % (str(_selected_vertex_index) if has_geo and _selected_vertex_index >= 0 else "--")
    if _geometry_face_option != null:
        _geometry_face_option.disabled = not has_geo
        _geometry_face_option.select(_selected_face_index)
    if _geometry_material_option != null:
        _geometry_material_option.disabled = not has_geo
        if has_geo:
            var materials: Array = _selected_piece.get_meta("custom_geo_materials", _default_geo_materials(false)) as Array
            var material_name: String = str(materials[_selected_face_index]) if _selected_face_index < materials.size() else "wall-side"
            _geometry_material_option.select(maxi(GEO_FACE_MATERIALS.find(material_name), 0))

func _refresh_inspector() -> void:
    _updating_inspector = true
    var has_selection: bool = _selected_piece != null and is_instance_valid(_selected_piece)
    _set_inspector_details_visible(has_selection)
    if has_selection:
        var piece_type: String = _selected_piece.get_meta("piece_type", "") as String
        _selection_label.text = "%s\n%s" % [_selected_piece.name, _piece_display_name(piece_type)]
        _set_vector3_editor_values("position", _selected_piece.position)
        _set_vector3_editor_values("rotation", _selected_piece.rotation_degrees)
        _set_vector3_editor_values("scale", _selected_piece.scale)
        _refresh_movement_controls(_movement_data(_selected_piece), true)
    else:
        _selection_label.text = "No selection. Add a piece or left-click one in the viewport."
        _set_vector3_editor_values("position", Vector3.ZERO)
        _set_vector3_editor_values("rotation", Vector3.ZERO)
        _set_vector3_editor_values("scale", Vector3.ONE)
        _refresh_movement_controls(_default_movement_data(), false)
    for spinbox_value: Variant in _inspector_spinboxes.values():
        var spinbox: SpinBox = spinbox_value as SpinBox
        spinbox.editable = has_selection
    _set_movement_controls_editable(has_selection)
    _refresh_geometry_ui()
    if _duplicate_button != null:
        _duplicate_button.disabled = not has_selection
    if _delete_button != null:
        _delete_button.disabled = not has_selection
    if not has_selection:
        _set_inspector_details_visible(false)
    _updating_inspector = false
    _update_movement_preview()

func _set_inspector_details_visible(show_details: bool) -> void:
    if _inspector_box == null:
        return
    for child: Node in _inspector_box.get_children():
        if child == _selection_label or child.name == "InspectorTitle":
            child.visible = true
        elif child == _position_label or child == _snap_label:
            child.visible = false
        elif child is Control:
            (child as Control).visible = show_details

func _set_vector3_editor_values(property_name: String, value: Vector3) -> void:
    for axis: int in range(3):
        var spinbox: SpinBox = _inspector_spinboxes["%s_%d" % [property_name, axis]] as SpinBox
        spinbox.value = value[axis]

func _refresh_movement_controls(movement: Dictionary, has_selection: bool) -> void:
    if _movement_type_option == null:
        return
    var type_name: String = str(movement.get("type", "none"))
    var type_index: int = maxi(MOVEMENT_TYPES.find(type_name), 0)
    _movement_type_option.select(type_index)
    _movement_length_spinbox.value = float(movement.get("length", 4.0))
    _movement_t0_spinbox.value = float(movement.get("t0", 0.0))
    _set_spinbox_vector(_movement_offset_spinboxes, _array_to_vector3(movement.get("offset", [2.0, 0.0, 0.0]), Vector3(2.0, 0.0, 0.0)))
    _set_spinbox_vector(_movement_axis_spinboxes, _array_to_vector3(movement.get("axis", [0.0, 1.0, 0.0]), Vector3.UP))
    _movement_theta0_spinbox.value = float(movement.get("theta0", 25.0))
    _movement_theta1_spinbox.value = float(movement.get("theta1", -25.0))
    _movement_transition_spinbox.value = float(movement.get("transition", 0.5))
    _set_movement_controls_editable(has_selection)
    _update_movement_control_visibility(type_name, has_selection)

func _update_movement_control_visibility(type_name: String, has_selection: bool) -> void:
    var active: bool = has_selection and type_name != "none"
    _set_control_row_visible(_movement_length_spinbox, active)
    _set_control_row_visible(_movement_t0_spinbox, active)
    var show_offset: bool = has_selection and type_name == "linear"
    _movement_offset_label.visible = show_offset
    for spinbox: SpinBox in _movement_offset_spinboxes:
        _set_control_row_visible(spinbox, show_offset)
    var show_axis: bool = has_selection and (type_name == "pendulum" or type_name == "ramp")
    _movement_axis_label.visible = show_axis
    for spinbox: SpinBox in _movement_axis_spinboxes:
        _set_control_row_visible(spinbox, show_axis)
    var show_theta0: bool = has_selection and (type_name == "pendulum" or type_name == "ramp")
    _set_control_row_visible(_movement_theta0_spinbox, show_theta0)
    _movement_angle_a_label.visible = show_theta0
    var show_theta1: bool = has_selection and type_name == "ramp"
    _set_control_row_visible(_movement_theta1_spinbox, show_theta1)
    _movement_angle_b_label.visible = show_theta1
    _set_control_row_visible(_movement_transition_spinbox, show_theta1)
    _movement_transition_label.visible = show_theta1

func _set_control_row_visible(control: Control, should_show: bool) -> void:
    if control == null:
        return
    var row: Control = control.get_parent() as Control
    if row != null:
        row.visible = should_show
    else:
        control.visible = should_show

func _set_spinbox_vector(spinboxes: Array[SpinBox], value: Vector3) -> void:
    for axis: int in range(3):
        if axis < spinboxes.size():
            spinboxes[axis].value = value[axis]

func _set_movement_controls_editable(editable: bool) -> void:
    var controls: Array[Control] = [_movement_type_option, _movement_length_spinbox, _movement_t0_spinbox, _movement_theta0_spinbox, _movement_theta1_spinbox, _movement_transition_spinbox]
    for spinbox: SpinBox in _movement_offset_spinboxes:
        controls.append(spinbox)
    for spinbox: SpinBox in _movement_axis_spinboxes:
        controls.append(spinbox)
    for control: Control in controls:
        if control == null:
            continue
        if control is SpinBox:
            (control as SpinBox).editable = editable
        elif control is OptionButton:
            (control as OptionButton).disabled = not editable

func _on_movement_type_selected(index: int) -> void:
    if _updating_inspector or _selected_piece == null or not is_instance_valid(_selected_piece):
        return
    var movement: Dictionary = _movement_data(_selected_piece)
    movement["type"] = MOVEMENT_TYPES[clampi(index, 0, MOVEMENT_TYPES.size() - 1)]
    _selected_piece.set_meta("movement", movement)
    _set_dirty(true)
    _update_movement_control_visibility(str(movement["type"]), true)
    _update_movement_preview()
    _set_status("Set %s movement to %s." % [_selected_piece.name, MOVEMENT_LABELS[index]])

func _on_movement_number_changed(value: float, property_name: String) -> void:
    if _updating_inspector or _selected_piece == null or not is_instance_valid(_selected_piece):
        return
    var movement: Dictionary = _movement_data(_selected_piece)
    movement[property_name] = value
    _selected_piece.set_meta("movement", movement)
    _set_dirty(true)
    _update_movement_preview()

func _on_movement_vector_changed(value: float, property_name: String, axis: int) -> void:
    if _updating_inspector or _selected_piece == null or not is_instance_valid(_selected_piece):
        return
    var movement: Dictionary = _movement_data(_selected_piece)
    var fallback: Vector3 = Vector3(2.0, 0.0, 0.0) if property_name == "offset" else Vector3.UP
    var vec: Vector3 = _array_to_vector3(movement.get(property_name, _vector3_to_array(fallback)), fallback)
    vec[axis] = value
    movement[property_name] = _vector3_to_array(vec)
    _selected_piece.set_meta("movement", movement)
    _set_dirty(true)
    _update_movement_preview()

func _on_transform_spinbox_changed(value: float, property_name: String, axis: int) -> void:
    if _updating_inspector or _selected_piece == null or not is_instance_valid(_selected_piece):
        return
    match property_name:
        "position":
            var pos: Vector3 = _selected_piece.position
            pos[axis] = value
            _selected_piece.position = pos
        "rotation":
            var rot: Vector3 = _selected_piece.rotation_degrees
            rot[axis] = value
            _selected_piece.rotation_degrees = rot
        "scale":
            var scl: Vector3 = _selected_piece.scale
            scl[axis] = maxf(0.05, value)
            _selected_piece.scale = scl
    _update_gizmo_visual()
    _update_movement_preview()
    _set_dirty(true)
    _set_status("Updated %s %s." % [_selected_piece.name, property_name])

func _duplicate_selected_piece() -> void:
    if _selected_piece == null or not is_instance_valid(_selected_piece):
        _set_status("Select a piece before duplicating.")
        return
    var source_name: String = _selected_piece.name
    var piece_type: String = _selected_piece.get_meta("piece_type", "platform") as String
    var source_position: Vector3 = _selected_piece.position
    var source_rotation: Vector3 = _selected_piece.rotation_degrees
    var source_scale: Vector3 = _selected_piece.scale
    var source_movement: Dictionary = _movement_data(_selected_piece).duplicate(true)
    var duplicated_piece: Node3D = _add_piece(piece_type)
    duplicated_piece.position = source_position + Vector3(1.0, 0.0, 1.0)
    duplicated_piece.rotation_degrees = source_rotation
    duplicated_piece.scale = source_scale
    duplicated_piece.set_meta("movement", source_movement)
    if _has_custom_geometry(_selected_piece):
        duplicated_piece.set_meta("custom_geo_points", (_selected_piece.get_meta("custom_geo_points") as Array).duplicate(true))
        if _selected_piece.has_meta("custom_geo_faces"):
            duplicated_piece.set_meta("custom_geo_faces", (_selected_piece.get_meta("custom_geo_faces") as Array).duplicate(true))
        duplicated_piece.set_meta("custom_geo_materials", (_selected_piece.get_meta("custom_geo_materials", []) as Array).duplicate(true))
        _apply_custom_geometry_preview(duplicated_piece)
    _select_piece(duplicated_piece)
    _update_gizmo_visual()
    _refresh_inspector()
    _set_status("Duplicated %s." % source_name)

func _delete_selected_piece() -> void:
    if _selected_piece == null or not is_instance_valid(_selected_piece):
        _set_status("Select a piece before deleting.")
        return
    var old_name: String = _selected_piece.name
    var piece_to_delete: Node3D = _selected_piece
    _selected_piece = null
    _selected_vertex_index = -1
    _remove_geometry_undo_entries_for_piece(piece_to_delete)
    _update_geometry_overlay()
    piece_to_delete.queue_free()
    _update_gizmo_visual()
    _refresh_inspector()
    _set_dirty(true)
    _set_status("Deleted %s." % old_name)

func _nudge_selected_piece_height(direction: float) -> void:
    if _selected_piece == null or not is_instance_valid(_selected_piece):
        return
    var step: float = _move_snap if _snap_enabled else 0.25
    var pos: Vector3 = _selected_piece.position
    pos.y += step * direction
    if _snap_enabled:
        pos.y = snappedf(pos.y, _move_snap)
    _selected_piece.position = pos
    _update_gizmo_visual()
    _refresh_inspector()
    _set_dirty(true)
    _set_status("Moved %s height to Y %.2f." % [_selected_piece.name, _selected_piece.position.y])

func _new_level() -> void:
    _clear_pieces()
    _piece_counter = 0
    _set_dirty(true)
    _set_status("Started a new empty editor level.")

func _clear_pieces() -> void:
    for child: Node in _pieces_root.get_children():
        child.free()
    _selected_piece = null
    _selected_vertex_index = -1
    _update_gizmo_visual()
    _update_geometry_overlay()
    _refresh_inspector()

func _on_file_path_submitted(path: String) -> void:
    _set_current_file_path(path)

func _on_file_path_focus_exited() -> void:
    if _file_path_edit != null:
        _set_current_file_path(_file_path_edit.text)

func _set_current_file_path(path: String) -> void:
    var clean_path: String = path.strip_edges()
    if clean_path.is_empty():
        clean_path = DEFAULT_EDITOR_SAVE_PATH
    if not clean_path.ends_with(".golfedit"):
        clean_path += ".golfedit"
    _current_file_path = clean_path
    if _file_path_edit != null:
        _file_path_edit.text = _current_file_path
    _refresh_dirty_ui()

func _save_golfedit() -> void:
    _set_current_file_path(_file_path_edit.text if _file_path_edit != null else _current_file_path)
    _ensure_parent_directory(_current_file_path)
    var f: FileAccess = FileAccess.open(_current_file_path, FileAccess.WRITE)
    if f == null:
        _set_status("Could not save %s (error %d)." % [_current_file_path, FileAccess.get_open_error()])
        return
    f.store_string(JSON.stringify(_serialize_editor_level(), "  "))
    f.close()
    _set_dirty(false)
    var count: int = _pieces_root.get_child_count()
    var noun: String = "piece" if count == 1 else "pieces"
    var report: Dictionary = _validation_report()
    if bool(report["export_ok"]):
        _set_status("Saved %d %s to %s." % [count, noun, _current_file_path])
    else:
        _set_status("Saved, but validation needs attention before Play/Export.")
        _validate_level_for_user()

func _load_golfedit() -> void:
    _set_current_file_path(_file_path_edit.text if _file_path_edit != null else _current_file_path)
    if not FileAccess.file_exists(_current_file_path):
        _set_status("No .golfedit file found at %s." % _current_file_path)
        return
    var f: FileAccess = FileAccess.open(_current_file_path, FileAccess.READ)
    if f == null:
        _set_status("Could not load %s (error %d)." % [_current_file_path, FileAccess.get_open_error()])
        return
    var text: String = f.get_as_text()
    f.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        _set_status("Invalid .golfedit JSON in %s." % _current_file_path)
        return
    _deserialize_editor_level(parsed as Dictionary)
    _set_dirty(false)
    var count: int = _pieces_root.get_child_count()
    var noun: String = "piece" if count == 1 else "pieces"
    _set_status("Loaded %d %s from %s." % [count, noun, _current_file_path])

func _export_level() -> void:
    var export_path: String = _export_current_level()
    if export_path.is_empty():
        return
    _set_status("Exported playable level to %s (%s)." % [export_path, ProjectSettings.globalize_path(export_path)])

func _export_current_level() -> String:
    _set_current_file_path(_file_path_edit.text if _file_path_edit != null else _current_file_path)
    var validation_errors: Array[String] = _validate_exportable_level()
    if not validation_errors.is_empty():
        _set_status("Export blocked: %s" % "; ".join(validation_errors))
        return ""
    var export_path: String = _export_path_from_editor_path(_current_file_path)
    _ensure_parent_directory(export_path)
    var f: FileAccess = FileAccess.open(export_path, FileAccess.WRITE)
    if f == null:
        _set_status("Could not export %s (error %d)." % [export_path, FileAccess.get_open_error()])
        return ""
    f.store_string(JSON.stringify(_build_open_golf_level_data(), "  "))
    f.close()
    return export_path

func _play_test_exported_level() -> void:
    _save_golfedit()
    var export_path: String = _export_current_level()
    if export_path.is_empty():
        return
    var editor_path: String = _current_file_path
    var packed: PackedScene = load("res://scenes/golf_play.tscn") as PackedScene
    if packed == null:
        _set_status("Could not open play scene for testing.")
        return
    var play_scene: Node = packed.instantiate()
    play_scene.set("level_path", export_path)
    play_scene.set("return_editor_golfedit_path", editor_path)
    var tree: SceneTree = get_tree()
    tree.root.add_child(play_scene)
    tree.current_scene = play_scene
    tree.root.remove_child(self)
    queue_free()

func _validate_exportable_level() -> Array[String]:
    var report: Dictionary = _validation_report()
    var errors: Array[String] = []
    if not bool(report["surface_ok"]):
        errors.append("add at least one platform/ramp/wall/water surface")
    if not bool(report["ball_start_ok"]):
        errors.append("add exactly one Ball Start")
    if not bool(report["hole_ok"]):
        errors.append("add exactly one Hole")
    if not errors.is_empty():
        _validate_level_for_user()
    return errors

func _export_path_from_editor_path(path: String) -> String:
    if path.ends_with(".golfedit"):
        return path.substr(0, path.length() - ".golfedit".length()) + LEVEL_EXPORT_EXTENSION
    return path + LEVEL_EXPORT_EXTENSION

func _reveal_current_file_folder() -> void:
    _set_current_file_path(_file_path_edit.text if _file_path_edit != null else _current_file_path)
    var export_path: String = _export_path_from_editor_path(_current_file_path)
    var folder_path: String = export_path.get_base_dir()
    if folder_path.is_empty():
        folder_path = "user://"
    _ensure_parent_directory(folder_path.path_join("placeholder.tmp"))
    var absolute_folder: String = ProjectSettings.globalize_path(folder_path)
    OS.shell_open(absolute_folder)
    _set_status("Opened export folder: %s. Current .level path: %s" % [absolute_folder, ProjectSettings.globalize_path(export_path)])

func _build_open_golf_level_data() -> Dictionary:
    var entities: Array = []
    for child: Node in _pieces_root.get_children():
        var piece: Node3D = child as Node3D
        if piece == null:
            continue
        var piece_type: String = piece.get_meta("piece_type", "") as String
        match piece_type:
            "platform", "ramp", "wall":
                entities.append(_piece_to_geo_entity(piece, "geo"))
            "water":
                entities.append(_piece_to_geo_entity(piece, "water"))
            "ball_start":
                entities.append(_piece_to_marker_entity(piece, "ball-start"))
            "hole":
                entities.append(_piece_to_marker_entity(piece, "hole"))
            "prop":
                entities.append(_piece_to_prop_model_entity(piece))
    return {
        "visual_settings": _current_visual_settings(),
        "data_dependencies": [
            "data/textures/ground.png",
            "data/textures/wood.jpg",
            "data/textures/environment/water.jpg",
            "data/textures/colors/light_gray.png",
            "data/models/nature_kit/tree_pineSmallB.obj",
        ],
        "materials": _export_materials(),
        "lightmap_images": [],
        "entities": entities,
    }

func _export_materials() -> Array:
    return [
        {"name": "ground", "friction": 0.3, "restitution": 0.4, "vel_scale": 1.0, "type": "environment", "texture": "data/textures/ground.png"},
        {"name": "default", "friction": 0.3, "restitution": 0.4, "vel_scale": 1.0, "type": "environment", "texture": "data/textures/ground.png"},
        {"name": "wall-top", "friction": 0.3, "restitution": 0.4, "vel_scale": 1.0, "type": "environment", "texture": "data/textures/wood.jpg"},
        {"name": "wall-side", "friction": 0.0, "restitution": 1.0, "vel_scale": 0.8, "type": "environment", "texture": "data/textures/wood.jpg"},
        {"name": "water", "friction": 0.15, "restitution": 0.1, "vel_scale": 0.2, "type": "water", "texture": "data/textures/environment/water.jpg"},
        {"name": "marker", "friction": 0.3, "restitution": 0.4, "vel_scale": 1.0, "type": "environment", "texture": "data/textures/colors/light_gray.png"},
    ]

func _piece_to_marker_entity(piece: Node3D, entity_type: String) -> Dictionary:
    var scale_value: float = maxf(piece.scale.x, maxf(piece.scale.y, piece.scale.z))
    if entity_type == "ball-start":
        scale_value = maxf(scale_value, 0.25)
    elif entity_type == "hole":
        scale_value = maxf(piece.scale.x, 0.35)
    return {
        "parent_idx": -1,
        "name": piece.name,
        "type": entity_type,
        "transform": {
            "position": _vector3_to_array(piece.position),
            "scale": [scale_value, scale_value, scale_value],
            "rotation": [0, 0, 0, 1],
        },
    }

func _piece_to_geo_entity(piece: Node3D, entity_type: String) -> Dictionary:
    var mesh_data: Dictionary = _piece_box_geo(piece, entity_type == "water")
    var entity: Dictionary = {
        "parent_idx": -1,
        "name": piece.name,
        "type": entity_type,
        "transform": _identity_transform_dict(),
        "geo": mesh_data,
    }
    var movement: Dictionary = _export_movement(piece)
    if not movement.is_empty():
        entity["movement"] = movement
    return entity

func _piece_to_prop_model_entity(piece: Node3D) -> Dictionary:
    var entity: Dictionary = {
        "parent_idx": -1,
        "name": piece.name,
        "type": "model",
        "model": "data/models/nature_kit/tree_pineSmallB.obj",
        "uv_scale": 1.0,
        "ignore_physics": true,
        "transform": {
            "position": _vector3_to_array(piece.position),
            "scale": _vector3_to_array(piece.scale),
            "rotation": [0, 0, 0, 1],
        },
    }
    var movement: Dictionary = _export_movement(piece)
    if not movement.is_empty():
        entity["movement"] = movement
    return entity

func _identity_transform_dict() -> Dictionary:
    return {"position": [0, 0, 0], "scale": [1, 1, 1], "rotation": [0, 0, 0, 1]}

func _export_movement(piece: Node3D) -> Dictionary:
    var movement: Dictionary = _movement_data(piece)
    var type_name: String = str(movement.get("type", "none"))
    if type_name == "none":
        return {}
    var length: float = maxf(float(movement.get("length", 4.0)), 0.1)
    var out: Dictionary = {
        "type": type_name,
        "t0": float(movement.get("t0", 0.0)),
        "length": length,
    }
    match type_name:
        "linear":
            out["p0"] = [0, 0, 0]
            out["p1"] = _vector3_to_array(_array_to_vector3(movement.get("offset", [2.0, 0.0, 0.0]), Vector3(2.0, 0.0, 0.0)))
        "spinner":
            pass
        "pendulum":
            out["theta0"] = deg_to_rad(float(movement.get("theta0", 25.0)))
            out["axis"] = _safe_axis_array(movement)
        "ramp":
            out["theta0"] = float(movement.get("theta0", 25.0))
            out["theta1"] = float(movement.get("theta1", -25.0))
            out["transition_length"] = minf(float(movement.get("transition", 0.5)), length * 0.49)
            out["axis"] = _safe_axis_array(movement)
        _:
            return {}
    return out

func _safe_axis_array(movement: Dictionary) -> Array[float]:
    var axis: Vector3 = _array_to_vector3(movement.get("axis", [0.0, 1.0, 0.0]), Vector3.UP)
    if axis.length_squared() < 0.001:
        axis = Vector3.UP
    axis = axis.normalized()
    return _vector3_to_array(axis)

func _piece_box_geo(piece: Node3D, is_water: bool) -> Dictionary:
    if _has_custom_geometry(piece):
        return _custom_piece_geo(piece, is_water)
    var sx: float = maxf(absf(piece.scale.x), 0.05) * 0.5
    var sy: float = maxf(absf(piece.scale.y), 0.05) * 0.5
    var sz: float = maxf(absf(piece.scale.z), 0.05) * 0.5
    var local_points: Array[Vector3] = [
        Vector3(-sx, -sy, -sz), Vector3(sx, -sy, -sz), Vector3(sx, -sy, sz), Vector3(-sx, -sy, sz),
        Vector3(-sx, sy, -sz), Vector3(sx, sy, -sz), Vector3(sx, sy, sz), Vector3(-sx, sy, sz),
    ]
    var piece_basis: Basis = Basis.from_euler(Vector3(deg_to_rad(piece.rotation_degrees.x), deg_to_rad(piece.rotation_degrees.y), deg_to_rad(piece.rotation_degrees.z)))
    var piece_transform: Transform3D = Transform3D(piece_basis, piece.position)
    var flat_points: Array = []
    for p: Vector3 in local_points:
        var world_p: Vector3 = piece_transform * p
        flat_points.append(world_p.x)
        flat_points.append(world_p.y)
        flat_points.append(world_p.z)
    var top_material: String = "water" if is_water else "ground"
    var side_material: String = "water" if is_water else "wall-side"
    var top_uv: String = "ground" if not is_water else "manual"
    return {
        "p": flat_points,
        "faces": [
            _export_face(top_material, [4, 7, 6, 5], top_uv),
            _export_face(side_material, [0, 1, 2, 3], "wall-side"),
            _export_face(side_material, [0, 4, 5, 1], "wall-side"),
            _export_face(side_material, [1, 5, 6, 2], "wall-side"),
            _export_face(side_material, [2, 6, 7, 3], "wall-side"),
            _export_face(side_material, [3, 7, 4, 0], "wall-side"),
        ],
    }

func _custom_piece_geo(piece: Node3D, is_water: bool) -> Dictionary:
    var points: Array = piece.get_meta("custom_geo_points") as Array
    var flat_points: Array = []
    for value: Variant in points:
        var local_point: Vector3 = _array_to_vector3(value, Vector3.ZERO)
        var world_point: Vector3 = piece.global_transform * local_point
        flat_points.append(world_point.x)
        flat_points.append(world_point.y)
        flat_points.append(world_point.z)
    var faces: Array = _custom_faces_for_piece(piece)
    var materials: Array = piece.get_meta("custom_geo_materials", _default_geo_materials(is_water)) as Array
    var export_faces: Array = []
    for i: int in range(faces.size()):
        var mat_name: String = str(materials[i]) if i < materials.size() else ("water" if is_water else "ground")
        var uv_type: String = "manual" if mat_name == "water" else "ground"
        export_faces.append(_export_face(mat_name, _int_array(faces[i] as Array), uv_type))
    return {"p": flat_points, "faces": export_faces}

func _custom_faces_for_piece(piece: Node3D) -> Array:
    if piece.has_meta("custom_geo_faces"):
        return (piece.get_meta("custom_geo_faces") as Array).duplicate(true)
    return [[4, 7, 6, 5], [0, 1, 2, 3], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]

func _int_array(values: Array) -> Array[int]:
    var out: Array[int] = []
    for value: Variant in values:
        out.append(int(value))
    return out

func _uv_array_for_count(count: int) -> Array:
    var out: Array = []
    for i: int in range(count):
        out.append(0 if i % 2 == 0 else 1)
    return out

func _export_face(material_name: String, idxs: Array[int], uv_gen_type: String) -> Dictionary:
    return {
        "material_name": material_name,
        "idxs": idxs,
        "uvs": _uv_array_for_count(idxs.size() * 2),
        "uv_gen_type": uv_gen_type,
        "water_dir": [0, 0, 0],
    }

func _serialize_editor_level() -> Dictionary:
    var pieces: Array = []
    for child: Node in _pieces_root.get_children():
        var piece: Node3D = child as Node3D
        if piece == null:
            continue
        var piece_data: Dictionary = {
            "name": piece.name,
            "type": piece.get_meta("piece_type", "platform"),
            "position": _vector3_to_array(piece.position),
            "rotation_degrees": _vector3_to_array(piece.rotation_degrees),
            "scale": _vector3_to_array(piece.scale),
            "movement": _movement_data(piece),
        }
        if _has_custom_geometry(piece):
            piece_data["custom_geo_points"] = (piece.get_meta("custom_geo_points") as Array).duplicate(true)
            if piece.has_meta("custom_geo_faces"):
                piece_data["custom_geo_faces"] = (piece.get_meta("custom_geo_faces") as Array).duplicate(true)
            piece_data["custom_geo_materials"] = (piece.get_meta("custom_geo_materials", []) as Array).duplicate(true)
        pieces.append(piece_data)
    return {
        "format": "golfdot-golfedit",
        "version": GOLFEDIT_VERSION,
        "visual_settings": _current_visual_settings(),
        "pieces": pieces,
        "camera": {
            "focus_position": _vector3_to_array(_focus_position),
            "yaw": _yaw,
            "pitch": _pitch,
            "distance": _distance,
        },
    }

func _deserialize_editor_level(data: Dictionary) -> void:
    _loading_level = true
    _clear_pieces()
    _piece_counter = 0
    var pieces: Array = data.get("pieces", []) as Array
    for piece_data_value: Variant in pieces:
        if typeof(piece_data_value) != TYPE_DICTIONARY:
            continue
        var piece_data: Dictionary = piece_data_value as Dictionary
        var piece_type: String = str(piece_data.get("type", "platform"))
        if not _materials.has(piece_type):
            piece_type = "platform"
        var piece: Node3D = _add_piece(piece_type)
        piece.name = str(piece_data.get("name", piece.name))
        piece.position = _array_to_vector3(piece_data.get("position", [0.0, 0.5, 0.0]), piece.position)
        piece.rotation_degrees = _array_to_vector3(piece_data.get("rotation_degrees", [0.0, 0.0, 0.0]), piece.rotation_degrees)
        piece.scale = _array_to_vector3(piece_data.get("scale", [1.0, 1.0, 1.0]), piece.scale)
        if piece_data.has("movement") and typeof(piece_data["movement"]) == TYPE_DICTIONARY:
            piece.set_meta("movement", _normalized_movement_data(piece_data["movement"] as Dictionary))
        if piece_data.has("custom_geo_points") and typeof(piece_data["custom_geo_points"]) == TYPE_ARRAY:
            piece.set_meta("custom_geo_points", (piece_data["custom_geo_points"] as Array).duplicate(true))
            if piece_data.has("custom_geo_faces") and typeof(piece_data["custom_geo_faces"]) == TYPE_ARRAY:
                piece.set_meta("custom_geo_faces", (piece_data["custom_geo_faces"] as Array).duplicate(true))
            piece.set_meta("custom_geo_materials", (piece_data.get("custom_geo_materials", _default_geo_materials(piece_type == "water")) as Array).duplicate(true))
            _apply_custom_geometry_preview(piece)
        _piece_counter = maxi(_piece_counter, _number_suffix(piece.name))
    var visual_data: Dictionary = data.get("visual_settings", {}) as Dictionary
    if not visual_data.is_empty():
        _set_visual_settings(visual_data)
    var camera_data: Dictionary = data.get("camera", {}) as Dictionary
    if not camera_data.is_empty():
        _focus_position = _array_to_vector3(camera_data.get("focus_position", _vector3_to_array(_focus_position)), _focus_position)
        _yaw = float(camera_data.get("yaw", _yaw))
        _pitch = float(camera_data.get("pitch", _pitch))
        _distance = float(camera_data.get("distance", _distance))
        _apply_camera_transform()
    _loading_level = false
    _select_piece(_pieces_root.get_child(_pieces_root.get_child_count() - 1) as Node3D if _pieces_root.get_child_count() > 0 else null)
    _refresh_inspector()

func _vector3_to_array(v: Vector3) -> Array[float]:
    return [v.x, v.y, v.z]

func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
    if not value is Array:
        return fallback
    var arr: Array = value as Array
    if arr.size() < 3:
        return fallback
    return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

func _normalized_movement_data(data: Dictionary) -> Dictionary:
    var movement: Dictionary = _default_movement_data()
    for key: Variant in data.keys():
        movement[key] = data[key]
    var type_name: String = str(movement.get("type", "none"))
    if not MOVEMENT_TYPES.has(type_name):
        movement["type"] = "none"
    movement["length"] = maxf(float(movement.get("length", 4.0)), 0.1)
    movement["t0"] = float(movement.get("t0", 0.0))
    movement["offset"] = _vector3_to_array(_array_to_vector3(movement.get("offset", [2.0, 0.0, 0.0]), Vector3(2.0, 0.0, 0.0)))
    movement["axis"] = _vector3_to_array(_array_to_vector3(movement.get("axis", [0.0, 1.0, 0.0]), Vector3.UP))
    movement["theta0"] = float(movement.get("theta0", 25.0))
    movement["theta1"] = float(movement.get("theta1", -25.0))
    movement["transition"] = float(movement.get("transition", 0.5))
    return movement

func _number_suffix(text: String) -> int:
    var digits: String = ""
    for i: int in range(text.length() - 1, -1, -1):
        var c: String = text.substr(i, 1)
        if not c.is_valid_int():
            break
        digits = c + digits
    return int(digits) if not digits.is_empty() else 0

func _ensure_parent_directory(path: String) -> void:
    var base_dir: String = path.get_base_dir()
    if not base_dir.is_empty() and not DirAccess.dir_exists_absolute(base_dir):
        DirAccess.make_dir_recursive_absolute(base_dir)

func _set_dirty(dirty: bool) -> void:
    _dirty = dirty
    _refresh_dirty_ui()

func _refresh_dirty_ui() -> void:
    if _save_button != null:
        _save_button.text = "Save"
        _save_button.tooltip_text = "Unsaved changes" if _dirty else "Saved"
    if _file_path_edit != null:
        var absolute_path: String = ProjectSettings.globalize_path(_current_file_path)
        _file_path_edit.tooltip_text = ("Unsaved changes in " if _dirty else "Current file: ") + _current_file_path + "\nOn disk: " + absolute_path
    if _reveal_export_folder_button != null:
        _reveal_export_folder_button.tooltip_text = "Open folder for %s\n.level export: %s" % [ProjectSettings.globalize_path(_current_file_path), ProjectSettings.globalize_path(_export_path_from_editor_path(_current_file_path))]

func _update_keyboard_camera(delta: float) -> void:
    var input_dir: Vector3 = Vector3.ZERO
    if Input.is_key_pressed(KEY_UP):
        input_dir.z -= 1.0
    if Input.is_key_pressed(KEY_DOWN):
        input_dir.z += 1.0
    if Input.is_key_pressed(KEY_LEFT):
        input_dir.x -= 1.0
    if Input.is_key_pressed(KEY_RIGHT):
        input_dir.x += 1.0
    if _selected_piece == null or not is_instance_valid(_selected_piece):
        if Input.is_key_pressed(KEY_PAGEUP):
            input_dir.y += 1.0
        if Input.is_key_pressed(KEY_PAGEDOWN):
            input_dir.y -= 1.0

    if input_dir == Vector3.ZERO:
        return

    input_dir = input_dir.normalized()
    var camera_basis: Basis = _camera.global_transform.basis
    var right: Vector3 = camera_basis.x
    var forward: Vector3 = -camera_basis.z
    forward.y = 0.0
    if forward.length_squared() > 0.001:
        forward = forward.normalized()
    var movement: Vector3 = (right * input_dir.x) + (forward * -input_dir.z) + (Vector3.UP * input_dir.y)
    _focus_position += movement * MOVE_SPEED * delta
    _apply_camera_transform()

func _pan_camera(relative: Vector2) -> void:
    var camera_basis: Basis = _camera.global_transform.basis
    var right: Vector3 = camera_basis.x
    var up: Vector3 = camera_basis.y
    _focus_position += ((right * -relative.x) + (up * relative.y)) * PAN_SENSITIVITY * (_distance * 0.15)
    _apply_camera_transform()

func _apply_camera_transform() -> void:
    _camera_rig.position = _focus_position
    _camera_rig.rotation = Vector3(_pitch, _yaw, 0.0)
    _camera.position = Vector3(0.0, 0.0, _distance)

func _is_pointer_over_editor_panel(pos: Vector2) -> bool:
    var viewport_size: Vector2 = get_viewport().get_visible_rect().size
    return pos.y <= 64.0 or pos.y >= viewport_size.y - 52.0 or pos.x <= 312.0 or pos.x >= viewport_size.x - 284.0

func _on_placeholder_action(action_name: String) -> void:
    _set_status("%s is reserved for a later phase." % action_name)

func _on_back_pressed() -> void:
    get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _set_status(text: String) -> void:
    _status_label.text = text
