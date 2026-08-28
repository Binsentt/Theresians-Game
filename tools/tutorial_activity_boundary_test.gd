extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_state_source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var tutorial_source := FileAccess.get_file_as_string("res://interiors/TutorialNPC.gd")
	var remote_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	_expect(game_state_source.contains("\"tutorial_activity\""), "Tutorial activity metadata must live on the existing canonical task data.")
	_expect(game_state_source.contains("func emit_tutorial_activity_started"), "GameState must emit the initial Tutorial activity only through its canonical boundary.")
	_expect(game_state_source.contains("func complete_tutorial_activity"), "GameState must expose one dedicated Tutorial completion boundary.")
	_expect(game_state_source.contains("canonical_activity_boundary"), "Tutorial activity must use GameState's canonical activity boundary signal, not a second quest list.")
	_expect(tutorial_source.contains("complete_tutorial_activity"), "The real TutorialNPC completion callback must emit Tutorial completion.")
	_expect(tutorial_source.contains("_tutorial_activity_completed"), "Repeated Tutorial input must not emit duplicate completion activity.")
	var lease_block := _function_block(remote_source, "func _on_progression_session_reset")
	_expect(lease_block.contains("emit_tutorial_activity_started"), "Tutorial start must be emitted only after the normal New Game lease attempt succeeds.")
	_expect(lease_block.contains("source == \"new_game\""), "Load Game must not invent a new Tutorial start activity.")
	_expect(not tutorial_source.contains("advance_task_and_save"), "Tutorial observability must not advance or reorder the existing quest state.")
	_finish()


func _function_block(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + signature.length())
	return source.substr(start) if next < 0 else source.substr(start, next - start)


func _finish() -> void:
	if _failures.is_empty():
		print("tutorial_activity_boundary_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
