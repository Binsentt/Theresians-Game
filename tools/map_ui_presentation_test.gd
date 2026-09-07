extends "res://tools/gameplay_battle_tree_audit.gd"

var observed: Array[Dictionary] = []
const VIEWPORTS := [Vector2i(1215, 545), Vector2i(844, 390), Vector2i(1280, 800)]

func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		get_node("/root/" + autoload_name).free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	for role in ["Tutorial", "Civilian", "Teacher", "Bandit"]:
		await _world_dialogue(role)
	await _timeout_presentation()
	var failed := checks.filter(func(c: Dictionary) -> bool: return not c.passed).size()
	var out := FileAccess.open("res://docs/qa/2026-09-07-map-ui-presentation.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"passed": checks.size() - failed, "failed": failed,
		"checks": checks, "observed": observed, "pointer_events": pointer_events, "live_requests": 0}, "\t"))
	out.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	print("MAP_UI_PRESENTATION_TEST " + JSON.stringify({"passed": checks.size() - failed, "failed": failed}))
	get_tree().quit(1 if failed else 0)

func _resize_window(dimensions: Vector2i) -> void:
	get_window().size = dimensions
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	_expect(get_window().size == dimensions, "Actual client size is " + str(dimensions))

func _world_dialogue(role: String) -> void:
	state.start_new_game(PROFILE, false)
	if role != "Tutorial":
		state.complete_tutorial_activity()
		state.current_task_index = 2 if role == "Bandit" else 1
	var scene := await _load(HOUSE if role == "Tutorial" else (TEACHER if role == "Teacher" else OAK))
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	player.set_physics_process(false)
	if role == "Tutorial":
		scene.get_node("NPCTeacher").set_physics_process(false)
		scene.get_node("NPCTeacher").start_tutorial()
	else:
		player.global_position = Vector2(-2000, -2000)
		for frame in 4:
			await get_tree().physics_frame
		var sensor: Node2D
		if role == "Civilian":
			scene.get_node("NPC").set_physics_process(false)
			sensor = scene.get_node("NPC/Visual/Area2D/CollisionShape2D")
		elif role == "Teacher":
			sensor = scene.get_node("Teacher/Area2D2/CollisionShape2D")
		else:
			sensor = scene.get_node("Bandits/BanditTaskTrigger/CollisionShape2D")
		player.global_position = sensor.global_position
		for frame in 5:
			await get_tree().physics_frame
		await _tap(scene)
	var panel := scene.get_node("CanvasLayer/Panel" if role == "Tutorial" else "CanvasLayer/DialoguePanel") as Control
	_expect(panel.is_visible_in_tree() and not state.battle_active, role + " actual interaction opens world dialogue only")
	for dimensions in VIEWPORTS:
		await _resize_window(dimensions)
		var rect := panel.get_global_rect()
		var viewport := panel.get_viewport_rect().size
		var act := _button(scene).get_global_rect()
		var label := role + " at " + str(dimensions)
		_expect(absf(rect.get_center().x - viewport.x * 0.5) < 1.0, label + " horizontally centered")
		if role == "Tutorial":
			_expect(absf(rect.get_center().y - viewport.y * 0.5) < 1.0, label + " approved Tutorial placement exception preserved")
		else:
			_expect(absf(viewport.y - rect.end.y - 40.0) < 1.5, label + " bottom-center with 40px margin")
		var original_height := viewport.y * 0.215 - 0.1749878 if role == "Tutorial" else (126.0 if role == "Teacher" else 80.0)
		_expect(absf(rect.size.y - original_height) < 1.5, label + " original box height preserved")
		var old_position := player.global_position
		player.global_position += Vector2(24, 0)
		await _frames(2)
		_expect(panel.get_global_rect() == rect, label + " independent of player/world position")
		player.global_position = old_position
		var data := {"role": role, "requested_window": str(dimensions), "actual_window": str(get_window().size),
			"viewport": str(viewport), "dialogue": str(rect), "act": str(act)}
		if role == "Tutorial":
			var next := panel.get_node("Button") as Control
			var shift := Vector2(0, viewport.y - 40.0 - rect.end.y)
			var projected_next := Rect2(next.get_global_rect().position + shift, next.size)
			data.projected_bottom_next = str(projected_next)
			data.projected_next_act_overlap = str(projected_next.intersection(act))
			_expect(not next.get_global_rect().intersects(act), label + " preserved Tutorial Next remains clear of ACT")
			# In-memory preview only, never saved to product source.
			var original_position := panel.position
			panel.position += shift
			await _capture_ui("tutorial-bottom-preview-" + str(dimensions.x))
			panel.position = original_position
		else:
			_expect(not rect.intersects(act), label + " dialogue clear of ACT")
			_expect(not _button(scene, "up").is_visible_in_tree() and _button(scene).is_visible_in_tree(), label + " approved dialogue control lifecycle")
		await _capture_ui(role.to_lower() + "-" + str(dimensions.x))
		observed.append(data)
	# Closing a civilian greeting exercises the same one-line/final-close host.
	if role == "Civilian":
		await _tap(scene)
		_expect(not panel.visible and not state.battle_active, "Civilian final deliberate close remains one interaction")

