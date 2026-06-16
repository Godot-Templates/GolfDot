extends Node
## Validates that the level-select menu builds a Credits button wired to the
## credits scene, and that the credits scene's Back button is wired back.

func _find_button(root: Node, text: String) -> Button:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == text:
			return n as Button
		for c in n.get_children():
			stack.append(c)
	return null

func test_level_select_has_wired_credits_button() -> void:
	var inst: Node = load("res://scenes/level_select.tscn").instantiate()
	inst._ready()  # build the code-driven UI without requiring the live tree

	var btn: Button = _find_button(inst, "Credits")
	assert(btn != null, "Credits button should exist in level_select")
	var conns: Array = btn.pressed.get_connections()
	assert(conns.size() == 1, "Credits button should have exactly one pressed handler")
	assert(conns[0]["callable"].get_method() == "_on_credits_pressed", "wired to _on_credits_pressed")
	inst.queue_free()

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
