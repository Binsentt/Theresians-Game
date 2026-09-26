extends Node

const HUD_SCENE := preload("res://ui/game_hud.tscn")
const HUD_HOST_SCRIPT := preload("res://scripts/scene_hud_host.gd")
const TIME_HEADER_PATH := "TimeMargin/TimePanel/TimeContent/TimeHeader"
const TIME_LABEL_PATH := "TimeMargin/TimePanel/TimeContent/TimeLabel"
const TIME_PROGRESS_PATH := "TimeMargin/TimePanel/TimeContent/TimeProgress"
const QUEST_GUIDE_PATH := "QuestGuide"
const QUEST_HEADING_PATH := QUEST_GUIDE_PATH + "/QuestContent/HeadingRow/Heading"
const QUEST_LABEL_PATH := QUEST_GUIDE_PATH + "/QuestContent/QuestLabel"

var _failures: Array[String] = []
var _passes := 0
var _layout_observations: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var http := get_tree().root.get_node_or_null("HttpApi")
	var remote_sync := get_tree().root.get_node_or_null("RemoteSync")
	_expect(http != null and http.has_method("is_local_qa_mode") and bool(http.call("is_local_qa_mode")), "HUD runtime test selects the local-only API profile before autoload startup.")
	_expect(remote_sync != null and bool(remote_sync.get("local_qa_only")), "HUD runtime test disables telemetry and progress writes.")
	if not _failures.is_empty():
		await _finish()
		return

	var original_mode: Variant = GameState.get_mode()
	var original_task_index: int = GameState.current_task_index
	var original_quest: String = GameState.current_quest
	var original_journey_complete: bool = GameState.journey_complete
	var original_time_limit: int = GameState.playtime_limit_minutes
	var original_remaining_seconds: float = GameState.playtime_remaining_seconds
	var original_window_size := get_window().size
	GameState.journey_complete = false
	GameState.current_task_index = 1
	GameState.current_quest = GameState.get_current_quest_text()

	var hud := HUD_SCENE.instantiate() as CanvasLayer
	hud.name = "GameHUD"
	get_tree().current_scene.add_child(hud)
	var initial_guide := hud.get_node_or_null(QUEST_GUIDE_PATH) as Control
	if initial_guide != null:
		_layout_observations["after_add_child"] = _describe_quest_layout(hud, initial_guide)
	await get_tree().process_frame
	if initial_guide != null:
		_layout_observations["after_first_frame"] = _describe_quest_layout(hud, initial_guide)
	await get_tree().process_frame
	if initial_guide != null:
		_layout_observations["after_second_frame"] = _describe_quest_layout(hud, initial_guide)
	_expect(initial_guide != null and initial_guide.size.y <= 100.0, "Initial quest layout stays compact without a manual relayout.")

	_exercise_hud_structure(hud)
	_exercise_time_display(hud)
	var default_snapshot_error := await _save_runtime_snapshot("user://game_hud_visual_qa_default_20260926.png")
	_expect(default_snapshot_error == OK, "Default viewport HUD visual snapshot is saved to a new disposable user:// QA path.")
	await _exercise_quest_display(hud)
	await _exercise_responsive_layout(hud, original_window_size)
	await _exercise_notification_separation(hud)
	await _exercise_hud_singleton()

	GameState.current_task_index = original_task_index
	GameState.current_quest = original_quest
	GameState.journey_complete = original_journey_complete
	GameState.playtime_limit_minutes = original_time_limit
	GameState.playtime_remaining_seconds = original_remaining_seconds
	GameState.set_mode(original_mode)

	hud.queue_free()
	await get_tree().process_frame
	await _finish()


