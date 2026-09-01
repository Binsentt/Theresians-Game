extends SceneTree

const QuestionProviderScript = preload("res://scripts/question_provider.gd")

var _exhausted_scopes: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var provider := QuestionProviderScript.new()
	var test_questions: Array[Dictionary] = [
		_question("a-1", 101, "Grade 1", "Easy", "Basic Addition"),
		_question("a-2", 101, "Grade 1", "Easy", "Basic Addition"),
		_question("b-1", 202, "Grade 1", "Medium", "Basic Addition"),
		_question("b-2", 202, "Grade 1", "Medium", "Basic Addition"),
		_question("c-valid", 303, "Grade 2", "Hard", "Fractions"),
		_question("c-malformed", 303, "Grade 2", "Hard", "Fractions", ["1", "2", "3"]),
	]
	provider._questions = test_questions

	var failed := false
	failed = not _assert(provider.has_signal("question_pool_exhausted"), "QuestionProvider must expose question_pool_exhausted(scope_descriptor).") or failed
	if provider.has_signal("question_pool_exhausted"):
		provider.connect("question_pool_exhausted", Callable(self, "_on_question_pool_exhausted"))

	var medium_scope := {
		"question_set_id": 202,
		"grade": "Grade 1",
		"difficulty": "Normal",
	}
	var medium_candidates: Array[Dictionary] = provider.call("_filter_questions", medium_scope)
	failed = not _assert_equal(medium_candidates.size(), 2, "Normalized Normal difficulty and question_set_id must resolve only Set 202 candidates.") or failed
	for candidate in medium_candidates:
		failed = not _assert_equal(int(candidate.get("question_set_id", 0)), 202, "Exact-scope filtering must not mix a different question set.") or failed

	var malformed_scope := {
		"question_set_id": 303,
		"grade": "Grade 2",
		"difficulty": "Difficult",
	}
	var valid_candidates: Array[Dictionary] = provider.call("_filter_questions", malformed_scope)
	failed = not _assert_equal(valid_candidates.size(), 1, "Three-choice candidates must be excluded from the selectable question pool.") or failed
	if valid_candidates.size() == 1:
		failed = not _assert_equal(String(valid_candidates[0].get("id", "")), "c-valid", "The valid four-choice candidate must remain available.") or failed

	var easy_scope := {
		"question_set_id": 101,
		"grade": "Grade 1",
		"difficulty": "Easy",
	}
	var medium_first: Dictionary = provider.get_question(medium_scope)
	failed = not _assert_equal(int(medium_first.get("question_set_id", 0)), 202, "Set 202 must be selectable without falling into Set 101.") or failed

	var easy_first: Dictionary = provider.get_question(easy_scope)
	var easy_second: Dictionary = provider.get_question(easy_scope)
	failed = not _assert(not easy_first.is_empty() and not easy_second.is_empty(), "A valid exact-scope pool must return its questions before exhaustion.") or failed
	failed = not _assert(String(easy_first.get("id", "")) != String(easy_second.get("id", "")), "A question must not repeat before its exact scope is exhausted.") or failed
	var easy_new_round: Dictionary = provider.get_question(easy_scope)
	failed = not _assert_equal(_exhausted_scopes.size(), 1, "Exhausting Set 101 must emit exactly one structured exhaustion event.") or failed
	if _exhausted_scopes.size() == 1:
		failed = not _assert_equal(_exhausted_scopes[0], {
			"question_set_id": 101,
			"grade": "Grade 1",
			"difficulty": "Easy",
		}, "The exhaustion event must describe only the exhausted Grade and Difficulty set scope.") or failed
	failed = not _assert_equal(int(easy_new_round.get("question_set_id", 0)), 101, "A new round must stay inside the exhausted scope instead of falling back to another set.") or failed

	var medium_second: Dictionary = provider.get_question(medium_scope)
	failed = not _assert(String(medium_second.get("id", "")) != String(medium_first.get("id", "")), "Exhausting Set 101 must not clear Set 202 history.") or failed
	var medium_new_round: Dictionary = provider.get_question(medium_scope)
	failed = not _assert_equal(_exhausted_scopes.size(), 2, "Each independently exhausted scope must emit one event for its own round.") or failed
	if _exhausted_scopes.size() == 2:
		failed = not _assert_equal(int(_exhausted_scopes[1].get("question_set_id", 0)), 202, "Set 202 exhaustion must not be attributed to Set 101.") or failed
	failed = not _assert_equal(int(medium_new_round.get("question_set_id", 0)), 202, "Set 202 must restart only within its own scope.") or failed

	var unavailable: Dictionary = provider.get_question({
		"question_set_id": 404,
		"grade": "Grade 6",
		"difficulty": "Easy",
	})
	failed = not _assert(unavailable.is_empty(), "An unavailable exact scope must report no question instead of selecting an unrelated fallback.") or failed
	var unsupported_difficulty: Dictionary = provider.get_question({
		"question_set_id": 101,
		"grade": "Grade 1",
		"difficulty": "Unsupported Difficulty",
	})
	failed = not _assert(unsupported_difficulty.is_empty(), "An unsupported difficulty must not broaden selection into a valid remote scope.") or failed

	provider._questions = [{
		"id": "local-fallback",
		"question": "Local fallback question",
		"choices": ["1", "2", "3", "4"],
		"correct": "0",
	}]
	var local_fallback: Dictionary = provider.get_question()
	failed = not _assert_equal(String(local_fallback.get("id", "")), "local-fallback", "A valid local fallback question must remain selectable when remote scope data is unavailable.") or failed
	failed = not _assert(not local_fallback.has("question_set_id"), "Local fallback questions must not gain remote question-set traceability metadata.") or failed

	provider.free()
	if not failed:
		print("question_pool_exhaustion_test: PASS")
	quit(1 if failed else 0)


func _question(id: String, question_set_id: int, grade_level: String, difficulty: String, math_topic: String, choices: Array = ["1", "2", "3", "4"]) -> Dictionary:
	return {
		"id": id,
		"question": "Question %s" % id,
		"choices": choices,
		"correct": "0",
		"question_set_id": question_set_id,
		"grade_level": grade_level,
		"difficulty": difficulty,
		"math_topic": math_topic,
	}


func _on_question_pool_exhausted(scope_descriptor: Dictionary) -> void:
	_exhausted_scopes.append(scope_descriptor.duplicate(true))


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[Question Pool Exhaustion Test] %s" % message)
		return false
	return true


func _assert_equal(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		printerr("[Question Pool Exhaustion Test] %s. Expected %s, got %s" % [message, str(expected), str(actual)])
		return false
	return true
