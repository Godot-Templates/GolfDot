extends Control
## Top-level menu and the game's main scene. Routes the player to Level Select or
## Highscores from the center, with Credits tucked into the bottom-right corner.
##
## Boot gate: on first launch (no stored PlayerProfile name) this scene forwards
## straight to the name-entry screen, so the player always has an identity before
## they reach the menu.

const NAME_ENTRY_SCENE := "res://scenes/name_entry.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"
const HIGHSCORES_SCENE := "res://scenes/highscores.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"

# Top-5 overall board shown in the corner of the menu.
var _top_list: VBoxContainer

func _ready() -> void:
    # First-launch gate: force name entry before showing the menu.
    if not PlayerProfile.has_player_name():
        call_deferred("_goto", NAME_ENTRY_SCENE)
        return

    var bg := ColorRect.new()
    bg.color = Color(0.12, 0.16, 0.22)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 18)
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(vbox)

    var title := Label.new()
    title.text = "GOLFDOT"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 48)
    vbox.add_child(title)

    var greeting := Label.new()
    greeting.text = "Welcome, %s" % PlayerProfile.get_player_name()
    greeting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    greeting.add_theme_font_size_override("font_size", 18)
    greeting.modulate = Color(0.7, 0.8, 0.9)
    vbox.add_child(greeting)

    vbox.add_child(_spacer(8))

    var level_btn := Button.new()
    level_btn.text = "Level Select"
    level_btn.custom_minimum_size = Vector2(260, 52)
    level_btn.pressed.connect(_goto.bind(LEVEL_SELECT_SCENE))
    vbox.add_child(level_btn)

    var highscores_btn := Button.new()
    highscores_btn.text = "Highscores"
    highscores_btn.custom_minimum_size = Vector2(260, 52)
    highscores_btn.pressed.connect(_goto.bind(HIGHSCORES_SCENE))
    vbox.add_child(highscores_btn)

    var change_name_btn := Button.new()
    change_name_btn.text = "Change Name"
    change_name_btn.flat = true
    change_name_btn.custom_minimum_size = Vector2(260, 36)
    change_name_btn.add_theme_font_size_override("font_size", 14)
    change_name_btn.pressed.connect(_goto.bind(NAME_ENTRY_SCENE))
    vbox.add_child(change_name_btn)

    # Credits sits in the bottom-right corner, separate from the centered column.
    var credits_btn := Button.new()
    credits_btn.text = "Credits"
    credits_btn.custom_minimum_size = Vector2(120, 40)
    credits_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    credits_btn.offset_left = -136
    credits_btn.offset_top = -56
    credits_btn.offset_right = -16
    credits_btn.offset_bottom = -16
    credits_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    credits_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
    credits_btn.pressed.connect(_goto.bind(CREDITS_SCENE))
    add_child(credits_btn)

    _build_top_panel()

## A compact "Top Golfers" board pinned to the top-left of the menu, showing the
## global best players by lowest total strokes. Backed by the Leaderboard
## autoload (durable, shared); refreshes live as scores arrive.
func _build_top_panel() -> void:
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
    panel.offset_left = 16
    panel.offset_top = 16
    panel.offset_right = 256
    panel.grow_horizontal = Control.GROW_DIRECTION_END
    panel.grow_vertical = Control.GROW_DIRECTION_END

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 6)
    panel.add_child(vbox)

    var header := Label.new()
    header.text = "Top Golfers"
    header.add_theme_font_size_override("font_size", 18)
    vbox.add_child(header)

    var sub := Label.new()
    sub.text = "lowest total across all holes"
    sub.add_theme_font_size_override("font_size", 11)
    sub.modulate = Color(0.7, 0.8, 0.9)
    vbox.add_child(sub)

    _top_list = VBoxContainer.new()
    _top_list.add_theme_constant_override("separation", 3)
    vbox.add_child(_top_list)

    add_child(panel)

    var lb := get_node_or_null("/root/Leaderboard")
    if lb != null and not lb.updated.is_connected(_refresh_top):
        lb.updated.connect(_refresh_top)
    _refresh_top()

func _refresh_top() -> void:
    if _top_list == null:
        return
    for c in _top_list.get_children():
        c.queue_free()

    var lb := get_node_or_null("/root/Leaderboard")
    if lb == null:
        return
    var board: Array = lb.get_overall_board()
    if board.is_empty():
        var empty := Label.new()
        empty.text = "No scores yet"
        empty.add_theme_font_size_override("font_size", 13)
        empty.modulate = Color(0.7, 0.8, 0.9)
        _top_list.add_child(empty)
        return

    var me := PlayerProfile.get_player_name()
    var shown: int = mini(board.size(), 5)
    for i in range(shown):
        var entry: Dictionary = board[i]
        var label := Label.new()
        var is_me: bool = String(entry["name"]) == me
        label.text = "%d. %s — %d" % [i + 1, String(entry["name"]), int(entry["strokes"])]
        label.add_theme_font_size_override("font_size", 14)
        if is_me:
            label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
        _top_list.add_child(label)

func _spacer(height: int) -> Control:
    var s := Control.new()
    s.custom_minimum_size = Vector2(0, height)
    return s

func _goto(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)
