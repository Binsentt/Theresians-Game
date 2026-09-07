extends Node
## Run only as an isolated canonical project test scene through Godot MCP.
## Uses all eight real VS scenes. Only question/result transport is replaced.
## No account, new-game, save/load, quest advancement, or live HTTP call is used.

const SCENE_DIRECTORY := "res://Battle/Battle-Enemy/"
const CASES := [
	{"scene": "male_vs_bandit.tscn", "player": "Player-male-battle.tscn", "enemy": "Bandit-Battle.tscn"},
	{"scene": "female_vs_bandit.tscn", "player": "player_female_battle.tscn", "enemy": "Bandit-Battle.tscn"},
	{"scene": "male_vs_boss.tscn", "player": "Player-male-battle.tscn", "enemy": "boss_bandit_battle.tscn"},
	{"scene": "female_vs_boss_bandit.tscn", "player": "player_female_battle.tscn", "enemy": "boss_bandit_battle.tscn"},
	{"scene": "male_vs_teacher.tscn", "player": "Player-male-battle.tscn", "enemy": "Teacher_Battle.tscn"},
	{"scene": "female_vs_teacher.tscn", "player": "player_female_battle.tscn", "enemy": "Teacher_Battle.tscn"},
	{"scene": "male_vs_wizard.tscn", "player": "Player-male-battle.tscn", "enemy": "Wizard-Battle.tscn"},
	{"scene": "female_vs_wizard1.tscn", "player": "player_female_battle.tscn", "enemy": "Wizard-Battle.tscn"},
]
const CHOICE_NAMES := ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"]
const QUESTION := {
	"id": "offline-presentation-question",
	"question_set_id": 901,
	"grade": "Grade 1",
	"difficulty": "Easy",
	"question": "1 + 1 = ?",
	"choices": ["2", "1", "3", "4"],
	"correct": 0,
}


class OfflineQuestionProvider extends Node:
	signal questions_loaded(count: int)

	func load_questions() -> void:
		# Exercise QuizManager's asynchronous injection into the original controls.
		await get_tree().process_frame
		questions_loaded.emit(1)

	func get_questions() -> Array[Dictionary]:
		return [QUESTION.duplicate(true)]

	func get_question() -> Dictionary:
		return QUESTION.duplicate(true)


class OfflineResults extends Node:
	var attempts: Array[Dictionary] = []

	func record_question_attempt(question: Dictionary, is_correct: bool) -> void:
		attempts.append({"question": question.duplicate(true), "is_correct": is_correct})


var _checks: Array[Dictionary] = []
var _observed: Array[Dictionary] = []
var _results: OfflineResults
var _game_state


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_game_state = get_node("/root/GameState")
	# A fresh MCP test process has an empty in-memory GameState. Remove all live
	# transport before attaching a VS scene; do not load any real player state.
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		var live_node := get_node_or_null("/root/" + autoload_name)
		if live_node != null:
			live_node.free()
	_expect(_game_state.student_id.is_empty() and _game_state.parent_id.is_empty(), "isolated GameState has no account identity")
	if not _game_state.student_id.is_empty() or not _game_state.parent_id.is_empty():
		_finish()
		return
	var provider := OfflineQuestionProvider.new()
	provider.name = "QuestionProvider"
	get_tree().root.add_child(provider)
	_results = OfflineResults.new()
	_results.name = "RemoteSync"
	get_tree().root.add_child(_results)
	_expect(get_node_or_null("/root/HttpApi") == null, "live HTTP transport removed before battle answers")

	for case_data in CASES:
		await _test_scene(case_data, true)
		await _test_scene(case_data, false)
	_finish()


