class_name HighscoresScreen
extends Control
## Main-menu-style highscores browser: select a hole or Overall on the left,
## then view the top 20 board on the right.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const LEVEL_COUNT := 20

var _board_title: Label
var _board_list: VBoxContainer
var _selector_list: VBoxContainer
var _overall_slot: VBoxContainer
var _status: Label
var _selected_level: int = 0 # 0 = overall, 1..20 = hole board

func _ready() -> void:
    theme = MenuThemeBuilder.build()
    _build_ui()
    var lb: Node = get_node_or_null("/root/Leaderboard")
    if lb != null and lb.has_signal("updated"):
        var updated_signal: Signal = lb.get("updated")
        if not updated_signal.is_connected(_refresh_all):
            updated_signal.connect(_refresh_all)
    _select_overall()

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
    dim.color = Color(0.04, 0.08, 0.10, 0.58)
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
    title.text = "HIGHSCORES"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
    title.add_theme_constant_override("outline_size", 6)
    title.add_theme_font_size_override("font_size", 40)
    vbox.add_child(title)

    _status = Label.new()
    _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status.add_theme_color_override("font_color", Color(0.86, 0.93, 0.8, 1))
    _status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
    _status.add_theme_constant_override("outline_size", 4)
    _status.add_theme_font_size_override("font_size", 14)
    vbox.add_child(_status)

    var body: HBoxContainer = HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 14)
    vbox.add_child(body)

    body.add_child(_make_selector_panel())
    body.add_child(_make_board_panel())

    var footer: HBoxContainer = HBoxContainer.new()
    footer.add_theme_constant_override("separation", 12)
    vbox.add_child(footer)

    var footer_spacer: Control = Control.new()
    footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer.add_child(footer_spacer)

    var back: Button = Button.new()
    back.text = "Back"
    back.custom_minimum_size = Vector2(160, 44)
    back.pressed.connect(_on_back_pressed)
    footer.add_child(back)

func _make_selector_panel() -> Control:
    var panel: PanelContainer = PanelContainer.new()
    panel.custom_minimum_size = Vector2(430, 0)
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_theme_stylebox_override("panel", _panel_box())

    var margin: MarginContainer = MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    panel.add_child(margin)

    var vbox: VBoxContainer = VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 10)
    margin.add_child(vbox)

    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    vbox.add_child(scroll)

    _selector_list = VBoxContainer.new()
    _selector_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _selector_list.add_theme_constant_override("separation", 10)
    scroll.add_child(_selector_list)

    _overall_slot = VBoxContainer.new()
    _overall_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(_overall_slot)
    _refresh_selector()
    return panel

func _make_board_panel() -> Control:
    var panel: PanelContainer = PanelContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_theme_stylebox_override("panel", _panel_box())

    var margin: MarginContainer = MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 16)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_right", 16)
    margin.add_theme_constant_override("margin_bottom", 14)
    panel.add_child(margin)

    var vbox: VBoxContainer = VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 10)
    margin.add_child(vbox)

    _board_title = Label.new()
    _board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _board_title.add_theme_font_size_override("font_size", 24)
    _board_title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.34))
    _board_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
    _board_title.add_theme_constant_override("outline_size", 3)
    vbox.add_child(_board_title)

    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    vbox.add_child(scroll)

    _board_list = VBoxContainer.new()
    _board_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _board_list.add_theme_constant_override("separation", 6)
    scroll.add_child(_board_list)
    return panel

func _refresh_all() -> void:
    _refresh_selector()
    _refresh_board()

func _refresh_selector() -> void:
    if _selector_list == null or _overall_slot == null:
        return
    for child: Node in _selector_list.get_children():
        child.queue_free()
    for child: Node in _overall_slot.get_children():
        child.queue_free()
    for i: int in range(1, LEVEL_COUNT + 1):
        _selector_list.add_child(_make_hole_button(i))
    _overall_slot.add_child(_make_overall_button())

func _make_hole_button(idx: int) -> Button:
    var your_best: int = GolfScores.get_best(idx)
    var your_text: String = "Your best: --" if your_best < 0 else "Your best: %d" % your_best
    var global_text: String = _global_best_text(idx)
    var btn: Button = _make_selector_button("Hole %02d" % idx, "Par %d   ·   Best: %s" % [GolfScores.get_par(idx), global_text], your_text)
    btn.pressed.connect(_select_hole.bind(idx))
    return btn

