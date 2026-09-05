extends SceneTree

const GameStateScript := preload("res://scripts/game_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_state := GameStateScript.new()
	_assert(game_state.has_method("is_valid_existing_student_id"), "GameState exposes existing Student-ID compatibility validation")
	_assert(game_state.has_method("is_valid_new_student_id"), "GameState exposes new Student-ID creation validation")
	_assert(game_state.has_method("sanitize_student_id"), "GameState exposes eight-character Student-ID sanitization")

	if game_state.has_method("is_valid_existing_student_id"):
		_assert(game_state.is_valid_existing_student_id("001234"), "six-digit legacy Student ID is valid for lookup")
		_assert(game_state.is_valid_existing_student_id("00123456"), "eight-digit Student ID is valid for lookup")
		for invalid_id in ["12345", "1234567", "123456789", "12A456", " 001234 "]:
			_assert(not game_state.is_valid_existing_student_id(invalid_id), "invalid existing Student ID is rejected: %s" % invalid_id)

	if game_state.has_method("is_valid_new_student_id"):
		_assert(game_state.is_valid_new_student_id("00123456"), "eight-digit Student ID is valid for creation")
		for invalid_id in ["001234", "1234567", "123456789", "12A45678", " 00123456 "]:
			_assert(not game_state.is_valid_new_student_id(invalid_id), "invalid new Student ID is rejected: %s" % invalid_id)

	if game_state.has_method("sanitize_student_id"):
		_assert(game_state.sanitize_student_id("12A 3456789") == "12345678", "Student sanitizer keeps only the first eight ASCII digits")

	_assert(game_state.is_valid_six_digit_id("654321"), "Parent ID remains exact-six validation")
	_assert(not game_state.is_valid_six_digit_id("65432100"), "Parent ID does not widen with Student ID")
	var valid_registration := {
		"gender": "female",
		"student_id": "001234",
		"parent_id": "654321",
		"student_name": "Legacy Student",
		"grade": "Grade 1",
	}
	_assert(game_state.is_valid_new_game_registration(valid_registration), "New Game accepts an existing six-digit Student lookup")
	valid_registration["student_id"] = "00123456"
	_assert(game_state.is_valid_new_game_registration(valid_registration), "New Game accepts an existing eight-digit Student lookup")
	valid_registration["student_id"] = "0012345"
	_assert(not game_state.is_valid_new_game_registration(valid_registration), "New Game rejects malformed Student ID before a request")
	valid_registration["student_id"] = "00123456"
	valid_registration["parent_id"] = "65432100"
	_assert(not game_state.is_valid_new_game_registration(valid_registration), "New Game keeps Parent ID exact-six")

	var scene_text := FileAccess.get_file_as_string("res://scenes/new_game_scene.tscn")
	var student_node_index := scene_text.find("[node name=\"StudentIdInput\"")
	var parent_node_index := scene_text.find("[node name=\"ParentIdInput\"")
	var student_node_text := scene_text.substr(student_node_index, parent_node_index - student_node_index) if student_node_index >= 0 and parent_node_index > student_node_index else ""
	_assert(student_node_text.contains("max_length = 8"), "New Game Student input has max length 8")
	_assert(not scene_text.substr(parent_node_index).contains("max_length = 8"), "Parent input remains separate from Student eight-digit limit")
	var controller_text := FileAccess.get_file_as_string("res://scenes/texture_rect_2.gd")
	_assert(controller_text.find("if not GameState.is_valid_existing_student_id(student_id_input.text):") < controller_text.find("http.request_get(\"/api/game/profile/check/\""), "New Game validates Student ID before requesting the profile")
	_assert(controller_text.contains("Student ID must be either 6 or 8 digits."), "New Game reports the truthful Student-ID validation error")
	game_state.free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("STUDENT_ID_COMPATIBILITY_TEST: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("STUDENT_ID_COMPATIBILITY_TEST: FAIL")
	quit(1)
