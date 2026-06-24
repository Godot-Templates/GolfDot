class_name MenuThemeBuilder
extends RefCounted
## Builds a small golf-themed Theme for the menus: fairway-green rounded buttons
## that lighten on hover and sink on press, with a soft accent border. Assign the
## returned Theme to a Control and every Button beneath it inherits the look.

# Fairway / green palette.
const COL_NORMAL := Color(0.17, 0.43, 0.25)
const COL_HOVER := Color(0.24, 0.57, 0.33)
const COL_PRESSED := Color(0.11, 0.31, 0.19)
const COL_BORDER := Color(0.86, 0.93, 0.80, 0.55)  # soft chalk-line accent
const COL_FOCUS := Color(0.95, 0.86, 0.35, 0.9)    # warm "flag" yellow focus ring

static func build() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", _box(COL_NORMAL, COL_BORDER, 1))
	t.set_stylebox("hover", "Button", _box(COL_HOVER, COL_BORDER, 1))
	t.set_stylebox("pressed", "Button", _box(COL_PRESSED, COL_BORDER, 1))
	t.set_stylebox("disabled", "Button", _box(COL_NORMAL.darkened(0.3), COL_BORDER, 1))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), COL_FOCUS, 2))
	t.set_color("font_color", "Button", Color(0.97, 0.99, 0.95))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.85, 0.95, 0.88))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_constant("outline_size", "Button", 0)
	return t

static func _box(fill: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	# Subtle lift so buttons feel like little tee markers on the grass.
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb
