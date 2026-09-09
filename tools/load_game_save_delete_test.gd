extends Node

const SAVE_DIRECTORY := "user://saves"
const FIRST_SAVE_PATH := SAVE_DIRECTORY + "/save_delete_regression_first.json"
const SECOND_SAVE_PATH := SAVE_DIRECTORY + "/save_delete_regression_second.json"
const LEGACY_SAVE_PATH := SAVE_DIRECTORY + "/save_delete_regression_legacy.json"
const MALFORMED_SAVE_PATH := SAVE_DIRECTORY + "/save_delete_regression_malformed.json"
const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")
const SAVE_ENTRY_SCENE_PATH := "res://ui/save_entry.tscn"
const SAVE_ENTRY_SCRIPT_PATH := "res://scripts/save_entry.gd"
const LOAD_GAME_SCENE_PATH := "res://load_game_scene.tscn"
const LOAD_GAME_SCRIPT_PATH := "res://scripts/load_game_scene.gd"

var _failures: Array[String] = []
var _selected_path := ""
var _deleted_path := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.student_id = "001234"
	GameState.parent_id = "009876"
	_prepare_fixture_saves()
	if not GameState.has_method("delete_save"):
		_fail("GameState must expose delete_save for selected local saves")
		_cleanup_fixture_saves()
		_finish()
		return

	_assert(FileAccess.file_exists(_absolute_path(FIRST_SAVE_PATH)), "first fixture save exists before deletion")
	_assert(FileAccess.file_exists(_absolute_path(SECOND_SAVE_PATH)), "second fixture save exists before deletion")
	_assert_legacy_and_malformed_save_handling()
	_assert(not GameState.delete_save("user://outside-save.json"), "paths outside the save directory are rejected")
	_assert(not GameState.delete_save("user://saves/nested/save.json"), "nested save paths are rejected")
	await _assert_delete_ui_contract()

	_cleanup_fixture_saves()
	_finish()


func _prepare_fixture_saves() -> void:
	DirAccess.make_dir_recursive_absolute(_absolute_path(SAVE_DIRECTORY))
	_write_fixture(FIRST_SAVE_PATH, "First Test Save")
	_write_fixture(SECOND_SAVE_PATH, "Second Test Save")
	_write_legacy_fixture()
	_write_malformed_fixture()


