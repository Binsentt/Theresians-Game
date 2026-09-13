extends Node

const PRODUCTION_PENDING_FILE := "user://pending_syncs.json"
const LOCAL_QA_PENDING_FILE := "user://pending_syncs_local_qa.json"
var _pending_file := PRODUCTION_PENDING_FILE

var _current_playtime_session_id: int = 0
var _current_playtime_session_credential: String = ""
var _session_start_in_progress: bool = false
var _playtime_heartbeat_in_progress: bool = false
var _playtime_heartbeat_elapsed: float = 0.0
var _playtime_timeout_handled: bool = false
var local_qa_only := false

const PLAYTIME_DAILY_LIMIT_MINUTES := 60
const PLAYTIME_HEARTBEAT_INTERVAL_SECONDS := 15.0
const CANONICAL_ACTIVITY_ENDPOINT := "/api/game/activity"
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
	if http != null and http.has_method("is_local_qa_mode") and bool(http.call("is_local_qa_mode")):
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

func enable_local_qa_mode() -> void:
	local_qa_only = true
	_pending_file = LOCAL_QA_PENDING_FILE
	_current_playtime_session_id = 0
	_current_playtime_session_credential = ""
	_session_start_in_progress = false
	_playtime_heartbeat_in_progress = false
	_activity_requests_in_flight.clear()
	_acknowledged_activity_keys.clear()
	print("RemoteSync: LOCAL QA ONLY — all telemetry/progress writes disabled")

func _process(delta: float) -> void:
	if local_qa_only:
		return
	if not GameState:
		return
	GameState.consume_playtime_clock(delta)
	if _current_playtime_session_id == 0 or _current_playtime_session_credential.is_empty() or not GameState.playtime_authorized:
		return
	_playtime_heartbeat_elapsed += delta
	if _playtime_heartbeat_elapsed >= PLAYTIME_HEARTBEAT_INTERVAL_SECONDS and not _playtime_heartbeat_in_progress:
		_playtime_heartbeat_elapsed = 0.0
		_refresh_playtime_lease.call_deferred()

func _on_save_created(save_data: Dictionary) -> void:
	if local_qa_only:
		return
	# Always allow local save to complete; attempt remote sync but do not block
	await _async_send_progress(save_data)

func _on_progression_session_reset(source: String) -> void:
	if local_qa_only:
		return
	if source == "new_game":
		await _create_activity_log("New Game", "New Game profile initialized", {})
	elif source == "load":
		await _create_activity_log("Load Game", "Existing game profile loaded", {})

	if source == "new_game" or source == "load":
		var session_result := await _start_playtime_session()
		if source == "new_game" and bool(session_result.get("ok", false)) and _has_active_playtime_lease():
			GameState.emit_tutorial_activity_started()

func _on_game_over() -> void:
	if local_qa_only:
		return
	await _end_playtime_session()

func _on_time_limit_reached() -> void:
	if GameState.playtime_authorized or _playtime_timeout_handled:
		return
	_playtime_timeout_handled = true
	if _session_start_in_progress:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		GameState.capture_runtime(current_scene.scene_file_path, get_tree().get_first_node_in_group("player_character").global_position if get_tree().get_first_node_in_group("player_character") != null else Vector2.ZERO)
	var auto_save_path: String = GameState.save_game()
	await _end_playtime_session()
	await _create_activity_log("Auto Save", "Auto-save due to daily playtime limit reached", {})
	await _create_activity_log("Timeout", "Gameplay session timed out after daily limit reached", {})
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
	await _submit_canonical_task_activity(previous_index, current_index, event)


func _on_canonical_activity_boundary(event: Dictionary) -> void:
	await _submit_canonical_task_activity(
		GameState.safe_int_value(event.get("previous_index", GameState.current_task_index), GameState.current_task_index),
		GameState.safe_int_value(event.get("current_index", GameState.current_task_index), GameState.current_task_index),
		event
	)


