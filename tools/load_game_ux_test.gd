extends Node

const QA_SAVE_ROOT := "user://qa_local_saves"
const LOAD_SCENE_PATH := "res://load_game_scene.tscn"
const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")

var _failures: Array[String] = []
var _save_directory := ""
var _oldest_path := ""
var _middle_path := ""
var _newest_path := ""
var _same_timestamp_newer_date_path := ""
var _fixture_paths: Array[String] = []
var _previous_save_directory := ""

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var http_api := get_node_or_null("/root/HttpApi")
	if http_api == null or not bool(http_api.call("enable_local_qa_mode", "http://127.0.0.1:5000")):
		_fail("Load Game UX test requires explicit local-only API mode.")
		_finish()
		return
	var remote_sync := get_node_or_null("/root/RemoteSync")
	if remote_sync != null:
		remote_sync.call("enable_local_qa_mode")
	var qa_save_id := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_save_directory = "%s/load_game_ux_%s" % [QA_SAVE_ROOT, qa_save_id]
	if DirAccess.dir_exists_absolute(_absolute_path(_save_directory)):
		_fail("Refusing to reuse an existing Load Game UX QA directory.")
		_finish()
		return
	if DirAccess.make_dir_recursive_absolute(_absolute_path(_save_directory)) != OK:
		_fail("Could not create the unique Load Game UX QA directory.")
		_finish()
		return
	_oldest_path = _save_directory + "/save_000_oldest.json"
	_middle_path = _save_directory + "/save_500_middle.json"
	_newest_path = _save_directory + "/save_900_newest.json"
	_same_timestamp_newer_date_path = _save_directory + "/save_100_same_timestamp_newer_date.json"
	_fixture_paths = [_oldest_path, _middle_path, _newest_path, _same_timestamp_newer_date_path]
	_promote_to_root()
	get_tree().current_scene = self
	_configure_live_remote_sync()
	GameState.set_script(load("res://tools/load_game_ux_test_state.gd"))
	_previous_save_directory = GameState.get_save_directory()
	GameState.set("_save_directory", _save_directory)
	GameState.student_id = "001234"
	GameState.parent_id = "123456"
	GameState.device_installation_id = "qa-load-game-ux-device"
	GameState.fixture_paths = _fixture_paths.duplicate()
	_prepare_fixture_saves()
	var loaded_middle := GameState.load_save(_middle_path, false)
	_assert(String(loaded_middle.get("student_id", "")) == "001234" and int(loaded_middle.get("current_task_index", -1)) == 2, "Individual Load preserves the selected save identity and quest fields")

	var initial_scene := await _mount_load_scene()
	var expected_order: Array[String] = [_same_timestamp_newer_date_path, _newest_path, _middle_path, _oldest_path]
	_assert(_save_paths(initial_scene) == expected_order, "Load Game orders entries by saved timestamp, then saved date/time, descending")
	_assert((initial_scene.get_node("TextureRect/SavePanel/MarginContainer/Content/Footer/DeleteAllButton") as Button).visible, "Delete All is placed in the separated Save Panel footer")
	initial_scene.queue_free()
	await get_tree().process_frame

	var restarted_scene := await _mount_load_scene()
	_assert(_save_paths(restarted_scene) == expected_order, "Restarting Load Game preserves timestamp/date ordering")

	var middle_entry := _find_entry(restarted_scene, _middle_path)
	var selected_path: Array[String] = [""]
	if middle_entry != null:
		_assert((middle_entry.get_node("MarginContainer/Content/Actions/LoadButton") as Button).visible, "Individual Load remains visible on each save entry")
	var standalone_entry := SAVE_ENTRY_SCENE.instantiate() as Control
	add_child(standalone_entry)
	standalone_entry.save_selected.connect(func(path: String) -> void: selected_path[0] = path)
	standalone_entry.setup(GameState.peek_save_data(_middle_path))
	(standalone_entry.get_node("MarginContainer/Content/Actions/LoadButton") as Button).pressed.emit()
	standalone_entry.queue_free()
	_assert(selected_path[0] == _middle_path, "Individual Load still targets the selected save")

	var individual_confirmation := restarted_scene.get_node("DeleteSaveConfirmation") as ConfirmationDialog
	restarted_scene.call("_on_delete_requested", _oldest_path)
	await get_tree().process_frame
	_assert(individual_confirmation.visible, "Individual Delete still opens confirmation")
	individual_confirmation.canceled.emit()
	individual_confirmation.hide()
	await get_tree().process_frame
	_assert(FileAccess.file_exists(_absolute_path(_oldest_path)), "Individual Delete cancel preserves the save")
	restarted_scene.call("_on_delete_requested", _oldest_path)
	individual_confirmation.confirmed.emit()
	individual_confirmation.hide()
	await get_tree().process_frame
	_assert(not FileAccess.file_exists(_absolute_path(_oldest_path)) and FileAccess.file_exists(_absolute_path(_middle_path)), "Individual Delete removes only the selected save")

	var delete_all_button := restarted_scene.get_node("TextureRect/SavePanel/MarginContainer/Content/Footer/DeleteAllButton") as Button
	var delete_all_confirmation := restarted_scene.get_node("DeleteAllSaveConfirmation") as ConfirmationDialog
	delete_all_button.pressed.emit()
	await get_tree().process_frame
	_assert(delete_all_confirmation.visible and delete_all_confirmation.dialog_text.to_lower().contains("all saved games"), "Delete All opens a clear all-saves confirmation")
	delete_all_confirmation.canceled.emit()
	delete_all_confirmation.hide()
	await get_tree().process_frame
	_assert(not GameState.list_saves().is_empty() and FileAccess.file_exists(_absolute_path(_middle_path)), "Delete All cancel preserves every remaining save")

	delete_all_button.pressed.emit()
	delete_all_confirmation.confirmed.emit()
	delete_all_confirmation.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	var remaining_after_delete_all := GameState.list_saves()
	var empty_label := restarted_scene.get_node("TextureRect/SavePanel/MarginContainer/Content/EmptyLabel") as Label
	_assert(remaining_after_delete_all.is_empty(), "Delete All confirmation removes every local save entry (remaining=%d)" % remaining_after_delete_all.size())
	_assert(empty_label.visible, "Delete All refreshes to the existing empty/no-save state (visible=%s, text=%s)" % [empty_label.visible, empty_label.text])
	_assert(delete_all_button.disabled, "Delete All disables itself when no saves remain (disabled=%s)" % delete_all_button.disabled)
	restarted_scene.queue_free()
	_cleanup_fixture_saves()

	_finish()