func _write_fixture(path: String, player_name: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("fixture save could not be created: %s" % path)
		return
	file.store_string(JSON.stringify({
		"player_name": player_name,
		"student_id": "001234",
		"parent_id": "009876",
		"grade_level": "Grade 1",
		"current_quest": "Test Quest",
		"save_date": "2026-08-24",
		"save_time": "10:00:00",
		"save_timestamp": 1,
	}))
	file.close()


func _write_legacy_fixture() -> void:
	var file := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_fail("legacy fixture save could not be created")
		return
	file.store_string(JSON.stringify({
		"student_id": "001234",
		"parent_id": "009876",
		"save_timestamp": 2,
	}))
	file.close()


func _write_malformed_fixture() -> void:
	var file := FileAccess.open(MALFORMED_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_fail("malformed fixture save could not be created")
		return
	file.store_string("{ invalid save json")
	file.close()


func _assert_legacy_and_malformed_save_handling() -> void:
	var saves := GameState.list_saves()
	var legacy_save := _find_save(saves, LEGACY_SAVE_PATH)
	var malformed_save := _find_save(saves, MALFORMED_SAVE_PATH)
	_assert(not legacy_save.is_empty(), "legacy saves remain visible")
	_assert(bool(legacy_save.get("loadable", false)), "legacy saves with optional fields omitted use safe defaults")
	_assert(String(legacy_save.get("scene_path", "")) == GameState.START_SCENE_PATH, "legacy saves default a missing scene to the player house")
	_assert(malformed_save.is_empty(), "malformed saves without provable Student ownership remain hidden")
	_assert(GameState.peek_save_data(MALFORMED_SAVE_PATH).is_empty(), "malformed saves cannot be accessed by direct path")
	_assert(not GameState.delete_save(MALFORMED_SAVE_PATH), "malformed saves are preserved rather than assigned to the current Student")


func _cleanup_fixture_saves() -> void:
	for path in [FIRST_SAVE_PATH, SECOND_SAVE_PATH, LEGACY_SAVE_PATH, MALFORMED_SAVE_PATH]:
		if FileAccess.file_exists(_absolute_path(path)):
			DirAccess.remove_absolute(_absolute_path(path))


func _assert_delete_ui_contract() -> void:
	var save_entry_source := FileAccess.get_file_as_string(SAVE_ENTRY_SCENE_PATH)
	var save_entry_script_source := FileAccess.get_file_as_string(SAVE_ENTRY_SCRIPT_PATH)
	var load_scene_source := FileAccess.get_file_as_string(LOAD_GAME_SCENE_PATH)
	var load_script_source := FileAccess.get_file_as_string(LOAD_GAME_SCRIPT_PATH)
	_assert(save_entry_source.contains('node name="LoadButton" type="Button"'), "each save entry exposes an explicit Load button")
	_assert(save_entry_source.contains('node name="DeleteButton" type="Button"'), "each save entry exposes an explicit Delete button")
	_assert(save_entry_source.contains('node name="SaveEntry" type="PanelContainer"'), "save metadata remains in a themed panel container")
	_assert(load_scene_source.contains('node name="DeleteSaveConfirmation" type="ConfirmationDialog"'), "Load Game owns one delete confirmation dialog")
	_assert(load_scene_source.contains('dialog_text = "Delete this save?"'), "delete confirmation uses the approved prompt")
	_assert(load_scene_source.contains("exclusive = true"), "delete confirmation is exclusive")
	_assert(save_entry_script_source.contains("signal save_delete_requested(save_path: String)"), "save entries expose a selected-save delete signal")
	_assert(load_script_source.contains("func _on_delete_confirmed() -> void:"), "Load Game handles confirmed deletion")
	_assert(load_script_source.contains("GameState.delete_save(save_path)"), "confirmed deletion calls the local save owner")
	_assert(load_script_source.contains("func _on_delete_canceled() -> void:"), "Load Game handles canceled deletion")
	_assert(not _function_source(load_script_source, "_on_delete_canceled").contains("delete_save"), "cancel never deletes a save")

	if not _failures.is_empty():
		return
	var save_entry := SAVE_ENTRY_SCENE.instantiate()
	add_child(save_entry)
	_selected_path = ""
	_deleted_path = ""
	save_entry.save_selected.connect(_on_save_selected)
	save_entry.save_delete_requested.connect(_on_save_delete_requested)
	save_entry.setup({"save_path": SECOND_SAVE_PATH, "player_name": "Second Test Save"})
	(save_entry.get_node("MarginContainer/Content/Actions/LoadButton") as Button).pressed.emit()
	(save_entry.get_node("MarginContainer/Content/Actions/DeleteButton") as Button).pressed.emit()
	_assert(_selected_path == SECOND_SAVE_PATH, "Load action targets only its save")
	_assert(_deleted_path == SECOND_SAVE_PATH, "Delete action targets only its save")
	save_entry.queue_free()

	if not _failures.is_empty():
		return

	var load_scene: Control = (load(LOAD_GAME_SCENE_PATH) as PackedScene).instantiate() as Control
	add_child(load_scene)
	await get_tree().process_frame
	var confirmation := load_scene.get_node("DeleteSaveConfirmation") as ConfirmationDialog
	var saves_container := load_scene.get_node("TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer") as VBoxContainer
	_assert(confirmation != null, "the actual Main Menu Load Game scene has a confirmation dialog")
	_assert(confirmation.exclusive, "confirmation blocks background actions while a save is pending")
	_assert(_save_list_contains_path(saves_container, FIRST_SAVE_PATH), "initial Load Game list contains the first save")
	_assert(_save_list_contains_path(saves_container, SECOND_SAVE_PATH), "initial Load Game list contains the second save")
	_assert(not _save_list_contains_path(saves_container, MALFORMED_SAVE_PATH), "Load Game does not expose an ownerless malformed save to this Student")

	load_scene.call("_on_delete_requested", FIRST_SAVE_PATH)
	await get_tree().process_frame
	_assert(confirmation.visible, "Delete requests open the confirmation dialog")
	confirmation.canceled.emit()
	await get_tree().process_frame
	_assert(FileAccess.file_exists(_absolute_path(FIRST_SAVE_PATH)), "cancel preserves the selected save")
	_assert(_save_list_contains_path(saves_container, FIRST_SAVE_PATH), "cancel keeps the selected save in the Load Game list")

	load_scene.call("_on_delete_requested", FIRST_SAVE_PATH)
	confirmation.confirmed.emit()
	await get_tree().process_frame
	_assert(not FileAccess.file_exists(_absolute_path(FIRST_SAVE_PATH)), "confirmed deletion removes only the selected save")
	_assert(FileAccess.file_exists(_absolute_path(SECOND_SAVE_PATH)), "confirmed deletion preserves every other save")
	_assert(not _save_list_contains_path(saves_container, FIRST_SAVE_PATH), "Load Game refreshes immediately after deletion")
	_assert(_save_list_contains_path(saves_container, SECOND_SAVE_PATH), "refreshed Load Game list retains the other save")
	_assert(not GameState.delete_save(FIRST_SAVE_PATH), "deleting an already deleted save fails safely")

	_assert(FileAccess.file_exists(_absolute_path(MALFORMED_SAVE_PATH)), "ownerless malformed data remains untouched for deliberate recovery")
	_assert(_save_list_contains_path(saves_container, SECOND_SAVE_PATH), "ownership filtering preserves valid current-Student saves")
	load_scene.queue_free()


func _save_list_contains_path(saves_container: VBoxContainer, save_path: String) -> bool:
	if saves_container == null:
		return false
	for entry in saves_container.get_children():
		if String(entry.get("save_path")) == save_path:
			return true
	return false


func _get_save_entry(saves_container: VBoxContainer, save_path: String) -> Control:
	if saves_container == null:
		return null
	for entry in saves_container.get_children():
		if String(entry.get("save_path")) == save_path:
			return entry as Control
	return null


func _find_save(saves: Array[Dictionary], save_path: String) -> Dictionary:
	for save_data in saves:
		if String(save_data.get("save_path", "")) == save_path:
			return save_data
	return {}


func _function_source(source: String, function_name: String) -> String:
	var start := source.find("func %s(" % function_name)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + 1)
	return source.substr(start, next - start if next >= 0 else -1)


func _on_save_selected(path: String) -> void:
	_selected_path = path


func _on_save_delete_requested(path: String) -> void:
	_deleted_path = path


func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("LOAD_GAME_SAVE_DELETE_TEST: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOAD_GAME_SAVE_DELETE_TEST: FAIL")
	get_tree().quit(1)
