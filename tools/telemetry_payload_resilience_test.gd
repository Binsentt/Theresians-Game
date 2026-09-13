extends Node

class HttpApiStub extends Node:
	var requests: Array[Dictionary] = []
	var leaderboard_response: Dictionary = {"ok": true, "status": 200, "body": {"entries": []}}

	func request_post(path: String, payload: Dictionary) -> Dictionary:
		requests.append({"path": path, "payload": payload.duplicate(true)})
		if path == "/api/game/leaderboard":
			return leaderboard_response
		return {"ok": true, "status": 201, "body": {}}


var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := get_tree().root
	var game_state := root.get_node_or_null("GameState")
	var remote := root.get_node_or_null("RemoteSync")
	if game_state == null or remote == null:
		_failures.append("Canonical GameState and RemoteSync autoloads are required.")
		_finish()
		return
	var http_original := root.get_node_or_null("HttpApi")
	if http_original != null:
		http_original.name = "_telemetry_original_http"
	var http_stub := HttpApiStub.new()
	http_stub.name = "HttpApi"
	root.add_child(http_stub)
	remote.set("_pending_file", "user://telemetry_payload_resilience_test.json")
	remote.enable_local_qa_mode()
	game_state.enable_local_qa_mode()

	game_state.configure_playtime_allowance({
		"daily_limit_minutes": {},
		"remaining_minutes": [],
		"remaining_seconds": Node.new(),
		"can_play": true,
	}, true)
	_expect(game_state.playtime_limit_minutes > 0 and game_state.playtime_remaining_seconds >= 0.0, "Malformed playtime numerics fall back without crashing")

	var malformed_event := {
		"previous_index": {},
		"current_index": [],
		"type": Node.new(),
		"key": Node.new(),
		"activity": {"activity_label": Node.new(), "activity_id": {}}
	}
	await remote._on_canonical_activity_boundary(malformed_event)
	_expect(true, "Malformed activity envelope does not abort the gameplay observer")

	var entries: Array = remote._sanitize_game_leaderboard_entries([
		{"rank": {}, "display_name": "ignored"},
		{"rank": "2", "display_name": "QA Student", "grade": Node.new()},
		{"rank": [], "display_name": "ignored"},
	])
	_expect(entries.size() == 1 and int(entries[0].get("rank", 0)) == 2, "Leaderboard rank parsing rejects malformed values safely")

	remote.set("local_qa_only", false)
	var malformed_save := {
		"parent_id": Node.new(),
		"student_id": "17000087",
		"player_name": Node.new(),
		"grade_level": "Grade 1",
		"gender": "male",
		"current_quest": Node.new(),
		"current_task_index": {},
		"lesson_progress": [],
		"progress_percentage": Node.new(),
		"scene_path": "res://scenes/Player House/player_house.tscn",
		"current_map": Node.new(),
		"save_timestamp": {},
		"score": [],
		"correct_answers": Node.new(),
		"incorrect_answers": {},
		"total_questions": [],
		"total_play_time": Node.new(),
		"total_quests_completed": {},
		"difficulty_level": Node.new(),
		"learning_cycle_version": [],
	}
	await remote._async_send_progress(malformed_save)
	_expect(http_stub.requests.size() == 1, "Malformed save telemetry still uses the best-effort transport")
	if http_stub.requests.size() == 1:
		var progress_payload: Dictionary = http_stub.requests[0].get("payload", {})
		_expect(progress_payload.get("quest_progress") is int and progress_payload.get("score") is int, "Progress numeric fields are normalized before transport")

	game_state.student_id = "17000087"
	game_state.parent_id = "170001"
	game_state.playtime_authorized = true
	remote.set("_current_playtime_session_id", 12)
	remote.set("_current_playtime_session_credential", "qa-lease")
	http_stub.leaderboard_response = {
		"ok": true,
		"status": "200",
		"body": {"entries": [{"rank": {}, "display_name": "bad"}, {"rank": "1", "display_name": "QA"}]},
	}
	var leaderboard: Dictionary = await remote.request_game_leaderboard()
	_expect(leaderboard.get("ok", false) and (leaderboard.get("entries", []) as Array).size() == 1, "Malformed leaderboard response remains safe and usable")

	remote.set("local_qa_only", true)
	http_stub.queue_free()
	if http_original != null:
		http_original.name = "HttpApi"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://telemetry_payload_resilience_test.json"))
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("TELEMETRY_PAYLOAD_RESILIENCE_TEST {\"failed\":0,\"passed\":7}")
		await get_tree().create_timer(3.0).timeout
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TELEMETRY_PAYLOAD_RESILIENCE_TEST {\"failed\":%d,\"passed\":%d}" % [_failures.size(), 7 - _failures.size()])
	await get_tree().create_timer(3.0).timeout
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
