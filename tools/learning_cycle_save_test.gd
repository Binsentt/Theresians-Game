extends Node

const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert(GameState.has_method("set_learning_cycle"), "GameState exposes authoritative learning-cycle state")
	_assert(GameState.has_method("annotate_save_learning_cycle"), "GameState can evaluate one local save against a server cycle")
	_assert(load("res://scripts/load_game_scene.gd") != null, "Load Game's learning-cycle gate parses")
	_assert(load("res://scripts/remote_sync.gd") != null, "RemoteSync learning-cycle contract parses")
	_assert(load("res://scenes/texture_rect_2.gd") != null, "canonical New Game learning-cycle handoff parses")
	var remote_sync_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	var progress_start := remote_sync_source.find("func _async_send_progress")
	var progress_end := remote_sync_source.find("func _build_playtime_start_payload", progress_start)
	var progress_sync_source := remote_sync_source.substr(progress_start, progress_end - progress_start)
	_assert(progress_sync_source.contains("\"playtime_session_id\": _current_playtime_session_id"), "progress writes include the active lease session ID")
	_assert(progress_sync_source.contains("\"playtime_session_credential\": _current_playtime_session_credential"), "progress writes include the active lease credential")
	if not failures.is_empty():
		_finish()
		return

	GameState.call("set_learning_cycle", {"version": 2, "started_at": "2026-08-25T04:00:00.000Z"})
	var save_data: Dictionary = GameState.build_save_data()
	_assert(int(save_data.get("learning_cycle_version", -1)) == 2, "new saves retain the authoritative cycle version")
	_assert(String(save_data.get("learning_cycle_started_at", "")) == "2026-08-25T04:00:00.000Z", "new saves retain the authoritative cycle boundary")

	var current_save: Dictionary = GameState.call("annotate_save_learning_cycle", {
		"student_id": "001234",
		"parent_id": "009876",
		"scene_path": GameState.START_SCENE_PATH,
		"learning_cycle_version": 2,
		"learning_cycle_started_at": "2026-08-25T04:00:00.000Z",
	}, {"version": 2, "started_at": "2026-08-25T04:00:00.000Z"})
	_assert(bool(current_save.get("loadable", false)), "matching current-cycle saves remain loadable")

	var previous_save: Dictionary = GameState.call("annotate_save_learning_cycle", {
		"student_id": "001234",
		"parent_id": "009876",
		"scene_path": GameState.START_SCENE_PATH,
		"learning_cycle_version": 1,
		"learning_cycle_started_at": "2026-08-01T00:00:00.000Z",
	}, {"version": 2, "started_at": "2026-08-25T04:00:00.000Z"})
	_assert(not bool(previous_save.get("loadable", true)), "previous-cycle saves cannot be loaded")
	_assert(String(previous_save.get("save_error", "")) == "Previous Learning Cycle", "previous-cycle saves use the approved clear label")

	var legacy_save: Dictionary = GameState.call("annotate_save_learning_cycle", {
		"student_id": "001234",
		"parent_id": "009876",
		"scene_path": GameState.START_SCENE_PATH,
	}, {"version": 0, "started_at": ""})
	_assert(bool(legacy_save.get("loadable", false)), "legacy cycle-zero saves remain compatible before a new cycle starts")

	var entry: Control = SAVE_ENTRY_SCENE.instantiate() as Control
	add_child(entry)
	entry.setup(previous_save)
	await get_tree().process_frame
	var load_button := entry.get_node("MarginContainer/Content/Actions/LoadButton") as Button
	var delete_button := entry.get_node("MarginContainer/Content/Actions/DeleteButton") as Button
	var availability_label := entry.get_node("MarginContainer/Content/Details/AvailabilityLabel") as Label
	_assert(load_button.disabled, "previous-cycle saves disable Load")
	_assert(not delete_button.disabled, "previous-cycle saves remain manually deletable")
	_assert(availability_label.visible and availability_label.text == "Previous Learning Cycle", "previous-cycle label is visible in the real save entry")
	entry.queue_free()

	GameState.call("set_learning_cycle", {"version": 0, "started_at": ""})
	_finish()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("LEARNING_CYCLE_SAVE_TEST: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("LEARNING_CYCLE_SAVE_TEST: FAIL")
	get_tree().quit(1)
