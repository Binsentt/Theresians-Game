extends Node

const QuestionProviderScript = preload("res://scripts/question_provider.gd")
const RemoteSyncScript = preload("res://scripts/remote_sync.gd")
var _failures: Array[String] = []
var _assertions := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var provider := QuestionProviderScript.new()
	provider.name = "QuestionProviderUnderTest"
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set("encounter_context", {})
	add_child(provider)
	failed = not _assert(provider.is_inside_tree(), "QuestionProvider fixture is in the scene tree before absolute-root context lookups") or failed

	var remote_question: Dictionary = provider._normalize_question({
		"id": 91,
		"question": "5 + 2 = ?",
		"choices": ["8", "7", "6", "9"],
		"correct": 1,
		"learning_file_id": 77,
	})
	failed = not _assert_equal(remote_question.get("question_set_id"), 77, "Remote learning_file_id must be preserved as question_set_id") or failed
	failed = not _assert_equal(typeof(remote_question.get("question_set_id")), TYPE_INT, "Remote question_set_id must be an integer") or failed
	var exact_scope := {"grade": "Grade 1", "difficulty": "Easy"}
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
	var canonical_remote_question: Dictionary = provider._normalize_question({
		"id": 501,
		"question_id": 501,
		"question": "3 + 4 = ?",
		"options": ["6", "7", "8", "9"],
		"correct_answer": "7",
		"learning_file_id": 77,
		"question_set_id": 77,
		"grade": "Grade 1",
		"difficulty": "Easy",
		"topic_id": "Basic_Addition",
	})
	failed = not _assert_equal(canonical_remote_question.get("question_id"), 501, "A pushed database question ID is preserved as canonical traceability") or failed
	failed = not _assert_equal(canonical_remote_question.get("question_set_id"), 77, "A pushed question set ID is preserved with the question") or failed
	failed = not _assert_equal(canonical_remote_question.get("topic_id"), "Basic_Addition", "Canonical topic IDs are preserved exactly as delivered") or failed
	var topic_gap_question: Dictionary = provider._normalize_question({
		"id": 502,
		"question_id": 502,
		"question": "4 + 1 = ?",
		"options": ["4", "5", "6", "7"],
		"correct_answer": "5",
		"learning_file_id": 77,
		"grade": "Grade 1",
		"difficulty": "Easy",
		"topic_id": null,
		"canonical_topic_id": null,
	})
	failed = not _assert(not topic_gap_question.has("topic_id"), "A null canonical topic remains absent instead of becoming the string null") or failed
	var remote_sync := RemoteSyncScript.new()
	var topic_gap_result_payload: Dictionary = remote_sync.call("_build_question_result_payload", topic_gap_question, true)
	failed = not _assert(not topic_gap_result_payload.has("topic_id"), "A question endpoint null topic remains absent from the result payload instead of becoming an invalid topic string") or failed
	remote_sync.free()
	failed = not _assert(provider._question_matches_scope(scoped_remote_question, exact_scope), "Remote question metadata must match the active Grade and Difficulty scope.") or failed
	var mismatched_question := scoped_remote_question.duplicate(true)
	mismatched_question["topic_id"] = "subtraction"
	failed = not _assert(provider._question_matches_scope(mismatched_question, exact_scope), "QuestionProvider must ignore optional Topic metadata for active-pool matching.") or failed
	failed = not _assert_equal(provider._question_history_key(scoped_remote_question), "Grade 1|Easy|77", "Question history must use Grade, Difficulty, and question_set_id only") or failed
	failed = not _assert_equal(provider._question_history_key(mismatched_question), "Grade 1|Easy|77", "Optional Topic metadata must not change question history scope") or failed
	failed = not _assert_no_filename_scope_routing() or failed
	failed = not _assert_scope_history(provider) or failed

	var float_set_question := _normalize_question_with_learning_file_id(provider, 77.0)
	failed = not _assert_equal(float_set_question.get("question_set_id"), 77, "Integral float learning_file_id must normalize to question_set_id") or failed
	failed = not _assert_equal(typeof(float_set_question.get("question_set_id")), TYPE_INT, "Integral float learning_file_id must produce an integer question_set_id") or failed

	var numeric_string_set_question := _normalize_question_with_learning_file_id(provider, "77")
	failed = not _assert_equal(numeric_string_set_question.get("question_set_id"), 77, "An exact positive numeric question-set ID string normalizes to the backend integer contract") or failed
	for invalid_set_id in [77.5, 0, -1]:
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

	failed = not _assert_remote_sync_payload_contract() or failed
	provider.queue_free()
	var result_directory := ProjectSettings.globalize_path("user://qa_local_saves")
	DirAccess.make_dir_recursive_absolute(result_directory)
	var result_file := FileAccess.open("user://qa_local_saves/question_set_traceability_test_result.json", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify({"passed": _assertions - _failures.size(), "failed": _failures.size(), "failures": _failures, "live_network_calls": 0, "production_writes": 0}, "\t"))
		result_file.close()
	if not failed:
		print("QUESTION_SET_TRACEABILITY_TEST PASSED")
	await get_tree().create_timer(0.5).timeout
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
	var exact_scope := {"grade": "Grade 1", "difficulty": "Easy"}
	var addition_questions: Array[Dictionary] = [
		{"id": "addition-1", "question": "1 + 1", "choices": ["1", "2", "3", "4"], "correct": "1", "grade": "Grade 1", "difficulty": "Easy", "topic": "Basic Addition", "question_set_id": 77},
		{"id": "addition-2", "question": "2 + 1", "choices": ["1", "2", "3", "4"], "correct": "1", "grade": "Grade 1", "difficulty": "Easy", "topic": "Subtraction", "question_set_id": 77},
	]
	provider.set("_questions", addition_questions)
	provider.call("reset_history")
	var first: Dictionary = provider.call("get_question", exact_scope)
	var second: Dictionary = provider.call("get_question", exact_scope)
	var unused_before_recycle: bool = str(first.get("id", "")) != str(second.get("id", ""))
	var subtraction_questions: Array[Dictionary] = [
		{"id": "subtraction-1", "question": "3 - 1", "choices": ["1", "2", "3", "4"], "correct": "1", "grade": "Grade 1", "difficulty": "Easy", "topic": "Subtraction", "question_set_id": 88},
	]
	provider.set("_questions", subtraction_questions)
	provider.call("get_question", {"grade": "Grade 1", "difficulty": "Easy"})
	var histories: Dictionary = provider.get("_history_by_scope")
	return _assert(unused_before_recycle, "QuestionProvider must use an unused question before recycling within one exact scope") \
		and _assert(histories.size() == 2, "Question history must be isolated by Grade, Difficulty, and active question set")


