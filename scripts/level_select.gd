class_name LevelSelect
extends Control
## Main-menu-style level select with live per-hole presence counts.

const LEVEL_COUNT := 20
const PLAY_SCENE := "res://scenes/golf_play.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var _player_labels: Dictionary = {}
var _presence: Node = null
var _total_label: Label
var _status_label: Label

func _ready() -> void:
    theme = MenuThemeBuilder.build()
    _presence = get_node_or_null("/root/MultiplayerManager")
    if _presence != null:
        if _presence.has_method("set_current_hole"):
            _presence.call("set_current_hole", 0)
        if _presence.has_signal("presence_counts_changed"):
            var counts_signal: Signal = _presence.get("presence_counts_changed")
            if not counts_signal.is_connected(_on_presence_counts_changed):
                counts_signal.connect(_on_presence_counts_changed)
    _build_ui()
    _refresh_presence_counts()

func _build_ui() -> void:
    var base: ColorRect = ColorRect.new()
    base.color = Color(0.1, 0.14, 0.18, 1)
    base.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(base)

    var background: MenuBackground = MenuBackground.new()
    background.set_anchors_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)

    var dim: ColorRect = ColorRect.new()
    dim.color = Color(0.04, 0.08, 0.10, 0.56)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(dim)

    var safe: MarginContainer = MarginContainer.new()
    safe.set_anchors_preset(Control.PRESET_FULL_RECT)
    safe.add_theme_constant_override("margin_left", 24)
    safe.add_theme_constant_override("margin_top", 20)
    safe.add_theme_constant_override("margin_right", 24)
    safe.add_theme_constant_override("margin_bottom", 20)
    add_child(safe)

    var vbox: VBoxContainer = VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 12)
    safe.add_child(vbox)

    var title: Label = Label.new()
    title.text = "⛳  SELECT HOLE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
    title.add_theme_constant_override("outline_size", 6)
    title.add_theme_font_size_override("font_size", 40)
    vbox.add_child(title)

    _total_label = Label.new()
    _total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _total_label.add_theme_color_override("font_color", Color(0.86, 0.93, 0.8, 1))
    _total_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
    _total_label.add_theme_constant_override("outline_size", 4)
    _total_label.add_theme_font_size_override("font_size", 16)
    _total_label.text = _total_text()
    vbox.add_child(_total_label)

    var panel: PanelContainer = PanelContainer.new()
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_theme_stylebox_override("panel", _panel_box())
    vbox.add_child(panel)

    var panel_margin: MarginContainer = MarginContainer.new()
    panel_margin.add_theme_constant_override("margin_left", 12)
    panel_margin.add_theme_constant_override("margin_top", 12)
    panel_margin.add_theme_constant_override("margin_right", 12)
    panel_margin.add_theme_constant_override("margin_bottom", 12)
    panel.add_child(panel_margin)

    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel_margin.add_child(scroll)

    var list: VBoxContainer = VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 10)
    scroll.add_child(list)

    for i: int in range(1, LEVEL_COUNT + 1):
        list.add_child(_make_level_button(i))

    var footer: HBoxContainer = HBoxContainer.new()
    footer.add_theme_constant_override("separation", 12)
    vbox.add_child(footer)

    _status_label = Label.new()
    _status_label.text = "Active players update live"
    _status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _status_label.add_theme_color_override("font_color", Color(0.72, 0.84, 0.72))
    _status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
    _status_label.add_theme_constant_override("outline_size", 3)
    footer.add_child(_status_label)

    var back_btn: Button = Button.new()
    back_btn.text = "Back"
    back_btn.custom_minimum_size = Vector2(160, 44)
    back_btn.pressed.connect(_on_back_pressed)
    footer.add_child(back_btn)

func _make_level_button(idx: int) -> Button:
    var btn: Button = Button.new()
    btn.text = ""
    btn.custom_minimum_size = Vector2(0, 82)
    btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    btn.pressed.connect(_on_level_pressed.bind(idx))

    var row: HBoxContainer = HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.set_anchors_preset(Control.PRESET_FULL_RECT)
    row.offset_left = 16
    row.offset_top = 8
    row.offset_right = -16
    row.offset_bottom = -8
    row.add_theme_constant_override("separation", 16)
    btn.add_child(row)

    var info: VBoxContainer = VBoxContainer.new()
    info.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(info)

    var title: Label = Label.new()
    title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    title.text = "Hole %02d" % idx
    title.add_theme_font_size_override("font_size", 22)
    info.add_child(title)

    var best: int = GolfScores.get_best(idx)
    var best_str: String = "Best --" if best < 0 else "Best %d" % best
    var detail: Label = Label.new()
    detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
    detail.text = "Par %d   ·   %s" % [GolfScores.get_par(idx), best_str]
    detail.add_theme_font_size_override("font_size", 14)
    detail.add_theme_color_override("font_color", Color(0.86, 0.95, 0.86))
    info.add_child(detail)

    var active: Label = Label.new()
    active.mouse_filter = Control.MOUSE_FILTER_IGNORE
    active.custom_minimum_size = Vector2(150, 0)
    active.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    active.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    active.add_theme_font_size_override("font_size", 16)
    active.add_theme_color_override("font_color", Color(0.96, 0.88, 0.34))
    active.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
    active.add_theme_constant_override("outline_size", 3)
    row.add_child(active)
    _player_labels[idx] = active

    return btn

func _total_text() -> String:
    var total_par: int = 0
    for i: int in range(1, LEVEL_COUNT + 1):
        total_par += GolfScores.get_par(i)
    var total_best: int = GolfScores.get_total_best()
    if total_best >= 0:
        return "Total: Par %d  —  Best %d  (%+d)" % [total_par, total_best, total_best - total_par]
    return "Total: Par %d  —  Best --" % total_par

func _refresh_presence_counts() -> void:
    var counts: Dictionary = {}
    if _presence != null and _presence.has_method("get_level_counts"):
        counts = _presence.call("get_level_counts")
    _on_presence_counts_changed(counts)

func _on_presence_counts_changed(counts: Dictionary) -> void:
    for i: int in range(1, LEVEL_COUNT + 1):
        var label: Label = _player_labels.get(i, null)
        if label == null:
            continue
        var count: int = int(counts.get(i, 0))
        label.text = _players_text(count)

func _players_text(count: int) -> String:
    if count <= 0:
        return ""
    return "1 player online" if count == 1 else "%d players online" % count

func _panel_box() -> StyleBoxFlat:
    var sb: StyleBoxFlat = StyleBoxFlat.new()
    sb.bg_color = Color(0.02, 0.05, 0.04, 0.52)
    sb.border_color = Color(0.86, 0.93, 0.80, 0.28)
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(14)
    sb.shadow_color = Color(0, 0, 0, 0.35)
    sb.shadow_size = 8
    sb.shadow_offset = Vector2(0, 3)
    return sb

func _on_back_pressed() -> void:
    get_tree().change_scene_to_file(MENU_SCENE)

func _on_level_pressed(idx: int) -> void:
    var packed: PackedScene = load(PLAY_SCENE)
    var inst: Node = packed.instantiate()
    inst.set("level_path", "res://assets/levels/level-%d.level" % idx)
    var tree: SceneTree = get_tree()
    tree.root.add_child(inst)
    tree.current_scene.queue_free()
    tree.current_scene = inst
