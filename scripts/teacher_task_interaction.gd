extends Node

## Reusable Teacher target for the mobile exploration InteractionManager.
## Narrative, battle, and completion semantics remain in QuestUI; this adapter
## only gates the interaction and owns its temporary DIALOGUE mode push.

@export var quest_ui_path: NodePath = NodePath("../CanvasLayer/Panel")

var _active: bool = false


func _exit_tree() -> void:
	# Scene changes can free the adapter while the awaited dialogue coroutine is
	# still suspended. Release the mode frame and guard so exploration cannot be
	# left blocked by a stale Teacher interaction.
	if _active:
		_finish_interaction()


func can_interact() -> bool:
	if _active or GameState.current_task_index != 1:
		return false
	if GameState.get_mode() != GameState.GameMode.EXPLORATION:
		return false
	if _is_input_locked():
		return false
	return _get_quest_ui() != null


func interact() -> bool:
	if not can_interact():
		return false

	_active = true
	GameState.push_mode(GameState.GameMode.DIALOGUE)
	_run_teacher_dialogue()
	return true


func _run_teacher_dialogue() -> void:
	var quest_ui := _get_quest_ui()
	if quest_ui == null or not quest_ui.has_method("play_teacher_dialogue"):
		_finish_interaction()
		return
	await quest_ui.play_teacher_dialogue()
	_finish_interaction()


func _finish_interaction() -> void:
	# Pop only the DIALOGUE mode this adapter pushed. A battle/cutscene mode
	# introduced by existing QuestUI content remains owned by that content.
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
