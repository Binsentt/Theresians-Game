extends Node

const STATE_FIXTURE := preload("res://tools/preservation_regression_state.gd")
const QUEST_UI_SCRIPT := preload("res://world/QuestUI.gd")
const PROGRESSION_ROUTER := preload("res://scripts/progression_battle_encounter.gd")
const PROFILE := {
	"player_name": "Final Story QA Fixture",
	"gender": "male",
	"grade_level": "Grade 1",
	"student_id": "87654321",
	"parent_id": "123456",
}
const EXPECTED_REVEAL: Array[String] = [
	"Teacher: You finally discovered the truth.",
	"Teacher: Every challenge you faced was part of your journey.",
	"Teacher: The bandits, the Wizard, and every mathematics challenge tested what you have learned.",
	"Teacher: You have grown stronger with every problem you solved.",
	"Teacher: But your journey is not complete yet.",
	"Teacher: Show me everything you have learned in one final challenge.",
]
const EXPECTED_EPILOGUE: Array[String] = [
	"Teacher: Excellent work.",
	"Teacher: You overcame every challenge and continued even when the problems became difficult.",
	"Teacher: You proved how much you have learned.",
	"Teacher: Your journey through Theresian's Quest is complete.",
	"Teacher: You are now a Math Champion.",
	"THERESIAN'S QUEST COMPLETE",
	"Congratulations! You completed your Mathematics Adventure.",
]
const EXPECTED_WIZARD_REVELATION: Array[String] = [
	"Wizard: You are stronger than I expected.",
	"Wizard: But I am not the one behind your greatest challenge.",
	"Wizard: The true Math Master has been guiding you from the beginning.",
	"Wizard: Your Teacher is waiting for you in the City of Knowledge.",
	"Wizard: Return to the School.",
]
const CITY := "res://scenes/city_of_knowledge.tscn"
const FOREST := "res://scenes/deepest_forest_path.tscn"
const PINEHILL := "res://scenes/2nd Village/Pinehill Village.tscn"
const SCHOOL := "res://interiors/school.tscn"
const RESULT_PATH := "res://docs/qa/final-story-continuation-qa-test-result.json"


class QuestionTransport extends Node:
	var requests: Array[Dictionary] = []

	func request_get(path: String, params: Dictionary = {}) -> Dictionary:
		requests.append({"path": path, "params": params.duplicate(true)})
		var questions: Array[Dictionary] = []
		for index in 6:
			questions.append({
				"id": 9800 + index,
				"question": "Synthetic final challenge %d: 18 + 24 = ?" % (index + 1),
				"options": ["42", "40", "41", "43"],
				"correct_answer": "42",
				"grade_level": "Grade 1",
				"difficulty": "Difficult",
				"learning_file_id": 980,
			})
		await get_tree().process_frame
		return {"ok": true, "status": 200, "body": {"questions": questions}}


class ResultCapture extends Node:
	var attempts: Array[Dictionary] = []

	func record_question_attempt(question: Dictionary, correct: bool) -> void:
		attempts.append({"question": question.duplicate(true), "correct": correct})

var _checks: Array[Dictionary] = []
var _state: Node


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, label: String) -> void:
	_checks.append({"label": label, "passed": condition})
	if not condition:
		push_error(label)


