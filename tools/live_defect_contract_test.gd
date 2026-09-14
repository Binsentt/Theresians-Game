extends Node

const RESULT_PATH := "user://live_defect_contract_test_result.json"
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var quiz_source := FileAccess.get_file_as_string("res://Battle/Battle-Enemy/QuizManager.gd")
	_expect(not quiz_source.contains('call_deferred("record_question_attempt"'), "Quiz answers enter the durable RemoteSync outbox before a scene change can cancel the enqueue")
	_expect(quiz_source.contains('remote_sync.call("record_question_attempt"'), "Quiz answers invoke the durable write-ahead path directly")
	var remote_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	var settings_source := FileAccess.get_file_as_string("res://scenes/Settings-Ingame/settings_ingame_controller.gd")
	var leaderboard_source := FileAccess.get_file_as_string("res://scripts/leaderboard_scene_controller.gd")
	var menu_source := FileAccess.get_file_as_string("res://scripts/main_menu_scene.gd")
	var menu_scene_source := FileAccess.get_file_as_string("res://scenes/main_menu.tscn")
	var new_game_source := FileAccess.get_file_as_string("res://scenes/texture_rect_2.gd")
	var load_game_source := FileAccess.get_file_as_string("res://scripts/load_game_scene.gd")
	_expect(remote_source.contains("func _ensure_playtime_session()"), "RemoteSync must have one shared lease-recovery path for gameplay results and leaderboard reads.")
	_expect(remote_source.contains("var session_result: Dictionary = await _ensure_playtime_session()"), "Question result sync must recover a missing playtime lease before sending the graded result.")
	_expect(not remote_source.contains("skipping question result because no active server playtime lease is available"), "Question results must not be silently discarded solely because the initial lease request raced the battle.")
	_expect(settings_source.contains("const MAIN_MENU_SCENE := \"res://scenes/main_menu.tscn\""), "In-game Settings must target the canonical Main Menu scene.")
	_expect(settings_source.contains("get_tree().change_scene_to_file(MAIN_MENU_SCENE)"), "In-game Settings Quit must return to Main Menu instead of quitting the process.")
	_expect(remote_source.contains("var session_result: Dictionary = await _ensure_playtime_session()"), "Leaderboard requests must recover a missing lease after a login/session race.")
	_expect(leaderboard_source.contains("request_game_leaderboard"), "Leaderboard remains owned by the canonical RemoteSync request path.")
	_expect(menu_source.contains("has_terms_session_acceptance") and menu_source.contains("production_acceptance"), "Main Menu Terms gate distinguishes debug sessions from production device acceptance.")
	_expect(menu_source.contains("get_node_or_null(\"VBoxContainer/OptionBtn\")"), "Options is gated before Terms acceptance.")
	_expect(menu_source.contains("get_node_or_null(\"VBoxContainer/QuitBtn\")"), "Quit is gated before Terms acceptance.")
	_expect(menu_scene_source.contains("node name=\"OptionBtn\""), "Main Menu exposes the Options control under the startup gate.")
	_expect(menu_scene_source.contains("node name=\"QuitBtn\""), "Main Menu exposes the Quit control under the startup gate.")
	_expect(menu_scene_source.contains("node name=\"TermsPrivacyButton\""), "Main Menu exposes Terms and Privacy review after acceptance.")
	_expect(menu_source.contains("get_node_or_null(\"VBoxContainer/TermsPrivacyButton\")"), "Main Menu resolves the Terms and Privacy review button at its real scene path.")
	_expect(new_game_source.contains("authoritative_start_cycle") and new_game_source.find("authoritative_start_cycle") < new_game_source.find("finalize_new_game_registration(true)"), "New Game finalization must retain the playtime-start response's authoritative learning cycle.")
	_expect(new_game_source.contains('"_force_refresh": true'), "New Game forces server lease revalidation after its earlier profile lookup.")
	_expect(load_game_source.contains("authoritative_start_cycle") and load_game_source.contains("annotate_save_learning_cycle(save_data, authoritative_start_cycle)"), "Load Game must revalidate the save against the playtime-start response's authoritative learning cycle.")
	_expect(load_game_source.contains('"_force_refresh": true'), "Load Game forces server lease revalidation after its earlier learning-cycle lookup.")
	_expect(load_game_source.contains("_ensure_terms_accepted_for_student") and load_game_source.find("_ensure_terms_accepted_for_student") < load_game_source.find("request_learning_cycle"), "Load Game must require the selected Student's Terms acceptance before starting gameplay requests.")
	_expect(remote_source.contains("_capture_playtime_lease_identity") and remote_source.contains("_lease_snapshot_matches_current"), "Late heartbeat/end responses are scoped to the lease that emitted them.")
	_expect(remote_source.contains("_playtime_timeout_pending"), "A start-time allowance denial remains pending until the session transition can process the timeout.")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var result := {"passed": _failures.is_empty(), "failures": _failures}
	var result_file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(result))
	if _failures.is_empty():
		print("live_defect_contract_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
