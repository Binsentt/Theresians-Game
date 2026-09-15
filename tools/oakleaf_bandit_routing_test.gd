extends Node
## Focused canonical routing fixture for Oakleaf Bandits2-5 and Boss-Bandit.
## It keeps the real QuestionProvider in place and substitutes only its HTTP/result
## boundary, so the original VS scenes receive a backend-shaped question payload.

const OAKLEAF_SCENE := "res://scenes/oak_leaf_village.tscn"
const ROUTE_NODE := "OakleafBattleEncounter"
const CHOICE_NAMES := ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"]
const CASES := [
	{"actor": "Bandits2", "encounter_id": "oakleaf_bandits2", "male": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
	{"actor": "Bandits3", "encounter_id": "oakleaf_bandits3", "male": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
	{"actor": "Bandits4", "encounter_id": "oakleaf_bandits4", "male": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
	{"actor": "Bandits5", "encounter_id": "oakleaf_bandits5", "male": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
	{"actor": "Boss-Bandit", "encounter_id": "oakleaf_boss_bandit", "male": "res://Battle/Battle-Enemy/male_vs_boss.tscn", "female": "res://Battle/Battle-Enemy/female_vs_boss_bandit.tscn"},
]
const BACKEND_CHOICES := ["47", "46", "48", "49"]


class PoolTransport extends Node:
	var requests: Array[Dictionary] = []

	func request_get(path: String, params: Dictionary = {}) -> Dictionary:
		requests.append({"path": path, "params": params.duplicate(true)})
		await get_tree().process_frame
		var questions: Array[Dictionary] = []
		for index in 4:
			questions.append({
				"id": 88000 + index,
				"question": "Oakleaf backend fixture %d: 24 + 24 = ?" % index,
				"options": BACKEND_CHOICES.duplicate(),
				"correct_answer": "48",
				"grade_level": "Grade 1",
				"difficulty": "Easy",
				"learning_file_id": 88,
			})
		return {"ok": true, "status": 200, "body": {"questions": questions}}


class ResultCapture extends Node:
	var attempts: Array[Dictionary] = []

	func record_question_attempt(question: Dictionary, is_correct: bool) -> void:
		attempts.append({"question": question.duplicate(true), "is_correct": is_correct})


var _checks: Array[Dictionary] = []
var _transport: PoolTransport
var _results: ResultCapture
var _battle_started_count := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	_remove_live_transport()
	_transport = PoolTransport.new()
	_transport.name = "HttpApi"
	get_tree().root.add_child(_transport)
	_results = ResultCapture.new()
	_results.name = "RemoteSync"
	get_tree().root.add_child(_results)
	_expect(_real_question_provider_present(), "actual QuestionProvider remains active for backend shape normalization")
	GameState.battle_started.connect(_on_battle_started)

	for case_data in CASES:
		await _run_case(case_data, "male")
		await _run_case(case_data, "female")

	_expect(_transport.requests.size() == CASES.size() * 2, "one backend request occurs for each routed encounter")
	for request in _transport.requests:
		_expect(request.get("path") == "/api/game/questions" and request.get("params") == {"grade": "Grade 1", "difficulty": "Easy"}, "routed encounter retains the Oakleaf Grade 1 Easy question scope")
	_finish()


func _run_case(case_data: Dictionary, gender: String) -> void:
	_prepare_case(gender, String(case_data.actor))
	_expect(await _load_scene(OAKLEAF_SCENE), "%s %s: canonical Oakleaf scene loads" % [case_data.actor, gender])
	await _frames(4)
	var world := get_tree().current_scene
	var actor := world.get_node_or_null(String(case_data.actor)) as Node2D if world != null else null
	var other_name := "Bandits3" if String(case_data.actor) == "Bandits2" else "Bandits2"
	var other_actor := world.get_node_or_null(other_name) as Node2D if world != null else null
	var encounter := actor.get_node_or_null(ROUTE_NODE) if actor != null else null
	var has_expected_other_actor := String(case_data.actor) == "Boss-Bandit" or other_actor != null
	_expect(actor != null and has_expected_other_actor, "%s %s: only existing Oakleaf actor nodes are used" % [case_data.actor, gender])
	_expect(encounter != null, "%s %s: exactly one focused encounter component is installed" % [case_data.actor, gender])
	if actor == null or (not has_expected_other_actor) or encounter == null:
		return
	_expect(actor.get_children().filter(func(child: Node) -> bool: return child.name == ROUTE_NODE).size() == 1, "%s %s: duplicate encounter component is zero" % [case_data.actor, gender])
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	_expect(player != null, "%s %s: project player is present" % [case_data.actor, gender])
	if player == null:
		return
	player.global_position = actor.global_position
	await _frames(2)
	_expect(InteractionManager.get_active_interactable() == encounter, "%s %s: nearby interaction selects only this actor" % [case_data.actor, gender])
	var starts_before := _battle_started_count
	InputManager.set_mobile_interact_pressed(false)
	await _frames(1)
	InputManager.set_mobile_interact_pressed(true)
	await _frames(2)
	InputManager.set_mobile_interact_pressed(false)
	_expect(not bool(encounter.call("interact")), "%s %s: repeated encounter activation is rejected" % [case_data.actor, gender])
	var battle := await _wait_for_battle(world)
	_expect(battle != null, "%s %s: mobile ACT starts one original VS battle" % [case_data.actor, gender])
	_expect(_battle_started_count == starts_before + 1, "%s %s: encounter trigger starts exactly one battle" % [case_data.actor, gender])
	if battle == null:
		return
	var expected_scene := String(case_data.get(gender, ""))
	_expect(battle.scene_file_path == expected_scene, "%s %s: routes to the required original VS scene" % [case_data.actor, gender])
	_expect(String(GameState.get_active_encounter_context().get("encounter_id", "")) == String(case_data.encounter_id), "%s %s: encounter identity is independent" % [case_data.actor, gender])
	await _verify_original_presentation(battle, "%s %s" % [case_data.actor, gender])
	var expected_index := 5 if String(case_data.actor) == "Boss-Bandit" else int(GameState.current_task_index)
	await _win_and_verify_state(battle, actor, other_actor, expected_index, "%s %s" % [case_data.actor, gender])


func _prepare_case(gender: String, actor_name: String) -> void:
	InputManager.clear_mobile_state()
	GameState.gender = gender
	GameState.grade_level = "Grade 1"
	GameState.difficulty_level = "Easy"
	GameState.playtime_authorized = true
	GameState.oakleaf_defeated_bandits = {
		"oakleaf_bandits1": true,
		"oakleaf_bandits2": false,
		"oakleaf_bandits3": false,
		"oakleaf_bandits4": false,
		"oakleaf_bandits5": false,
	}
	if actor_name == "Boss-Bandit":
		GameState.current_task_index = 4
		for encounter_id in GameState.OAKLEAF_BANDIT_IDS:
			GameState.oakleaf_defeated_bandits[encounter_id] = true
	else:
		GameState.current_task_index = 3
	GameState.oakleaf_boss_defeated = false
	GameState.oakleaf_return_to_teacher = false
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.encounter_context.clear()
	GameState.end_battle()
	GameState.set_mode(GameState.GameMode.EXPLORATION)


func _verify_original_presentation(battle: Node, label: String) -> void:
	var question := battle.get_node_or_null("CanvasLayer/Panel/QuestionLabel") as Label
	var buttons: Array[Button] = []
	for choice_name in CHOICE_NAMES:
		var button := battle.get_node_or_null("CanvasLayer/Panel/" + choice_name) as Button
		if button != null:
			buttons.append(button)
	_expect(question != null and await _wait_for_question(question), label + ": backend-shaped question reaches the original VS label")
	_expect(buttons.size() == 4, label + ": exactly four original choice controls are retained")
	for index in buttons.size():
		_expect(buttons[index].text == BACKEND_CHOICES[index] and not buttons[index].disabled, label + ": backend answer fills original " + CHOICE_NAMES[index])
	var manager_count := 0
	var visible_questions := 0
	var replacement_count := 0
	for node in get_tree().root.find_children("*", "", true, false):
		var node_script: Script = node.get_script() as Script
		if node_script != null and node_script.resource_path == "res://Battle/Battle-Enemy/QuizManager.gd":
			manager_count += 1
		if node is CanvasItem and node.is_visible_in_tree() and node.name == "QuestionLabel":
			visible_questions += 1
		var compact_name := str(node.name).replace(" ", "").replace("_", "").to_lower()
		if "questioncontainer" in compact_name or "multiplechoice" in compact_name:
			replacement_count += 1
	_expect(manager_count == 1 and visible_questions == 1 and replacement_count == 0, label + ": duplicate battle UI is zero")
	var player_health := battle.get_node_or_null("PlayerHealth")
	var enemy_health := battle.get_node_or_null("EnemyHealth")
	var enemy_effect := battle.get_node_or_null("Bandit/SlashEffect") as Node2D
	_expect(_health_is(player_health, 3) and _health_is(enemy_health, 3), label + ": original three-heart rows are preserved")
	var current_question: Dictionary = battle.get("_current_question_data")
	var correct_index := int(current_question.get("correct", -1))
	var question_set_id := str(current_question.get("question_set_id", ""))
	_expect(correct_index == 2 and question_set_id == "88", label + ": backend correct-answer text maps to original ChoiceC")
	battle.call("answer_selected", 2)
	await _frames(2)
	var animation := enemy_effect.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D if enemy_effect != null else null
	_expect(_health_is(enemy_health, 2) and enemy_effect != null and enemy_effect.visible and animation != null and animation.is_playing(), label + ": correct answer preserves original enemy damage and effect")
	_expect(animation != null and animation.sprite_frames.get_frame_count(&"explode") == 60 and is_equal_approx(animation.sprite_frames.get_animation_speed(&"explode"), 60.0) and not animation.sprite_frames.get_animation_loop(&"explode"), label + ": original hit animation remains intact")


func _win_and_verify_state(battle: Node, actor: Node2D, other_actor: Node2D, task_before: int, label: String) -> void:
	var active_encounter_id := String(GameState.get_active_encounter_context().get("encounter_id", ""))
	var is_boss := active_encounter_id == "oakleaf_boss_bandit"
	battle.call("answer_selected", 2)
	battle.call("answer_selected", 2)
	if is_boss:
		var quest_ui := get_tree().current_scene.get_node_or_null("CanvasLayer/Panel") if get_tree().current_scene != null else null
		var dialogue_deadline := Time.get_ticks_msec() + 3500
		while is_instance_valid(actor) and Time.get_ticks_msec() < dialogue_deadline:
			if quest_ui != null and quest_ui.has_method("is_dialogue_active") and bool(quest_ui.call("is_dialogue_active")):
				break
			await get_tree().process_frame
		var dialogue_open := quest_ui != null and quest_ui.has_method("is_dialogue_active") and bool(quest_ui.call("is_dialogue_active"))
		var dialogue_label := get_tree().current_scene.get_node_or_null("CanvasLayer/DialoguePanel/DialogueLabel") as Label if get_tree().current_scene != null else null
		_expect(dialogue_open and GameState.get_mode() == GameState.GameMode.DIALOGUE, label + ": Boss victory opens the shared bottom dialogue before progression completes")
		_expect(dialogue_label != null and dialogue_label.text.to_lower().contains("defeat") and dialogue_label.text.to_lower().contains("road"), label + ": Boss defeat dialogue closes the road-blocking story beat")
		if dialogue_open:
			InputManager.set_mobile_interact_pressed(false)
			await _frames(2)
			InputManager.set_mobile_interact_pressed(true)
			await _frames(2)
			InputManager.set_mobile_interact_pressed(false)
	var deadline := Time.get_ticks_msec() + 3500
	while is_instance_valid(actor) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _frames(2)
	_expect(not is_instance_valid(actor), label + ": victory defeats only this actor")
	if other_actor != null:
		_expect(is_instance_valid(other_actor) and other_actor.get_node_or_null(ROUTE_NODE) != null, label + ": another bandit keeps its independent encounter state")
	_expect(GameState.current_task_index == task_before and GameState.get_active_encounter_context().is_empty() and GameState.get_mode() == GameState.GameMode.EXPLORATION, label + ": victory does not reset or advance quest state")


func _wait_for_battle(world: Node) -> Node:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if world != null:
			var presentation := world.get_node_or_null("OriginalBattlePresentation")
			if presentation != null and presentation.get_child_count() == 1:
				return presentation.get_child(0)
		await get_tree().process_frame
	return null


func _wait_for_question(question: Label) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while is_instance_valid(question) and Time.get_ticks_msec() < deadline:
		if question.text.begins_with("Oakleaf backend fixture"):
			return true
		await get_tree().process_frame
	return false


func _health_is(health: Node, expected: int) -> bool:
	if health == null or int(health.get("health")) != expected or int(health.get("max_health")) != 3:
		return false
	for index in 3:
		var heart := health.get_node_or_null("Hearts/Heart%d" % (index + 1)) as TextureRect
		if heart == null or heart.visible != (index < expected):
			return false
	return true


func _load_scene(path: String) -> bool:
	if get_tree().change_scene_to_file(path) != OK:
		return false
	for index in 240:
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _remove_live_transport() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()


func _real_question_provider_present() -> bool:
	var provider := get_node_or_null("/root/QuestionProvider")
	var script: Script = provider.get_script() as Script if provider != null else null
	return script != null and script.resource_path == "res://scripts/question_provider.gd"


func _promote_to_root() -> void:
	var tree := get_tree()
	var parent_node := get_parent()
	if tree != null and parent_node != null:
		parent_node.remove_child(self)
		tree.root.add_child(self)


func _frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame


func _on_battle_started(_battle: Node) -> void:
	_battle_started_count += 1


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if not bool(check.passed):
			failed += 1
	var report := {"passed": _checks.size() - failed, "failed": failed, "cases": CASES.size() * 2, "requests": _transport.requests.size() if _transport != null else 0, "checks": _checks}
	var report_file := FileAccess.open("res://tools/oakleaf_bandit_routing_result.json", FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report))
		report_file.close()
	print("OAKLEAF_BANDIT_ROUTING_TEST " + JSON.stringify(report))
	await get_tree().create_timer(10.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
