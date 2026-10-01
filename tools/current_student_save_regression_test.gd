extends Node

const STUDENT_A := "88001001"
const STUDENT_B := "88001002"
const STUDENT_C := "88001003"
const PARENT_A := "880011"
const PARENT_B := "880012"
const PARENT_C := "880013"
const VALID_SCENE := "res://scenes/oak_leaf_village.tscn"
const MANUAL_SAVE_SCENES := [
	"res://scenes/oak_leaf_village.tscn",
	"res://scenes/city_of_knowledge.tscn",
	"res://scenes/2nd Village/Pinehill Village.tscn",
]

var _checks := 0
var _failures: Array[String] = []
var _test_directory := ""
var _original_save_directory := ""
var _original_device_id := ""
var _test_device_id := ""
var _test_directory_created := false
var _run_id := ""
var _manual_paths_a: Array[String] = []
var _manual_path_b := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_disable_live_transport()
	GameState.enable_local_qa_mode()
	_original_save_directory = GameState.get_save_directory()
	_original_device_id = String(GameState.get("device_installation_id"))
	_test_device_id = "qa-save-device-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_run_id = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_directory = "%s/current_save_regression_%d_%d" % [
		GameState.LOCAL_QA_SAVE_DIRECTORY,
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	var absolute_test_directory := ProjectSettings.globalize_path(_test_directory)
	if DirAccess.dir_exists_absolute(absolute_test_directory):
		_failures.append("Refusing to reuse an existing QA fixture directory")
		_finish()
		return
	_test_directory_created = DirAccess.make_dir_recursive_absolute(absolute_test_directory) == OK
	_assert(_test_directory_created, "Creates a unique disposable QA-local save directory")
	if not _test_directory_created:
		_finish()
		return
	GameState.set("_save_directory", _test_directory)
	GameState.set("device_installation_id", _test_device_id)

	_test_manual_save_count_and_snapshots()
	_test_autosave_checkpoint()
	_test_save_entrypoint_wiring()
	await _test_load_game_list_shows_manual_slots()
	_test_student_isolation()
	_test_legacy_checkpoint_migration()
	_test_manual_delete_scope()
	await _test_load_game_badge()
	_finish()


func _test_manual_save_count_and_snapshots() -> void:
	_set_student(STUDENT_A, PARENT_A, "QA Student A")
	_assert(GameState.list_saves().is_empty(), "Fresh test Student starts without a save")
	for save_number in range(3):
		GameState.current_scene_path = MANUAL_SAVE_SCENES[save_number]
		GameState.current_map = MANUAL_SAVE_SCENES[save_number]
		GameState.current_task_index = save_number + 1
		GameState.current_quest = GameState.get_current_quest_text()
		GameState.player_position = Vector2(110.0 + save_number, 205.0 + save_number)
		GameState.total_play_time = 100 + save_number * 60
		GameState.score = 10 + save_number
		var manual_path := GameState.save_manual_game()
		_manual_paths_a.append(manual_path)
		_assert(not manual_path.is_empty() and FileAccess.file_exists(manual_path), "Manual save %d is durably written" % (save_number + 1))
		_assert(not _manual_paths_a.slice(0, save_number).has(manual_path), "Manual save %d has its own distinct snapshot path" % (save_number + 1))
		_assert(GameState.list_saves().size() == save_number + 1, "%d manual save(s) produce exactly %d visible entry/entries" % [save_number + 1, save_number + 1])
		var entries: Array[Dictionary] = GameState.list_saves()
		var snapshot: Dictionary = GameState.peek_save_data(manual_path)
		_assert(String(snapshot.get("save_kind", "")) == "manual", "Visible entry %d is explicitly marked manual" % (save_number + 1))
		_assert(int(snapshot.get("manual_save_sequence", 0)) == save_number + 1, "Manual save receives the next Student-owned sequence number")
		if entries.size() > save_number:
			_assert(String(entries[save_number].get("save_path", "")) == manual_path, "Manual saves are listed in Student sequence order")
		else:
			_assert(false, "Manual saves are listed in Student sequence order")

	for save_number in range(_manual_paths_a.size()):
		GameState.player_position = Vector2.ZERO
		GameState.current_task_index = 0
		GameState.total_play_time = 0
		GameState.score = 0
		var loaded: Dictionary = GameState.load_save(_manual_paths_a[save_number], false)
		_assert(not loaded.is_empty(), "Student A can load manual save %d" % (save_number + 1))
		_assert(GameState.current_scene_path == MANUAL_SAVE_SCENES[save_number], "Manual save %d restores its own scene" % (save_number + 1))
		_assert(GameState.current_map == MANUAL_SAVE_SCENES[save_number], "Manual save %d restores its own map" % (save_number + 1))
		_assert(GameState.player_position == Vector2(110.0 + save_number, 205.0 + save_number), "Manual save %d restores its own position" % (save_number + 1))
		_assert(GameState.current_task_index == save_number + 1, "Manual save %d restores its own quest checkpoint" % (save_number + 1))
		_assert(GameState.current_quest == GameState.get_current_quest_text(), "Manual save %d restores the canonical quest for its checkpoint" % (save_number + 1))
		_assert(GameState.total_play_time == 100 + save_number * 60 and GameState.score == 10 + save_number, "Manual save %d restores its own playtime and battle score" % (save_number + 1))


