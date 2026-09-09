extends Node

const SAVE_DIRECTORY := "user://saves"
const LEGACY_SAVE_PATH := SAVE_DIRECTORY + "/save_data_compatibility_legacy.json"
const MALFORMED_SAVE_PATH := SAVE_DIRECTORY + "/save_data_compatibility_malformed.json"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.student_id = "001234"
	GameState.parent_id = "009876"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	_write_fixture(LEGACY_SAVE_PATH, JSON.stringify({
		"student_id": "001234",
		"parent_id": "009876",
		"save_timestamp": 2,
	}))
	_write_fixture(MALFORMED_SAVE_PATH, "{ malformed save json")

	var saves := GameState.list_saves()
	var legacy_save := _find_save(saves, LEGACY_SAVE_PATH)
	var malformed_save := _find_save(saves, MALFORMED_SAVE_PATH)
	_assert(bool(legacy_save.get("loadable", false)), "legacy saves with omitted optional metadata remain loadable")
	_assert(String(legacy_save.get("scene_path", "")) == GameState.START_SCENE_PATH, "legacy saves default a missing scene safely")
	var loaded_legacy := GameState.load_save(LEGACY_SAVE_PATH, false)
	_assert(not loaded_legacy.is_empty(), "loadable legacy saves continue through the normal load path")
	_assert(GameState.current_scene_path == GameState.START_SCENE_PATH, "legacy load resumes at the safe default scene")
	_assert(not malformed_save.is_empty(), "malformed saves remain visible for individual cleanup")
	_assert(not bool(malformed_save.get("loadable", true)), "malformed saves are never loadable")
	_assert(not String(malformed_save.get("save_error", "")).is_empty(), "malformed saves show an unavailable reason")
	_assert(GameState.load_save(MALFORMED_SAVE_PATH, false).is_empty(), "malformed saves are rejected by the normal load path")
	_assert(GameState.delete_save(MALFORMED_SAVE_PATH), "only the selected malformed local file can be deleted")
	_assert(FileAccess.file_exists(LEGACY_SAVE_PATH), "deleting malformed data leaves other local saves intact")

	_cleanup()
	if _failures.is_empty():
		print("LOAD_GAME_SAVE_DATA_COMPATIBILITY_TEST: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOAD_GAME_SAVE_DATA_COMPATIBILITY_TEST: FAIL")
	get_tree().quit(1)


func _write_fixture(save_path: String, content: String) -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_fail("fixture could not be created: %s" % save_path)
		return
	file.store_string(content)
	file.close()


func _find_save(saves: Array[Dictionary], save_path: String) -> Dictionary:
	for save_data in saves:
		if String(save_data.get("save_path", "")) == save_path:
			return save_data
	return {}


func _cleanup() -> void:
	for save_path in [LEGACY_SAVE_PATH, MALFORMED_SAVE_PATH]:
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)
