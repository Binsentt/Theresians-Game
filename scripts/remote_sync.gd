extends Node

const PRODUCTION_PENDING_FILE := "user://pending_syncs.json"
const LOCAL_QA_PENDING_FILE := "user://pending_syncs_local_qa.json"
const ANDROID_QA_PENDING_FILE := "user://pending_syncs_android_qa.json"
var _pending_file := PRODUCTION_PENDING_FILE

var _current_playtime_session_id: int = 0
var _current_playtime_session_credential: String = ""
var _current_playtime_student_id: String = ""
var _current_playtime_parent_id: String = ""
var _current_playtime_learning_cycle_version: int = -1
var _session_start_in_progress: bool = false
var _playtime_end_in_progress: bool = false
var _playtime_heartbeat_in_progress: bool = false
var _playtime_heartbeat_elapsed: float = 0.0
var _playtime_timeout_handled: bool = false
var _playtime_timeout_pending: bool = false
var _app_close_in_progress: bool = false
var _pending_flush_in_progress: bool = false
var _pending_flush_requested: bool = false
var local_qa_only := false
var android_qa_mode := false
var android_qa_remote_writes_enabled := false

const PLAYTIME_DAILY_LIMIT_MINUTES := 60
const PLAYTIME_HEARTBEAT_INTERVAL_SECONDS := 15.0
const CANONICAL_ACTIVITY_ENDPOINT := "/api/game/activity"
const CANONICAL_RESULT_ENDPOINT := "/api/game/result"
const CANONICAL_ACTIVITY_TYPES := {
	"task_trigger": "task_triggered",
	"task_completed": "task_completed",
	"quest_completed": "quest_completed",
}

var _acknowledged_activity_keys: Dictionary = {}
var _activity_requests_in_flight: Dictionary = {}

func _ensure_playtime_session() -> Dictionary:
	if _has_active_playtime_lease():
		return {"ok": true, "session_id": _current_playtime_session_id, "can_play": true}
	var waited_frames := 0
	while _session_start_in_progress and waited_frames < 120:
		await get_tree().process_frame
		waited_frames += 1
	if _has_active_playtime_lease():
		return {"ok": true, "session_id": _current_playtime_session_id, "can_play": true}
	return await _start_playtime_session()

func _ready() -> void:
	var http := get_node_or_null("/root/HttpApi")
	if http != null and http.has_method("is_android_qa_mode") and bool(http.call("is_android_qa_mode")):
		var android_writes_enabled := http.has_method("is_android_qa_remote_writes_enabled") and bool(http.call("is_android_qa_remote_writes_enabled"))
		configure_android_qa_mode(android_writes_enabled)
	elif http != null and http.has_method("is_local_qa_mode") and bool(http.call("is_local_qa_mode")):
		enable_local_qa_mode()
	var game_state := get_node_or_null("/root/GameState")
	if game_state:
		game_state.connect("save_created", Callable(self, "_on_save_created"))
		game_state.connect("progression_session_reset", Callable(self, "_on_progression_session_reset"))
		game_state.connect("game_over", Callable(self, "_on_game_over"))
		game_state.connect("time_limit_reached", Callable(self, "_on_time_limit_reached"))
		game_state.connect("playtime_warning", Callable(self, "_on_playtime_warning"))
		if not game_state.task_state_changed.is_connected(_on_task_state_changed):
			game_state.task_state_changed.connect(_on_task_state_changed)
		if not game_state.canonical_activity_boundary.is_connected(_on_canonical_activity_boundary):
			game_state.canonical_activity_boundary.connect(_on_canonical_activity_boundary)
	_load_pending()
	var root_window := get_tree().root if get_tree() != null else null
	if root_window is Window:
		get_tree().auto_accept_quit = false
		if not root_window.close_requested.is_connected(_on_window_close_requested):
			root_window.close_requested.connect(_on_window_close_requested)


func _on_window_close_requested() -> void:
	if _app_close_in_progress:
		return
	_app_close_in_progress = true
	if GameState != null:
		await _end_playtime_session()
		GameState.discard_unsaved_run()
	if get_tree() != null:
		get_tree().quit()

func enable_local_qa_mode() -> void:
	android_qa_mode = false
	android_qa_remote_writes_enabled = false
	local_qa_only = true
	_pending_file = LOCAL_QA_PENDING_FILE
	_invalidate_playtime_lease()
	_session_start_in_progress = false
	_playtime_end_in_progress = false
	_playtime_heartbeat_in_progress = false
	_playtime_timeout_pending = false
	_activity_requests_in_flight.clear()
	_acknowledged_activity_keys.clear()
	print("RemoteSync: LOCAL QA ONLY — all telemetry/progress writes disabled")


func configure_android_qa_mode(_remote_writes_enabled: bool) -> void:
	android_qa_mode = true
	android_qa_remote_writes_enabled = false
	local_qa_only = false
	_pending_file = ANDROID_QA_PENDING_FILE
	_invalidate_playtime_lease()
	_session_start_in_progress = false
	_playtime_end_in_progress = false
	_playtime_heartbeat_in_progress = false
	_playtime_timeout_pending = false
	_activity_requests_in_flight.clear()
	_acknowledged_activity_keys.clear()
	print("RemoteSync: ANDROID QA RETIRED — isolated outbox retained, remote writes disabled")


func _remote_writes_blocked() -> bool:
	return local_qa_only or (android_qa_mode and not android_qa_remote_writes_enabled)


func _current_environment_scope() -> String:
	if local_qa_only:
		return "local_qa"
	if android_qa_mode:
		return "android_qa"
	return "production"

func _process(delta: float) -> void:
	if not GameState:
		return
	GameState.consume_playtime_clock(delta)
	if _remote_writes_blocked():
		return
	if not _has_active_playtime_lease():
		return
	_playtime_heartbeat_elapsed += delta
	if _playtime_heartbeat_elapsed >= PLAYTIME_HEARTBEAT_INTERVAL_SECONDS and not _playtime_heartbeat_in_progress:
		_playtime_heartbeat_elapsed = 0.0
		_refresh_playtime_lease.call_deferred()

func _on_save_created(save_data: Dictionary) -> void:
	if _remote_writes_blocked():
		return
	if GameState.historical_replay_mode or bool(save_data.get("historical_replay_mode", false)):
		return
	var save_kind := String(save_data.get("save_kind", ""))
	if save_kind not in ["manual", "daily_time_limit"]:
		return
	if not _commit_academic_save_data(save_data):
		print("RemoteSync: save commit was not durably queued; retaining pending academic events locally.")
		return
	GameState.mark_academic_commit_enqueued(save_data)
	# A daily limit ends permission to play. Keep the committed bundle durable
	# and let the next authorized session flush it rather than opening a new
	# session just to send records after the limit.
	if GameState.playtime_authorized:
		await _flush_pending()

func _on_progression_session_reset(source: String) -> void:
	if _remote_writes_blocked():
		return
	if source == "new_game":
		_stage_academic_activity_log("New Game", "New Game profile initialized", {})
	elif source == "load":
		_stage_academic_activity_log("Load Game", "Existing game profile loaded", {})

	if source == "new_game" or source == "load":
		var session_result := await _start_playtime_session()
		if source == "new_game" and bool(session_result.get("ok", false)) and _has_active_playtime_lease():
			GameState.emit_tutorial_activity_started()

func _on_game_over() -> void:
	# Game Over is a retry state, not the end of the independent Screen Time
	# session. The session is closed only when the player chooses to leave.
	return

