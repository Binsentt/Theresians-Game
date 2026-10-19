extends SceneTree

const GameStateScript := preload("res://scripts/game_state.gd")

var failures: Array[String] = []
var save_created := false
var game_state: Node

func _initialize() -> void:
	game_state = GameStateScript.new()
	get_root().add_child(game_state)
	game_state.save_created.connect(_on_save_created)
	call_deferred("_run")

func _run() -> void:
	for value in ["123456", "000123"]:
		_assert(game_state.is_valid_existing_student_id(value), "Student lookup accepts legacy six ASCII digits: %s" % value)
		_assert(game_state.is_valid_six_digit_id(value), "Parent ID accepts exact six ASCII digits: %s" % value)
	for value in ["12345678", "00001234"]:
		_assert(game_state.is_valid_existing_student_id(value), "Student lookup accepts current eight ASCII digits: %s" % value)
		_assert(game_state.is_valid_new_student_id(value), "New Student ID accepts exact eight ASCII digits: %s" % value)
	for value in ["12345", "1234567", "123456789", "12A456", "12-456", "123 456", "123.45", "+12345", "１２３４５６"]:
		_assert(not game_state.is_valid_existing_student_id(value), "Student lookup rejects invalid ID: %s" % value)
		_assert(not game_state.is_valid_new_student_id(value), "New Student ID rejects invalid ID: %s" % value)
	_assert(not game_state.is_valid_six_digit_id("12345678"), "Parent ID remains exactly six digits")
	_assert(game_state.sanitize_student_id("12A 3-456789") == "12345678", "Student pasted text keeps only the first eight digits")
	_assert(game_state.sanitize_six_digit_id("12A 3-4567") == "123456", "Parent pasted text keeps only the first six digits")

	game_state.begin_new_game_registration()
	game_state.update_new_game_registration({
		"gender": "female",
		"student_id": "91348276"
	})
	_assert(not game_state.finalize_new_game_registration(), "incomplete registration does not finalize")
	_assert(not save_created, "incomplete registration does not emit a save")

	game_state.update_new_game_registration({
		"gender": "female",
		"student_id": "91348276",
		"parent_id": "654321",
		"student_name": "  Ana Maria  ",
		"grade": "Grade 6"
	})
	var registration: Dictionary = game_state.get_new_game_registration()
	var expected_registration_keys: Array = ["gender", "student_id", "parent_id", "student_name", "grade", "section", "learning_cycle"]
	var actual_registration_keys: Array = registration.keys()
	expected_registration_keys.sort()
	actual_registration_keys.sort()
	_assert(actual_registration_keys == expected_registration_keys, "temporary registration has the current canonical registration keys")
	_assert(registration.get("gender") == "female", "temporary gender is preserved")
	_assert(registration.get("student_id") == "91348276", "temporary current Student ID is preserved exactly")
	_assert(registration.get("parent_id") == "654321", "temporary Parent ID is preserved")
	_assert(registration.get("student_name") == "  Ana Maria  ", "temporary name is preserved before final trim")
	_assert(registration.get("grade") == "Grade 6", "temporary grade is preserved")

	game_state.current_scene_path = "res://scenes/city_of_knowledge.tscn"
	game_state.player_position = Vector2(999, 999)
	game_state.current_task_index = 2
	game_state.battle_active = true
	game_state.current_battle_enemy_path = NodePath("stale_enemy")
	_assert(game_state.finalize_new_game_registration(), "valid registration finalizes")
	_assert(game_state.gender == "female", "final gender is committed")
	_assert(game_state.student_id == "91348276", "final Student ID is committed as a string")
	_assert(game_state.parent_id == "654321", "final Parent ID is committed as a string")
	_assert(game_state.player_name == "Ana Maria", "final name is trimmed")
	_assert(game_state.grade_level == "Grade 6", "exact grade value is committed")
	_assert(game_state.current_scene_path == game_state.START_SCENE_PATH, "new game starts at the canonical scene")
	_assert(game_state.player_position == game_state.get_scene_fallback_spawn(game_state.START_SCENE_PATH), "new game resets player position to the canonical spawn")
	_assert(game_state.current_task_index == 0, "new game resets task state")
	_assert(not game_state.battle_active, "new game clears stale battle state")
	_assert(game_state.current_battle_enemy_path.is_empty(), "new game clears stale battle enemy path")
	_assert(game_state.get_new_game_registration().is_empty(), "temporary registration clears after finalization")
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
