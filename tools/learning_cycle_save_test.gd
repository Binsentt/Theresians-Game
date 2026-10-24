extends Node

const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert(HttpApi.is_local_qa_profile_active(), "Learning-cycle tests start in local-only mode before autoload initialization")
	if not HttpApi.is_local_qa_profile_active():
		_finish()
		return
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

	_assert(GameState.call("set_learning_cycle", {"version": 0.0, "started_at": null}), "JSON numeric cycle version 0.0 with a null boundary is accepted")
	_assert(GameState.learning_cycle_version == 0, "JSON numeric cycle version 0.0 normalizes to version 0")
	_assert(GameState.learning_cycle_started_at == "", "a null cycle boundary normalizes to an empty value")
	_assert(GameState.call("set_learning_cycle", {"version": 1.0}), "a float JSON cycle version with a missing boundary is accepted")
	_assert(GameState.learning_cycle_version == 1, "float JSON cycle version 1.0 normalizes to version 1")
	_assert(GameState.learning_cycle_started_at == "", "a missing cycle boundary remains empty")
	_assert(GameState.call("set_learning_cycle", {"version": "2", "started_at": "2026-08-25T04:00:00.000Z"}), "a numeric string cycle version is accepted")
	_assert(GameState.learning_cycle_version == 2, "a numeric string cycle version normalizes to its integer value")
	_assert(GameState.learning_cycle_started_at == "2026-08-25T04:00:00.000Z", "a valid cycle boundary string is preserved")
	_assert(not GameState.call("set_learning_cycle", {"version": "not-a-version"}), "a nonnumeric cycle version is rejected instead of being fabricated as version 0")
	_assert(GameState.learning_cycle_version == 2, "an invalid cycle version cannot replace the existing authoritative version")
	_assert(not GameState.call("set_learning_cycle", {"version": 1.5}), "a fractional cycle version is rejected instead of being truncated")
	_assert(not GameState.call("set_learning_cycle", null), "a missing lifecycle descriptor is rejected without a crash")

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
		"save_version": GameState.SAVE_VERSION,
		"save_kind": "manual",
		"manual_save_sequence": 1,
		"learning_cycle_version": 1,
		"learning_cycle_started_at": "2026-08-01T00:00:00.000Z",
		"pending_academic_results": [{"learning_cycle_version": 1, "result_event_id": "old-result"}],
		"pending_academic_activities": [{"learning_cycle_version": 1, "event_key": "old-activity"}],
	}, {"version": 2, "started_at": "2026-08-25T04:00:00.000Z"})
	_assert(bool(previous_save.get("loadable", false)), "a valid prior-cycle manual save remains playable as historical replay")
	_assert(bool(previous_save.get("historical_replay_mode", false)), "prior-cycle manual save is marked as historical replay")
	_assert(int(previous_save.get("replay_origin_learning_cycle_version", -1)) == 1, "historical replay records the originating cycle")
	_assert(int(previous_save.get("learning_cycle_version", -1)) == 2, "replay uses the authoritative current cycle, not the old saved cycle")
	_assert(String(previous_save.get("learning_cycle_started_at", "")) == "2026-08-25T04:00:00.000Z", "replay uses the authoritative current cycle boundary")
	_assert((previous_save.get("pending_academic_results", []) as Array).is_empty(), "prior-cycle answer payloads are discarded before load")
	_assert((previous_save.get("pending_academic_activities", []) as Array).is_empty(), "prior-cycle task/activity payloads are discarded before load")
	GameState.call("set_learning_cycle", {"version": 2, "started_at": "2026-08-25T04:00:00.000Z"})
	GameState.apply_save_data(previous_save, false)
	_assert(GameState.learning_cycle_version == 2, "applying a replay snapshot cannot roll the runtime cycle backward")
	_assert(GameState.get("historical_replay_mode") == true, "applying a prior-cycle manual snapshot enables replay isolation")
	_assert(GameState.get_pending_academic_event_count() == 0, "old pending academic payloads are not restored")
	var replay_answer_staged: bool = GameState.stage_pending_academic_result({
		"student_id": "001234", "parent_id": "009876", "learning_cycle_version": 2, "result_event_id": "replay-answer"
	})
	var replay_task_staged: bool = GameState.stage_pending_academic_activity({
		"student_id": "001234", "parent_id": "009876", "learning_cycle_version": 2, "event_key": "replay-task"
	})
	_assert(not replay_answer_staged and not replay_task_staged, "historical replay answers and task events cannot enter the current academic queue")
	_assert(GameState.get_pending_academic_event_count() == 0, "historical replay keeps the academic queue empty")
	var prior_cycle_without_authority: Dictionary = GameState.call("annotate_save_learning_cycle", previous_save, {})
	_assert(not bool(prior_cycle_without_authority.get("loadable", true)), "historical replay fails closed without an authoritative current-cycle descriptor")

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
	_assert(not load_button.disabled, "historical replay save keeps Load enabled")
	_assert(not delete_button.disabled, "previous-cycle saves remain manually deletable")
	_assert(availability_label.visible and availability_label.text.contains("Historical"), "historical replay state is visible in the real save entry")
	entry.queue_free()

	GameState.call("set_learning_cycle", {"version": 0, "started_at": ""})
	_finish()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("LEARNING_CYCLE_SAVE_TEST: PASS")
		await get_tree().create_timer(30.0).timeout
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("LEARNING_CYCLE_SAVE_TEST: FAIL")
	await get_tree().create_timer(30.0).timeout
	get_tree().quit(1)