func _assert_quiz_manager_wiring() -> bool:
	var quiz_manager_file := FileAccess.open("res://Battle/Battle-Enemy/QuizManager.gd", FileAccess.READ)
	if quiz_manager_file == null:
		return _assert(false, "QuizManager source must be readable")
	var source := quiz_manager_file.get_as_text()
	quiz_manager_file.close()
	var has_answer_hook := source.contains("_record_question_attempt(q, is_correct)")
	var durable_sync := source.contains("remote_sync.call(\"record_question_attempt\", question.duplicate(true), is_correct)")
	return _assert(has_answer_hook, "QuizManager must forward each answer through _record_question_attempt(q, is_correct)") and _assert(durable_sync, "QuizManager immediately invokes RemoteSync's synchronous staging boundary")


func _assert_remote_sync_payload_contract() -> bool:
	var remote_sync_file := FileAccess.open("res://scripts/remote_sync.gd", FileAccess.READ)
	if remote_sync_file == null:
		return _assert(false, "RemoteSync source must be readable")
	var source := remote_sync_file.get_as_text()
	remote_sync_file.close()
	var start := source.find("func record_question_attempt")
	var end := source.find("func _enqueue_pending", start)
	var payload_source := source.substr(start, end - start) if start >= 0 and end > start else ""
	return _assert(payload_source.contains("\"grade_level\": GameState.grade_level"), "Result payloads must retain Grade traceability") \
		and _assert(payload_source.contains("\"difficulty\": str(question.get(\"difficulty\""), "Result payloads must retain Difficulty traceability") \
		and _assert(payload_source.contains("payload[\"question_set_id\"]"), "Positive question_set_id must be included in the result payload") \
		and _assert(payload_source.contains("payload[\"topic_id\"]"), "Result payloads preserve canonical topic metadata when present") \
		and _assert(not payload_source.contains("\"math_topic\""), "Result payloads do not substitute display topic text for a canonical topic ID")


func _assert(condition: bool, message: String) -> bool:
	_assertions += 1
	if not condition:
		_failures.append(message)
		printerr("[Question Set Traceability Test] %s" % message)
		return false
	return true


func _assert_equal(actual: Variant, expected: Variant, message: String) -> bool:
	_assertions += 1
	if actual != expected:
		_failures.append(message)
		printerr("[Question Set Traceability Test] %s. Expected %s, got %s" % [message, str(expected), str(actual)])
		return false
	return true
