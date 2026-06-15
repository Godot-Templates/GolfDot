class_name GolfAimOverlay
extends Control
## Lightweight 2D aim indicator: a ring around the ball plus a pull-back line to
## the cursor while aiming. Stand-in for Open-Golf's aim_circle UI.

var active: bool = false
var ball_screen: Vector2 = Vector2.ZERO
var cursor: Vector2 = Vector2.ZERO
var circle_radius: float = 60.0
var line_color: Color = Color.GREEN

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func update_aim(p_active: bool, p_ball: Vector2, p_cursor: Vector2, p_radius: float, p_color: Color) -> void:
	active = p_active
	ball_screen = p_ball
	cursor = p_cursor
	circle_radius = p_radius
	line_color = p_color
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	draw_arc(ball_screen, circle_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.7), 2.0, true)
	draw_line(ball_screen, cursor, line_color, 4.0, true)
	draw_circle(cursor, 6.0, line_color)
