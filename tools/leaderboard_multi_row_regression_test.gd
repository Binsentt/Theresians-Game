extends Node

const LEADERBOARD_SCENE := preload("res://leaderboard_scene.tscn")


class LocalLeaderboardStub extends Node:
	var entries: Array = []

	func request_game_leaderboard() -> Dictionary:
		return {"ok": true, "entries": entries.duplicate(true)}


var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
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
	stub.entries = [_entry(1, "Player One", "Grade 1", 50)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	var rows := _rows(leaderboard)
	_expect(rows != null, "Leaderboard owns one reusable row container below its existing column headers.")
	_expect(rows != null and rows.get_child_count() == 1, "One valid API entry renders exactly one leaderboard row.")
	_expect(_row_label(rows, 0, "Rank") == "#1", "The rendered row keeps the API rank.")
	_expect(_row_label(rows, 0, "DisplayName") == "Player One", "The rendered row keeps the privacy-safe display name.")
	_expect(_row_label(rows, 0, "Grade") == "Grade 1", "The rendered row keeps the grade label.")
	_expect(_row_label(rows, 0, "Progress") == "50%", "The rendered row keeps the formatted progress value.")

	stub.entries = [
		_entry(1, "Player One", "Grade 1", 50),
		_entry(2, "Player Two", "Grade 2", 75),
		_entry(3, "Player Three", "Grade 3", 87.5),
	]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	rows = _rows(leaderboard)
	_expect(rows != null and rows.get_child_count() == 3, "Three valid API entries render three independent reusable rows.")
	_expect(_row_label(rows, 2, "DisplayName") == "Player Three", "Later API entries remain visible instead of being discarded after entries[0].")
	_assert_rows_are_privacy_safe(rows)


func _assert_overflow_rows_scroll(leaderboard: Control, stub: LocalLeaderboardStub) -> void:
	stub.entries = []
	for rank in range(1, 8):
		stub.entries.append(_entry(rank, "Player %d" % rank, "Grade %d" % rank, rank * 10))
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
		_entry(1, "Player A", "Grade 1", 10),
		_entry(2, "Player A Two", "Grade 1", 20),
	]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	stub.entries = [_entry(1, "Player B", "Grade 4", 90)]
	await leaderboard.refresh_leaderboard()
	await get_tree().process_frame
	var rows := _rows(leaderboard)
	_expect(rows != null and rows.get_child_count() == 1, "Refresh removes stale rows before rendering the new collection.")
	_expect(_row_label(rows, 0, "DisplayName") == "Player B", "Refresh replaces Player A data with Player B data.")
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
			for column_name in ["Rank", "DisplayName", "Grade", "Progress"]:
				visible_text += (row.get_node_or_null(column_name) as Label).text
	_expect(not visible_text.contains("001234") and not visible_text.contains("009876"), "Leaderboard rows never render private parent or student identifiers.")


func _entry(rank: int, display_name: String, grade: String, progress: Variant) -> Dictionary:
	return {
		"rank": rank,
		"display_name": display_name,
		"grade": grade,
		"progress_percentage": progress,
		"student_id": "001234",
		"parent_id": "009876",
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("leaderboard_multi_row_regression_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
