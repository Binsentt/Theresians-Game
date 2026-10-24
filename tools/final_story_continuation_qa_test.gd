extends Node

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
	"Teacher: Congratulations, Math Champion. Keep practicing and keep learning.",
]
const EXPECTED_WIZARD_REVELATION: Array[String] = [
	"Wizard: You have defeated me... but I am not the true Math Champion.",
	"Wizard: The real Math Champion is your Math Teacher.",
	"Wizard: If you want to become the greatest Math Champion, return to the School and face your final challenge.",
]
const CITY := "res://scenes/city_of_knowledge.tscn"
const PINEHILL := "res://scenes/2nd Village/Pinehill Village.tscn"
const SCHOOL := "res://interiors/school.tscn"
const COMPLETION_SCREEN_PATH := "res://ui/journey_completion_screen.tscn"
const POST_COMPLETION_TEACHER_LINE := "Teacher: Congratulations, Math Champion. Keep practicing and keep learning."
const RESULT_PATH := "user://qa/final_story_continuation_qa_test_result.json"


class QuestionTransport extends "res://scripts/http_api.gd":
	var requests: Array[Dictionary] = []

	func request_get(path: String, params: Dictionary = {}, _timeout_ms: int = -1) -> Dictionary:
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


class ResultCapture extends "res://scripts/remote_sync.gd":
	var attempts: Array[Dictionary] = []

	func record_question_attempt(question: Dictionary, correct: bool) -> void:
		attempts.append({"question": question.duplicate(true), "correct": correct})


class FinalStoryState extends "res://tools/preservation_regression_state.gd":
	var fixture_checkpoint_save_count := 0

	func save_checkpoint() -> String:
		var path := super.save_checkpoint()
		if not path.is_empty():
			fixture_checkpoint_save_count += 1
		return path

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
	var test_save_directory := "user://qa_test_artifacts/final_story_continuation_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_save_directory)) != OK:
		_expect(false, "Final story test creates a unique isolated QA save directory")
		get_tree().quit(2)
		return
	var original_http_script: Script = http.get_script()
	var original_remote_script: Script = remote.get_script()
	http.set_script(QuestionTransport)
	http.set("base_url", "http://127.0.0.1:5000")
	http.set("local_qa_only", true)
	http.set("production_qa_mode", false)
	remote.set_script(ResultCapture)
	remote.set("local_qa_only", true)
	_expect(get_tree().root.find_children("*", "HTTPRequest", true, false).is_empty(), "No live HTTPRequest nodes exist in the isolated test")
	var transport := http as QuestionTransport
	var result_capture := remote as ResultCapture

	_state = get_node("/root/GameState")
	_state.set_script(FinalStoryState)
	_state.set("_save_directory", test_save_directory)
	_state.fixture_path = test_save_directory + "/manual_loss_fixture.json"
	_state.start_new_game(PROFILE, false)
	await _test_completion_screen_contract()
	_test_final_teacher_contract()
	await _test_deliberate_dialogue(EXPECTED_REVEAL, "revelation")
	await _test_deliberate_dialogue(EXPECTED_EPILOGUE, "epilogue")
	_test_return_and_retry_flow()
	_test_final_victory_and_completed_reload()
	await _test_real_final_teacher_interactions(transport, result_capture)

	var failed := _checks.filter(func(row: Dictionary) -> bool: return not bool(row.get("passed", false))).size()
	var evidence := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks, "live_network_calls": 0}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa"))
	var report := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify(evidence, "\t"))
		report.close()
	print("FINAL_STORY_CONTINUATION_QA " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "live_network_calls": 0}))
	if FileAccess.file_exists(_state.fixture_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_state.fixture_path))
	# Restore the actual autoload scripts before the guarded test process exits.
	if is_instance_valid(http) and original_http_script != null:
		http.set_script(original_http_script)
	if is_instance_valid(remote) and original_remote_script != null:
		remote.set_script(original_remote_script)
	get_tree().quit(1 if failed else 0)


