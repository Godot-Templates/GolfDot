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

func _spacer(height: int) -> Control:
    var s := Control.new()
    s.custom_minimum_size = Vector2(0, height)
    return s

func _goto(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)