func _mount_load_scene() -> Control:
	var scene := (load(LOAD_SCENE_PATH) as PackedScene).instantiate() as Control
	get_tree().current_scene = self
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame
	return scene

func _prepare_fixture_saves() -> void:
	_write_fixture(_oldest_path, 100, "2026-01-01", "08:00:00", 1)
	_write_fixture(_middle_path, 200, "2026-01-02", "08:00:00", 2)
	_write_fixture(_newest_path, 300, "2026-01-03", "08:00:00", 3)
	_write_fixture(_same_timestamp_newer_date_path, 300, "2026-01-04", "08:00:00", 4)

func _write_fixture(path: String, timestamp: int, save_date: String, save_time: String, sequence: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("fixture save could not be created: %s" % path)
		return
	file.store_string(JSON.stringify({
		"save_version": GameState.SAVE_VERSION,
		"player_name": "Save UX Fixture",
		"gender": "female",
		"grade_level": "Grade 3",
		"student_id": "001234",
		"parent_id": "123456",
		"current_quest": "Fixture Quest",
		"scene_path": "res://interiors/player_house.tscn",
		"player_position": {"x": 128.0, "y": 96.0},
		"current_lives": 2,
		"max_lives": 3,
		"current_task_index": 2,
		"correct_answers": 4,
		"incorrect_answers": 1,
		"save_kind": "manual",
		"manual_save_sequence": sequence,
		"save_date": save_date,
		"save_time": save_time,
		"save_timestamp": timestamp,
	}))
	file.close()

func _save_paths(scene: Control) -> Array[String]:
	var paths: Array[String] = []
	var saves_container := scene.get_node("TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer") as VBoxContainer
	for entry in saves_container.get_children():
		paths.append(String(entry.get("save_path")))
	return paths

func _find_entry(scene: Control, save_path: String) -> Control:
	var saves_container := scene.get_node("TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer") as VBoxContainer
	for entry in saves_container.get_children():
		if String(entry.get("save_path")) == save_path:
			return entry as Control
	return null

func _configure_live_remote_sync() -> void:
	var live := get_node_or_null("/root/RemoteSync")
	if live != null:
		live.set_script(load("res://tools/load_game_ux_remote_stub.gd"))

func _promote_to_root() -> void:
	var tree := get_tree()
	var parent_node := get_parent()
	if tree != null and parent_node != null:
		parent_node.remove_child(self)
		tree.root.add_child(self)

func _cleanup_fixture_saves() -> void:
	for path in _fixture_paths:
		if not path.begins_with(_save_directory + "/"):
			push_error("Refusing to clean a Load Game UX fixture outside its unique QA directory.")
			continue
		if FileAccess.file_exists(_absolute_path(path)):
			DirAccess.remove_absolute(_absolute_path(path))
	if not _save_directory.is_empty() and _save_directory.begins_with(QA_SAVE_ROOT + "/"):
		DirAccess.remove_absolute(_absolute_path(_save_directory))
	if not _previous_save_directory.is_empty():
		GameState.set("_save_directory", _previous_save_directory)

func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _fail(message: String) -> void:
	_failures.append(message)

func _finish() -> void:
	var report := {"passed": 0, "failed": _failures.size(), "failures": _failures}
	var report_file := FileAccess.open("user://load_game_ux_test_result.json", FileAccess.WRITE)
	if report_file != null:
		report["passed"] = 14 - _failures.size()
		report_file.store_string(JSON.stringify(report))
		report_file.close()
	if _failures.is_empty():
		print("LOAD_GAME_UX_TEST: PASS")
		await get_tree().create_timer(45.0).timeout
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOAD_GAME_UX_TEST: FAIL")
	await get_tree().create_timer(45.0).timeout
	get_tree().quit(1)
