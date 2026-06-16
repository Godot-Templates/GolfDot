extends Control
## Credits / attribution screen. Built in code to match level_select.gd's style.
## Golfdot began as a Godot port of mgerdes' Open-Golf; this screen credits that
## work and the third-party assets it brought along.

const SELECT_SCENE := "res://scenes/level_select.tscn"

const LINK_COLOR := Color(0.55, 0.75, 1.0)
const LINK_HOVER_COLOR := Color(0.75, 0.88, 1.0)

const CREDITS := [
    {"role": "Original game", "name": "Open-Golf by mgerdes", "url": "https://github.com/mgerdes/Open-Golf"},
    {"role": "Assets", "name": "Nature Kit by Kenney", "url": "https://kenney.nl/assets/nature-kit"},
    {"role": "Godot port", "name": "Godot Template Team", "url": "https://github.com/Godot-Templates"},
]

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
    title.text = "GOLFDOT — Credits"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 32)
    vbox.add_child(title)

    var intro := Label.new()
    intro.text = "A Godot port of Open-Golf. Thanks to everyone whose work made it possible."
    intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    intro.custom_minimum_size = Vector2(520, 0)
    vbox.add_child(intro)

    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 24)
    grid.add_theme_constant_override("v_separation", 10)
    vbox.add_child(grid)

    for entry in CREDITS:
        var role := Label.new()
        role.text = entry["role"]
        role.add_theme_font_size_override("font_size", 18)
        role.modulate = Color(0.7, 0.8, 0.9)
        grid.add_child(role)

        grid.add_child(_make_link(entry["name"], entry["url"]))

    var back := Button.new()
    back.text = "Back"
    back.custom_minimum_size = Vector2(160, 44)
    back.pressed.connect(_on_back_pressed)
    vbox.add_child(back)

## Build a hyperlink whose underline is a real 2px rule rather than the
## LinkButton's built-in 1px underline, which can vanish on certain rows under
## the project's fractional canvas_items scaling.
func _make_link(text: String, url: String) -> Control:
    var cell := VBoxContainer.new()
    cell.add_theme_constant_override("separation", 1)
    # Shrink the cell to the text width so the underline hugs the link.
    cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

    var link := LinkButton.new()
    link.text = text
    link.uri = url
    link.underline = LinkButton.UNDERLINE_MODE_NEVER
    link.add_theme_font_size_override("font_size", 18)
    link.add_theme_color_override("font_color", LINK_COLOR)
    link.add_theme_color_override("font_hover_color", LINK_HOVER_COLOR)
    cell.add_child(link)

    var rule := ColorRect.new()
    rule.color = LINK_COLOR
    rule.custom_minimum_size = Vector2(0, 2)
    rule.size_flags_horizontal = Control.SIZE_FILL
    cell.add_child(rule)
    return cell

func _on_back_pressed() -> void:
    get_tree().change_scene_to_file(SELECT_SCENE)
