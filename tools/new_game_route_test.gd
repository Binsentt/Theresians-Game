extends SceneTree

const MAIN_MENU := "res://scenes/main_menu.tscn"
const NEW_GAME := "res://scenes/new_game_scene.tscn"
const LOADING := "res://scenes/loading_screen.tscn"
const PLAYER_HOUSE := "res://interiors/player_house.tscn"

var failures: Array[String] = []

func _initialize() -> void:
	var root := get_root()
	if root != null:
		var http_api := root.get_node_or_null("HttpApi")
		var http_stub := load("res://tools/test_http_api_stub.gd")
		if http_api != null and (http_api.get_script() == null or http_api.get_script().resource_path != http_stub.resource_path):
			http_api.set_script(http_stub)
		var remote_sync := root.get_node_or_null("RemoteSync")
		var remote_stub := load("res://tools/test_remote_sync_stub.gd")
		if remote_sync != null and (remote_sync.get_script() == null or remote_sync.get_script().resource_path != remote_stub.resource_path):
			remote_sync.set_script(remote_stub)
	call_deferred("_run")

func _run() -> void:
	if not await _load_scene(MAIN_MENU):
		_report_failure_and_quit("MAIN_MENU")
		return
	print("MAIN_MENU: PASS")

	var menu_btn := current_scene.get_node("VBoxContainer/NewGameBtn") as Button
	if menu_btn == null:
		failures.append("MainMenu NewGameBtn missing from actual tree")
		_report_failure_and_quit("NEW_GAME_NAVIGATION")
		return

	await _press(menu_btn)
	if not await wait_for_scene(NEW_GAME, 180):
		failures.append("Navigation did not reach new_game_scene.tscn")
		_report_failure_and_quit("NEW_GAME_NAVIGATION")
		return
	print("NEW_GAME_NAVIGATION: PASS")

	var wizard := current_scene.get_node("TextureRect2")
	_assert(wizard != null, "TextureRect2 exists in actual new_game scene")
	_assert(wizard.get_node("GenderSelect").visible, "New Game opens on Gender")
	_assert(not wizard.get_node("StudentParentId").visible, "Gender step hides IDs until Continue")
	_assert(not wizard.get_node("NameGradeSelect").visible, "Gender step hides Name/Grade until IDs")
	print("GENDER_SELECTION: PASS")

	await _press(wizard.get_node("GenderSelect/MaleBtn") as BaseButton)
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.25)
	_assert(not wizard.get_node("GenderSelect").visible, "Gender panel hides after continue")
	_assert(wizard.get_node("StudentParentId").visible, "IDs panel is visible after continue")
	print("GENDER_SELECTION_MALE: PASS")
	print("GENDER_TO_IDS: PASS")

	var student_input: LineEdit = wizard.get_node("StudentParentId/StudentIdInput")
	var parent_input: LineEdit = wizard.get_node("StudentParentId/ParentIdInput")
	_set_line_edit_text(student_input, "001234")
	_set_line_edit_text(parent_input, "654321")
	await _wait_seconds(0.25)
	_assert(student_input.text == "001234", "Student ID preserves leading zeros")
	_assert(parent_input.text == "654321", "Parent ID accepts valid placeholder")
	print("STUDENT_ID_INPUT: PASS")
	print("LEADING_ZERO: PASS")
	print("PARENT_ID_INPUT: PASS")

	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.5)
	_assert(wizard.get_node("NameGradeSelect").visible, "IDs next reveals Name/Grade step")
	print("IDS_TO_NAME_GRADE: PASS")

	var name_input: LineEdit = wizard.get_node("NameGradeSelect/NameInput")
	_set_line_edit_text(name_input, "Test Student")
	await _wait_seconds(0.25)
	await _press(wizard.get_node("NameGradeSelect/Grade2") as BaseButton)
	_assert(get_game_state().get_new_game_registration().get("grade") == "Grade 2", "Grade selection is stored")
	print("NAME_ENTRY: PASS")
	print("GRADE_SELECTION: PASS")

	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	if not await wait_for_scene(LOADING, 180):
		failures.append("New Game did not reach loading scene")
		_report_failure_and_quit("START_GAME")
		return
	print("START_GAME: PASS")
	if not await wait_for_scene(PLAYER_HOUSE, 300):
		failures.append("New Game did not reach player house")
		_report_failure_and_quit("PLAYER_HOUSE")
		return
	print("PLAYER_HOUSE: PASS")
	print("TUTORIAL_ROUTE: PASS")
	print("MALE_ROUTE: PASS")

	await _load_scene(MAIN_MENU)
	print("MAIN_MENU: PASS")
	var female_btn := current_scene.get_node("VBoxContainer/NewGameBtn") as Button
	await _press(female_btn)
	if not await wait_for_scene(NEW_GAME, 180):
		failures.append("Female route did not reach new_game scene")
		_report_failure_and_quit("FEMALE_ROUTE")
		return
	wizard = current_scene.get_node("TextureRect2")
	await _press(wizard.get_node("GenderSelect/FemaleBtn") as BaseButton)
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.5)
	student_input = wizard.get_node("StudentParentId/StudentIdInput")
	parent_input = wizard.get_node("StudentParentId/ParentIdInput")
	_set_line_edit_text(student_input, "001234")
	_set_line_edit_text(parent_input, "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.5)
	name_input = wizard.get_node("NameGradeSelect/NameInput")
	_set_line_edit_text(name_input, "Test Student")
	await _press(wizard.get_node("NameGradeSelect/Grade6") as BaseButton)
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	if not await wait_for_scene(LOADING, 180):
		failures.append("Female route did not reach loading scene")
		_report_failure_and_quit("FEMALE_ROUTE")
		return
	if not await wait_for_scene(PLAYER_HOUSE, 300):
		failures.append("Female route did not reach player house")
		_report_failure_and_quit("FEMALE_ROUTE")
		return
	print("FEMALE_ROUTE: PASS")

	await _load_scene(MAIN_MENU)
	await _press(current_scene.get_node("VBoxContainer/NewGameBtn") as BaseButton)
	if not await wait_for_scene(NEW_GAME, 180):
		failures.append("Back-navigation route did not reach new_game scene")
		_report_failure_and_quit("BACK_NAVIGATION")
		return
	wizard = current_scene.get_node("TextureRect2")
	await _press(wizard.get_node("GenderSelect/MaleBtn") as BaseButton)
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.5)
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.5)
	var back_btn := current_scene.get_node("Button") as Button
	await _press(back_btn)
	await _wait_seconds(0.5)
	_assert(wizard.get_node("GenderSelect").visible, "Back from IDs returns to Gender")
	print("BACK_NAVIGATION: PASS")

	if failures.is_empty():
		print("NEW_GAME_ROUTE_TEST: PASS")
		quit(0)
		return
	_report_failure_and_quit("NEW_GAME_ROUTE_TEST")

