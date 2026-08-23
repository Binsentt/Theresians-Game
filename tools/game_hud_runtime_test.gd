extends Node

const HUD_SCENE := preload("res://ui/game_hud.tscn")
const HUD_LABELS_PATH := "MarginContainer/PlayerPanel/VBoxContainer"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud := HUD_SCENE.instantiate()
	get_tree().root.add_child(hud)
	await get_tree().process_frame

	var labels := hud.get_node_or_null(HUD_LABELS_PATH) as VBoxContainer
	var quest_label := hud.get_node_or_null(HUD_LABELS_PATH + "/QuestLabel") as Label
	var playtime_label := hud.get_node_or_null(HUD_LABELS_PATH + "/PlaytimeLabel") as Label
	_expect(labels != null, "HUD must provide its label container.")
	_expect(quest_label != null, "HUD must provide QuestLabel.")
	_expect(playtime_label != null, "HUD must create exactly one PlaytimeLabel during initialization.")

	if labels != null and quest_label != null and playtime_label != null:
		_expect(
			playtime_label.get_theme_font("font") == quest_label.get_theme_font("font"),
			"PlaytimeLabel must use QuestLabel's effective theme font."
		)
		hud.call("_ensure_playtime_label")
		_expect(_count_named_children(labels, "PlaytimeLabel") == 1, "HUD must not create duplicate playtime labels.")

		GameState.configure_playtime_allowance({
			"daily_limit_minutes": 60,
			"remaining_seconds": 300,
			"can_play": true,
		}, true)
		hud.call("_update_playtime_label")
		_expect(playtime_label.text == "Time Left: 5 min", "HUD must keep the playtime status label working.")

	hud.queue_free()
	if _failures.is_empty():
		print("game_hud_runtime_test: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _count_named_children(parent: Node, node_name: String) -> int:
	var count := 0
	for child in parent.get_children():
		if child.name == node_name:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
