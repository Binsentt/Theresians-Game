extends Node

const NEW_GAME := "res://scenes/new_game_scene.tscn"
const LOADING := "res://scenes/loading_screen.tscn"
const PLAYER_HOUSE := "res://interiors/player_house.tscn"
const HttpApiStub := preload("res://tools/test_profile_http_api_stub.gd")
const RemoteSyncStub := preload("res://tools/test_playtime_remote_sync_stub.gd")

var _checks := 0
var _failures: Array[String] = []
var _http: Node
var _remote: Node
var _state: Node
var _current_student_id := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	_http = get_node_or_null("/root/HttpApi")
	_remote = get_node_or_null("/root/RemoteSync")
	_state = get_node_or_null("/root/GameState")
	_expect(_http != null and _remote != null and _state != null, "canonical registration autoloads are available")
	if _http == null or _remote == null or _state == null:
		_finish()
		return
	_http.set_script(HttpApiStub)
	_remote.set_script(RemoteSyncStub)

	await _verify_current_eight_digit_pair_and_tutorial()
	await _verify_legacy_six_digit_pair()
	await _verify_wrong_parent()
	await _verify_missing_parent()
	await _verify_archived_parent()
	await _verify_deleted_family()
	await _verify_input_validation()
	_finish()


func _verify_current_eight_digit_pair_and_tutorial() -> void:
	_current_student_id = _unused_student_id(8)
	_set_profile_response(200, _valid_profile_body("Current QA Student", "Grade 4"))
	var wizard := await _open_ids_step()
	if wizard == null:
		return
	_set_ids(wizard, _current_student_id, "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	_expect(await _wait_for_visible(wizard.get_node("NameGradeSelect"), 240), "valid 8-digit Student plus linked Parent advances")
	_expect(_http.requests.size() == 1, "valid 8-digit submit emits exactly one request")
	_expect(_request_matches(_current_student_id, "654321"), "valid 8-digit submit uses the canonical GET route and Parent query")
	var name_input := wizard.get_node("NameGradeSelect/NameInput") as LineEdit
	_expect(name_input.text == "Current QA Student" and not name_input.editable, "canonical Student name is applied and locked")
	_expect(String(wizard.get("selected_grade")) == "Grade 4", "canonical Grade is applied")
	_expect((wizard.get_node("NameGradeSelect/Grade4") as BaseButton).disabled, "canonical Grade controls are locked")
	_expect(bool(wizard.get("_step_transitioning")), "Play becomes visible during the short Name/Grade fade")
	print("NEW GAME TRACE: student_length=8 parent_length=6 selected_grade=Grade 4 method=GET route=/api/game/profile/check/[STUDENT]?parent_id=[PARENT] sent=true status=200")

	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	_expect(await _wait_for_scene(LOADING, 240), "valid pair reaches canonical Loading")
	_expect(await _wait_for_scene(PLAYER_HOUSE, 480), "valid pair reaches Player House tutorial entry")
	_expect(_state.is_tutorial_active(), "Tutorial is active after the valid New Game transition")
	_expect(String(_state.student_id) == _current_student_id and String(_state.parent_id) == "654321", "canonical linked identity is committed to GameState")
	_expect(_remote.requests.size() == 1, "the preserved Play press starts exactly one playtime request")


func _verify_legacy_six_digit_pair() -> void:
	_current_student_id = _unused_student_id(6)
	_set_profile_response(200, _valid_profile_body("Legacy QA Student", "Grade 2"))
	var wizard := await _open_ids_step()
	if wizard == null:
		return
	_set_ids(wizard, _current_student_id, "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	_expect(await _wait_for_visible(wizard.get_node("NameGradeSelect"), 240), "valid legacy 6-digit Student plus linked Parent advances")
	_expect(_request_matches(_current_student_id, "654321"), "legacy submit preserves the canonical route and Parent query")
	_expect((wizard.get_node("NameGradeSelect/NameInput") as LineEdit).text == "Legacy QA Student", "legacy canonical profile is applied")


func _verify_wrong_parent() -> void:
	_set_profile_response(403, {
		"ok": false,
		"can_play": false,
		"should_block": true,
		"error": "This Student is not linked to this Parent account.",
	})
	var wizard := await _open_ids_step()
	if wizard == null:
		return
	_set_ids(wizard, _unused_student_id(8), "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_for_transition(wizard)
	_expect(wizard.get_node("StudentParentId").visible and not wizard.get_node("NameGradeSelect").visible, "wrong Parent stays on the ID step")
	_expect(_validation_text(wizard) == "This Student is not linked to this Parent account.", "wrong Parent renders the truthful HTTP 403 error")


func _verify_missing_parent() -> void:
	_set_profile_response(404, {"ok": false, "error": "Parent ID does not exist."})
	var wizard := await _open_ids_step()
	if wizard == null:
		return
	_set_ids(wizard, _unused_student_id(8), "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_for_transition(wizard)
	_expect(wizard.get_node("StudentParentId").visible and not wizard.get_node("NameGradeSelect").visible, "missing Parent stays on the ID step")
	_expect(_validation_text(wizard) == "Parent ID does not exist.", "missing Parent renders the truthful HTTP 404 error")


func _verify_archived_parent() -> void:
	_set_profile_response(403, {
		"ok": false,
		"can_play": false,
		"should_block": true,
		"error": "Parent account is archived.",
	})
	var wizard := await _open_ids_step()
	if wizard == null:
		return
	_set_ids(wizard, _unused_student_id(8), "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_for_transition(wizard)
	_expect(wizard.get_node("StudentParentId").visible and not wizard.get_node("NameGradeSelect").visible, "archived Parent stays on the ID step")
	_expect(_validation_text(wizard) == "Parent account is archived.", "archived Parent rejection remains truthful")


func _verify_deleted_family() -> void:
	_set_profile_response(404, {
		"ok": false,
		"can_play": false,
		"error": "Student or Parent account does not exist.",
	})
	var wizard := await _open_ids_step()
	if wizard == null:
		return
	_set_ids(wizard, _unused_student_id(8), "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_for_transition(wizard)
	_expect(wizard.get_node("StudentParentId").visible and not wizard.get_node("NameGradeSelect").visible, "deleted family stays on the ID step")
	_expect(_validation_text(wizard) == "Student or Parent account does not exist.", "deleted relationship rejection remains truthful")


func _verify_input_validation() -> void:
	_set_profile_response(200, _valid_profile_body("Unused", "Grade 1"))
	var wizard := await _open_ids_step()
	if wizard == null:
		return
	_set_ids(wizard, "1234567", "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	_expect(_http.requests.is_empty(), "invalid Student length is rejected before any request")
	_expect(_validation_text(wizard).begins_with("Student ID"), "invalid Student length renders a visible validation error")

	_set_ids(wizard, _unused_student_id(8), "12345")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	_expect(_http.requests.is_empty(), "invalid Parent length is rejected before any request")
	_expect(_validation_text(wizard).begins_with("Parent ID"), "invalid Parent length renders a visible validation error")


func _open_ids_step() -> Node:
	_state.clear_new_game_registration()
	_http.requests.clear()
	var previous_scene := get_tree().current_scene
	var result := get_tree().change_scene_to_file(NEW_GAME)
	_expect(result == OK, "New Game scene opens")
	if result != OK or not await _wait_for_replaced_scene(NEW_GAME, previous_scene, 240):
		return null
	var wizard := get_tree().current_scene.get_node_or_null("TextureRect2")
	_expect(wizard != null, "New Game registration controller is present")
	if wizard == null:
		return null
	await _press(wizard.get_node("GenderSelect/MaleBtn") as BaseButton)
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	_expect(await _wait_for_visible(wizard.get_node("StudentParentId"), 180), "Gender step advances to Student/Parent IDs")
	await _wait_for_transition(wizard)
	return wizard


func _set_profile_response(status: int, body: Dictionary) -> void:
	_http.profile_result = {"ok": status >= 200 and status < 300, "status": status, "body": body}


func _valid_profile_body(student_name: String, grade: String) -> Dictionary:
	return {
		"ok": true,
		"can_play": true,
		"should_block": false,
		"canonical_profile": {"name": student_name, "grade_level": grade, "section": "Amethyst"},
		"learning_cycle": {},
	}


func _set_ids(wizard: Node, student_code: String, parent_code: String) -> void:
	_set_text(wizard.get_node("StudentParentId/StudentIdInput") as LineEdit, student_code)
	_set_text(wizard.get_node("StudentParentId/ParentIdInput") as LineEdit, parent_code)


func _set_text(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)


func _request_matches(student_code: String, parent_code: String) -> bool:
	if _http.requests.size() != 1:
		return false
	var request: Dictionary = _http.requests[0]
	return request.get("kind") == "get" \
		and request.get("path") == "/api/game/profile/check/" + student_code \
		and request.get("payload", {}) == {"parent_id": parent_code}


func _unused_student_id(length: int) -> String:
	var maximum := 100000000 if length == 8 else 1000000
	var value := int(Time.get_ticks_usec() % maximum)
	for offset in 100:
		var candidate := str((value + offset) % maximum).pad_zeros(length)
		if not _state.has_existing_game_profile_for_student_id(candidate):
			return candidate
	return ("8" if length == 8 else "6").repeat(length)


func _validation_text(wizard: Node) -> String:
	var label := wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel") as Label
	return label.text


func _press(button: BaseButton) -> void:
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait_for_transition(wizard: Node) -> void:
	for _index in 240:
		if not bool(wizard.get("_step_transitioning")):
			return
		await get_tree().process_frame


func _wait_for_visible(node: CanvasItem, frames: int) -> bool:
	for _index in frames:
		if node.visible:
			return true
		await get_tree().process_frame
	return false


func _wait_for_scene(path: String, frames: int) -> bool:
	for _index in frames:
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _wait_for_replaced_scene(path: String, previous_scene: Node, frames: int) -> bool:
	for _index in frames:
		if get_tree().current_scene != null and get_tree().current_scene != previous_scene \
				and get_tree().current_scene.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var file := FileAccess.open("res://tools/new_game_login_contract_test_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"passed": _checks - _failures.size(),
			"failed": _failures.size(),
			"failures": _failures,
		}, "\t"))
		file.close()
	if _failures.is_empty():
		print("NEW_GAME_LOGIN_CONTRACT_TEST PASS checks=%d failures=0" % _checks)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("NEW_GAME_LOGIN_CONTRACT_TEST FAIL checks=%d failures=%d" % [_checks, _failures.size()])
	get_tree().quit(1)
