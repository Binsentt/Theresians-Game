extends Control

var _refresh_generation: int = 0


func _ready() -> void:
	_set_loading_state()
	await _refresh_leaderboard_from_api()


func refresh_leaderboard() -> void:
	await _refresh_leaderboard_from_api()


func _set_loading_state() -> void:
	_set_labels("LOADING", "...", "...", "...")


func _set_empty_state() -> void:
	_set_labels("--", "No rankings yet", "--", "--")


func _set_connection_error_state() -> void:
	_set_labels("--", "Leaderboard unavailable", "--", "--")


func _set_labels(rank: String, display_name: String, grade: String, progress: String) -> void:
	var number_label := get_node_or_null("LeaderboardBG/NumberLbl") as Label
	var name_label := get_node_or_null("LeaderboardBG/NameLbl") as Label
	var grade_label := get_node_or_null("LeaderboardBG/GradeLbl") as Label
	var percentage_label := get_node_or_null("LeaderboardBG/PercentageLbl") as Label
	if number_label != null:
		number_label.text = rank
	if name_label != null:
		name_label.text = display_name
	if grade_label != null:
		grade_label.text = grade
	if percentage_label != null:
		percentage_label.text = progress


func _refresh_leaderboard_from_api() -> void:
	_refresh_generation += 1
	var request_generation := _refresh_generation
	_set_loading_state()
	var remote_sync := get_node_or_null("/root/RemoteSync")
	if remote_sync == null or not remote_sync.has_method("request_game_leaderboard"):
		if request_generation == _refresh_generation:
			_set_connection_error_state()
		return

	var result: Dictionary = await remote_sync.request_game_leaderboard()
	if request_generation != _refresh_generation:
		return
	if not bool(result.get("ok", false)):
		_set_connection_error_state()
		return
	var entries: Variant = result.get("entries", [])
	if not (entries is Array) or entries.is_empty():
		_set_empty_state()
		return

	var first: Variant = entries[0]
	if not (first is Dictionary):
		_set_empty_state()
		return
	var rank := int(first.get("rank", 0))
	var display_name := String(first.get("display_name", "")).strip_edges()
	if rank <= 0 or display_name.is_empty():
		_set_empty_state()
		return
	var grade := String(first.get("grade", "")).strip_edges()
	var progress_value: Variant = first.get("progress_percentage", null)
	var progress := _format_progress_percentage(progress_value)
	_set_labels("#%d" % rank, display_name, grade if not grade.is_empty() else "--", progress)


func _format_progress_percentage(progress_value: Variant) -> String:
	if progress_value is int:
		return "%d%%" % progress_value
	if progress_value is float:
		var progress_float: float = progress_value
		if not is_finite(progress_float):
			return "--"
		if is_equal_approx(progress_float, roundf(progress_float)):
			return "%d%%" % int(roundf(progress_float))
		return "%s%%" % str(progress_float)
	return "--"
