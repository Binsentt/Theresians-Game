extends Node

const OAKLEAF_SCENE := "res://scenes/oak_leaf_village.tscn"
const BANDIT_ADAPTER_PATH := "Bandits/BanditTaskTrigger/TaskDialogAdapter"
const BANDIT_TRIGGER_PATH := "Bandits/BanditTaskTrigger"
const CHOICE_NAMES := ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"]

@export_enum("male", "female") var test_gender := "male"

var _failures: Array[String] = []
var _check_count := 0
var _battle_transition_count := 0
var _task_events: Array[Dictionary] = []
var _created_save_paths: Array[String] = []


class QuestionProviderStub extends Node:
	signal questions_loaded(count: int)

	const QUESTION := {
		"question": "1 + 1 = ?",
		"choices": ["2", "1", "3", "4"],
		"correct": 0,
	}

	func load_questions() -> void:
		questions_loaded.emit(1)

	func get_questions() -> Array[Dictionary]:
		return [QUESTION.duplicate(true)]

	func get_question() -> Dictionary:
		return QUESTION.duplicate(true)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	_remove_live_transport()
	_replace_question_provider_with_stub()
	GameState.current_task_index = 2
	GameState.gender = test_gender
	GameState.student_id = "87654321"
	GameState.parent_id = "654321"
	GameState.playtime_authorized = true
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	GameState.task_state_changed.connect(_on_task_state_changed)
	GameState.save_created.connect(_on_save_created)
	InputManager.unlock_input("door_transition")
	InputManager.clear_mobile_state()

	_assert(await _load_scene(OAKLEAF_SCENE), "Oakleaf loads in project context")
	await _wait_frames(4)

	var oakleaf := get_tree().current_scene
	var trigger := oakleaf.get_node_or_null(BANDIT_TRIGGER_PATH) as Area2D if oakleaf != null else null
	var adapter := oakleaf.get_node_or_null(BANDIT_ADAPTER_PATH) if oakleaf != null else null
	var panel := oakleaf.get_node_or_null("CanvasLayer/Panel") if oakleaf != null else null
	var dialogue_panel := oakleaf.get_node_or_null("CanvasLayer/DialoguePanel") as CanvasItem if oakleaf != null else null
	var dialogue_label := oakleaf.get_node_or_null("CanvasLayer/DialoguePanel/DialogueLabel") as Label if oakleaf != null else null
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	_assert(trigger != null, "Oakleaf exposes the First Bandit interaction area")
	_assert(adapter != null, "Oakleaf exposes the First Bandit TaskDialogAdapter")
	_assert(panel != null, "Oakleaf exposes the canonical CanvasLayer/Panel dialogue host")
	_assert(dialogue_panel != null and dialogue_label != null, "Oakleaf exposes the shared First Bandit DialoguePanel and label")
	_assert(player != null, "Oakleaf project context creates the player")
	if trigger == null or adapter == null or panel == null or dialogue_panel == null or dialogue_label == null or player == null:
		_finish()
		return

	player.global_position = trigger.global_position
	trigger.call("_on_body_entered", player)

	var resolved_panel := adapter.get_node_or_null(adapter.quest_ui_path)
	_assert(resolved_panel == panel, "First Bandit TaskDialogAdapter resolves the canonical CanvasLayer/Panel")
	_assert(adapter.can_interact(), "TaskDialogAdapter can interact at the active First Bandit task")
	_assert(trigger.can_interact(), "Player reaching the First Bandit interaction area enables Interact")
	if not _failures.is_empty():
		_finish()
		return

	GameState.battle_started.connect(_on_battle_started)
	_assert(trigger.interact(), "First Bandit interaction is accepted once")
	await _wait_frames(2)
	_assert(dialogue_panel.visible and dialogue_label.visible, "First Bandit dialogue opens through the shared dialogue panel")
	_assert(dialogue_label.text == "You want to pass? Solve this first!", "First Bandit renders its existing opening dialogue line before battle")
	_assert(not trigger.interact(), "A duplicate interaction is rejected while First Bandit dialogue is active")
	await _advance_dialogue_once()
	_assert(await _wait_for_battle_transition(6.0), "The final First Bandit dialogue close starts its existing battle")
	_assert(_battle_transition_count == 1, "First Bandit dialogue creates exactly one battle transition")
	await _wait_frames(4)
	_assert(_battle_transition_count == 1, "Duplicate interaction cannot create a second battle transition")
	var battle := GameState.get_current_battle_enemy()
	var expected_scene := "res://Battle/Battle-Enemy/female_vs_bandit.tscn" if test_gender == "female" else "res://Battle/Battle-Enemy/male_vs_bandit.tscn"
	_assert(battle != null and battle.scene_file_path == expected_scene, "%s First Bandit uses the original gender-matched VS scene" % test_gender.capitalize())
	var question := battle.get_node_or_null("CanvasLayer/Panel/QuestionLabel") as Label if battle != null else null
	_assert(question != null and await _wait_for_question(question), "%s First Bandit receives the backend-shaped question in the original VS UI" % test_gender.capitalize())
	var choices: Array[Button] = []
	if battle != null:
		for choice_name in CHOICE_NAMES:
			var button := battle.get_node_or_null("CanvasLayer/Panel/" + choice_name) as Button
			if button != null:
				choices.append(button)
	_assert(choices.size() == 4, "%s First Bandit retains exactly four original choice buttons" % test_gender.capitalize())
	if choices.size() == 4:
		_assert(choices[0].text == "2" and choices[1].text == "1" and choices[2].text == "3" and choices[3].text == "4", "%s First Bandit maps the backend choices to A-D" % test_gender.capitalize())
	var player_health := battle.get_node_or_null("PlayerHealth") if battle != null else null
	var enemy_health := battle.get_node_or_null("EnemyHealth") if battle != null else null
	_assert(player_health != null and enemy_health != null and int(player_health.get("health")) == 3 and int(enemy_health.get("health")) == 3, "%s First Bandit preserves the original three-heart battle state" % test_gender.capitalize())

	var scope := GameState.get_encounter_question_scope()
	_assert(String(scope.get("grade", "")) == "Grade 1", "First Bandit keeps Grade 1 scope")
	_assert(String(scope.get("difficulty", "")) == "Easy", "First Bandit keeps Easy scope")
	_assert(not scope.has("topic_id") and not scope.has("topic"), "First Bandit uses Grade and Difficulty without a required Topic")

	if battle != null:
		battle.call("answer_selected", 0)
		battle.call("answer_selected", 0)
		battle.call("answer_selected", 0)
	_assert(await _wait_for_first_bandit_completion(5.0), "First Bandit victory returns to Oakleaf exploration")
	_assert(GameState.current_task_index == GameState.OAKLEAF_BANDIT_TASK_INDEX, "First Bandit advances only to the normal-bandit state")
	_assert(GameState.get_current_quest_text() == "Defeat All Bandits", "Current Quest becomes Defeat All Bandits")
	_assert(GameState.is_oakleaf_bandit_defeated("oakleaf_bandits1"), "Only the First Bandit is recorded defeated")
	_assert(GameState.get_oakleaf_defeated_bandit_count() == 1, "First Bandit victory records exactly one Oakleaf defeat")
	_assert(not GameState.oakleaf_boss_defeated and not GameState.oakleaf_return_to_teacher and not GameState.city_of_knowledge_unlocked, "First Bandit victory does not complete Boss, Teacher return, or City unlock")
	var premature_completion := false
	for event in _task_events:
		var event_type := String(event.get("type", ""))
		var title := String(event.get("title", ""))
		if event_type in ["task_completed", "quest_completed"] or title == "Task 3 Complete":
			premature_completion = true
	_assert(not premature_completion, "First Bandit must not announce Task 3 or Quest 3 complete")
	_finish()


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _replace_question_provider_with_stub() -> void:
	var provider := get_node_or_null("/root/QuestionProvider")
	if provider != null:
		get_tree().root.remove_child(provider)
		provider.queue_free()
	var stub := QuestionProviderStub.new()
	stub.name = "QuestionProvider"
	get_tree().root.add_child(stub)