func _on_time_limit_reached() -> void:
	if GameState.playtime_authorized or _playtime_timeout_handled:
		return
	if _session_start_in_progress:
		_playtime_timeout_pending = true
		return
	_playtime_timeout_pending = false
	_playtime_timeout_handled = true
	var time_limit_state_ready := true
	var in_battle := GameState.battle_active or GameState.get_mode() == GameState.GameMode.BATTLE \
			or GameState.current_lives <= 0
	if in_battle:
		time_limit_state_ready = GameState.prepare_daily_time_limit_state()
	else:
		var current_scene: Node = get_tree().current_scene
		if current_scene != null and GameState._is_recoverable_gameplay_scene(current_scene.scene_file_path):
			var player := get_tree().get_first_node_in_group("player_character") as Node2D
			if player != null:
				GameState.capture_runtime(current_scene.scene_file_path, player.global_position)
			time_limit_state_ready = GameState.prepare_daily_time_limit_state()
		else:
			time_limit_state_ready = GameState.prepare_daily_time_limit_state()
	if time_limit_state_ready:
		await _create_activity_log("Auto Save", "Auto-save due to daily playtime limit reached", {})
		await _create_activity_log("Timeout", "Gameplay session timed out after daily limit reached", {})
	var auto_save_path: String = GameState.save_daily_time_limit_game() if time_limit_state_ready else ""
	if not auto_save_path.is_empty():
		_commit_academic_save_data(GameState.peek_save_data(auto_save_path))
	if _remote_writes_blocked():
		# Local human QA keeps the same local-save/modal behavior without making
		# any telemetry or progress request outside the isolated runtime.
		_invalidate_playtime_lease()
	else:
		await _end_playtime_session()
		if auto_save_path.is_empty():
			print("RemoteSync: daily time-limit save was unavailable; no academic commit was created.")
	var hud := get_node_or_null("/root/GameHUD")
	if hud != null and hud.has_method("show_time_limit_reached"):
		hud.call("show_time_limit_reached")
	if auto_save_path != "":
		print("RemoteSync: local autosave completed for time-limit stop: %s" % auto_save_path)
	if get_tree() != null:
		get_tree().paused = true


func _on_playtime_warning(remaining_minutes: int) -> void:
	var notification_manager := get_node_or_null("/root/QuestNotificationManager")
	if notification_manager != null and notification_manager.has_method("show_system_notification"):
		notification_manager.call(
			"show_system_notification",
			"Playtime Reminder",
			"%d minute%s remaining today." % [remaining_minutes, "" if remaining_minutes == 1 else "s"],
			"playtime-warning:%d" % remaining_minutes
		)


func _on_task_state_changed(previous_index: int, current_index: int, event: Dictionary) -> void:
	# GameState owns progression. This observer adds no quest state or UI effects.
	_submit_canonical_task_activity(previous_index, current_index, event)


func _on_canonical_activity_boundary(event: Dictionary) -> void:
	_submit_canonical_task_activity(
		GameState.safe_int_value(event.get("previous_index", GameState.current_task_index), GameState.current_task_index),
		GameState.safe_int_value(event.get("current_index", GameState.current_task_index), GameState.current_task_index),
		event
	)


func _submit_canonical_task_activity(previous_index: int, current_index: int, event: Dictionary) -> void:
	if _remote_writes_blocked() or GameState.historical_replay_mode:
		return
	var event_type := _canonical_activity_type(GameState.safe_text_value(event.get("activity_type", event.get("type", ""))))
	if event_type.is_empty():
		return
	var metadata := _activity_metadata_for_event(previous_index, current_index, event, event_type)
	var activity_label := GameState.safe_text_value(metadata.get("activity_label", ""))
	if activity_label.is_empty():
		return
	var stable_event_key := GameState.safe_text_value(event.get("key", ""))
	if stable_event_key.is_empty():
		return
	var event_key := "cycle:%d:task:%d:%d:%s:%s" % [
		int(GameState.learning_cycle_version), previous_index, current_index, event_type, stable_event_key
	]
	var acknowledgement_key := _activity_acknowledgement_key(event_key)
	if _is_activity_acknowledged(event_key) or _activity_requests_in_flight.has(acknowledgement_key):
		return

	var canonical_event: Dictionary = GameState.build_canonical_activity_event(event, previous_index if event_type in ["task_completed", "quest_completed"] else current_index, event_type)
	var payload := {
		"session_id": _current_playtime_session_id,
		"session_credential": _current_playtime_session_credential,
		"learning_cycle_version": int(GameState.learning_cycle_version),
		"event_type": event_type,
		"event_key": event_key,
		"task_id": activity_label,
		"current_quest": GameState.safe_text_value(GameState.current_quest),
		"telemetry_contract_version": GameState.safe_text_value(canonical_event.get("telemetry_contract_version", "2.0"), "2.0"),
		"quest_graph_version": GameState.safe_text_value(canonical_event.get("quest_graph_version", "oakleaf-city-pinehill-v1"), "oakleaf-city-pinehill-v1"),
		"activity_event_id": event_key,
		"canonical_activity_id": GameState.safe_text_value(canonical_event.get("canonical_activity_id", metadata.get("activity_id", ""))),
		"canonical_quest_id": GameState.safe_text_value(canonical_event.get("canonical_quest_id", "main"), "main"),
		"canonical_task_id": GameState.safe_text_value(canonical_event.get("canonical_task_id", metadata.get("canonical_task_id", ""))),
		"canonical_milestone_id": GameState.safe_text_value(canonical_event.get("canonical_milestone_id", "")),
		"map_id": GameState.safe_text_value(canonical_event.get("map_id", GameState.canonical_map_id()), GameState.canonical_map_id()),
		"difficulty": GameState.safe_text_value(canonical_event.get("difficulty", GameState.canonical_difficulty_for_map(GameState.canonical_map_id())), GameState.canonical_difficulty_for_map(GameState.canonical_map_id())),
		"started_at": GameState.safe_text_value(canonical_event.get("started_at", "")),
		"completed_at": GameState.safe_text_value(canonical_event.get("completed_at", "")),
		"duration_seconds": canonical_event.get("duration_seconds", null),
		"is_player_facing": bool(canonical_event.get("is_player_facing", true)),
	}
	# Progression is local until the player explicitly commits it. Staging also
	# writes the event into the hidden owner-scoped checkpoint for crash safety.
	GameState.stage_pending_academic_activity(payload, CANONICAL_ACTIVITY_ENDPOINT)


func _canonical_activity_type(candidate: String) -> String:
	return GameState.safe_text_value(CANONICAL_ACTIVITY_TYPES.get(candidate, ""))


func _activity_metadata_for_event(previous_index: int, current_index: int, event: Dictionary, event_type: String) -> Dictionary:
	var explicit_metadata: Variant = event.get("activity", {})
	if explicit_metadata is Dictionary and not explicit_metadata.is_empty():
		return explicit_metadata
	var task_index := previous_index if event_type in ["task_completed", "quest_completed"] else current_index
	return GameState.get_task_activity_metadata(task_index)


func _has_active_playtime_lease() -> bool:
	return _lease_matches_context(GameState.student_id, GameState.parent_id, int(GameState.learning_cycle_version))


func _lease_matches_context(student_id: String, parent_id: String, learning_cycle_version: int) -> bool:
	return (
		GameState.playtime_authorized
		and _lease_is_bound_to_context(student_id, parent_id, learning_cycle_version)
	)


func _lease_is_bound_to_context(student_id: String, parent_id: String, learning_cycle_version: int) -> bool:
	return (
		_current_playtime_session_id != 0
		and not _current_playtime_session_credential.is_empty()
		and _current_playtime_student_id == student_id.strip_edges()
		and _current_playtime_parent_id == parent_id.strip_edges()
		and _current_playtime_learning_cycle_version == learning_cycle_version
	)


func _lease_identity_matches(session_id: int, session_credential: String, student_id: String, parent_id: String, learning_cycle_version: int) -> bool:
	return (
		_current_playtime_session_id == session_id
		and _current_playtime_session_credential == session_credential
		and _current_playtime_student_id == student_id
		and _current_playtime_parent_id == parent_id
		and _current_playtime_learning_cycle_version == learning_cycle_version
	)


func _capture_playtime_lease_identity() -> Dictionary:
	return {
		"session_id": _current_playtime_session_id,
		"session_credential": _current_playtime_session_credential,
		"student_id": _current_playtime_student_id,
		"parent_id": _current_playtime_parent_id,
		"learning_cycle_version": _current_playtime_learning_cycle_version,
	}


func _lease_snapshot_matches_current(lease: Dictionary) -> bool:
	return _lease_identity_matches(
		GameState.safe_int_value(lease.get("session_id", 0), 0),
		GameState.safe_text_value(lease.get("session_credential", "")),
		GameState.safe_text_value(lease.get("student_id", "")),
		GameState.safe_text_value(lease.get("parent_id", "")),
		GameState.safe_int_value(lease.get("learning_cycle_version", -1), -1)
	)


