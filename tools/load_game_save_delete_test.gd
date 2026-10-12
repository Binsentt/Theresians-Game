extends Node

const FIRST_SAVE_NAME := "save_delete_regression_first.json"
const SECOND_SAVE_NAME := "save_delete_regression_second.json"
const LEGACY_SAVE_NAME := "save_delete_regression_legacy.json"
const MALFORMED_SAVE_NAME := "save_delete_regression_malformed.json"
const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")
const SAVE_ENTRY_SCENE_PATH := "res://ui/save_entry.tscn"
const SAVE_ENTRY_SCRIPT_PATH := "res://scripts/save_entry.gd"
const LOAD_GAME_SCENE_PATH := "res://load_game_scene.tscn"
const LOAD_GAME_SCRIPT_PATH := "res://scripts/load_game_scene.gd"

var _failures: Array[String] = []
var _check_count := 0
var _selected_path := ""
var _deleted_path := ""
var _previous_save_directory := ""
var _run_directory := ""
var _first_save_path := ""
var _second_save_path := ""
var _legacy_save_path := ""
var _malformed_save_path := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var http := get_node_or_null("/root/HttpApi")
	var remote_sync := get_node_or_null("/root/RemoteSync")
	if http == null or not http.has_method("is_local_qa_mode") or not bool(http.call("is_local_qa_mode")):
		_fail("save/delete test refuses to run unless HttpApi selected local QA before autoload startup")
		_finish()
		return
	if remote_sync == null or not bool(remote_sync.get("local_qa_only")):
		_fail("save/delete test refuses to run unless RemoteSync is local-only")
		_finish()
		return
	GameState.enable_local_qa_mode()
	_previous_save_directory = GameState.get_save_directory()
	_run_directory = "%s/test_runs/load_game_save_delete_%d_%d" % [
		GameState.get_save_directory(),
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	if DirAccess.dir_exists_absolute(_absolute_path(_run_directory)):
		_fail("unique save/delete fixture directory unexpectedly already exists")
		_finish()
		return
	GameState._save_directory = _run_directory
	_first_save_path = _run_directory.path_join(FIRST_SAVE_NAME)
	_second_save_path = _run_directory.path_join(SECOND_SAVE_NAME)
	_legacy_save_path = _run_directory.path_join(LEGACY_SAVE_NAME)
	_malformed_save_path = _run_directory.path_join(MALFORMED_SAVE_NAME)
	GameState.student_id = "001234"
	GameState.parent_id = "009876"
	_prepare_fixture_saves()
	if not GameState.has_method("delete_save"):
		_fail("GameState must expose delete_save for selected local saves")
		_cleanup_fixture_saves()
		_finish()
		return

	_assert(FileAccess.file_exists(_absolute_path(_first_save_path)), "first fixture save exists before deletion")
	_assert(FileAccess.file_exists(_absolute_path(_second_save_path)), "second fixture save exists before deletion")
	_assert_legacy_and_malformed_save_handling()
	_assert(not GameState.delete_save("user://outside-save.json"), "paths outside the save directory are rejected")
	_assert(not GameState.delete_save(_run_directory.path_join("nested/save.json")), "nested save paths are rejected")
	await _assert_delete_ui_contract()

	_cleanup_fixture_saves()
	_finish()


func _prepare_fixture_saves() -> void:
	var make_directory_error := DirAccess.make_dir_recursive_absolute(_absolute_path(_run_directory))
	if make_directory_error != OK:
		_fail("isolated save/delete fixture directory could not be created")
		return
	_write_fixture(_first_save_path, "First Test Save", 1)
	_write_fixture(_second_save_path, "Second Test Save", 2)
	_write_legacy_fixture()
	_write_malformed_fixture()


func _write_fixture(path: String, player_name: String, sequence: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("fixture save could not be created: %s" % path)
		return
	file.store_string(JSON.stringify({
		"player_name": player_name,
		"student_id": "001234",
		"parent_id": "009876",
		"save_kind": "manual",
		"manual_save_sequence": sequence,
		"grade_level": "Grade 1",
		"current_quest": "Test Quest",
		"scene_path": GameState.START_SCENE_PATH,
		"save_date": "2026-08-24",
		"save_time": "10:00:00",
		"save_timestamp": sequence,
	}))
	file.close()


func _write_legacy_fixture() -> void:
	var file := FileAccess.open(_legacy_save_path, FileAccess.WRITE)
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
	var file := FileAccess.open(_malformed_save_path, FileAccess.WRITE)
	if file == null:
		_fail("malformed fixture save could not be created")
		return
	file.store_string("{ invalid save json")
	file.close()


func _assert_legacy_and_malformed_save_handling() -> void:
	var saves := GameState.list_saves()
	var legacy_save := _find_save(saves, _legacy_save_path)
	var malformed_save := _find_save(saves, _malformed_save_path)
	var legacy_data := GameState.call("_read_save_file", _legacy_save_path) as Dictionary
	var prepared_legacy := GameState.call("_prepare_save_entry", legacy_data, _legacy_save_path) as Dictionary
	_assert(legacy_save.is_empty(), "ambiguous legacy saves without an explicit manual marker remain hidden")
	_assert(bool(prepared_legacy.get("loadable", false)), "legacy metadata with omitted optional fields still receives safe load defaults")
	_assert(String(prepared_legacy.get("scene_path", "")) == GameState.START_SCENE_PATH, "legacy metadata defaults a missing scene without making the entry visible")
	_assert(FileAccess.file_exists(_absolute_path(_legacy_save_path)), "hidden ambiguous legacy source data is preserved")
	_assert(malformed_save.is_empty(), "malformed saves with no provable owner remain hidden")
	_assert(FileAccess.file_exists(_absolute_path(_malformed_save_path)), "hidden malformed data is preserved safely")


func _cleanup_fixture_saves() -> void:
	if _run_directory.is_empty():
		return
	var directory := DirAccess.open(_absolute_path(_run_directory))
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir():
			DirAccess.remove_absolute(_absolute_path(_run_directory.path_join(file_name)))
		file_name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(_absolute_path(_run_directory))
	if not _previous_save_directory.is_empty():
		GameState._save_directory = _previous_save_directory


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
	_assert(load_script_source.contains("dialog.exclusive = true"), "delete confirmation enables exclusivity during runtime configuration")
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
	save_entry.setup({"save_path": _second_save_path, "player_name": "Second Test Save"})
	(save_entry.get_node("MarginContainer/Content/Actions/LoadButton") as Button).pressed.emit()
	(save_entry.get_node("MarginContainer/Content/Actions/DeleteButton") as Button).pressed.emit()
	_assert(_selected_path == _second_save_path, "Load action targets only its save")
	_assert(_deleted_path == _second_save_path, "Delete action targets only its save")
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
	_assert(_save_list_contains_path(saves_container, _first_save_path), "initial Load Game list contains the first save")
	_assert(_save_list_contains_path(saves_container, _second_save_path), "initial Load Game list contains the second save")
	_assert(not _save_list_contains_path(saves_container, _legacy_save_path), "Load Game hides ambiguous legacy data without a manual marker")
	_assert(not _save_list_contains_path(saves_container, _malformed_save_path), "Load Game does not expose malformed data with no provable owner")

	load_scene.call("_on_delete_requested", _first_save_path)
	await get_tree().process_frame
	_assert(confirmation.visible, "Delete requests open the confirmation dialog")
	var delete_all_confirmation := load_scene.get_node("DeleteAllSaveConfirmation") as ConfirmationDialog
	var delete_all_button := load_scene.get_node("TextureRect/SavePanel/MarginContainer/Content/Footer/DeleteAllButton") as Button
	var delete_all_rect := delete_all_button.get_global_rect()
	var background_click := InputEventMouseButton.new()
	background_click.position = delete_all_rect.get_center()
	background_click.button_index = MOUSE_BUTTON_LEFT
	background_click.pressed = true
	get_viewport().push_input(background_click, true)
	background_click.pressed = false
	get_viewport().push_input(background_click, true)
	await get_tree().process_frame
	_assert(not delete_all_confirmation.visible, "exclusive single-save confirmation blocks the underlying Delete All button")
	confirmation.canceled.emit()
	await get_tree().process_frame
	_assert(FileAccess.file_exists(_absolute_path(_first_save_path)), "cancel preserves the selected save")
	_assert(_save_list_contains_path(saves_container, _first_save_path), "cancel keeps the selected save in the Load Game list")

	load_scene.call("_on_delete_requested", _first_save_path)
	confirmation.confirmed.emit()
	await get_tree().process_frame
	_assert(not FileAccess.file_exists(_absolute_path(_first_save_path)), "confirmed deletion removes only the selected save")
	_assert(FileAccess.file_exists(_absolute_path(_second_save_path)), "confirmed deletion preserves every other save")
	_assert(not _save_list_contains_path(saves_container, _first_save_path), "Load Game refreshes immediately after deletion")
	_assert(_save_list_contains_path(saves_container, _second_save_path), "refreshed Load Game list retains the other save")
	_assert(not GameState.delete_save(_first_save_path), "deleting an already deleted save fails safely")

	load_scene.call("_on_delete_requested", _malformed_save_path)
	confirmation.confirmed.emit()
	await get_tree().process_frame
	_assert(FileAccess.file_exists(_absolute_path(_malformed_save_path)), "a crafted delete request cannot remove ownerless malformed data")
	_assert(_save_list_contains_path(saves_container, _second_save_path), "rejected malformed delete preserves valid saves")
	load_scene.queue_free()


func _save_list_contains_path(saves_container: VBoxContainer, save_path: String) -> bool:
	if saves_container == null:
		return false
	for entry in saves_container.get_children():
		if String(entry.get("save_path")) == save_path:
			return true
	return false


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
	_check_count += 1
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	var file := FileAccess.open("user://load_game_save_delete_test_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"passed": _check_count - _failures.size(),
			"failed": _failures.size(),
			"failures": _failures,
			"fixture_directory": _run_directory,
			"qa_local_only": true,
			"production_requests": 0,
			"production_writes": 0,
		}, "\t"))
		file.close()
	if _failures.is_empty():
		print("LOAD_GAME_SAVE_DELETE_TEST: PASS checks=%d failures=0" % _check_count)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOAD_GAME_SAVE_DELETE_TEST: FAIL checks=%d failures=%d" % [_check_count, _failures.size()])
	get_tree().quit(1)
