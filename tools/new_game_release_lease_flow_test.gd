extends SceneTree

const NEW_GAME_SCENE := "res://scenes/new_game_scene.tscn"
const LOADING_SCENE := "res://scenes/loading_screen.tscn"
const PLAYER_HOUSE_SCENE := "res://interiors/player_house.tscn"
const LeaseHttpApi := preload("res://tools/test_http_api_new_game_lease_stub.gd")

var failures: Array[String] = []
var http_api: Node
var remote_sync: Node
var game_state: Node
var _terms_acceptance_path := ""


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
	_terms_acceptance_path = "user://qa_test_artifacts/terms_startup_flow_test_new_game_lease_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var terms_directory := ProjectSettings.globalize_path("user://qa_test_artifacts")
	var terms_directory_ready := DirAccess.make_dir_recursive_absolute(terms_directory) == OK
	_assert(terms_directory_ready, "The isolated Terms QA directory is available")
	if not terms_directory_ready:
		_finish()
		return
	var terms_path_selected := game_state.has_method("set_terms_app_acceptance_path_for_qa") \
			and bool(game_state.call("set_terms_app_acceptance_path_for_qa", _terms_acceptance_path))
	_assert(terms_path_selected, "The playtime fixture selects an isolated Terms acceptance file")
	var terms_accepted := terms_path_selected and bool(game_state.call("record_terms_app_acceptance"))
	_assert(terms_accepted and bool(game_state.call("has_current_terms_app_acceptance")), "The playtime fixture accepts Terms without touching the normal user profile")
	if not terms_accepted:
		_finish()
		return

	http_api.set_script(LeaseHttpApi)
	# Confirm the autoload is an in-memory stub before permitting the test-only
	# RemoteSync override; this fixture cannot reach any external API.
	var http_stub_loaded: bool = http_api.get_script() == LeaseHttpApi
	_assert(http_stub_loaded, "the playtime fixture installs its in-memory HTTP stub")
	if not http_stub_loaded:
		_finish()
		return
	# Load this override only after autoload initialization. Preloading the real
	# RemoteSync parent at script parse time cannot resolve the GameState autoload.
	var lease_remote_sync_script: Script = load("res://tools/test_remote_sync_new_game_lease.gd") as Script
	_assert(lease_remote_sync_script != null, "the isolated RemoteSync override loads after autoload initialization")
	if lease_remote_sync_script == null:
		_finish()
		return
	remote_sync.set_script(lease_remote_sync_script)
	var lease_method_available: bool = remote_sync.has_method("request_playtime_session")
	_assert(lease_method_available, "the isolated RemoteSync override preserves the playtime request method")
	if not lease_method_available:
		_finish()
		return
	await _verify_successful_registration_with_a_real_lease_parser()
	await _verify_failed_lease_stays_on_the_form()
	_finish()


