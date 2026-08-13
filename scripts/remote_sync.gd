extends Node

var _pending_file := "user://pending_syncs.json"

var _current_playtime_session_id: int = 0
var _session_start_in_progress: bool = false

func _ready() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state:
		game_state.connect("save_created", Callable(self, "_on_save_created"))
		game_state.connect("progression_session_reset", Callable(self, "_on_progression_session_reset"))
		game_state.connect("game_over", Callable(self, "_on_game_over"))
		game_state.connect("time_limit_reached", Callable(self, "_on_time_limit_reached"))
	_load_pending()

func _process(delta: float) -> void:
	if not GameState:
		return
	GameState.consume_playtime_clock(delta)
	if GameState.playtime_countdown_active:
		return

func _on_save_created(save_data: Dictionary) -> void:
	# Always allow local save to complete; attempt remote sync but do not block
	_async_send_progress(save_data)

func _on_progression_session_reset(source: String) -> void:
	if source == "new_game":
		_create_activity_log("New Game", "New Game profile initialized", {})
	elif source == "load":
		_create_activity_log("Load Game", "Existing game profile loaded", {})

	if source == "new_game" or source == "load":
		await _start_playtime_session()

func _on_game_over() -> void:
	await _end_playtime_session()

func _on_time_limit_reached() -> void:
	if GameState.playtime_authorized:
		return
	if _session_start_in_progress:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		GameState.capture_runtime(current_scene.scene_file_path, get_tree().get_first_node_in_group("player_character").global_position if get_tree().get_first_node_in_group("player_character") != null else Vector2.ZERO)
	var auto_save_path: String = GameState.save_game()
	_async_send_progress(GameState.build_save_data())
	await _end_playtime_session()
	_create_activity_log("Auto Save", "Auto-save due to daily playtime limit reached", {})
	_create_activity_log("Timeout", "Gameplay session timed out after daily limit reached", {})
	GameState.time_limit_reached.emit()
	var hud := get_node_or_null("/root/GameHUD")
	if hud != null and hud.has_method("show_time_limit_reached"):
		hud.call("show_time_limit_reached")
	if auto_save_path != "":
		print("RemoteSync: local autosave completed for time-limit stop: %s" % auto_save_path)
	if get_tree() != null:
		get_tree().paused = true

func _async_send_progress(save_data: Dictionary) -> void:
	# perform non-blocking via thread? We'll do simple call and rely on HttpApi's await behavior
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		print("RemoteSync: HttpApi unavailable; queueing sync")
		_enqueue_pending(save_data)
		return
	# Build the payload as a real Save Game projection of the authoritative runtime fields.
	# The backend already normalizes these fields into student_game_progress and activity_logs.
	var payload := {
		"parent_id": String(save_data.get("parent_id", "")),
		"student_id": String(save_data.get("student_id", "")),
		"student_name": String(save_data.get("player_name", save_data.get("student_name", ""))),
		"grade_level": String(save_data.get("grade_level", "")),
		"gender": String(save_data.get("gender", "")),
		"current_quest": String(save_data.get("current_quest", "")),
		"quest_progress": int(save_data.get("current_task_index", 0)),
		"lesson_progress": int(save_data.get("lesson_progress", save_data.get("lesson_progress", 0))),
		"progress_percentage": int(save_data.get("progress_percentage", save_data.get("completion_percentage", 0))),
		"current_scene": String(save_data.get("scene_path", save_data.get("current_scene", ""))),
		"current_map": String(save_data.get("current_map", save_data.get("scene_path", ""))),
		"save_timestamp": int(save_data.get("save_timestamp", 0)),
		"save_time": String(save_data.get("save_time", "")),
		"save_date": String(save_data.get("save_date", "")),
		"score": int(save_data.get("score", 0)),
		"correct_answers": int(save_data.get("correct_answers", 0)),
		"incorrect_answers": int(save_data.get("incorrect_answers", 0)),
		"total_questions": int(save_data.get("total_questions", 0)),
		"total_play_time": int(save_data.get("total_play_time", 0)),
		"total_quests_completed": int(save_data.get("total_quests_completed", 0)),
		"difficulty_level": String(save_data.get("difficulty_level", "Unknown")),
		"save_status": "saved"
	}
	var result = http.request_post("/api/game/progress", payload)
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
		"student_id": String(override_payload.get("student_id", GameState.student_id)),
		"parent_id": String(override_payload.get("parent_id", GameState.parent_id)),
		"student_name": String(override_payload.get("student_name", GameState.player_name)),
		"grade_level": String(override_payload.get("grade_level", GameState.grade_level)),
		"section": String(override_payload.get("section", ""))
	}
	return payload

func _send_playtime_start_request(override_payload: Dictionary = {}) -> Dictionary:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Playtime service unavailable", "should_block": false}

	var payload := _build_playtime_start_payload(override_payload)
	if not GameState.is_valid_six_digit_id(payload.get("student_id", "")) or not GameState.is_valid_six_digit_id(payload.get("parent_id", "")):
		return {"ok": false, "error": "Invalid student or parent ID", "should_block": false}

	return http.request_post("/api/playtime/start", payload)

