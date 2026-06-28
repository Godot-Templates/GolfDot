class_name SkinShop
extends Control
## Menu screen for selecting unlockable golf-ball colors.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const TOTAL_BEST_GOLD_REQUIREMENT := 60
const HOLE_IN_ONE_SKIN_HOLE := 5
const HOLE_IN_ONE_SKIN_STROKES := 1
const GOLD_STRIPE_SHADER_CODE := """
shader_type spatial;

varying vec3 local_normal;

void vertex() {
    local_normal = NORMAL;
}

void fragment() {
    vec3 gold = vec3(1.0, 0.78, 0.12);
    vec3 black = vec3(0.015, 0.012, 0.01);
    float stripe = step(abs(normalize(local_normal).y), 0.34);
    ALBEDO = mix(gold, black, stripe);
    ROUGHNESS = 0.34;
    METALLIC = 0.08;
}
"""

const SKINS: Array[Dictionary] = [
    {"id": "white", "name": "White", "color": Color.WHITE, "description": "Default ball", "required_levels": 0, "requires_all": false, "requires_gold_total": false, "requires_hole_in_one": false},
    {"id": "pink", "name": "Pink", "color": Color(1.0, 0.28, 0.72), "description": "Beat 5 holes", "required_levels": 5, "requires_all": false, "requires_gold_total": false, "requires_hole_in_one": false},
    {"id": "orange", "name": "Orange", "color": Color(1.0, 0.48, 0.1), "description": "Beat 10 holes", "required_levels": 10, "requires_all": false, "requires_gold_total": false, "requires_hole_in_one": false},
    {"id": "brown", "name": "Brown", "color": Color(0.45, 0.25, 0.1), "description": "Beat all 20 holes", "required_levels": 20, "requires_all": true, "requires_gold_total": false, "requires_hole_in_one": false},
    {"id": "gold", "name": "Gold", "color": Color(1.0, 0.78, 0.12), "description": "Beat all 20 holes with total best par 60", "required_levels": 20, "requires_all": true, "requires_gold_total": true, "requires_hole_in_one": false},
    {"id": "gold_black_stripe", "name": "Gold + Black Stripe", "color": Color(1.0, 0.78, 0.12), "description": "Beat Hole 5 in one shot", "required_levels": 0, "requires_all": false, "requires_gold_total": false, "requires_hole_in_one": true, "black_stripe": true},
]

var _status_label: Label
var _list: VBoxContainer

class SkinSwatch:
    extends Control

    var base_color: Color = Color.WHITE
    var has_black_stripe: bool = false

    func _init(p_base_color: Color, p_has_black_stripe: bool) -> void:
        base_color = p_base_color
        has_black_stripe = p_has_black_stripe
        custom_minimum_size = Vector2(36, 36)
        mouse_filter = Control.MOUSE_FILTER_IGNORE

    func _draw() -> void:
        draw_rect(Rect2(Vector2.ZERO, size), base_color)
        if has_black_stripe:
            var stripe_height: float = size.y * 0.36
            var stripe_y: float = (size.y - stripe_height) * 0.5
            draw_rect(Rect2(Vector2(0.0, stripe_y), Vector2(size.x, stripe_height)), Color.BLACK)

static func color_for_skin(skin_id: String) -> Color:
    var skin: Dictionary = _skin_data(skin_id)
    return skin.get("color", Color.WHITE)

static func display_name_for_skin(skin_id: String) -> String:
    var skin: Dictionary = _skin_data(skin_id)
    return String(skin.get("name", "White"))

static func ball_material_for_skin(skin_id: String) -> Material:
    var skin: Dictionary = _skin_data(skin_id)
    if bool(skin.get("black_stripe", false)):
        var shader: Shader = Shader.new()
        shader.code = GOLD_STRIPE_SHADER_CODE
        var shader_mat: ShaderMaterial = ShaderMaterial.new()
        shader_mat.shader = shader
        return shader_mat
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_color = skin.get("color", Color.WHITE)
    return mat

static func is_skin_unlocked(skin_id: String) -> bool:
    return _is_unlocked(_skin_data(skin_id))

static func normalize_skin(skin_id: String) -> String:
    var id: String = skin_id.strip_edges().to_lower()
    if id == "":
        return PlayerProfile.DEFAULT_SKIN
    var skin: Dictionary = _skin_data(id)
    if String(skin.get("id", PlayerProfile.DEFAULT_SKIN)) != id:
        return PlayerProfile.DEFAULT_SKIN
    return id if _is_unlocked(skin) else PlayerProfile.DEFAULT_SKIN

static func _skin_data(skin_id: String) -> Dictionary:
    var id: String = skin_id.strip_edges().to_lower()
    for skin: Dictionary in SKINS:
        if String(skin.get("id", "")) == id:
            return skin
    return SKINS[0]

