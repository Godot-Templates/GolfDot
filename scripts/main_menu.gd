extends Control
## Top-level menu and the game's main scene. The layout (panning 3D backdrop,
## title, buttons) lives declaratively in main_menu.tscn; this script only handles
## the dynamic bits: the first-launch name gate, the golf button theme, the
## personalized greeting, and routing button presses to other scenes.
##
## Boot gate: on first launch (no stored PlayerProfile name) this scene forwards
## straight to the name-entry screen, so the player always has an identity before
## they reach the menu.

const NAME_ENTRY_SCENE := "res://scenes/name_entry.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"
const SKIN_SHOP_SCENE := "res://scenes/skin_shop.tscn"
const HIGHSCORES_SCENE := "res://scenes/highscores.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"

func _ready() -> void:
    # First-launch gate: force name entry before showing the menu.
    if not PlayerProfile.has_player_name():
        call_deferred("_goto", NAME_ENTRY_SCENE)
        return

    var backdrop: Node = get_node_or_null("/root/MenuBackdrop")
    if backdrop != null and backdrop.has_method("show_for_menu"):
        backdrop.call("show_for_menu", Color(0.06, 0.10, 0.14, 0.45))

    # Golf-themed fairway buttons; inherited by every Button under this Control.
    theme = MenuThemeBuilder.build()

    var greeting: Label = $Center/VBox/Greeting
    greeting.text = "Welcome, %s" % PlayerProfile.get_player_name()

# --- Button handlers (wired via signal connections in main_menu.tscn) ---------

func _on_level_select_pressed() -> void:
    _goto(LEVEL_SELECT_SCENE)

func _on_skin_shop_pressed() -> void:
    _goto(SKIN_SHOP_SCENE)

func _on_highscores_pressed() -> void:
    _goto(HIGHSCORES_SCENE)

func _on_change_name_pressed() -> void:
    _goto(NAME_ENTRY_SCENE)

func _on_credits_pressed() -> void:
    _goto(CREDITS_SCENE)

func _goto(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)
