extends Node2D

const QuestionProviderScript = preload("res://scripts/question_provider.gd")

signal battle_finished(success: bool)

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
var _provider_load_completed := false
var _battle_finished_emitted := false

func _ready():
	_provider = get_node_or_null("/root/QuestionProvider")
	if _provider == null:
		_provider = QuestionProviderScript.new()
		_provider.name = "QuestionProvider"
		get_tree().root.add_child(_provider)

	# Load questions from provider if available, otherwise empty
	if _provider != null and _provider.has_method("load_questions"):
		_provider_load_completed = false
		var connected := false
		if _provider.has_signal("questions_loaded"):
			connected = _provider.connect("questions_loaded", Callable(self, "_on_questions_loaded"), CONNECT_ONE_SHOT) == OK
		_provider.call("load_questions")
		if connected:
			while not _provider_load_completed:
				await get_tree().process_frame
		var loaded = _provider.call("get_questions") if _provider.has_method("get_questions") else []
		if loaded is Array:
			questions = Array(loaded)
		else:
			questions = []
	else:
		questions = []

	if questions.is_empty():
		question_label.text = "No questions found!"
		disable_buttons()
		return

	# Initialize the first question
	load_question()


func _on_questions_loaded(_count: int) -> void:
	_provider_load_completed = true


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
	if _battle_finished_emitted:
		return
	var q: Dictionary = _current_question_data
	if q.is_empty() and current_question < questions.size():
		q = questions[current_question]
	if q is Dictionary:
		var is_correct := index == int(q.get("correct", -1))
		_record_question_attempt(q, is_correct)
		if is_correct:
			print("Correct!")
			enemy_effect.play_effect()
			enemy.take_damage()
		else:
			print("Wrong!")
			player_effect.play_effect()
			player.take_damage()

	if enemy.health <= 0:
		question_label.text = "YOU WIN!"
		_finish_battle(true)
		return

	if player.health <= 0:
		question_label.text = "GAME OVER!"
		_finish_battle(false)
		return

	load_question()


func _record_question_attempt(question: Dictionary, is_correct: bool) -> void:
	# Keep battle damage and progression untouched; this only projects the result into Save Game analytics.
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.total_questions += 1
		if is_correct:
			game_state.correct_answers += 1
		else:
			game_state.incorrect_answers += 1
		var question_difficulty := String(question.get("difficulty", game_state.difficulty_level)).strip_edges()
		if not question_difficulty.is_empty():
			game_state.difficulty_level = question_difficulty

	var remote_sync := get_node_or_null("/root/RemoteSync")
	if remote_sync != null and remote_sync.has_method("record_question_attempt"):
		# RemoteSync durably appends the answer before its first await. Invoke it
		# immediately so a scene change or crash cannot cancel the enqueue.
		remote_sync.call("record_question_attempt", question.duplicate(true), is_correct)


func disable_buttons():

	for button in buttons:
		button.disabled = true


func _finish_battle(success: bool) -> void:
	if _battle_finished_emitted:
		return
	_battle_finished_emitted = true
	disable_buttons()
	# Keep the original final hit and result visible until the existing effect
	# finishes; the quest owner frees this scene when battle_finished is emitted.
	var terminal_effect: Node2D = enemy_effect if success else player_effect
	var animation := terminal_effect.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if animation != null and animation.is_playing():
		await animation.animation_finished
	battle_finished.emit(success)


func _on_choice_a_pressed():
	answer_selected(0)

func _on_choice_b_pressed():
	answer_selected(1)

func _on_choice_c_pressed():
	answer_selected(2)

func _on_choice_d_pressed():
	answer_selected(3)
