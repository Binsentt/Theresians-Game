extends "res://tools/preservation_restoration_test.gd"
## Canonical real-world route checks, isolated transport, and stale-save replay.
## Battle pointer checks are preserved from gameplay_battle_tree_audit.gd.

class PoolTransport extends Node:
	var requests: Array[Dictionary] = []
	var posts: Array[Dictionary] = []
	var post_status := 200
	func request_post(path: String, payload: Dictionary = {}) -> Dictionary:
		posts.append({"path":path, "payload":payload.duplicate(true)})
		await get_tree().process_frame
		return {"ok":post_status == 200, "status":post_status,
			"body":{"current_task_index":0, "quest_progress":0, "current_quest":"Go to the Teacher's House"}}
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
var counterfactual := false
var quest_observations: Array[Dictionary] = []

func _ready() -> void:
	# Fail closed if any test path tries to instantiate real HTTP transport.
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is HTTPRequest:
			node.free()
			push_error("Final fixture rejected a live HTTPRequest node")
			get_tree().quit(2)
	)
	_run.call_deferred()

func _run() -> void:
	get_node("/root/RemoteSync").free()
	get_node("/root/HttpApi").free()
	transport = PoolTransport.new()
	transport.name = "HttpApi"
	get_tree().root.add_child(transport)
	results = ResultCapture.new()
	results.name = "RemoteSync"
	get_tree().root.add_child(results)
	_expect(get_tree().root.find_children("*", "HTTPRequest", true, false).is_empty(), "No real HTTPRequest nodes exist before any fixture gameplay")
	_expect(get_node("/root/HttpApi") == transport and transport is PoolTransport, "Every HTTP operation resolves only to the in-memory transport")
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.fixture_path = "user://saves/final_world_quest_%d.json" % Time.get_ticks_usec()
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	_expect(get_node("/root/QuestionProvider").get_script().resource_path == "res://scripts/question_provider.gd", "Actual canonical QuestionProvider is active")
	await _quest_checkpoints()
	counterfactual = true
	await _actual_provider_encounter("female")
	counterfactual = false
	for gender in ["male", "female"]:
		await _actual_provider_encounter(gender)
	await _actual_provider_encounter("male", false)
	await _remote_quest_observer()
	await _timeout_return()
	var failed := 0
	for check in checks:
		if not check.passed:
			failed += 1
	var evidence := {"checks": checks, "passed": checks.size() - failed, "failed": failed,
		"quest_observations":quest_observations, "presentations": presentations, "question_requests": transport.requests,
		"recorded_answers": results.answers, "pointer_events": pointer_events, "live_network_calls": 0}
	var file := FileAccess.open("res://docs/qa/2026-09-07-final-battle-tree.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	print("FINAL_WORLD_QUEST_TEST " + JSON.stringify({"passed": checks.size() - failed, "failed": failed}))
	get_tree().quit(1 if failed else 0)

func _quest_checkpoints() -> void:
	state.start_new_game(PROFILE, false)
	await _roundtrip("during Tutorial", 0, HOUSE)
	_expect(state.is_tutorial_active() and state.current_quest == "Tutorial", "Tutorial save/load retains the active tutorial")
	var house := get_tree().current_scene
	var teacher := house.get_node("NPCTeacher")
	teacher.set_physics_process(false)
	teacher.start_tutorial()
	await _frames(4)
	var next := house.get_node("CanvasLayer/Panel/Button") as Button
	for index in 8:
		await _click_control(next)
	_expect(not state.is_tutorial_active() and state.current_task_index == 0, "Original Next sequence completes Tutorial without advancing Teacher House")
	await _roundtrip("after Tutorial", 0, HOUSE)
	_expect(state.current_quest == "Go to the Teacher's House", "Post-Tutorial objective remains source-supported Teacher House")
	# The existing arrival trigger, also used by the source-proven world flow.
	var oak := await _load(OAK)
	var arrival: Node = null
	for node in oak.find_children("*", "", true, false):
		var script = node.get_script()
		if script != null and script.resource_path == "res://world/task_progress_trigger.gd":
			arrival = node
			break
	_expect(arrival != null, "Original Teacher House arrival trigger remains bound")
	if arrival != null:
		var player := get_tree().get_first_node_in_group("player_character") as Node2D
		var saves_before: int = state.fixture_save_count
		arrival._on_body_entered(player)
		arrival._on_body_entered(player)
		_expect(state.current_task_index == 1 and state.fixture_save_count == saves_before + 1, "Teacher House arrival trigger advances and saves exactly once")
	await _roundtrip("Teacher House arrival", 1, TEACHER)
	await _teacher()
	_expect(state.current_task_index == 2, "Teacher final deliberate close exposes the First Bandit objective")
	await _roundtrip("Teacher conversation completed", 2, OAK)
	var stale: Dictionary = state.build_save_data()
	stale.current_task_index = 3
	stale.current_quest = "Go to the Teacher's House"
	var source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var reconciliation := "\t# Older saves can carry a completed checkpoint with an obsolete quest title.\n\t# The checkpoint is authoritative; reconcile presentation without replaying tasks.\n\tcurrent_quest = TUTORIAL_QUEST if is_tutorial_active() else (\n\t\tString(tasks[current_task_index].get(\"quest_text\", \"\")) if current_task_index < tasks.size() else DEFAULT_QUEST\n\t)\n"
	_expect(source.contains(reconciliation), "Existing focused stale-title restoration is present")
	var head_script := GDScript.new()
	head_script.source_code = source.replace(reconciliation, "")
	_expect(head_script.reload() == OK, "HEAD loader counterfactual compiles in memory")
	var old_state: Node = head_script.new()
	add_child(old_state)
	old_state.apply_save_data(stale, false)
	_expect(old_state.current_task_index == 3 and old_state.current_quest == "Go to the Teacher's House", "HEAD loader reproduces completed checkpoint with obsolete Teacher House quest")
	quest_observations.append({"case":"HEAD stale-save counterfactual", "index":old_state.current_task_index, "quest":old_state.current_quest})
	old_state.free()
	for checkpoint in [1, 2, 3]:
		stale.current_task_index = checkpoint
		state.apply_save_data(stale, false)
		var expected: String = state.tasks[checkpoint].quest_text if checkpoint < state.tasks.size() else state.DEFAULT_QUEST
		_expect(state.current_task_index == checkpoint and state.current_quest == expected, "Stale title is reconciled to authoritative checkpoint " + str(checkpoint))
		await _roundtrip("stale title at checkpoint " + str(checkpoint), checkpoint, OAK)
	_expect(not state.advance_task_and_save({}).advanced and state.current_task_index == 3, "Completed source-proven chain cannot duplicate or restart advancement")

func _roundtrip(label: String, checkpoint: int, scene_path: String) -> void:
	var expected: String = state.current_quest
	state.current_scene_path = scene_path
	var path: String = state.save_game()
	var saved: Dictionary = state._read_save_file(path)
	state.start_new_game(PROFILE, false)
	var loaded: Dictionary = state.load_save(path, false)
	_expect(not loaded.is_empty() and state.current_task_index == checkpoint and state.current_quest == expected, label + ": real serializer/file/loader retains authoritative checkpoint and title")
	var scene := await _load(scene_path)
	var hud := scene.get_node("GameHUD")
	var expected_hud := "" if expected == state.DEFAULT_QUEST else expected.strip_edges()
	_expect(hud._get_active_quest_text() == expected_hud and state.current_task_index == checkpoint, label + ": actual scene reload and HUD cannot reactivate an earlier objective")
	var rebuilt: Dictionary = state.build_save_data()
	var saved_keys := saved.keys()
	var rebuilt_keys := rebuilt.keys()
	saved_keys.sort()
	rebuilt_keys.sort()
	_expect(saved_keys == rebuilt_keys and saved.save_version == 8, label + ": existing save schema remains version 8 with identical keys")
	quest_observations.append({"case":label, "index":state.current_task_index, "quest":state.current_quest, "hud":hud._get_active_quest_text()})

func _install_head_dialogue(world: Node) -> void:
	var source := FileAccess.get_file_as_string("res://world/QuestUI.gd")
	var route := "\t\tvar battle_scene_path: String = current_task_data[\"next_scene\"]\n\t\tif GameState.gender == \"female\" and battle_scene_path == \"res://Battle/Battle-Enemy/male_vs_bandit.tscn\":\n\t\t\tbattle_scene_path = \"res://Battle/Battle-Enemy/female_vs_bandit.tscn\"\n\t\tvar battle_scene = load(battle_scene_path).instantiate()"
	var host := "\t# Ordinary NPC greetings still use this shared host after the last quest.\n\tupdate_task_ui()"
	_expect(source.contains(route) and source.contains(host), "Existing two focused QuestUI corrections are present")
	source = source.replace(route, "\t\tvar battle_scene = load(current_task_data[\"next_scene\"]).instantiate()")
	source = source.replace(host, "\tif GameState.current_task_index < GameState.tasks.size():\n\t\tupdate_task_ui()\n\telse:\n\t\tqueue_free()")
	var script := GDScript.new()
	script.source_code = source
	_expect(script.reload() == OK, "HEAD route and host counterfactual compiles in memory")
	var ui := world.get_node("CanvasLayer/Panel")
	ui.set_script(script)
	ui.quest_text = ui.get_node_or_null("QuestText")
	ui.dialogue_panel = world.get_node("CanvasLayer/DialoguePanel")
	ui.dialogue_label = world.get_node("CanvasLayer/DialoguePanel/DialogueLabel")

func _completed_greeting(world: Node) -> void:
	for actor_name in ["girl_npc", "NPC", "villager-female", "NPC1"]:
		var actor := world.get_node(actor_name)
		actor.set_physics_process(false)
		var player := get_tree().get_first_node_in_group("player_character") as Node2D
		player.global_position = Vector2(-4000, -4000)
		for frame in 4:
			await get_tree().physics_frame
		player.global_position = actor.find_child("Area2D", true, false).get_node("CollisionShape2D").global_position
		for frame in 5:
			await get_tree().physics_frame
		var ui := world.get_node("CanvasLayer/Panel")
		await _tap(world)
		_expect(ui.is_dialogue_active(), actor_name + ": after final battle the actual civilian greeting can still open")
		await _tap(world)
		_expect(not ui.is_dialogue_active() and state.current_task_index == 3 and not state.battle_active, actor_name + ": post-battle greeting closes once without replaying quest or battle")

func _remote_quest_observer() -> void:
	state.current_task_index = 3
	state.current_quest = state.DEFAULT_QUEST
	# Only the transport is substituted. The actual observer loads its own unique
	# empty queue, never the user's pending syncs or a real server lease.
	get_node("/root/RemoteSync").name = "AnswerCapture"
	var remote := Node.new()
	remote.set_script(load("res://scripts/remote_sync.gd"))
	remote.name = "RemoteSync"
	remote._pending_file = "user://final_remote_quest_%d.json" % Time.get_ticks_usec()
	get_tree().root.add_child(remote)
	remote.set_process(false)
	remote._current_playtime_session_id = 123
	remote._current_playtime_session_credential = "offline-fixture-credential"
	state.playtime_authorized = true
	for status in [200, 503]:
		transport.post_status = status
		await remote._async_send_progress(state.build_save_data())
		_expect(state.current_task_index == 3 and state.current_quest == state.DEFAULT_QUEST, "RemoteSync progress response " + str(status) + " cannot downgrade local authoritative quest")
	transport.post_status = 200
	await remote._flush_pending()
	var activities_before := transport.posts.filter(func(row: Dictionary) -> bool: return row.path == "/api/game/activity").size()
	await remote._submit_canonical_task_activity(2, 3, {"type":"task_completed", "reason":"battle_victory", "key":"quest:main:task:2:complete"})
	_expect(transport.posts.filter(func(row: Dictionary) -> bool: return row.path == "/api/game/activity").size() == activities_before + 1, "Actual RemoteSync activity endpoint receives exactly one fixture POST")
	await remote.record_question_attempt({"id":9100, "question_set_id":901, "grade":"Grade 1", "difficulty":"Easy"}, true)
	_expect(state.current_task_index == 3 and state.current_quest == state.DEFAULT_QUEST, "RemoteSync queue/activity/result stale response fields cannot reactivate Teacher House")
	for request in transport.posts:
		if request.path == "/api/game/progress":
			_expect(int(request.payload.get("quest_progress", request.payload.get("current_task_index", -1))) == 3 and request.payload.current_quest == state.DEFAULT_QUEST, "RemoteSync projects completed authoritative checkpoint")
	quest_observations.append({"case":"actual RemoteSync observer with stale response fixtures", "posts":transport.posts, "live_calls":0})
	remote.free()
	results.name = "RemoteSync"

func _actual_provider_encounter(gender: String, victory: bool = true) -> void:
	var profile: Dictionary = PROFILE.duplicate(true)
	profile.gender = gender
	state.start_new_game(profile, false)
	state.complete_tutorial_activity()
	state.current_task_index = 2
	state.current_quest = String(state.tasks[2].quest_text)
	var world := await _load(OAK)
	if counterfactual:
		_install_head_dialogue(world)
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
	var expected_scene := "res://Battle/Battle-Enemy/" + ("male" if counterfactual else gender) + "_vs_bandit.tscn"
	_expect(battle.scene_file_path == expected_scene, ("HEAD counterfactual reproduces female routed to male VS" if counterfactual else gender + ": original gender-matched VS scene is active"))
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
	var screenshot_path := "res://docs/qa/2026-09-07-final-original-" + gender + ("-head-counterfactual" if counterfactual else ("" if victory else "-defeat")) + "-bandit.png"
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
		_expect(world.has_node("CanvasLayer/Panel") != counterfactual, "HEAD counterfactual removes shared greeting host" if counterfactual else "Completed quest retains shared greeting host")
		if not counterfactual:
			await _completed_greeting(world)
	else:
		_expect(state.fixture_save_count == saves_before, "Defeat does not save a false task completion")
		_expect(state.current_task_index == 2 and state.encounter_context.retry_count == 1, "Defeat preserves the first Bandit checkpoint and retry contract")
	_expect(get_tree().current_scene == world and world.visible and not state.battle_active and world.get_node("MobileControls").visible, gender + ": original world destination, visibility and controller restore")
	if victory and not counterfactual:
		await _roundtrip("post-Bandit", 3, OAK)
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
	get_viewport().get_texture().get_image().save_png("res://docs/qa/2026-09-07-final-battle-timeout.png")
	var return_button := hud.get_node("GameOverOverlay/PanelContainer/VBoxContainer/ReturnButton") as Button
	var presses := [0]
	return_button.pressed.connect(func() -> void: presses[0] += 1)
	await _click_control(return_button)
	var timeout_deadline := Time.get_ticks_msec() + 2500
	while (get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://scenes/main_menu.tscn") and Time.get_ticks_msec() < timeout_deadline:
		await _frames(2)
	_expect(presses[0] == 1, "Actual timeout Return button receives exactly one pointer press")
	_expect(not get_tree().paused and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Actual timeout Return click reaches Main Menu and unpauses")
