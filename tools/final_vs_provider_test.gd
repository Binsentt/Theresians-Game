extends "res://tools/original_battle_presentation_test.gd"
## Canonical MCP fixture only. Specialized scene cases do not establish world routes.
## Retains actual QuestionProvider; removes live HTTP/results before any encounter.
## No account identity, new game, save/load, quest advancement or network is used.

const OUTPUT_PATH := "res://docs/qa/2026-09-07-final-vs-provider-runtime.json"
const FIXTURE_SET_ID := 170901
const FIXTURE_SCOPE := {"grade": "Grade 1", "difficulty": "Easy"}
const FIXTURE_CHOICES := ["19", "16", "17", "18"]


class PoolTransport extends Node:
	var requests: Array[Dictionary] = []

	func request_get(path: String, params: Dictionary = {}) -> Dictionary:
		requests.append({"path": path, "params": params.duplicate(true)})
		await get_tree().process_frame
		var questions: Array[Dictionary] = []
		for index in 6:
			questions.append({
				"id": 17090100 + index,
				"question": "Offline backend fixture %d: 11 + 6 = ?" % index,
				"options": ["19", "16", "17", "18"],
				"correct_answer": "17",
				"grade_level": "Grade 1",
				"difficulty": "Easy",
				"learning_file_id": 170901,
			})
		return {"ok": true, "status": 200, "body": {"questions": questions}}


class ResultCapture extends Node:
	var attempts: Array[Dictionary] = []

	func record_question_attempt(question: Dictionary, is_correct: bool) -> void:
		attempts.append({"question": question.duplicate(true), "is_correct": is_correct})


var _transport: PoolTransport
var _capture: ResultCapture
var _pointers: Array[Dictionary] = []
var _run_stamp := ""
var _output_path := OUTPUT_PATH

func _ready() -> void:
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is HTTPRequest:
			node.free()
			push_error("VS fixture rejected a live HTTPRequest node")
			get_tree().quit(2)
	)
	_run.call_deferred()

func _run() -> void:
	_run_stamp = "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	if FileAccess.file_exists(_output_path):
		_output_path = OUTPUT_PATH.get_basename() + "-" + _run_stamp + ".json"
	_game_state = get_node("/root/GameState")
	# These are the only network-capable roots involved in the tested boundary.
	# Remove them before setting even a fixture encounter context.
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	_expect(_game_state.student_id.is_empty() and _game_state.parent_id.is_empty(), "fixture starts without an account identity")
	if not _game_state.student_id.is_empty() or not _game_state.parent_id.is_empty():
		_finish()
		return
	_transport = PoolTransport.new()
	_transport.name = "HttpApi"
	get_tree().root.add_child(_transport)
	_capture = ResultCapture.new()
	_capture.name = "RemoteSync"
	get_tree().root.add_child(_capture)
	var provider := get_node_or_null("/root/QuestionProvider")
	var provider_script: Script = provider.get_script() as Script if provider != null else null
	var provider_is_real: bool = provider_script != null and provider_script.resource_path == "res://scripts/question_provider.gd"
	_expect(provider_is_real, "actual canonical QuestionProvider is retained")
	_expect(get_node("/root/HttpApi") == _transport and get_node("/root/RemoteSync") == _capture, "all question and result transport is isolated before battle")
	if not provider_is_real:
		_finish()
		return
	for case_data in CASES:
		await _test_scene(case_data, true)
		await _test_scene(case_data, false)
	_expect(_transport.requests.size() == CASES.size() * 2, "one exact-scope backend fixture request per original scene/outcome")
	for request in _transport.requests:
		_expect(request.path == "/api/game/questions" and request.params == FIXTURE_SCOPE, "backend request uses Grade + Difficulty with no required Topic")
	_finish()