func _exercise_hud_structure(hud: CanvasLayer) -> void:
	var time_panel := hud.get_node_or_null("TimeMargin/TimePanel") as PanelContainer
	var time_header := hud.get_node_or_null(TIME_HEADER_PATH) as Label
	var time_label := hud.get_node_or_null(TIME_LABEL_PATH) as Label
	var time_progress := hud.get_node_or_null(TIME_PROGRESS_PATH) as ProgressBar
	var quest_guide := hud.get_node_or_null(QUEST_GUIDE_PATH) as PanelContainer
	var quest_heading := hud.get_node_or_null(QUEST_HEADING_PATH) as Label
	var quest_label := hud.get_node_or_null(QUEST_LABEL_PATH) as Label

	_expect(time_panel != null, "HUD provides the compact fantasy Time Left panel.")
	_expect(time_header != null and time_header.text == "TIME LEFT", "Time card has a clear small TIME LEFT header.")
	_expect(time_label != null, "Time card separates the large numeric countdown from its header.")
	_expect(time_progress != null and not time_progress.show_percentage, "Time card uses a real progress bar without a percentage label.")
	_expect(quest_guide != null, "HUD provides the persistent Current Quest panel.")
	_expect(quest_heading != null and quest_heading.text == "CURRENT QUEST", "Active story shows the CURRENT QUEST heading.")
	_expect(quest_label != null and quest_label.autowrap_mode != TextServer.AUTOWRAP_OFF, "Quest objective wraps instead of overflowing.")
	_expect(hud.has_method("_set_quest_text"), "Quest updates use a single change-aware presentation path.")
	_expect(hud.has_method("_quest_layout_for_viewport"), "Quest layout is calculated responsively from viewport dimensions.")
	_expect(hud.get_node_or_null("TimeMargin/PlayerPanel") == null, "Overworld HUD does not retain the HP panel.")
	_expect(hud.get_node_or_null("TimeMargin/TimePanel/LivesRow") == null, "Overworld HUD does not render exploration lives.")
	_expect(_read_fixture("res://ui/battle_life_display.tscn").contains("PlayerLivesRow"), "Battle hearts remain in the separate battle UI.")

	if time_panel != null:
		var time_rect := time_panel.get_global_rect()
		_expect(time_rect.size.x >= 170.0 and time_rect.size.x <= 200.0, "Time panel stays within the requested compact width.")
		_expect(time_rect.size.y >= 62.0 and time_rect.size.y <= 78.0, "Time panel stays within the requested compact height.")
	if quest_guide != null:
		_expect(_rect_inside_viewport(quest_guide.get_global_rect()), "Quest guide remains inside the actual viewport.")
		_expect(quest_guide.size.y <= 100.0, "A short quest uses a compact content-fit panel height (got %.1f)." % quest_guide.size.y)
		_layout_observations["default"] = _describe_quest_layout(hud, quest_guide)