func _test_autosave_checkpoint() -> void:
	_set_student(STUDENT_A, PARENT_A, "QA Student A")
	var checkpoint_path := _current_path(STUDENT_A)
	_assert(GameState.has_method("save_checkpoint"), "GameState exposes an explicit internal checkpoint writer")
	var first_checkpoint := _call_checkpoint()
	_assert(first_checkpoint == checkpoint_path and FileAccess.file_exists(checkpoint_path), "Autosave writes the deterministic hidden Student checkpoint")
	_assert(GameState.list_saves().size() == 3, "The first internal checkpoint does not add a visible manual save")
	for checkpoint_number in range(5):
		GameState.player_position = Vector2(300.0 + checkpoint_number, 400.0 + checkpoint_number)
		GameState.total_play_time = 900 + checkpoint_number
		var repeated_checkpoint := _call_checkpoint()
		_assert(repeated_checkpoint == checkpoint_path, "Repeated autosave %d updates the same hidden checkpoint" % (checkpoint_number + 1))
		_assert(GameState.list_saves().size() == 3, "Repeated autosave %d leaves visible manual count unchanged" % (checkpoint_number + 1))
	var checkpoint: Dictionary = GameState.peek_save_data(checkpoint_path)
	_assert(String(checkpoint.get("save_kind", "")) == "checkpoint", "Checkpoint is explicitly marked as an internal autosave")
	_assert(GameState.player_position == Vector2(304.0, 404.0) and GameState.total_play_time == 904, "Checkpoint retains the latest runtime state")
	_assert(FileAccess.file_exists(_recovery_path(STUDENT_A)), "Checkpoint keeps a recovery copy for interruption safety")
	var progression_result: Dictionary = GameState.advance_task_and_save({
		"type": "task_completed",
		"title": "QA checkpoint",
		"description": "Synthetic local save regression checkpoint.",
	})
	_assert(bool(progression_result.get("advanced", false)), "Canonical task progression advances in the save fixture")
	_assert(String(progression_result.get("save_path", "")) == checkpoint_path, "Progression autosave returns the hidden checkpoint path")
	_assert(GameState.list_saves().size() == 3, "Progression autosave never adds a visible manual entry")
	var progressed_checkpoint: Dictionary = GameState.peek_save_data(checkpoint_path)
	_assert(int(progressed_checkpoint.get("current_task_index", -1)) == int(GameState.current_task_index), "Progression checkpoint stores the advanced quest state")


func _test_save_entrypoint_wiring() -> void:
	var settings_source := FileAccess.get_file_as_string("res://scenes/Settings-Ingame/settings_ingame_controller.gd")
	var remote_sync_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	_assert(settings_source.contains("GameState.save_manual_game()"), "Settings Save action creates a visible manual save")
	_assert(settings_source.contains("GameState.save_checkpoint()"), "Settings exit persists to the hidden checkpoint")
	_assert(remote_sync_source.contains("GameState.save_checkpoint()"), "RemoteSync timeout persists to the hidden checkpoint")
	_assert(not remote_sync_source.contains("GameState.save_game()"), "RemoteSync never creates a visible manual save")


