extends SceneTree

const NEW_GAME_SCENE := "res://scenes/new_game_scene.tscn"
const LOADING_SCENE := "res://scenes/loading_screen.tscn"
const PLAYER_HOUSE_SCENE := "res://interiors/player_house.tscn"
const LeaseHttpApi := preload("res://tools/test_http_api_new_game_lease_stub.gd")

var failures: Array[String] = []
var http_api: Node
var remote_sync: Node
var game_state: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	http_api = get_root().get_node_or_null("HttpApi")
	remote_sync = get_root().get_node_or_null("RemoteSync")
	game_state = get_root().get_node_or_null("GameState")
	_assert(http_api != null, "HttpApi autoload is present")
	_assert(remote_sync != null, "the real RemoteSync autoload is present")
	_assert(game_state != null, "GameState autoload is present")
	if http_api == null or remote_sync == null or game_state == null:
		_finish()
		return

	http_api.set_script(LeaseHttpApi)
	await _verify_successful_registration_with_a_real_lease_parser()
	await _verify_failed_lease_stays_on_the_form()
	_finish()


func _verify_successful_registration_with_a_real_lease_parser() -> void:
	var wizard := await _open_name_grade_step()
	if wizard == null:
		return
	var stub := http_api as Node
	stub.set("respond_with_lease", true)
	remote_sync.set("_current_playtime_session_id", 777)
	remote_sync.set("_current_playtime_session_credential", "")

	_set_line_edit_text(wizard.get_node("NameGradeSelect/NameInput") as LineEdit, "Test Student")
	await _press(wizard.get_node("NameGradeSelect/Grade2") as BaseButton)
	var start_button := wizard.get_node("NameGradeSelect/Start") as BaseButton
	start_button.pressed.emit()
	await process_frame
	start_button.pressed.emit()
	await process_frame

	_assert(int(stub.get("start_request_count")) == 1, "Start cannot issue duplicate playtime-start requests while a lease request is pending")
	var start_payload := stub.get("last_start_payload") as Dictionary
	_assert(String(start_payload.get("student_id", "")) == "001234", "Start sends the Student ID as a six-character string")
	_assert(String(start_payload.get("parent_id", "")) == "654321", "Start sends the Parent ID as a six-character string")
	_assert(String(start_payload.get("section", "")) == "", "a nullable canonical Section is represented as an empty client field and is not invented")

	_assert(await _wait_for_scene(LOADING_SCENE, 240), "a valid lease starts the loading transition")
	_assert(await _wait_for_scene(PLAYER_HOUSE_SCENE, 480), "a valid lease reaches Player House")
	_assert(int(remote_sync.get("_current_playtime_session_id")) == 9001, "RemoteSync retains the server-issued session ID")
	_assert(not String(remote_sync.get("_current_playtime_session_credential")).is_empty(), "RemoteSync retains the server-issued lease credential")
	_assert(String(game_state.get("student_id")) == "001234", "GameState finalizes the validated Student ID")
	_assert(String(game_state.get("parent_id")) == "654321", "GameState finalizes the validated Parent ID")


func _verify_failed_lease_stays_on_the_form() -> void:
	remote_sync.set("_current_playtime_session_id", 0)
	remote_sync.set("_current_playtime_session_credential", "")
	var wizard := await _open_name_grade_step()
	if wizard == null:
		return
	var stub := http_api as Node
	stub.set("respond_with_lease", false)
	_set_line_edit_text(wizard.get_node("NameGradeSelect/NameInput") as LineEdit, "Test Student")
	await _press(wizard.get_node("NameGradeSelect/Grade2") as BaseButton)
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	await _wait_seconds(0.25)
	var validation_label := wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel") as Label
	_assert(wizard.get_node("NameGradeSelect").visible, "a failed lease keeps the user on the Name/Grade form")
	_assert(validation_label != null and validation_label.text == "Playtime service is temporarily unavailable.", "a failed lease displays the truthful backend message")


func _open_name_grade_step() -> Node:
	game_state.call("clear_new_game_registration")
	var result := change_scene_to_file(NEW_GAME_SCENE)
	_assert(result == OK, "New Game scene loads")
	if result != OK or not await _wait_for_scene(NEW_GAME_SCENE, 180):
		return null
	var wizard := current_scene.get_node_or_null("TextureRect2")
	_assert(wizard != null, "New Game registration wizard exists")
	if wizard == null:
		return null
	await _press(wizard.get_node("GenderSelect/MaleBtn") as BaseButton)
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_for_transition(wizard)
	_set_line_edit_text(wizard.get_node("StudentParentId/StudentIdInput") as LineEdit, "001234")
	_set_line_edit_text(wizard.get_node("StudentParentId/ParentIdInput") as LineEdit, "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_for_transition(wizard)
	_assert(wizard.get_node("NameGradeSelect").visible, "valid Parent and profile responses reach Name/Grade")
	return wizard


func _wait_for_transition(wizard: Node) -> void:
	var deadline := Time.get_ticks_msec() + 1600
	while Time.get_ticks_msec() < deadline:
		if not bool(wizard.get("_step_transitioning")):
			return
		await create_timer(0.01).timeout
	failures.append("Registration panel transition did not complete")


func _wait_for_scene(expected_path: String, timeout_frames: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(float(timeout_frames) * 1000.0 / 60.0)
	while Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.scene_file_path == expected_path:
			return true
		await create_timer(0.01).timeout
	failures.append("Expected scene was not reached: %s" % expected_path)
	return false


func _press(button: BaseButton) -> void:
	if button == null:
		failures.append("Attempted to press a missing New Game control")
		return
	button.pressed.emit()
	await process_frame
	await process_frame


func _set_line_edit_text(input: LineEdit, text_value: String) -> void:
	if input == null:
		failures.append("Attempted to set a missing New Game text field")
		return
	input.text = text_value
	input.text_changed.emit(text_value)


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("NEW_GAME_RELEASE_LEASE_FLOW_TEST: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NEW_GAME_RELEASE_LEASE_FLOW_TEST: FAIL")
	quit(1)
