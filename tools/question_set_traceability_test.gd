extends Node

const QuestionProviderScript = preload("res://scripts/question_provider.gd")
const RemoteSyncScript = preload("res://scripts/remote_sync.gd")


class HttpApiStub extends Node:
	var requests: Array[Dictionary] = []

	func request_post(path: String, payload: Dictionary) -> Dictionary:
		requests.append({
			"path": path,
			"payload": payload.duplicate(true),
		})
		return {"ok": true, "status": 201, "body": {}}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var provider := QuestionProviderScript.new()

	var remote_question: Dictionary = provider._normalize_question({
		"id": 91,
		"question": "5 + 2 = ?",
		"choices": ["8", "7", "6", "9"],
		"correct": 1,
		"learning_file_id": 77,
	})
	failed = not _assert_equal(remote_question.get("question_set_id"), 77, "Remote learning_file_id must be preserved as question_set_id") or failed
	failed = not _assert_equal(typeof(remote_question.get("question_set_id")), TYPE_INT, "Remote question_set_id must be an integer") or failed
	var exact_scope := {"grade": "Grade 1", "difficulty": "Easy", "topic_id": "basic_addition", "topic": "Basic Addition"}
	var scoped_remote_question: Dictionary = provider._normalize_question({
		"id": 92,
		"question": "5 + 2 = ?",
		"options": ["8", "7", "6", "9"],
		"correct_answer": "7",
		"learning_file_id": 77,
		"grade_level": "Grade 1",
		"difficulty": "Easy",
		"topic_id": "basic_addition",
		"math_topic": "Basic Addition",
	})
	failed = not _assert(provider._question_matches_scope(scoped_remote_question, exact_scope), "Remote question metadata must match the active exact scope.") or failed
	var mismatched_question := scoped_remote_question.duplicate(true)
	mismatched_question["topic_id"] = "subtraction"
	failed = not _assert(not provider._question_matches_scope(mismatched_question, exact_scope), "QuestionProvider must reject a response outside the active topic scope.") or failed
	failed = not _assert_no_filename_scope_routing() or failed
	failed = not _assert_scope_history(provider) or failed

	var float_set_question := _normalize_question_with_learning_file_id(provider, 77.0)
	failed = not _assert_equal(float_set_question.get("question_set_id"), 77, "Integral float learning_file_id must normalize to question_set_id") or failed
	failed = not _assert_equal(typeof(float_set_question.get("question_set_id")), TYPE_INT, "Integral float learning_file_id must produce an integer question_set_id") or failed

	for invalid_set_id in [77.5, 0, -1, "77"]:
		var invalid_set_question := _normalize_question_with_learning_file_id(provider, invalid_set_id)
		failed = not _assert(not invalid_set_question.has("question_set_id"), "Non-positive, fractional, and string learning_file_id values must be omitted") or failed

	var fallback_question: Dictionary = provider._normalize_question({
		"id": 1,
		"question": "5 + 2 = ?",
		"choices": ["8", "7", "6", "9"],
		"correct": 1,
	})
	failed = not _assert(not fallback_question.has("question_set_id"), "Local fallback questions must not receive a question_set_id") or failed
	failed = not _assert_quiz_manager_wiring() or failed

	var remote_sync: Node = RemoteSyncScript.new()
	if not _assert(remote_sync.has_method("record_question_attempt"), "RemoteSync must expose record_question_attempt(question, is_correct)"):
		failed = true
	else:
		failed = _assert_recorded_payloads(remote_sync) or failed

	remote_sync.free()
	provider.free()
	get_tree().quit(1 if failed else 0)


func _normalize_question_with_learning_file_id(provider: Node, learning_file_id: Variant) -> Dictionary:
	var normalized: Variant = provider.call("_normalize_question", {
		"id": 91,
		"question": "5 + 2 = ?",
		"choices": ["8", "7", "6", "9"],
		"correct": 1,
		"learning_file_id": learning_file_id,
	})
	return normalized if normalized is Dictionary else {}


func _assert_no_filename_scope_routing() -> bool:
	var provider_file := FileAccess.open("res://scripts/question_provider.gd", FileAccess.READ)
	if provider_file == null:
		return _assert(false, "QuestionProvider source must be readable")
	var source := provider_file.get_as_text()
	provider_file.close()
	return _assert(not source.contains("resolved_path.find(\"?\")"), "QuestionProvider must not derive scope from source-file query text") \
		and _assert(not source.contains("Set A") and not source.contains("Set B"), "QuestionProvider must not route by set labels")