func _invalidate_playtime_lease() -> void:
	_current_playtime_session_id = 0
	_current_playtime_session_credential = ""
	_current_playtime_student_id = ""
	_current_playtime_parent_id = ""
	_current_playtime_learning_cycle_version = -1
	_playtime_heartbeat_elapsed = 0.0


func _activity_acknowledgement_key(event_key: String, student_id: String = "") -> String:
	var scoped_student_id := student_id.strip_edges()
	if scoped_student_id.is_empty():
		scoped_student_id = GameState.safe_text_value(GameState.student_id)
	return "%s:%s" % [scoped_student_id, event_key]


func _is_activity_acknowledged(event_key: String) -> bool:
	return _acknowledged_activity_keys.has(_activity_acknowledgement_key(event_key))


func _is_activity_lease_rejected(result: Dictionary) -> bool:
	return _is_playtime_lease_rejected(result)


func _is_stale_playtime_lease(result: Dictionary) -> bool:
	if GameState.safe_int_value(result.get("status", 0), 0) != 409:
		return false
	var body: Variant = result.get("body", {})
	return body is Dictionary and GameState.safe_text_value(body.get("code", "")) == "PLAYTIME_HEARTBEAT_STALE"


func _is_playtime_lease_rejected(result: Dictionary) -> bool:
	var status := GameState.safe_int_value(result.get("status", 0), 0)
	return status == 401 or status == 403 or _is_stale_playtime_lease(result)
func _apply_learning_cycle(response_body: Variant) -> Dictionary:
	if not (response_body is Dictionary):
		return {}
	var descriptor: Variant = response_body.get("learning_cycle", {})
	if descriptor is Dictionary and descriptor.has("version") and GameState.set_learning_cycle(descriptor):
		return GameState.get_learning_cycle_descriptor()
	return {}


func _is_learning_cycle_changed(result: Dictionary) -> bool:
	if GameState.safe_int_value(result.get("status", 0), 0) != 409:
		return false
	var body: Variant = result.get("body", {})
	return body is Dictionary and GameState.safe_text_value(body.get("code", "")) == "LEARNING_CYCLE_CHANGED"

func _commit_academic_save_data(save_data: Dictionary) -> bool:
	if _remote_writes_blocked() or GameState.historical_replay_mode \
			or bool(save_data.get("historical_replay_mode", false)):
		return false
	var save_kind := String(save_data.get("save_kind", ""))
	if save_kind not in ["manual", "daily_time_limit"]:
		return false
	var student_id := GameState.safe_text_value(save_data.get("student_id", ""))
	var parent_id := GameState.safe_text_value(save_data.get("parent_id", ""))
	var commit_id := GameState.safe_text_value(save_data.get("save_commit_id", ""))
	if not GameState.is_valid_existing_student_id(student_id) \
			or not GameState.is_valid_six_digit_id(parent_id) or commit_id.is_empty():
		return false
	if student_id != GameState.safe_text_value(GameState.student_id) \
			or parent_id != GameState.safe_text_value(GameState.parent_id) \
			or int(save_data.get("learning_cycle_version", -1)) != int(GameState.learning_cycle_version):
		return false
	var queue := _load_pending()
	var queued_ids: Dictionary = {}
	for item: Variant in queue:
		if item is Dictionary:
			queued_ids[_pending_item_identity(item)] = true
	var environment_scope := _current_environment_scope()
	var results: Variant = save_data.get("pending_academic_results", [])
	if results is Array:
		for result: Variant in results:
			if not (result is Dictionary):
				continue
			var result_payload: Dictionary = result.duplicate(true)
			if String(result_payload.get("student_id", "")) != student_id \
					or String(result_payload.get("parent_id", "")) != parent_id \
					or int(result_payload.get("learning_cycle_version", -1)) != int(save_data.get("learning_cycle_version", -2)):
				continue
			result_payload.erase("playtime_session_id")
			result_payload.erase("playtime_session_credential")
			result_payload.erase("session_id")
			result_payload["environment_scope"] = environment_scope
			var item := {
				"kind": "result",
				"path": CANONICAL_RESULT_ENDPOINT,
				"environment_scope": environment_scope,
				"student_id": student_id,
				"parent_id": parent_id,
				"learning_cycle_version": int(save_data.get("learning_cycle_version", 0)),
				"payload": result_payload,
			}
			var identity := _pending_item_identity(item)
			if not queued_ids.has(identity):
				queue.append(item)
				queued_ids[identity] = true
	var activities: Variant = save_data.get("pending_academic_activities", [])
	if activities is Array:
		for activity: Variant in activities:
			if not (activity is Dictionary):
				continue
			var event_key := GameState.safe_text_value(activity.get("event_key", ""))
			var activity_owner := GameState.safe_text_value(activity.get("student_id", ""))
			var activity_parent := GameState.safe_text_value(activity.get("parent_id", ""))
			var activity_cycle := GameState.safe_int_value(activity.get("learning_cycle_version", -1), -1)
			var nested_payload: Variant = activity.get("payload", {})
			var endpoint := GameState.safe_text_value(activity.get("path", CANONICAL_ACTIVITY_ENDPOINT))
			if event_key.is_empty() or activity_owner != student_id or activity_parent != parent_id \
					or activity_cycle != int(save_data.get("learning_cycle_version", -2)) \
					or not (nested_payload is Dictionary) \
					or endpoint not in [CANONICAL_ACTIVITY_ENDPOINT, "/api/activity-logs"]:
				continue
			var activity_payload: Dictionary = nested_payload.duplicate(true)
			activity_payload.erase("session_id")
			activity_payload.erase("session_credential")
			activity_payload["event_key"] = event_key
			activity_payload["activity_event_id"] = event_key
			activity_payload["environment_scope"] = environment_scope
			var item := {
				"kind": "activity",
				"path": endpoint,
				"environment_scope": environment_scope,
				"student_id": student_id,
				"parent_id": parent_id,
				"learning_cycle_version": int(save_data.get("learning_cycle_version", 0)),
				"payload": activity_payload,
			}
			var identity := _pending_item_identity(item)
			if not queued_ids.has(identity):
				queue.append(item)
				queued_ids[identity] = true
	var progress_payload := _build_progress_commit_payload(save_data)
	progress_payload["environment_scope"] = environment_scope
	var progress_item := {
		"kind": "progress_commit",
		"path": "/api/game/progress",
		"environment_scope": environment_scope,
		"student_id": student_id,
		"parent_id": parent_id,
		"learning_cycle_version": int(save_data.get("learning_cycle_version", 0)),
		"save_commit_id": commit_id,
		"payload": progress_payload,
	}
	var progress_identity := _pending_item_identity(progress_item)
	if not queued_ids.has(progress_identity):
		queue.append(progress_item)
		queued_ids[progress_identity] = true
	return _persist_pending_queue(queue)


func _build_progress_commit_payload(save_data: Dictionary) -> Dictionary:
	return {
		"parent_id": GameState.safe_text_value(save_data.get("parent_id", "")),
		"student_id": GameState.safe_text_value(save_data.get("student_id", "")),
		"student_name": GameState.safe_text_value(save_data.get("player_name", save_data.get("student_name", ""))),
		"grade_level": GameState.safe_text_value(save_data.get("grade_level", "")),
		"gender": GameState.safe_text_value(save_data.get("gender", "")),
		"current_quest": GameState.safe_text_value(save_data.get("current_quest", "")),
		"quest_progress": GameState.safe_int_value(save_data.get("current_task_index", 0), 0),
		"lesson_progress": GameState.safe_int_value(save_data.get("lesson_progress", 0), 0),
		"progress_percentage": GameState.safe_int_value(save_data.get("progress_percentage", save_data.get("completion_percentage", 0)), 0),
		"current_scene": GameState.safe_text_value(save_data.get("scene_path", save_data.get("current_scene", ""))),
		"current_map": GameState.safe_text_value(save_data.get("current_map", save_data.get("scene_path", ""))),
		"save_timestamp": GameState.safe_int_value(save_data.get("save_timestamp", 0), 0),
		"save_time": GameState.safe_text_value(save_data.get("save_time", "")),
		"save_date": GameState.safe_text_value(save_data.get("save_date", "")),
		"score": GameState.safe_int_value(save_data.get("score", 0), 0),
		"correct_answers": GameState.safe_int_value(save_data.get("correct_answers", 0), 0),
		"incorrect_answers": GameState.safe_int_value(save_data.get("incorrect_answers", 0), 0),
		"total_questions": GameState.safe_int_value(save_data.get("total_questions", 0), 0),
		"total_play_time": GameState.safe_int_value(save_data.get("total_play_time", 0), 0),
		"total_quests_completed": GameState.safe_int_value(save_data.get("total_quests_completed", 0), 0),
		"difficulty_level": GameState.safe_text_value(save_data.get("difficulty_level", "Unknown"), "Unknown"),
		"learning_cycle_version": GameState.safe_int_value(save_data.get("learning_cycle_version", GameState.learning_cycle_version), GameState.learning_cycle_version),
		"save_commit_id": GameState.safe_text_value(save_data.get("save_commit_id", "")),
		"commit_trigger": GameState.safe_text_value(save_data.get("commit_trigger", "")),
		"save_status": "saved",
	}


