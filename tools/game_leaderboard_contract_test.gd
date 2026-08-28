extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var remote_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	var controller_source := FileAccess.get_file_as_string("res://scripts/leaderboard_scene_controller.gd")
	_expect(remote_source.contains("func request_game_leaderboard"), "RemoteSync must provide the game leaderboard request owned by the active lease.")
	var leaderboard_block := _function_block(remote_source, "func request_game_leaderboard")
	_expect(leaderboard_block.contains("/api/game/leaderboard"), "Game leaderboard must use the game endpoint rather than a portal route.")
	_expect(leaderboard_block.contains("session_id") and leaderboard_block.contains("session_credential") and leaderboard_block.contains("learning_cycle_version"), "Game leaderboard requests must carry only the current playtime lease and cycle.")
	var projection_block := _function_block(remote_source, "func _sanitize_game_leaderboard_entries")
	_expect(projection_block.contains("display_name") and projection_block.contains("progress_percentage") and projection_block.contains("accuracy_rate"), "RemoteSync must preserve the approved privacy-safe leaderboard fields.")
	_expect(not projection_block.contains("student_id") and not projection_block.contains("parent_id") and not projection_block.contains("email"), "RemoteSync must discard sensitive leaderboard fields.")
	_expect(controller_source.contains("request_game_leaderboard"), "Leaderboard controller must request data through RemoteSync.")
	_expect(not controller_source.contains("/api/leaderboard/top-achievers"), "Leaderboard controller must not call a portal-only route directly.")
	_expect(controller_source.contains("_refresh_generation"), "Leaderboard controller must ignore older responses after a newer refresh.")
	_expect(controller_source.contains("No rankings yet"), "An empty current-cycle leaderboard must use a truthful no-ranking state.")
	_finish()


func _function_block(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + signature.length())
	return source.substr(start) if next < 0 else source.substr(start, next - start)


func _finish() -> void:
	if _failures.is_empty():
		print("game_leaderboard_contract_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