func _test_completion_screen_contract() -> void:
	var original_values := {
		"player_name": _state.player_name,
		"grade_level": _state.grade_level,
		"student_id": _state.student_id,
		"parent_id": _state.parent_id,
		"correct_answers": _state.correct_answers,
		"incorrect_answers": _state.incorrect_answers,
		"total_questions": _state.total_questions,
		"progress_percentage": _state.progress_percentage,
		"journey_complete": _state.journey_complete,
	}
	_state.player_name = "Synthetic Champion"
	_state.grade_level = "Grade 3"
	_state.student_id = "87654321"
	_state.parent_id = "123456"
	_state.correct_answers = 3
	_state.incorrect_answers = 2
	_state.total_questions = 5
	_state.progress_percentage = 72
	_state.journey_complete = true
	var packed := load(COMPLETION_SCREEN_PATH) as PackedScene if ResourceLoader.exists(COMPLETION_SCREEN_PATH) else null
	_expect(packed != null, "A dedicated journey completion presentation scene exists")
	if packed == null:
		_restore_completion_test_state(original_values)
		return
	var screen := packed.instantiate() as CanvasLayer
	_expect(screen != null, "Journey completion presentation instantiates as a CanvasLayer")
	if screen == null:
		_restore_completion_test_state(original_values)
		return
	add_child(screen)
	await get_tree().process_frame
	_expect(screen.visible, "Completion presentation is visible when explicitly instantiated")
	_expect(screen.has_method("build_summary_rows"), "Completion summary uses a testable authoritative GameState projection")
	_expect(screen.has_method("get_panel_rect_for_viewport"), "Completion layout exposes the same responsive geometry used at runtime")
	var panel_control := screen.find_child("CompletionPanel", true, false) as Control
	_expect(panel_control != null, "Completion presentation has one bounded game-themed panel")
	if panel_control != null:
		var content_minimum := panel_control.get_combined_minimum_size()
		_expect(content_minimum.x <= 760.0 and content_minimum.y <= 460.0, "All completion content fits within the responsive panel bounds")
	var labels: Array[String] = []
	if screen.has_method("build_summary_rows"):
		var rows: Array = screen.call("build_summary_rows")
		for row_value in rows:
			if row_value is Dictionary:
				labels.append(String(row_value.get("label", "")))
		_expect(labels.has("Student") and labels.has("Grade"), "Completion summary includes the existing student name and Grade")
	_expect(labels.has("Oak Leaf") and labels.has("City of Knowledge") and labels.has("Pinehill") and labels.has("Math Teacher"), "Completion summary shows the completed canonical campaign regions")
	_expect(labels.has("Correct Answers") and labels.has("Incorrect Answers") and labels.has("Total Answers"), "Completion summary uses only authoritative answer totals")
	var rendered_copy := ""
	for label_value in screen.find_children("*", "Label", true, false):
		rendered_copy += (label_value as Label).text + "\n"
	_expect(not rendered_copy.contains("87654321") and not rendered_copy.contains("123456"), "Completion screen never displays Student or Parent IDs")
	if screen.has_method("get_panel_rect_for_viewport"):
		for viewport_size in [Vector2(844, 509), Vector2(1215, 545), Vector2(1280, 720), Vector2(1920, 1080)]:
			var rect: Rect2 = screen.call("get_panel_rect_for_viewport", viewport_size)
			var in_bounds: bool = rect.position.x >= 0.0 and rect.position.y >= 0.0 \
					and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y
			var centered: bool = absf((rect.position.x * 2.0 + rect.size.x) - viewport_size.x) < 1.0 \
					and absf((rect.position.y * 2.0 + rect.size.y) - viewport_size.y) < 1.0
			_expect(in_bounds and centered, "Completion panel stays centered and within %dx%d" % [int(viewport_size.x), int(viewport_size.y)])
	var buttons := screen.find_children("*", "Button", true, false)
	_expect(buttons.size() == 1, "Completion presentation exposes only the final Main Menu action")
	var the_end_label := screen.find_child("TheEndLabel", true, false) as Label
	var summary_content := screen.find_child("SummaryContent", true, false) as Control
	_expect(the_end_label != null and the_end_label.text == "The End" and the_end_label.visible, "Completion begins with a short The End card")
	if screen.has_method("get_end_card_duration"):
		await get_tree().create_timer(float(screen.call("get_end_card_duration")) + 0.1).timeout
	_expect(summary_content != null and summary_content.visible, "The End card automatically advances to the completion summary")
	var title_label := screen.find_child("TitleLabel", true, false) as Label
	_expect(title_label != null and title_label.text == "THERESIAN'S QUEST COMPLETE", "Completion summary follows the The End card")
	var continue_button := screen.find_child("ContinueButton", true, false) as Button
	var main_menu_button := screen.find_child("MainMenuButton", true, false) as Button
	_expect(continue_button == null and main_menu_button != null, "Continue is removed after the final ending")
	var sfx := screen.find_child("CompletionSound", true, false) as AudioStreamPlayer
	_expect(sfx != null and sfx.bus == AudioSettingsManager.SFX_BUS_NAME and sfx.stream != null \
			and sfx.stream.resource_path == "res://audio/completed.mp3", "Completion sting reuses the existing completion sound on the SFX bus")
	if sfx != null:
		var sound_deadline := Time.get_ticks_msec() + 1500
		while not sfx.playing and Time.get_ticks_msec() < sound_deadline:
			await get_tree().process_frame
		_expect(sfx.playing, "Completion sting plays once through the existing SFX bus")
	if main_menu_button != null:
		main_menu_button.pressed.emit()
		main_menu_button.pressed.emit()
		_expect(String(screen.get("selected_action")) == "main_menu", "Main Menu selection is stable against a duplicate button press")
	var zero_result_rows: Array = []
	_state.correct_answers = 0
	_state.incorrect_answers = 0
	_state.total_questions = 0
	_state.progress_percentage = 0
	if screen.has_method("build_summary_rows"):
		zero_result_rows = screen.call("build_summary_rows")
	var zero_labels: Array[String] = []
	for row_value in zero_result_rows:
		if row_value is Dictionary:
			zero_labels.append(String(row_value.get("label", "")))
	_expect(not zero_labels.has("Correct Answers") and not zero_labels.has("Incorrect Answers") and not zero_labels.has("Total Answers"), "Untracked zero metrics are omitted rather than fabricated")
	screen.queue_free()
	_restore_completion_test_state(original_values)
	await get_tree().process_frame