func _send_playtime_end_request() -> Dictionary:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Playtime service unavailable", "should_block": false}

	var payload := {
		"student_id": String(GameState.student_id)
	}
	if _current_playtime_session_id != 0:
		payload["session_id"] = _current_playtime_session_id

	return http.request_post("/api/playtime/end", payload)

func _create_activity_log(status: String, description: String, override_payload: Dictionary = {}) -> void:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return

	var student_id := String(override_payload.get("student_id", GameState.student_id))
	if not GameState.is_valid_six_digit_id(student_id):
		return

	var payload := {
		"student_id": student_id,
		"student_name": String(override_payload.get("student_name", GameState.player_name)),
		"grade_level": String(override_payload.get("grade_level", GameState.grade_level)),
		"section": String(override_payload.get("section", "")),
		"current_quest": String(override_payload.get("current_quest", GameState.current_quest)),
		"save_status": "playing" if status == "Playing" else "saved",
		"total_play_time": 0,
		"quest_progress": int(override_payload.get("quest_progress", GameState.current_task_index)),
		"role": "Student",
		"status": status,
		"activity_description": description
	}

	var result: Dictionary = http.request_post("/api/activity-logs", payload)
	if not result.ok:
		print("RemoteSync: activity log failed: %s" % str(result.error))

func _start_playtime_session(override_payload: Dictionary = {}) -> Dictionary:
	if _current_playtime_session_id != 0:
		return {"ok": true, "session_id": _current_playtime_session_id, "can_play": true}
	if _session_start_in_progress:
		return {"ok": false, "error": "Playtime session start already pending", "should_block": false, "can_play": false}

	_session_start_in_progress = true
	var result: Dictionary = {}
	var final_result: Dictionary = {}
	
	result = _send_playtime_start_request(override_payload)
	if result.ok and (result.status == 201 or result.status == 200):
		var api_can_play := bool(result.body.get("can_play", true))
		if api_can_play == false:
			GameState.configure_playtime_allowance(result.body)
			final_result = {
				"ok": false,
				"status": result.status,
				"error": String(result.body.get("error", "Daily playtime limit reached.")),
				"message": String(result.body.get("message", "Daily playtime limit reached.")),
				"should_block": true,
				"can_play": false,
				"remaining_minutes": int(result.body.get("remaining_minutes", 0)),
				"daily_limit_minutes": int(result.body.get("daily_limit_minutes", 60)),
			}
		else:
			GameState.configure_playtime_allowance(result.body)
			_current_playtime_session_id = int(result.body.get("session_id", 0))
			if _current_playtime_session_id != 0:
				_create_activity_log("Playing", "Gameplay session started", override_payload)
				final_result = {
					"ok": true,
					"session_id": _current_playtime_session_id,
					"remaining_minutes": int(result.body.get("remaining_minutes", 60)),
					"daily_limit_minutes": int(result.body.get("daily_limit_minutes", 60)),
					"total_playtime_today": int(result.body.get("total_playtime_today", 0)),
					"can_play": true,
					"message": String(result.body.get("message", "Playtime session started.")),
				}
			else:
				final_result = {"ok": false, "error": "Playtime session did not return a session ID", "should_block": false, "can_play": false}
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
	if _current_playtime_session_id == 0 and not GameState.is_valid_six_digit_id(GameState.student_id):
		return {"ok": false, "error": "Missing session or student ID", "should_block": false}

	var result := _send_playtime_end_request()
	if not result.ok:
		return result

	if result.status == 200:
		_create_activity_log("Offline", "Gameplay session ended")
		_current_playtime_session_id = 0
		return {"ok": true}

	var error_message := "Unable to end playtime session"
	if typeof(result.body) == TYPE_DICTIONARY and result.body.has("error"):
		error_message = String(result.body.get("error"))

	return {"ok": false, "status": result.status, "error": error_message, "should_block": false}

func request_playtime_session(override_payload: Dictionary = {}) -> Dictionary:
	# Public wrapper for UI code to start or resume a backend-authoritative playtime session.
	return _start_playtime_session(override_payload)

func request_end_playtime_session() -> Dictionary:
	# Public wrapper for UI or scene lifecycle code to cleanly end the current playtime session.
	return _end_playtime_session()

func _enqueue_pending(save_data: Dictionary) -> void:
	var pending := _load_pending()
	pending.append(save_data)
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
		var j = JSON.parse_string(text)
		if j.error == OK and typeof(j.result) == TYPE_ARRAY:
			pending = j.result
	return pending

func _flush_pending() -> void:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return
	var pending := _load_pending()
	if pending.size() == 0:
		return
	var remaining := []
	for item in pending:
		var result: Dictionary = http.request_post("/api/game/progress", item)
		if not result.ok or result.status < 200 or result.status >= 300:
			remaining.append(item)
	# overwrite pending file
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(remaining))
		file.close()