func _test_scene(case_data: Dictionary, victory: bool) -> void:
	var label := String(case_data.scene) + (" victory" if victory else " defeat")
	var record := {"scene": SCENE_DIRECTORY + String(case_data.scene), "victory": victory,
		"classification": "FIXTURE ONLY - no world route or milestone evidence",
		"fixture_scope": FIXTURE_SCOPE.duplicate(true), "effects": [], "screenshots": []}
	var request_count_before := _transport.requests.size()
	var attempt_count_before := _capture.attempts.size()
	var correct_before: int = _game_state.correct_answers
	var incorrect_before: int = _game_state.incorrect_answers
	var progress_before: int = _game_state.progress_percentage
	var lesson_before: int = _game_state.lesson_progress
	_game_state.encounter_context.clear()
	_game_state.begin_encounter({
		"encounter_id": "offline_original_vs_fixture",
		"source_scene_path": "res://scenes/oak_leaf_village.tscn",
		"source_position": Vector2.ZERO,
		"quest_checkpoint": 0,
		"question_scope": FIXTURE_SCOPE.duplicate(true),
	})
	var packed := load(SCENE_DIRECTORY + String(case_data.scene)) as PackedScene
	_expect(packed != null, label + ": original packed scene loads")
	if packed == null:
		return
	var battle := packed.instantiate()
	# Mirror the already-approved original presentation canvas boundary.
	var art_layer := CanvasLayer.new()
	art_layer.name = "FinalOriginalVSFixture"
	art_layer.layer = -1
	add_child(art_layer)
	(battle.get_node("CanvasLayer") as CanvasLayer).layer = 0
	art_layer.add_child(battle)
	_game_state.begin_battle(battle)
	var question_label := battle.get_node("CanvasLayer/Panel/QuestionLabel") as Label
	var timeout := Time.get_ticks_msec() + 3000
	while not question_label.text.begins_with("Offline backend fixture") and Time.get_ticks_msec() < timeout:
		await get_tree().process_frame
	_expect(question_label.text.begins_with("Offline backend fixture"), label + ": real provider fills original question field")
	if not question_label.text.begins_with("Offline backend fixture"):
		art_layer.queue_free()
		await _frames(2)
		_game_state.end_battle()
		return
	_expect(_transport.requests.size() == request_count_before + 1, label + ": asynchronous exact-scope API boundary invoked once")
	_expect(battle.get_node("player").scene_file_path == "res://Battle/" + String(case_data.player), label + ": original gender sprite retained")
	_expect(battle.get_node("Bandit").scene_file_path == "res://Battle/" + String(case_data.enemy), label + ": specialized original enemy sprite retained")
	_expect(battle.get_node("Sprite2D").scene_file_path == "res://Battle/Bg-battle.tscn", label + ": original background retained")
	var managers: Array[String] = []
	var visible_questions: Array[String] = []
	var replacement_nodes: Array[String] = []
	var visible_choices: Array[String] = []
	for node in get_tree().root.find_children("*", "", true, false):
		var script = node.get_script()
		if script != null and script.resource_path == "res://Battle/Battle-Enemy/QuizManager.gd":
			managers.append(str(node.get_path()))
		if node is CanvasItem and node.is_visible_in_tree():
			if node.name == "QuestionLabel":
				visible_questions.append(str(node.get_path()))
			if String(node.name) in CHOICE_NAMES:
				visible_choices.append(str(node.get_path()))
			var compact_name := String(node.name).replace(" ", "").replace("_", "").to_lower()
			if "questioncontainer" in compact_name or "multiplechoice" in compact_name:
				replacement_nodes.append(str(node.get_path()))
	_expect(managers.size() == 1 and visible_questions == [str(question_label.get_path())], label + ": one manager and one visible original question field")
	_expect(replacement_nodes.is_empty() and visible_choices.size() == 4, label + ": duplicate question UI is zero and exactly four original choices are visible")
	record.manager_paths = managers
	record.question_paths = visible_questions
	record.replacement_paths = replacement_nodes
	record.duplicate_question_ui_count = maxi(0, visible_questions.size() - 1) + replacement_nodes.size()
	var buttons: Array[Button] = []
	for choice_index in CHOICE_NAMES.size():
		var button := battle.get_node("CanvasLayer/Panel/" + CHOICE_NAMES[choice_index]) as Button
		buttons.append(button)
		_expect(button.text == FIXTURE_CHOICES[choice_index] and not button.disabled, label + ": backend content fills original " + CHOICE_NAMES[choice_index])
		var center := button.get_global_transform_with_canvas() * (button.size / 2.0)
		_expect(get_viewport().get_visible_rect().has_point(center), label + ": original " + CHOICE_NAMES[choice_index] + " is inside viewport")
	var player_health := battle.get_node("PlayerHealth")
	var enemy_health := battle.get_node("EnemyHealth")
	_expect(_health_is(player_health, 3) and _health_is(enemy_health, 3), label + ": all six original hearts initialize")
	await _capture_screen(case_data, victory, "question", record)
	# Correct is C. Both outcomes exercise correct and wrong. The defeat case
	# clicks A, B, C and D while enabled; victory proves 3 right + 1 wrong = 75%.
	var answer_indices: Array[int] = [2, 0, 2, 2]
	if not victory:
		answer_indices = [2, 0, 2, 1, 3]
	var expected_player := 3
	var expected_enemy := 3
	var events: Array[String] = []
	var outcomes: Array[bool] = []
	var terminal_started_msec := [0]
	var terminal_finished_msec := [0]
	var effect_finished_before_result := [false]
	battle.tree_exiting.connect(func() -> void: events.append("tree_exiting"), CONNECT_ONE_SHOT)
	battle.battle_finished.connect(func(won: bool) -> void:
		effect_finished_before_result[0] = events.has("animation_finished")
		terminal_finished_msec[0] = Time.get_ticks_msec()
		events.append("battle_finished")
		outcomes.append(won)
		art_layer.queue_free()
	)
	for answer_index in answer_indices.size():
		var selected := answer_indices[answer_index]
		var is_correct: bool = selected == 2
		var terminal: bool = answer_index == answer_indices.size() - 1
		var question: Dictionary = battle.get("_current_question_data")
		_expect(int(question.get("correct", -1)) == 2 and question.get("question_set_id") == FIXTURE_SET_ID
			and question.get("grade") == "Grade 1" and question.get("difficulty") == "Easy"
			and not question.has("topic"), label + ": backend answer index, set traceability and optional Topic survive normalization")
		var effect := battle.get_node("Bandit/SlashEffect" if is_correct else "player/SlashEffect") as Node2D
		var animation := effect.get_node("AnimatedSprite2D") as AnimatedSprite2D
		_expect(animation.sprite_frames.get_frame_count(&"explode") == 60
			and is_equal_approx(animation.sprite_frames.get_animation_speed(&"explode"), 60.0)
			and not animation.sprite_frames.get_animation_loop(&"explode"), label + ": original 60-frame 60-fps effect timing remains")
		if terminal:
			animation.animation_finished.connect(func() -> void: events.append("animation_finished"), CONNECT_ONE_SHOT)
			terminal_started_msec[0] = Time.get_ticks_msec()
		var click := await _viewport_click(buttons[selected], label)
		_expect(int(click.pressed_count) == 1, label + ": viewport click dispatches exactly one original " + CHOICE_NAMES[selected])
		if is_correct:
			expected_enemy -= 1
		else:
			expected_player -= 1
		_expect(_health_is(player_health, expected_player) and _health_is(enemy_health, expected_enemy), label + ": answer damages only the intended original heart row")
		_expect(effect.visible and animation.is_playing() and animation.animation == &"explode", label + ": original hit effect is visible and playing")
		record.effects.append({"answer_index": answer_index, "correct": is_correct,
			"player_hearts": expected_player, "enemy_hearts": expected_enemy,
			"effect": str(effect.get_path()), "frame": animation.frame})
		if terminal:
			_expect(outcomes.is_empty() and not art_layer.is_queued_for_deletion(), label + ": parent retains original final effect before result signal")
			_expect(question_label.text == ("YOU WIN!" if victory else "GAME OVER!"), label + ": original terminal feedback is displayed")
			for button in buttons:
				_expect(button.disabled, label + ": terminal original choice disables immediately")
			var before_duplicate := _capture.attempts.size()
			battle.answer_selected(selected)
			var disabled_click := await _viewport_click(buttons[3], label + " terminal disabled")
			_expect(int(disabled_click.pressed_count) == 0 and _capture.attempts.size() == before_duplicate, label + ": extra terminal call and disabled viewport click cannot duplicate results")
			await _capture_screen(case_data, victory, "terminal", record)
	var deadline := Time.get_ticks_msec() + 3500
	while outcomes.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _frames(2)
	_expect(outcomes == [victory] and effect_finished_before_result[0], label + ": one correct outcome follows original animation completion")
	_expect(events == ["animation_finished", "battle_finished", "tree_exiting"], label + ": original effect completes before parent teardown")
	_expect(not is_instance_valid(battle), label + ": fixture parent removes original presentation after result")
	_expect(_capture.attempts.size() == attempt_count_before + answer_indices.size(), label + ": one traceable result per viewport answer")
	_expect(_game_state.progress_percentage == progress_before and _game_state.lesson_progress == lesson_before, label + ": accuracy is never written into Total Progress or lesson progress")
	_expect(_game_state.difficulty_level == "Easy", label + ": authoritative current gameplay difficulty stays Easy")
	if victory:
		var correct_delta: int = _game_state.correct_answers - correct_before
		var incorrect_delta: int = _game_state.incorrect_answers - incorrect_before
		_expect(correct_delta == 3 and incorrect_delta == 1 and is_equal_approx(100.0 * correct_delta / (correct_delta + incorrect_delta), 75.0), label + ": 3 correct and 1 incorrect preserve 75 percent Accuracy")
	for attempt in _capture.attempts.slice(attempt_count_before):
		_expect(attempt.question.get("question_set_id") == FIXTURE_SET_ID and attempt.question.get("grade") == "Grade 1"
			and attempt.question.get("difficulty") == "Easy", label + ": results preserve original backend scope and question-set identity")
	record.events = events
	record.outcomes = outcomes
	record.terminal_effect_elapsed_ms = terminal_finished_msec[0] - terminal_started_msec[0]
	record.effect_finished_before_result = effect_finished_before_result[0]
	_observed.append(record)
	if is_instance_valid(art_layer):
		art_layer.queue_free()
		await _frames(2)
	_game_state.end_battle()
	_game_state.encounter_context.clear()
	print("FINAL_VS_PROVIDER_CASE " + JSON.stringify(record))


