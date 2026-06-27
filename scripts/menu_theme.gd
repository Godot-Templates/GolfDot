class_name MenuThemeBuilder
extends RefCounted
## Builds the shared golf-themed Theme for menu screens and in-game popups:
## fairway-green rounded buttons, soft dark panels, light text, and a warm
## flag-yellow focus/accent. Assign the returned Theme to a Control and every
## compatible Control beneath it inherits the look.

# Bundled emoji fallback for Web exports. Browsers do not expose their system
# emoji fonts to Godot's canvas renderer, so labels need an exported font that
# contains the emoji glyphs we use in menu titles.
const EMOJI_FONT := preload("res://assets/fonts/NotoColorEmoji.ttf")

# Fairway / green palette.
const COL_NORMAL := Color(0.17, 0.43, 0.25)
const COL_HOVER := Color(0.24, 0.57, 0.33)
const COL_PRESSED := Color(0.11, 0.31, 0.19)
const COL_BORDER := Color(0.86, 0.93, 0.80, 0.55)  # soft chalk-line accent
const COL_FOCUS := Color(0.95, 0.86, 0.35, 0.9)    # warm "flag" yellow focus ring
const COL_TEXT := Color(0.97, 0.99, 0.95)
const COL_PANEL := Color(0.02, 0.05, 0.04, 0.72)
const COL_PANEL_BORDER := Color(0.86, 0.93, 0.80, 0.32)

static func build() -> Theme:
	var t: Theme = Theme.new()
	var emoji_fallback: FontVariation = FontVariation.new()
	emoji_fallback.fallbacks = [EMOJI_FONT]
	t.set_default_font(emoji_fallback)

	# Golf-themed fairway buttons.
	t.set_stylebox("normal", "Button", _box(COL_NORMAL, COL_BORDER, 1))
	t.set_stylebox("hover", "Button", _box(COL_HOVER, COL_BORDER, 1))
	t.set_stylebox("pressed", "Button", _box(COL_PRESSED, COL_BORDER, 1))
	t.set_stylebox("disabled", "Button", _box(COL_NORMAL.darkened(0.3), COL_BORDER, 1))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), COL_FOCUS, 2))
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.85, 0.95, 0.88))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_constant("outline_size", "Button", 0)

	# Shared menu/popup panel and readable label defaults.
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_outline_size", "Label", 2)

	# Give sliders the same fairway track treatment where those theme items apply.
	t.set_stylebox("slider", "HSlider", _track_box(Color(0.04, 0.12, 0.07, 0.95)))
	t.set_stylebox("grabber_area", "HSlider", _track_box(COL_HOVER))
	t.set_stylebox("grabber_area_highlight", "HSlider", _track_box(COL_FOCUS))
	return t

static func panel_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 3)
	return sb

static func style_title(label: Label, font_size: int) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", COL_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", font_size)

static func _box(fill: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
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

static func _track_box(fill: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb
