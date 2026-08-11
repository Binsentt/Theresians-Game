extends SceneTree

const MAIN_MENU := "res://scenes/main_menu.tscn"
const LEADERBOARD := "res://leaderboard_scene.tscn"
const NEW_GAME := "res://scenes/new_game_scene.tscn"
const LOADING := "res://scenes/loading_screen.tscn"
const PLAYER_HOUSE := "res://interiors/player_house.tscn"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _load_scene(MAIN_MENU)
	await _press(current_scene.get_node("LeaderboardButton") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(LEADERBOARD)
	await _press(current_scene.get_node("TextureRect2/BackgroundMenu/Back-Button") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(MAIN_MENU)

	await _press(current_scene.get_node("VBoxContainer/NewGameBtn") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(NEW_GAME)
	_assert(current_scene.get_node("TextureRect2/GenderSelect").visible, "New Game opens Gender")
	_assert(not current_scene.get_node("TextureRect2/StudentParentId").visible, "New Game hides IDs until Continue")
	_assert(not current_scene.get_node("TextureRect2/NameGradeSelect").visible, "New Game hides Name/Grade until IDs")
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(MAIN_MENU)
	_assert(GameState.get_new_game_registration().is_empty(), "Gender Back cancels temporary registration")

	await _run_back_preservation_case()
	await _run_gender_case("male", "Grade 1")
	await _run_gender_case("female", "Grade 6")

	if failures.is_empty():
		print("NEW_GAME_ROUTE_TEST PASSED")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NEW_GAME_ROUTE_TEST FAILED")
	quit(1)

func _run_back_preservation_case() -> void:
	await _load_scene(MAIN_MENU)
	await _press(current_scene.get_node("VBoxContainer/NewGameBtn") as BaseButton)
	await _wait_seconds(0.5)
	var wizard := current_scene.get_node("TextureRect2")
	_assert_panel_visibility(wizard, true, false, false, "initial New Game")
	await _press(wizard.get_node("GenderSelect/MaleBtn") as BaseButton)
	_assert(wizard.get_node("GenderSelect").visible, "gender selection does not auto-advance")
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.3)
	_assert(wizard.get_node("StudentParentId").visible, "Gender Continue opens IDs")
	_assert_panel_visibility(wizard, false, true, false, "Gender Continue")
	wizard.get_node("StudentParentId/StudentIdInput").text = "000123"
	wizard.get_node("StudentParentId/ParentIdInput").text = "654321"
	await process_frame
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.3)
	_assert(wizard.get_node("GenderSelect").visible, "ID Back returns to Gender")
	_assert_panel_visibility(wizard, true, false, false, "ID Back")
	_assert(GameState.get_new_game_registration().get("gender") == "male", "ID Back preserves gender")
	_assert(GameState.get_new_game_registration().get("student_id") == "000123", "ID Back preserves Student ID")
	_assert(GameState.get_new_game_registration().get("parent_id") == "654321", "ID Back preserves Parent ID")
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.3)
	_assert_panel_visibility(wizard, false, true, false, "returning to IDs")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.3)
	_assert_panel_visibility(wizard, false, false, true, "valid IDs Next")
	wizard.get_node("NameGradeSelect/NameInput").text = " Student "
	await process_frame
	await _press(wizard.get_node("NameGradeSelect/Grade2") as BaseButton)
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.3)
	_assert(wizard.get_node("StudentParentId").visible, "Name/Grade Back returns to IDs")
	_assert_panel_visibility(wizard, false, true, false, "Name/Grade Back")
	_assert(GameState.get_new_game_registration().get("student_id") == "000123", "Name/Grade Back preserves Student ID")
	_assert(GameState.get_new_game_registration().get("parent_id") == "654321", "Name/Grade Back preserves Parent ID")
	_assert(GameState.get_new_game_registration().get("student_name") == " Student ", "Name/Grade Back preserves name")
	_assert(GameState.get_new_game_registration().get("grade") == "Grade 2", "Name/Grade Back preserves grade")
	_assert(GameState.get_new_game_registration().get("gender") == "male", "Name/Grade Back preserves gender")
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.3)
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(MAIN_MENU)
	_assert(GameState.get_new_game_registration().is_empty(), "cancelled registration is cleared")