func _remove_live_transport() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()


func _load_scene(path: String) -> bool:
	if get_tree().change_scene_to_file(path) != OK:
		return false
	for _index in 240:
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _wait_for_battle_transition(timeout_seconds: float) -> bool:
	var timeout := get_tree().create_timer(timeout_seconds)
	while timeout.time_left > 0.0:
		if _battle_transition_count > 0:
			return true
		await get_tree().process_frame
	return _battle_transition_count > 0


func _wait_frames(frame_count: int) -> void:
	for _index in frame_count:
		await get_tree().process_frame


func _wait_for_question(question: Label) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while is_instance_valid(question) and Time.get_ticks_msec() < deadline:
		if question.text == String(QuestionProviderStub.QUESTION.question):
			return true
		await get_tree().process_frame
	return false


func _wait_for_first_bandit_completion(timeout_seconds: float) -> bool:
	var timeout := get_tree().create_timer(timeout_seconds)
	while timeout.time_left > 0.0:
		if GameState.current_task_index == GameState.OAKLEAF_BANDIT_TASK_INDEX \
				and GameState.get_current_battle_enemy() == null \
				and GameState.get_mode() == GameState.GameMode.EXPLORATION:
			return true
		await get_tree().process_frame
	return false


func _advance_dialogue_once() -> void:
	InputManager.set_mobile_interact_pressed(false)
	await _wait_frames(1)
	InputManager.set_mobile_interact_pressed(true)
	await _wait_frames(2)
	InputManager.set_mobile_interact_pressed(false)
	await _wait_frames(1)


func _on_battle_started(_battle: Node) -> void:
	_battle_transition_count += 1


func _on_task_state_changed(_previous_index: int, _current_index: int, event: Dictionary) -> void:
	_task_events.append(event.duplicate(true))


func _on_save_created(data: Dictionary) -> void:
	if String(data.get("student_id", "")) != "87654321":
		return
	var path := String(data.get("save_path", ""))
	if not path.is_empty() and path not in _created_save_paths:
		_created_save_paths.append(path)


func _assert(condition: bool, message: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for save_path in _created_save_paths:
		GameState.delete_save(save_path)
	var report_path := "res://tools/first_bandit_interaction_%s_project_context_result.json" % test_gender
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify({
			"gender": test_gender,
			"passed": _failures.is_empty(),
			"passed_checks": _check_count - _failures.size(),
			"failed_checks": _failures.size(),
			"failures": _failures,
			"task_events": _task_events,
			"current_task_index": GameState.current_task_index,
			"current_quest": GameState.get_current_quest_text(),
		}, "\t"))
		report_file.close()
	if _failures.is_empty():
		print("FIRST_BANDIT_INTERACTION_PROJECT_CONTEXT_TEST PASSED")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FIRST_BANDIT_INTERACTION_PROJECT_CONTEXT_TEST FAILED")
	get_tree().quit(1)