func _persist_pending_queue(queue: Array) -> bool:
	var directory := _pending_file.get_base_dir()
	if directory.is_empty():
		return false
	var absolute_directory := ProjectSettings.globalize_path(directory)
	if not DirAccess.dir_exists_absolute(absolute_directory) \
			and DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var nonce := str(Time.get_ticks_usec())
	var temporary_path := "%s.%s.tmp" % [_pending_file, nonce]
	var backup_path := "%s.%s.backup" % [_pending_file, nonce]
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(queue))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not _is_valid_pending_queue(_load_pending_queue_from_path(temporary_path)):
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	var had_existing := FileAccess.file_exists(_pending_file)
	if had_existing and DirAccess.rename_absolute(ProjectSettings.globalize_path(_pending_file), ProjectSettings.globalize_path(backup_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(_pending_file)) != OK:
		if had_existing:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(_pending_file))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	if had_existing and FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	return true


func _load_pending_queue_from_path(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Array else []


func _async_send_progress(save_data: Dictionary) -> void:
	if _remote_writes_blocked() or GameState.historical_replay_mode \
			or bool(save_data.get("historical_replay_mode", false)):
		return
	# perform non-blocking via thread? We'll do simple call and rely on HttpApi's await behavior
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		print("RemoteSync: HttpApi unavailable; queueing sync")
		_enqueue_pending(save_data)
		return
	# Build the payload as a real Save Game projection of the authoritative runtime fields.
	# The backend already normalizes these fields into student_game_progress and activity_logs.
	var payload := {
		"parent_id": GameState.safe_text_value(save_data.get("parent_id", "")),
		"student_id": GameState.safe_text_value(save_data.get("student_id", "")),
		"student_name": GameState.safe_text_value(save_data.get("player_name", save_data.get("student_name", ""))),
		"grade_level": GameState.safe_text_value(save_data.get("grade_level", "")),
		"gender": GameState.safe_text_value(save_data.get("gender", "")),
		"current_quest": GameState.safe_text_value(save_data.get("current_quest", "")),
		"quest_progress": GameState.safe_int_value(save_data.get("current_task_index", 0), 0),
		"lesson_progress": GameState.safe_int_value(save_data.get("lesson_progress", 0), 0),
		"progress_percentage": GameState.safe_int_value(save_data.get("progress_percentage", save_data.get("completion_percentage", 0)), 0),
		"current_scene": GameState.safe_text_value(save_data.get("scene_path", save_data.get("current_scene", ""))),
		"current_map": GameState.safe_text_value(save_data.get("current_map", save_data.get("scene_path", ""))),
		"save_timestamp": GameState.safe_int_value(save_data.get("save_timestamp", 0), 0),
		"save_time": GameState.safe_text_value(save_data.get("save_time", "")),
		"save_date": GameState.safe_text_value(save_data.get("save_date", "")),
		"score": GameState.safe_int_value(save_data.get("score", 0), 0),
		"correct_answers": GameState.safe_int_value(save_data.get("correct_answers", 0), 0),
		"incorrect_answers": GameState.safe_int_value(save_data.get("incorrect_answers", 0), 0),
		"total_questions": GameState.safe_int_value(save_data.get("total_questions", 0), 0),
		"total_play_time": GameState.safe_int_value(save_data.get("total_play_time", 0), 0),
		"total_quests_completed": GameState.safe_int_value(save_data.get("total_quests_completed", 0), 0),
		"difficulty_level": GameState.safe_text_value(save_data.get("difficulty_level", "Unknown"), "Unknown"),
		"learning_cycle_version": GameState.safe_int_value(save_data.get("learning_cycle_version", GameState.learning_cycle_version), GameState.learning_cycle_version),
		"playtime_session_id": _current_playtime_session_id,
		"playtime_session_credential": _current_playtime_session_credential,
		"save_status": "saved"
	}
	var result: Dictionary = await http.request_post("/api/game/progress", payload)
	if _is_learning_cycle_changed(result):
		print("RemoteSync: discarded a previous-learning-cycle progress write.")
		return
	if not result.ok:
		print("RemoteSync: progress sync failed, queuing: %s" % str(result))
		_enqueue_pending(save_data)
		return
	if result.status >= 200 and result.status < 300:
		print("RemoteSync: progress synced")
		# try flushing pending
		_flush_pending()
	else:
		print("RemoteSync: unexpected status %s" % str(result))
		_enqueue_pending(save_data)

func _build_playtime_start_payload(override_payload: Dictionary = {}) -> Dictionary:
	var payload := {
		"student_id": GameState.safe_text_value(override_payload.get("student_id", GameState.student_id)),
		"parent_id": GameState.safe_text_value(override_payload.get("parent_id", GameState.parent_id)),
		"student_name": GameState.safe_text_value(override_payload.get("student_name", GameState.player_name)),
		"grade_level": GameState.safe_text_value(override_payload.get("grade_level", GameState.grade_level)),
		"section": GameState.safe_text_value(override_payload.get("section", ""))
	}
	return payload

func _send_playtime_start_request(override_payload: Dictionary = {}) -> Dictionary:
	if _remote_writes_blocked():
		return {"ok": false, "error": "Local QA mode disables playtime writes", "should_block": false}
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Playtime service unavailable", "should_block": false}

	var payload := _build_playtime_start_payload(override_payload)
	if not GameState.is_valid_existing_student_id(payload.get("student_id", "")) or not GameState.is_valid_six_digit_id(payload.get("parent_id", "")):
		return {"ok": false, "error": "Invalid student or parent ID", "should_block": false}

	return await http.request_post("/api/playtime/start", payload)

func _send_playtime_end_request(lease: Dictionary = {}) -> Dictionary:
	if _remote_writes_blocked():
		return {"ok": false, "error": "Local QA mode disables playtime writes", "should_block": false}
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Playtime service unavailable", "should_block": false}

	var session_id := GameState.safe_int_value(lease.get("session_id", _current_playtime_session_id), 0)
	var session_credential := GameState.safe_text_value(lease.get("session_credential", _current_playtime_session_credential))
	if session_id == 0 or session_credential.is_empty():
		return {"ok": false, "error": "No active server playtime lease", "should_block": false}
	var payload := {
		"session_id": session_id,
		"session_credential": session_credential,
		"status": "Timed Out" if not GameState.playtime_authorized else "Completed",
	}

	return await http.request_post("/api/playtime/end", payload)


func _send_playtime_heartbeat_request(lease: Dictionary = {}) -> Dictionary:
	if _remote_writes_blocked():
		return {"ok": false, "error": "Local QA mode disables playtime writes", "should_block": false}
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Playtime service unavailable", "should_block": false}
	var session_id := GameState.safe_int_value(lease.get("session_id", _current_playtime_session_id), 0)
	var session_credential := GameState.safe_text_value(lease.get("session_credential", _current_playtime_session_credential))
	if session_id == 0 or session_credential.is_empty():
		return {"ok": false, "error": "No active server playtime lease", "should_block": false}
	return await http.request_post("/api/playtime/heartbeat", {
		"session_id": session_id,
		"session_credential": session_credential,
	})


func _refresh_playtime_lease() -> void:
	if _playtime_heartbeat_in_progress or not _has_active_playtime_lease():
		return
	_playtime_heartbeat_in_progress = true
	var lease := _capture_playtime_lease_identity()
	var result := await _send_playtime_heartbeat_request(lease)
	if not _lease_snapshot_matches_current(lease):
		_playtime_heartbeat_in_progress = false
		return
	if _is_learning_cycle_changed(result):
		GameState.configure_playtime_allowance({
			"daily_limit_minutes": PLAYTIME_DAILY_LIMIT_MINUTES,
			"remaining_seconds": 0,
			"can_play": false,
		}, false)
		_playtime_heartbeat_in_progress = false
		return
	if _is_stale_playtime_lease(result):
		_invalidate_playtime_lease()
		_playtime_heartbeat_in_progress = false
		return
	var response_body: Variant = result.get("body", null)
	var response_status := GameState.safe_int_value(result.get("status", 0), 0)
	if (
		bool(result.get("ok", false))
		and response_status >= 200
		and response_status < 300
		and response_body is Dictionary
		and not response_body.is_empty()
	):
		GameState.configure_playtime_allowance(response_body, false)
	if result.ok and result.status >= 200 and result.status < 300:
		_playtime_timeout_handled = false
		# A successful heartbeat is the reconnect signal for this active Student.
		# Resume durable progress/result/activity writes without blocking the heartbeat.
		_flush_pending.call_deferred()
	else:
		# A 403 is a server-authoritative expiry. Other transport failures keep
		# the previously issued lease until the next heartbeat rather than making
		# a client-side decision about remaining time.
		if result.status == 403:
			GameState.configure_playtime_allowance({
				"daily_limit_minutes": PLAYTIME_DAILY_LIMIT_MINUTES,
				"remaining_seconds": 0,
				"can_play": false,
			}, false)
	_playtime_heartbeat_in_progress = false

func _create_activity_log(status: String, description: String, override_payload: Dictionary = {}) -> void:
	if _remote_writes_blocked():
		return
	if status not in ["Playing", "Offline"]:
		_stage_academic_activity_log(status, description, override_payload)
		return
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return
	var payload := _build_activity_log_payload(status, description, override_payload)
	if payload.is_empty():
		return
	var result: Dictionary = await http.request_post("/api/activity-logs", payload)
	if not result.ok:
		print("RemoteSync: activity log failed: %s" % str(result.error))


func _stage_academic_activity_log(status: String, description: String, override_payload: Dictionary = {}) -> void:
	if _remote_writes_blocked():
		return
	var payload := _build_activity_log_payload(status, description, override_payload)
	if payload.is_empty():
		return
	var event_key := "cycle:%d:app:%s:%s:%d" % [
		int(GameState.learning_cycle_version), status.to_lower().replace(" ", "_"),
		GameState.safe_text_value(payload.get("student_id", "")), Time.get_ticks_usec()
	]
	payload["event_key"] = event_key
	payload["activity_event_id"] = event_key
	GameState.stage_pending_academic_activity(payload, "/api/activity-logs")


func _build_activity_log_payload(status: String, description: String, override_payload: Dictionary) -> Dictionary:
	var student_id := GameState.safe_text_value(override_payload.get("student_id", GameState.student_id))
	if not GameState.is_valid_existing_student_id(student_id):
		return {}
	var payload := {
		"student_id": student_id,
		"parent_id": GameState.safe_text_value(override_payload.get("parent_id", GameState.parent_id)),
		"student_name": GameState.safe_text_value(override_payload.get("student_name", GameState.player_name)),
		"grade_level": GameState.safe_text_value(override_payload.get("grade_level", GameState.grade_level)),
		"section": GameState.safe_text_value(override_payload.get("section", "")),
		"current_quest": GameState.safe_text_value(override_payload.get("current_quest", "")),
		"save_status": "playing" if status == "Playing" else "saved",
		"total_play_time": 0,
		"quest_progress": GameState.safe_int_value(override_payload.get("quest_progress", 0), 0),
		"role": "Student",
		"status": status,
		"activity_description": description
	}
	return payload

func _finish_playtime_start_transition() -> void:
	_session_start_in_progress = false
	if _playtime_timeout_pending and not GameState.playtime_authorized:
		_playtime_timeout_pending = false
		_on_time_limit_reached.call_deferred()


func _start_playtime_session(override_payload: Dictionary = {}) -> Dictionary:
	var requested_payload := _build_playtime_start_payload(override_payload)
	var requested_student_id := GameState.safe_text_value(requested_payload.get("student_id", ""))
	var requested_parent_id := GameState.safe_text_value(requested_payload.get("parent_id", ""))
	var requested_cycle_version := int(GameState.learning_cycle_version)
	var force_refresh := bool(override_payload.get("_force_refresh", false))
	if not force_refresh and _lease_matches_context(requested_student_id, requested_parent_id, requested_cycle_version):
		return {
			"ok": true,
			"session_id": _current_playtime_session_id,
			"can_play": true,
			"learning_cycle": GameState.get_learning_cycle_descriptor(),
		}
	if _session_start_in_progress:
		return {"ok": false, "error": "Playtime session start already pending", "should_block": false, "can_play": false}
	if _playtime_end_in_progress:
		return {"ok": false, "error": "Playtime session end already pending", "should_block": false, "can_play": false}
	_session_start_in_progress = true
	if _current_playtime_session_id != 0 or not _current_playtime_session_credential.is_empty():
		# Close the previous bound lease before changing Student/cycle context. The
		# lease credential authenticates this end request even when GameState has
		# already moved to the next profile.
		var previous_lease := _capture_playtime_lease_identity()
		var end_result := await _send_playtime_end_request(previous_lease)
		var end_status := GameState.safe_int_value(end_result.get("status", 0), 0)
		var old_lease_closed := bool(end_result.get("ok", false)) and end_status >= 200 and end_status < 300
		var old_lease_rejected := end_status in [401, 403, 404, 409]
		if _lease_snapshot_matches_current(previous_lease):
			if old_lease_closed or old_lease_rejected:
				_invalidate_playtime_lease()
			else:
				_finish_playtime_start_transition()
				return {
					"ok": false,
					"status": end_status,
					"error": "Unable to close the previous playtime session safely.",
					"should_block": false,
					"can_play": false,
				}
		elif _current_playtime_session_id != 0 or not _current_playtime_session_credential.is_empty():
			_finish_playtime_start_transition()
			return {"ok": false, "error": "Playtime lease changed during session transition.", "should_block": false, "can_play": false}

	var result: Dictionary = {}
	var final_result: Dictionary = {}
	
	result = await _send_playtime_start_request(requested_payload)
	if result.ok and (result.status == 201 or result.status == 200):
		var learning_cycle := _apply_learning_cycle(result.body)
		var api_can_play := bool(result.body.get("can_play", true))
		var is_new_registration := bool(result.body.get("is_new_registration", false))
		
		if api_can_play == false:
			GameState.configure_playtime_allowance(result.body, true)
			final_result = {
				"ok": false,
				"status": result.status,
				"error": String(result.body.get("error", "Daily playtime limit reached.")),
				"message": String(result.body.get("message", "Daily playtime limit reached.")),
				"should_block": true,
				"can_play": false,
				"remaining_minutes": GameState.safe_int_value(result.body.get("remaining_minutes", 0), 0),
				"daily_limit_minutes": GameState.safe_int_value(result.body.get("daily_limit_minutes", 60), 60),
			}
		elif is_new_registration:
			# New student registration: allow without creating session yet
			GameState.configure_playtime_allowance(result.body, true)
			_invalidate_playtime_lease()
			final_result = {
				"ok": true,
				"session_id": 0,
				"is_new_registration": true,
				"remaining_minutes": GameState.safe_int_value(result.body.get("remaining_minutes", PLAYTIME_DAILY_LIMIT_MINUTES), PLAYTIME_DAILY_LIMIT_MINUTES),
				"daily_limit_minutes": GameState.safe_int_value(result.body.get("daily_limit_minutes", PLAYTIME_DAILY_LIMIT_MINUTES), PLAYTIME_DAILY_LIMIT_MINUTES),
				"total_playtime_today": GameState.safe_int_value(result.body.get("total_playtime_today", 0), 0),
				"can_play": true,
				"learning_cycle": learning_cycle,
				"message": String(result.body.get("message", "New student registration ready.")),
			}
		else:
			GameState.configure_playtime_allowance(result.body, true)
			_current_playtime_session_id = GameState.safe_int_value(result.body.get("session_id", 0), 0)
			_current_playtime_session_credential = GameState.safe_text_value(result.body.get("session_credential", ""))
			_current_playtime_student_id = requested_student_id
			_current_playtime_parent_id = requested_parent_id
			_current_playtime_learning_cycle_version = int(GameState.learning_cycle_version)
			_playtime_heartbeat_elapsed = 0.0
			_playtime_timeout_handled = false
			if _current_playtime_session_id != 0 and not _current_playtime_session_credential.is_empty():
				await _create_activity_log("Playing", "Gameplay session started", requested_payload)
				final_result = {
					"ok": true,
					"session_id": _current_playtime_session_id,
					"remaining_minutes": GameState.safe_int_value(result.body.get("remaining_minutes", 60), 60),
					"remaining_seconds": GameState.safe_int_value(result.body.get("remaining_seconds", 60 * 60), 60 * 60),
					"daily_limit_minutes": GameState.safe_int_value(result.body.get("daily_limit_minutes", 60), 60),
					"total_playtime_today": GameState.safe_int_value(result.body.get("total_playtime_today", 0), 0),
					"can_play": true,
					"learning_cycle": learning_cycle,
					"message": String(result.body.get("message", "Playtime session started.")),
				}
			else:
				_invalidate_playtime_lease()
				final_result = {"ok": false, "error": "Playtime session did not return a valid server lease", "should_block": false, "can_play": false}
	else:
		var error_message := "Unable to start playtime session"
		if typeof(result.body) == TYPE_DICTIONARY and result.body.has("error"):
			error_message = String(result.body.get("error"))
		final_result = {
			"ok": false,
			"status": result.status,
			"error": error_message,
			"message": String(result.body.get("message", error_message)) if typeof(result.body) == TYPE_DICTIONARY else error_message,
			"should_block": result.status == 403,
			"can_play": false,
		}

	_finish_playtime_start_transition()
	if bool(final_result.get("ok", false)) and _current_playtime_session_id != 0 and not _pending_flush_in_progress:
		_flush_pending.call_deferred()
	return final_result

func _end_playtime_session() -> Dictionary:
	if not _lease_is_bound_to_context(GameState.student_id, GameState.parent_id, int(GameState.learning_cycle_version)):
		return {"ok": false, "error": "Missing active server playtime lease", "should_block": false}
	if _session_start_in_progress or _playtime_end_in_progress:
		return {"ok": false, "error": "Playtime session transition already pending", "should_block": false}

	var lease := _capture_playtime_lease_identity()
	var activity_identity := {
		"student_id": GameState.student_id,
		"student_name": GameState.player_name,
		"grade_level": GameState.grade_level,
	}
	_playtime_end_in_progress = true
	var result := await _send_playtime_end_request(lease)
	_playtime_end_in_progress = false
	if not _lease_snapshot_matches_current(lease):
		return {"ok": false, "error": "Playtime lease changed while the prior session was ending.", "should_block": false}
	if not result.ok:
		return result

	if result.status == 200:
		_invalidate_playtime_lease()
		await _create_activity_log("Offline", "Gameplay session ended", activity_identity)
		return {"ok": true}

	var error_message := "Unable to end playtime session"
	if typeof(result.body) == TYPE_DICTIONARY and result.body.has("error"):
		error_message = String(result.body.get("error"))

	return {"ok": false, "status": result.status, "error": error_message, "should_block": false}

func request_playtime_session(override_payload: Dictionary = {}) -> Dictionary:
	# Public wrapper for UI code to start or resume a backend-authoritative playtime session.
	return await _start_playtime_session(override_payload)

func request_learning_cycle(student_code: String, parent_code: String) -> Dictionary:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Unable to verify Learning Cycle. Connect to continue."}
	if not GameState.is_valid_existing_student_id(student_code) or not GameState.is_valid_six_digit_id(parent_code):
		return {"ok": false, "error": "This save is missing a valid Parent or Student ID."}
	var result: Dictionary = await http.request_get("/api/game/learning-cycle/" + student_code, {"parent_id": parent_code})
	var body: Variant = result.get("body", {})
	var status := GameState.safe_int_value(result.get("status", 0), 0)
	if not result.get("ok", false) or status < 200 or status >= 300:
		return {"ok": false, "status": status, "error": "Unable to verify Learning Cycle. Connect to continue."}
	var descriptor := _apply_learning_cycle(body)
	if descriptor.is_empty():
		return {"ok": false, "status": status, "error": "Unable to verify Learning Cycle. Connect to continue."}
	return {"ok": true, "status": status, "learning_cycle": descriptor}

func request_end_playtime_session() -> Dictionary:
	# Public wrapper for UI or scene lifecycle code to cleanly end the current playtime session.
	return await _end_playtime_session()


func request_game_leaderboard() -> Dictionary:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "status": 0, "error": "Leaderboard service unavailable.", "entries": []}
	var result: Dictionary = await http.request_get("/api/game/leaderboard")
	var status := GameState.safe_int_value(result.get("status", 0), 0)
	if not bool(result.get("ok", false)) or status < 200 or status >= 300:
		return {"ok": false, "status": status, "error": "Leaderboard unavailable.", "entries": []}
	var body: Variant = result.get("body", {})
	var entries: Array = []
	if body is Dictionary:
		var raw_entries: Variant = body.get("entries", [])
		if raw_entries is Array:
			entries = _sanitize_game_leaderboard_entries(raw_entries)
	return {"ok": true, "status": status, "entries": entries}