func _test_scene(case_data: Dictionary, victory: bool) -> void:
	var label := String(case_data.scene) + (" victory" if victory else " defeat")
	var packed := load(SCENE_DIRECTORY + String(case_data.scene)) as PackedScene
	_expect(packed != null, label + ": original scene loads")
	if packed == null:
		return
	var battle := packed.instantiate()
	add_child(battle)
	var question_label := battle.get_node_or_null("CanvasLayer/Panel/QuestionLabel") as Label
	var player_health := battle.get_node_or_null("PlayerHealth")
	var enemy_health := battle.get_node_or_null("EnemyHealth")
	var player_effect := battle.get_node_or_null("player/SlashEffect") as Node2D
	var enemy_effect := battle.get_node_or_null("Bandit/SlashEffect") as Node2D
	var player_portrait := battle.get_node_or_null("player") as Sprite2D
	var enemy_portrait := battle.get_node_or_null("Bandit") as Sprite2D
	var background := battle.get_node_or_null("Sprite2D") as Sprite2D
	var nodes_present := question_label != null and player_health != null and enemy_health != null \
		and player_effect != null and enemy_effect != null and player_portrait != null \
		and enemy_portrait != null and background != null
	_expect(nodes_present, label + ": original question, portraits, effects, and health nodes exist")
	if not nodes_present:
		battle.queue_free()
		await _frames(2)
		return
	_expect(player_portrait.scene_file_path == "res://Battle/" + String(case_data.player) and player_portrait.texture != null, label + ": original gender portrait retained")
	_expect(enemy_portrait.scene_file_path == "res://Battle/" + String(case_data.enemy) and enemy_portrait.texture != null, label + ": original enemy portrait retained")
	_expect(background.scene_file_path == "res://Battle/Bg-battle.tscn" and background.texture != null, label + ": original background retained")
	var load_timeout := get_tree().create_timer(2.0)
	while question_label.text != String(QUESTION.question) and load_timeout.time_left > 0.0:
		await get_tree().process_frame
	_expect(question_label.text == String(QUESTION.question), label + ": delayed provider question reaches original label")
	var choices: Array[Button] = []
	for index in CHOICE_NAMES.size():
		var button := battle.get_node_or_null("CanvasLayer/Panel/" + CHOICE_NAMES[index]) as Button
		_expect(button != null, label + ": original " + CHOICE_NAMES[index] + " exists")
		if button != null:
			choices.append(button)
			_expect(button.text == String(QUESTION.choices[index]) and not button.disabled, label + ": provider fills " + CHOICE_NAMES[index])
	if choices.size() != 4 or question_label.text != String(QUESTION.question):
		battle.queue_free()
		await _frames(2)
		return
	_expect(_health_is(player_health, 3) and _health_is(enemy_health, 3), label + ": original three hearts initialize on both sides")
	var initial_attempts := _results.attempts.size()
	# Exercise the real scene's pressed-signal bindings and health/effect scripts.
	choices[0].pressed.emit()
	_expect(_health_is(enemy_health, 2) and _health_is(player_health, 3) and enemy_effect.visible, label + ": correct answer damages only enemy and plays original effect")
	choices[1].pressed.emit()
	_expect(_health_is(player_health, 2) and _health_is(enemy_health, 2) and player_effect.visible, label + ": wrong answer damages only player and plays original effect")
	choices[0 if victory else 1].pressed.emit()
	var terminal_health: Node = enemy_health if victory else player_health
	var terminal_effect: Node2D = enemy_effect if victory else player_effect
	var animation := terminal_effect.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_expect(_health_is(terminal_health, 1), label + ": terminal answer begins at one remaining heart")
	_expect(animation != null, label + ": original terminal AnimatedSprite2D exists")
	if animation == null:
		battle.queue_free()
		await _frames(2)
		return
	_expect(animation.sprite_frames.get_frame_count(&"explode") == 60 \
		and is_equal_approx(animation.sprite_frames.get_animation_speed(&"explode"), 60.0) \
		and not animation.sprite_frames.get_animation_loop(&"explode"), label + ": original 60-frame 60-fps non-looping explosion retained")

	var events: Array[String] = []
	var outcomes: Array[bool] = []
	var state_before := int(_game_state.total_questions)
	var terminal_text := "YOU WIN!" if victory else "GAME OVER!"
	var detail := {"scene": String(case_data.scene), "victory": victory, "effect_finished_before_signal": false, "frames_alive_before_signal": 0}
	animation.animation_finished.connect(func() -> void: events.append("animation_finished"), CONNECT_ONE_SHOT)
	battle.tree_exiting.connect(func() -> void: events.append("tree_exiting"), CONNECT_ONE_SHOT)
	# Deliberately reproduce QuestUI.gd's existing ownership boundary: the parent
	# queues the VS overlay for deletion as soon as battle_finished is delivered.
	# This does not claim to exercise quest advancement or QuestUI dialogue.
	battle.connect("battle_finished", func(won: bool) -> void:
		detail.effect_finished_before_signal = events.has("animation_finished")
		events.append("battle_finished")
		outcomes.append(won)
		battle.queue_free()
	)
	choices[0 if victory else 1].pressed.emit()
	_expect(question_label.text == terminal_text and question_label.is_visible_in_tree(), label + ": original terminal result text is visible")
	_expect(_health_is(terminal_health, 0), label + ": terminal answer removes the final original heart")
	_expect(terminal_effect.visible and animation.is_playing() and animation.animation == &"explode", label + ": terminal answer starts the original explosion")
	_expect(outcomes.is_empty() and not battle.is_queued_for_deletion(), label + ": terminal overlay must not be freed before the real animation finishes")
	for button in choices:
		_expect(button.disabled, label + ": terminal controls disable immediately")
	# A second answer call must be guarded even while the terminal animation runs.
	battle.call("answer_selected", 0 if victory else 1)
	_expect(int(_game_state.total_questions) == state_before + 1, label + ": repeated terminal answer records once")
	_expect(_health_is(terminal_health, 0), label + ": repeated terminal answer cannot damage again")
	var finish_timeout := get_tree().create_timer(2.5)
	while is_instance_valid(battle) and outcomes.is_empty() and finish_timeout.time_left > 0.0:
		detail.frames_alive_before_signal += 1
		await get_tree().process_frame
	await _frames(2)
	_expect(outcomes == [victory], label + ": exactly one expected battle outcome arrives")
	_expect(bool(detail.effect_finished_before_signal), label + ": animation_finished must precede battle_finished")
	_expect(events == ["animation_finished", "battle_finished", "tree_exiting"], label + ": existing parent teardown follows the complete terminal effect")
	_expect(int(detail.frames_alive_before_signal) > 0, label + ": original terminal presentation survives frames before completion")
	_expect(not is_instance_valid(battle), label + ": parent frees the overlay after the single outcome")
	_expect(_results.attempts.size() == initial_attempts + 4, label + ": duplicate answer cannot duplicate deferred results")
	if _results.attempts.size() > initial_attempts:
		_expect(int(_results.attempts.back().question.get("question_set_id", 0)) == 901, label + ": question-set traceability remains attached to result")
	detail.events = events
	detail.outcomes = outcomes
	_observed.append(detail)
	print("ORIGINAL_BATTLE_PRESENTATION_CASE " + JSON.stringify(detail))
	if is_instance_valid(battle):
		battle.queue_free()
		await _frames(2)


func _health_is(health: Node, expected: int) -> bool:
	if int(health.get("health")) != expected or int(health.get("max_health")) != 3:
		return false
	for index in 3:
		var heart := health.get_node_or_null("Hearts/Heart%d" % (index + 1)) as TextureRect
		if heart == null or heart.texture == null or heart.visible != (index < expected):
			return false
	return true


func _frames(count: int) -> void:
	for frame_index in count:
		await get_tree().process_frame


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		print("FAIL " + label)


func _finish() -> void:
	var failures := 0
	for check in _checks:
		if not bool(check.passed):
			failures += 1
	print("ORIGINAL_BATTLE_PRESENTATION_TEST " + JSON.stringify({
		"passed": _checks.size() - failures,
		"failed": failures,
		"cases": _observed.size(),
		"live_http_calls": 0,
		"save_load_calls": 0,
	}))
	get_tree().quit(0 if failures == 0 else 1)
