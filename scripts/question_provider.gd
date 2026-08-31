extends Node

signal questions_loaded(count: int)
signal question_requested(question: Dictionary)
signal question_pool_exhausted(scope_descriptor: Dictionary)

const DEFAULT_SOURCE_PATH := "res://Data/questions.json"

var _source_path: String = DEFAULT_SOURCE_PATH
var _questions: Array[Dictionary] = []
var _history_by_scope: Dictionary = {}
var _fallback_history_by_filter: Dictionary = {}
var _last_requested_id: String = ""


func _ready() -> void:
	# An API-backed pool is requested by QuizManager after a real encounter starts.
	# Do not manufacture a fail-closed error during app startup before that context exists.
	if _should_wait_for_encounter_context():
		return
	# Call async load_questions without awaiting; it will emit signal when done.
	load_questions.call_deferred(_source_path)


func _should_wait_for_encounter_context() -> bool:
	if get_node_or_null("/root/HttpApi") == null:
		return false
	var game_state := get_node_or_null("/root/GameState")
	if game_state == null or not game_state.has_method("get_active_encounter_context"):
		return false
	var encounter_context: Variant = game_state.call("get_active_encounter_context")
	return encounter_context is Dictionary and encounter_context.is_empty()


func set_source_path(path: String) -> void:
	_source_path = path.strip_edges()
	if _source_path.is_empty():
		_source_path = DEFAULT_SOURCE_PATH
	load_questions.call_deferred(_source_path)


func get_source_path() -> String:
	return _source_path


func load_questions(path: String = "") -> Array[Dictionary]:
	var resolved_path := path.strip_edges()
	if resolved_path.is_empty():
		resolved_path = _source_path
	if resolved_path.is_empty():
		resolved_path = DEFAULT_SOURCE_PATH
	_source_path = resolved_path

	_questions.clear()
	_history_by_scope.clear()
	_fallback_history_by_filter.clear()
	_last_requested_id = ""
	# Prefer API-backed questions when HttpApi is available; fall back to local JSON file
	var http := get_node_or_null("/root/HttpApi")
	if http != null:
		var params := _get_encounter_question_params()
		if not _has_exact_scope(params):
			push_error("Remote question loading requires an explicit Grade, Difficulty, and Topic encounter scope.")
			questions_loaded.emit(0)
			return []
		var result: Dictionary = await http.request_get("/api/game/questions", params)
		if result.get("ok", false) and int(result.get("status", 0)) >= 200 and int(result.get("status", 0)) < 300:
			var body: Variant = result.get("body", {})
			if typeof(body) == TYPE_DICTIONARY and body.has("questions"):
				var question_entries: Array = body.get("questions", [])
				for entry in question_entries:
					if entry is Dictionary:
						var normalized := _normalize_question(entry)
						if not normalized.is_empty() and _question_matches_scope(normalized, params):
							_questions.append(normalized)
						elif not normalized.is_empty():
							push_error("Rejected a remote question outside the active Grade, Difficulty, and Topic scope.")
			questions_loaded.emit(_questions.size())
			return _questions
		# A failed exact-scope request must never widen into a local or unrelated pool.
		questions_loaded.emit(0)
		return []

	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open question source: %s" % resolved_path)
		questions_loaded.emit(0)
		return []

	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		push_error("JSON Parse Error in %s" % resolved_path)
		questions_loaded.emit(0)
		return []

	var parsed: Variant = json.data
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary:
				var normalized := _normalize_question(entry)
				if not normalized.is_empty():
					_questions.append(normalized)
	else:
		push_error("Question source %s did not resolve to an array" % resolved_path)
	questions_loaded.emit(_questions.size())
	return _questions


func _get_encounter_question_params() -> Dictionary:
	var params: Dictionary = {}
	var game_state := get_node_or_null("/root/GameState")
	if game_state == null or not game_state.has_method("get_encounter_question_scope"):
		return params
	var scope: Variant = game_state.call("get_encounter_question_scope")
	if not (scope is Dictionary):
		return params
	for key in ["grade", "difficulty"]:
		var value := str(scope.get(key, "")).strip_edges()
		if value.is_empty():
			return {}
		params[key] = value
	var topic_id := str(scope.get("topic_id", "")).strip_edges()
	if not topic_id.is_empty():
		params["topic_id"] = topic_id
		return params
	var topic := str(scope.get("topic", "")).strip_edges()
	if topic.is_empty():
		return {}
	params["topic"] = topic
	return params


