extends Control
## First-launch name prompt. The player must choose a display name before they
## can reach the main menu; this name is stored via PlayerProfile and will become
## their identity for the highscore boards and (later) multiplayer sessions.
##
## This same scene doubles as the "change name" screen — it pre-fills any existing
## name and, on submit, always returns to the main menu.

const MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var _line_edit: LineEdit = $CenterContainer/VBox/NameEdit
@onready var _submit_btn: Button = $CenterContainer/VBox/SubmitBtn
@onready var _hint: Label = $CenterContainer/VBox/Hint

func _ready() -> void:
    _line_edit.max_length = PlayerProfile.MAX_NAME_LENGTH
    _line_edit.text = PlayerProfile.get_player_name()  # pre-fill when editing
    _line_edit.text_changed.connect(_on_text_changed)
    _line_edit.text_submitted.connect(_on_text_submitted)

    _hint.text = "1-%d characters" % PlayerProfile.MAX_NAME_LENGTH

    _submit_btn.pressed.connect(_on_submit_pressed)

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
