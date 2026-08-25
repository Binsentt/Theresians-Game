extends SceneTree

const NEW_GAME_SCENE := "res://scenes/new_game_scene.tscn"
const FailureHttpApi := preload("res://tools/test_http_api_registration_failure_stub.gd")
const SlowHttpApi := preload("res://tools/test_http_api_slow_registration_stub.gd")
const MissingCanonicalProfileHttpApi := preload("res://tools/test_http_api_missing_canonical_profile_stub.gd")
const MultiChildHttpApi := preload("res://tools/test_http_api_multi_child_registration_stub.gd")

var failures: Array[String] = []
var http_api: Node
var game_state: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	http_api = get_root().get_node_or_null("HttpApi")
	game_state = get_root().get_node_or_null("GameState")
	_assert(http_api != null, "HttpApi autoload is available for the registration flow")
	_assert(game_state != null, "GameState autoload is available for the registration flow")
	if http_api == null or game_state == null:
		_finish()
		return

	await _reject_unverified_ids()
	await _reject_a_profile_without_canonical_identity()
	await _show_loading_while_online_validation_is_pending()
	await _validate_multiple_linked_children_with_one_parent()
	_finish()


func _reject_unverified_ids() -> void:
	http_api.set_script(FailureHttpApi)
	var wizard := await _open_ids_step()
	if wizard == null:
		return

	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.45)
	_assert(wizard.get_node("StudentParentId").visible, "failed Parent validation keeps the registration flow on the IDs step")
	_assert(not wizard.get_node("NameGradeSelect").visible, "failed Parent validation never advances to Name/Grade in a shipped build")
	var validation_label := wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel") as Label
	_assert(validation_label != null and validation_label.text == "Registration service is unavailable.", "failed Parent validation displays the server error instead of an offline-test bypass")


func _reject_a_profile_without_canonical_identity() -> void:
	http_api.set_script(MissingCanonicalProfileHttpApi)
	var wizard := await _open_ids_step()
	if wizard == null:
		return

	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.10)
	_assert(wizard.get_node("StudentParentId").visible, "a profile response without a canonical linked Student keeps the registration flow on the IDs step")
	_assert(not wizard.get_node("NameGradeSelect").visible, "a profile response without canonical identity never permits manual name or Grade entry")
	var validation_label := wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel") as Label
	_assert(validation_label != null and validation_label.text == "Unable to verify the linked Student profile. Please try again.", "missing canonical identity displays a safe validation error")


func _show_loading_while_online_validation_is_pending() -> void:
	http_api.set_script(SlowHttpApi)
	var wizard := await _open_ids_step()
	if wizard == null:
		return

	wizard.get_node("StudentParentId/NextBtn").pressed.emit()
	await process_frame
	var validation_label := wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel") as Label
	_assert(validation_label != null and validation_label.text == "Validating Parent and Student ID…", "pending online validation has a visible loading message")
	_assert(wizard.get_node("StudentParentId").visible and not wizard.get_node("NameGradeSelect").visible, "the IDs step remains visible until both online checks finish")

	await _wait_seconds(0.45)
	_assert(wizard.get_node("NameGradeSelect").visible, "a slow successful canonical profile validation advances immediately after the one authoritative request")
	_assert(not (wizard.get_node("NameGradeSelect/NameInput") as LineEdit).editable, "a slow successful canonical profile locks the name field")
	_assert((wizard.get_node("NameGradeSelect/Grade3") as BaseButton).disabled, "a slow successful canonical profile locks Grade selection")
	_assert(int(http_api.get("get_request_count")) == 1, "registration validation makes one profile request")
	_assert(int(http_api.get("post_request_count")) == 0, "registration validation does not make a duplicate Parent-validation request")


func _validate_multiple_linked_children_with_one_parent() -> void:
	http_api.set_script(MultiChildHttpApi)
	for student_id in ["000001", "000002"]:
		var wizard := await _open_ids_step()
		if wizard == null:
			return
		_set_line_edit_text(wizard.get_node("StudentParentId/StudentIdInput") as LineEdit, student_id)
		await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
		await _wait_for_transition(wizard)
		_assert(wizard.get_node("NameGradeSelect").visible, "each linked child validates for the same Parent account")

	var unlinked_wizard := await _open_ids_step()
	if unlinked_wizard != null:
		_set_line_edit_text(unlinked_wizard.get_node("StudentParentId/StudentIdInput") as LineEdit, "000003")
		await _press(unlinked_wizard.get_node("StudentParentId/NextBtn") as BaseButton)
		await _wait_for_transition(unlinked_wizard)
		var label := unlinked_wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel") as Label
		_assert(label != null and label.text == "This Student is not linked to this Parent account.", "an existing but unlinked Student receives the truthful relationship error")

	_assert(int(http_api.get("profile_request_count")) == 3, "each Parent/Student validation uses one canonical profile request")


func _open_ids_step() -> Node:
	game_state.call("clear_new_game_registration")
	var result := change_scene_to_file(NEW_GAME_SCENE)
	_assert(result == OK, "New Game scene loads for online-validation regression")
	if result != OK or not await _wait_for_scene(NEW_GAME_SCENE, 180):
		return null
	var wizard := current_scene.get_node_or_null("TextureRect2")
	_assert(wizard != null, "New Game registration wizard exists")
	if wizard == null:
		return null

	await _press(wizard.get_node("GenderSelect/MaleBtn") as BaseButton)
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_for_transition(wizard)
	_assert(wizard.get_node("StudentParentId").visible, "Gender selection advances to IDs")
	var student_input := wizard.get_node("StudentParentId/StudentIdInput") as LineEdit
	var parent_input := wizard.get_node("StudentParentId/ParentIdInput") as LineEdit
	_set_line_edit_text(student_input, "001234")
	_set_line_edit_text(parent_input, "654321")
	return wizard


func _wait_for_transition(wizard: Node) -> void:
	var deadline := Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < deadline:
		if not bool(wizard.get("_step_transitioning")):
			return
		await create_timer(0.01).timeout
	failures.append("Registration step transition did not complete")


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
		failures.append("Attempted to press a missing registration button")
		return
	button.pressed.emit()
	await process_frame
	await process_frame


func _set_line_edit_text(input: LineEdit, text_value: String) -> void:
	if input == null:
		failures.append("Attempted to write a missing registration input")
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
		print("NEW_GAME_ONLINE_VALIDATION_TEST: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NEW_GAME_ONLINE_VALIDATION_TEST: FAIL")
	quit(1)
