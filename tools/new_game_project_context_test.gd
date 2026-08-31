extends Node

const MAIN_MENU := "res://scenes/main_menu.tscn"
const NEW_GAME := "res://scenes/new_game_scene.tscn"
const LOADING := "res://scenes/loading_screen.tscn"
const PLAYER_HOUSE := "res://interiors/player_house.tscn"
const HttpApiStub := preload("res://tools/test_profile_http_api_stub.gd")
const RemoteSyncStub := preload("res://tools/test_playtime_remote_sync_stub.gd")

var _failures: Array[String] = []
var _request_sequence: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	var http_api := get_node_or_null("/root/HttpApi")
	var remote_sync := get_node_or_null("/root/RemoteSync")
	_assert(http_api != null, "Project-context test requires the HttpApi autoload")
	_assert(remote_sync != null, "Project-context test requires the RemoteSync autoload")
	if http_api == null or remote_sync == null:
		_finish()
		return

	http_api.set_script(HttpApiStub)
	remote_sync.set_script(RemoteSyncStub)
	http_api.request_recorded.connect(_on_http_request_recorded)
	remote_sync.request_recorded.connect(_on_playtime_request_recorded)

	_assert(await _load_scene(MAIN_MENU), "Main Menu opens in normal project context")
	var menu_button := get_tree().current_scene.get_node_or_null("VBoxContainer/NewGameBtn") as BaseButton
	_assert(menu_button != null, "Main Menu exposes its New Game button")
	if menu_button != null:
		await _press(menu_button)
	_assert(await _wait_for_scene(NEW_GAME, 180), "New Game opens from Main Menu")
	await _wait_frames(4)

	var wizard := _current_wizard()
	_assert(wizard != null, "New Game contains its registration wizard")
	if wizard != null:
		var validation_started_at := Time.get_ticks_msec()
		await _drive_to_name_grade(wizard)
		_assert(
			Time.get_ticks_msec() - validation_started_at < 2000,
			"Immediate fixture responses do not introduce an artificial validation delay"
		)
		_assert(bool(wizard.get_node("NameGradeSelect").visible), "Valid Parent/Student pair reaches Name and Grade")
		_assert(_count_request(http_api, "post", "/api/game/parent/validate") == 1, "Parent validation issues exactly one request")
		_assert(_count_request(http_api, "get", "/api/game/profile/check/000123") == 1, "Profile check issues exactly one request")
		_assert(
			_count_request_with_payload(http_api, "post", "/api/game/parent/validate", {"parent_id": "654321"}) == 1,
			"Parent validation uses the canonical Parent ID request shape"
		)
		_assert(
			_count_request_with_payload(http_api, "get", "/api/game/profile/check/000123", {"parent_id": "654321"}) == 1,
			"Profile validation carries the Student/Parent pair without a localhost URL"
		)
		_assert(_all_stub_paths_are_relative(http_api), "New Game uses API-relative paths, never a localhost production URL")

		await _fill_name_grade_and_start(wizard)
		_assert(await _wait_for_scene(LOADING, 180), "Valid registration transitions through Loading")
		_assert(await _wait_for_scene(PLAYER_HOUSE, 360), "Valid registration transitions to Player House")
		_assert(GameState.current_scene_path == PLAYER_HOUSE, "Player House transition preserves the canonical destination")
		_assert(remote_sync.requests.size() == 1, "A valid registration requests exactly one playtime lease")
		_assert(_request_sequence.size() >= 3 and _request_sequence[-1] == "lease", "Lease request follows Parent and Profile validation")

		await _exercise_blocked_profile(http_api)

	_finish()


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _drive_to_name_grade(wizard: Node) -> void:
	await _press(wizard.get_node("GenderSelect/MaleBtn") as BaseButton)
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	_assert(await _wait_for_visible(wizard.get_node("StudentParentId"), 120), "Gender selection advances to IDs")
	await _wait_seconds(0.30)
	_set_text(wizard.get_node("StudentParentId/StudentIdInput") as LineEdit, "000123")
	_set_text(wizard.get_node("StudentParentId/ParentIdInput") as LineEdit, "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	_assert(await _wait_for_visible(wizard.get_node("NameGradeSelect"), 180), "Valid IDs advance to Name and Grade")
	await _wait_seconds(0.30)


func _fill_name_grade_and_start(wizard: Node) -> void:
	_set_text(wizard.get_node("NameGradeSelect/NameInput") as LineEdit, "Fixture Student")
	await _press(wizard.get_node("NameGradeSelect/Grade2") as BaseButton)
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)