func _run() -> void:
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	var local_api := http != null \
			and http.has_method("is_local_qa_mode") \
			and bool(http.call("is_local_qa_mode")) \
			and String(http.call("get_resolved_api_base_url")).begins_with("http://127.0.0.1:")
	var local_sync := remote != null and bool(remote.get("local_qa_only"))
	_expect(local_api, "QA runner must select the configured loopback-only API profile")
	_expect(local_sync, "QA runner must disable RemoteSync writes")
	if not local_api or not local_sync:
		print("FINAL_STORY_CONTINUATION_QA BLOCKED: local-only runtime guard not active")
		get_tree().quit(2)
		return
	if http != null:
		http.free()
	if remote != null:
		remote.free()
	_expect(get_tree().root.find_children("*", "HTTPRequest", true, false).is_empty(), "No live HTTPRequest nodes exist in the isolated test")
	var transport := QuestionTransport.new()
	transport.name = "HttpApi"
	get_tree().root.add_child(transport)
	var result_capture := ResultCapture.new()
	result_capture.name = "RemoteSync"
	get_tree().root.add_child(result_capture)

	_state = get_node("/root/GameState")
	_state.set_script(STATE_FIXTURE)
	_state.fixture_path = "user://saves/final_story_continuation_%d.json" % Time.get_ticks_usec()
	_state.start_new_game(PROFILE, false)
	_test_final_teacher_contract()
	await _test_deliberate_dialogue(EXPECTED_REVEAL, "revelation")
	await _test_deliberate_dialogue(EXPECTED_EPILOGUE, "epilogue")
	_test_return_and_retry_flow()
	_test_final_victory_and_completed_reload()
	await _test_real_final_teacher_interactions(transport, result_capture)

	var failed := _checks.filter(func(row: Dictionary) -> bool: return not bool(row.get("passed", false))).size()
	var evidence := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks, "live_network_calls": 0}
	var report := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify(evidence, "\t"))
		report.close()
	print("FINAL_STORY_CONTINUATION_QA " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "live_network_calls": 0}))
	if FileAccess.file_exists(_state.fixture_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_state.fixture_path))
	var active_scene := get_tree().current_scene
	if active_scene != null and active_scene != self:
		active_scene.queue_free()
		get_tree().current_scene = self
		await get_tree().process_frame
	get_tree().quit(1 if failed else 0)


func _test_final_teacher_contract() -> void:
	var final_task: Dictionary = _state.tasks[_state.FINAL_TEACHER_TASK_INDEX]
	_expect(PROGRESSION_ROUTER.WIZARD_REVELATION_DIALOGUE == EXPECTED_WIZARD_REVELATION, "Wizard revelation keeps the approved five lines")
	_expect(Array(final_task.get("dialogue", [])) == EXPECTED_REVEAL, "Final Teacher reveal matches all six approved lines")
	_expect(Array(final_task.get("victory_dialogue", [])) == EXPECTED_EPILOGUE, "Final epilogue matches all seven approved lines")
	_expect(String(final_task.get("encounter_id", "")) == "final_teacher", "Final encounter retains its canonical ID")
	_expect(Dictionary(final_task.get("question_scope", {})).get("difficulty", "") == "Difficult", "Final encounter retains Difficult question scope")
	var male_scene := String(final_task.get("male_battle_scene", ""))
	var female_scene := String(final_task.get("female_battle_scene", ""))
	_expect(male_scene == "res://Battle/Battle-Enemy/male_vs_teacher.tscn" and ResourceLoader.exists(male_scene), "Male final battle uses the original Teacher VS scene")
	_expect(female_scene == "res://Battle/Battle-Enemy/female_vs_teacher.tscn" and ResourceLoader.exists(female_scene), "Female final battle uses the original Teacher VS scene")
	var male_packed := load(male_scene) as PackedScene if not male_scene.is_empty() else null
	var female_packed := load(female_scene) as PackedScene if not female_scene.is_empty() else null
	_expect(male_packed != null, "Original male Teacher VS battle loads without resource errors")
	_expect(female_packed != null, "Original female Teacher VS battle loads without resource errors")
	if male_packed != null:
		var male_battle := male_packed.instantiate()
		_expect(male_battle.scene_file_path == male_scene, "Male route instantiates the canonical scene")
		male_battle.free()
	if female_packed != null:
		var female_battle := female_packed.instantiate()
		_expect(female_battle.scene_file_path == female_scene, "Female route instantiates the canonical scene")
		female_battle.free()


func _test_deliberate_dialogue(lines: Array[String], label: String) -> void:
	var dialogue_panel := Panel.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.visible = false
	var dialogue_label := Label.new()
	dialogue_label.name = "DialogueLabel"
	dialogue_panel.add_child(dialogue_label)
	add_child(dialogue_panel)

	var quest_ui := Panel.new()
	quest_ui.name = "QuestUI"
	quest_ui.set_script(QUEST_UI_SCRIPT)
	add_child(quest_ui)
	quest_ui.call("begin_dialogue", lines)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(bool(quest_ui.call("is_dialogue_active")), label + " opens in the existing dialogue panel")
	for index in lines.size():
		_expect(int(quest_ui.call("get_dialogue_line_index")) == index and dialogue_label.text == lines[index], label + " presents line " + str(index + 1))
		await get_tree().process_frame
		_expect(int(quest_ui.call("get_dialogue_line_index")) == index, label + " does not auto-skip line " + str(index + 1))
		quest_ui.call("_advance_dialogue_once")
		await get_tree().process_frame
	_expect(not bool(quest_ui.call("is_dialogue_active")) and not dialogue_panel.visible, label + " closes only after the last deliberate advance")
	quest_ui.free()
	dialogue_panel.free()