func _restore_completion_test_state(values: Dictionary) -> void:
	for key in values:
		_state.set(String(key), values[key])


func _test_final_teacher_contract() -> void:
	var final_task: Dictionary = _state.tasks[_state.FINAL_TEACHER_TASK_INDEX]
	_expect(PROGRESSION_ROUTER.WIZARD_REVELATION_DIALOGUE == EXPECTED_WIZARD_REVELATION, "Wizard revelation points directly to the Teacher's final Math Champion challenge")
	_expect(Array(final_task.get("dialogue", [])) == EXPECTED_REVEAL, "Final Teacher reveal matches all six approved lines")
	_expect(Array(final_task.get("victory_dialogue", [])) == EXPECTED_EPILOGUE, "Final epilogue ends with the approved Math Champion line")
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

	_state.handle_scene_entered(GameState.DEEPEST_FOREST_PATH)
	var forest_save: Dictionary = _state.build_save_data()
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(forest_save, false)
	_expect(_state.current_scene_path == CITY and _state.current_task_index == _state.RETURN_CITY_TASK_INDEX and _state.wizard_defeated, "Legacy Forest save/load normalizes to City without replay")
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
	var saves_before_victory: int = _state.fixture_checkpoint_save_count
	var victory: Dictionary = _state.record_encounter_victory()
	var progression: Dictionary = victory.get("progression", {})
	_expect(bool(progression.get("changed", false)) and _state.final_teacher_defeated and _state.journey_complete, "Final Teacher victory completes the journey once")
	_expect(_state.fixture_checkpoint_save_count == saves_before_victory + 1, "Final Teacher victory persists exactly one hidden completion checkpoint")
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
	_expect(not duplicate_victory.get("changed", false) and completion_events.size() == 1 and _state.fixture_checkpoint_save_count == saves_before_victory + 1, "Duplicate final completion does not add an event or checkpoint")


