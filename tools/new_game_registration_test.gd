extends SceneTree

var failures: Array[String] = []
var save_created := false

func _initialize() -> void:
	GameState.save_created.connect(_on_save_created)
	call_deferred("_run")

func _run() -> void:
	var valid_id_values := ["123456", "000123"]
	var invalid_id_values := ["12345", "1234567", "12A456", "12-456", "123 456", "123.45", "+12345", "１２３４５６"]
	for field_label in ["Student ID", "Parent ID"]:
		for value in valid_id_values:
			_assert(GameState.is_valid_six_digit_id(value), "%s accepts exact six ASCII digits: %s" % [field_label, value])
		for value in invalid_id_values:
			_assert(not GameState.is_valid_six_digit_id(value), "%s rejects invalid ID: %s" % [field_label, value])
	_assert(GameState.sanitize_six_digit_id("12A 3-4567") == "123456", "pasted text keeps only the first six digits")

	GameState.begin_new_game_registration()
	GameState.update_new_game_registration({
		"gender": "female",
		"student_id": "000123"
	})
	_assert(not GameState.finalize_new_game_registration(), "incomplete registration does not finalize")
	_assert(not save_created, "incomplete registration does not emit a save")

	GameState.update_new_game_registration({
		"gender": "female",
		"student_id": "000123",
		"parent_id": "654321",
		"student_name": "  Ana Maria  ",
		"grade": "Grade 6"
	})
	var registration := GameState.get_new_game_registration()
	var expected_registration_keys := ["gender", "student_id", "parent_id", "student_name", "grade"]
	var actual_registration_keys := registration.keys()
	expected_registration_keys.sort()
	actual_registration_keys.sort()
	_assert(actual_registration_keys == expected_registration_keys, "temporary registration has exactly the five expected keys")
	_assert(registration.get("gender") == "female", "temporary gender is preserved")
	_assert(registration.get("student_id") == "000123", "temporary student ID preserves leading zeroes")
	_assert(registration.get("parent_id") == "654321", "temporary Parent ID is preserved")
	_assert(registration.get("student_name") == "  Ana Maria  ", "temporary name is preserved before final trim")
	_assert(registration.get("grade") == "Grade 6", "temporary grade is preserved")

	GameState.current_scene_path = "res://scenes/city_of_knowledge.tscn"
	GameState.player_position = Vector2(999, 999)
	GameState.current_task_index = 2
	GameState.battle_active = true
	GameState.current_battle_enemy_path = NodePath("stale_enemy")
	_assert(GameState.finalize_new_game_registration(), "valid registration finalizes")
	_assert(GameState.gender == "female", "final gender is committed")
	_assert(GameState.student_id == "000123", "final Student ID is committed as a string")
	_assert(GameState.parent_id == "654321", "final Parent ID is committed as a string")
	_assert(GameState.player_name == "Ana Maria", "final name is trimmed")
	_assert(GameState.grade_level == "Grade 6", "exact grade value is committed")
	_assert(GameState.current_scene_path == GameState.START_SCENE_PATH, "new game starts at the canonical scene")
	_assert(GameState.player_position == GameState.get_scene_fallback_spawn(GameState.START_SCENE_PATH), "new game resets player position to the canonical spawn")
	_assert(GameState.current_task_index == 0, "new game resets task state")
	_assert(not GameState.battle_active, "new game clears stale battle state")
	_assert(GameState.current_battle_enemy_path.is_empty(), "new game clears stale battle enemy path")
	_assert(GameState.get_new_game_registration().is_empty(), "temporary registration clears after finalization")
	_assert(not save_created, "finalization itself does not create a save")

	if failures.is_empty():
		print("NEW_GAME_REGISTRATION_TEST PASSED")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("NEW_GAME_REGISTRATION_TEST FAILED")
	quit(1)

func _on_save_created(_save_data: Dictionary) -> void:
	save_created = true

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