func _test_return_and_retry_flow() -> void:
	_state.current_scene_path = PINEHILL
	_state.current_task_index = _state.WIZARD_TASK_INDEX
	_state.city_first_arrival_seen = true
	_state.pinehill_unlocked = true
	_state.pinehill_old_man_completed = true
	for encounter_id in _state.DEEP_FOREST_BANDIT_IDS:
		_state.deep_forest_defeated_bandits[encounter_id] = true
	for encounter_id in _state.PINEHILL_BANDIT_IDS:
		_state.pinehill_defeated_bandits[encounter_id] = true
	var wizard_result: Dictionary = _state.record_progression_encounter_victory("pinehill_wizard", false)
	_expect(bool(wizard_result.get("changed", false)) and _state.wizard_defeated and _state.current_task_index == _state.RETURN_CITY_TASK_INDEX, "Wizard victory starts the City return exactly once")
	_expect(not bool(_state.record_progression_encounter_victory("pinehill_wizard", false).get("changed", false)), "Duplicate Wizard victory does not replay its completion")
	var post_wizard_save: Dictionary = _state.build_save_data()
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(post_wizard_save, false)
	_expect(_state.wizard_defeated and _state.current_task_index == _state.RETURN_CITY_TASK_INDEX, "Wizard victory save/load retains the return quest")

	_state.handle_scene_entered(FOREST)
	var forest_save: Dictionary = _state.build_save_data()
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(forest_save, false)
	_expect(_state.current_task_index == _state.RETURN_CITY_TASK_INDEX and _state.wizard_defeated, "Forest return save/load keeps the City objective without replay")
	for encounter_id in _state.DEEP_FOREST_BANDIT_IDS:
		_expect(_state.is_progression_encounter_defeated(encounter_id), "Cleared Forest encounter remains defeated: " + encounter_id)
	for encounter_id in _state.PINEHILL_BANDIT_IDS:
		_expect(_state.is_progression_encounter_defeated(encounter_id), "Cleared Pinehill guard remains defeated: " + encounter_id)
	_state.handle_scene_entered(CITY)
	_expect(_state.current_task_index == _state.FINAL_SCHOOL_TASK_INDEX and _state.get_current_quest_text() == "Return to the School.", "Return to City advances to the School objective")
	var city_save: Dictionary = _state.build_save_data()
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(city_save, false)
	_state.handle_scene_entered(CITY)
	_expect(_state.current_task_index == _state.FINAL_SCHOOL_TASK_INDEX, "Repeated City entry cannot duplicate or regress the return transition")
	_state.handle_scene_entered(SCHOOL)
	_expect(_state.current_task_index == _state.FINAL_TEACHER_TASK_INDEX and _state.get_current_quest_text() == "Face the Teacher's Final Challenge.", "School arrival opens the final Teacher objective without starting a battle")
	_state.handle_scene_entered(SCHOOL)
	_expect(_state.current_task_index == _state.FINAL_TEACHER_TASK_INDEX, "Repeated School entry cannot duplicate final-task advancement")

	var source_position := Vector2(412.0, 276.0)
	_state.begin_encounter({
		"encounter_id": "final_teacher",
		"source_scene_path": SCHOOL,
		"source_position": source_position,
		"quest_checkpoint": _state.FINAL_TEACHER_TASK_INDEX,
		"question_scope": {"difficulty": "Difficult"},
	})
	var loss: Dictionary = _state.record_encounter_loss()
	_expect(loss.get("action", "") == "retry" and not _state.journey_complete and not _state.final_teacher_defeated, "Final Teacher loss leaves the journey incomplete and retryable")
	_expect(_state.current_task_index == _state.FINAL_TEACHER_TASK_INDEX and _state.current_scene_path == SCHOOL and _state.player_position == source_position, "Final Teacher loss returns safely to the School checkpoint")
	var loss_save: Dictionary = _state.build_save_data()
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(loss_save, false)
	_expect(_state.is_final_teacher_active() and int(_state.encounter_context.get("retry_count", 0)) == 1, "Save/load after loss preserves a retryable final encounter")
	var retry_context: Dictionary = _state.begin_encounter({
		"encounter_id": "final_teacher",
		"source_scene_path": SCHOOL,
		"source_position": source_position,
		"quest_checkpoint": _state.FINAL_TEACHER_TASK_INDEX,
		"question_scope": {"difficulty": "Difficult"},
	})
	_expect(int(retry_context.get("retry_count", 0)) == 1, "Retry reuses one encounter identity and retains retry count")


