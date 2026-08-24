extends Node

const HUD_SCENE := preload("res://ui/game_hud.tscn")
const TIME_LABEL_PATH := "TimeMargin/TimePanel/TimeLabel"
const QUEST_GUIDE_PATH := "QuestGuide"
const QUEST_LABEL_PATH := QUEST_GUIDE_PATH + "/QuestContent/QuestLabel"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud := HUD_SCENE.instantiate()
	get_tree().root.add_child(hud)
	await get_tree().process_frame

	var time_panel := hud.get_node_or_null("TimeMargin/TimePanel") as PanelContainer
	var time_label := hud.get_node_or_null(TIME_LABEL_PATH) as Label
	var quest_guide := hud.get_node_or_null(QUEST_GUIDE_PATH) as PanelContainer
	var quest_heading := hud.get_node_or_null(QUEST_GUIDE_PATH + "/QuestContent/Heading") as Label
	var quest_label := hud.get_node_or_null(QUEST_LABEL_PATH) as Label
	_expect(time_panel != null, "HUD must provide the compact overworld Time Left panel.")
	_expect(time_label != null, "HUD must provide a static Time Left label.")
	_expect(quest_guide != null, "HUD must provide the quest-guide container.")
	_expect(quest_heading != null and quest_heading.text == "CURRENT QUEST", "Quest guide must have a clear CURRENT QUEST heading.")
	_expect(quest_label != null, "Quest guide must provide QuestLabel.")
	_expect(hud.get_node_or_null("TimeMargin/PlayerPanel") == null, "Overworld HUD must not retain the HP panel.")
	_expect(hud.get_node_or_null("TimeMargin/TimePanel/LivesRow") == null, "Overworld HUD must not render exploration lives.")
	_expect(_read_fixture("res://ui/battle_life_display.tscn").contains("PlayerLivesRow"), "Battle hearts remain in the separate battle UI.")

	if time_label != null:
		GameState.configure_playtime_allowance({
			"daily_limit_minutes": 60,
			"remaining_seconds": 300,
			"can_play": true,
		}, true)
		hud.call("_update_playtime_label")
		_expect(time_label.text == "Time Left: 5 min", "HUD must keep the Time Left label working.")
		_expect(time_label.get_global_rect().size.x <= 180.0, "Time Left panel must remain compact.")
	if quest_guide != null:
		_expect(_rect_inside_viewport(quest_guide.get_global_rect()), "Quest guide must remain inside the viewport.")

	hud.queue_free()
	if _failures.is_empty():
		print("game_hud_runtime_test: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _rect_inside_viewport(rect: Rect2) -> bool:
	return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(rect)


func _read_fixture(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
