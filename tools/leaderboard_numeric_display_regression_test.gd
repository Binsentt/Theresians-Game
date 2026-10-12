extends Node

const LEADERBOARD_SCENE := preload("res://leaderboard_scene.tscn")
class LocalLeaderboardStub extends Node:
	var entries: Array = []
	var request_count := 0
	var response_ok := true

	func request_game_leaderboard() -> Dictionary:
		request_count += 1
		return {"ok": response_ok, "entries": entries.duplicate(true)}


var _failures: Array[String] = []
var _check_count := 0
var _qa_save_directory := ""
var _created_qa_save_directory := false
var _previous_save_directory := ""
var _previous_identity: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_state := get_tree().root.get_node_or_null("GameState")
	if game_state == null:
		_expect(false, "The local leaderboard fixture requires the GameState autoload.")
		_finish()
		return
	game_state.enable_local_qa_mode()
	_previous_save_directory = String(game_state.get_save_directory())
	_previous_identity = {
		"student_id": game_state.student_id,
		"parent_id": game_state.parent_id,
		"player_name": game_state.player_name,
		"grade_level": game_state.grade_level,
		"device_installation_id": game_state.device_installation_id,
	}
	_qa_save_directory = "%s/leaderboard_display_%d_%d" % [
		game_state.LOCAL_QA_SAVE_DIRECTORY,
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	var absolute_qa_directory := ProjectSettings.globalize_path(_qa_save_directory)
	if DirAccess.dir_exists_absolute(absolute_qa_directory):
		_expect(false, "Refusing to reuse an existing leaderboard QA save directory.")
		_finish()
		return
	if DirAccess.make_dir_recursive_absolute(absolute_qa_directory) != OK:
		_expect(false, "Could not create the isolated leaderboard QA save directory.")
		_finish()
		return
	_created_qa_save_directory = true
	game_state.set("_save_directory", _qa_save_directory)
	game_state.student_id = ""
	game_state.parent_id = ""
	game_state.player_name = ""
	game_state.grade_level = ""
	game_state.device_installation_id = "leaderboard-display-qa-device"
	_expect(game_state.list_saves().is_empty(), "The isolated logged-out leaderboard fixture starts without a manual save.")

	var real_remote_sync := get_tree().root.get_node_or_null("RemoteSync")
	if real_remote_sync != null:
		var provider_shaped := real_remote_sync.call("_sanitize_game_leaderboard_entries", [{
			"rank": "1",
			"display_name": "Player String",
			"game_score": "88",
			"progress_percentage": "98.00",
			"accuracy_rate": "90.00",
			"correct_answers": "9",
			"total_questions": "10",
			"quests_completed": "7",
		}]) as Array
		_expect(provider_shaped.size() == 1 and (provider_shaped[0].get("correct_answers") is int or provider_shaped[0].get("correct_answers") is float) and is_equal_approx(float(provider_shaped[0].get("correct_answers")), 9.0), "Provider-shaped total-correct-answer data remains available for Game Score rendering.")
		real_remote_sync.name = "LeaderboardNumericOriginalRemoteSync"

	var stub := LocalLeaderboardStub.new()
	stub.name = "RemoteSync"
	get_tree().root.add_child(stub)
	var leaderboard := LEADERBOARD_SCENE.instantiate() as Control
	get_tree().root.add_child(leaderboard)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(_status_label(leaderboard) == "No leaderboard records yet.", "Empty responses show the approved no-records state before Student login.")
	_expect(stub.request_count == 1, "The leaderboard is fetched immediately with no Student identity and no manual save.")
	_assert_final_columns(leaderboard)
	await _assert_numeric_game_score_cases(leaderboard, stub)
	await _assert_refresh_replaces_visible_entry(leaderboard, stub)
	await _assert_missing_and_unsupported_values(leaderboard, stub)
	await _assert_connection_failure_state(leaderboard, stub)
	_assert_visible_fields_are_privacy_safe(leaderboard)

	leaderboard.queue_free()
	stub.queue_free()
	if real_remote_sync != null:
		real_remote_sync.name = "RemoteSync"
	await get_tree().process_frame
	_cleanup_qa_fixture(game_state)
	game_state.set("_save_directory", _previous_save_directory)
	for key in _previous_identity:
		game_state.set(key, _previous_identity[key])
	_finish()


func _cleanup_qa_fixture(_game_state: Node) -> void:
	if not _created_qa_save_directory:
		return
	var absolute_directory := ProjectSettings.globalize_path(_qa_save_directory)
	var directory := DirAccess.open(absolute_directory)
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
			file_name = directory.get_next()
		directory.list_dir_end()
		DirAccess.remove_absolute(absolute_directory)
	_created_qa_save_directory = false


func _assert_numeric_game_score_cases(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	var cases: Array[Dictionary] = [
		{"value": 0, "expected": "0"},
		{"value": 1, "expected": "1"},
		{"value": 50, "expected": "50"},
		{"value": 50.0, "expected": "50"},
		{"value": "9", "expected": "9"},
	]
	for case_data in cases:
		stub.entries = [_entry("Player Numeric", case_data["value"], 98, 12)]
		await leaderboard.refresh_leaderboard()
		await get_tree().process_frame
		_expect(
			_row_label(_rows(leaderboard), 0, "GameScore") == String(case_data["expected"]),
			"Canonical total correct-answer count %s renders as %s independently from progress and accuracy." % [str(case_data["value"]), String(case_data["expected"])]
		)


func _assert_refresh_replaces_visible_entry(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = [_entry("Player A", 11, 44, 19)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	stub.entries = [_entry("Player B", 22, 76, 38)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "DisplayName") == "Player B", "Refresh replaces the prior visible entry with the new response.")
	_expect(_row_label(_rows(leaderboard), 0, "GameScore") == "22", "Refresh renders the new canonical total-correct-answer count.")
	_expect(stub.request_count >= 8, "Every numeric case and explicit refresh uses one local leaderboard request.")


func _assert_missing_and_unsupported_values(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = [_entry("Player Missing", null, 99, 10)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "GameScore") == "--", "A null canonical total-correct-answer count uses a truthful fallback.")
	stub.entries = [{
		"rank": 1,
		"display_name": "Player Missing",
		"grade": "Grade 1",
		"game_score": 500,
		"accuracy_rate": 99,
	}]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "GameScore") == "--", "Missing canonical correct-answer data is not inferred from game score or accuracy.")
	stub.entries = [_entry("Player Unsupported", [50], 80, 99)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "GameScore") == "--", "Unsupported total-correct-answer values are not blindly stringified.")
	stub.entries = [_entry("Player Fractional", 50.5, 80, 99)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "GameScore") == "--", "Fractional correct-answer counts are not rendered as valid counts.")
	stub.entries = [_entry("Player Negative", -1, 80, 99)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "GameScore") == "--", "Negative correct-answer counts are not rendered as valid data.")