func _test_final_victory_and_completed_reload() -> void:
	_state.current_task_index = _state.FINAL_TEACHER_TASK_INDEX
	_state.wizard_defeated = true
	_state.return_to_city_stage = 2
	_state.pinehill_unlocked = true
	for encounter_id in _state.DEEP_FOREST_BANDIT_IDS:
		_state.deep_forest_defeated_bandits[encounter_id] = true
	for encounter_id in _state.PINEHILL_BANDIT_IDS:
		_state.pinehill_defeated_bandits[encounter_id] = true
	_state.begin_encounter({
		"encounter_id": "final_teacher",
		"source_scene_path": SCHOOL,
		"source_position": Vector2(412.0, 276.0),
		"quest_checkpoint": _state.FINAL_TEACHER_TASK_INDEX,
		"question_scope": {"difficulty": "Difficult"},
	})
	var completion_events: Array[Dictionary] = []
	_state.task_state_changed.connect(func(_previous: int, _next: int, event: Dictionary) -> void:
		if String(event.get("key", "")) == "quest:world:journey_complete":
			completion_events.append(event)
	)
	var saves_before_victory: int = _state.fixture_save_count
	var victory: Dictionary = _state.record_encounter_victory()
	var progression: Dictionary = victory.get("progression", {})
	_expect(bool(progression.get("changed", false)) and _state.final_teacher_defeated and _state.journey_complete, "Final Teacher victory completes the journey once")
	_expect(_state.fixture_save_count == saves_before_victory + 1, "Final Teacher victory persists exactly one completion save")
	_expect(completion_events.size() == 1, "Final Teacher victory emits exactly one final completion event")
	_expect(_state.get_current_quest_text() == "Math Champion" and _state.current_task_index >= _state.tasks.size(), "Completed quest display remains Math Champion with no active task")
	_expect(not _state.is_final_teacher_active() and not _state.can_start_progression_encounter("final_teacher"), "Completed Teacher challenge cannot be started again")
	_expect(_state.wizard_defeated and _state.is_progression_encounter_defeated("pinehill_wizard"), "Wizard remains defeated after final completion")
	var completed_save: Dictionary = _state.build_save_data()
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(completed_save, false)
	_expect(_state.journey_complete and _state.final_teacher_defeated and _state.get_current_quest_text() == "Math Champion", "Completed save reload preserves Math Champion")
	_expect(not _state.can_start_progression_encounter("final_teacher") and not _state.can_start_progression_encounter("pinehill_wizard"), "Completed save cannot replay Teacher or Wizard battle")
	for encounter_id in _state.DEEP_FOREST_BANDIT_IDS:
		_expect(_state.is_progression_encounter_defeated(encounter_id), "Completed save keeps Forest enemy defeated: " + encounter_id)
	for encounter_id in _state.PINEHILL_BANDIT_IDS:
		_expect(_state.is_progression_encounter_defeated(encounter_id), "Completed save keeps guard defeated: " + encounter_id)
	var duplicate_victory: Dictionary = _state.record_progression_encounter_victory("final_teacher", false)
	_expect(not duplicate_victory.get("changed", false) and completion_events.size() == 1 and _state.fixture_save_count == saves_before_victory + 1, "Duplicate final completion does not add an event or save")


