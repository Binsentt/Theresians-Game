extends Node

const TASK_PROGRESS_TRIGGER_SCRIPT := preload("res://world/task_progress_trigger.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_task_index := GameState.current_task_index
	var original_quest := GameState.current_quest
	GameState.current_task_index = 0
	GameState.current_quest = String(GameState.tasks[0].get("quest_text", ""))

	var oak_leaf_source := _read_fixture("res://scenes/oak_leaf_village.tscn")
	_expect(GameState.tasks[0].get("quest_text", "") == "Go to the Teacher's House", "The first quest retains its original objective with valid text encoding.")
	_expect(oak_leaf_source.contains("[node name=\"TeacherHouseTaskTrigger\""), "Oak Leaf must retain the existing Teacher House trigger node.")
	_expect(oak_leaf_source.contains("[node name=\"TeacherHouseExitSpawn\""), "Oak Leaf must retain the canonical Teacher House return marker.")
	_expect(oak_leaf_source.contains("[sub_resource type=\"RectangleShape2D\" id=\"RectangleShape2D_teacher_house_task_trigger\"]\nsize = Vector2(40, 28)"), "Teacher House uses its own doorway-sized trigger shape.")
	_expect(oak_leaf_source.contains("position = Vector2(-1, -6)\nshape = SubResource(\"RectangleShape2D_teacher_house_task_trigger\")"), "Teacher House trigger covers the canonical doorway/return position without altering the Bandit trigger.")

	var trigger := TASK_PROGRESS_TRIGGER_SCRIPT.new() as Area2D
	trigger.required_task_index = 0
	get_tree().root.add_child(trigger)
	await get_tree().process_frame
	_expect(trigger.required_task_index == 0, "Teacher House trigger remains limited to the first quest.")
	var player := Node2D.new()
	player.add_to_group("player_character")
	get_tree().root.add_child(player)
	trigger.call("_on_body_entered", player)
	_expect(GameState.current_task_index == 1, "Teacher House trigger advances exactly from task zero to task one.")
	trigger.call("_on_body_entered", player)
	_expect(GameState.current_task_index == 1, "Teacher House trigger cannot advance the quest twice.")
	player.queue_free()
	trigger.queue_free()
	GameState.current_task_index = original_task_index
	GameState.current_quest = original_quest

	if _failures.is_empty():
		print("teacher_house_trigger_regression_test: PASS")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _read_fixture(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
