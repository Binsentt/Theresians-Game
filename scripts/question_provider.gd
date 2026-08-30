extends Node

signal questions_loaded(count: int)
signal question_requested(question: Dictionary)

const DEFAULT_SOURCE_PATH := "res://Data/questions.json"

var _source_path: String = DEFAULT_SOURCE_PATH
var _questions: Array[Dictionary] = []
var _history: Array[String] = []
var _history_by_scope: Dictionary = {}
var _last_requested_id: String = ""


func _ready() -> void:
	# Call async load_questions without awaiting; it will emit signal when done
	load_questions.call_deferred(_source_path)


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
	_history.clear()
	_history_by_scope.clear()
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
	for key in ["grade", "difficulty", "topic"]:
		var value := String(scope.get(key, "")).strip_edges()
		if value.is_empty():
			return {}
		params[key] = value
	return params


func _has_exact_scope(scope: Dictionary) -> bool:
	for key in ["grade", "difficulty", "topic"]:
		if String(scope.get(key, "")).strip_edges().is_empty():
			return false
	return true


func _question_matches_scope(question: Dictionary, scope: Dictionary) -> bool:
	return String(question.get("grade", "")).strip_edges() == String(scope.get("grade", "")).strip_edges() \
		and String(question.get("difficulty", "")).strip_edges() == String(scope.get("difficulty", "")).strip_edges() \
		and String(question.get("topic", "")).strip_edges() == String(scope.get("topic", "")).strip_edges()


func get_question(filters: Dictionary = {}) -> Dictionary:
	var candidates := _filter_questions(filters)
	if candidates.is_empty():
		return {}

	candidates.shuffle()
	for candidate in candidates:
		var id := str(candidate.get("id", ""))
		if id.is_empty():
			continue
		var history_key := _question_history_key(candidate)
		var history := _scope_history(history_key)
		if history.has(id):
			continue
		history.append(id)
		if history.size() > 32:
			history.remove_at(0)
		_history_by_scope[history_key] = history
		_history = history.duplicate()
		_last_requested_id = id
		var question_copy := _clone_question(candidate)
		question_requested.emit(question_copy)
		return question_copy

	var fallback := _clone_question(candidates[0])
	var fallback_history_key := _question_history_key(fallback)
	var fallback_history := _scope_history(fallback_history_key)
	fallback_history.append(str(fallback.get("id", "")))
	_history_by_scope[fallback_history_key] = fallback_history
	_history = fallback_history.duplicate()
	_last_requested_id = str(fallback.get("id", ""))
	return fallback


func reset_history() -> void:
	_history.clear()
	_history_by_scope.clear()
	_last_requested_id = ""


func _scope_history(history_key: String) -> Array[String]:
	var history: Array[String] = []
	for value in _history_by_scope.get(history_key, []):
		history.append(String(value))
	return history


func _question_history_key(question: Dictionary) -> String:
	var question_set_id := String(question.get("question_set_id", "local")).strip_edges()
	return "%s|%s|%s|%s" % [
		String(question.get("grade", "")).strip_edges(),
		String(question.get("difficulty", "")).strip_edges(),
		String(question.get("topic", "")).strip_edges(),
		question_set_id,
	]


func _filter_questions(filters: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for question in _questions:
		if not question is Dictionary:
			continue
		var matches := true
		if filters.has("grade"):
			var grade_value := str(filters.get("grade", ""))
			var question_grade := str(question.get("grade", ""))
			if not grade_value.is_empty() and question_grade != grade_value:
				matches = false
		if matches and filters.has("topic"):
			var topic_value := str(filters.get("topic", ""))
			var question_topic := str(question.get("topic", ""))
			if not topic_value.is_empty() and question_topic != topic_value:
				matches = false
		if matches and filters.has("difficulty"):
			var difficulty_value := str(filters.get("difficulty", ""))
			var question_difficulty := str(question.get("difficulty", ""))
			if not difficulty_value.is_empty() and question_difficulty != difficulty_value:
				matches = false
		if matches:
			candidates.append(question)
	return candidates


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
	if choices.size() < 2:
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
	for key in ["grade", "grade_level", "difficulty", "topic", "math_topic", "source"]:
		if question.has(key):
			normalized[key] = question.get(key)
	var normalized_grade := String(normalized.get("grade", normalized.get("grade_level", ""))).strip_edges()
	var normalized_topic := String(normalized.get("topic", normalized.get("math_topic", ""))).strip_edges()
	if not normalized_grade.is_empty():
		normalized["grade"] = normalized_grade
	if not normalized_topic.is_empty():
		normalized["topic"] = normalized_topic

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
