extends Node

const TASK_PROGRESS_TRIGGER_SCRIPT := preload("res://world/task_progress_trigger.gd")
const QUEST_UI_SCRIPT := preload("res://world/QuestUI.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Canonical tests preserve real user saves and never emit production writes.
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var autoload := get_node_or_null("/root/" + autoload_name)
		if autoload != null:
			autoload.free()
	GameState.set_script(load("res://tools/preservation_regression_state.gd"))
	var original_task_index := GameState.current_task_index
	var original_quest := GameState.current_quest
	var original_mode := GameState.get_mode()
	GameState.current_task_index = 0
	GameState.current_quest = String(GameState.tasks[0].get("quest_text", ""))
	GameState.set_mode(GameState.GameMode.EXPLORATION)

	var oak_leaf_source := _read_fixture("res://scenes/oak_leaf_village.tscn")
	_expect(GameState.tasks[0].get("quest_text", "") == "Go to the Teacher's House", "The first quest retains its original objective with valid text encoding.")
	_expect(oak_leaf_source.contains("[node name=\"TeacherHouseTaskTrigger\""), "Oak Leaf must retain the existing Teacher House trigger node.")
	_expect(oak_leaf_source.contains("[node name=\"TeacherHouseExitSpawn\""), "Oak Leaf must retain the canonical Teacher House return marker.")
	_expect(oak_leaf_source.contains("[sub_resource type=\"RectangleShape2D\" id=\"RectangleShape2D_teacher_house_task_trigger\"]"), "Teacher House retains its dedicated doorway trigger shape.")
	_expect(oak_leaf_source.contains("position = Vector2(-3, -8)\nshape = SubResource(\"RectangleShape2D_teacher_house_task_trigger\")"), "Teacher House trigger preserves the approved canonical doorway offset without altering the Bandit trigger.")
	_expect(not oak_leaf_source.contains("TeacherTriggerPortrait"), "The retired top-right Teacher portrait is absent from the active Oak Leaf scene.")
	_expect(oak_leaf_source.count("[node name=\"DialoguePanel\" type=\"PanelContainer\" parent=\"CanvasLayer\"") == 1, "Oak Leaf provides exactly one shared DialoguePanel regardless of editor node IDs.")
	var legacy_quest_ui := QUEST_UI_SCRIPT.new() as Panel
	var legacy_quest_text := Label.new()
	legacy_quest_text.name = "QuestText"
	legacy_quest_ui.add_child(legacy_quest_text)
	get_tree().root.add_child(legacy_quest_ui)
	await get_tree().process_frame
	legacy_quest_ui.update_task_ui()
	_expect(not legacy_quest_text.visible, "The legacy floating QuestUI label stays hidden so only the GameHUD Current Quest panel presents the objective.")
	legacy_quest_ui.queue_free()

	var trigger := TASK_PROGRESS_TRIGGER_SCRIPT.new() as Area2D
	trigger.required_task_index = 0
	_expect(trigger.notification_portrait_path == "res://Images/NPC.jpg", "Teacher House inherits the approved portrait from the shared trigger default.")
	get_tree().root.add_child(trigger)
	await get_tree().process_frame
	_expect(trigger.required_task_index == 0, "Teacher House trigger remains limited to the first quest.")
	var player := Node2D.new()
	player.add_to_group("player_character")
	get_tree().root.add_child(player)
	trigger.call("_on_body_entered", player)
	_expect(GameState.current_task_index == 1, "Teacher House trigger advances exactly from task zero to task one.")
	_expect(String(trigger.notification_portrait_path) == "res://Images/NPC.jpg", "Teacher House trigger preserves the approved portrait asset path.")
	var notification_manager := get_tree().root.get_node_or_null("QuestNotificationManager")
	_expect(
		notification_manager != null and notification_manager.has_method("get_active_notification_key")
			and String(notification_manager.call("get_active_notification_key")) == "quest:main:task:0:arrival",
		"Teacher House trigger routes its one-shot arrival through the stable Task Trigger notification key."
	)
	trigger.call("_on_body_entered", player)
	_expect(GameState.current_task_index == 1, "Teacher House trigger cannot advance the quest twice.")
	player.queue_free()
	trigger.queue_free()
	GameState.current_task_index = original_task_index
	GameState.current_quest = original_quest
	GameState.set_mode(original_mode)
	var fixture_path: String = GameState.get("fixture_path")
	if FileAccess.file_exists(fixture_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))

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
