extends Control

const LEADERBOARD_FONT: FontFile = preload("res://Font/PressStart2P.ttf")
const ROW_HEIGHT := 44.0
const ROW_FONT_SIZE := 16

var _refresh_generation: int = 0


func _ready() -> void:
	_set_loading_state()
	await _refresh_leaderboard_from_api()


func refresh_leaderboard() -> void:
	await _refresh_leaderboard_from_api()


func _set_loading_state() -> void:
	_show_status("Loading leaderboard...")


func _set_empty_state() -> void:
	_show_status("No rankings yet")


func _set_connection_error_state() -> void:
	_show_status("Leaderboard unavailable")


func _show_status(message: String) -> void:
	_clear_rows()
	var rows_scroll := _rows_scroll()
	if rows_scroll != null:
		rows_scroll.visible = false
	var status_label := _status_label()
	if status_label != null:
		status_label.text = message
		status_label.visible = true


func _render_entries(entries: Array) -> void:
	var rows := _rows_container()
	var rows_scroll := _rows_scroll()
	if rows == null or rows_scroll == null:
		_set_connection_error_state()
		return

	_clear_rows()
	for entry: Variant in entries:
		var row_data := _normalized_row_data(entry)
		if row_data.is_empty():
			continue
		rows.add_child(_create_row(row_data))

	if rows.get_child_count() == 0:
		_set_empty_state()
		return

	var status_label := _status_label()
	if status_label != null:
		status_label.visible = false
	rows_scroll.visible = true
	rows_scroll.scroll_vertical = 0


func _normalized_row_data(entry: Variant) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var rank := int(entry.get("rank", 0))
	var display_name := str(entry.get("display_name", "")).strip_edges()
	if rank <= 0 or display_name.is_empty():
		return {}
	var grade := str(entry.get("grade", "")).strip_edges()
	return {
		"rank": "#%d" % rank,
		"display_name": display_name,
		"grade": grade if not grade.is_empty() else "--",
		"progress": _format_progress_percentage(entry.get("progress_percentage", null)),
	}


func _create_row(row_data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "LeaderboardRow"
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 18)
	row.add_child(_create_row_label("Rank", str(row_data["rank"]), 110.0))
	row.add_child(_create_row_label("DisplayName", str(row_data["display_name"]), 325.0))
	row.add_child(_create_row_label("Grade", str(row_data["grade"]), 195.0))
	row.add_child(_create_row_label("Progress", str(row_data["progress"]), 190.0))
	return row


func _create_row_label(label_name: String, value: String, minimum_width: float) -> Label:
	var label := Label.new()
	label.name = label_name
	label.custom_minimum_size = Vector2(minimum_width, ROW_HEIGHT)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_color_override(&"font_color", Color(0.8980392, 0.7529412, 0.41568628, 1.0))
	label.add_theme_color_override(&"font_shadow_color", Color(0.78039217, 0.627451, 0.30980393, 1.0))
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.99607843))
	label.add_theme_constant_override(&"outline_size", 5)
	label.add_theme_font_override(&"font", LEADERBOARD_FONT)
	label.add_theme_font_size_override(&"font_size", ROW_FONT_SIZE)
	return label


func _clear_rows() -> void:
	var rows := _rows_container()
	if rows == null:
		return
	for row in rows.get_children():
		row.free()


func _rows_scroll() -> ScrollContainer:
	return get_node_or_null("LeaderboardBG/LeaderboardRowsScroll") as ScrollContainer


func _rows_container() -> VBoxContainer:
	return get_node_or_null("LeaderboardBG/LeaderboardRowsScroll/LeaderboardRows") as VBoxContainer


func _status_label() -> Label:
	return get_node_or_null("LeaderboardBG/LeaderboardStatusLabel") as Label


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
	_render_entries(entries)


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
