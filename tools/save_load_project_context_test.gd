extends Node

const TEST_SCENE := "res://interiors/player_house.tscn"
const PREVIOUS_SCHEMA_SAVE := "user://saves/project_context_previous_schema_save.json"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	# Keep the real serializer/loader while isolating writes in this canonical run.
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var autoload := get_node_or_null("/root/" + autoload_name)
		if autoload != null:
			autoload.free()
	GameState.set_script(load("res://tools/preservation_regression_state.gd"))
	if FileAccess.file_exists(PREVIOUS_SCHEMA_SAVE):
		_assert(false, "Previous-schema fixture path must be absent; existing user data is preserved")
		_finish()
		return
	GameState.apply_save_data({
		"save_version": GameState.SAVE_VERSION,
		"player_name": "Verification Student",
		"gender": "female",
		"grade_level": "Grade 3",
		"student_id": "000123",
		"parent_id": "654321",
		"current_quest": "Verification Quest",
		"scene_path": TEST_SCENE,
		"player_position": {"x": 128.0, "y": 96.0},
		"current_lives": 2,
		"max_lives": 3,
		"current_task_index": 2,
	}, false)
	var save_path := GameState.save_game()
	_assert(not save_path.is_empty() and FileAccess.file_exists(save_path), "Current-state save is written to isolated user data")

	GameState.apply_save_data({"scene_path": "res://scenes/main_menu.tscn", "current_lives": 1, "max_lives": 3, "current_task_index": 0}, false)
	var loaded := GameState.load_save(save_path, false)
	_assert(not loaded.is_empty(), "Isolated save loads successfully")
	_assert(GameState.current_scene_path == TEST_SCENE, "Load restores the saved scene")
	_assert(GameState.player_position == Vector2(128.0, 96.0), "Load restores player position")
	_assert(GameState.current_lives == 2 and GameState.max_lives == 3, "Load restores player lives")
	_assert(GameState.current_task_index == 2 and GameState.current_quest == String(GameState.tasks[2].get("quest_text", "")), "Load restores the authoritative checkpoint and reconciles its saved quest title")

	var previous_file := FileAccess.open(PREVIOUS_SCHEMA_SAVE, FileAccess.WRITE)
	_assert(previous_file != null, "Previous-schema fixture can be created in isolated user data")
	if previous_file != null:
		previous_file.store_string(JSON.stringify({
			"save_version": 5,
			"student_id": "000123",
			"parent_id": "654321",
			"scene_path": TEST_SCENE,
			"current_quest": "Previous Schema",
			"current_task_index": 99,
		}))
		previous_file.close()
		var previous_loaded := GameState.load_save(PREVIOUS_SCHEMA_SAVE, false)
		_assert(not previous_loaded.is_empty(), "Previous-schema saves use the existing compatibility path")
		_assert(GameState.current_task_index == GameState.tasks.size(), "Existing compatibility clamps old task indexes safely")

	_cleanup_file(save_path)
	_cleanup_file(PREVIOUS_SCHEMA_SAVE)
	_finish()


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _cleanup_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SAVE_LOAD_PROJECT_CONTEXT_TEST PASSED")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SAVE_LOAD_PROJECT_CONTEXT_TEST FAILED")
	get_tree().quit(1)
