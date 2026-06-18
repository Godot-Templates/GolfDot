extends Node
## Validates the restructured menu navigation: the main menu exposes Level Select,
## Highscores and Credits; level-select and credits return to the main menu; and
## the supporting PlayerProfile / GolfHighscores data models behave.

const MENU_SCENE := "res://scenes/main_menu.tscn"

func _find_button(root: Node, text: String) -> Button:
    var stack: Array = [root]
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if n is Button and (n as Button).text == text:
            return n as Button
        for c in n.get_children():
            stack.append(c)
    return null

func test_main_menu_has_core_buttons() -> void:
    # A name must exist or the menu redirects to name entry instead of building UI.
    var had_name: bool = PlayerProfile.has_player_name()
    var prev: String = PlayerProfile.get_player_name()
    PlayerProfile.set_player_name("Tester")

    var inst: Node = load(MENU_SCENE).instantiate()
    inst._ready()

    assert(_find_button(inst, "Level Select") != null, "main menu should have Level Select")
    assert(_find_button(inst, "Highscores") != null, "main menu should have Highscores")
    assert(_find_button(inst, "Credits") != null, "main menu should have Credits")
    inst.queue_free()

    # Restore the prior profile state so tests don't clobber a real player's name.
    if had_name:
        PlayerProfile.set_player_name(prev)
    else:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.SAVE_PATH))

func test_level_select_back_button_wired_to_menu() -> void:
    var inst: Node = load("res://scenes/level_select.tscn").instantiate()
    inst._ready()  # build the code-driven UI without requiring the live tree

    var back: Button = _find_button(inst, "Back")
    assert(back != null, "level_select should have a Back button")
    var conns: Array = back.pressed.get_connections()
    assert(conns.size() == 1, "Back button should have exactly one pressed handler")
    assert(conns[0]["callable"].get_method() == "_on_back_pressed", "wired to _on_back_pressed")
    # Credits moved out of level select onto the main menu.
    assert(_find_button(inst, "Credits") == null, "Credits should no longer live in level select")
    inst.queue_free()

func test_player_profile_sanitize_and_validation() -> void:
    assert(PlayerProfile.sanitize("  Ace  ") == "Ace", "should trim surrounding whitespace")
    assert(PlayerProfile.sanitize("") == "", "empty is invalid")
    assert(not PlayerProfile.is_valid(""), "empty name is not valid")
    assert(PlayerProfile.is_valid("Bob"), "normal name is valid")
    var long_name: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    assert(PlayerProfile.sanitize(long_name).length() == PlayerProfile.MAX_NAME_LENGTH,
        "over-long names are clamped to MAX_NAME_LENGTH")

func test_highscores_submit_orders_ascending() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(GolfHighscores.SAVE_PATH))

    GolfHighscores.submit_hole_score(99, "Slow", 8)
    var rank: int = GolfHighscores.submit_hole_score(99, "Fast", 2)
    GolfHighscores.submit_hole_score(99, "Mid", 5)

    var board: Array = GolfHighscores.get_hole_scores(99)
    assert(board.size() == 3, "three entries recorded")
    assert(board[0]["name"] == "Fast", "lowest strokes ranks first")
    assert(rank == 1, "Fast should report rank 1 when submitted")

    GolfHighscores.submit_course_score("Champ", 54)
    var course: Array = GolfHighscores.get_course_scores()
    assert(course.size() >= 1 and course[0]["name"] == "Champ", "course total recorded")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(GolfHighscores.SAVE_PATH))

func test_credits_scene_has_back_button_and_links() -> void:
    var inst: Node = load("res://scenes/credits.tscn").instantiate()
    inst._ready()  # build the code-driven UI without requiring the live tree

    var back: Button = _find_button(inst, "Back")
    assert(back != null, "Back button should exist in credits")
    assert(back.pressed.get_connections().size() == 1, "Back button should be wired")

    # Verify attribution link to Open-Golf is present
    var has_open_golf: bool = false
    var stack: Array = [inst]
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if n is LinkButton and "Open-Golf" in (n as LinkButton).text:
            has_open_golf = true
        for c in n.get_children():
            stack.append(c)
    assert(has_open_golf, "Credits should include an Open-Golf attribution link")
    inst.queue_free()