func _report_failure_and_quit(label: String) -> void:
	for failure in failures:
		push_error(failure)
	print(label + ": FAIL")
	print("NEW_GAME_ROUTE_TEST: FAIL")
	quit(1)

func _load_scene(path: String) -> bool:
	var result := change_scene_to_file(path)
	if result != OK:
		failures.append("scene change accepted: %s" % path)
		return false
	return await wait_for_scene(path, 180)

func wait_for_scene(expected_path: String, timeout_frames: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(float(timeout_frames) * 1000.0 / 60.0)
	while Time.get_ticks_msec() < deadline:
		var current := current_scene
		if current != null and current.scene_file_path == expected_path:
			return true
		await create_timer(0.01).timeout
	var current := current_scene
	if current == null:
		print("wait_for_scene timeout: current scene is null; expected %s" % expected_path)
	else:
		print("wait_for_scene timeout: expected %s, got %s" % [expected_path, current.scene_file_path])
	return false

func _press(button: BaseButton) -> void:
	if button == null:
		failures.append("Attempted to press a null button")
		return
	button.pressed.emit()
	await process_frame
	await process_frame

func _set_line_edit_text(input: LineEdit, text_value: String) -> void:
	if input == null:
		failures.append("Attempted to set text on a null LineEdit")
		return
	input.text = text_value
	input.text_changed.emit(text_value)

func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func get_game_state() -> Node:
	var root := get_root()
	if root == null:
		return null
	return root.get_node_or_null("GameState")