func _sanitize_game_leaderboard_entries(raw_entries: Array) -> Array:
	var sanitized: Array = []
	for raw_entry in raw_entries:
		if not (raw_entry is Dictionary):
			continue
		var rank := GameState.safe_int_value(raw_entry.get("rank", 0), 0)
		var display_name := GameState.safe_text_value(raw_entry.get("display_name", ""))
		if rank <= 0 or display_name.is_empty():
			continue
		var entry := {
			"rank": rank,
			"display_name": display_name,
			"correct_answers": _normalize_leaderboard_number(raw_entry.get("correct_answers", null)),
		}
		if raw_entry.has("grade"):
			entry["grade"] = GameState.safe_text_value(raw_entry.get("grade", ""))
		sanitized.append(entry)
	# The game mirrors the canonical website ranking order but only exposes the
	# approved six public rows. Keep the API order; do not re-rank locally.
	return sanitized.slice(0, 6)


func _normalize_leaderboard_number(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		return value if is_finite(value) else null
	if value is String:
		var parsed := GameState.safe_float_value(value, -1.0)
		if parsed >= 0.0:
			return parsed
		return null
	return null


func record_question_attempt(question: Dictionary, is_correct: bool) -> void:
	if _remote_writes_blocked():
		return
	if not GameState.is_valid_existing_student_id(GameState.student_id) or not GameState.is_valid_six_digit_id(GameState.parent_id):
		return
	var payload := _build_question_result_payload(question, is_correct)
	# A graded answer is academic progress. Persist it locally, but do not create
	# an outbox item or make a network request until an approved save boundary.
	GameState.stage_pending_academic_result(payload)


func _build_question_result_payload(question: Dictionary, is_correct: bool) -> Dictionary:
	var question_identity := str(question.get("question_id", question.get("id", ""))).strip_edges()
	if question_identity.is_empty():
		question_identity = "question:%s" % str(question.get("question", question.get("text", ""))).strip_edges().to_lower().hash()
	var battle_identity := str(GameState.encounter_context.get("encounter_id", "")).strip_edges()
	if battle_identity.is_empty():
		battle_identity = str(question.get("battle_id", question.get("encounter_id", ""))).strip_edges()
	if battle_identity.is_empty():
		battle_identity = "task-%d" % int(GameState.current_task_index)
	# Every submitted answer is its own canonical event, even when a player sees
	# the same question again in a later battle retry.  The payload is built once
	# and then retained verbatim by the outbox, so transport retries keep this ID
	# while genuine subsequent answers receive a new one.
	var retry_count: int = maxi(0, int(GameState.encounter_context.get("retry_count", 0)))
	var answer_trace := ("%s|%s" % [battle_identity, question_identity]).sha256_text().substr(0, 24)
	var answer_nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	var result_event_id := "cycle:%d:attempt:%d:answer:%s:%s" % [int(GameState.learning_cycle_version), retry_count, answer_trace, answer_nonce]
	var payload := {
		"parent_id": GameState.parent_id,
		"student_id": GameState.student_id,
		"student_name": GameState.player_name,
		"grade_level": GameState.grade_level,
		"difficulty": str(question.get("difficulty", "Unknown")).strip_edges(),
		"score": 1 if is_correct else 0,
		"total_items": 1,
		"playtime_session_id": _current_playtime_session_id,
		"playtime_session_credential": _current_playtime_session_credential,
		"learning_cycle_version": GameState.learning_cycle_version,
		"result_event_id": result_event_id,
		"telemetry_contract_version": GameState.TELEMETRY_CONTRACT_VERSION,
		"quest_graph_version": GameState.QUEST_GRAPH_VERSION,
		"session_id": _current_playtime_session_id,
		"map_id": GameState.canonical_map_id(),
		"canonical_quest_id": "main",
		"canonical_task_id": GameState.get_task_activity_metadata(GameState.current_task_index).get("canonical_task_id", ""),
		"canonical_battle_id": battle_identity,
		"canonical_milestone_id": str(question.get("milestone_id", "")),
	}
	var question_set_id: Variant = question.get("question_set_id", null)
	if question_set_id is int and question_set_id > 0:
		payload["question_set_id"] = question_set_id
	var canonical_question_id: Variant = question.get("question_id", null)
	if canonical_question_id is int and canonical_question_id > 0:
		payload["question_id"] = canonical_question_id
	var raw_topic_id: Variant = question.get("topic_id", null)
	var canonical_topic_id := "" if raw_topic_id == null else str(raw_topic_id).strip_edges()
	# The backend accepts topic evidence only when it can verify the question ID
	# against its canonical question set. Legacy/local IDs remain event identity
	# only and must not make an otherwise valid legacy result fail validation.
	if canonical_question_id is int and canonical_question_id > 0 and not canonical_topic_id.is_empty():
		payload["topic_id"] = canonical_topic_id
	var question_presented_at := str(question.get("question_presented_at", "")).strip_edges()
	var answer_submitted_at := str(question.get("answer_submitted_at", "")).strip_edges()
	var response_time_seconds := GameState.safe_int_value(question.get("response_time_seconds", -1), -1)
	if not question_presented_at.is_empty():
		payload["question_presented_at"] = question_presented_at
	if not answer_submitted_at.is_empty():
		payload["answer_submitted_at"] = answer_submitted_at
	if response_time_seconds >= 0:
		payload["response_time_seconds"] = response_time_seconds
	return payload


func _update_result_lease_fields(payload: Dictionary) -> void:
	payload["playtime_session_id"] = _current_playtime_session_id
	payload["playtime_session_credential"] = _current_playtime_session_credential
	payload["session_id"] = _current_playtime_session_id
	payload["learning_cycle_version"] = int(GameState.learning_cycle_version)


func _update_activity_lease_fields(payload: Dictionary) -> void:
	payload["session_id"] = _current_playtime_session_id
	payload["session_credential"] = _current_playtime_session_credential
	payload["learning_cycle_version"] = int(GameState.learning_cycle_version)


func _update_progress_lease_fields(payload: Dictionary) -> void:
	payload["playtime_session_id"] = _current_playtime_session_id
	payload["playtime_session_credential"] = _current_playtime_session_credential
	payload["learning_cycle_version"] = int(GameState.learning_cycle_version)


func _format_outbox_failure_diagnostic(endpoint: String, result: Dictionary) -> String:
	var status := GameState.safe_int_value(result.get("status", 0), 0)
	var body: Variant = result.get("body", {})
	var error_text := ""
	var error_code := ""
	if body is Dictionary:
		error_text = _safe_backend_diagnostic_text(body.get("error", ""))
		error_code = _safe_backend_diagnostic_text(body.get("code", ""))
	var details := ""
	if not error_code.is_empty():
		details += " code=%s" % error_code
	if not error_text.is_empty():
		details += " error=%s" % error_text
	return "RemoteSync: POST %s rejected HTTP %d%s" % [endpoint, status, details]


func _safe_backend_diagnostic_text(value: Variant) -> String:
	var text := str(value).strip_edges().replace("\r", " ").replace("\n", " ")
	if text.is_empty():
		return ""
	if not _current_playtime_session_credential.is_empty():
		text = text.replace(_current_playtime_session_credential, "[redacted]")
	var secret_pattern := RegEx.new()
	if secret_pattern.compile("(?i)(password|session[_ -]?credential|credential|authorization|token)(\\s*[:=]\\s*|\\s+)[^\\s,;]+") == OK:
		text = secret_pattern.sub(text, "$1 [redacted]", true)
	var lower_text := text.to_lower()
	for internal_marker in ["sqlstate", "postgres", "database url", "stack trace", "exception:", "syntax error at"]:
		if lower_text.contains(internal_marker):
			return "Backend rejected the request with internal details."
	return text.substr(0, 200)


func _enqueue_pending_result(payload: Dictionary) -> void:
	var event_id := String(payload.get("result_event_id", "")).strip_edges()
	if event_id.is_empty():
		return
	var pending := _load_pending()
	for item in pending:
		if item is Dictionary and String(item.get("kind", "")) == "result":
			var existing_payload: Variant = item.get("payload", item)
			if existing_payload is Dictionary and String(existing_payload.get("result_event_id", "")) == event_id:
				return
	var queued_payload := payload.duplicate(true)
	queued_payload.erase("playtime_session_id")
	queued_payload.erase("playtime_session_credential")
	queued_payload.erase("session_id")
	queued_payload["environment_scope"] = _current_environment_scope()
	pending.append({
		"kind": "result",
		"path": CANONICAL_RESULT_ENDPOINT,
		"environment_scope": _current_environment_scope(),
		"payload": queued_payload,
	})
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pending))
		file.close()
		if _pending_flush_in_progress:
			_pending_flush_requested = true