static func _is_unlocked(skin: Dictionary) -> bool:
    var completed: int = GolfScores.get_completed_count()
    if completed < int(skin.get("required_levels", 0)):
        return false
    if bool(skin.get("requires_all", false)) and not GolfScores.all_completed():
        return false
    if bool(skin.get("requires_gold_total", false)):
        var total_best: int = GolfScores.get_total_best()
        if total_best < 0 or total_best > TOTAL_BEST_GOLD_REQUIREMENT:
            return false
    if bool(skin.get("requires_hole_in_one", false)):
        var hole_best: int = GolfScores.get_best(HOLE_IN_ONE_SKIN_HOLE)
        if hole_best < 0 or hole_best > HOLE_IN_ONE_SKIN_STROKES:
            return false
    return true

func _ready() -> void:
    var backdrop: Node = get_node_or_null("/root/MenuBackdrop")
    if backdrop != null and backdrop.has_method("show_for_menu"):
        backdrop.call("show_for_menu")
    theme = MenuThemeBuilder.build()
    _build_ui()
    _refresh()

func _build_ui() -> void:
    var center: CenterContainer = CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var panel: PanelContainer = PanelContainer.new()
    panel.custom_minimum_size = Vector2(440, 0)
    center.add_child(panel)

    var vbox: VBoxContainer = VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 14)
    panel.add_child(vbox)

    var title: Label = Label.new()
    title.text = "Skin Shop"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    vbox.add_child(title)

    _status_label = Label.new()
    _status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vbox.add_child(_status_label)

    _list = VBoxContainer.new()
    _list.add_theme_constant_override("separation", 8)
    vbox.add_child(_list)

    var back_btn: Button = Button.new()
    back_btn.text = "Back"
    back_btn.custom_minimum_size = Vector2(0, 44)
    back_btn.pressed.connect(_on_back_pressed)
    vbox.add_child(back_btn)

func _refresh() -> void:
    for child: Node in _list.get_children():
        child.queue_free()

    var selected: String = normalize_skin(PlayerProfile.get_skin())
    if selected != PlayerProfile.get_skin():
        PlayerProfile.set_skin(selected)

    var completed: int = GolfScores.get_completed_count()
    var total_best: int = GolfScores.get_total_best()
    var total_text: String = "--" if total_best < 0 else str(total_best)
    _status_label.text = "Selected: %s\nProgress: %d/20 holes beaten · Total best: %s" % [display_name_for_skin(selected), completed, total_text]

    for skin: Dictionary in SKINS:
        _list.add_child(_make_skin_row(skin, selected))

func _make_skin_row(skin: Dictionary, selected: String) -> Control:
    var id: String = String(skin.get("id", "white"))
    var unlocked: bool = _is_unlocked(skin)
    var is_selected: bool = id == selected

    var row_panel: PanelContainer = PanelContainer.new()
    row_panel.add_theme_stylebox_override("panel", _skin_row_box(is_selected))

    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    row_panel.add_child(row)

    var swatch: SkinSwatch = SkinSwatch.new(skin.get("color", Color.WHITE), bool(skin.get("black_stripe", false)))
    row.add_child(swatch)

    var label: Label = Label.new()
    label.text = "%s\n%s" % [String(skin.get("name", "White")), _unlock_text(skin, unlocked)]
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)

    var btn: Button = Button.new()
    btn.custom_minimum_size = Vector2(108, 38)
    btn.text = "Selected" if is_selected else ("Use" if unlocked else "Locked")
    btn.disabled = (not unlocked) or is_selected
    if unlocked and not is_selected:
        btn.pressed.connect(_on_skin_pressed.bind(id))
    row.add_child(btn)

    return row_panel

func _skin_row_box(is_selected: bool) -> StyleBoxFlat:
    var sb: StyleBoxFlat = StyleBoxFlat.new()
    sb.bg_color = Color(0.95, 0.86, 0.35, 0.16) if is_selected else Color(0, 0, 0, 0)
    sb.border_color = Color(0.95, 0.86, 0.35, 0.62) if is_selected else Color(0.86, 0.93, 0.80, 0.08)
    sb.set_border_width_all(1 if is_selected else 0)
    sb.set_corner_radius_all(10)
    sb.content_margin_left = 10
    sb.content_margin_right = 10
    sb.content_margin_top = 8
    sb.content_margin_bottom = 8
    return sb

func _unlock_text(skin: Dictionary, unlocked: bool) -> String:
    if unlocked:
        return String(skin.get("description", "Unlocked"))
    if bool(skin.get("requires_hole_in_one", false)):
        return "Locked — beat Hole %d in one shot" % HOLE_IN_ONE_SKIN_HOLE
    if bool(skin.get("requires_gold_total", false)):
        return "Locked — beat all 20 holes with total best 60 or better"
    if bool(skin.get("requires_all", false)):
        return "Locked — beat all 20 holes"
    return "Locked — beat %d holes" % int(skin.get("required_levels", 0))

func _on_skin_pressed(skin_id: String) -> void:
    if not is_skin_unlocked(skin_id):
        return
    PlayerProfile.set_skin(skin_id)
    _refresh()

func _on_back_pressed() -> void:
    get_tree().change_scene_to_file(MENU_SCENE)