func _exercise_time_display(hud: CanvasLayer) -> void:
	var time_label := hud.get_node_or_null(TIME_LABEL_PATH) as Label
	var time_progress := hud.get_node_or_null(TIME_PROGRESS_PATH) as ProgressBar
	var time_panel := hud.get_node_or_null("TimeMargin/TimePanel") as PanelContainer
	_expect(hud.has_method("_format_remaining_time"), "HUD exposes a tested MM:SS formatter.")
	_expect(hud.has_method("_time_visual_state"), "HUD exposes deterministic time-warning threshold selection.")
	if hud.has_method("_format_remaining_time"):
		_expect(String(hud.call("_format_remaining_time", 3600.0)) == "60:00", "3600 seconds display as 60:00.")
		_expect(String(hud.call("_format_remaining_time", 754.0)) == "12:34", "754 seconds display as 12:34.")
		_expect(String(hud.call("_format_remaining_time", 59.0)) == "00:59", "59 seconds display as 00:59.")
		_expect(String(hud.call("_format_remaining_time", 0.0)) == "00:00", "0 seconds display as 00:00.")
	if hud.has_method("_time_visual_state"):
		_expect(String(hud.call("_time_visual_state", 60, 901.0)) == "NORMAL", "More than 15 minutes uses the normal time visual.")
		_expect(String(hud.call("_time_visual_state", 60, 900.0)) == "WARNING_15", "15 minutes enters the first warning state.")
		_expect(String(hud.call("_time_visual_state", 60, 300.0)) == "WARNING_5", "5 minutes enters the stronger warning state.")
		_expect(String(hud.call("_time_visual_state", 60, 60.0)) == "CRITICAL_1", "1 minute enters the critical visual state.")
		_expect(String(hud.call("_time_visual_state", 0, 60.0)) == "DISABLED", "A disabled time limit uses the neutral state.")

	GameState.playtime_limit_minutes = 60
	GameState.playtime_remaining_seconds = 300.0
	hud.call("_update_playtime_label")
	if time_label != null:
		_expect(time_label.text == "05:00", "Live time display shows exact remaining MM:SS, not rounded minutes.")
	if time_progress != null:
		var expected_progress := (300.0 / 3600.0) * 100.0
		_expect(absf(time_progress.value - expected_progress) <= 0.02, "Progress bar reflects remaining seconds divided by the configured limit (got %.3f; expected %.3f)." % [time_progress.value, expected_progress])

	var normal_style_id := -1
	if time_panel != null:
		normal_style_id = time_panel.get_theme_stylebox("panel").get_instance_id()
	hud.call("_update_playtime_label")
	if time_panel != null:
		_expect(time_panel.get_theme_stylebox("panel").get_instance_id() == normal_style_id, "Unchanged timer frames reuse the existing panel style resource.")

	GameState.playtime_limit_minutes = 0
	hud.call("_update_playtime_label")
	if time_label != null:
		_expect(time_label.text == "--:--", "Disabled playtime limits display a clean --:-- value.")
	if time_progress != null:
		_expect(is_equal_approx(time_progress.value, 0.0), "Disabled playtime limits do not leave an invalid progress value.")
	GameState.playtime_limit_minutes = 60
	GameState.playtime_remaining_seconds = 300.0
	hud.call("_update_playtime_label")


