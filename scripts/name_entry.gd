extends Control
## First-launch name prompt. The player must choose a display name before they
## can reach the main menu; this name is stored via PlayerProfile and will become
## their identity for the highscore boards and (later) multiplayer sessions.
##
## This same scene doubles as the "change name" screen — it pre-fills any existing
## name and, on submit, always returns to the main menu.

const MENU_SCENE := "res://scenes/main_menu.tscn"

var _line_edit: LineEdit
var _submit_btn: Button
var _hint: Label

func _ready() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.12, 0.16, 0.22)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 16)
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(vbox)

    var title := Label.new()
    title.text = "GOLFDOT"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 40)
    vbox.add_child(title)

    var prompt := Label.new()
    prompt.text = "What should we call you?"
    prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    prompt.add_theme_font_size_override("font_size", 20)
    vbox.add_child(prompt)

    _line_edit = LineEdit.new()
    _line_edit.placeholder_text = "Your name"
    _line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _line_edit.max_length = PlayerProfile.MAX_NAME_LENGTH
    _line_edit.custom_minimum_size = Vector2(280, 44)
    _line_edit.text = PlayerProfile.get_player_name()  # pre-fill when editing
    _line_edit.text_changed.connect(_on_text_changed)
    _line_edit.text_submitted.connect(_on_text_submitted)
    vbox.add_child(_line_edit)

    _hint = Label.new()
    _hint.text = "1-%d characters" % PlayerProfile.MAX_NAME_LENGTH
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hint.add_theme_font_size_override("font_size", 14)
    _hint.modulate = Color(0.7, 0.8, 0.9)
    vbox.add_child(_hint)

    _submit_btn = Button.new()
    _submit_btn.text = "Continue"
    _submit_btn.custom_minimum_size = Vector2(280, 44)
    _submit_btn.pressed.connect(_on_submit_pressed)
    vbox.add_child(_submit_btn)

    _refresh_validity()
    _line_edit.grab_focus()

func _on_text_changed(_new_text: String) -> void:
    _refresh_validity()

func _on_text_submitted(_new_text: String) -> void:
    _on_submit_pressed()

func _on_submit_pressed() -> void:
    if not PlayerProfile.is_valid(_line_edit.text):
        _refresh_validity()
        return
    if PlayerProfile.set_player_name(_line_edit.text):
        get_tree().change_scene_to_file(MENU_SCENE)

## Enable/disable the Continue button based on whether the current text is a valid
## name, so the player can't proceed with an empty entry.
func _refresh_validity() -> void:
    _submit_btn.disabled = not PlayerProfile.is_valid(_line_edit.text)
