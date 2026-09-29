extends Node

const QuizManagerScript := preload("res://Battle/Battle-Enemy/QuizManager.gd")

class FakeProvider extends Node:
	signal questions_loaded(count: int)
	var load_calls := 0
	var last_load_error_code := ""
	var questions: Array[Dictionary] = []

	func load_questions() -> Array[Dictionary]:
		load_calls += 1
		await get_tree().create_timer(0.15).timeout
		if load_calls == 1:
			last_load_error_code = "network"
			questions.clear()
			questions_loaded.emit(0)
			return []
		last_load_error_code = ""
		questions = [{
			"id": "retry-question",
			"question": "12 + 8 = ?",
			"choices": ["18", "19", "20", "21"],
			"correct": 2,
			"difficulty": "Easy",
		}]
		questions_loaded.emit(questions.size())
		return questions

	func get_questions() -> Array[Dictionary]:
		return questions.duplicate(true)

	func get_question(_filters: Dictionary = {}) -> Dictionary:
		return questions[0].duplicate(true) if not questions.is_empty() else {}


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
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	var local_profile_active := http != null and bool(http.call("is_local_qa_profile_active"))
	_expect(local_profile_active, "network retry fixture starts with the loopback-only API profile")
	if not local_profile_active:
		_finish()
		return
	_expect(http != null and bool(http.call("enable_local_qa_mode", "http://127.0.0.1:5000")), "QA HTTP boundary is loopback-only")
	if remote != null:
		remote.call("enable_local_qa_mode")
		_expect(bool(remote.get("local_qa_only")), "RemoteSync writes are disabled for this test")

	var previous_provider := get_node_or_null("/root/QuestionProvider")
	if previous_provider != null:
		previous_provider.free()
	var provider := FakeProvider.new()
	provider.name = "QuestionProvider"
	get_tree().root.add_child(provider)

	var quiz := Node2D.new()
	quiz.name = "QuizManagerNetworkRetryFixture"
	quiz.set_script(QuizManagerScript)
	_build_quiz_tree(quiz)
	add_child(quiz)
	await get_tree().process_frame
	var question_label := quiz.get_node("CanvasLayer/Panel/QuestionLabel") as Label
	var buttons: Array[Button] = []
	for button_name in ["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"]:
		buttons.append(quiz.get_node("CanvasLayer/Panel/" + button_name) as Button)
	_expect(question_label.text == "Loading questions...", "the real question request has a clear in-place loading state")
	var failure_wait_frames := 120
	while question_label.text == "Loading questions..." and failure_wait_frames > 0:
		await get_tree().process_frame
		failure_wait_frames -= 1
	_expect(question_label.text.contains("Connection lost"), "a transient fetch failure is not presented as an empty question set")
	_expect(buttons[0].text == "Retry Questions" and not buttons[0].disabled, "retry is available in the current encounter")
	_expect(buttons.slice(1).all(func(button: Button) -> bool: return button.disabled), "answer choices stay disabled while reconnecting")
	var player_health: HealthNode = quiz.get_node("PlayerHealth")
	var enemy_health: HealthNode = quiz.get_node("EnemyHealth")
	buttons[0].pressed.emit()
	buttons[0].pressed.emit()
	var retry_wait_frames := 120
	while (provider.load_calls < 2 or question_label.text != "12 + 8 = ?") and retry_wait_frames > 0:
		await get_tree().process_frame
		retry_wait_frames -= 1
	_expect(provider.load_calls == 2, "repeated retry input does not create duplicate question requests")
	_expect(question_label.text == "12 + 8 = ?", "the same battle resumes with its fetched question")
	_expect(buttons.map(func(button: Button) -> String: return button.text) == ["18", "19", "20", "21"], "all four original answer choices are restored")
	_expect(buttons.all(func(button: Button) -> bool: return not button.disabled), "choices enable only after questions arrive")
	_expect(player_health.health == 3 and enemy_health.health == 3, "retry does not consume an answer, health, or encounter progress")
	_verify_android_export_permission()
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
	var handlers := ["_on_choice_a_pressed", "_on_choice_b_pressed", "_on_choice_c_pressed", "_on_choice_d_pressed"]
	for index in range(4):
		panel.get_node(["ChoiceA", "ChoiceB", "ChoiceC", "ChoiceD"][index]).pressed.connect(Callable(quiz, handlers[index]))


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _verify_android_export_permission() -> void:
	var config := ConfigFile.new()
	var load_error := config.load("res://export_presets.cfg")
	_expect(load_error == OK, "Android export preset is readable for connectivity verification")
	if load_error != OK:
		return
	var android_section := ""
	for section in config.get_sections():
		if not String(section).begins_with("preset.") or String(section).ends_with(".options"):
			continue
		if String(config.get_value(section, "platform", "")) == "Android":
			android_section = String(section) + ".options"
			break
	_expect(not android_section.is_empty(), "An Android export preset exists")
	if not android_section.is_empty():
		_expect(bool(config.get_value(android_section, "permissions/internet", false)), "Android APK export grants the Internet permission required by website APIs")


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	print("QUIZ_MANAGER_NETWORK_RETRY_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(30.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
