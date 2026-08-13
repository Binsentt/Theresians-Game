extends Control

const API_PATH := "/api/leaderboard/top-achievers"

func _ready() -> void:
	_set_loading_state()
	await _refresh_leaderboard_from_api()

func _set_loading_state() -> void:
	var number_label := get_node_or_null("LeaderboardBG/NumberLbl") as Label
	var name_label := get_node_or_null("LeaderboardBG/NameLbl") as Label
	var grade_label := get_node_or_null("LeaderboardBG/GradeLbl") as Label
	var percentage_label := get_node_or_null("LeaderboardBG/PercentageLbl") as Label
	if number_label != null:
		number_label.text = "LOADING"
	if name_label != null:
		name_label.text = "..."
	if grade_label != null:
		grade_label.text = "..."
	if percentage_label != null:
		percentage_label.text = "..."

func _set_empty_state() -> void:
	var number_label := get_node_or_null("LeaderboardBG/NumberLbl") as Label
	var name_label := get_node_or_null("LeaderboardBG/NameLbl") as Label
	var grade_label := get_node_or_null("LeaderboardBG/GradeLbl") as Label
	var percentage_label := get_node_or_null("LeaderboardBG/PercentageLbl") as Label
	if number_label != null:
		number_label.text = "--"
	if name_label != null:
		name_label.text = "No results"
	if grade_label != null:
		grade_label.text = "--"
	if percentage_label != null:
		percentage_label.text = "--"

func _set_connection_error_state() -> void:
	var name_label := get_node_or_null("LeaderboardBG/NameLbl") as Label
	if name_label != null:
		name_label.text = "Connection Error"
	var number_label := get_node_or_null("LeaderboardBG/NumberLbl") as Label
	if number_label != null:
		number_label.text = "--"

func _refresh_leaderboard_from_api() -> void:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		print("Leaderboard: HttpApi unavailable; remote leaderboard not loaded")
		_set_connection_error_state()
		return

	var result: Dictionary = await http.request_get(API_PATH)
	if not result.get("ok", false):
		print("Leaderboard: API request failed: %s" % str(result))
		_set_connection_error_state()
		return
	if int(result.get("status", 0)) != 200:
		print("Leaderboard: unexpected API status %s" % str(result.get("status", 0)))
		_set_connection_error_state()
		return

	var rows: Array = []
	if typeof(result.get("body", [])) == TYPE_ARRAY:
		rows = result.get("body", [])
	elif typeof(result.get("body", {})) == TYPE_DICTIONARY:
		var data: Dictionary = result.get("body", {})
		if data.has("data") and typeof(data.get("data", [])) == TYPE_ARRAY:
			rows = data.get("data", [])
		else:
			rows = []

	if rows.is_empty():
		print("Leaderboard: top achievers API returned no rows")
		_set_empty_state()
		return

	var rank_label := get_node_or_null("LeaderboardBG/NumberLbl") as Label
	if rank_label != null:
		rank_label.text = "NO."

	var owner_name := ""
	if rows.size() > 0:
		var first := rows[0] as Dictionary
		owner_name = String(first.get("student_name", "Unknown"))
		print("Leaderboard: loaded %d top achiever rows; top is %s" % [rows.size(), owner_name])

	var name_label := get_node_or_null("LeaderboardBG/NameLbl") as Label
	var grade_label := get_node_or_null("LeaderboardBG/GradeLbl") as Label
	var percentage_label := get_node_or_null("LeaderboardBG/PercentageLbl") as Label
	if name_label != null:
		name_label.text = owner_name
	if grade_label != null:
		grade_label.text = String(rows[0].get("grade_level", "--"))
	if percentage_label != null:
		var pm: Variant = rows[0].get("progress_percentage", rows[0].get("completion_percentage", 0))
		percentage_label.text = "%s%%" % String(pm)

	if rank_label != null:
		rank_label.text = "#1"
