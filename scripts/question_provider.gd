extends Node

signal questions_loaded(count: int)
signal question_requested(question: Dictionary)

const DEFAULT_SOURCE_PATH := "res://Data/questions.json"

var _source_path: String = DEFAULT_SOURCE_PATH
var _questions: Array[Dictionary] = []
var _history: Array[String] = []
var _last_requested_id: String = ""


func _ready() -> void:
	load_questions(_source_path)


func set_source_path(path: String) -> void:
	_source_path = path.strip_edges()
	if _source_path.is_empty():
		_source_path = DEFAULT_SOURCE_PATH
	load_questions(_source_path)


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
	_last_requested_id = ""
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

	var parsed := json.data
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


func get_question(filters: Dictionary = {}) -> Dictionary:
	var candidates := _filter_questions(filters)
	if candidates.is_empty():
		return {}

	candidates.shuffle()
	for candidate in candidates:
		var id := String(candidate.get("id", ""))
		if id.is_empty():
			continue
		if _history.has(id) and _history.size() >= candidates.size():
			continue
		_history.append(id)
		if _history.size() > 32:
			_history.remove_at(0)
		_last_requested_id = id
		var question_copy := _clone_question(candidate)
		question_requested.emit(question_copy)
		return question_copy

	var fallback := _clone_question(candidates[0])
	_history.append(String(fallback.get("id", "")))
	_last_requested_id = String(fallback.get("id", ""))
	question_requested.emit(fallback)
	return fallback


func reset_history() -> void:
	_history.clear()
	_last_requested_id = ""


func _filter_questions(filters: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for question in _questions:
		if not question is Dictionary:
			continue
		var matches := true
		if filters.has("grade"):
			var grade_value := String(filters.get("grade", ""))
			var question_grade := String(question.get("grade", ""))
			if not grade_value.is_empty() and question_grade != grade_value:
				matches = false
		if matches and filters.has("topic"):
			var topic_value := String(filters.get("topic", ""))
			var question_topic := String(question.get("topic", ""))
			if not topic_value.is_empty() and question_topic != topic_value:
				matches = false
		if matches and filters.has("difficulty"):
			var difficulty_value := String(filters.get("difficulty", ""))
			var question_difficulty := String(question.get("difficulty", ""))
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
	if not question.has("id"):
		return {}
	var normalized := Dictionary(question)
	var id_value := normalized.get("id", "")
	if id_value is String:
		normalized["id"] = id_value
	elif id_value is int or id_value is float:
		normalized["id"] = String(id_value)
	else:
		return {}
	if not normalized.has("question") or not normalized.has("choices") or not normalized.has("correct"):
		return {}
	if normalized["choices"] is Array:
		var choices := Array(normalized["choices"])
		if choices.size() < 2:
			return {}
		normalized["choices"] = choices
	else:
		return {}
	return normalized