func _viewport_click(control: Button, label: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var position := control.get_global_transform_with_canvas() * (control.size / 2.0)
	var record := {"case": label, "target": str(control.get_path()), "position": str(position), "pressed_count": 0}
	control.pressed.connect(func() -> void: record.pressed_count += 1, CONNECT_ONE_SHOT)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	var hovered := get_viewport().gui_get_hovered_control()
	record.hovered = str(hovered.get_path()) if hovered != null else "none"
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await _frames(2)
	_pointers.append(record)
	return record


func _capture_screen(case_data: Dictionary, victory: bool, phase: String, record: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://docs/qa/2026-09-07-final-vs-provider-" + String(case_data.scene).get_basename()
	path += ("-victory-" if victory else "-defeat-") + phase + "-" + _run_stamp + ".png"
	var saved := get_viewport().get_texture().get_image().save_png(path) == OK
	_expect(saved, String(case_data.scene) + ": fresh " + phase + " screenshot saved")
	if saved:
		record.screenshots.append(path)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if not bool(check.passed):
			failed += 1
	var result := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks,
		"cases": _observed, "case_count": _observed.size(), "pointers": _pointers,
		"question_requests": _transport.requests if _transport != null else [],
		"recorded_answers": _capture.attempts if _capture != null else [],
		"live_network_calls": 0, "save_load_calls": 0, "quest_advancement_calls": 0,
		"classification": "All scene cases are isolated presentation fixtures; no new gameplay routes are proven.",
		"human_acceptance": "PENDING", "output": _output_path}
	var output := FileAccess.open(_output_path, FileAccess.WRITE)
	if output == null:
		print("FAIL could not write " + _output_path)
		get_tree().quit(1)
		return
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("FINAL_VS_PROVIDER_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed,
		"cases": _observed.size(), "live_network_calls": 0, "output": _output_path}))
	get_tree().quit(0 if failed == 0 else 1)
