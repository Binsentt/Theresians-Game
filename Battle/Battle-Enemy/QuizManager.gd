extends Node2D

const QuestionProviderScript = preload("res://scripts/question_provider.gd")

# Character Nodes
@onready var player_character = $player
@onready var enemy_character = $Bandit

# Slash Effects
@onready var player_effect = $player/SlashEffect
@onready var enemy_effect = $Bandit/SlashEffect

# Health Systems
@onready var player = $PlayerHealth
@onready var enemy = $EnemyHealth

# UI
@onready var question_label = $CanvasLayer/Panel/QuestionLabel

@onready var buttons = [
	$CanvasLayer/Panel/ChoiceA,
	$CanvasLayer/Panel/ChoiceB,
	$CanvasLayer/Panel/ChoiceC,
	$CanvasLayer/Panel/ChoiceD
]

var current_question := 0
var questions: Array[Dictionary] = []
var _provider: Node = null
var _current_question_data: Dictionary = {}

func _ready():
	_provider = get_node_or_null("/root/QuestionProvider")
	if _provider == null:
		_provider = QuestionProviderScript.new()
		_provider.name = "QuestionProvider"
		get_tree().root.add_child(_provider)
	_provider.call("load_questions")
	questions = _provider.call("load_questions") if _provider.has_method("load_questions") else []

	if questions.is_empty():
		question_label.text = "No questions found!"
		disable_buttons()
		return

	load_question()
		# Prefer using the shared QuestionProvider autoload for question data.
		if _provider != null and _provider.has_method("load_questions"):
			questions = Array(_provider.call("load_questions"))
			return

		# If provider is unexpectedly missing, ensure UI is disabled and log.
		questions = []
		push_error("QuestionProvider not available; no questions loaded")
		disable_buttons()
	if json.data is Array:
		for entry in json.data:
			if entry is Dictionary:
				questions.append(entry)


func load_question():
	if _provider != null and _provider.has_method("get_question"):
		var q: Dictionary = _provider.call("get_question")
		if q.is_empty():
			return
		_current_question_data = q
		question_label.text = String(q.get("question", ""))
		var choices: Array = q.get("choices", ["", "", "", ""])
		for i in range(buttons.size()):
			buttons[i].text = String(choices[i] if i < choices.size() else "")
		return

	current_question += 1
	if current_question >= questions.size():
		current_question = 0
		questions.shuffle()

	var q: Dictionary = questions[current_question]
	_current_question_data = q
	question_label.text = String(q.get("question", ""))
	var choices: Array = q.get("choices", ["", "", "", ""])
	for i in range(buttons.size()):
		buttons[i].text = String(choices[i] if i < choices.size() else "")


func answer_selected(index:int):
	var q: Dictionary = _current_question_data
	if q.is_empty() and current_question < questions.size():
		q = questions[current_question]
	if q is Dictionary:
		if index == int(q.get("correct", -1)):
			print("Correct!")
			enemy_effect.play_effect()
			enemy.take_damage()
		else:
			print("Wrong!")
			player_effect.play_effect()
			player.take_damage()

	if enemy.health <= 0:
		question_label.text = "YOU WIN!"
		disable_buttons()
		return

	if player.health <= 0:
		question_label.text = "GAME OVER!"
		disable_buttons()
		return

	load_question()


func disable_buttons():

	for button in buttons:
		button.disabled = true


func _on_choice_a_pressed():
	answer_selected(0)

func _on_choice_b_pressed():
	answer_selected(1)

func _on_choice_c_pressed():
	answer_selected(2)

func _on_choice_d_pressed():
	answer_selected(3)
