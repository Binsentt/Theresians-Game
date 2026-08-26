extends AnimatedSprite2D

## Reuses the one Oakleaf DialoguePanel through QuestUI. NPC greetings are real
## dialogue, so they retain the existing DIALOGUE mode lock until the player
## deliberately closes their one visible line.

@export var quest_ui_path: NodePath = NodePath("../CanvasLayer/Panel")
@export_multiline var greeting_message: String = "Hello traveler! Welcome to our town."

var _dialogue_active := false


func can_interact() -> bool:
	if _dialogue_active or GameState.get_mode() != GameState.GameMode.EXPLORATION:
		return false
	var input_manager := get_node_or_null("/root/InputManager")
	if input_manager != null and input_manager.has_method("is_input_locked") and bool(input_manager.call("is_input_locked")):
		return false
	return _get_quest_ui() != null


func interact() -> bool:
	if not can_interact():
		return false
	show_dialogue_timed()
	return true


func show_dialogue_timed() -> void:
	# Retain the established entry point for existing scene wiring while routing
	# its content through the one shared, deliberate-input DialoguePanel.
	if _dialogue_active:
		return
	_dialogue_active = true
	GameState.push_mode(GameState.GameMode.DIALOGUE)
	_run_dialogue()


func _run_dialogue() -> void:
	var quest_ui := _get_quest_ui()
	if quest_ui == null or not quest_ui.has_method("begin_dialogue"):
		_finish_dialogue()
		return
	await quest_ui.begin_dialogue([greeting_message])
	_finish_dialogue()


func _finish_dialogue() -> void:
	if GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
	_dialogue_active = false


func hide_dialogue() -> void:
	_finish_dialogue()


func _get_quest_ui() -> Node:
	if quest_ui_path.is_empty():
		return null
	return get_node_or_null(quest_ui_path)