func _run_gender_case(gender_value: String, final_grade: String) -> void:
	await _load_scene(MAIN_MENU)
	await _press(current_scene.get_node("VBoxContainer/NewGameBtn") as BaseButton)
	await _wait_seconds(0.5)
	var wizard := current_scene.get_node("TextureRect2")
	_assert_panel_visibility(wizard, true, false, false, "initial New Game")
	var gender_button_path := "GenderSelect/MaleBtn" if gender_value == "male" else "GenderSelect/FemaleBtn"
	await _press(wizard.get_node(gender_button_path) as BaseButton)
	_assert(wizard.get_node("GenderSelect").visible, "gender selection waits for Continue")
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.3)
	_assert_panel_visibility(wizard, false, true, false, "Gender Continue")
	var pasted_student_id := wizard.get_node("StudentParentId/StudentIdInput") as LineEdit
	pasted_student_id.text = "12A 3-4567"
	pasted_student_id.text_changed.emit(pasted_student_id.text)
	await process_frame
	_assert(pasted_student_id.text == "123456", "mixed pasted Student ID characters are sanitized")
	wizard.get_node("StudentParentId/ParentIdInput").text = "12345"
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	_assert(wizard.get_node("ValidationPanel").visible, "invalid ID shows validation")
	_assert(String(wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel").text).contains("Student ID"), "invalid Student ID is named first")
	wizard.get_node("StudentParentId/StudentIdInput").text = "000123"
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	_assert(wizard.get_node("ValidationPanel").visible, "invalid Parent ID shows validation")
	_assert(String(wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel").text).contains("Parent ID"), "invalid Parent ID is named second")
	wizard.get_node("StudentParentId/ParentIdInput").text = "654321"
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.3)
	_assert_panel_visibility(wizard, false, false, true, "valid IDs Next")
	wizard.get_node("NameGradeSelect/NameInput").text = "   "
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	_assert(wizard.get_node("ValidationPanel").visible, "empty name is rejected")
	_assert(String(wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel").text).contains("name"), "empty name is named")
	wizard.get_node("NameGradeSelect/NameInput").text = " Student "
	await process_frame
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	_assert(wizard.get_node("ValidationPanel").visible, "missing grade is rejected")
	_assert(String(wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel").text).contains("grade"), "missing grade is named")
	for grade_number in range(1, 7):
		await _press(wizard.get_node("NameGradeSelect/Grade%d" % grade_number) as BaseButton)
		_assert(GameState.get_new_game_registration().get("grade") == "Grade %d" % grade_number, "grade %d stores its exact value" % grade_number)
	var final_grade_number := int(final_grade.trim_prefix("Grade "))
	await _press(wizard.get_node("NameGradeSelect/Grade%d" % final_grade_number) as BaseButton)
	_assert(GameState.get_new_game_registration().get("grade") == final_grade, "requested final grade is selected")
	GameState.current_scene_path = "res://scenes/city_of_knowledge.tscn"
	GameState.current_task_index = 2
	GameState.battle_active = true
	GameState.current_battle_enemy_path = NodePath("stale_enemy")
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	await _wait_seconds(0.2)
	_assert_scene(LOADING)
	await _wait_seconds(1.0)
	_assert_scene(PLAYER_HOUSE)
	_assert(GameState.gender == gender_value, "%s gender is finalized" % gender_value)
	_assert(GameState.get_player_scene_path().ends_with("player_%s.tscn" % gender_value), "%s player scene is selected" % gender_value)
	_assert(GameState.student_id == "000123", "%s Student ID is finalized" % gender_value)
	_assert(GameState.parent_id == "654321", "%s Parent ID is finalized" % gender_value)
	_assert(GameState.player_name == "Student", "%s name is finalized" % gender_value)
	_assert(GameState.grade_level == final_grade, "%s grade is finalized" % gender_value)
	_assert(GameState.current_scene_path == PLAYER_HOUSE, "%s stale scene is reset" % gender_value)
	_assert(GameState.current_task_index == 0, "%s task state resets" % gender_value)
	_assert(not GameState.battle_active, "%s battle state resets" % gender_value)
	_assert(GameState.current_battle_enemy_path.is_empty(), "%s battle enemy state resets" % gender_value)

func _load_scene(path: String) -> void:
	var result := change_scene_to_file(path)
	_assert(result == OK, "scene change accepted: %s" % path)
	await process_frame
	await process_frame

func _assert_scene(path: String) -> void:
	var current := current_scene.scene_file_path
	_assert(current == path, "expected %s, got %s" % [path, current])

func _press(button: BaseButton) -> void:
	button.pressed.emit()
	await process_frame

func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func _assert_panel_visibility(wizard: Node, gender_visible: bool, ids_visible: bool, name_grade_visible: bool, context: String) -> void:
	_assert(wizard.get_node("GenderSelect").visible == gender_visible, "%s: Gender panel visibility" % context)
	_assert(wizard.get_node("StudentParentId").visible == ids_visible, "%s: IDs panel visibility" % context)
	_assert(wizard.get_node("NameGradeSelect").visible == name_grade_visible, "%s: Name/Grade panel visibility" % context)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