func _enqueue_pending(save_data: Dictionary) -> void:
	if GameState.historical_replay_mode or bool(save_data.get("historical_replay_mode", false)):
		return
	var pending := _load_pending()
	var queued_save := save_data.duplicate(true)
	queued_save["environment_scope"] = _current_environment_scope()
	pending.append(queued_save)
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pending))
		file.close()
		if _pending_flush_in_progress:
			_pending_flush_requested = true


func _enqueue_pending_activity(payload: Dictionary) -> void:
	if GameState.historical_replay_mode:
		return
	var event_key := String(payload.get("event_key", "")).strip_edges()
	var student_id := GameState.safe_text_value(GameState.student_id)
	var parent_id := GameState.safe_text_value(GameState.parent_id)
	if event_key.is_empty() or _is_activity_acknowledged(event_key):
		return
	var pending := _load_pending()
	for item in pending:
		if item is Dictionary and String(item.get("kind", "")) == "activity":
			var existing_payload: Variant = item.get("payload", {})
			if (
				existing_payload is Dictionary
				and String(existing_payload.get("event_key", "")) == event_key
				and _pending_item_student_id(item) == student_id
				and _pending_item_parent_id(item) == parent_id
			):
				return
	var queued_payload := payload.duplicate(true)
	queued_payload.erase("session_id")
	queued_payload.erase("session_credential")
	var environment_scope := _current_environment_scope()
	queued_payload["environment_scope"] = environment_scope
	pending.append({
		"kind": "activity",
		"path": CANONICAL_ACTIVITY_ENDPOINT,
		"environment_scope": environment_scope,
		"student_id": student_id,
		"parent_id": parent_id,
		"learning_cycle_version": int(GameState.learning_cycle_version),
		"payload": queued_payload,
	})
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pending))
		file.close()
		if _pending_flush_in_progress:
			_pending_flush_requested = true