func _make_overall_button() -> Button:
    var total: int = GolfScores.get_total_best()
    var your_text: String = "Your best: --" if total < 0 else "Your best: %d" % total
    var global_text: String = _global_best_text(0)
    var btn: Button = _make_selector_button("Overall", "All 20 holes   ·   Best: %s" % global_text, your_text)
    btn.pressed.connect(_select_overall)
    return btn

func _global_best_text(level: int) -> String:
    var lb: Node = get_node_or_null("/root/Leaderboard")
    if lb == null:
        return "--"
    var board: Array = lb.call("get_overall_board") if level == 0 else lb.call("get_hole_board", level)
    if board.is_empty():
        return "--"
    var top_entry: Dictionary = board[0]
    return str(int(top_entry.get("strokes", -1)))

func _make_selector_button(title_text: String, detail_text: String, right_text: String) -> Button:
    var btn: Button = Button.new()
    btn.text = ""
    btn.custom_minimum_size = Vector2(0, 82)
    btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var row: HBoxContainer = HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.set_anchors_preset(Control.PRESET_FULL_RECT)
    row.offset_left = 16
    row.offset_top = 8
    row.offset_right = -16
    row.offset_bottom = -8
    row.add_theme_constant_override("separation", 12)
    btn.add_child(row)

    var info: VBoxContainer = VBoxContainer.new()
    info.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(info)

    var title: Label = Label.new()
    title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    title.text = title_text
    title.add_theme_font_size_override("font_size", 20)
    info.add_child(title)

    var detail: Label = Label.new()
    detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
    detail.text = detail_text
    detail.add_theme_font_size_override("font_size", 13)
    detail.add_theme_color_override("font_color", Color(0.86, 0.95, 0.86))
    info.add_child(detail)

    var right: Label = Label.new()
    right.mouse_filter = Control.MOUSE_FILTER_IGNORE
    right.custom_minimum_size = Vector2(128, 0)
    right.text = right_text
    right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    right.add_theme_font_size_override("font_size", 14)
    right.add_theme_color_override("font_color", Color(0.96, 0.88, 0.34))
    row.add_child(right)
    return btn

func _select_hole(level: int) -> void:
    _selected_level = level
    _refresh_board()

func _select_overall() -> void:
    _selected_level = 0
    _refresh_board()

func _refresh_board() -> void:
    if _board_list == null:
        return
    for child: Node in _board_list.get_children():
        child.queue_free()

    var lb: Node = get_node_or_null("/root/Leaderboard")
    if lb == null:
        _status.text = "Leaderboard unavailable."
        return

    _status.text = "Online — global top 20" if lb.call("is_online") else "Local scores shown until the global board connects"

    var board: Array = []
    if _selected_level == 0:
        _board_title.text = "Overall Top 20"
        board = lb.call("get_overall_board")
    else:
        _board_title.text = "Hole %02d Top 20" % _selected_level
        board = lb.call("get_hole_board", _selected_level)

    if board.is_empty():
        var empty: Label = Label.new()
        empty.text = "No scores yet."
        empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _board_list.add_child(empty)
        return

    var me: String = PlayerProfile.get_player_name()
    for i: int in range(board.size()):
        var entry: Dictionary = board[i]
        _board_list.add_child(_make_score_row(i + 1, String(entry["name"]), int(entry["strokes"]), String(entry["name"]) == me))

func _make_score_row(rank: int, player_name: String, strokes: int, is_me: bool) -> Control:
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)

    var rank_label: Label = Label.new()
    rank_label.text = "%02d" % rank
    rank_label.custom_minimum_size = Vector2(42, 0)
    row.add_child(rank_label)

    var name_label: Label = Label.new()
    name_label.text = player_name + (" (you)" if is_me else "")
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(name_label)

    var score_label: Label = Label.new()
    score_label.text = "%d strokes" % strokes
    score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    row.add_child(score_label)

    if is_me:
        var highlight: Color = Color(0.55, 1.0, 0.6)
        rank_label.add_theme_color_override("font_color", highlight)
        name_label.add_theme_color_override("font_color", highlight)
        score_label.add_theme_color_override("font_color", highlight)
    return row

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
