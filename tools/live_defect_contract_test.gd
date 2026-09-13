extends Node

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var remote_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	var settings_source := FileAccess.get_file_as_string("res://scenes/Settings-Ingame/settings_ingame_controller.gd")
	var leaderboard_source := FileAccess.get_file_as_string("res://scripts/leaderboard_scene_controller.gd")
	var menu_source := FileAccess.get_file_as_string("res://scripts/main_menu_scene.gd")
	var menu_scene_source := FileAccess.get_file_as_string("res://scenes/main_menu.tscn")
	_expect(remote_source.contains("func _ensure_playtime_session()"), "RemoteSync must have one shared lease-recovery path for gameplay results and leaderboard reads.")
	_expect(remote_source.contains("var session_result: Dictionary = await _ensure_playtime_session()"), "Question result sync must recover a missing playtime lease before sending the graded result.")
	_expect(not remote_source.contains("skipping question result because no active server playtime lease is available"), "Question results must not be silently discarded solely because the initial lease request raced the battle.")
	_expect(settings_source.contains("const MAIN_MENU_SCENE := \"res://scenes/main_menu.tscn\""), "In-game Settings must target the canonical Main Menu scene.")
	_expect(settings_source.contains("get_tree().change_scene_to_file(MAIN_MENU_SCENE)"), "In-game Settings Quit must return to Main Menu instead of quitting the process.")
	_expect(remote_source.contains("var session_result: Dictionary = await _ensure_playtime_session()"), "Leaderboard requests must recover a missing lease after a login/session race.")
	_expect(leaderboard_source.contains("request_game_leaderboard"), "Leaderboard remains owned by the canonical RemoteSync request path.")
	_expect(not menu_source.contains("if GameState.has_current_terms_app_acceptance():"), "Main Menu Terms gate must not bypass a fresh app launch after a prior acceptance.")
	_expect(menu_source.contains("get_node_or_null(\"VBoxContainer/OptionBtn\")"), "Options is gated before Terms acceptance.")
	_expect(menu_source.contains("get_node_or_null(\"VBoxContainer/QuitBtn\")"), "Quit is gated before Terms acceptance.")
	_expect(menu_scene_source.contains("node name=\"OptionBtn\""), "Main Menu exposes the Options control under the startup gate.")
	_expect(menu_scene_source.contains("node name=\"QuitBtn\""), "Main Menu exposes the Quit control under the startup gate.")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("live_defect_contract_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