func _load_pending() -> Array:
	var pending := []
	var file := FileAccess.open(_pending_file, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		pending = _normalize_pending_queue_payload(JSON.parse_string(text))
	return pending

func _normalize_pending_queue_payload(payload: Variant) -> Array:
	var queue: Array = []
	if payload is Array:
		queue = payload
	elif payload is Dictionary:
		var wrapper_error: Variant = payload.get("error", null)
		var wrapper_result: Variant = payload.get("result", null)
		if wrapper_error == OK and wrapper_result is Array:
			queue = wrapper_result
	if not _is_valid_pending_queue(queue):
		print("RemoteSync: ignoring malformed pending queue payload.")
		return []
	return queue

func _is_valid_pending_queue(queue: Array) -> bool:
	for item in queue:
		if not item is Dictionary:
			return false
	return true


func _pending_item_identity(item: Dictionary) -> String:
	var kind := String(item.get("kind", ""))
	var payload: Variant = item.get("payload", item)
	if kind == "progress_commit":
		var commit_id := String(item.get("save_commit_id", "")).strip_edges()
		if not commit_id.is_empty():
			return "progress:%s:%s" % [_pending_item_student_id(item), commit_id]
	if kind == "result" and payload is Dictionary:
		var result_event_id := String(payload.get("result_event_id", "")).strip_edges()
		if not result_event_id.is_empty():
			return "result:%s:%s" % [_pending_item_student_id(item), result_event_id]
	if kind == "activity" and payload is Dictionary:
		var event_key := String(payload.get("event_key", "")).strip_edges()
		if not event_key.is_empty():
			return "activity:%s:%s" % [_pending_item_student_id(item), event_key]
	return "payload:" + JSON.stringify(item).sha256_text()


func _pending_item_student_id(item: Dictionary) -> String:
	var payload: Variant = item.get("payload", item)
	if payload is Dictionary:
		var payload_student_id := GameState.safe_text_value(payload.get("student_id", ""))
		if not payload_student_id.is_empty():
			return payload_student_id
	return GameState.safe_text_value(item.get("student_id", ""))


func _pending_item_parent_id(item: Dictionary) -> String:
	var payload: Variant = item.get("payload", item)
	if payload is Dictionary:
		var payload_parent_id := GameState.safe_text_value(payload.get("parent_id", ""))
		if not payload_parent_id.is_empty():
			return payload_parent_id
	return GameState.safe_text_value(item.get("parent_id", ""))


func _pending_item_learning_cycle_version(item: Dictionary) -> int:
	var payload: Variant = item.get("payload", item)
	if payload is Dictionary and payload.has("learning_cycle_version"):
		return GameState.safe_int_value(payload.get("learning_cycle_version", -1), -1)
	return GameState.safe_int_value(item.get("learning_cycle_version", -1), -1)


func _mark_pending_item_processed(processed_counts: Dictionary, item: Dictionary) -> void:
	var identity := _pending_item_identity(item)
	processed_counts[identity] = int(processed_counts.get(identity, 0)) + 1


func _reconcile_processed_pending_items(processed_counts: Dictionary) -> void:
	var latest: Array = _load_pending()
	var reconciled: Array = []
	for item: Variant in latest:
		if not (item is Dictionary):
			continue
		var identity := _pending_item_identity(item)
		var processed_count := int(processed_counts.get(identity, 0))
		if processed_count > 0:
			processed_counts[identity] = processed_count - 1
			continue
		reconciled.append(item)
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(reconciled))
		file.close()


