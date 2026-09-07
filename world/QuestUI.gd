extends Panel

## QuestUI keeps the existing quest/battle continuation, while the one Oakleaf
## DialoguePanel owns deliberate, one-line-at-a-time dialogue presentation.

signal dialogue_closed

@onready var quest_text: Label = get_node_or_null("QuestText") as Label
@onready var dialogue_panel: Control = get_node_or_null("../DialoguePanel") as Control
@onready var dialogue_label: Label = get_node_or_null("../DialoguePanel/DialogueLabel") as Label

var _dialogue_lines: Array[String] = []
var _dialogue_line_index := 0
var _dialogue_active := false
var _await_release_after_open := false
var _final_close_consumed := false


func _ready() -> void:
	update_task_ui()


func _process(_delta: float) -> void:
	if not _dialogue_active:
		return
	if _await_release_after_open:
		if not _is_interact_held():
			_await_release_after_open = false
		return
	if _consume_interact_press():
		_advance_dialogue_once()


func update_task_ui() -> void:
	if GameState.current_task_index >= GameState.tasks.size():
		visible = false
		return

	# GameHUD owns the single persistent Current Quest presentation. Keep this
	# legacy Panel only as the QuestUI bridge used by existing interaction scripts.
	if quest_text != null:
		quest_text.visible = false
	visible = true


func begin_dialogue(lines: Array) -> void:
	if _dialogue_active:
		return
	_dialogue_lines = _normalize_dialogue_lines(lines)
	if _dialogue_lines.is_empty():
		call_deferred("_close_dialogue")
		await dialogue_closed
		return

	_dialogue_active = true
	_dialogue_line_index = 0
	_final_close_consumed = false
	# The press that opened the real interaction must not consume line one.
	_await_release_after_open = true
	_render_dialogue_line()
	await dialogue_closed


func show_completed_with_dialogue() -> void:
	if GameState.current_task_index >= GameState.tasks.size():
		return

	var current_task_data: Dictionary = GameState.tasks[GameState.current_task_index]
	await begin_dialogue(current_task_data.get("dialogue", []))

	if current_task_data.has("next_scene"):
		if not GameState.playtime_authorized:
			return
		var player := get_tree().get_first_node_in_group("player_character") as Node2D
		var source_position := player.global_position if player != null else GameState.player_position
		var source_scene := get_tree().current_scene
		var source_scene_path := source_scene.scene_file_path if source_scene != null else GameState.current_scene_path
		GameState.begin_encounter({
			"encounter_id": "quest_task_%d" % GameState.current_task_index,
			"source_scene_path": source_scene_path,
			"source_position": source_position,
			"quest_checkpoint": GameState.current_task_index,
			"question_scope": current_task_data.get("question_scope", {}),
		})

		var battle_scene = load(current_task_data["next_scene"]).instantiate()
		get_tree().current_scene.add_child(battle_scene)
		GameState.begin_battle(battle_scene)
		visible = false

		var battle_won: bool = await battle_scene.battle_finished
		battle_scene.queue_free()
		visible = true
		if not battle_won:
			var loss_result: Dictionary = GameState.record_encounter_loss()
			if bool(loss_result.get("game_over", false)):
				return
			update_task_ui()
			return
		GameState.record_encounter_victory()

	var completed_task_index := GameState.current_task_index
	var completion_type := "task_completed" if current_task_data.has("next_scene") else "quest_completed"
	var completion_description := "Battle completed" if current_task_data.has("next_scene") else "Teacher conversation completed"
	GameState.advance_task_and_save({
		"type": completion_type,
		"key": "quest:main:task:%d:complete" % completed_task_index,
		"title": "Task %d Complete" % (completed_task_index + 1),
		"description": completion_description,
		"source": "quest_ui",
		"reason": "battle_victory" if current_task_data.has("next_scene") else "teacher_task_completed",
	})

	if GameState.current_task_index < GameState.tasks.size():
		update_task_ui()
	else:
		queue_free()


func play_teacher_dialogue() -> void:
	# TeacherTaskInteraction continues to own the DIALOGUE mode frame and its
	# one-shot guard. This method only runs the existing quest continuation.
	await show_completed_with_dialogue()


func is_dialogue_active() -> bool:
	return _dialogue_active


func get_dialogue_line_index() -> int:
	return _dialogue_line_index


func _advance_dialogue_once() -> void:
	if not _dialogue_active:
		return
	if _dialogue_line_index + 1 < _dialogue_lines.size():
		_dialogue_line_index += 1
		_await_release_after_open = true
		_render_dialogue_line()
		return
	if _final_close_consumed:
		return
	_final_close_consumed = true
	_close_dialogue()


func _render_dialogue_line() -> void:
	if dialogue_label != null:
		dialogue_label.text = _dialogue_lines[_dialogue_line_index]
	if dialogue_panel != null:
		dialogue_panel.visible = true


func _close_dialogue() -> void:
	if not _dialogue_active:
		return
	_dialogue_active = false
	_await_release_after_open = false
	if dialogue_panel != null:
		dialogue_panel.visible = false
	dialogue_closed.emit()


func _normalize_dialogue_lines(lines: Array) -> Array[String]:
	var normalized: Array[String] = []
	for line_value in lines:
		var line := String(line_value).strip_edges()
		if not line.is_empty():
			normalized.append(line)
	return normalized


func _is_interact_held() -> bool:
	return InputManager.is_interact_pressed()


func _consume_interact_press() -> bool:
	return InputManager.consume_interact_just_pressed()
