extends Node

const LEADERBOARD_SCENE := preload("res://leaderboard_scene.tscn")
const QA_STUDENT_ID := "88001018"
const QA_PARENT_ID := "880118"


class LocalLeaderboardStub extends Node:
	var entries: Array = []

	func request_game_leaderboard() -> Dictionary:
		return {"ok": true, "entries": entries.duplicate(true)}


var _failures: Array[String] = []
var _game_state: Node
var _qa_save_directory := ""
var _previous_save_directory := ""
var _previous_identity: Dictionary = {}
var _created_qa_directory := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_state = get_tree().root.get_node_or_null("GameState")
	if _game_state == null:
		_expect(false, "The isolated leaderboard fixture requires the GameState autoload.")
		_finish()
		return
	_previous_save_directory = String(_game_state.get_save_directory())
	_game_state.enable_local_qa_mode()
	_previous_identity = {
		"student_id": _game_state.student_id,
		"parent_id": _game_state.parent_id,
		"player_name": _game_state.player_name,
		"grade_level": _game_state.grade_level,
		"device_installation_id": _game_state.device_installation_id,
	}
	_qa_save_directory = "%s/leaderboard_multi_row_%d_%d" % [
		_game_state.LOCAL_QA_SAVE_DIRECTORY,
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	var absolute_qa_directory := ProjectSettings.globalize_path(_qa_save_directory)
	if DirAccess.dir_exists_absolute(absolute_qa_directory) or DirAccess.make_dir_recursive_absolute(absolute_qa_directory) != OK:
		_expect(false, "Could not create a new isolated leaderboard fixture directory.")
		_finish()
		return
	_created_qa_directory = true
	_game_state.set("_save_directory", _qa_save_directory)
	_game_state.student_id = QA_STUDENT_ID
	_game_state.parent_id = QA_PARENT_ID
	_game_state.player_name = "Leaderboard Multi Row QA"
	_game_state.grade_level = "Grade 2"
	_game_state.device_installation_id = "leaderboard-multi-row-qa-device"
	_expect(_game_state.save_manual_game().begins_with(_qa_save_directory + "/"), "An isolated local save anchors leaderboard rendering without a network request.")

	var real_remote_sync := get_tree().root.get_node_or_null("RemoteSync")
	if real_remote_sync != null:
		real_remote_sync.name = "LeaderboardMultiRowOriginalRemoteSync"

	var stub := LocalLeaderboardStub.new()
	stub.name = "RemoteSync"
	get_tree().root.add_child(stub)
	var leaderboard := LEADERBOARD_SCENE.instantiate() as Control
	get_tree().root.add_child(leaderboard)
	await get_tree().process_frame
	await get_tree().process_frame

	await _assert_one_and_three_rows(leaderboard, stub)
	await _assert_overflow_rows_scroll(leaderboard, stub)
	await _assert_refresh_replaces_all_rows(leaderboard, stub)

	leaderboard.queue_free()
	stub.queue_free()
	if real_remote_sync != null:
		real_remote_sync.name = "RemoteSync"
	await get_tree().process_frame
	_finish()


func _assert_one_and_three_rows(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = [_entry(1, "Ava Santos", "Grade 1", 50, 87)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	var rows := _rows(leaderboard)
	_expect(rows != null, "Leaderboard owns one reusable row container below its existing column headers.")
	_expect(rows != null and rows.get_child_count() == 1, "One valid API entry renders exactly one leaderboard row.")
	_expect(_row_label(rows, 0, "Rank") == "#1", "The rendered row keeps the API rank.")
	_expect(_row_label(rows, 0, "DisplayName") == "Ava Santos", "The rendered row keeps the canonical student name.")
	_expect(_row_label(rows, 0, "Grade") == "Grade 1", "The rendered row keeps the grade label.")
	_expect(_row_label(rows, 0, "GameScore") == "87", "The rendered row keeps the canonical game score.")

	stub.entries = [
		_entry(1, "Ava Santos", "Grade 1", 50, 87),
		_entry(2, "Noah Santos", "Grade 2", 75, 76),
		_entry(3, "Lia Santos", "Grade 3", 87.5, 65),
	]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	rows = _rows(leaderboard)
	_expect(rows != null and rows.get_child_count() == 3, "Three valid API entries render three independent reusable rows.")
	_expect(_row_label(rows, 2, "DisplayName") == "Lia Santos", "Later API entries remain visible instead of being discarded after entries[0].")
	_assert_rows_are_privacy_safe(rows)


func _assert_overflow_rows_scroll(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = []
	for rank in range(1, 8):
		stub.entries.append(_entry(rank, "Student %d" % rank, "Grade %d" % rank, rank * 10, rank * 5))
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	await get_tree().process_frame
	var rows := _rows(leaderboard)
	var scroll := leaderboard.get_node_or_null("LeaderboardBG/LeaderboardRowsScroll") as ScrollContainer
	_expect(rows != null and rows.get_child_count() == 7, "A longer collection retains every reusable row.")
	_expect(scroll != null and scroll.size.y > 0.0, "Leaderboard uses a bounded internal scroll region for rows.")
	if scroll != null:
		scroll.scroll_vertical = 60
		await get_tree().process_frame
		_expect(scroll.scroll_vertical > 0, "Leaderboard rows can scroll vertically when entries exceed the visible panel.")


func _assert_refresh_replaces_all_rows(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = [
		_entry(1, "Student A", "Grade 1", 10, 10),
		_entry(2, "Student A Two", "Grade 1", 20, 20),
	]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	stub.entries = [_entry(1, "Student B", "Grade 4", 90, 90)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	var rows := _rows(leaderboard)
	_expect(rows != null and rows.get_child_count() == 1, "Refresh removes stale rows before rendering the new collection.")
	_expect(_row_label(rows, 0, "DisplayName") == "Student B", "Refresh replaces Player A data with Player B data.")
	_expect(_row_label(rows, 1, "DisplayName").is_empty(), "No stale second row remains after a smaller refresh response.")


func _rows(leaderboard: Control) -> VBoxContainer:
	return leaderboard.get_node_or_null("LeaderboardBG/LeaderboardRowsScroll/LeaderboardRows") as VBoxContainer


func _row_label(rows: VBoxContainer, row_index: int, label_name: String) -> String:
	if rows == null or row_index < 0 or row_index >= rows.get_child_count():
		return ""
	var label := rows.get_child(row_index).get_node_or_null(label_name) as Label
	return label.text if label != null else ""


func _assert_rows_are_privacy_safe(rows: VBoxContainer) -> void:
	var visible_text := ""
	if rows != null:
		for row in rows.get_children():
			for column_name in ["Rank", "DisplayName", "Grade", "GameScore"]:
				visible_text += (row.get_node_or_null(column_name) as Label).text
	_expect(not visible_text.contains("001234") and not visible_text.contains("009876"), "Leaderboard rows never render private parent or student identifiers.")


func _entry(rank: int, display_name: String, grade: String, progress: Variant, game_score: Variant) -> Dictionary:
	return {
		"rank": rank,
		"display_name": display_name,
		"grade": grade,
		"progress_percentage": progress,
		"correct_answers": game_score,
		"student_id": "001234",
		"parent_id": "009876",
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	_cleanup_qa_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa_test_artifacts"))
	var report := FileAccess.open("user://qa_test_artifacts/leaderboard_multi_row_regression_test.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": 8 - _failures.size(), "failed": _failures.size(), "failures": _failures}, "\t"))
		report.close()
	if _failures.is_empty():
		print("leaderboard_multi_row_regression_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _cleanup_qa_fixture() -> void:
	if _game_state == null:
		return
	if _created_qa_directory:
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
			_created_qa_directory = false
	if not _previous_save_directory.is_empty():
		_game_state.set("_save_directory", _previous_save_directory)
	for key in _previous_identity:
		_game_state.set(key, _previous_identity[key])