func _exercise_quest_display(hud: CanvasLayer) -> void:
	var quest_guide := hud.get_node_or_null(QUEST_GUIDE_PATH) as PanelContainer
	var quest_heading := hud.get_node_or_null(QUEST_HEADING_PATH) as Label
	var quest_label := hud.get_node_or_null(QUEST_LABEL_PATH) as Label
	if quest_guide == null or quest_heading == null or quest_label == null:
		return

	var original_index: int = GameState.current_task_index
	var original_quest := GameState.current_quest
	var original_journey_complete: bool = GameState.journey_complete
	GameState.journey_complete = false
	GameState.current_task_index = 1
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.quest_changed.emit(GameState.current_quest)
	await get_tree().process_frame
	var first_quest := quest_label.text
	GameState.current_task_index = 2
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.quest_changed.emit(GameState.current_quest)
	await get_tree().process_frame
	_expect(not first_quest.is_empty() and quest_label.text == GameState.current_quest.strip_edges() and quest_label.text != first_quest, "A real GameState quest change updates the displayed objective (first='%s', state='%s', display='%s', index=%d)." % [first_quest, GameState.current_quest, quest_label.text, GameState.current_task_index])

	var active_tween: Tween = hud.get("_quest_change_tween") as Tween
	var active_tween_id := active_tween.get_instance_id() if active_tween != null else -1
	GameState.quest_changed.emit(GameState.current_quest)
	GameState.quest_changed.emit(GameState.current_quest)
	var same_quest_tween: Tween = hud.get("_quest_change_tween") as Tween
	var same_quest_tween_id := same_quest_tween.get_instance_id() if same_quest_tween != null else -1
	_expect(active_tween != null and same_quest_tween_id == active_tween_id, "Repeated identical quest signals do not restart the change animation (first tween=%d, after repeats=%d)." % [active_tween_id, same_quest_tween_id])

	var long_objective := "Defeat the Bandits in the Deepest Forest, then continue to Pinehill Village and find someone who knows about the Wizard."
	_apply_quest_text(hud, long_objective)
	var narrow_layout: Dictionary = {}
	if hud.has_method("_quest_layout_for_viewport"):
		narrow_layout = hud.call("_quest_layout_for_viewport", Vector2(844.0, 509.0), long_objective)
	_expect(int(narrow_layout.get("line_count", 0)) >= 2, "Long objective is measured as wrapped lines at narrow game width.")
	_expect(quest_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Long objective uses normal word wrapping.")

	GameState.journey_complete = true
	GameState.current_task_index = GameState.tasks.size()
	GameState.current_quest = "Math Champion"
	GameState.quest_changed.emit(GameState.current_quest)
	await get_tree().process_frame
	_expect(quest_guide.visible and quest_heading.text == "ACHIEVEMENT" and quest_label.text == "Math Champion", "Completed journey keeps the HUD visible with the Math Champion achievement.")

	GameState.journey_complete = original_journey_complete
	GameState.current_task_index = original_index
	GameState.current_quest = original_quest
	GameState.quest_changed.emit(GameState.current_quest)
	await get_tree().process_frame


func _exercise_responsive_layout(hud: CanvasLayer, original_window_size: Vector2i) -> void:
	var sizes: Array[Vector2] = [
		Vector2(844.0, 509.0),
		Vector2(1215.0, 545.0),
		Vector2(1280.0, 720.0),
		Vector2(1920.0, 1080.0),
	]
	for viewport_size in sizes:
		var layout: Dictionary = hud.call("_quest_layout_for_viewport", viewport_size, "Return to the City of Knowledge") if hud.has_method("_quest_layout_for_viewport") else {}
		var quest_rect := Rect2(Vector2(layout.get("position", Vector2.ZERO)), Vector2(layout.get("size", Vector2.ZERO)))
		var screen_rect := Rect2(Vector2.ZERO, viewport_size)
		var time_rect := Rect2(Vector2(14.0, 12.0), Vector2(190.0, 74.0))
		_expect(screen_rect.encloses(quest_rect), "Quest panel fits within %dx%d viewport." % [int(viewport_size.x), int(viewport_size.y)])
		_expect(not quest_rect.intersects(time_rect), "Quest and time panels do not overlap at %dx%d." % [int(viewport_size.x), int(viewport_size.y)])

	get_window().size = Vector2i(844, 509)
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_quest_text(hud, "Defeat the Bandits in the Deepest Forest, then continue to Pinehill Village and find someone who knows about the Wizard.")
	await get_tree().process_frame
	var quest_guide := hud.get_node_or_null(QUEST_GUIDE_PATH) as PanelContainer
	var quest_label := hud.get_node_or_null(QUEST_LABEL_PATH) as Label
	if quest_guide != null and quest_label != null:
		_expect(_rect_inside_viewport(quest_guide.get_global_rect()), "Long objective card stays inside a resized 844x509 runtime viewport.")
		_expect(quest_label.get_line_count() >= 2, "Long objective visibly wraps in the narrow runtime viewport.")
		_layout_observations["narrow"] = _describe_quest_layout(hud, quest_guide)
		var narrow_snapshot_error := await _save_runtime_snapshot("user://game_hud_visual_qa_20260926.png")
		_expect(narrow_snapshot_error == OK, "Narrow viewport HUD visual snapshot is saved to a new disposable user:// QA path.")
	get_window().size = original_window_size
	await get_tree().process_frame
	if hud.has_method("_layout_hud"):
		hud.call("_layout_hud")


func _exercise_notification_separation(hud: CanvasLayer) -> void:
	var manager := get_tree().root.get_node_or_null("QuestNotificationManager")
	var quest_guide := hud.get_node_or_null(QUEST_GUIDE_PATH) as PanelContainer
	_expect(manager != null, "Quest notifications continue to use the existing shared manager.")
	if manager == null or quest_guide == null:
		return

	_apply_quest_text(hud, "Return to the City of Knowledge")
	if hud.has_method("_layout_hud"):
		hud.call("_layout_hud")
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	manager.call("_on_progression_session_reset", "hud_runtime_test")
	manager.call("show_task_completed", "Task Complete", "Return to the Teacher", "hud-runtime-task-complete")
	var layout_frames := 0
	var completion_panel := manager.get("_task_complete_panel") as Control
	while (not bool(manager.get("_is_showing")) or (completion_panel != null and not completion_panel.visible)) and layout_frames < 20:
		await get_tree().process_frame
		layout_frames += 1
	await get_tree().process_frame
	var quest_rect := quest_guide.get_global_rect()
	if completion_panel != null:
		_expect(completion_panel.visible, "Task completion notification is presented by the shared manager.")
		var completion_y := completion_panel.get_global_rect().position.y
		_expect(completion_y >= quest_rect.end.y + 10.0, "Task Complete appears below, not over, the persistent Current Quest card (notification y=%.1f, quest bottom=%.1f)." % [completion_y, quest_rect.end.y])
	manager.call("_on_progression_session_reset", "hud_runtime_test_cleanup")


func _exercise_hud_singleton() -> void:
	var scene_hud_host := HUD_HOST_SCRIPT.new() as Node
	get_tree().current_scene.add_child(scene_hud_host)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud_count := 0
	for child in get_tree().current_scene.get_children():
		if child.name == "GameHUD":
			hud_count += 1
	_expect(hud_count == 1, "SceneHudHost does not create a duplicate GameHUD instance.")
	scene_hud_host.queue_free()


func _rect_inside_viewport(rect: Rect2) -> bool:
	return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(rect)


func _describe_quest_layout(hud: CanvasLayer, guide: Control) -> Dictionary:
	var content := guide.get_node_or_null("QuestContent") as Control
	var label := guide.get_node_or_null("QuestContent/QuestLabel") as Label
	var viewport_size := get_viewport().get_visible_rect().size
	var calculated_layout: Dictionary = hud.call("_quest_layout_for_viewport", viewport_size, label.text) if hud.has_method("_quest_layout_for_viewport") and label != null else {}
	return {
		"viewport": viewport_size,
		"guide_position": guide.position,
		"guide_size": guide.size,
		"guide_global_rect": guide.get_global_rect(),
		"guide_offsets": {"left": guide.offset_left, "top": guide.offset_top, "right": guide.offset_right, "bottom": guide.offset_bottom},
		"guide_anchors": {"left": guide.anchor_left, "top": guide.anchor_top, "right": guide.anchor_right, "bottom": guide.anchor_bottom},
		"guide_minimum": guide.get_combined_minimum_size(),
		"content_size": content.size if content != null else Vector2.ZERO,
		"content_minimum": content.get_combined_minimum_size() if content != null else Vector2.ZERO,
		"label_size": label.size if label != null else Vector2.ZERO,
		"label_lines": label.get_line_count() if label != null else 0,
		"label_text": label.text if label != null else "<missing>",
		"calculated_layout": calculated_layout,
	}


func _save_runtime_snapshot(path: String) -> Error:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return ERR_UNAVAILABLE
	return image.save_png(path)


func _apply_quest_text(hud: CanvasLayer, text: String) -> void:
	if hud.has_method("_set_quest_text"):
		hud.call("_set_quest_text", text)
		return
	var guide := hud.get_node_or_null(QUEST_GUIDE_PATH) as Control
	var label := hud.get_node_or_null(QUEST_LABEL_PATH) as Label
	if guide != null:
		guide.visible = not text.is_empty()
	if label != null:
		label.text = text


func _read_fixture(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _expect(condition: bool, message: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(message)


func _finish() -> void:
	var result := {"passed": _passes, "failed": _failures.size(), "failures": _failures, "layout": _layout_observations}
	var result_file := FileAccess.open("user://game_hud_runtime_result_hud_20260926.json", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(result))
		result_file.close()
	await get_tree().create_timer(1.0).timeout
	if _failures.is_empty():
		print("game_hud_runtime_test: PASS (%d/%d)" % [_passes, _passes])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("game_hud_runtime_test: FAIL (%d/%d passed)" % [_passes, _passes + _failures.size()])
	get_tree().quit(1)
