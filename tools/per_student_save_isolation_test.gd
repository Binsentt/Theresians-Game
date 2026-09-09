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
	_assert(GameState.list_saves().is_empty(), "No current Student identity exposes no device-local saves")
	_assert(GameState.peek_save_data(A_NEW).is_empty(), "No current Student identity cannot inspect an owned save by direct path")
	_assert(not GameState.delete_save(A_OLD), "No current Student identity cannot delete an owned save by direct path")
	_assert(FileAccess.file_exists(OWNERLESS_LEGACY), "Ownerless legacy data is preserved while hidden")

	GameState.student_id = STUDENT_A
	GameState.parent_id = PARENT_A
	_assert(_paths(GameState.list_saves()) == [A_NEW, A_OLD], "Student A sees only Student A saves, newest first")
	_assert(GameState.peek_save_data(B_ONLY).is_empty(), "Student A cannot inspect Student B save by direct path")
	var before_cross_load := GameState.student_id
	_assert(GameState.load_save(B_ONLY, false).is_empty(), "Student A cannot load Student B save by direct path")
	_assert(GameState.student_id == before_cross_load, "Rejected cross-Student load cannot replace Student A identity")
	_assert(not GameState.delete_save(B_ONLY), "Student A cannot delete Student B save by direct path")
	_assert(FileAccess.file_exists(B_ONLY), "Rejected cross-Student delete preserves Student B save")
	_assert(_find_path(GameState.list_saves(), OWNERLESS_LEGACY).is_empty(), "Ownerless legacy save is hidden from Student A")
	_assert(GameState.peek_save_data(OWNERLESS_LEGACY).is_empty(), "Ownerless legacy save cannot be inspected directly")
	_assert(not GameState.delete_save(OWNERLESS_LEGACY), "Ownerless legacy save cannot be deleted through another Student")

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
	_assert(not FileAccess.file_exists(A_OLD) and not FileAccess.file_exists(A_NEW), "Delete All removes every current-Student save")
	_assert(FileAccess.file_exists(B_ONLY), "Delete All preserves another Student's save")
	_assert(FileAccess.file_exists(OWNERLESS_LEGACY), "Delete All preserves ownerless legacy data")
	var empty_label := load_scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/EmptyLabel") as Label
	_assert(empty_label != null and empty_label.visible and empty_label.text == "No save data found", "Delete All refreshes Student A to the empty state")
	load_scene.queue_free()
	await get_tree().process_frame

	GameState.student_id = STUDENT_B
	GameState.parent_id = PARENT_B
	_assert(_paths(GameState.list_saves()) == [B_ONLY], "Student B sees only Student B save")
	_assert(GameState.delete_save(B_ONLY), "Student B can delete Student B save")
	_assert(not FileAccess.file_exists(B_ONLY), "Owned individual delete removes only Student B save")
	_assert(FileAccess.file_exists(OWNERLESS_LEGACY), "Ownership enforcement leaves ownerless legacy data untouched")

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
		print("PER_STUDENT_SAVE_ISOLATION_TEST PASSED checks=%d failures=0" % _check_count)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("PER_STUDENT_SAVE_ISOLATION_TEST FAILED checks=%d failures=%d" % [_check_count, _failures.size()])
	get_tree().quit(1)
