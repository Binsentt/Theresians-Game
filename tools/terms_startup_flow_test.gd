extends Node

const TERMS_APP_ACCEPTANCE_PATH := "user://terms_app_acceptance.json"
const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")

var _checks: Array[Dictionary] = []
var _original_acceptance := ""
var _had_original_acceptance := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_original_acceptance = FileAccess.get_file_as_string(TERMS_APP_ACCEPTANCE_PATH)
	_had_original_acceptance = FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH)
	if _had_original_acceptance:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_APP_ACCEPTANCE_PATH))

	var game_state := get_node_or_null("/root/GameState")
	_expect(game_state != null and game_state.has_method("has_current_terms_app_acceptance"), "GameState exposes a device-scoped app Terms acceptance")
	_expect(game_state != null and game_state.has_method("record_terms_app_acceptance"), "GameState persists app Terms acceptance without inventing a Student ID")

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
	_expect(terms_gate != null and terms_gate.visible, "Terms gate appears automatically at Main Menu startup")
	_expect(new_game != null and new_game.disabled, "New Game is gated before Terms acceptance")
	_expect(load_game != null and load_game.disabled, "Load Game is gated before Terms acceptance")
	_expect(leaderboard != null and leaderboard.disabled, "Leaderboard is gated before Terms acceptance")

	if terms_gate != null:
		var checkbox := terms_gate.get_node_or_null("Panel/Margin/Content/AgreementRow/AgreementCheckBox") as CheckBox
		var continue_button := terms_gate.get_node_or_null("Panel/Margin/Content/Actions/ContinueButton") as Button
		var cancel_button := terms_gate.get_node_or_null("Panel/Margin/Content/Actions/CancelButton") as Button
		var scroll := terms_gate.get_node_or_null("Panel/Margin/Content/TermsScroll") as ScrollContainer
		var panel := terms_gate.get_node_or_null("Panel") as PanelContainer
		_expect(checkbox != null, "Terms gate has a real checkbox")
		_expect(continue_button != null and continue_button.disabled, "Continue is disabled while unchecked")
		_expect(cancel_button != null, "Terms gate has a Cancel action")
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
			_expect(terms_gate.visible and new_game.disabled, "Cancel leaves the player at a gated Main Menu")
			checkbox.button_pressed = true
			await get_tree().process_frame
			continue_button.pressed.emit()
			await get_tree().process_frame
			await get_tree().process_frame
			_expect(not terms_gate.visible, "Continue closes the Terms gate cleanly")
			_expect(not new_game.disabled and not load_game.disabled and not leaderboard.disabled, "Main Menu controls restore after acceptance")
			_expect(game_state != null and bool(game_state.call("has_current_terms_app_acceptance")), "Continue persists the app acceptance")

	var saved_app_acceptance := FileAccess.get_file_as_string(TERMS_APP_ACCEPTANCE_PATH)
	var stale_file := FileAccess.open(TERMS_APP_ACCEPTANCE_PATH, FileAccess.WRITE)
	if stale_file != null:
		stale_file.store_string(JSON.stringify({
			"device_installation_id": game_state.get_device_installation_id(),
			"terms_version": "old-version",
			"accepted_at": "2020-01-01T00:00:00Z",
		}))
		stale_file.close()
	_expect(game_state != null and not bool(game_state.call("has_current_terms_app_acceptance")), "Terms version changes require fresh acceptance")
	var current_file := FileAccess.open(TERMS_APP_ACCEPTANCE_PATH, FileAccess.WRITE)
	if current_file != null:
		current_file.store_string(saved_app_acceptance)
		current_file.close()

	var accepted_menu := MAIN_MENU_SCENE.instantiate() as Control
	get_tree().root.add_child(accepted_menu)
	get_tree().current_scene = accepted_menu
	await get_tree().process_frame
	await get_tree().process_frame
	var accepted_new_game := accepted_menu.get_node_or_null("VBoxContainer/NewGameBtn") as BaseButton
	_expect(accepted_menu.get_node_or_null("TermsGate") == null, "Existing accepted version does not block startup again")
	if is_instance_valid(accepted_new_game):
		accepted_new_game.pressed.emit()
		await get_tree().create_timer(0.8).timeout
		_expect(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/new_game_scene.tscn", "New Game starts normally after Terms acceptance")

	_cleanup_acceptance()
	_finish()


func _cleanup_acceptance() -> void:
	if FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_APP_ACCEPTANCE_PATH))
	if _had_original_acceptance:
		var file := FileAccess.open(TERMS_APP_ACCEPTANCE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_original_acceptance)
			file.close()


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if not bool(check.get("passed", false)):
			failed += 1
	print("TERMS_STARTUP_FLOW_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	get_tree().quit(0 if failed == 0 else 1)
