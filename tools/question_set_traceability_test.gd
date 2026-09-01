extends SceneTree

const QuestionProviderScript = preload("res://scripts/question_provider.gd")


func _init() -> void:
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

	failed = not _assert_remote_sync_payload_contract() or failed
	provider.free()
	quit(1 if failed else 0)


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
	var has_deferred_sync := source.contains("remote_sync.call_deferred(\"record_question_attempt\", question.duplicate(true), is_correct)")
	return _assert(has_answer_hook, "QuizManager must forward each answer through _record_question_attempt(q, is_correct)") and _assert(has_deferred_sync, "QuizManager must defer question-attempt forwarding to RemoteSync")


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
		and _assert(payload_source.contains("\"difficulty\": String(question.get(\"difficulty\""), "Result payloads must retain Difficulty traceability") \
		and _assert(payload_source.contains("payload[\"question_set_id\"]"), "Positive question_set_id must be included in the result payload") \
		and _assert(not payload_source.contains("\"topic_id\"") and not payload_source.contains("\"math_topic\""), "Result payloads must not require or manufacture Topic metadata")


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
