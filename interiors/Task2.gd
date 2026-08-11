extends Node

@export var ui_panel: Panel

func _ready():
	if GameState.task_2_done:
		queue_free()


func can_interact() -> bool:
	if GameState.task_2_done:
		return false
	if GameState.get_mode() != GameState.GameMode.EXPLORATION:
		return false
	if _is_input_locked():
		return false
	return ui_panel != null


func interact() -> bool:
	if not can_interact():
		return false
	GameState.task_2_done = true
	GameState.push_mode(GameState.GameMode.DIALOGUE)
	if ui_panel != null and ui_panel.has_method("show_completed_with_dialogue"):
		await ui_panel.show_completed_with_dialogue()
	GameState.pop_mode()
	queue_free()
	return true


func _is_input_locked() -> bool:
	var input_manager := get_node_or_null("/root/InputManager")
	return input_manager == null \
		or not input_manager.has_method("is_input_locked") \
		or bool(input_manager.call("is_input_locked"))
