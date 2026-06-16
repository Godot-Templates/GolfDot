extends Control
## Simple level-select menu: a grid of buttons (one per ported Open-Golf hole)
## that launches golf_play.tscn on the chosen level.

const LEVEL_COUNT := 20
const PLAY_SCENE := "res://scenes/golf_play.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"

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
    center.add_child(vbox)

    var title := Label.new()
    title.text = "GOLFDOT — Select Hole"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 32)
    vbox.add_child(title)

    var grid := GridContainer.new()
    grid.columns = 5
    grid.add_theme_constant_override("h_separation", 10)
    grid.add_theme_constant_override("v_separation", 10)
    vbox.add_child(grid)

    for i in range(1, LEVEL_COUNT + 1):
        var btn := Button.new()
        var best := GolfScores.get_best(i)
        var best_str := "best --" if best < 0 else "best %d" % best
        btn.text = "Hole %d\nPar %d\n%s" % [i, GolfScores.get_par(i), best_str]
        btn.custom_minimum_size = Vector2(96, 72)
        btn.pressed.connect(_on_level_pressed.bind(i))
        grid.add_child(btn)

    var credits_btn := Button.new()
    credits_btn.text = "Credits"
    credits_btn.custom_minimum_size = Vector2(0, 44)
    credits_btn.pressed.connect(_on_credits_pressed)
    vbox.add_child(credits_btn)

func _on_credits_pressed() -> void:
    get_tree().change_scene_to_file(CREDITS_SCENE)

func _on_level_pressed(idx: int) -> void:
    var packed: PackedScene = load(PLAY_SCENE)
    var inst := packed.instantiate()
    inst.set("level_path", "res://assets/levels/level-%d.level" % idx)
    var tree := get_tree()
    tree.root.add_child(inst)
    tree.current_scene.queue_free()
    tree.current_scene = inst
