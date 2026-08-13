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
	})
	if not _assert_equal(api_question.get("correct"), "1", "API answer text must normalize to the QuizManager choice index"):
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
		"id": 92,
		"question": "Which value is one?",
		"options": ["1", "2"],
		"correct_answer": "1",
	})
	if not _assert_equal(numeric_api_answer.get("correct"), "0", "API text answers must not be mistaken for fallback indices"):
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