func _timeout_presentation() -> void:
	state.start_new_game(PROFILE, false)
	state.complete_tutorial_activity()
	var scene := await _load(OAK)
	var hud := scene.get_node("GameHUD")
	var panel := hud.get_node("GameOverOverlay/PanelContainer") as Control
	var heading := panel.get_node("VBoxContainer/Label") as Label
	var description := panel.get_node("VBoxContainer/Description") as Label
	var button := panel.get_node("VBoxContainer/ReturnButton") as Button
	var old_style := panel.get_theme_stylebox("panel")
	var old_minutes: int = state.playtime_limit_minutes
	_expect(heading.text == "GAME OVER" and heading.get_theme_font_size("font_size") == 20, "Normal game-over presentation remains original before timeout")
	state.time_limit_reached.emit()
	get_tree().paused = true
	for dimensions in VIEWPORTS:
		await _resize_window(dimensions)
		var viewport := panel.get_viewport_rect().size
		var rect := panel.get_global_rect()
		_expect(rect.size.is_equal_approx(Vector2(420, 228)), "Timeout modest panel size at " + str(dimensions))
		_expect(rect.get_center().is_equal_approx(viewport * 0.5), "Timeout preserves center at " + str(dimensions))
		_expect(heading.get_theme_font_size("font_size") == 22 and description.get_theme_font_size("font_size") == 11 and button.get_theme_font_size("font_size") == 13, "Timeout modest font sizes at " + str(dimensions))
		_expect(heading.text == "TIME LIMIT REACHED" and description.text == "Daily playtime allowance is complete." and button.text == "RETURN TO MAIN MENU", "Timeout exact wording preserved")
		_expect(panel.get_theme_stylebox("panel") == old_style and state.playtime_limit_minutes == old_minutes, "Timeout original style and time duration preserved")
		_expect(rect.get_area() < viewport.x * viewport.y * 0.28, "Timeout occupies a modest viewport area")
		observed.append({"role":"Timeout", "requested_window":str(dimensions), "actual_window":str(get_window().size), "viewport":str(viewport), "panel":str(rect), "heading_font":heading.get_theme_font_size("font_size")})
		await _capture_ui("timeout-" + str(dimensions.x))
	await _click_control(button)
	var deadline := Time.get_ticks_msec() + 3000
	while (get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://scenes/main_menu.tscn") and Time.get_ticks_msec() < deadline:
		await _frames(2)
	_expect(not get_tree().paused and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Timeout real Return click unpauses and reaches Main Menu")

func _capture_ui(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/2026-09-07-map-ui-" + label + ".png")