func _assert_scope_history(provider: Node) -> bool:
	var exact_scope := {"grade": "Grade 1", "difficulty": "Easy", "topic": "Basic Addition"}
	var addition_questions: Array[Dictionary] = [
		{"id": "addition-1", "question": "1 + 1", "choices": ["1", "2"], "correct": "1", "grade": "Grade 1", "difficulty": "Easy", "topic": "Basic Addition", "question_set_id": 77},
		{"id": "addition-2", "question": "2 + 1", "choices": ["2", "3"], "correct": "1", "grade": "Grade 1", "difficulty": "Easy", "topic": "Basic Addition", "question_set_id": 77},
	]
	provider.set("_questions", addition_questions)
	provider.call("reset_history")
	var first: Dictionary = provider.call("get_question", exact_scope)
	var second: Dictionary = provider.call("get_question", exact_scope)
	var unused_before_recycle: bool = str(first.get("id", "")) != str(second.get("id", ""))
	var subtraction_questions: Array[Dictionary] = [
		{"id": "subtraction-1", "question": "3 - 1", "choices": ["1", "2"], "correct": "1", "grade": "Grade 1", "difficulty": "Easy", "topic": "Subtraction", "question_set_id": 88},
	]
	provider.set("_questions", subtraction_questions)
	provider.call("get_question", {"grade": "Grade 1", "difficulty": "Easy", "topic": "Subtraction"})
	var histories: Dictionary = provider.get("_history_by_scope")
	return _assert(unused_before_recycle, "QuestionProvider must use an unused question before recycling within one exact scope") \
		and _assert(histories.size() == 2, "Question history must be isolated by Grade, Difficulty, Topic, and active question set")


func _assert_quiz_manager_wiring() -> bool:
	var quiz_manager_file := FileAccess.open("res://Battle/Battle-Enemy/QuizManager.gd", FileAccess.READ)
	if quiz_manager_file == null:
		return _assert(false, "QuizManager source must be readable")
	var source := quiz_manager_file.get_as_text()
	quiz_manager_file.close()
	var has_answer_hook := source.contains("_record_question_attempt(q, is_correct)")
	var has_deferred_sync := source.contains("remote_sync.call_deferred(\"record_question_attempt\", question.duplicate(true), is_correct)")
	return _assert(has_answer_hook, "QuizManager must forward each answer through _record_question_attempt(q, is_correct)") and _assert(has_deferred_sync, "QuizManager must defer question-attempt forwarding to RemoteSync")


func _assert_recorded_payloads(remote_sync: Node) -> bool:
	var root: Window = get_tree().root
	remote_sync.name = "TraceabilityRemoteSync"
	root.add_child(remote_sync)
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state == null:
		return not _assert(false, "The test runner must provide the GameState autoload")
	var active_http: Node = root.get_node_or_null("HttpApi")
	var original_http_name := ""
	if active_http != null:
		original_http_name = active_http.name
		active_http.name = "_question_set_traceability_original_http"

	var http_stub := HttpApiStub.new()
	http_stub.name = "HttpApi"
	root.add_child(http_stub)

	var original_student_id: Variant = game_state.get("student_id")
	var original_parent_id: Variant = game_state.get("parent_id")
	var original_player_name: Variant = game_state.get("player_name")
	var original_grade_level: Variant = game_state.get("grade_level")
	remote_sync.set("_current_playtime_session_id", 501)
	remote_sync.set("_current_playtime_session_credential", "test-server-issued-lease")
	game_state.set("student_id", "123456")
	game_state.set("parent_id", "654321")
	game_state.set("player_name", "Traceability Student")
	game_state.set("grade_level", "Grade 3")

	remote_sync.call("record_question_attempt", {
		"question_set_id": 77,
		"topic_id": "addition",
		"topic": "Addition",
		"difficulty": "Easy",
	}, false)
	remote_sync.call("record_question_attempt", {
		"topic": "Addition",
		"difficulty": "Easy",
	}, true)

	var failed := false
	failed = not _assert_equal(http_stub.requests.size(), 2, "Each answered question must post one result") or failed
	if http_stub.requests.size() >= 2:
		var remote_payload: Dictionary = http_stub.requests[0].get("payload", {})
		var fallback_payload: Dictionary = http_stub.requests[1].get("payload", {})
		failed = not _assert_equal(http_stub.requests[0].get("path"), "/api/game/result", "Question attempts must use the game-result endpoint") or failed
		failed = not _assert_equal(remote_payload.get("question_set_id"), 77, "Positive question_set_id must be included in the result payload") or failed
		failed = not _assert_equal(remote_payload.get("topic_id"), "addition", "Canonical question topic_id must be included in the result payload") or failed
		failed = not _assert(not fallback_payload.has("question_set_id"), "Result payloads must omit missing question_set_id values") or failed
		failed = not _assert_equal(remote_payload.get("playtime_session_id"), 501, "Question results must include the active server playtime session") or failed
		failed = not _assert_equal(remote_payload.get("playtime_session_credential"), "test-server-issued-lease", "Question results must include the issued server lease credential") or failed
		failed = not _assert_equal(remote_payload.get("score"), 0, "Incorrect answers must be forwarded as score 0") or failed
		failed = not _assert_equal(fallback_payload.get("score"), 1, "Correct answers must be forwarded as score 1") or failed

	game_state.set("student_id", original_student_id)
	game_state.set("parent_id", original_parent_id)
	game_state.set("player_name", original_player_name)
	game_state.set("grade_level", original_grade_level)
	http_stub.free()
	if active_http != null:
		active_http.name = original_http_name

	return failed


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[Question Set Traceability Test] %s" % message)
		return false
	return true


func _assert_equal(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		printerr("[Question Set Traceability Test] %s. Expected %s, got %s" % [message, str(expected), str(actual)])
		return false
	return true