func _assert_connection_failure_state(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.response_ok = false
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_status_label(leaderboard) == "Leaderboard unavailable.", "Network failures show the approved unavailable state.")
	stub.response_ok = true


func _assert_visible_fields_are_privacy_safe(leaderboard: Control) -> void:
	var visible_text := ""
	var rows := _rows(leaderboard)
	if rows != null:
		for row in rows.get_children():
			for column_name in ["Rank", "DisplayName", "Grade", "GameScore"]:
				visible_text += (row.get_node_or_null(column_name) as Label).text
	_expect(not visible_text.contains("001234") and not visible_text.contains("009876"), "The game leaderboard never renders private IDs.")
	_expect(not visible_text.contains("98%") and not visible_text.contains("12%"), "Progress and Q&A percentages are not displayed as Game Score.")


func _entry(display_name: String, game_score_value: Variant, progress_value: Variant, accuracy_value: Variant) -> Dictionary:
	return {
		"rank": 1,
		"display_name": display_name,
		"grade": "Grade 1",
		"correct_answers": game_score_value,
		"progress_percentage": progress_value,
		"accuracy_rate": accuracy_value,
		"student_id": "001234",
		"parent_id": "009876",
	}


func _rows(leaderboard: Control) -> VBoxContainer:
	return leaderboard.get_node_or_null("LeaderboardBG/LeaderboardRowsScroll/LeaderboardRows") as VBoxContainer


func _status_label(leaderboard: Control) -> String:
	var label := leaderboard.get_node_or_null("LeaderboardBG/LeaderboardStatusLabel") as Label
	return label.text if label != null else ""


func _assert_final_columns(leaderboard: Control) -> void:
	var background := leaderboard.get_node_or_null("LeaderboardBG")
	var expected := {
		"NumberLbl": "NO.",
		"NameLbl": "NAME",
		"GradeLbl": "GRADE",
		"PercentageLbl": "GAME SCORE",
	}
	for node_name in expected:
		var label := background.get_node_or_null(node_name) as Label if background != null else null
		_expect(label != null and label.text == expected[node_name], "Leaderboard header %s uses the required %s label." % [node_name, expected[node_name]])


func _row_label(rows: VBoxContainer, row_index: int, label_name: String) -> String:
	if rows == null or row_index < 0 or row_index >= rows.get_child_count():
		return ""
	var label := rows.get_child(row_index).get_node_or_null(label_name) as Label
	return label.text if label != null else ""


func _expect(condition: bool, message: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var evidence := {"passed": _check_count - _failures.size(), "failed": _failures.size(), "failures": _failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa_test_artifacts"))
	var output := FileAccess.open("user://qa_test_artifacts/leaderboard_numeric_display_regression_test.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(evidence, "\t"))
		output.close()
	if _failures.is_empty():
		print("leaderboard_numeric_display_regression_test: %d/%d passed" % [_check_count, _check_count])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
