extends Node

const RESULT_PATH := "user://game_leaderboard_contract_test_result.json"
var _failures: Array[String] = []
var _checks := 0


class LocalLeaderboardHttpStub extends Node:
	var requests: Array[Dictionary] = []
	var response: Dictionary = {}

	func request_get(path: String, params: Dictionary = {}, timeout_ms: int = -1) -> Dictionary:
		requests.append({"path": path, "params": params.duplicate(true), "timeout_ms": timeout_ms})
		return response.duplicate(true)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var startup_http := get_tree().root.get_node_or_null("HttpApi")
	if startup_http == null or not bool(startup_http.call("is_local_qa_profile_active")):
		_failures.append("Leaderboard contract runner did not start in local-only QA mode before autoloads.")
		_finish()
		return
	var remote_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	var controller_source := FileAccess.get_file_as_string("res://scripts/leaderboard_scene_controller.gd")
	var scene_source := FileAccess.get_file_as_string("res://leaderboard_scene.tscn")
	var request_block := _function_block(remote_source, "func request_game_leaderboard")
	_expect(remote_source.contains("func request_game_leaderboard"), "RemoteSync must provide the public game leaderboard request.")
	_expect(request_block.contains("request_get(\"/api/game/leaderboard\")") and not request_block.contains("request_post"), "The public leaderboard uses its read-only GET endpoint.")
	_expect(not request_block.contains("session_id") and not request_block.contains("session_credential") and not request_block.contains("learning_cycle_version") and not request_block.contains("_has_active_playtime_lease"), "Viewing the leaderboard does not require an authenticated Student or playtime lease.")
	var projection_block := _function_block(remote_source, "func _sanitize_game_leaderboard_entries")
	_expect(projection_block.contains("display_name") and projection_block.contains("grade") and projection_block.contains("correct_answers"), "RemoteSync preserves the canonical name, grade, and total correct answers.")
	_expect(not projection_block.contains("progress_percentage") and not projection_block.contains("accuracy_rate"), "Public leaderboard projection does not expose unrelated progress or accuracy metrics.")
	_expect(not projection_block.contains("student_id") and not projection_block.contains("parent_id") and not projection_block.contains("email") and not projection_block.contains("session_credential"), "RemoteSync discards identifiers, email, and credentials.")
	_expect(projection_block.contains("slice(0, 6)"), "Game leaderboard must expose only the top six canonical entries in API order.")
	_expect(controller_source.contains("request_game_leaderboard"), "Leaderboard controller must request data through RemoteSync.")
	var row_projection := _function_block(controller_source, "func _normalized_row_data")
	_expect(row_projection.contains('entry.get("correct_answers"') and row_projection.contains("_format_correct_answer_count") and not row_projection.contains("progress_percentage"), "Leaderboard Game Score uses the canonical total-correct-answer field only.")
	_expect(controller_source.contains('_create_row_label("GameScore"'), "Leaderboard row displays the canonical Game Score field.")
	_expect(not controller_source.contains("/api/leaderboard/top-achievers"), "Leaderboard controller must not call a portal-only route directly.")
	_expect(controller_source.contains("_refresh_generation"), "Leaderboard controller must ignore older responses after a newer refresh.")
	_expect(controller_source.contains("No leaderboard records yet."), "An empty response uses the approved no-records state.")
	_expect(controller_source.contains("Leaderboard unavailable."), "Network failure uses the approved unavailable state.")
	_expect(scene_source.contains('text = "GAME SCORE"') and not scene_source.contains('text = "PERCENTAGE"'), "Leaderboard preserves the authored GAME SCORE column.")
	await _verify_public_get_without_identity()
	_finish()


func _verify_public_get_without_identity() -> void:
	var http := get_tree().root.get_node_or_null("HttpApi")
	var remote_sync := get_tree().root.get_node_or_null("RemoteSync")
	var game_state := get_tree().root.get_node_or_null("GameState")
	_expect(http != null and remote_sync != null and game_state != null, "The safe runtime contract fixture has its required autoloads.")
	var http_api := get_tree().root.get_node_or_null("HttpApi")
	if http_api == null or remote_sync == null or game_state == null:
		return
	var previous_student_id: Variant = game_state.student_id
	var previous_parent_id: Variant = game_state.parent_id
	game_state.student_id = ""
	game_state.parent_id = ""
	http_api.name = "LeaderboardContractOriginalHttpApi"
	var stub := LocalLeaderboardHttpStub.new()
	stub.name = "HttpApi"
	stub.response = {
		"ok": true,
		"status": 200,
		"body": {"entries": [{
			"rank": 1,
			"display_name": "Public Name",
			"grade": "Grade 3",
			"correct_answers": 7,
			"student_id": "private-student-id",
			"parent_id": "private-parent-id",
			"email": "private@example.test",
			"session_credential": "private-credential",
		}]},
	}
	get_tree().root.add_child(stub)
	var result: Dictionary = await remote_sync.request_game_leaderboard()
	_expect(stub.requests.size() == 1, "One anonymous leaderboard refresh makes exactly one read request.")
	if not stub.requests.is_empty():
		_expect(stub.requests[0].get("path", "") == "/api/game/leaderboard", "RemoteSync requests the exact public leaderboard route.")
		_expect((stub.requests[0].get("params", {}) as Dictionary).is_empty(), "Anonymous leaderboard request carries no identity, session, or query parameters.")
	var entries: Array = result.get("entries", [])
	_expect(result.get("ok", false) and entries.size() == 1, "A logged-out player can receive public leaderboard rows.")
	if not entries.is_empty():
		_expect(entries[0] == {"rank": 1, "display_name": "Public Name", "grade": "Grade 3", "correct_answers": 7}, "RemoteSync keeps only rank, public name, grade, and canonical score evidence.")
	get_tree().root.remove_child(stub)
	stub.free()
	http_api.name = "HttpApi"
	game_state.student_id = previous_student_id
	game_state.parent_id = previous_parent_id


func _function_block(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + signature.length())
	return source.substr(start) if next < 0 else source.substr(start, next - start)


func _finish() -> void:
	var result := {"passed": _failures.is_empty(), "failures": _failures}
	var result_file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(result))
	if _failures.is_empty():
		print("game_leaderboard_contract_test: %d/%d passed" % [_checks, _checks])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
