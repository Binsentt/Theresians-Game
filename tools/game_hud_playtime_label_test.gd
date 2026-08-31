extends Node

const GAME_HUD_SCENE := preload("res://ui/game_hud.tscn")
const PLAYTIME_LABEL_PATH := "MarginContainer/PlayerPanel/VBoxContainer/PlaytimeLabel"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud := GAME_HUD_SCENE.instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var playtime_label := hud.get_node_or_null(PLAYTIME_LABEL_PATH) as Label
	var passed := playtime_label != null
	passed = _assert(passed, "Game HUD creates the playtime label") and passed
	if playtime_label != null:
		passed = _assert(playtime_label.visible, "Game HUD keeps the playtime label visible") and passed
		passed = _assert(playtime_label.get_theme_font_size("font_size") == 9, "Game HUD preserves the compact playtime font size") and passed

	hud.queue_free()
	if passed:
		print("[Game HUD Playtime Label Test] PASS")
	get_tree().quit(0 if passed else 1)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[Game HUD Playtime Label Test] %s" % message)
		return false
	return true