func _verify_successful_registration_with_a_real_lease_parser() -> void:
	var wizard := await _open_name_grade_step()
	if wizard == null:
		return
	var stub := http_api as Node
	stub.set("respond_with_lease", true)
	# This is a clean new-registration flow. A session ID without its
	# server-issued credential is intentionally invalid and must not be used.
	remote_sync.set("_current_playtime_session_id", 0)
	remote_sync.set("_current_playtime_session_credential", "")

	var name_input := wizard.get_node("NameGradeSelect/NameInput") as LineEdit
	_assert(name_input.text == "Ava Santos", "a validated linked profile pre-fills the canonical student name")
	_assert(not name_input.editable, "a validated canonical student name cannot be edited by the game client")
	_assert((wizard.get_node("NameGradeSelect/Grade3") as BaseButton).disabled, "a validated canonical Grade cannot be changed by the game client")
	_assert(String(game_state.call("get_new_game_registration").get("grade", "")) == "Grade 3", "GameState stores the canonical Grade before a lease can start")
	_assert(String(game_state.call("get_new_game_registration").get("section", "")) == "", "a null canonical Section stays empty instead of being fabricated")
	_set_line_edit_text(name_input, "Client Override")
	await _press(wizard.get_node("NameGradeSelect/Grade2") as BaseButton)
	_assert(name_input.text == "Ava Santos", "the client cannot replace the canonical student name after validation")
	_assert(String(game_state.call("get_new_game_registration").get("grade", "")) == "Grade 3", "the client cannot replace the canonical Grade after validation")
	var start_button := wizard.get_node("NameGradeSelect/Start") as BaseButton
	start_button.pressed.emit()
	await process_frame
	start_button.pressed.emit()
	await process_frame

	_assert(int(stub.get("start_request_count")) == 1, "Start cannot issue duplicate playtime-start requests while a lease request is pending")
	var start_payload := stub.get("last_start_payload") as Dictionary
	_assert(String(start_payload.get("student_id", "")) == "00123456", "Start sends the Student ID as an eight-character string")
	_assert(String(start_payload.get("parent_id", "")) == "654321", "Start sends the Parent ID as a six-character string")
	_assert(String(start_payload.get("student_name", "")) == "Ava Santos", "Start sends the canonical student name rather than a player-entered replacement")
	_assert(String(start_payload.get("grade_level", "")) == "Grade 3", "Start sends the canonical Grade rather than a player-entered replacement")
	_assert(String(start_payload.get("section", "")) == "", "a nullable canonical Section is represented as an empty client field and is not invented")

	_assert(await _wait_for_scene(LOADING_SCENE, 240), "a valid lease starts the loading transition")
	_assert(await _wait_for_scene(PLAYER_HOUSE_SCENE, 480), "a valid lease reaches Player House")
	_assert(int(remote_sync.get("_current_playtime_session_id")) == 9001, "RemoteSync retains the server-issued session ID")
	_assert(not String(remote_sync.get("_current_playtime_session_credential")).is_empty(), "RemoteSync retains the server-issued lease credential")
	_assert(String(game_state.get("student_id")) == "00123456", "GameState finalizes the validated Student ID")
	_assert(String(game_state.get("parent_id")) == "654321", "GameState finalizes the validated Parent ID")
	_assert(int(game_state.get("learning_cycle_version")) == 2, "New Game retains the newer playtime-start learning-cycle version instead of the earlier profile-check version")
	_assert(String(game_state.get("learning_cycle_started_at")) == "2030-01-01T00:00:00.000Z", "New Game retains the playtime-start learning-cycle boundary through finalization")


func _verify_failed_lease_stays_on_the_form() -> void:
	remote_sync.set("_current_playtime_session_id", 0)
	remote_sync.set("_current_playtime_session_credential", "")
	var wizard := await _open_name_grade_step()
	if wizard == null:
		return
	var stub := http_api as Node
	stub.set("respond_with_lease", false)
	_assert(not (wizard.get_node("NameGradeSelect/NameInput") as LineEdit).editable, "a failed lease does not unlock canonical identity fields")
	_assert((wizard.get_node("NameGradeSelect/Grade3") as BaseButton).disabled, "a failed lease does not unlock canonical Grade selection")
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
	_set_line_edit_text(wizard.get_node("StudentParentId/StudentIdInput") as LineEdit, "00123456")
	_set_line_edit_text(wizard.get_node("StudentParentId/ParentIdInput") as LineEdit, "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_for_transition(wizard)
	_assert(wizard.get_node("NameGradeSelect").visible, "valid Parent and canonical-profile responses reach the existing Start confirmation")
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
	if game_state != null and game_state.has_method("reset_terms_app_acceptance_path_for_qa"):
		game_state.call("reset_terms_app_acceptance_path_for_qa")
	if not _terms_acceptance_path.is_empty() and FileAccess.file_exists(_terms_acceptance_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_terms_acceptance_path))
	if failures.is_empty():
		print("NEW_GAME_RELEASE_LEASE_FLOW_TEST: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NEW_GAME_RELEASE_LEASE_FLOW_TEST: FAIL")
	quit(1)
