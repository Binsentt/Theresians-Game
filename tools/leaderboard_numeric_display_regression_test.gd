extends Node

const LEADERBOARD_SCENE := preload("res://leaderboard_scene.tscn")


class LocalLeaderboardStub extends Node:
	var entries: Array = []
	var request_count := 0

	func request_game_leaderboard() -> Dictionary:
		request_count += 1
		return {"ok": true, "entries": entries.duplicate(true)}


var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var real_remote_sync := get_tree().root.get_node_or_null("RemoteSync")
	if real_remote_sync != null:
		var provider_shaped := real_remote_sync.call("_sanitize_game_leaderboard_entries", [{
			"rank": "1",
			"display_name": "Player String",
			"progress_percentage": "98.00",
			"accuracy_rate": "90.00",
			"correct_answers": "9",
			"total_questions": "10",
			"quests_completed": "7",
		}]) as Array
		_expect(provider_shaped.size() == 1 and provider_shaped[0].get("progress_percentage") is float and is_equal_approx(provider_shaped[0].get("progress_percentage"), 98.0), "Provider-shaped decimal strings normalize to numeric leaderboard progress before UI rendering.")
		real_remote_sync.name = "LeaderboardNumericOriginalRemoteSync"

	var stub := LocalLeaderboardStub.new()
	stub.name = "RemoteSync"
	get_tree().root.add_child(stub)
	var leaderboard := LEADERBOARD_SCENE.instantiate() as Control
	get_tree().root.add_child(leaderboard)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(_status_label(leaderboard) == "No rankings yet", "Empty responses keep the truthful no-ranking state.")
	await _assert_numeric_progress_cases(leaderboard, stub)
	await _assert_refresh_replaces_visible_entry(leaderboard, stub)
	await _assert_missing_and_unsupported_values(leaderboard, stub)
	_assert_visible_fields_are_privacy_safe(leaderboard)

	leaderboard.queue_free()
	stub.queue_free()
	if real_remote_sync != null:
		real_remote_sync.name = "RemoteSync"
	await get_tree().process_frame
	_finish()


func _assert_numeric_progress_cases(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	var cases: Array[Dictionary] = [
		{"value": 0, "expected": "0%"},
		{"value": 1, "expected": "1%"},
		{"value": 50, "expected": "50%"},
		{"value": 50.0, "expected": "50%"},
		{"value": 87.5, "expected": "87.5%"},
		{"value": "98.00", "expected": "98%"},
	]
	for case_data in cases:
		stub.entries = [_entry("Player Numeric", case_data["value"])]
		await leaderboard.refresh_leaderboard()
		await get_tree().process_frame
		_expect(
			_row_label(_rows(leaderboard), 0, "Progress") == String(case_data["expected"]),
			"Numeric progress %s renders as %s without a conversion error." % [str(case_data["value"]), String(case_data["expected"])]
		)


func _assert_refresh_replaces_visible_entry(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = [_entry("Player A", 50)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	stub.entries = [_entry("Player B", 87.5)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "DisplayName") == "Player B", "Refresh replaces the prior visible entry with the new response.")
	_expect(_row_label(_rows(leaderboard), 0, "Progress") == "87.5%", "Refresh renders the new numeric progress value.")
	_expect(stub.request_count >= 8, "Every numeric case and explicit refresh uses one local leaderboard request.")


func _assert_missing_and_unsupported_values(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = [_entry("Player Missing", null)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "Progress") == "--", "A null progress value uses the existing truthful fallback.")
	stub.entries = [{
		"rank": 1,
		"display_name": "Player Missing",
		"grade": "Grade 1",
	}]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "Progress") == "--", "A missing progress value uses the existing truthful fallback.")
	stub.entries = [_entry("Player Unsupported", [50])]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_row_label(_rows(leaderboard), 0, "Progress") == "--", "Unsupported progress values are not blindly stringified.")


func _assert_visible_fields_are_privacy_safe(leaderboard: Control) -> void:
	var visible_text := ""
	var rows := _rows(leaderboard)
	if rows != null:
		for row in rows.get_children():
			for column_name in ["Rank", "DisplayName", "Grade", "Progress"]:
				visible_text += (row.get_node_or_null(column_name) as Label).text
	_expect(not visible_text.contains("001234") and not visible_text.contains("009876"), "The game leaderboard never renders private IDs.")


func _entry(display_name: String, progress_value: Variant) -> Dictionary:
	return {
		"rank": 1,
		"display_name": display_name,
		"grade": "Grade 1",
		"progress_percentage": progress_value,
		"student_id": "001234",
		"parent_id": "009876",
	}


func _rows(leaderboard: Control) -> VBoxContainer:
	return leaderboard.get_node_or_null("LeaderboardBG/LeaderboardRowsScroll/LeaderboardRows") as VBoxContainer


func _status_label(leaderboard: Control) -> String:
	var label := leaderboard.get_node_or_null("LeaderboardBG/LeaderboardStatusLabel") as Label
	return label.text if label != null else ""


func _row_label(rows: VBoxContainer, row_index: int, label_name: String) -> String:
	if rows == null or row_index < 0 or row_index >= rows.get_child_count():
		return ""
	var label := rows.get_child(row_index).get_node_or_null(label_name) as Label
	return label.text if label != null else ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var evidence := {"passed": 13 - _failures.size(), "failed": _failures.size(), "failures": _failures}
	var output := FileAccess.open("res://docs/qa/leaderboard_numeric_display_regression_test.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(evidence, "\t"))
		output.close()
	if _failures.is_empty():
		print("leaderboard_numeric_display_regression_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
