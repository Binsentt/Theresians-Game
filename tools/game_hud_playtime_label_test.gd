extends Node

const GAME_HUD_SCENE := preload("res://ui/game_hud.tscn")
const PLAYTIME_LABEL_PATH := "TimeMargin/TimePanel/TimeContent/TimeLabel"
const TIME_HEADER_PATH := "TimeMargin/TimePanel/TimeContent/TimeHeader"

var _passes := 0
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud := GAME_HUD_SCENE.instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var playtime_label := hud.get_node_or_null(PLAYTIME_LABEL_PATH) as Label
	var time_header := hud.get_node_or_null(TIME_HEADER_PATH) as Label
	var passed := playtime_label != null
	passed = _assert(passed, "Game HUD creates the Time Left label") and passed
	passed = _assert(time_header != null and time_header.text == "TIME LEFT", "Game HUD exposes a separate compact TIME LEFT header") and passed
	if playtime_label != null:
		passed = _assert(playtime_label.visible, "Game HUD keeps the Time Left label visible") and passed
		passed = _assert(playtime_label.text == "60:00" or playtime_label.text == "--:--", "Game HUD displays the remaining time in MM:SS format") and passed
		passed = _assert(playtime_label.get_theme_font_size("font_size") == 14, "Game HUD renders the exact MM:SS value at the updated readable size") and passed

	hud.queue_free()
	if passed:
		print("[Game HUD Playtime Label Test] PASS (%d/%d)" % [_passes, _passes])
	var result := FileAccess.open("user://game_hud_playtime_label_result_hud_20260926.json", FileAccess.WRITE)
	if result != null:
		result.store_string(JSON.stringify({"passed": _passes, "failed": _failures}))
		result.close()
	get_tree().quit(0 if passed else 1)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		_failures += 1
		printerr("[Game HUD Playtime Label Test] %s" % message)
		return false
	_passes += 1
	return true
