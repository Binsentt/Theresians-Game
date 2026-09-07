extends "res://tools/map_ui_presentation_test.gd"

var tutorial_observations: Array[Dictionary] = []

func _run() -> void:
	# Remove live transports before opening gameplay with isolated fixture state.
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		get_node("/root/" + autoload_name).free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.fixture_path = "user://saves/tutorial_lifecycle_%d.json" % Time.get_ticks_usec()
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	for dimensions in VIEWPORTS:
		await _tutorial_layout_at(dimensions)
	await _committed_controller_layout()
	await _committed_controller_layout(true)
	await _committed_controller_layout(false, true)
	await _committed_controller_layout(true, false, true)
	await _committed_controller_layout(false, true, true)
	for role in ["Civilian", "Teacher", "Bandit"]:
		await _world_dialogue(role)
	var failed := checks.filter(func(check: Dictionary) -> bool: return not check.passed).size()
	var result := {"passed":checks.size() - failed, "failed":failed, "checks":checks,
		"tutorial":tutorial_observations, "world":observed, "pointer_events":pointer_events,
		"live_network_calls":0, "canonical_root":ProjectSettings.globalize_path("res://")}
	var output := FileAccess.open("res://docs/qa/2026-09-07-tutorial-lifecycle-runtime.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	print("TUTORIAL_LAYOUT_LIFECYCLE_TEST " + JSON.stringify({"passed":checks.size() - failed, "failed":failed}))
	get_tree().quit(1 if failed else 0)

func _tutorial_layout_at(dimensions: Vector2i) -> void:
	await _resize_window(dimensions)
	state.start_new_game(PROFILE, false)
	var scene := await _load(HOUSE)
	var teacher := scene.get_node("NPCTeacher")
	teacher.set_physics_process(false)
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	player.set_physics_process(false)
	var panel := scene.get_node("CanvasLayer/Panel") as Control
	var next := panel.get_node("Button") as Button
	var portrait := panel.get_node("NPCImage") as TextureRect
	var instruction := panel.get_node("Image") as TextureRect
	var label := panel.get_node("TextLabel") as Label
	var controller := scene.get_node("MobileControls")
	var prefix := "Tutorial %s: " % dimensions
	_expect(not panel.visible, prefix + "panel initially closed")
	await _controls(scene)
	var controller_before := _controller_layout(scene)
	var original_style := panel.get_theme_stylebox("panel")
	var original_font := label.get_theme_font("font")
	var original_children := _child_layout(panel)
	_key(true, KEY_UP)
	await _frames(3)
	var keyboard_before: Vector2 = inputs.get_movement_vector()
	_key(false, KEY_UP)
	await _frames(2)
	_touch(scene, true, "up")
	await _frames(2)
	teacher.start_tutorial()
	await _frames(4)
	_expect(inputs.get_movement_vector() == Vector2.ZERO, prefix + "opening releases obstructing held D-pad")
	_touch(scene, false, "up")
	var expected := {"anchor_left":0.0, "anchor_top":0.785, "anchor_right":1.0, "anchor_bottom":1.0,
		"offset_left":4.0, "offset_top":0.1749878, "offset_right":0.0, "offset_bottom":0.0}
	for property in expected:
		_expect(is_equal_approx(float(panel.get(property)), expected[property]), prefix + "ZIP " + property)
	_expect(panel.position.is_equal_approx(Vector2(4, 428)) and panel.size.is_equal_approx(Vector2(1211, 117)), prefix + "original lower rectangle 4,428 / 1211x117")
	_expect(portrait.texture.resource_path == "res://Images/NPC.jpg" and portrait.get_global_rect().size.is_equal_approx(Vector2(140, 116)), prefix + "original Teacher image and drawn size")
	_expect(next.text == "Next" and next.size.is_equal_approx(Vector2(107.822, 39.852)), prefix + "original Next text and size")
	_expect(next.pressed.is_connected(Callable(teacher, "_on_button_pressed")), prefix + "original Next signal binding")
	_check_obstructions(scene, panel, prefix)
	var row := {"window":str(dimensions), "viewport":str(panel.get_viewport_rect().size), "panel":str(panel.get_global_rect()),
		"portrait":str(portrait.get_global_rect()), "next":str(next.get_global_rect()),
		"movement_hidden":not _button(scene, "up").is_visible_in_tree(), "act_hidden":not _button(scene).is_visible_in_tree()}
	tutorial_observations.append(row)
	await _capture_ui("tutorial-" + str(dimensions.x))
	var panel_before := panel.get_global_rect()
	player.position += Vector2(20, 10)
	teacher.position += Vector2(10, 10)
	await _frames(2)
	_expect(panel.get_global_rect() == panel_before, prefix + "viewport-relative independent of world position")
	inputs.lock_input("tutorial_layout_fixture")
	inputs.unlock_input("tutorial_layout_fixture")
	state.set_mode(state.GameMode.MENU)
	state.set_mode(state.GameMode.EXPLORATION)
	controller.configure(true)
	await _frames(2)
	_check_obstructions(scene, panel, prefix + "after normal visibility updates: ")
	get_window().size = Vector2i(960, 540)
	await _frames(4)
	_check_obstructions(scene, panel, prefix + "resize while open: ")
	get_window().size = dimensions
	await _frames(4)
	_expect(state.get_mode() == state.GameMode.EXPLORATION, prefix + "keyboard exploration mode preserved")
	_key(true, KEY_UP)
	await _frames(3)
	_expect(inputs.get_movement_vector() == keyboard_before, prefix + "keyboard movement behavior unchanged during dialogue")
	_key(false, KEY_UP)
	await _frames(2)
	_expect(scene.get_node("GameHUD")._get_active_quest_text() == "Tutorial", prefix + "Tutorial quest unchanged before completion")
	await _click_control(next)
	_expect(teacher.step == 1 and int(pointer_events.back().pressed) == 1, prefix + "real Next click advances exactly one line")
	await _frames(12)
	_expect(teacher.step == 1, prefix + "Next has no duplicate delayed advancement")
	_expect(instruction.texture != null and instruction.texture.resource_path == "res://Images/move.png", prefix + "original movement instruction image")
	await _capture_ui("tutorial-instruction-" + str(dimensions.x))
	_key(true)
	await _frames(12)
	_key(true, KEY_E, true)
	await _frames(3)
	_expect(teacher.step == 2, prefix + "held keyboard E and echo advance only one line")
	_key(false)
	await _frames(4)
	for expected_step in range(3, 8):
		await _click_control(next)
		_expect(teacher.step == expected_step and state.is_tutorial_active() and int(pointer_events.back().pressed) == 1, prefix + "one Next press reaches step " + str(expected_step))
	_expect(panel.visible and state.is_tutorial_active() and state.current_task_index == 0, prefix + "final line waits for deliberate close")
	_expect(original_children == _child_layout(panel) and panel.get_theme_stylebox("panel") == original_style and label.get_theme_font("font") == original_font, prefix + "all child geometry, artwork style and font preserved")
	await _click_control(next)
	_expect(teacher.step == 8 and not panel.visible and not state.is_tutorial_active() and state.current_task_index == 0, prefix + "final Next completes only Tutorial")
	_expect(scene.get_node("GameHUD")._get_active_quest_text() == "Go to the Teacher's House", prefix + "existing next quest appears after deliberate close")
	_expect(controller_before == _controller_layout(scene), prefix + "all control geometry/styles/visibility restored exactly")
	await _controls(scene)
	await _capture_ui("tutorial-closed-" + str(dimensions.x))
	# Leaving an open Tutorial must not suppress controls on the next scene.
	state.start_new_game(PROFILE, false)
	scene = await _load(HOUSE)
	teacher = scene.get_node("NPCTeacher")
	teacher.set_physics_process(false)
	teacher.start_tutorial()
	# Also cover a controller attached after the Tutorial is already open.
	scene.get_node("MobileControls").free()
	var replacement: Node = load("res://ui/mobile_controls.tscn").instantiate()
	replacement.name = "MobileControls"
	scene.add_child(replacement)
	await _frames(4)
	_check_obstructions(scene, scene.get_node("CanvasLayer/Panel"), prefix + "late controller attachment: ")
	state.complete_tutorial_activity()
	scene = await _load(HOUSE)
	_expect(not scene.get_node("CanvasLayer/Panel").visible and _button(scene).is_visible_in_tree() and _button(scene, "up").is_visible_in_tree(), prefix + "scene exit/reentry clears Tutorial-only suppression")

func _committed_controller_layout(act_only: bool = false, simultaneous_keyboard: bool = false, release_before_open: bool = false) -> void:
	# Source-proven d6180f4 geometry, applied only to this runtime fixture.
	# The working controller scene has separate pre-existing, uncommitted edits.
	await _resize_window(Vector2i(844, 390))
	state.start_new_game(PROFILE, false)
	var scene := await _load(HOUSE)
	var teacher := scene.get_node("NPCTeacher")
	teacher.set_physics_process(false)
	var controller := scene.get_node("MobileControls")
	var movement := controller.get_node("Root/MovementMargin") as Control
	var action := controller.get_node("Root/ActionMargin") as Control
	movement.offset_left = 20.0
	movement.offset_top = -300.0
	movement.offset_right = 272.0
	movement.offset_bottom = -20.0
	if act_only:
		# Isolate the user-requested ACT-only obstruction branch, in memory.
		movement.offset_top = -545.0
		movement.offset_bottom = -265.0
	action.offset_left = -232.0
	action.offset_top = -192.0
	action.offset_right = -20.0
	action.offset_bottom = -20.0
	for direction in ["up", "down", "left", "right"]:
		_button(scene, direction).custom_minimum_size = Vector2(76, 76)
	controller.get_node("Root/MovementMargin/MovementPanel/MovementBox/MiddleRow/CenterSpacer").custom_minimum_size = Vector2(30, 76)
	await _frames(4)
	var before := _controller_layout(scene)
	if act_only:
		_touch(scene, true, "up")
	_touch(scene, true)
	if simultaneous_keyboard:
		_key(true, KEY_SPACE)
	if release_before_open:
		_touch(scene, false)
		if simultaneous_keyboard:
			_key(false, KEY_SPACE)
	teacher.start_tutorial()
	await _frames(4)
	_expect(teacher.step == (1 if simultaneous_keyboard else 0) and inputs.is_interact_pressed() == (simultaneous_keyboard and not release_before_open), "Controller fixture: opening cancels mobile edge; keyboard=%s, released-before-open=%s" % [simultaneous_keyboard, release_before_open])
	_touch(scene, false)
	if simultaneous_keyboard:
		_key(false, KEY_SPACE)
		await _frames(4)
	if act_only:
		_expect(inputs.get_movement_vector() == Vector2.UP, "ACT-only fixture: nonobstructing held D-pad remains usable")
		_touch(scene, false, "up")
	var panel := scene.get_node("CanvasLayer/Panel") as Control
	_check_obstructions(scene, panel, "Committed controller fixture: ")
	_expect(movement.is_visible_in_tree() == act_only and not action.is_visible_in_tree() and _button(scene).disabled, "Controller overlap fixture: only obstructing portions hidden, ACT-only=" + str(act_only))
	await _capture_ui("controller-overlap-act-only-" + str(act_only) + "-keyboard-" + str(simultaneous_keyboard))
	var next := panel.get_node("Button") as Button
	for expected_step in range(2 if simultaneous_keyboard else 1, 9):
		if expected_step == 2:
			_key(true, KEY_SPACE)
			await _frames(12)
			_expect(teacher.step == 2, "Committed controller fixture: keyboard Space advances once while ACT hidden")
			_key(false, KEY_SPACE)
			await _frames(4)
		else:
			await _click_control(next)
			_expect(teacher.step == expected_step and int(pointer_events.back().pressed) == 1, "Committed controller fixture: one Next click reaches step " + str(expected_step))
	_expect(before == _controller_layout(scene), "Committed controller fixture: both controls restore exact geometry/style/state after close")
	await _controls(scene)

func _check_obstructions(scene: Node, panel: Control, prefix: String) -> void:
	for group in ["MovementMargin", "ActionMargin"]:
		var margin := scene.get_node("MobileControls/Root/" + group) as Control
		var overlaps := false
		for child_name in ["NPCImage", "Button"]:
			var target := panel.get_node(child_name) as Control
			overlaps = overlaps or margin.get_global_rect().intersects(target.get_global_rect())
		_expect(margin.is_visible_in_tree() != overlaps, prefix + group + " hides only if it obstructs portrait or Next")

func _child_layout(panel: Control) -> Dictionary:
	var result: Dictionary = {}
	for child in panel.get_children():
		if child is Control:
			var properties: Dictionary = {}
			for property in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom", "scale"]:
				properties[property] = child.get(property)
			result[child.name] = properties
	return result

func _controller_layout(scene: Node) -> Dictionary:
	var result: Dictionary = {}
	for direction in BUTTONS:
		var button := _button(scene, direction)
		result[direction] = {"rect":button.get_global_rect(), "visible":button.is_visible_in_tree(),
			"style":button.get_theme_stylebox("normal"), "scale":button.scale, "disabled":button.disabled}
	return result

func _capture_ui(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/2026-09-07-tutorial-lifecycle-" + label + ".png")
