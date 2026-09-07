extends Node

const QuestionProviderScript = preload("res://scripts/question_provider.gd")
const BASE_SCOPE := {"grade": "Grade 1", "difficulty": "Easy"}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var provider := QuestionProviderScript.new()
	var failed := false
	failed = not _assert_single_question_cycle(provider) or failed
	failed = not _assert_two_question_cycle(provider) or failed
	failed = not _assert_five_question_cycle(provider) or failed
	failed = not _assert_same_bandit_retry_uses_unused_question(provider) or failed
	failed = not _assert_new_bandit_same_scope_shares_history(provider) or failed
	failed = not _assert_scope_isolation(provider) or failed
	failed = not _assert_active_set_replacement(provider) or failed
	provider.free()
	if not failed:
		print("[Question Pool Randomization Test] PASS")
	get_tree().quit(1 if failed else 0)


func _assert_single_question_cycle(provider: Node) -> bool:
	_set_pool(provider, _make_pool(BASE_SCOPE, 101, 1))
	var first := _request(provider, BASE_SCOPE)
	var second := _request(provider, BASE_SCOPE)
	return _assert(_identity(first) == _identity(second), "one-question pool recycles only its single exact-scope question") \
		and _assert_scope(second, BASE_SCOPE, "one-question recycle preserves exact scope")


func _assert_two_question_cycle(provider: Node) -> bool:
	_set_pool(provider, _make_pool(BASE_SCOPE, 102, 2))
	var first := _request(provider, BASE_SCOPE)
	var second := _request(provider, BASE_SCOPE)
	return _assert(_identity(first) != _identity(second), "two-question pool uses both questions before reuse")


func _assert_five_question_cycle(provider: Node) -> bool:
	_set_pool(provider, _make_pool(BASE_SCOPE, 103, 5))
	var identities: Dictionary = {}
	var last_question: Dictionary = {}
	for _index in range(5):
		last_question = _request(provider, BASE_SCOPE)
		identities[_identity(last_question)] = true
		if not _assert_scope(last_question, BASE_SCOPE, "five-question selection preserves exact scope"):
			return false
	return _assert(identities.size() == 5, "five-question pool uses five distinct stable identities before reuse")


func _assert_same_bandit_retry_uses_unused_question(provider: Node) -> bool:
	_set_pool(provider, _make_pool(BASE_SCOPE, 104, 3))
	var first := _request(provider, BASE_SCOPE)
	var retry := _request(provider, BASE_SCOPE)
	return _assert(_identity(first) != _identity(retry), "same-Bandit retry receives another unused question")


func _assert_new_bandit_same_scope_shares_history(provider: Node) -> bool:
	_set_pool(provider, _make_pool(BASE_SCOPE, 105, 3))
	var first_bandit := _request(provider, BASE_SCOPE)
	var second_bandit := _request(provider, BASE_SCOPE)
	return _assert(_identity(first_bandit) != _identity(second_bandit), "new Bandit in the same exact pool shares unused-question history")


func _assert_scope_isolation(provider: Node) -> bool:
	var mixed_topic_scope := {"grade": "Grade 1", "difficulty": "Easy"}
	var difficulty_scope := {"grade": "Grade 1", "difficulty": "Normal"}
	var grade_scope := {"grade": "Grade 2", "difficulty": "Easy"}
	var pool: Array[Dictionary] = []
	pool.append_array(_make_pool(BASE_SCOPE, 106, 1, "addition-id", "Basic Addition"))
	pool.append_array(_make_pool(mixed_topic_scope, 106, 1, "subtraction-id", "Subtraction"))
	pool.append_array(_make_pool(difficulty_scope, 106, 1, "normal-id"))
	pool.append_array(_make_pool(grade_scope, 106, 1, "grade-two-id"))
	_set_pool(provider, pool)
	return _assert_scope(_request(provider, BASE_SCOPE), BASE_SCOPE, "base scope is selectable") \
		and _assert_scope(_request(provider, mixed_topic_scope), mixed_topic_scope, "mixed Topic metadata remains in one Grade and Difficulty pool") \
		and _assert_scope(_request(provider, difficulty_scope), difficulty_scope, "different difficulty uses separate history") \
		and _assert_scope(_request(provider, grade_scope), grade_scope, "different grade uses separate history")


func _assert_active_set_replacement(provider: Node) -> bool:
	_set_pool(provider, _make_pool(BASE_SCOPE, 107, 1, "stable-question"))
	var set_a_question := _request(provider, BASE_SCOPE)
	_set_questions_without_reset(provider, _make_pool(BASE_SCOPE, 108, 1, "stable-question"))
	var set_b_question := _request(provider, BASE_SCOPE)
	return _assert(_identity(set_a_question) != _identity(set_b_question), "new active set uses a fresh set-specific history") \
		and _assert_scope(set_b_question, BASE_SCOPE, "active-set replacement preserves exact scope")


func _make_pool(scope: Dictionary, question_set_id: int, count: int, fixed_id: String = "", topic: String = "") -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for index in range(count):
		var question_id := fixed_id if not fixed_id.is_empty() else "question-%s" % index
		var question: Dictionary = {
			"id": question_id,
			"question": "Fixture %s" % index,
			"choices": ["1", "2", "3", "4"],
			"correct": "0",
			"grade": scope["grade"],
			"difficulty": scope["difficulty"],
			"question_set_id": question_set_id,
		}
		if not topic.is_empty():
			question["topic"] = topic
		pool.append(question)
	return pool


func _set_pool(provider: Node, pool: Array[Dictionary]) -> void:
	provider.set("_questions", pool)
	provider.call("reset_history")


func _set_questions_without_reset(provider: Node, pool: Array[Dictionary]) -> void:
	provider.set("_questions", pool)


func _request(provider: Node, scope: Dictionary) -> Dictionary:
	var result: Variant = provider.call("get_question", scope)
	return result if result is Dictionary else {}


func _identity(question: Dictionary) -> String:
	return "%s|%s" % [str(question.get("question_set_id", "")), str(question.get("id", ""))]


func _assert_scope(question: Dictionary, scope: Dictionary, message: String) -> bool:
	return _assert(str(question.get("grade", "")) == str(scope.get("grade", "")) \
		and str(question.get("difficulty", "")) == str(scope.get("difficulty", "")), message)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[Question Pool Randomization Test] %s" % message)
		return false
	return true