func _submit_canonical_task_activity(previous_index: int, current_index: int, event: Dictionary) -> void:
	if local_qa_only:
		return
	if not _has_active_playtime_lease():
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
	if _is_activity_acknowledged(event_key) or _activity_requests_in_flight.has(event_key):
		return

	var canonical_event: Dictionary = GameState.build_canonical_activity_event(event, previous_index if event_type in ["task_completed", "quest_completed"] else current_index, event_type)
	var payload := {
		"session_id": _current_playtime_session_id,
		"session_credential": _current_playtime_session_credential,
		"learning_cycle_version": int(GameState.learning_cycle_version),
		"event_type": event_type,
		"event_key": event_key,
		"task_id": activity_label,
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
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		_enqueue_pending_activity(payload)
		return

	_activity_requests_in_flight[event_key] = true
	var result: Dictionary = await http.request_post(CANONICAL_ACTIVITY_ENDPOINT, payload)
	_activity_requests_in_flight.erase(event_key)
	if _is_learning_cycle_changed(result) or _is_activity_lease_rejected(result):
		return
	if bool(result.get("ok", false)) and GameState.safe_int_value(result.get("status", 0), 0) >= 200 and GameState.safe_int_value(result.get("status", 0), 0) < 300:
		_acknowledged_activity_keys[event_key] = true
		await _flush_pending()
		return
	_enqueue_pending_activity(payload)


func _canonical_activity_type(candidate: String) -> String:
	return GameState.safe_text_value(CANONICAL_ACTIVITY_TYPES.get(candidate, ""))


func _activity_metadata_for_event(previous_index: int, current_index: int, event: Dictionary, event_type: String) -> Dictionary:
	var explicit_metadata: Variant = event.get("activity", {})
	if explicit_metadata is Dictionary and not explicit_metadata.is_empty():
		return explicit_metadata
	var task_index := previous_index if event_type in ["task_completed", "quest_completed"] else current_index
	return GameState.get_task_activity_metadata(task_index)


func _has_active_playtime_lease() -> bool:
	return GameState.playtime_authorized and _current_playtime_session_id != 0 and not _current_playtime_session_credential.is_empty()


func _is_activity_acknowledged(event_key: String) -> bool:
	return _acknowledged_activity_keys.has(event_key)


func _is_activity_lease_rejected(result: Dictionary) -> bool:
	var status := GameState.safe_int_value(result.get("status", 0), 0)
	return status == 401 or status == 403
func _apply_learning_cycle(response_body: Variant) -> Dictionary:
	if not (response_body is Dictionary):
		return {}
	var descriptor: Variant = response_body.get("learning_cycle", {})
	if descriptor is Dictionary and GameState.set_learning_cycle(descriptor):
		return GameState.get_learning_cycle_descriptor()
	return {}


func _is_learning_cycle_changed(result: Dictionary) -> bool:
	if GameState.safe_int_value(result.get("status", 0), 0) != 409:
		return false
	var body: Variant = result.get("body", {})
	return body is Dictionary and GameState.safe_text_value(body.get("code", "")) == "LEARNING_CYCLE_CHANGED"

func _async_send_progress(save_data: Dictionary) -> void:
	if local_qa_only:
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
	if local_qa_only:
		return {"ok": false, "error": "Local QA mode disables playtime writes", "should_block": false}
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Playtime service unavailable", "should_block": false}

	var payload := _build_playtime_start_payload(override_payload)
	if not GameState.is_valid_existing_student_id(payload.get("student_id", "")) or not GameState.is_valid_six_digit_id(payload.get("parent_id", "")):
		return {"ok": false, "error": "Invalid student or parent ID", "should_block": false}

	return await http.request_post("/api/playtime/start", payload)

func _send_playtime_end_request() -> Dictionary:
	if local_qa_only:
		return {"ok": false, "error": "Local QA mode disables playtime writes", "should_block": false}
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Playtime service unavailable", "should_block": false}

	if _current_playtime_session_id == 0 or _current_playtime_session_credential.is_empty():
		return {"ok": false, "error": "No active server playtime lease", "should_block": false}
	var payload := {
		"session_id": _current_playtime_session_id,
		"session_credential": _current_playtime_session_credential,
		"status": "Timed Out" if not GameState.playtime_authorized else "Completed",
	}

	return await http.request_post("/api/playtime/end", payload)


func _send_playtime_heartbeat_request() -> Dictionary:
	if local_qa_only:
		return {"ok": false, "error": "Local QA mode disables playtime writes", "should_block": false}
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Playtime service unavailable", "should_block": false}
	if _current_playtime_session_id == 0 or _current_playtime_session_credential.is_empty():
		return {"ok": false, "error": "No active server playtime lease", "should_block": false}
	return await http.request_post("/api/playtime/heartbeat", {
		"session_id": _current_playtime_session_id,
		"session_credential": _current_playtime_session_credential,
	})


func _refresh_playtime_lease() -> void:
	if _playtime_heartbeat_in_progress or _current_playtime_session_id == 0:
		return
	_playtime_heartbeat_in_progress = true
	var result := await _send_playtime_heartbeat_request()
	if _is_learning_cycle_changed(result):
		GameState.configure_playtime_allowance({
			"daily_limit_minutes": PLAYTIME_DAILY_LIMIT_MINUTES,
			"remaining_seconds": 0,
			"can_play": false,
		}, false)
		_playtime_heartbeat_in_progress = false
		return
	if typeof(result.body) == TYPE_DICTIONARY:
		GameState.configure_playtime_allowance(result.body, false)
	if result.ok and result.status >= 200 and result.status < 300:
		_playtime_timeout_handled = false
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
	if local_qa_only:
		return
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return

	var student_id := GameState.safe_text_value(override_payload.get("student_id", GameState.student_id))
	if not GameState.is_valid_existing_student_id(student_id):
		return

	var payload := {
		"student_id": student_id,
		"student_name": GameState.safe_text_value(override_payload.get("student_name", GameState.player_name)),
		"grade_level": GameState.safe_text_value(override_payload.get("grade_level", GameState.grade_level)),
		"section": GameState.safe_text_value(override_payload.get("section", "")),
		"current_quest": GameState.safe_text_value(override_payload.get("current_quest", GameState.current_quest)),
		"save_status": "playing" if status == "Playing" else "saved",
		"total_play_time": 0,
		"quest_progress": GameState.safe_int_value(override_payload.get("quest_progress", GameState.current_task_index), GameState.current_task_index),
		"role": "Student",
		"status": status,
		"activity_description": description
	}

	var result: Dictionary = await http.request_post("/api/activity-logs", payload)
	if not result.ok:
		print("RemoteSync: activity log failed: %s" % str(result.error))

func _start_playtime_session(override_payload: Dictionary = {}) -> Dictionary:
	if _current_playtime_session_id != 0 and not _current_playtime_session_credential.is_empty():
		return {"ok": true, "session_id": _current_playtime_session_id, "can_play": true}
	if _session_start_in_progress:
		return {"ok": false, "error": "Playtime session start already pending", "should_block": false, "can_play": false}

	_session_start_in_progress = true
	var result: Dictionary = {}
	var final_result: Dictionary = {}
	
	result = await _send_playtime_start_request(override_payload)
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
			_current_playtime_session_id = 0
			_current_playtime_session_credential = ""
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
			_playtime_heartbeat_elapsed = 0.0
			_playtime_timeout_handled = false
			if _current_playtime_session_id != 0 and not _current_playtime_session_credential.is_empty():
				await _create_activity_log("Playing", "Gameplay session started", override_payload)
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
				_current_playtime_session_id = 0
				_current_playtime_session_credential = ""
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

	_session_start_in_progress = false
	return final_result

func _end_playtime_session() -> Dictionary:
	if _current_playtime_session_id == 0 or _current_playtime_session_credential.is_empty():
		return {"ok": false, "error": "Missing active server playtime lease", "should_block": false}

	var result := await _send_playtime_end_request()
	if not result.ok:
		return result

	if result.status == 200:
		await _create_activity_log("Offline", "Gameplay session ended")
		_current_playtime_session_id = 0
		_current_playtime_session_credential = ""
		_playtime_heartbeat_elapsed = 0.0
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
	if not _has_active_playtime_lease():
		if GameState.is_valid_existing_student_id(GameState.student_id) and GameState.is_valid_six_digit_id(GameState.parent_id):
			var session_result: Dictionary = await _ensure_playtime_session()
			if not bool(session_result.get("ok", false)):
				return {"ok": false, "status": 0, "error": "An active playtime lease is required.", "entries": []}
		else:
			return {"ok": false, "status": 0, "error": "An active playtime lease is required.", "entries": []}
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "status": 0, "error": "Leaderboard service unavailable.", "entries": []}
	var result: Dictionary = await http.request_post("/api/game/leaderboard", {
		"session_id": _current_playtime_session_id,
		"session_credential": _current_playtime_session_credential,
		"learning_cycle_version": int(GameState.learning_cycle_version),
	})
	var status := GameState.safe_int_value(result.get("status", 0), 0)
	if _is_learning_cycle_changed(result):
		return {"ok": false, "status": status, "error": "Leaderboard belongs to a previous learning cycle.", "entries": []}
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
			"progress_percentage": _normalize_leaderboard_number(raw_entry.get("progress_percentage", null)),
			"accuracy_rate": _normalize_leaderboard_number(raw_entry.get("accuracy_rate", null)),
			"correct_answers": _normalize_leaderboard_number(raw_entry.get("correct_answers", null)),
			"total_questions": _normalize_leaderboard_number(raw_entry.get("total_questions", null)),
			"quests_completed": _normalize_leaderboard_number(raw_entry.get("quests_completed", null)),
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
		return parsed if parsed >= 0.0 else null
	return null


