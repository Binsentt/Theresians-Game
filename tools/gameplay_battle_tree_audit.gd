extends "res://tools/preservation_restoration_test.gd"

class PoolTransport extends Node:
	var requests: Array[Dictionary] = []
	func request_get(path: String, params: Dictionary = {}) -> Dictionary:
		requests.append({"path": path, "params": params.duplicate(true)})
		await get_tree().process_frame
		var questions: Array[Dictionary] = []
		for index in 6:
			questions.append({"id": 9000 + index, "question": "Backend fixture %d: 11 + 6 = ?" % index,
				"options": ["19", "17", "18", "16"], "correct_answer": "17",
				"grade_level": "Grade 1", "difficulty": "Easy", "learning_file_id": 901})
		return {"ok": true, "status": 200, "body": {"questions": questions}}

class ResultCapture extends Node:
	var answers: Array[Dictionary] = []
	func record_question_attempt(question: Dictionary, correct: bool) -> void:
		answers.append({"question": question.duplicate(true), "correct": correct})

var transport: PoolTransport
var results: ResultCapture
var presentations: Array[Dictionary] = []
var pointer_events: Array[Dictionary] = []

func _run() -> void:
	get_node("/root/RemoteSync").free()
	get_node("/root/HttpApi").free()
	transport = PoolTransport.new()
	transport.name = "HttpApi"
	get_tree().root.add_child(transport)
	results = ResultCapture.new()
	results.name = "RemoteSync"
	get_tree().root.add_child(results)
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	_expect(get_node("/root/QuestionProvider").get_script().resource_path == "res://scripts/question_provider.gd", "Actual canonical QuestionProvider is active")
	for gender in ["male", "female"]:
		await _actual_provider_encounter(gender)
	await _actual_provider_encounter("male", false)
	await _timeout_return()
	var failed := 0
	for check in checks:
		if not check.passed:
			failed += 1
	var evidence := {"checks": checks, "passed": checks.size() - failed, "failed": failed,
		"presentations": presentations, "question_requests": transport.requests,
		"recorded_answers": results.answers, "pointer_events": pointer_events, "live_network_calls": 0}
	var file := FileAccess.open("res://docs/qa/2026-09-07-gameplay-battle-tree.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	print("GAMEPLAY_BATTLE_TREE_AUDIT " + JSON.stringify({"passed": checks.size() - failed, "failed": failed}))
	get_tree().quit(1 if failed else 0)

func _actual_provider_encounter(gender: String, victory: bool = true) -> void:
	var profile: Dictionary = PROFILE.duplicate(true)
	profile.gender = gender
	state.start_new_game(profile, false)
	state.complete_tutorial_activity()
	state.current_task_index = 2
	state.current_quest = String(state.tasks[2].quest_text)
	var world := await _load(OAK)
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	player.set_physics_process(false)
	player.global_position = Vector2(-2000, -2000)
	for frame in 5:
		await get_tree().physics_frame
	player.global_position = world.get_node("Bandits/BanditTaskTrigger/CollisionShape2D").global_position
	for frame in 5:
		await get_tree().physics_frame
	await _tap(world)
	_expect(world.get_node("CanvasLayer/Panel").is_dialogue_active() and not state.battle_active, gender + ": first ACT opens the existing world dialogue")
	var saves_before: int = state.fixture_save_count
	var answers_before := results.answers.size()
	await _tap(world)
	await _frames(8)
	var battle: Node = state.get_current_battle_enemy()
	_expect(is_instance_valid(battle), gender + ": deliberate close enters actual battle")
	if not is_instance_valid(battle):
		return
	var expected_scene := "res://Battle/Battle-Enemy/" + gender + "_vs_bandit.tscn"
	_expect(battle.scene_file_path == expected_scene, gender + ": original gender-matched VS scene is active")
	var managers: Array[String] = []
	var question_labels: Array[String] = []
	var replacement_nodes: Array[String] = []
	for node in get_tree().root.find_children("*", "", true, false):
		var script = node.get_script()
		if script != null and script.resource_path == "res://Battle/Battle-Enemy/QuizManager.gd":
			managers.append(str(node.get_path()))
		if node is CanvasItem and node.is_visible_in_tree():
			if node.name == "QuestionLabel":
				question_labels.append(str(node.get_path()))
			if "QuestionContainer" in str(node.name) or "MultipleChoice" in str(node.name):
				replacement_nodes.append(str(node.get_path()))
	_expect(managers.size() == 1 and question_labels == [str(battle.get_node("CanvasLayer/Panel/QuestionLabel").get_path())], gender + ": exactly one active VS manager and visible original question label")
	_expect(replacement_nodes.is_empty(), gender + ": no active replacement QuestionContainer or MultipleChoice overlay")
	var question: Dictionary = battle.get("_current_question_data")
	_expect(String(question.get("question", "")).begins_with("Backend fixture"), gender + ": HTTP pool response passes through actual QuestionProvider into original UI")
	_expect(question.get("question_set_id") == 901 and question.get("difficulty") == "Easy", gender + ": normalized question retains set traceability and difficulty")
	var labels: Array[String] = []
	for choice_name in ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"]:
		var button := battle.get_node("CanvasLayer/Panel/" + choice_name) as Button
		labels.append(button.text)
		_expect(button.is_visible_in_tree() and not button.disabled, gender + ": original " + choice_name + " is visible and usable")
	_expect(labels.size() == 4 and labels[int(question.correct)] == "17", gender + ": exactly four normalized choices retain the backend correct answer")
	_expect(not world.get_node("MobileControls").visible, gender + ": world controller follows approved battle hide rule")
	var hud := world.get_node("GameHUD") as CanvasLayer
	var art_layer := battle.get_parent() as CanvasLayer
	var question_layer := battle.get_node("CanvasLayer") as CanvasLayer
	_expect(art_layer != null and hud.layer > art_layer.layer and hud.layer > question_layer.layer, gender + ": preserved HUD and timeout modal draw above all battle presentation")
	_expect(art_layer != null and question_layer.layer > art_layer.layer and not world.visible, gender + ": original questions draw above original art and the world canvas stays behind battle")
	var settings := hud.get_node("Settings-Ingame")
	await _click_control(settings.get_node("Settings-Logo-Button"))
	_expect(get_tree().paused and settings.get_node("SettingsPopup").visible, gender + ": actual pointer click reaches preserved Settings above battle")
	await _click_control(settings.get_node("SettingsPopup/TextureRect/X"))
	_expect(not get_tree().paused and state.battle_active, gender + ": actual Settings close returns to the same battle")
	for visual_path in ["Sprite2D", "player", "Bandit", "PlayerHealth/Hearts", "EnemyHealth/Hearts"]:
		var visual := battle.get_node(visual_path) as CanvasItem
		var screen_origin := visual.get_global_transform_with_canvas().origin
		_expect(get_viewport().get_visible_rect().has_point(screen_origin), gender + ": original " + visual_path + " is rendered inside the battle viewport")
		_expect(visual.get_canvas_transform().is_equal_approx(Transform2D.IDENTITY), gender + ": original " + visual_path + " is independent of the world camera")
	await RenderingServer.frame_post_draw
	var screenshot_path := "res://docs/qa/2026-09-07-gameplay-original-" + gender + ("" if victory else "-defeat") + "-bandit.png"
	_expect(get_viewport().get_texture().get_image().save_png(screenshot_path) == OK, gender + ": canonical original presentation capture saved")
	presentations.append({"gender": gender, "scene": battle.scene_file_path, "manager_paths": managers,
		"question_paths": question_labels, "replacement_paths": replacement_nodes, "choices": labels,
		"screenshot": screenshot_path})
	var completion_count := [0]
	battle.battle_finished.connect(func(_won: bool) -> void: completion_count[0] += 1)
	for answer in 3:
		var correct := int(battle.get("_current_question_data").correct)
		var selected := correct if victory else (correct + 1) % 4
		await _click_control(battle.get_node("CanvasLayer/Panel/" + ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"][selected]))
	# A further click during the terminal effect must not record another answer.
	battle.answer_selected(0)
	var deadline := Time.get_ticks_msec() + 4000
	while completion_count[0] == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _frames(6)
	_expect(completion_count[0] == 1 and results.answers.size() == answers_before + 3, gender + ": one terminal completion and one result per actual answer")
	if victory:
		_expect(state.fixture_save_count == saves_before + 1, gender + ": victory saves progression exactly once")
		_expect(state.current_task_index == state.tasks.size() and state.current_quest == state.DEFAULT_QUEST, gender + ": victory retains completed task checkpoint without Teacher House regression")
	else:
		_expect(state.fixture_save_count == saves_before, "Defeat does not save a false task completion")
		_expect(state.current_task_index == 2 and state.encounter_context.retry_count == 1, "Defeat preserves the first Bandit checkpoint and retry contract")
	_expect(get_tree().current_scene == world and world.visible and not state.battle_active and world.get_node("MobileControls").visible, gender + ": original world destination, visibility and controller restore")
	for request in transport.requests:
		_expect(request.path == "/api/game/questions" and request.params == {"grade": "Grade 1", "difficulty": "Easy"}, gender + ": actual provider keeps the exact Grade + Difficulty API and optional Topic contract")

func _click_control(control: Control) -> void:
	await RenderingServer.frame_post_draw
	var position := control.get_global_transform_with_canvas() * (control.size / 2.0)
	var event_record := {"target": str(control.get_path()), "position": str(position), "pressed": 0}
	if control is BaseButton:
		control.pressed.connect(func() -> void: event_record.pressed += 1, CONNECT_ONE_SHOT)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	var hovered := get_viewport().gui_get_hovered_control()
	event_record.hovered = str(hovered.get_path()) if hovered != null else "none"
	# Deliver a complete viewport click together: waiting between its edges lets
	# unrelated native desktop pointer motion cancel a synthetic held click.
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = position
		click.global_position = position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(click, true)
	await _frames(4)
	pointer_events.append(event_record)
	print("POINTER " + JSON.stringify(event_record))

func _timeout_return() -> void:
	state.start_new_game(PROFILE, false)
	state.complete_tutorial_activity()
	state.current_task_index = 2
	var world := await _load(OAK)
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	player.set_physics_process(false)
	player.global_position = world.get_node("Bandits/BanditTaskTrigger/CollisionShape2D").global_position
	for frame in 5:
		await get_tree().physics_frame
	await _tap(world)
	await _tap(world)
	await _frames(8)
	_expect(state.battle_active, "Timeout fixture enters the real original battle")
	var hud := world.get_node("GameHUD")
	# Deliver the actual HUD signal and pause state without a production lease.
	state.time_limit_reached.emit()
	get_tree().paused = true
	await _frames(3)
	_expect(hud.get_node("GameOverOverlay").visible, "Battle timeout keeps the existing return modal visible")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/2026-09-07-gameplay-battle-timeout.png")
	var return_button := hud.get_node("GameOverOverlay/PanelContainer/VBoxContainer/ReturnButton") as Button
	var presses := [0]
	return_button.pressed.connect(func() -> void: presses[0] += 1)
	await _click_control(return_button)
	var timeout_deadline := Time.get_ticks_msec() + 2500
	while (get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://scenes/main_menu.tscn") and Time.get_ticks_msec() < timeout_deadline:
		await _frames(2)
	_expect(presses[0] == 1, "Actual timeout Return button receives exactly one pointer press")
	_expect(not get_tree().paused and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Actual timeout Return click reaches Main Menu and unpauses")