func _exercise_blocked_profile(http_api: Node) -> void:
	http_api.requests.clear()
	http_api.profile_result = {
		"ok": true,
		"status": 200,
		"body": {"ok": true, "should_block": true, "error": "Existing fixture profile."},
	}
	_assert(await _load_scene(NEW_GAME), "New Game can reopen for the invalid-profile path")
	await _wait_frames(4)
	var wizard := _current_wizard()
	if wizard == null:
		return
	await _drive_to_ids(wizard)
	_set_text(wizard.get_node("StudentParentId/StudentIdInput") as LineEdit, "000123")
	_set_text(wizard.get_node("StudentParentId/ParentIdInput") as LineEdit, "654321")
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_for_visible(wizard.get_node("ValidationPanel"), 180)
	_assert(bool(wizard.get_node("StudentParentId").visible), "Blocked profile remains on the ID step")
	_assert(not bool(wizard.get_node("NameGradeSelect").visible), "Blocked profile cannot advance to Name and Grade")
	var message := wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel") as Label
	_assert(message != null and message.text == "Existing fixture profile.", "Blocked response uses the backend lifecycle descriptor")
	_assert(_count_request(http_api, "get", "/api/game/profile/check/000123") == 1, "Blocked profile uses one profile request")


func _drive_to_ids(wizard: Node) -> void:
	await _press(wizard.get_node("GenderSelect/FemaleBtn") as BaseButton)
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	_assert(await _wait_for_visible(wizard.get_node("StudentParentId"), 120), "Female selection advances to IDs")
	await _wait_seconds(0.30)


func _current_wizard() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("TextureRect2") if scene != null else null


func _load_scene(path: String) -> bool:
	if get_tree().change_scene_to_file(path) != OK:
		return false
	return await _wait_for_scene(path, 180)


func _wait_for_scene(path: String, frame_limit: int) -> bool:
	for _index in frame_limit:
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _wait_for_visible(node: CanvasItem, frame_limit: int) -> bool:
	if node == null:
		return false
	for _index in frame_limit:
		if node.visible:
			return true
		await get_tree().process_frame
	return false


func _wait_frames(frame_count: int) -> void:
	for _index in frame_count:
		await get_tree().process_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _press(button: BaseButton) -> void:
	if button == null:
		_failures.append("Attempted to press a missing control")
		return
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


func _set_text(field: LineEdit, value: String) -> void:
	if field == null:
		_failures.append("Attempted to populate a missing input")
		return
	field.text = value
	field.text_changed.emit(value)


func _count_request(http_api: Node, kind: String, path: String) -> int:
	var count := 0
	for entry in http_api.requests:
		if String(entry.get("kind", "")) == kind and String(entry.get("path", "")) == path:
			count += 1
	return count


func _count_request_with_payload(http_api: Node, kind: String, path: String, payload: Dictionary) -> int:
	var count := 0
	for entry in http_api.requests:
		if String(entry.get("kind", "")) == kind and String(entry.get("path", "")) == path and entry.get("payload", {}) == payload:
			count += 1
	return count


func _all_stub_paths_are_relative(http_api: Node) -> bool:
	for entry in http_api.requests:
		if "://" in String(entry.get("path", "")):
			return false
	return true


func _on_http_request_recorded(kind: String, path: String, _payload: Dictionary) -> void:
	_request_sequence.append("%s:%s" % [kind, path])


func _on_playtime_request_recorded(_payload: Dictionary) -> void:
	_request_sequence.append("lease")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("NEW_GAME_PROJECT_CONTEXT_TEST PASSED")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("NEW_GAME_PROJECT_CONTEXT_TEST FAILED")
	get_tree().quit(1)
