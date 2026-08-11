extends Node

## Reusable adapter for intentional dialogue-style interactions that should be
## triggered by the mobile Interact button instead of proximity.

@export var quest_ui_path: NodePath = NodePath()
@export var dialogue_target_path: NodePath = NodePath()
@export var completion_key: String = ""
@export var mode: String = "task"
@export var require_task_index: int = -1
@export var completion_state_key: String = ""
@export var completion_state_value: bool = true

var _active: bool = false


func _exit_tree() -> void:
	if _active:
		_finish_interaction()


func can_interact() -> bool:
	if _active:
		return false
	if GameState.get_mode() != GameState.GameMode.EXPLORATION:
		return false
	if _is_input_locked():
		return false
	if require_task_index >= 0 and GameState.current_task_index != require_task_index:
		return false
	return _get_quest_ui() != null


func interact() -> bool:
	if not can_interact():
		return false

	_active = true
	GameState.push_mode(GameState.GameMode.DIALOGUE)
	_run_dialogue()
	return true


func _run_dialogue() -> void:
	var quest_ui := _get_quest_ui()
	if quest_ui == null:
		_finish_interaction()
		return
	if quest_ui.has_method("show_completed_with_dialogue"):
		await quest_ui.show_completed_with_dialogue()
	elif quest_ui.has_method("play_teacher_dialogue"):
		await quest_ui.play_teacher_dialogue()
	else:
		await get_tree().create_timer(0.2).timeout
	_finish_interaction()


func _finish_interaction() -> void:
	if GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
	_active = false


func _get_quest_ui() -> Node:
	if quest_ui_path.is_empty():
		return null
	return get_node_or_null(quest_ui_path)


func _is_input_locked() -> bool:
	var input_manager := get_node_or_null("/root/InputManager")
	return input_manager == null \
		or not input_manager.has_method("is_input_locked") \
		or bool(input_manager.call("is_input_locked"))
