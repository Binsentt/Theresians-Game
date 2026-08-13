extends SceneTree

const QuizManagerScript = preload("res://Battle/Battle-Enemy/QuizManager.gd")

class FakeProvider extends Node:
	func load_questions() -> Array[Dictionary]:
		await get_tree().create_timer(0.01).timeout
		return [{
			"id": "provider-question",
			"question": "2 + 2 = ?",
			"choices": ["3", "4", "5", "6"],
			"correct": "1",
		}]

	func get_question(_filters: Dictionary = {}) -> Dictionary:
		return {
			"id": "provider-question",
			"question": "2 + 2 = ?",
			"choices": ["3", "4", "5", "6"],
			"correct": "1",
		}

	func get_questions() -> Array[Dictionary]:
		return [{
			"id": "provider-question",
			"question": "2 + 2 = ?",
			"choices": ["3", "4", "5", "6"],
			"correct": "1",
		}]

class HealthNode extends Node:
	var health: int = 3
	func take_damage() -> void:
		health -= 1

class EffectNode extends Node:
	func play_effect() -> void:
		pass

func _init() -> void:
	var provider := FakeProvider.new()
	provider.name = "QuestionProvider"
	root.add_child(provider)

	var quiz := Node2D.new()
	quiz.set_script(QuizManagerScript)
	_build_quiz_tree(quiz)
	root.add_child(quiz)

	await create_timer(0.05).timeout
	var question_label: Label = quiz.get_node("CanvasLayer/Panel/QuestionLabel")
	if question_label.text != "2 + 2 = ?":
		printerr("[QuizManager Test] Expected delayed provider question, got: %s" % question_label.text)
		quiz.queue_free()
		provider.queue_free()
		quit(1)
		return

	quiz.queue_free()
	provider.queue_free()
	quit()

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
		panel.add_child(button)
	canvas.add_child(panel)
	quiz.add_child(canvas)