func _flush_pending(allow_lease_recovery: bool = true) -> void:
	if _remote_writes_blocked() or GameState.historical_replay_mode:
		return
	if _pending_flush_in_progress:
		_pending_flush_requested = true
		return
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return
	var pending := _load_pending()
	if pending.size() == 0:
		return
	var flush_student_id := GameState.safe_text_value(GameState.student_id)
	var flush_parent_id := GameState.safe_text_value(GameState.parent_id)
	var flush_cycle_version := int(GameState.learning_cycle_version)
	_pending_flush_in_progress = true
	_pending_flush_requested = false
	var processed_counts: Dictionary = {}
	var context_changed := false
	var lease_recovery_required := false
	for item in pending:
		if not (item is Dictionary):
			continue
		var expected_environment_scope := _current_environment_scope()
		if String(item.get("environment_scope", "production")) != expected_environment_scope:
			_mark_pending_item_processed(processed_counts, item)
			continue
		if (
			GameState.safe_text_value(GameState.student_id) != flush_student_id
			or GameState.safe_text_value(GameState.parent_id) != flush_parent_id
			or int(GameState.learning_cycle_version) != flush_cycle_version
		):
			context_changed = true
			break
		var queued_student_id := _pending_item_student_id(item)
		if queued_student_id.is_empty() or queued_student_id != flush_student_id:
			continue
		var queued_parent_id := _pending_item_parent_id(item)
		if queued_parent_id.is_empty() or queued_parent_id != flush_parent_id:
			continue
		var queued_cycle_version := _pending_item_learning_cycle_version(item)
		if queued_cycle_version >= 0 and queued_cycle_version != flush_cycle_version:
			print("RemoteSync: removed a pending item from a previous learning cycle.")
			_mark_pending_item_processed(processed_counts, item)
			continue
		var path := "/api/game/progress"
		var payload: Dictionary = item.duplicate(true)
		var is_activity := false
		var item_kind := String(item.get("kind", ""))
		if item_kind in ["activity", "progress_commit"]:
			path = String(item.get("path", CANONICAL_ACTIVITY_ENDPOINT))
			var queued_payload: Variant = item.get("payload", {})
			if not (queued_payload is Dictionary):
				_mark_pending_item_processed(processed_counts, item)
				continue
			payload = queued_payload.duplicate(true)
			if String(payload.get("environment_scope", "production")) != expected_environment_scope:
				_mark_pending_item_processed(processed_counts, item)
				continue
			if item_kind == "activity":
				is_activity = true
			else:
				path = "/api/game/progress"
		elif item_kind == "result":
			path = String(item.get("path", CANONICAL_RESULT_ENDPOINT))
			var queued_result: Variant = item.get("payload", {})
			if not (queued_result is Dictionary):
				_mark_pending_item_processed(processed_counts, item)
				continue
			payload = queued_result.duplicate(true)
			if String(payload.get("environment_scope", "production")) != expected_environment_scope:
				_mark_pending_item_processed(processed_counts, item)
				continue
		if not _has_active_playtime_lease():
			var lease_result: Dictionary = await _ensure_playtime_session()
			if not bool(lease_result.get("ok", false)):
				# Preserve FIFO chronology for this Student. A later Current Quest or
				# result must not overtake the earliest unsent write.
				break
			if (
				GameState.safe_text_value(GameState.student_id) != flush_student_id
				or GameState.safe_text_value(GameState.parent_id) != flush_parent_id
				or int(GameState.learning_cycle_version) != flush_cycle_version
			):
				context_changed = true
				break
		if is_activity:
			_update_activity_lease_fields(payload)
		elif item_kind == "result":
			_update_result_lease_fields(payload)
		else:
			_update_progress_lease_fields(payload)
		var sent_session_id := _current_playtime_session_id
		var sent_session_credential := _current_playtime_session_credential
		var sent_student_id := _current_playtime_student_id
		var sent_parent_id := _current_playtime_parent_id
		var sent_cycle_version := _current_playtime_learning_cycle_version
		var result: Dictionary = await http.request_post(path, payload)
		if _is_learning_cycle_changed(result):
			print("RemoteSync: removed a stale pending item from the queue.")
			_mark_pending_item_processed(processed_counts, item)
			continue
		if not bool(result.get("ok", false)) or int(result.get("status", 0)) < 200 or int(result.get("status", 0)) >= 300:
			print(_format_outbox_failure_diagnostic(path, result))
		if _is_playtime_lease_rejected(result):
			if _lease_identity_matches(sent_session_id, sent_session_credential, sent_student_id, sent_parent_id, sent_cycle_version):
				_invalidate_playtime_lease()
			lease_recovery_required = true
			break
		if bool(result.get("ok", false)) and int(result.get("status", 0)) >= 200 and int(result.get("status", 0)) < 300:
			if is_activity:
				_acknowledged_activity_keys[_activity_acknowledgement_key(String(payload.get("event_key", "")), queued_student_id)] = true
			_mark_pending_item_processed(processed_counts, item)
			continue
		# Keep the failed item and stop this Student's drain so later progress or
		# activity cannot overwrite it out of chronological order.
		break
	_reconcile_processed_pending_items(processed_counts)
	var rerun_requested := _pending_flush_requested or context_changed or (lease_recovery_required and allow_lease_recovery)
	_pending_flush_in_progress = false
	_pending_flush_requested = false
	if rerun_requested:
		_flush_pending.bind(false if lease_recovery_required else allow_lease_recovery).call_deferred()
