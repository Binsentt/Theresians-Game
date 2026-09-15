extends Node

const QuizManagerScript := preload("res://Battle/Battle-Enemy/QuizManager.gd")


class FakeProvider extends Node:
	signal questions_loaded(count: int)
	var questions: Array[Dictionary] = []

	func load_questions() -> Array[Dictionary]:
		await get_tree().create_timer(0.35).timeout
		questions = [{
			"id": "delayed-provider-question",
			"question": "12 + 8 = ?",
			"choices": ["18", "19", "20", "21"],
			"correct": 2,
			"difficulty": "Easy",
		}]
		questions_loaded.emit(questions.size())
		return questions

	func get_question(_filters: Dictionary = {}) -> Dictionary:
		return questions[0].duplicate(true) if not questions.is_empty() else {}

	func get_questions() -> Array[Dictionary]:
		return questions.duplicate(true)


class HealthNode extends Node:
	var health := 3
	func take_damage() -> void:
		health -= 1


class EffectNode extends Node:
	func play_effect() -> void:
		pass


var _checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for autoload_name in ["QuestionProvider", "RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	var provider := FakeProvider.new()
	provider.name = "QuestionProvider"
	get_tree().root.add_child(provider)
	var quiz := Node2D.new()
	quiz.name = "QuizManagerLoadingFixture"
	quiz.set_script(QuizManagerScript)
	_build_quiz_tree(quiz)
	add_child(quiz)
	await get_tree().process_frame
	await get_tree().process_frame

	var question_label := quiz.get_node("CanvasLayer/Panel/QuestionLabel") as Label
	var buttons: Array[Button] = []
	for button_name in ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"]:
		buttons.append(quiz.get_node("CanvasLayer/Panel/" + button_name) as Button)
	_expect(question_label.text == "Preparing your math challenge...", "battle immediately shows the themed question loading state")
	_expect(buttons.all(func(button: Button) -> bool: return button.disabled and button.text.is_empty()), "all four choices stay blank and disabled while questions load")

	await get_tree().create_timer(0.45).timeout
	_expect(question_label.text == "12 + 8 = ?", "real delayed provider question replaces the loading state")
	_expect(buttons.map(func(button: Button) -> String: return button.text) == ["18", "19", "20", "21"], "the original four choice controls receive the provider choices")
	_expect(buttons.all(func(button: Button) -> bool: return not button.disabled), "choices enable only after a valid question is ready")

	quiz.queue_free()
	provider.queue_free()
	_finish()


func _build_quiz_tree(quiz: Node2D) -> void:
	var player_visual := Node2D.new()
	player_visual.name = "player"
	var player_effect := EffectNode.new()
	player_effect.name = "SlashEffect"
	player_visual.add_child(player_effect)
	quiz.add_child(player_visual)
	var enemy_visual := Node2D.new()
	enemy_visual.name = "Bandit"
	var enemy_effect := EffectNode.new()
	enemy_effect.name = "SlashEffect"
	enemy_visual.add_child(enemy_effect)
	quiz.add_child(enemy_visual)
	var player_health := HealthNode.new()
	player_health.name = "PlayerHealth"
	quiz.add_child(player_health)
	var enemy_health := HealthNode.new()
	enemy_health.name = "EnemyHealth"
	quiz.add_child(enemy_health)
	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	var panel := Panel.new()
	panel.name = "Panel"
	var label := Label.new()
	label.name = "QuestionLabel"
	panel.add_child(label)
	for button_name in ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"]:
		var button := Button.new()
		button.name = button_name
		button.text = "stale"
		panel.add_child(button)
	canvas.add_child(panel)
	quiz.add_child(canvas)


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	print("QUIZ_MANAGER_LOADING_STATE_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
