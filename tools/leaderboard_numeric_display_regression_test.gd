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
		real_remote_sync.name = "LeaderboardNumericOriginalRemoteSync"

	var stub := LocalLeaderboardStub.new()
	stub.name = "RemoteSync"
	get_tree().root.add_child(stub)
	var leaderboard := LEADERBOARD_SCENE.instantiate() as Control
	get_tree().root.add_child(leaderboard)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(_label(leaderboard, "NameLbl") == "No rankings yet", "Empty responses keep the truthful no-ranking state.")
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
	]
	for case_data in cases:
		stub.entries = [_entry("Player Numeric", case_data["value"])]
		await leaderboard.refresh_leaderboard()
		await get_tree().process_frame
		_expect(
			_label(leaderboard, "PercentageLbl") == String(case_data["expected"]),
			"Numeric progress %s renders as %s without a conversion error." % [str(case_data["value"]), String(case_data["expected"])]
		)


func _assert_refresh_replaces_visible_entry(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = [_entry("Player A", 50)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	stub.entries = [_entry("Player B", 87.5)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_label(leaderboard, "NameLbl") == "Player B", "Refresh replaces the prior visible entry with the new response.")
	_expect(_label(leaderboard, "PercentageLbl") == "87.5%", "Refresh renders the new numeric progress value.")
	_expect(stub.request_count >= 8, "Every numeric case and explicit refresh uses one local leaderboard request.")


func _assert_missing_and_unsupported_values(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = [_entry("Player Missing", null)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_label(leaderboard, "PercentageLbl") == "--", "A null progress value uses the existing truthful fallback.")
	stub.entries = [{
		"rank": 1,
		"display_name": "Player Missing",
		"grade": "Grade 1",
	}]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_label(leaderboard, "PercentageLbl") == "--", "A missing progress value uses the existing truthful fallback.")
	stub.entries = [_entry("Player Unsupported", [50])]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	_expect(_label(leaderboard, "PercentageLbl") == "--", "Unsupported progress values are not blindly stringified.")


func _assert_visible_fields_are_privacy_safe(leaderboard: Control) -> void:
	var visible_text := "%s %s %s %s" % [
		_label(leaderboard, "NumberLbl"),
		_label(leaderboard, "NameLbl"),
		_label(leaderboard, "GradeLbl"),
		_label(leaderboard, "PercentageLbl"),
	]
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


func _label(leaderboard: Control, label_name: String) -> String:
	var label := leaderboard.get_node_or_null("LeaderboardBG/" + label_name) as Label
	return label.text if label != null else ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("leaderboard_numeric_display_regression_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