func record_question_attempt(question: Dictionary, is_correct: bool) -> void:
	if local_qa_only:
		return
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return
	if not GameState.is_valid_existing_student_id(GameState.student_id) or not GameState.is_valid_six_digit_id(GameState.parent_id):
		return
	# Battle scenes can answer the first question while the asynchronous
	# playtime-start request is still completing. Recover the current lease here
	# instead of silently dropping that graded answer from website analytics.
	if _current_playtime_session_id == 0 or _current_playtime_session_credential.is_empty():
		var session_result: Dictionary = await _ensure_playtime_session()
		if not bool(session_result.get("ok", false)):
			print("RemoteSync: unable to establish a playtime lease for question result; local gameplay continues.")
			return
	var question_identity := str(question.get("question_id", question.get("id", ""))).strip_edges()
	if question_identity.is_empty():
		question_identity = "question:%s" % str(question.get("question", question.get("text", ""))).strip_edges().to_lower().hash()
	var battle_identity := str(question.get("battle_id", question.get("encounter_id", GameState.encounter_context.get("encounter_id", "")))).strip_edges()
	if battle_identity.is_empty():
		battle_identity = "task-%d" % int(GameState.current_task_index)

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
		"result_event_id": "cycle:%d:battle:%s:question:%s" % [int(GameState.learning_cycle_version), battle_identity, question_identity],
		"telemetry_contract_version": GameState.TELEMETRY_CONTRACT_VERSION,
		"quest_graph_version": GameState.QUEST_GRAPH_VERSION,
		"session_id": _current_playtime_session_id,
		"map_id": GameState.canonical_map_id(),
		"canonical_quest_id": "main",
		"canonical_task_id": GameState.get_task_activity_metadata(GameState.current_task_index).get("canonical_task_id", ""),
		"canonical_battle_id": str(question.get("battle_id", question.get("encounter_id", ""))),
		"canonical_milestone_id": str(question.get("milestone_id", "")),
	}
	var question_set_id: Variant = question.get("question_set_id", null)
	if question_set_id is int and question_set_id > 0:
		payload["question_set_id"] = question_set_id

	var result: Dictionary = await http.request_post("/api/game/result", payload)
	if _is_learning_cycle_changed(result):
		print("RemoteSync: discarded a previous-learning-cycle question result.")
		return
	var status := GameState.safe_int_value(result.get("status", 0), 0)
	if not result.get("ok", false) or status < 200 or status >= 300:
		print("RemoteSync: question result sync failed; local gameplay continues: %s" % str(result))


