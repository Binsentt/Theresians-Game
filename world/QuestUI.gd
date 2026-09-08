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
	if dialogue_panel != null:
		var panel_height := snappedf(dialogue_panel.size.y * 0.9, 2.0)
		dialogue_panel.offset_left -= 20.0
		dialogue_panel.offset_right += 20.0
		dialogue_panel.anchor_top = 1.0
		dialogue_panel.anchor_bottom = 1.0
		# Longer wrapped text grows upward from the same bottom margin.
		dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		dialogue_panel.offset_top = -40.0 - panel_height
		dialogue_panel.offset_bottom = -40.0
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
			"encounter_id": "oakleaf_bandits1" if GameState.current_task_index == 2 else "quest_task_%d" % GameState.current_task_index,
			"source_scene_path": source_scene_path,
			"source_position": source_position,
			"quest_checkpoint": GameState.current_task_index,
			"question_scope": current_task_data.get("question_scope", {}),
		})

		var battle_scene_path: String = current_task_data["next_scene"]
		if GameState.gender == "female" and battle_scene_path == "res://Battle/Battle-Enemy/male_vs_bandit.tscn":
			battle_scene_path = "res://Battle/Battle-Enemy/female_vs_bandit.tscn"
		var battle_scene = load(battle_scene_path).instantiate()
		# Original VS art uses viewport coordinates. Keep it outside the world's
		# Camera2D transform while retaining the encounter world for its return.
		var battle_layer := CanvasLayer.new()
		battle_layer.name = "OriginalBattlePresentation"
		battle_layer.layer = -1
		var world_canvas := source_scene as CanvasItem
		var world_was_visible := world_canvas.visible
		world_canvas.hide()
		get_tree().current_scene.add_child(battle_layer)
		var question_layer := battle_scene.get_node("CanvasLayer") as CanvasLayer
		question_layer.layer = 0
		battle_layer.add_child(battle_scene)
		GameState.begin_battle(battle_scene)
		visible = false

		var battle_won: bool = await battle_scene.battle_finished
		battle_layer.queue_free()
		world_canvas.visible = world_was_visible
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

	# Ordinary NPC greetings still use this shared host after the last quest.
	update_task_ui()


func play_teacher_dialogue() -> void:
	# TeacherTaskInteraction continues to own the DIALOGUE mode frame and its
	# one-shot guard. This method only runs the existing quest continuation.
	if GameState.has_method("is_city_school_active") \
			and bool(GameState.call("is_city_school_active")):
		var school_task: Dictionary = GameState.tasks[GameState.CITY_SCHOOL_TASK_INDEX]
		await begin_dialogue(school_task.get("dialogue", []))
		GameState.complete_city_school_teacher()
		update_task_ui()
		return
	if GameState.has_method("is_oakleaf_return_to_teacher_active") \
			and bool(GameState.call("is_oakleaf_return_to_teacher_active")):
		var return_task: Dictionary = GameState.tasks[GameState.current_task_index]
		await begin_dialogue(return_task.get("dialogue", []))
		GameState.complete_oakleaf_teacher_return()
		update_task_ui()
		return
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