func _test_real_final_teacher_interactions(transport: QuestionTransport, result_capture: ResultCapture) -> void:
	await _prepare_school("male")
	var world := get_tree().current_scene
	var teacher := world.get_node("Teacher")
	var quest_ui := world.get_node("CanvasLayer/Panel")
	var male_battle := await _start_final_teacher_interaction(world, teacher, quest_ui, "male")
	if male_battle == null:
		return
	var male_completion_events: Array[Dictionary] = []
	var male_completion_callback := func(_previous: int, _next: int, event: Dictionary) -> void:
		if String(event.get("key", "")) == "quest:world:journey_complete":
			male_completion_events.append(event)
	_state.task_state_changed.connect(male_completion_callback)
	var saves_before_male_victory: int = _state.fixture_checkpoint_save_count
	var male_win := await _finish_synthetic_battle(male_battle, true, "Male final Teacher challenge")
	_expect(male_win, "Actual male final Teacher battle can be won")
	await _advance_dialogue_lines(world, quest_ui, EXPECTED_EPILOGUE, "Male final Teacher epilogue")
	var male_completion_screen := await _wait_for_completion_screen(world)
	_expect(male_completion_screen != null, "First male Final Teacher victory opens completion only after the full epilogue closes")
	_expect(_state.journey_complete and _state.final_teacher_defeated and _state.get_current_quest_text() == "Math Champion", "Actual male victory reaches Math Champion after the full epilogue")
	_expect(_state.fixture_checkpoint_save_count == saves_before_male_victory + 1, "The authoritative Final Teacher victory remains the only completion checkpoint")
	_expect(male_completion_events.size() == 1, "First Final Teacher victory emits one completion event")
	if male_completion_screen != null:
		_expect(_state.get_mode() == _state.GameMode.CUTSCENE, "Completion presentation blocks gameplay with CUTSCENE mode")
		var game_hud := world.get_node_or_null("GameHUD")
		var mobile_controls := world.get_node_or_null("MobileControls")
		var time_panel := game_hud.get_node_or_null("TimeMargin") as CanvasItem if game_hud != null else null
		var quest_panel := game_hud.get_node_or_null("QuestGuide") as CanvasItem if game_hud != null else null
		var controls_root := mobile_controls.get_node_or_null("Root") as CanvasItem if mobile_controls != null else null
		_expect(time_panel != null and not time_panel.visible and quest_panel != null and not quest_panel.visible, "Time and quest HUD are hidden during the completion presentation")
		_expect(controls_root != null and not controls_root.visible, "ACT and movement controls are hidden during the completion presentation")
		var ending_music_ready := await _wait_for_music_track("ending")
		_expect(ending_music_ready, "The existing MusicManager transitions to the ending track")
		var background_players := get_node("/root/MusicManager").find_children("*", "AudioStreamPlayer", true, false)
		_expect(background_players.size() == 1 and String(get_node("/root/MusicManager").get("_current_track_key")) == "ending", "Ending music replaces rather than stacks the existing background player")
		quest_ui.call("_show_journey_completion")
		_expect(world.get_node_or_null("JourneyCompletionScreen") == male_completion_screen, "A repeated presentation request cannot open a duplicate overlay")
		var continue_button := male_completion_screen.find_child("ContinueButton", true, false) as Button
		var main_menu_button := male_completion_screen.find_child("MainMenuButton", true, false) as Button
		_expect(continue_button == null and main_menu_button != null, "Final completion exposes Main Menu without a Continue path")
	_expect(_state.fixture_checkpoint_save_count == saves_before_male_victory + 1 and male_completion_events.size() == 1, "Opening the ending creates no duplicate checkpoint or completion event")
	_state.task_state_changed.disconnect(male_completion_callback)
	var completed_checkpoint_path := String(_state.call("_get_current_student_save_path", _state.student_id))
	var completed_data: Dictionary = _state._read_save_file(completed_checkpoint_path)
	_expect(bool(completed_data.get("journey_complete", false)) and bool(completed_data.get("final_teacher_defeated", false)), "The hidden first-victory checkpoint already contains completed state")
	var completed_checkpoint_listed := false
	for save_entry in _state.list_saves():
		if String(save_entry.get("save_path", "")) == completed_checkpoint_path:
			completed_checkpoint_listed = true
	_expect(not completed_checkpoint_listed, "Hidden completion checkpoint is not exposed as a manual Load Game slot")
	# This fixture remains in the School world to inspect the hidden checkpoint;
	# a real ending leaves through Main Menu. Remove the existing presentation so
	# the next assertion can prove load does not create a second one.
	if male_completion_screen != null and is_instance_valid(male_completion_screen):
		male_completion_screen.queue_free()
		await get_tree().process_frame
	_state.start_new_game(PROFILE, false)
	_state.apply_save_data(completed_data, false)
	_expect(_state.journey_complete and _state.final_teacher_defeated and not _state.is_final_teacher_active(), "Actual completed game save/load retains the no-replay Math Champion state")
	_expect(world.get_node_or_null("JourneyCompletionScreen") == null, "Loading a completed save never auto-replays the completion presentation")
	_expect(_state.wizard_defeated and _state.is_progression_encounter_defeated("pinehill_wizard"), "Actual final save keeps Wizard defeated")
	for encounter_id in _state.DEEP_FOREST_BANDIT_IDS + _state.PINEHILL_BANDIT_IDS:
		_expect(_state.is_progression_encounter_defeated(encounter_id), "Actual final save keeps prior encounter defeated: " + encounter_id)
	_expect(result_capture.attempts.size() == 3, "Actual male final Teacher battle records exactly three local synthetic attempts")
	_expect(transport.requests.size() == 1, "Male final Teacher battle loads one isolated question batch")
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
	var female_completion_screen := await _wait_for_completion_screen(world)
	_expect(female_completion_screen != null, "First female Final Teacher victory opens the same completion presentation after its epilogue")
	_expect(_state.journey_complete and _state.final_teacher_defeated, "Actual female victory completes the same canonical journey")
	_expect(result_capture.attempts.size() == 6, "Male and female final Teacher battles record six local synthetic attempts total")
	_expect(transport.requests.size() == 2, "Male and female routes each load one isolated question batch")
	_expect(transport.requests.back().params == {"grade": "Grade 1", "difficulty": "Difficult"}, "Female final battle keeps the same exact question scope")
	await _test_post_completion_civilian_greeting()
	if female_completion_screen != null:
		var saves_before_menu: int = int(_state.fixture_checkpoint_save_count)
		var menu_button := female_completion_screen.find_child("MainMenuButton", true, false) as Button
		_expect(menu_button != null, "Main Menu action exists on the completion screen")
		if menu_button != null:
			menu_button.pressed.emit()
			var menu_opened := await _wait_for_scene_path("res://scenes/main_menu.tscn")
			_expect(menu_opened, "Main Menu action returns cleanly to the existing main menu scene")
			_expect(_state.player_name == PROFILE.player_name and _state.student_id == PROFILE.student_id, "Main Menu preserves the current Student identity in runtime")
			_expect(_state.journey_complete and FileAccess.file_exists(completed_checkpoint_path), "Main Menu preserves the authoritative completed checkpoint without writing another save")
			_expect(_state.fixture_checkpoint_save_count == saves_before_menu, "Main Menu adds no duplicate completion checkpoint")
			var menu_music_ready := await _wait_for_music_track("menu")
			_expect(menu_music_ready, "Main Menu transition returns to the menu music")
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
	# The harness remains current_scene during the School instance's _ready().
	# Ensure this fixture owns the same production UI scenes the real runtime
	# attaches to the active world.
	if school_instance.get_node_or_null("GameHUD") == null:
		var hud_scene := load("res://ui/game_hud.tscn") as PackedScene
		if hud_scene != null:
			var hud := hud_scene.instantiate()
			hud.name = "GameHUD"
			school_instance.add_child(hud)
	if school_instance.get_node_or_null("MobileControls") == null:
		var controls_scene := load("res://ui/mobile_controls.tscn") as PackedScene
		if controls_scene != null:
			var controls := controls_scene.instantiate()
			controls.name = "MobileControls"
			school_instance.add_child(controls)
	var qa_hud := school_instance.get_node_or_null("GameHUD")
	var qa_mobile_controls := school_instance.get_node_or_null("MobileControls")
	if qa_hud != null:
		var time_panel := qa_hud.get_node_or_null("TimeMargin") as CanvasItem
		var quest_panel := qa_hud.get_node_or_null("QuestGuide") as CanvasItem
		if time_panel != null:
			time_panel.visible = true
		if quest_panel != null:
			quest_panel.visible = true
	if qa_mobile_controls != null:
		var controls_root := qa_mobile_controls.get_node_or_null("Root") as CanvasItem
		if controls_root != null:
			controls_root.visible = true
	_expect(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == SCHOOL, gender + " QA uses the canonical School scene")
	_expect(get_tree().root.find_children("*", "HTTPRequest", true, false).is_empty(), gender + " QA has no real HTTP transport")


func _wait_for_completion_screen(world: Node) -> Node:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		var screen := world.get_node_or_null("JourneyCompletionScreen")
		if screen != null:
			return screen
		await get_tree().process_frame
	return null


func _wait_for_music_track(track_key: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		var manager := get_node_or_null("/root/MusicManager")
		if manager != null and String(manager.get("_current_track_key")) == track_key:
			return true
		await get_tree().process_frame
	return false


func _wait_for_scene_path(scene_path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		var current_scene := get_tree().current_scene
		if current_scene != null and current_scene.scene_file_path == scene_path:
			return true
		await get_tree().process_frame
	return false


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