func _test_real_final_teacher_interactions(transport: QuestionTransport, result_capture: ResultCapture) -> void:
	await _prepare_school("male")
	var world := get_tree().current_scene
	var teacher := world.get_node("Teacher")
	var quest_ui := world.get_node("CanvasLayer/Panel")
	var male_battle := await _start_final_teacher_interaction(world, teacher, quest_ui, "male")
	if male_battle == null:
		return
	var male_loss := await _finish_synthetic_battle(male_battle, false, "Male final Teacher loss")
	_expect(not male_loss and not _state.journey_complete and not _state.final_teacher_defeated, "Actual male final battle loss leaves the journey incomplete")
	_expect(_state.current_task_index == _state.FINAL_TEACHER_TASK_INDEX and _state.current_scene_path == SCHOOL, "Actual male loss returns to the School final-task checkpoint")
	_expect(not _state.battle_active and quest_ui.visible, "Actual male loss clears battle state and restores the world UI")
	_state.save_game()
	var loss_save: Dictionary = _state._read_save_file(_state.fixture_path)
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(loss_save, false)
	_expect(_state.is_final_teacher_active() and int(_state.encounter_context.get("retry_count", 0)) == 1, "Actual final-battle loss save reload remains retryable")
	_state.set_mode(_state.GameMode.EXPLORATION)
	var retry_battle := await _start_final_teacher_interaction(world, teacher, quest_ui, "male retry")
	if retry_battle == null:
		return
	_expect(int(_state.get_active_encounter_context().get("retry_count", 0)) == 1, "Actual Teacher retry preserves the single encounter identity and retry count")
	var male_win := await _finish_synthetic_battle(retry_battle, true, "Male final Teacher retry")
	_expect(male_win, "Actual male final Teacher retry can be won")
	await _advance_dialogue_lines(world, quest_ui, EXPECTED_EPILOGUE, "Male final Teacher epilogue")
	_expect(_state.journey_complete and _state.final_teacher_defeated and _state.get_current_quest_text() == "Math Champion", "Actual male victory reaches Math Champion after the full epilogue")
	_expect(not teacher.call("can_interact") and not teacher.call("interact"), "Completed actual Teacher interaction cannot start another battle")
	var completed_path: String = _state.save_game()
	var completed_data: Dictionary = _state._read_save_file(completed_path)
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(completed_data, false)
	_expect(_state.journey_complete and _state.final_teacher_defeated and not _state.is_final_teacher_active(), "Actual completed game save/load retains the no-replay Math Champion state")
	_expect(_state.wizard_defeated and _state.is_progression_encounter_defeated("pinehill_wizard"), "Actual final save keeps Wizard defeated")
	for encounter_id in _state.DEEP_FOREST_BANDIT_IDS + _state.PINEHILL_BANDIT_IDS:
		_expect(_state.is_progression_encounter_defeated(encounter_id), "Actual final save keeps prior encounter defeated: " + encounter_id)
	_expect(result_capture.attempts.size() == 6, "Actual male loss and retry record exactly three local synthetic attempts each")
	_expect(transport.requests.size() == 2, "Male loss and retry each load one isolated question batch")
	for request in transport.requests:
		_expect(request.path == "/api/game/questions" and request.params == {"grade": "Grade 1", "difficulty": "Difficult"}, "Final battles request only Grade 1 Difficult questions")
	for attempt in result_capture.attempts:
		_expect(String(attempt.question.get("difficulty", "")) == "Difficult" and String(attempt.question.get("question", "")).begins_with("Synthetic final challenge"), "Captured battle result uses the synthetic final-challenge question")
	await _prepare_school("female")
	world = get_tree().current_scene
	teacher = world.get_node("Teacher")
	quest_ui = world.get_node("CanvasLayer/Panel")
	var female_battle := await _start_final_teacher_interaction(world, teacher, quest_ui, "female")
	if female_battle == null:
		return
	var female_win := await _finish_synthetic_battle(female_battle, true, "Female final Teacher challenge")
	_expect(female_win, "Actual female final Teacher battle can be won")
	await _advance_dialogue_lines(world, quest_ui, EXPECTED_EPILOGUE, "Female final Teacher epilogue")
	_expect(_state.journey_complete and _state.final_teacher_defeated, "Actual female victory completes the same canonical journey")
	_expect(result_capture.attempts.size() == 9, "Actual three final battles record exactly nine local synthetic attempts")
	_expect(transport.requests.size() == 3, "Female route makes one additional local fixture question request")
	_expect(transport.requests.back().params == {"grade": "Grade 1", "difficulty": "Difficult"}, "Female final battle keeps the same exact question scope")
	await _test_post_completion_civilian_greeting()
	transport.free()
	result_capture.free()
	get_tree().current_scene = self