func _has_exact_scope(scope: Dictionary) -> bool:
	for key in ["grade", "difficulty"]:
		if str(scope.get(key, "")).strip_edges().is_empty():
			return false
	return not str(scope.get("topic_id", scope.get("topic", ""))).strip_edges().is_empty()


func _question_matches_scope(question: Dictionary, scope: Dictionary) -> bool:
	if str(question.get("grade", "")).strip_edges() != str(scope.get("grade", "")).strip_edges() \
		or str(question.get("difficulty", "")).strip_edges() != str(scope.get("difficulty", "")).strip_edges():
		return false
	var scoped_topic_id := str(scope.get("topic_id", "")).strip_edges()
	if not scoped_topic_id.is_empty():
		return str(question.get("topic_id", "")).strip_edges() == scoped_topic_id
	return str(question.get("topic", "")).strip_edges() == str(scope.get("topic", "")).strip_edges()


func get_question(filters: Dictionary = {}) -> Dictionary:
	var candidates := _filter_questions(filters)
	if candidates.is_empty():
		return {}

	var resolved_scope := _resolve_question_scope(candidates[0])
	if not resolved_scope.is_empty():
		var scoped_candidates: Array[Dictionary] = []
		var scope_key := _scope_key(resolved_scope)
		for candidate in candidates:
			if _scope_key(_resolve_question_scope(candidate)) == scope_key:
				scoped_candidates.append(candidate)
		return _select_from_scope(scoped_candidates, resolved_scope)

	return _select_from_fallback(candidates, filters)


func reset_history() -> void:
	_history_by_scope.clear()
	_fallback_history_by_filter.clear()
	_last_requested_id = ""


func _scope_history(history_key: String) -> Array[String]:
	var history: Array[String] = []
	for value in _history_by_scope.get(history_key, []):
		history.append(str(value))
	return history


func _question_history_key(question: Dictionary) -> String:
	var question_set_id := str(question.get("question_set_id", "local")).strip_edges()
	return "%s|%s|%s|%s" % [
		str(question.get("grade", "")).strip_edges(),
		str(question.get("difficulty", "")).strip_edges(),
		str(question.get("topic_id", question.get("topic", ""))).strip_edges(),
		question_set_id,
	]


