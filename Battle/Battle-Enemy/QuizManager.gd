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
var _network_retry_available := false
var _network_retry_in_progress := false
var _current_question_presented_at := ""
var _current_question_presented_unix := -1.0
var _music_return_scene_path := ""

func _ready():
	_music_return_scene_path = _resolve_music_return_scene_path()
	var music_manager := get_node_or_null("/root/MusicManager")
	if music_manager != null and music_manager.has_method("play_for_scene"):
		music_manager.call("play_for_scene", scene_file_path)
	question_label.text = "Loading questions..."
	for button in buttons:
		button.text = ""
	disable_buttons()
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
		_show_question_load_failure()
		return

	# Initialize the first question
	load_question()


func _exit_tree() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == self:
		return
	var music_manager := tree.root.get_node_or_null("MusicManager")
	if music_manager != null and music_manager.has_method("play_for_scene") and not _music_return_scene_path.is_empty():
		music_manager.call("play_for_scene", _music_return_scene_path)


func _resolve_music_return_scene_path() -> String:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		var context: Variant = game_state.get("encounter_context")
		if context is Dictionary:
			var source_scene_path := String(context.get("source_scene_path", "")).strip_edges()
			if not source_scene_path.is_empty():
				return source_scene_path
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene.scene_file_path
	return ""


func _on_questions_loaded(_count: int) -> void:
	_provider_load_completed = true


func load_question():
	if _network_retry_available or _network_retry_in_progress:
		return
	if _provider != null and _provider.has_method("get_question"):
		var provider_question: Dictionary = _provider.call("get_question")
		if provider_question.is_empty():
			return
		_set_presented_question(provider_question)
		question_label.text = String(provider_question.get("question", ""))
		var provider_choices: Array = provider_question.get("choices", ["", "", "", ""])
		for i in range(buttons.size()):
			buttons[i].text = String(provider_choices[i] if i < provider_choices.size() else "")
		enable_buttons()
		return

	current_question += 1
	if current_question >= questions.size():
		current_question = 0
		questions.shuffle()

	var q: Dictionary = questions[current_question]
	_set_presented_question(q)
	question_label.text = String(q.get("question", ""))
	var choices: Array = q.get("choices", ["", "", "", ""])
	for i in range(buttons.size()):
		buttons[i].text = String(choices[i] if i < choices.size() else "")
	enable_buttons()


func answer_selected(index:int):
	if _battle_finished_emitted or _network_retry_available or _network_retry_in_progress:
		return
	var q: Dictionary = _current_question_data.duplicate(true)
	if q.is_empty() and current_question < questions.size():
		q = questions[current_question]
	if q is Dictionary:
		var answer_submitted_unix := Time.get_unix_time_from_system()
		q["question_presented_at"] = _current_question_presented_at
		q["answer_submitted_at"] = Time.get_datetime_string_from_system(true) + "Z"
		if _current_question_presented_unix >= 0.0:
			q["response_time_seconds"] = maxi(0, int(answer_submitted_unix - _current_question_presented_unix))
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


func _set_presented_question(question: Dictionary) -> void:
	_current_question_data = question.duplicate(true)
	_current_question_presented_unix = Time.get_unix_time_from_system()
	_current_question_presented_at = Time.get_datetime_string_from_system(true) + "Z"


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


func enable_buttons() -> void:
	for button in buttons:
		button.disabled = false


func _show_question_load_failure() -> void:
	disable_buttons()
	for button in buttons:
		button.text = ""
	var error_code := String(_provider.get("last_load_error_code")) if _provider != null else ""
	if error_code == "network":
		_network_retry_available = true
		question_label.text = "Connection lost. Retry to continue this battle."
		buttons[0].text = "Retry Questions"
		buttons[0].disabled = false
		return
	question_label.text = "No questions are available for this challenge."


func _retry_questions() -> void:
	if _network_retry_in_progress or not _network_retry_available or _provider == null:
		return
	_network_retry_available = false
	_network_retry_in_progress = true
	question_label.text = "Reconnecting... Loading questions..."
	disable_buttons()
	for button in buttons:
		button.text = ""
	var loaded: Variant = await _provider.call("load_questions")
	if loaded is Array:
		questions = Array(loaded)
	elif _provider.has_method("get_questions"):
		var provider_questions: Variant = _provider.call("get_questions")
		questions = Array(provider_questions) if provider_questions is Array else []
	else:
		questions = []
	_network_retry_in_progress = false
	if questions.is_empty():
		_show_question_load_failure()
		return
	load_question()


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
	if _network_retry_available:
		_retry_questions()
		return
	answer_selected(0)

func _on_choice_b_pressed():
	answer_selected(1)

func _on_choice_c_pressed():
	answer_selected(2)

func _on_choice_d_pressed():
	answer_selected(3)