func _prepare_school(gender: String) -> void:
	var profile := PROFILE.duplicate(true)
	profile.gender = gender
	_state.start_new_game(profile, false)
	_state.current_task_index = _state.FINAL_TEACHER_TASK_INDEX
	_state.current_quest = _state.get_current_quest_text()
	_state.wizard_defeated = true
	_state.return_to_city_stage = 2
	_state.final_teacher_defeated = false
	_state.journey_complete = false
	_state.playtime_authorized = true
	_state.current_scene_path = SCHOOL
	_state.pinehill_unlocked = true
	for encounter_id in _state.DEEP_FOREST_BANDIT_IDS:
		_state.deep_forest_defeated_bandits[encounter_id] = true
	for encounter_id in _state.PINEHILL_BANDIT_IDS:
		_state.pinehill_defeated_bandits[encounter_id] = true
	_state.set_mode(_state.GameMode.EXPLORATION)
	var existing_scene := get_tree().current_scene
	if existing_scene != null and existing_scene != self:
		existing_scene.queue_free()
		get_tree().current_scene = self
		await get_tree().process_frame
	var school_resource := load(SCHOOL) as PackedScene
	var school_instance := school_resource.instantiate() if school_resource != null else null
	_expect(school_instance != null, gender + " QA scenario loads the canonical School scene")
	if school_instance == null:
		return
	get_tree().root.add_child(school_instance)
	get_tree().current_scene = school_instance
	for frame in 8:
		await get_tree().process_frame
	_expect(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == SCHOOL, gender + " QA uses the canonical School scene")
	_expect(get_tree().root.find_children("*", "HTTPRequest", true, false).is_empty(), gender + " QA has no real HTTP transport")


func _start_final_teacher_interaction(world: Node, teacher: Node, quest_ui: Node, label: String) -> Node:
	var input_manager := get_node_or_null("/root/InputManager")
	_expect(_state.is_final_teacher_active(), label + ": authoritative final Teacher task is active")
	_expect(_state.get_mode() == _state.GameMode.EXPLORATION, label + ": gameplay mode permits the Teacher interaction")
	_expect(input_manager != null and not bool(input_manager.call("is_input_locked")), label + ": no global input lock blocks the Teacher interaction")
	_expect(teacher.get_node_or_null(teacher.get("quest_ui_path")) == quest_ui, label + ": the canonical Teacher adapter resolves the scene QuestUI")
	_expect(not bool(teacher.get("_active")), label + ": the Teacher adapter has no stale in-progress interaction")
	_expect(bool(teacher.call("_is_school_scene")), label + ": Teacher adapter recognizes the School scene")
	_expect(bool(_state.call("is_final_teacher_active")) and bool(teacher.call("_is_school_scene")), label + ": final-task and School gates both permit the Teacher")
	var teacher_available := bool(teacher.call("can_interact"))
	_expect(teacher_available, label + ": canonical Teacher target is available at final task")
	if not teacher_available:
		return null
	_expect(bool(teacher.call("interact")), label + ": intentional Teacher interaction starts dialogue")
	_expect(not bool(teacher.call("interact")), label + ": a duplicate interaction is rejected while dialogue is active")
	await _advance_dialogue_lines(world, quest_ui, EXPECTED_REVEAL, label + " reveal")
	var deadline := Time.get_ticks_msec() + 8000
	var battle: Node = null
	while Time.get_ticks_msec() < deadline:
		battle = _state.get_current_battle_enemy()
		if is_instance_valid(battle) and not Dictionary(battle.get("_current_question_data")).is_empty():
			break
		await get_tree().process_frame
	_expect(is_instance_valid(battle), label + ": original Teacher VS battle starts only after the reveal")
	if not is_instance_valid(battle):
		return null
	var expected_scene := "res://Battle/Battle-Enemy/%s_vs_teacher.tscn" % ("female" if label.begins_with("female") else "male")
	_expect(battle.scene_file_path == expected_scene, label + ": actual original gender-specific Teacher scene is active")
	_expect(String(_state.get_active_encounter_context().get("encounter_id", "")) == "final_teacher", label + ": real battle uses canonical final_teacher encounter")
	_expect(_state.get_active_encounter_context().get("question_scope", {}) == {"grade": "Grade 1", "difficulty": "Difficult"}, label + ": real battle context carries the canonical Difficult scope")
	var question: Dictionary = battle.get("_current_question_data")
	_expect(String(question.get("question", "")).begins_with("Synthetic final challenge"), label + ": actual QuestionProvider feeds the original VS UI")
	_expect(String(question.get("difficulty", "")) == "Difficult" and String(question.get("grade", "")) == "Grade 1", label + ": normalized backend-shaped question retains grade and difficulty")
	var choices: Array[String] = []
	for choice_name in ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"]:
		var choice := battle.get_node("CanvasLayer/Panel/" + choice_name) as Button
		choices.append(choice.text)
		_expect(choice.is_visible_in_tree() and not choice.disabled, label + ": original " + choice_name + " is available")
	_expect(choices.size() == 4 and choices[int(question.get("correct", -1))] == "42", label + ": four original choices preserve the mapped correct answer")
	_expect(get_tree().root.find_children("*", "HTTPRequest", true, false).is_empty(), label + ": no network request nodes are introduced by battle setup")
	return battle


