extends Node

const QuestionProviderScript := preload("res://scripts/question_provider.gd")

var _failures: Array[String] = []
var _questions_loaded_count := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Keep this runner alive while it drives production scene changes or autoloads.
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)

	var game_state := get_node_or_null("/root/GameState")
	_assert(game_state != null, "Project-context test requires the GameState autoload")
	_assert(get_node_or_null("/root/HttpApi") != null, "Project-context test requires the HttpApi autoload")
	if game_state != null:
		game_state.encounter_context.clear()
		game_state.battle_active = false

	var provider := QuestionProviderScript.new()
	provider.name = "StartupProviderUnderTest"
	provider.questions_loaded.connect(_on_questions_loaded)
	get_tree().root.add_child(provider)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert(
		_questions_loaded_count == 0,
		"QuestionProvider startup must not request remote questions before an encounter exists"
	)

	provider.queue_free()
	await get_tree().process_frame
	_finish()


func _on_questions_loaded(_count: int) -> void:
	_questions_loaded_count += 1


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("QUESTION_PROVIDER_STARTUP_CONTEXT_TEST PASSED")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("QUESTION_PROVIDER_STARTUP_CONTEXT_TEST FAILED")
	get_tree().quit(1)
