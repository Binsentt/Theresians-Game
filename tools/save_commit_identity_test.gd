extends Node

const RemoteSyncScript := preload("res://scripts/remote_sync.gd")

var _checks: Array[Dictionary] = []
var _run_id := ""
var _qa_directory := ""
var _pending_file := ""
var _owns_qa_directory := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_run_id = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_qa_directory = "%s/save_commit_identity_%s" % [GameState.LOCAL_QA_SAVE_DIRECTORY, _run_id]
	_pending_file = "%s/queued.json" % _qa_directory
	var conflict_file := "%s/conflicts.json" % _qa_directory
	_expect(HttpApi.is_local_qa_profile_active(), "test starts with the runtime suite's local-only API profile")
	if not HttpApi.is_local_qa_profile_active():
		await _finish(conflict_file)
		return
	HttpApi.enable_local_qa_mode("http://127.0.0.1:5000")
	RemoteSync.enable_local_qa_mode()
	GameState.enable_local_qa_mode()
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_qa_directory)), "test uses a new isolated save directory")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_qa_directory)):
		await _finish(conflict_file)
		return
	var create_directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_qa_directory))
	_expect(create_directory_error == OK, "creates its isolated save directory")
	if create_directory_error != OK:
		await _finish(conflict_file)
		return
	_owns_qa_directory = true
	GameState.set("_save_directory", _qa_directory)
	GameState.start_new_game({
		"player_name": "Synthetic Save Commit Student",
		"gender": "female",
		"grade_level": "Grade 4",
		"student_id": "88003001",
		"parent_id": "880301",
		"learning_cycle": {"version": 0, "started_at": "2026-10-01T00:00:00Z"},
	}, false)
	GameState.device_installation_id = "save-commit-identity-test-device"
	GameState.score = 12
	GameState.correct_answers = 4
	GameState.total_questions = 5

	var id_pattern := RegEx.new()
	_expect(id_pattern.compile("^save:[0-9a-f]{32}$") == OK, "compiles the backend-compatible commit ID pattern")
	var generated_ids: Dictionary = {}
	for index in range(64):
		var generated_id := String(GameState.call("_generate_save_commit_id"))
		_expect(generated_id.length() <= 128 and id_pattern.search(generated_id) != null, "generated ID %d uses only allowed characters and length" % index)
		_expect(not generated_ids.has(generated_id), "generated ID %d is distinct within this installation" % index)
		generated_ids[generated_id] = true

	var manual_path := GameState.save_manual_game()
	var manual_snapshot: Dictionary = GameState.peek_save_data(manual_path)
	var manual_id := String(manual_snapshot.get("save_commit_id", ""))
	_expect(not manual_path.is_empty() and not manual_snapshot.is_empty(), "manual save still creates a readable save file")
	_expect(id_pattern.search(manual_id) != null, "manual save stores a collision-resistant commit ID")
	var manual_bytes := _read_text(manual_path)
	var second_manual_path := GameState.save_manual_game()
	var second_manual_snapshot: Dictionary = GameState.peek_save_data(second_manual_path)
	var second_manual_id := String(second_manual_snapshot.get("save_commit_id", ""))
	_expect(id_pattern.search(second_manual_id) != null and second_manual_id != manual_id, "each separate manual save receives a unique ID")
	var daily_path := GameState.save_daily_time_limit_game()
	var daily_snapshot: Dictionary = GameState.peek_save_data(daily_path)
	var daily_id := String(daily_snapshot.get("save_commit_id", ""))
	_expect(not daily_path.is_empty() and not daily_snapshot.is_empty(), "daily time-limit save still creates a readable recovery save")
	_expect(id_pattern.search(daily_id) != null and daily_id != manual_id and daily_id != second_manual_id, "daily save receives its own independent commit ID")
	_expect(String(GameState.peek_save_data(manual_path).get("save_commit_id", "")) == manual_id, "creating a later save does not rewrite the earlier save ID")
	_expect(String(GameState.load_save(manual_path, false).get("save_commit_id", "")) == manual_id, "loading an existing save retains its original commit ID")
	_expect(_read_text(manual_path) == manual_bytes, "loading the save does not rewrite its persisted identity")

	var legacy_queue_item := {
		"kind": "progress_commit",
		"path": "/api/game/progress",
		"environment_scope": "production",
		"student_id": "88003001",
		"parent_id": "880301",
		"learning_cycle_version": 0,
		"save_commit_id": "manual:88003001:0:5",
		"payload": {"student_id": "88003001", "parent_id": "880301", "learning_cycle_version": 0, "save_commit_id": "manual:88003001:0:5", "score": 5},
	}
	var remote_sync: Node = RemoteSyncScript.new()
	remote_sync.set("_pending_file", _pending_file)
	remote_sync.set("_conflict_file", conflict_file)
	_expect(bool(remote_sync.call("_persist_pending_queue", [legacy_queue_item])), "writes the pre-existing queue fixture through the durable queue writer")
	_expect(bool(remote_sync.call("_commit_academic_save_data", manual_snapshot)), "queues the newly created save without contacting an API")
	_expect(bool(remote_sync.call("_commit_academic_save_data", manual_snapshot)), "re-enqueueing one save remains idempotent")
	var queued: Array = remote_sync.call("_load_pending")
	var matching_progress := queued.filter(func(item: Variant) -> bool:
		return item is Dictionary and String(item.get("kind", "")) == "progress_commit"
	)
	_expect(matching_progress.size() == 2, "queue contains the original event plus exactly one new committed save")
	var legacy_preserved := false
	var generated_preserved := false
	for item: Variant in matching_progress:
		if not (item is Dictionary):
			continue
		legacy_preserved = legacy_preserved or JSON.stringify(item) == JSON.stringify(legacy_queue_item)
		generated_preserved = generated_preserved or String(item.get("save_commit_id", "")) == manual_id
	_expect(legacy_preserved, "existing queued IDs remain byte-for-byte equivalent at the event level")
	_expect(generated_preserved, "queued save uses the exact ID persisted in its save file")
	remote_sync.free()

	var restarted_sync: Node = RemoteSyncScript.new()
	restarted_sync.set("_pending_file", _pending_file)
	restarted_sync.set("_conflict_file", conflict_file)
	var after_restart: Array = restarted_sync.call("_load_pending")
	_expect(after_restart == queued, "queue restart preserves old and new IDs without regeneration")
	restarted_sync.free()
	await _finish(conflict_file)


func _read_text(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish(conflict_file: String) -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	print("SAVE_COMMIT_IDENTITY_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	if _owns_qa_directory:
		for file_path in [_pending_file, conflict_file]:
			if not String(file_path).is_empty() and FileAccess.file_exists(file_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	var absolute_directory := ProjectSettings.globalize_path(_qa_directory)
	if _owns_qa_directory and DirAccess.dir_exists_absolute(absolute_directory):
		var directory := DirAccess.open(absolute_directory)
		if directory != null:
			directory.list_dir_begin()
			var file_name := directory.get_next()
			while not file_name.is_empty():
				if not directory.current_is_dir():
					DirAccess.remove_absolute(ProjectSettings.globalize_path(_qa_directory + "/" + file_name))
				file_name = directory.get_next()
			directory.list_dir_end()
		DirAccess.remove_absolute(absolute_directory)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
