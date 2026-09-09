extends Node

const SAVE_DIRECTORY := "user://saves"
const STUDENT_A := "88000001"
const STUDENT_B := "88000002"
const PARENT_A := "880001"
const PARENT_B := "880002"
const A_OLD := SAVE_DIRECTORY + "/save_owner_test_a_old.json"
const A_NEW := SAVE_DIRECTORY + "/save_owner_test_a_new.json"
const B_ONLY := SAVE_DIRECTORY + "/save_owner_test_b_only.json"
const OWNERLESS_LEGACY := SAVE_DIRECTORY + "/save_owner_test_ambiguous_legacy.json"
const LOAD_SCENE := preload("res://load_game_scene.tscn")

var _failures: Array[String] = []
var _check_count := 0
var _fixture_paths: Array[String] = [A_OLD, A_NEW, B_ONLY, OWNERLESS_LEGACY]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	_remove_live_transport()
	GameState.set_script(load("res://tools/load_game_ux_test_state.gd"))
	GameState.fixture_paths = _fixture_paths
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	_cleanup()
	_write_save(A_OLD, STUDENT_A, PARENT_A, 100, "A old")
	_write_save(A_NEW, STUDENT_A, PARENT_A, 300, "A new")
	_write_save(B_ONLY, STUDENT_B, PARENT_B, 200, "B only")
	_write_ownerless_legacy()

	GameState.student_id = ""
	GameState.parent_id = ""
	_assert(_paths(GameState.list_saves()) == [OWNERLESS_LEGACY, A_NEW, B_ONLY, A_OLD], "The device list exposes every local save newest first without a current Student")
	var legacy_entry := _find_path(GameState.list_saves(), OWNERLESS_LEGACY)
	_assert(not legacy_entry.is_empty(), "An ownerless legacy file remains visible for recovery or deletion")
	_assert(not bool(legacy_entry.get("loadable", true)), "An incompatible ownerless legacy file is shown truthfully as unavailable")
	_assert(FileAccess.file_exists(OWNERLESS_LEGACY), "Listing never deletes an ownerless legacy file")

	var inspected_b := GameState.peek_save_data(B_ONLY)
	_assert(String(inspected_b.get("student_id", "")) == STUDENT_B, "A local save can be inspected without matching the current runtime identity")
	var loaded_b := GameState.load_save(B_ONLY, false)
	_assert(not loaded_b.is_empty(), "A compatible local save loads without an identity gate")
	_assert(GameState.student_id == STUDENT_B and GameState.parent_id == PARENT_B, "Loading restores that save's Student and Parent metadata")
	_assert(GameState.player_name == "B only" and GameState.current_task_index == 3, "Loading restores that save's profile and progression")
	_assert(String(GameState.peek_save_data(A_NEW).get("student_id", "")) == STUDENT_A, "Another Student's local save remains selectable after a load")

	_assert(GameState.delete_save(A_OLD), "Individual Delete removes the selected device-local save regardless of active identity")
	_assert(not FileAccess.file_exists(A_OLD), "Individual Delete removes only its local file")
	_assert(FileAccess.file_exists(A_NEW) and FileAccess.file_exists(B_ONLY) and FileAccess.file_exists(OWNERLESS_LEGACY), "Individual Delete preserves every other local save")

	_assert(GameState.has_method("delete_all_saves"), "GameState retains the local Delete All service")
	var load_scene := LOAD_SCENE.instantiate() as Control
	get_tree().root.add_child(load_scene)
	get_tree().current_scene = load_scene
	await get_tree().process_frame
	await get_tree().process_frame
	load_scene.call("_on_delete_all_requested")
	load_scene.call("_on_delete_all_confirmed")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_all_fixture_files_absent(), "Delete All removes all save files on this installation, including other saved identities")
	var empty_label := load_scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/EmptyLabel") as Label
	_assert(empty_label != null and empty_label.visible and empty_label.text == "No save data found", "Delete All refreshes the actual Load Game screen to its empty state")
	load_scene.queue_free()
	await get_tree().process_frame

	_cleanup()
	_finish()


func _write_save(path: String, owner_id: String, relationship_id: String, timestamp: int, player: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create fixture %s" % path)
		return
	file.store_string(JSON.stringify({
		"save_version": GameState.SAVE_VERSION,
		"player_name": player,
		"gender": "female",
		"grade_level": "Grade 3",
		"student_id": owner_id,
		"parent_id": relationship_id,
		"current_quest": "Defeat All Bandits",
		"scene_path": "res://scenes/oak_leaf_village.tscn",
		"player_position": {"x": 100.0, "y": 100.0},
		"current_lives": 3,
		"max_lives": 3,
		"current_task_index": 3,
		"save_date": "2026-09-09",
		"save_time": "18:%02d:00" % timestamp,
		"save_timestamp": timestamp,
	}))
	file.close()


func _write_ownerless_legacy() -> void:
	var file := FileAccess.open(OWNERLESS_LEGACY, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create ownerless legacy fixture")
		return
	file.store_string(JSON.stringify({
		"player_name": "Legacy Device Save",
		"scene_path": "res://interiors/player_house.tscn",
		"save_timestamp": 400,
	}))
	file.close()


func _paths(saves: Array[Dictionary]) -> Array[String]:
	var paths: Array[String] = []
	for save_data in saves:
		paths.append(String(save_data.get("save_path", "")))
	return paths


func _find_path(saves: Array[Dictionary], path: String) -> Dictionary:
	for save_data in saves:
		if String(save_data.get("save_path", "")) == path:
			return save_data
	return {}


func _all_fixture_files_absent() -> bool:
	for path in _fixture_paths:
		if FileAccess.file_exists(path):
			return false
	return true


func _remove_live_transport() -> void:
	var remote_sync := get_node_or_null("/root/RemoteSync")
	if remote_sync != null:
		remote_sync.set_script(load("res://tools/load_game_ux_remote_stub.gd"))
	var http_api := get_node_or_null("/root/HttpApi")
	if http_api != null:
		http_api.free()


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)
	tree.current_scene = self


func _cleanup() -> void:
	for path in _fixture_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert(condition: bool, message: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var report := {
		"passed": _check_count - _failures.size(),
		"failed": _failures.size(),
		"failures": _failures,
	}
	var file := FileAccess.open("res://tools/per_student_save_isolation_test_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if _failures.is_empty():
		print("DEVICE_LOCAL_SAVE_MODEL_TEST PASSED checks=%d failures=0" % _check_count)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("DEVICE_LOCAL_SAVE_MODEL_TEST FAILED checks=%d failures=%d" % [_check_count, _failures.size()])
	get_tree().quit(1)
