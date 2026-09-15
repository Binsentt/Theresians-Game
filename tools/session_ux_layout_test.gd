extends Node

const VIEWPORTS := [
	Vector2i(1134, 509),
	Vector2i(1215, 545),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
]
const RESULT_PATH := "user://session_ux_layout_test_result.json"

var _checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	if http != null:
		_expect(bool(http.call("enable_local_qa_mode", "http://127.0.0.1:5000")), "QA test forces the API to loopback")
	if remote != null:
		remote.call("enable_local_qa_mode")
		_expect(bool(remote.get("local_qa_only")), "QA test disables production sync")

	var manager: Node = get_node_or_null("/root/QuestNotificationManager")
	var hud: Node = load("res://ui/game_hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	var settings := hud.get_node_or_null("Settings-Ingame") as Control
	var dialogue: Node = load("res://ui/progression_dialogue_overlay.tscn").instantiate()
	add_child(dialogue)
	await get_tree().process_frame

	for dimensions in VIEWPORTS:
		get_window().size = dimensions
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var viewport := get_viewport().get_visible_rect().size

		GameState.set_mode(GameState.GameMode.EXPLORATION)
		await manager.call("_show_event_panel", {
			"kind": "task_trigger", "title": "Task 2", "description": "Talk to the Teacher",
			"portrait_path": "res://Images/NPC.jpg", "accent": "blue",
		})
		var teacher_panel := manager.get_node("QuestNotificationLayer/TaskTriggerPanel") as Control
		var teacher_rect := teacher_panel.get_global_rect()
		_expect(absf(teacher_rect.get_center().x - viewport.x * 0.5) < 1.5, "Teacher task panel is horizontally centered at %s" % dimensions)
		_expect(absf(viewport.y - teacher_rect.end.y - 28.0) < 1.5, "Teacher task panel is bottom-positioned at %s" % dimensions)
		manager.call("_hide_all_panels_immediately")

		await manager.call("_show_event_panel", {
			"kind": "quest_updated", "title": "New Quest", "description": "Defeat All Bandits",
			"accent": "blue",
		})
		var toast := manager.get_node("QuestNotificationLayer/TaskCompletePanel") as Control
		var toast_rect := toast.get_global_rect()
		_expect(absf(toast_rect.position.y - 12.0) < 1.5, "Quest objective is a top toast at %s" % dimensions)
		_expect(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Quest toast is nonblocking at %s" % dimensions)
		manager.call("_hide_all_panels_immediately")

		var dialogue_panel := dialogue.get_node("DialoguePanel") as Control
		var dialogue_rect := dialogue_panel.get_global_rect()
		_expect(dialogue_rect.size.x >= minf(800.0, viewport.x - 300.0), "Shared dialogue is widened responsively at %s" % dimensions)
		_expect(absf(viewport.y - dialogue_rect.end.y - 40.0) < 1.5, "Shared dialogue remains bottom-positioned at %s" % dimensions)

		hud.call("_on_time_limit_reached")
		var daily_panel := hud.get_node("GameOverOverlay/PanelContainer") as Control
		var daily_rect := daily_panel.get_global_rect()
		var daily_heading := daily_panel.get_node("VBoxContainer/Label") as Label
		var daily_description := daily_panel.get_node("VBoxContainer/Description") as Label
		_expect(daily_rect.get_center().distance_to(viewport * 0.5) < 2.0, "Daily-limit modal is centered at %s" % dimensions)
		_expect(daily_rect.size.x <= minf(460.0, viewport.x * 0.9), "Daily-limit modal remains compact at %s" % dimensions)
		_expect(daily_heading.text == "DAILY PLAYTIME COMPLETE" and daily_description.text.contains("progress has been saved"), "Daily-limit modal confirms autosave at %s" % dimensions)
		hud.get_node("GameOverOverlay").visible = false
		InputManager.unlock_input("daily_time_limit")

		settings.call("_on_exit_pressed")
		var exit_dialog := settings.get_node("ExitConfirmationDialog") as ConfirmationDialog
		_expect(exit_dialog.title == "Return to Main Menu?", "Return confirmation title is correct at %s" % dimensions)
		_expect(exit_dialog.dialog_text.contains("progress will be saved"), "Return confirmation explains save behavior at %s" % dimensions)
		_expect(exit_dialog.get_ok_button().text == "YES / RETURN" and exit_dialog.get_cancel_button().text == "NO / CANCEL", "Return confirmation exposes both actions at %s" % dimensions)
		_expect(exit_dialog.get_theme_stylebox("panel") is StyleBoxFlat, "Return confirmation uses the game-styled panel at %s" % dimensions)
		exit_dialog.hide()

	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	var result_file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
		result_file.close()
	print("SESSION_UX_LAYOUT_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)
