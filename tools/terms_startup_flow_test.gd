extends Node

const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")
const NEW_GAME_SCENE := preload("res://scenes/new_game_scene.tscn")
const RESULT_PATH := "user://terms_startup_flow_test_result.json"

var _checks: Array[Dictionary] = []
var _isolated_directory := ""
var _isolated_acceptance_path := ""
var _secondary_acceptance_path := ""
var _simulated_acceptance_path := ""
var _original_device_installation_id := ""
var _original_app_acceptance_contents := ""
var _original_app_acceptance_exists := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not HttpApi.is_local_qa_profile_active():
		push_error("Terms QA refused to run without local-only startup selected before autoload initialization.")
		get_tree().quit(1)
		return
	var game_state := get_node_or_null("/root/GameState")
	_expect(game_state != null and game_state.has_method("has_current_terms_app_acceptance"), "GameState exposes a device-scoped app Terms acceptance")
	_expect(game_state != null and game_state.has_method("record_terms_app_acceptance"), "GameState persists app Terms acceptance without inventing a Student ID")
	_expect(game_state != null and game_state.has_method("set_terms_app_acceptance_path_for_qa"), "Terms QA can select an isolated acceptance profile without touching developer user data")
	if game_state == null or not game_state.has_method("set_terms_app_acceptance_path_for_qa"):
		await _finish()
		return

	_isolated_directory = "user://qa_test_artifacts/terms_startup_flow_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_directory := ProjectSettings.globalize_path(_isolated_directory)
	if DirAccess.dir_exists_absolute(absolute_directory):
		_expect(false, "Refusing to reuse an existing isolated Terms QA profile")
		await _finish()
		return
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		_expect(false, "Could not create the isolated Terms QA profile")
		await _finish()
		return
	_isolated_acceptance_path = _isolated_directory.path_join("profile_one_terms.json")
	_secondary_acceptance_path = _isolated_directory.path_join("profile_two_terms.json")
	_original_app_acceptance_exists = FileAccess.file_exists(GameState.TERMS_APP_ACCEPTANCE_PATH)
	if _original_app_acceptance_exists:
		_original_app_acceptance_contents = FileAccess.get_file_as_string(GameState.TERMS_APP_ACCEPTANCE_PATH)
	_original_device_installation_id = String(game_state.get("device_installation_id"))
	game_state.set("device_installation_id", "terms-test-device-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var profile_selected := bool(game_state.call("set_terms_app_acceptance_path_for_qa", _isolated_acceptance_path))
	_expect(profile_selected, "Terms QA selected a unique clean acceptance profile")
	if not profile_selected:
		_cleanup_acceptance()
		await _finish()
		return
	_expect(not FileAccess.file_exists(_isolated_acceptance_path), "Fresh isolated profile begins without accepted Terms")

	# The production button scripts resolve Fade/VBoxContainer from the active
	# scene during @onready; provide harmless stand-ins while this harness mounts
	# the menu as a child, then make the menu the active scene before exercising it.
	var fade_stub := ColorRect.new()
	fade_stub.name = "Fade"
	add_child(fade_stub)
	var menu_stub := VBoxContainer.new()
	menu_stub.name = "VBoxContainer"
	add_child(menu_stub)
	var menu := MAIN_MENU_SCENE.instantiate() as Control
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	await get_tree().process_frame

	var terms_gate := menu.get_node_or_null("TermsGate") as Control
	var new_game := menu.get_node_or_null("VBoxContainer/NewGameBtn") as BaseButton
	var load_game := menu.get_node_or_null("VBoxContainer/LoadGameBtn") as BaseButton
	var leaderboard := menu.get_node_or_null("LeaderboardButton") as BaseButton
	var terms_privacy := menu.get_node_or_null("VBoxContainer/TermsPrivacyButton") as BaseButton
	var title := menu.get_node_or_null("Label") as Control
	var menu_controls := menu.get_node_or_null("VBoxContainer") as Control
	_expect(terms_gate != null and terms_gate.visible, "Terms gate appears automatically at Main Menu startup")
	_expect(new_game != null and new_game.disabled, "New Game is gated before Terms acceptance")
	_expect(load_game != null and load_game.disabled, "Load Game is gated before Terms acceptance")
	_expect(leaderboard != null and leaderboard.disabled, "Leaderboard is gated before Terms acceptance")
	_expect(terms_privacy != null and not terms_privacy.disabled, "Terms & Privacy remains available while gameplay actions are gated")
	_expect(title != null and menu_controls != null and menu_controls.position.y - (title.position.y + title.size.y) >= 20.0, "Main Menu controls sit clearly below the title")
	if menu_controls != null:
		for validation_size in [Vector2(1134, 509), Vector2(1215, 545), Vector2(1280, 720), Vector2(1920, 1080)]:
			_expect(menu_controls.position.y + menu_controls.get_combined_minimum_size().y <= validation_size.y, "Main Menu controls fit %dx%d" % [validation_size.x, validation_size.y])

	if terms_gate != null:
		var checkbox := terms_gate.get_node_or_null("Panel/Margin/Content/AgreementRow/AgreementCheckBox") as CheckBox
		var continue_button := terms_gate.get_node_or_null("Panel/Margin/Content/Actions/ContinueButton") as Button
		var cancel_button := terms_gate.get_node_or_null("Panel/Margin/Content/Actions/CancelButton") as Button
		var actions := terms_gate.get_node_or_null("Panel/Margin/Content/Actions") as HBoxContainer
		var scroll := terms_gate.get_node_or_null("Panel/Margin/Content/TermsScroll") as ScrollContainer
		var panel := terms_gate.get_node_or_null("Panel") as Control
		_expect(checkbox != null, "Terms gate has a real checkbox")
		_expect(continue_button != null and continue_button.disabled, "Continue is disabled while unchecked")
		_expect(cancel_button != null, "Terms gate has a Cancel action")
		_expect(actions != null and actions.visible, "Terms footer actions remain visible")
		_expect(checkbox != null and checkbox.visible, "Terms agreement checkbox remains visible")
		_expect(scroll != null and scroll.get_node_or_null("TermsBody") != null, "Terms body is wrapped in a scrollable control")
		_expect(panel != null and panel.size.x <= get_viewport().get_visible_rect().size.x * 0.9 + 2.0, "Terms panel stays within a safe viewport width")
		if checkbox != null and continue_button != null:
			checkbox.button_pressed = true
			await get_tree().process_frame
			_expect(not continue_button.disabled, "Continue enables after checking the agreement")
			checkbox.button_pressed = false
			await get_tree().process_frame
			_expect(continue_button.disabled, "Continue disables again when unchecked")
			cancel_button.pressed.emit()
			await get_tree().process_frame
			_expect(not terms_gate.visible and new_game.disabled and load_game.disabled and leaderboard.disabled, "Cancel closes Terms while leaving Main Menu actions gated")
			terms_privacy.pressed.emit()
			await get_tree().process_frame
			_expect(terms_gate.visible, "Terms & Privacy reopens the required Terms gate after Cancel")
			_expect(checkbox.visible and not checkbox.button_pressed, "Reopened Terms keeps the agreement checkbox available and unchecked")
			checkbox.button_pressed = true
			await get_tree().process_frame
			continue_button.pressed.emit()
			await get_tree().process_frame
			await get_tree().process_frame
			_expect(not terms_gate.visible, "Continue closes the Terms gate cleanly")
			_expect(not new_game.disabled and not load_game.disabled and not leaderboard.disabled, "Main Menu controls restore after acceptance")
			_expect(game_state != null and bool(game_state.call("has_current_terms_app_acceptance")), "Continue persists the app acceptance")

	var saved_app_acceptance := FileAccess.get_file_as_string(_isolated_acceptance_path)
	var stale_file := FileAccess.open(_isolated_acceptance_path, FileAccess.WRITE)
	if stale_file != null:
		stale_file.store_string(JSON.stringify({
			"device_installation_id": game_state.get_device_installation_id(),
			"terms_version": "old-version",
			"accepted_at": "2020-01-01T00:00:00Z",
		}))
		stale_file.close()
	_expect(game_state != null and not bool(game_state.call("has_current_terms_app_acceptance")), "Terms version changes require fresh acceptance")
	var current_file := FileAccess.open(_isolated_acceptance_path, FileAccess.WRITE)
	if current_file != null:
		current_file.store_string(saved_app_acceptance)
		current_file.close()

	if game_state != null and game_state.has_method("reset_terms_session_acceptance"):
		game_state.call("reset_terms_session_acceptance")
	var accepted_menu := MAIN_MENU_SCENE.instantiate() as Control
	get_tree().root.add_child(accepted_menu)
	get_tree().current_scene = accepted_menu
	await get_tree().process_frame
	await get_tree().process_frame
	var accepted_new_game := accepted_menu.get_node_or_null("VBoxContainer/NewGameBtn") as BaseButton
	var accepted_terms_gate := accepted_menu.get_node_or_null("TermsGate") as Control
	_expect(accepted_terms_gate == null or not accepted_terms_gate.visible, "Persisted device acceptance survives a fresh debug run")
	_expect(accepted_new_game != null and not accepted_new_game.disabled, "Persisted device acceptance unlocks gameplay after restart")
	var fresh_install_button := accepted_menu.get_node_or_null("EditorFreshTermsButton") as Button
	_expect(fresh_install_button != null and fresh_install_button.visible, "Editor/local-QA Main Menu exposes an explicit fresh-install Terms simulation")
	if fresh_install_button != null:
		fresh_install_button.pressed.emit()
		await get_tree().process_frame
		accepted_terms_gate = accepted_menu.get_node_or_null("TermsGate") as Control
		_simulated_acceptance_path = String(game_state.call("_terms_app_acceptance_path"))
		_expect(accepted_terms_gate != null and accepted_terms_gate.visible, "Fresh-install simulation opens the real Terms gate")
		_expect(_simulated_acceptance_path.begins_with("user://qa_test_artifacts/terms_startup_flow_test_editor_"), "Simulation stores acceptance in a unique QA-only profile")
		_expect(accepted_new_game != null and accepted_new_game.disabled, "Fresh-install simulation gates gameplay until Terms are accepted")
		var simulated_checkbox := accepted_terms_gate.get_node_or_null("Panel/Margin/Content/AgreementRow/AgreementCheckBox") as CheckBox if accepted_terms_gate != null else null
		var simulated_continue := accepted_terms_gate.get_node_or_null("Panel/Margin/Content/Actions/ContinueButton") as Button if accepted_terms_gate != null else null
		if simulated_checkbox != null and simulated_continue != null:
			simulated_checkbox.button_pressed = true
			await get_tree().process_frame
			simulated_continue.pressed.emit()
			await get_tree().process_frame
			_expect(FileAccess.file_exists(_simulated_acceptance_path), "Accept persists Terms for the simulated profile during this run")
		_expect(not FileAccess.file_exists(GameState.TERMS_APP_ACCEPTANCE_PATH) if not _original_app_acceptance_exists else FileAccess.get_file_as_string(GameState.TERMS_APP_ACCEPTANCE_PATH) == _original_app_acceptance_contents, "Simulation never overwrites the real installation acceptance")
	var simulated_restart_game_state: Node = load("res://scripts/game_state.gd").new()
	simulated_restart_game_state.set("device_installation_id", String(game_state.get("device_installation_id")))
	simulated_restart_game_state.call("set_terms_app_acceptance_path_for_qa", _isolated_acceptance_path)
	_expect(bool(simulated_restart_game_state.call("has_current_terms_app_acceptance")), "A fresh GameState instance reads acceptance from the same persisted profile after restart")
	simulated_restart_game_state.free()

	var new_game_wizard := NEW_GAME_SCENE.instantiate() as Control
	get_tree().root.add_child(new_game_wizard)
	var new_game_controller := new_game_wizard.get_node_or_null("TextureRect2")
	GameState.update_new_game_registration({"student_id": "12345678", "parent_id": "654321"})
	_expect(new_game_controller != null and new_game_controller.has_method("has_local_terms_acceptance"), "New Game checks device acceptance independently of Student ownership")
	if new_game_controller != null and new_game_controller.has_method("has_local_terms_acceptance"):
		_expect(bool(new_game_controller.call("has_local_terms_acceptance")), "Accepted device Terms remain valid after Student/Parent validation")
		GameState.update_new_game_registration({"student_id": "23456789", "parent_id": "654321"})
		_expect(bool(new_game_controller.call("has_local_terms_acceptance")), "Switching linked Student profiles does not reopen device Terms")
	new_game_wizard.queue_free()

	var fresh_profile_selected := bool(game_state.call("set_terms_app_acceptance_path_for_qa", _secondary_acceptance_path))
	_expect(fresh_profile_selected and not FileAccess.file_exists(_secondary_acceptance_path), "A different fresh local profile has no inherited acceptance")
	var fresh_profile_menu := MAIN_MENU_SCENE.instantiate() as Control
	get_tree().root.add_child(fresh_profile_menu)
	get_tree().current_scene = fresh_profile_menu
	await get_tree().process_frame
	await get_tree().process_frame
	var fresh_profile_gate := fresh_profile_menu.get_node_or_null("TermsGate") as Control
	_expect(fresh_profile_gate != null and fresh_profile_gate.visible, "A different fresh local profile sees Terms before gameplay")
	fresh_profile_menu.queue_free()

	_cleanup_acceptance()
	_finish()


func _cleanup_acceptance() -> void:
	for path in [_isolated_acceptance_path, _secondary_acceptance_path, _simulated_acceptance_path]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not _isolated_directory.is_empty() and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_isolated_directory)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_isolated_directory))
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		if game_state.has_method("reset_terms_app_acceptance_path_for_qa"):
			game_state.call("reset_terms_app_acceptance_path_for_qa")
		game_state.set("device_installation_id", _original_device_installation_id)


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if not bool(check.get("passed", false)):
			failed += 1
	var result := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks}
	var result_file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(result))
	print("TERMS_STARTUP_FLOW_TEST " + JSON.stringify(result))
	await get_tree().create_timer(45.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