func _filter_questions(filters: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for question in _questions:
		if not question is Dictionary:
			continue
		if not _is_selectable_question(question):
			continue
		var matches := true
		if filters.has("grade"):
			var grade_value := str(filters.get("grade", "")).strip_edges()
			var question_grade := _question_grade(question)
			if not grade_value.is_empty() and question_grade != grade_value:
				matches = false
		if matches and filters.has("topic"):
			var topic_value := str(filters.get("topic", "")).strip_edges()
			var question_topic := _question_topic(question)
			if not topic_value.is_empty() and question_topic != topic_value:
				matches = false
		if matches and filters.has("topic_id"):
			var topic_id_value := str(filters.get("topic_id", ""))
			var question_topic_id := str(question.get("topic_id", ""))
			if not topic_id_value.is_empty() and question_topic_id != topic_id_value:
				matches = false
		if matches and filters.has("difficulty"):
			var requested_difficulty := str(filters.get("difficulty", "")).strip_edges()
			var difficulty_value := _canonical_difficulty(requested_difficulty)
			var question_difficulty := _canonical_difficulty(question.get("difficulty", ""))
			if not requested_difficulty.is_empty() and (difficulty_value.is_empty() or question_difficulty != difficulty_value):
				matches = false
		if matches and (filters.has("question_set_id") or filters.has("learning_file_id")):
			var requested_question_set_id := _positive_question_set_id(filters.get("question_set_id", filters.get("learning_file_id", null)))
			var candidate_question_set_id := _positive_question_set_id(question.get("question_set_id", question.get("learning_file_id", null)))
			if requested_question_set_id <= 0 or candidate_question_set_id != requested_question_set_id:
				matches = false
		if matches:
			candidates.append(question)
	return candidates


func _select_from_scope(candidates: Array[Dictionary], scope_descriptor: Dictionary) -> Dictionary:
	var unique_candidates := _unique_candidates(candidates)
	if unique_candidates.is_empty():
		return {}
	var scope_key := _scope_key(scope_descriptor)
	var history: Array = Array(_history_by_scope.get(scope_key, []))
	var available := _unused_candidates(unique_candidates, history)
	if available.is_empty():
		question_pool_exhausted.emit(scope_descriptor.duplicate(true))
		history.clear()
		available = unique_candidates.duplicate()
	available.shuffle()
	var selected: Dictionary = available[0]
	var selected_id := str(selected.get("id", ""))
	history.append(selected_id)
	_history_by_scope[scope_key] = history
	return _emit_selected_question(selected)


func _select_from_fallback(candidates: Array[Dictionary], filters: Dictionary) -> Dictionary:
	var unique_candidates := _unique_candidates(candidates)
	if unique_candidates.is_empty():
		return {}
	var filter_key := JSON.stringify(filters)
	var history: Array = Array(_fallback_history_by_filter.get(filter_key, []))
	var available := _unused_candidates(unique_candidates, history)
	if available.is_empty():
		history.clear()
		available = unique_candidates.duplicate()
	available.shuffle()
	var selected: Dictionary = available[0]
	history.append(str(selected.get("id", "")))
	_fallback_history_by_filter[filter_key] = history
	return _emit_selected_question(selected)


func _emit_selected_question(question: Dictionary) -> Dictionary:
	var question_copy := _clone_question(question)
	_last_requested_id = str(question_copy.get("id", ""))
	question_requested.emit(question_copy)
	return question_copy


func _unused_candidates(candidates: Array[Dictionary], history: Array) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for candidate in candidates:
		if not history.has(str(candidate.get("id", ""))):
			available.append(candidate)
	return available


func _unique_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var unique_candidates: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for candidate in candidates:
		var id := str(candidate.get("id", ""))
		if id.is_empty() or seen_ids.has(id):
			continue
		seen_ids[id] = true
		unique_candidates.append(candidate)
	return unique_candidates


func _is_selectable_question(question: Dictionary) -> bool:
	var id := str(question.get("id", "")).strip_edges()
	if id.is_empty():
		return false
	var choices: Variant = question.get("choices", null)
	if not (choices is Array) or choices.size() != 4:
		return false
	for choice in choices:
		if str(choice).strip_edges().is_empty():
			return false
	return true


func _resolve_question_scope(question: Dictionary) -> Dictionary:
	var question_set_id := _positive_question_set_id(question.get("question_set_id", question.get("learning_file_id", null)))
	var grade := _question_grade(question)
	var difficulty := _canonical_difficulty(question.get("difficulty", ""))
	var topic := _question_topic(question)
	if question_set_id <= 0 or grade.is_empty() or difficulty.is_empty() or topic.is_empty():
		return {}
	return {
		"question_set_id": question_set_id,
		"grade": grade,
		"difficulty": difficulty,
		"topic": topic,
	}


func _scope_key(scope_descriptor: Dictionary) -> String:
	if scope_descriptor.is_empty():
		return ""
	return "%s|%s|%s|%s" % [
		str(scope_descriptor.get("question_set_id", "")),
		str(scope_descriptor.get("grade", "")),
		str(scope_descriptor.get("difficulty", "")),
		str(scope_descriptor.get("topic", "")),
	]


func _question_grade(question: Dictionary) -> String:
	return str(question.get("grade", question.get("grade_level", ""))).strip_edges()


func _question_topic(question: Dictionary) -> String:
	return str(question.get("topic", question.get("math_topic", ""))).strip_edges()


func _canonical_difficulty(value: Variant) -> String:
	match str(value).strip_edges().to_lower():
		"easy":
			return "Easy"
		"normal", "medium":
			return "Medium"
		"difficult", "hard":
			return "Hard"
		_:
			return ""


func _positive_question_set_id(value: Variant) -> int:
	if value is int:
		return value if value > 0 else 0
	if value is float:
		var normalized := int(value)
		return normalized if value > 0.0 and value == float(normalized) else 0
	if value is String:
		var text: String = value.strip_edges()
		if text.is_valid_int():
			var parsed: int = text.to_int()
			return parsed if parsed > 0 else 0
	return 0


func _clone_question(question: Dictionary) -> Dictionary:
	var clone: Dictionary = {}
	for key in question.keys():
		clone[key] = question[key]
	if clone.has("choices") and clone["choices"] is Array:
		clone["choices"] = Array(clone["choices"])
	return clone


func _normalize_question(question: Dictionary) -> Dictionary:
	# Accept multiple backend shapes: {id, question, choices, correct} OR
	# {id, question, options, correct_answer, grade_level, difficulty}
	var normalized := Dictionary()
	var id_value = null
	if question.has("id"):
		id_value = question.get("id")
	elif question.has("_id"):
		id_value = question.get("_id")
	if id_value == null:
		return {}
	if id_value is String:
		normalized["id"] = id_value
	elif id_value is int or id_value is float:
		normalized["id"] = str(id_value)
	else:
		return {}

	var qtext = question.get("question") if question.has("question") else question.get("text")
	if qtext == null:
		return {}
	normalized["question"] = qtext

	var choices = null
	if question.has("choices"):
		choices = question.get("choices")
	elif question.has("options"):
		choices = question.get("options")
	if choices == null or not (choices is Array):
		return {}
	# QuizManager presents exactly four answer controls. Reject malformed
	# remote or fallback content instead of rendering blank battle choices.
	if choices.size() != 4:
		return {}
	normalized["choices"] = Array(choices)

	var correct: Variant = _normalize_correct_answer(question, normalized["choices"])
	if correct == null:
		return {}
	normalized["correct"] = correct

	var learning_file_id: Variant = question.get("learning_file_id", null)
	if learning_file_id is int and learning_file_id > 0:
		normalized["question_set_id"] = learning_file_id
	elif learning_file_id is float:
		var question_set_id := int(learning_file_id)
		if learning_file_id > 0.0 and learning_file_id == float(question_set_id):
			normalized["question_set_id"] = question_set_id

	# optional metadata passthrough
	for key in ["grade", "grade_level", "difficulty", "topic_id", "topic", "math_topic", "source"]:
		if question.has(key):
			normalized[key] = question.get(key)
	var normalized_grade := str(normalized.get("grade", normalized.get("grade_level", ""))).strip_edges()
	var normalized_topic := str(normalized.get("topic", normalized.get("math_topic", ""))).strip_edges()
	var normalized_topic_id := str(normalized.get("topic_id", "")).strip_edges().to_lower()
	if not normalized_grade.is_empty():
		normalized["grade"] = normalized_grade
	if not normalized_topic.is_empty():
		normalized["topic"] = normalized_topic
	if not normalized_topic_id.is_empty():
		normalized["topic_id"] = normalized_topic_id

	return normalized


func _normalize_correct_answer(question: Dictionary, choices: Array) -> Variant:
	# Local fallback questions already use QuizManager's zero-based `correct`
	# index. Published backend questions use `correct_answer` as choice text.
	if question.has("correct"):
		return _normalize_choice_index(question.get("correct"), choices.size())
	if question.has("correct_answer"):
		return _resolve_unique_choice_index(question.get("correct_answer"), choices)
	return null


func _normalize_choice_index(value: Variant, choice_count: int) -> Variant:
	var index := -1
	if value is int:
		index = value
	elif value is float:
		if value != floor(value):
			return null
		index = int(value)
	elif value is String:
		var index_text: String = value.strip_edges()
		if not index_text.is_valid_int():
			return null
		index = index_text.to_int()
	else:
		return null
	if index < 0 or index >= choice_count:
		return null
	return str(index)


func _resolve_unique_choice_index(answer: Variant, choices: Array) -> Variant:
	var answer_text := str(answer)
	var matching_index := -1
	for index in range(choices.size()):
		if str(choices[index]) != answer_text:
			continue
		if matching_index != -1:
			return null
		matching_index = index
	if matching_index == -1:
		return null
	return str(matching_index)