func _enqueue_pending(save_data: Dictionary) -> void:
	var pending := _load_pending()
	var queued_save := save_data.duplicate(true)
	if local_qa_only:
		queued_save["environment_scope"] = "local_qa"
	pending.append(queued_save)
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pending))
		file.close()


func _enqueue_pending_activity(payload: Dictionary) -> void:
	var event_key := String(payload.get("event_key", "")).strip_edges()
	if event_key.is_empty() or _is_activity_acknowledged(event_key):
		return
	var pending := _load_pending()
	for item in pending:
		if item is Dictionary and String(item.get("kind", "")) == "activity":
			var existing_payload: Variant = item.get("payload", {})
			if existing_payload is Dictionary and String(existing_payload.get("event_key", "")) == event_key:
				return
	var queued_payload := payload.duplicate(true)
	var environment_scope := "local_qa" if local_qa_only else "production"
	queued_payload["environment_scope"] = environment_scope
	pending.append({
		"kind": "activity",
		"path": CANONICAL_ACTIVITY_ENDPOINT,
		"environment_scope": environment_scope,
		"payload": queued_payload,
	})
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pending))
		file.close()


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

func _flush_pending() -> void:
	if local_qa_only:
		return
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return
	var pending := _load_pending()
	if pending.size() == 0:
		return
	var remaining := []
	for item in pending:
		if not (item is Dictionary):
			continue
		if String(item.get("environment_scope", "production")) != "production":
			continue
		var path := "/api/game/progress"
		var payload: Dictionary = item
		var is_activity := false
		if String(item.get("kind", "")) == "activity":
			path = String(item.get("path", CANONICAL_ACTIVITY_ENDPOINT))
			var queued_payload: Variant = item.get("payload", {})
			if not (queued_payload is Dictionary):
				continue
			payload = queued_payload
			if String(payload.get("environment_scope", "production")) != "production":
				continue
			is_activity = true
		var result: Dictionary = await http.request_post(path, payload)
		if _is_learning_cycle_changed(result):
			print("RemoteSync: removed a stale pending item from the queue.")
			continue
		if is_activity and _is_activity_lease_rejected(result):
			continue
		if bool(result.get("ok", false)) and int(result.get("status", 0)) >= 200 and int(result.get("status", 0)) < 300:
			if is_activity:
				_acknowledged_activity_keys[String(payload.get("event_key", ""))] = true
			continue
		if not result.ok or result.status < 200 or result.status >= 300:
			remaining.append(item)
	# overwrite pending file
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(remaining))
		file.close()