func _finish_synthetic_battle(battle: Node, should_win: bool, label: String) -> bool:
	var finished: Array[bool] = []
	battle.battle_finished.connect(func(success: bool) -> void: finished.append(success), CONNECT_ONE_SHOT)
	for answer_index in 3:
		var question: Dictionary = battle.get("_current_question_data")
		var correct := int(question.get("correct", -1))
		_expect(correct >= 0 and correct < 4, label + ": each question maps one correct choice")
		battle.call("answer_selected", correct if should_win else (correct + 1) % 4)
		await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 8000
	while finished.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not finished.is_empty(), label + ": original battle emits one terminal result")
	if finished.is_empty():
		return false
	return finished[0]


func _advance_dialogue_lines(world: Node, quest_ui: Node, expected: Array[String], label: String) -> void:
	for index in expected.size():
		var deadline := Time.get_ticks_msec() + 4000
		while (not bool(quest_ui.call("is_dialogue_active")) or int(quest_ui.call("get_dialogue_line_index")) != index) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_expect(bool(quest_ui.call("is_dialogue_active")) and int(quest_ui.call("get_dialogue_line_index")) == index, label + ": deliberate line " + str(index + 1) + " is presented")
		var label_node := world.get_node("CanvasLayer/DialoguePanel/DialogueLabel") as Label
		_expect(label_node.text == expected[index], label + ": text matches line " + str(index + 1))
		quest_ui.call("_advance_dialogue_once")
		await get_tree().process_frame
	var close_deadline := Time.get_ticks_msec() + 4000
	while bool(quest_ui.call("is_dialogue_active")) and Time.get_ticks_msec() < close_deadline:
		await get_tree().process_frame
	_expect(not bool(quest_ui.call("is_dialogue_active")), label + ": dialogue closes after its final deliberate advance")


func _test_post_completion_civilian_greeting() -> void:
	var host := Node2D.new()
	host.name = "CompletedJourneyGreetingFixture"
	add_child(host)
	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	host.add_child(canvas)
	var dialogue_panel := Panel.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.visible = false
	canvas.add_child(dialogue_panel)
	var dialogue_label := Label.new()
	dialogue_label.name = "DialogueLabel"
	dialogue_panel.add_child(dialogue_label)
	var quest_ui := Panel.new()
	quest_ui.name = "Panel"
	quest_ui.set_script(QUEST_UI_SCRIPT)
	canvas.add_child(quest_ui)
	var civilian_scene := load("res://NPC/Npc/wandering_girl_npc.tscn") as PackedScene
	var civilian := civilian_scene.instantiate() if civilian_scene != null else null
	_expect(civilian != null, "A canonical ordinary civilian actor loads after journey completion")
	if civilian == null:
		host.free()
		return
	host.add_child(civilian)
	await get_tree().process_frame
	var greeting := civilian.get_node("Visual")
	greeting.set("greeting_message", "Welcome to the City of Knowledge. The school is just ahead.")
	_state.set_mode(_state.GameMode.EXPLORATION)
	_expect(_state.journey_complete and _state.get_current_quest_text() == "Math Champion", "Civilian greeting test begins in persisted Math Champion state")
	_expect(bool(greeting.call("can_interact")), "Ordinary civilian greeting remains available after the journey is complete")
	_expect(bool(greeting.call("interact")), "Ordinary civilian still opens its canonical greeting")
	await get_tree().process_frame
	_expect(bool(greeting.get("_dialogue_active")), "Ordinary civilian remains in its shared dialogue interaction")
	_expect(dialogue_panel.visible, "Completed-state greeting opens the existing QuestUI dialogue panel")
	_expect(dialogue_label.text == String(greeting.get("greeting_message")), "Completed-state greeting renders its canonical City message")
	quest_ui.call("_advance_dialogue_once")
	for frame in 4:
		await get_tree().process_frame
	_expect(_state.journey_complete and _state.get_current_quest_text() == "Math Champion" and not _state.battle_active, "Ordinary greeting closes without replaying the completed journey or starting a battle")
	host.free()
	await get_tree().process_frame
