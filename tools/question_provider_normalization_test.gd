extends SceneTree

const QuestionProviderScript = preload("res://scripts/question_provider.gd")

func _init() -> void:
	var provider := QuestionProviderScript.new()
	var api_question: Dictionary = provider._normalize_question({
		"id": 91,
		"question": "5 + 2 = ?",
		"options": ["8", "7", "6", "9"],
		"correct_answer": "7",
		"grade_level": "Grade 1",
		"difficulty": "Easy",
		"topic_id": "basic_addition",
		"learning_file_id": 77,
	})
	if not _assert_equal(api_question.get("correct"), "1", "API answer text must normalize to the QuizManager choice index"):
		provider.free()
		quit(1)
		return
	if not _assert_equal(api_question.get("question_set_id"), 77, "Remote question-set metadata must survive answer normalization"):
		provider.free()
		quit(1)
		return
	if not _assert_equal(api_question.get("topic_id"), "basic_addition", "Canonical topic IDs must survive question normalization"):
		provider.free()
		quit(1)
		return

	var indexed_remote_question: Dictionary = provider._normalize_question({
		"id": 92,
		"question": "Which index is correct?",
		"choices": ["5", "7", "9", "11"],
		"correct": "1",
	})
	if not _assert_equal(indexed_remote_question.get("correct"), "1", "Canonical remote choice indices must remain unchanged"):
		provider.free()
		quit(1)
		return

	var fallback_question: Dictionary = provider._normalize_question({
		"id": 1,
		"question": "5 + 2 = ?",
		"choices": ["8", "7", "6", "9"],
		"correct": 1,
	})
	if not _assert_equal(fallback_question.get("correct"), "1", "JSON fallback choice index must remain unchanged"):
		provider.free()
		quit(1)
		return

	var numeric_api_answer: Dictionary = provider._normalize_question({
		"id": 93,
		"question": "Which value is one?",
		"options": ["1", "2"],
		"correct_answer": "1",
	})
	if not _assert_equal(numeric_api_answer.get("correct"), "0", "API text answers must not be mistaken for fallback indices"):
		provider.free()
		quit(1)
		return

	var duplicate_choice_answer: Dictionary = provider._normalize_question({
		"id": 94,
		"question": "Which duplicate value is correct?",
		"options": ["7", "7", "9"],
		"correct_answer": "7",
	})
	if not _assert(duplicate_choice_answer.is_empty(), "Ambiguous duplicate answer text must be rejected"):
		provider.free()
		quit(1)
		return

	var unmatched_answer: Dictionary = provider._normalize_question({
		"id": 95,
		"question": "Which value is missing?",
		"options": ["5", "7", "9"],
		"correct_answer": "11",
	})
	if not _assert(unmatched_answer.is_empty(), "Unmatched answer text must be rejected"):
		provider.free()
		quit(1)
		return
	provider.free()
	quit()

func _assert_equal(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		printerr("[QuestionProvider Test] %s. Expected %s, got %s" % [message, str(expected), str(actual)])
		return false
	return true


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[QuestionProvider Test] %s" % message)
		return false
	return true