func _test_load_game_list_shows_manual_slots() -> void:
	_set_student(STUDENT_A, PARENT_A, "QA Student A")
	var load_scene := (load("res://load_game_scene.tscn") as PackedScene).instantiate() as Control
	get_tree().root.add_child(load_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var saves_container := load_scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer") as VBoxContainer
	_assert(saves_container != null and saves_container.get_child_count() == 3, "Load Game renders only the three manual saves, not the hidden checkpoint")
	if saves_container != null and saves_container.get_child_count() == 3:
		for index in range(3):
			var entry := saves_container.get_child(index) as Control
			var caption := entry.get_node_or_null("MarginContainer/Content/SlotBadge/BadgeContent/SlotCaption") as Label
			var number := entry.get_node_or_null("MarginContainer/Content/SlotBadge/BadgeContent/SlotNumber") as Label
			_assert(caption != null and caption.text == "SAVE", "Manual slot caption %d is SAVE" % (index + 1))
			_assert(number != null and number.text == str(index + 1), "Manual slot is labeled SAVE %d in per-Student order" % (index + 1))
			var load_button := entry.get_node_or_null("MarginContainer/Content/Actions/LoadButton") as Button
			var delete_button := entry.get_node_or_null("MarginContainer/Content/Actions/DeleteButton") as Button
			_assert(load_button != null and delete_button != null, "Manual save %d keeps its Load and Delete actions" % (index + 1))
	load_scene.queue_free()
	await get_tree().process_frame


func _test_student_isolation() -> void:
	var a_path := _manual_paths_a[0]
	_set_student(STUDENT_B, PARENT_B, "QA Student B")
	GameState.player_position = Vector2(32.0, 48.0)
	var b_path := GameState.save_game()
	_manual_path_b = b_path
	_assert(not b_path.is_empty() and b_path != a_path, "Another Student receives a separate manual save")
	_assert(GameState.list_saves().size() == 1 and String(GameState.list_saves()[0].get("save_path", "")) == b_path, "Student B sees only Student B's manual save")
	_assert(GameState.peek_save_data(a_path).is_empty(), "Student B cannot inspect Student A's save")
	_assert(GameState.load_save(a_path, false).is_empty(), "Student B cannot load Student A's save")
	_assert(not GameState.delete_save(a_path), "Student B cannot delete Student A's save")
	_assert(FileAccess.file_exists(a_path), "Rejected cross-Student delete preserves Student A's manual save")
	_set_student(STUDENT_A, PARENT_A, "QA Student A")
	_assert(GameState.list_saves().size() == 3, "Returning to Student A restores only Student A's three manual entries")


func _test_legacy_checkpoint_migration() -> void:
	var old_path := _test_directory + "/save_%s_20260101_100000.json" % STUDENT_C
	var newest_path := _test_directory + "/save_%s_20260201_100000.json" % STUDENT_C
	var invalid_newest_path := _test_directory + "/save_%s_20260301_100000.json" % STUDENT_C
	var ownerless_path := _test_directory + "/legacy_owner_unknown.json"
	var mismatched_device_path := _test_directory + "/legacy_device_mismatch.json"
	_write_fixture(old_path, STUDENT_C, PARENT_C, 100, "Older Legacy", VALID_SCENE, _test_device_id)
	_write_fixture(newest_path, STUDENT_C, PARENT_C, 200, "Newest Valid Legacy", VALID_SCENE, _test_device_id)
	_write_fixture(invalid_newest_path, STUDENT_C, PARENT_C, 300, "Invalid Newer Legacy", "res://missing_qa_scene.tscn", _test_device_id)
	_write_fixture(ownerless_path, "", PARENT_C, 999, "Ownerless Legacy", VALID_SCENE, "")
	_write_fixture(mismatched_device_path, STUDENT_C, PARENT_C, 1000, "Other Device", VALID_SCENE, "another-qa-device")

	_set_student(STUDENT_C, PARENT_C, "QA Student C")
	var visible_saves: Array[Dictionary] = GameState.list_saves()
	_assert(visible_saves.is_empty(), "Ambiguous legacy timestamp files are hidden rather than misclassified as manual saves")
	var migrated_path := _current_path(STUDENT_C)
	var migrated := GameState.peek_save_data(migrated_path)
	_assert(not migrated.is_empty() and String(migrated.get("player_name", "")) == "Newest Valid Legacy", "Newest valid owned legacy save seeds the hidden checkpoint")
	_assert(String(migrated.get("save_kind", "")) == "checkpoint", "Migrated legacy state is explicitly marked as a hidden checkpoint")
	_assert(GameState.current_task_index == 0, "Listing legacy saves does not unexpectedly mutate live gameplay state")
	_assert(FileAccess.file_exists(old_path) and FileAccess.file_exists(newest_path) and FileAccess.file_exists(invalid_newest_path), "Legacy history is preserved on disk during migration")


func _test_manual_delete_scope() -> void:
	_set_student(STUDENT_C, PARENT_C, "QA Student C")
	var legacy_checkpoint := GameState.peek_save_data(_current_path(STUDENT_C))
	_assert(not legacy_checkpoint.is_empty(), "Legacy checkpoint remains available before visible-save deletion tests")
	_set_student(STUDENT_A, PARENT_A, "QA Student A")
	var checkpoint_path := _current_path(STUDENT_A)
	_assert(FileAccess.file_exists(checkpoint_path), "Student A checkpoint exists before deleting manual saves")
	var selected_path := _manual_paths_a[1]
	_assert(GameState.delete_save(selected_path), "Delete removes the exact selected manual save")
	var remaining := GameState.list_saves()
	_assert(remaining.size() == 2, "Deleting one manual save leaves the other two visible")
	_assert(not FileAccess.file_exists(selected_path) and FileAccess.file_exists(_manual_paths_a[0]) and FileAccess.file_exists(_manual_paths_a[2]), "Selected deletion changes only that manual file")
	_assert(FileAccess.file_exists(checkpoint_path), "Deleting a manual save preserves the hidden autosave checkpoint")
	var deletion_result: Dictionary = GameState.delete_all_saves()
	_assert(int(deletion_result.get("deleted_count", 0)) == 2 and int(deletion_result.get("failed_count", 0)) == 0, "Delete All removes exactly the authenticated Student's remaining manual saves")
	_assert(GameState.list_saves().is_empty(), "Delete All empties this Student's visible manual list")
	_assert(FileAccess.file_exists(checkpoint_path), "Delete All preserves this Student's hidden checkpoint")
	_assert(FileAccess.file_exists(_manual_paths_a[0]) == false and FileAccess.file_exists(_manual_paths_a[2]) == false, "Delete All removes only the selected Student's visible manual files")
	_assert(FileAccess.file_exists(_manual_path_b), "Delete All preserves another Student's manual save")
	_set_student(STUDENT_B, PARENT_B, "QA Student B")
	_assert(GameState.list_saves().size() == 1, "Student B's manual entry remains visible after Student A Delete All")
	_assert(GameState.delete_all_saves().get("deleted_count", 0) == 1, "Student B can independently Delete All their own manual save")
	_assert(FileAccess.file_exists(_current_path(STUDENT_B)), "Student B Delete All preserves the hidden checkpoint")
	_assert(FileAccess.file_exists(ownerless_path_for_test()), "Student deletion leaves unrelated ownerless legacy data untouched")


func _test_load_game_badge() -> void:
	var entry := (load("res://ui/save_entry.tscn") as PackedScene).instantiate() as Control
	get_tree().root.add_child(entry)
	entry.call("set_slot_number", 55)
	await get_tree().process_frame
	var caption := entry.get_node_or_null("MarginContainer/Content/SlotBadge/BadgeContent/SlotCaption") as Label
	var number := entry.get_node_or_null("MarginContainer/Content/SlotBadge/BadgeContent/SlotNumber") as Label
	_assert(caption != null and caption.text == "SAVE", "Load Game card retains the simple SAVE badge")
	_assert(number != null and number.text == "55", "Save slot badge displays the supplied manual-save order number")
	entry.queue_free()
	await get_tree().process_frame


func _set_student(owner_id: String, parent_id: String, student_name: String) -> void:
	GameState.student_id = owner_id
	GameState.parent_id = parent_id
	GameState.player_name = student_name
	GameState.gender = "female"
	GameState.grade_level = "Grade 2"
	GameState.current_quest = "QA current checkpoint"
	GameState.current_scene_path = VALID_SCENE
	GameState.current_map = VALID_SCENE
	GameState.player_position = Vector2(128.0, 96.0)
	GameState.current_task_index = 0
	GameState.current_lives = 3
	GameState.max_lives = 3
	GameState.total_play_time = 30
	GameState.score = 0
	GameState.correct_answers = 0
	GameState.incorrect_answers = 0
	GameState.total_questions = 0
	GameState.oakleaf_defeated_bandits = {}
	GameState.current_quest = GameState.get_current_quest_text()


func _current_path(owner_id: String) -> String:
	return "%s/save_%s_current.json" % [_test_directory, owner_id]


func _call_checkpoint() -> String:
	if not GameState.has_method("save_checkpoint"):
		return ""
	return String(GameState.call("save_checkpoint"))


func _recovery_path(owner_id: String) -> String:
	return "%s/save_%s_recovery.json" % [_test_directory, owner_id]


func _find_current_save(owner_id: String) -> Dictionary:
	for save_data in GameState.list_saves():
		if String(save_data.get("student_id", "")) == owner_id:
			return save_data
	return {}


func _count_json_files() -> int:
	var absolute_directory := ProjectSettings.globalize_path(_test_directory)
	var directory := DirAccess.open(absolute_directory)
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			count += 1
		file_name = directory.get_next()
	directory.list_dir_end()
	return count


func _write_fixture(path: String, owner_id: String, parent_id: String, timestamp: int, player_name: String, scene_path: String, device_id: String) -> void:
	var data := {
		"save_version": GameState.SAVE_VERSION,
		"player_name": player_name,
		"gender": "female",
		"grade_level": "Grade 2",
		"student_id": owner_id,
		"parent_id": parent_id,
		"device_installation_id": device_id,
		"current_quest": "Legacy checkpoint",
		"scene_path": scene_path,
		"current_map": scene_path,
		"player_position": {"x": 203.0, "y": 207.0},
		"current_lives": 2,
		"max_lives": 3,
		"current_task_index": 3,
		"score": 4,
		"correct_answers": 4,
		"incorrect_answers": 1,
		"total_questions": 5,
		"total_play_time": 123,
		"save_date": "2026-01-01",
		"save_time": "10:00:00",
		"save_timestamp": timestamp,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create a disposable legacy QA fixture")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func ownerless_path_for_test() -> String:
	return _test_directory + "/legacy_owner_unknown.json"


func _disable_live_transport() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var transport := get_tree().root.get_node_or_null(autoload_name)
		if transport != null:
			transport.free()


func _cleanup_test_directory() -> void:
	if not _test_directory_created:
		return
	var absolute_directory := ProjectSettings.globalize_path(_test_directory)
	var directory := DirAccess.open(absolute_directory)
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
			file_name = directory.get_next()
		directory.list_dir_end()
	DirAccess.remove_absolute(absolute_directory)
	_test_directory_created = false


func _assert(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	_cleanup_test_directory()
	if not _original_save_directory.is_empty():
		GameState.set("_save_directory", _original_save_directory)
	GameState.set("device_installation_id", _original_device_id)
	var failed := _failures.size()
	print("CURRENT_STUDENT_SAVE_REGRESSION_TEST " + JSON.stringify({
		"passed": _checks - failed,
		"failed": failed,
		"checks": _checks,
		"failures": _failures,
		"qa_local_only": true,
		"production_writes": 0,
		"cleanup": "unique QA-local fixture directory removed",
	}))
	var report_path := "user://qa_local_saves/current_student_save_regression_%s.json" % _run_id
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({
			"passed": _checks - failed,
			"failed": failed,
			"checks": _checks,
			"failures": _failures,
			"qa_local_only": true,
			"production_writes": 0,
			"cleanup": "unique QA-local fixture directory removed",
		}, "\t"))
		report.close()
	else:
		push_error("Unable to write the disposable QA-local test report")
	# Keep the Godot MCP debug stream available long enough to collect the report.
	await get_tree().create_timer(30.0).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failed == 0 else 1)
