extends Control
## Overall highscores screen — the global "best golfers" board, ranked by the
## LOWEST total stroke count across all 20 holes (fewer is better). Data comes
## from the Leaderboard autoload, which is backed by the Ziva durable-object
## store, so the board is shared across every player and survives everyone
## disconnecting. Until multiplayer is enabled it shows this device's own total.

const MENU_SCENE := "res://scenes/main_menu.tscn"

var _list: VBoxContainer
var _status: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var title := Label.new()
	title.text = "GOLFDOT — Overall Highscores"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Lowest total strokes across all 20 holes"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.modulate = Color(0.7, 0.8, 0.9)
	vbox.add_child(subtitle)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color(0.6, 0.72, 0.85)
	vbox.add_child(_status)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(_list)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 44)
	back.pressed.connect(_on_back_pressed)
	vbox.add_child(back)

	var lb := get_node_or_null("/root/Leaderboard")
	if lb != null and not lb.updated.is_connected(_refresh):
		lb.updated.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()

	var lb := get_node_or_null("/root/Leaderboard")
	if lb == null:
		_status.text = "Leaderboard unavailable."
		return

	_status.text = "Online — global board" if lb.is_online() \
		else "Local only — enable multiplayer (Settings > Ziva Cloud) for global scores"

	var board: Array = lb.get_overall_board()
	if board.is_empty():
		var empty := Label.new()
		empty.text = "No completed rounds yet. Finish all 20 holes to appear here!"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(420, 0)
		_list.add_child(empty)
		return

	var me := PlayerProfile.get_player_name()
	for i in range(board.size()):
		var entry: Dictionary = board[i]
		_list.add_child(_make_row(i + 1, String(entry["name"]), int(entry["strokes"]), String(entry["name"]) == me))

func _make_row(rank: int, player_name: String, strokes: int, is_me: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var rank_label := Label.new()
	rank_label.text = "%d." % rank
	rank_label.custom_minimum_size = Vector2(34, 0)
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = player_name + (" (you)" if is_me else "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var score_label := Label.new()
	score_label.text = "%d strokes" % strokes
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(score_label)

	if is_me:
		var hl := Color(0.55, 1.0, 0.6)
		rank_label.add_theme_color_override("font_color", hl)
		name_label.add_theme_color_override("font_color", hl)
		score_label.add_theme_color_override("font_color", hl)
	return row

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
