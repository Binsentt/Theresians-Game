extends Node

const RemoteSyncScript := preload("res://scripts/remote_sync.gd")


class FakeHttpApi extends Node:
	var responses: Array[Dictionary] = []
	var requests: Array[Dictionary] = []
	var progress_commit_ids: Array[String] = []

	func request_post(path: String, payload: Dictionary) -> Dictionary:
		requests.append({"path": path, "payload": payload.duplicate(true)})
		if path == "/api/game/progress":
			progress_commit_ids.append(String(payload.get("save_commit_id", "")))
		if responses.is_empty():
			return {"ok": true, "status": 201, "body": {}}
		return responses.pop_front()


var _checks: Array[Dictionary] = []
var _run_id := ""
var _created_files: Array[String] = []
var _fake_http: FakeHttpApi


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_run_id = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var root := get_tree().root
	var real_http := root.get_node_or_null("HttpApi")
	if real_http != null:
		real_http.free()
	var existing_remote := root.get_node_or_null("RemoteSync")
	if existing_remote != null and existing_remote.has_method("enable_local_qa_mode"):
		existing_remote.call("enable_local_qa_mode")
	GameState.enable_local_qa_mode()
	GameState.historical_replay_mode = false
	GameState.student_id = "88003001"
	GameState.parent_id = "880301"
	GameState.learning_cycle_version = 0
	GameState.playtime_authorized = true

	_fake_http = FakeHttpApi.new()
	_fake_http.name = "HttpApi"
	root.add_child(_fake_http)

	var offline_queue_path := "user://local_qa_saves/commit_conflict_offline_%s.json" % _run_id
	var offline_conflict_path := "user://local_qa_saves/commit_conflict_offline_journal_%s.json" % _run_id
	if not _reserve_new_files([offline_queue_path, offline_conflict_path]):
		_expect(false, "offline fixture paths are new and not reused")
		await _finish()
		return
	var offline_id := "save:0123456789abcdef0123456789abcdef"
	var offline_item := _progress_item(offline_id, 8)
	var offline_remote := _new_remote(offline_queue_path, offline_conflict_path)
	_expect(bool(offline_remote.call("_persist_pending_queue", [offline_item])), "offline fixture is saved before the first request")
	_fake_http.responses = [
		{"ok": false, "status": 0, "body": {}, "error": "synthetic offline"},
		{"ok": true, "status": 201, "body": {"success": true}},
	]
	await offline_remote.call("_flush_pending")
	var after_offline: Array = offline_remote.call("_load_pending")
	_expect(_same_content(after_offline, [offline_item]), "temporary offline failure leaves the original committed event queued")
	_expect(_fake_http.progress_commit_ids == [offline_id], "first attempt sends the persisted ID unchanged")
	offline_remote.free()

	var restarted_offline_remote := _new_remote(offline_queue_path, offline_conflict_path)
	await restarted_offline_remote.call("_flush_pending")
	_expect(_fake_http.progress_commit_ids == [offline_id, offline_id], "retry after queue restart reuses the same save ID")
	_expect((restarted_offline_remote.call("_load_pending") as Array).is_empty(), "successful retry removes only the acknowledged event")
	restarted_offline_remote.free()

	var conflict_queue_path := "user://local_qa_saves/commit_conflict_queue_%s.json" % _run_id
	var conflict_journal_path := "user://local_qa_saves/commit_conflict_journal_%s.json" % _run_id
	if not _reserve_new_files([conflict_queue_path, conflict_journal_path]):
		_expect(false, "conflict fixture paths are new and not reused")
		await _finish()
		return
	var conflicting_id := "save:abcdef0123456789abcdef0123456789"
	var independent_id := "save:fedcba9876543210fedcba9876543210"
	var conflicting_item := _progress_item(conflicting_id, 12)
	var independent_item := _progress_item(independent_id, 13)
	var conflict_remote := _new_remote(conflict_queue_path, conflict_journal_path)
	_expect(bool(conflict_remote.call("_persist_pending_queue", [conflicting_item, independent_item])), "conflict fixture and later independent event are queued together")
	_fake_http.progress_commit_ids.clear()
	_fake_http.responses = [
		{"ok": true, "status": 409, "body": {"code": "SAVE_COMMIT_ID_REUSED", "error": "save_commit_id was already used with different progress data."}},
		{"ok": true, "status": 201, "body": {"success": true}},
	]
	await conflict_remote.call("_flush_pending")
	_expect(_fake_http.progress_commit_ids == [conflicting_id, independent_id], "a permanent save-ID conflict does not block a later independent progress commit")
	_expect((conflict_remote.call("_load_pending") as Array).is_empty(), "both the preserved conflict and successful independent event leave the active queue")
	var journal: Dictionary = conflict_remote.call("_load_conflict_journal")
	var journal_items: Array = journal.get("items", [])
	_expect(journal.get("schema_version", 0) == 1 and journal_items.size() == 1, "one conflict is durably stored in the versioned journal")
	if journal_items.size() == 1 and journal_items[0] is Dictionary:
		var saved_entry: Dictionary = journal_items[0]
		_expect(_same_content(saved_entry.get("original_event", {}), conflicting_item), "journal preserves the exact original queued event")
		var diagnostic: Variant = saved_entry.get("diagnostic", {})
		_expect(diagnostic is Dictionary and diagnostic.get("code", "") == "SAVE_COMMIT_ID_REUSED" and diagnostic.get("status", 0) == 409, "journal preserves the server conflict diagnostic")
		_expect(String(saved_entry.get("original_event", {}).get("save_commit_id", "")) == conflicting_id, "conflict recovery never invents a replacement commit ID")
	conflict_remote.free()

	var restarted_conflict_remote := _new_remote(conflict_queue_path, conflict_journal_path)
	var restarted_journal: Dictionary = restarted_conflict_remote.call("_load_conflict_journal")
	_expect(restarted_journal == journal, "conflict evidence remains readable after constructing a new queue instance")
	_expect(not bool(restarted_conflict_remote.call("_is_save_commit_id_reused", {"status": 409, "body": {"code": "LEARNING_CYCLE_CHANGED"}})), "cycle changes are not misclassified as save-ID reuse")
	_expect(bool(restarted_conflict_remote.call("_is_save_commit_id_reused", {"status": 409, "body": {"code": "SAVE_COMMIT_ID_REUSED"}})), "save-ID reuse has an exact independent classifier")
	restarted_conflict_remote.free()

	await _test_journal_failure_preserves_pending_item()
	await _finish()


func _progress_item(commit_id: String, score: int) -> Dictionary:
	return {
		"kind": "progress_commit",
		"path": "/api/game/progress",
		"environment_scope": "production",
		"student_id": "88003001",
		"parent_id": "880301",
		"learning_cycle_version": 0,
		"save_commit_id": commit_id,
		"payload": {
			"student_id": "88003001",
			"parent_id": "880301",
			"learning_cycle_version": 0,
			"save_commit_id": commit_id,
			"score": score,
			"save_status": "saved",
		},
	}


func _new_remote(queue_path: String, journal_path: String) -> Node:
	var remote: Node = RemoteSyncScript.new()
	remote.set("_pending_file", queue_path)
	remote.set("_conflict_file", journal_path)
	remote.set("_current_playtime_session_id", 78)
	remote.set("_current_playtime_session_credential", "synthetic-test-lease")
	remote.set("_current_playtime_student_id", "88003001")
	remote.set("_current_playtime_parent_id", "880301")
	remote.set("_current_playtime_learning_cycle_version", 0)
	get_tree().root.add_child(remote)
	return remote


func _test_journal_failure_preserves_pending_item() -> void:
	var queue_path := "user://local_qa_saves/commit_conflict_corrupt_queue_%s.json" % _run_id
	var journal_path := "user://local_qa_saves/commit_conflict_corrupt_journal_%s.json" % _run_id
	if not _reserve_new_files([queue_path, journal_path]):
		_expect(false, "corrupt-journal fixture paths are new and not reused")
		return
	var item := _progress_item("save:00112233445566778899aabbccddeeff", 15)
	var remote := _new_remote(queue_path, journal_path)
	_expect(bool(remote.call("_persist_pending_queue", [item])), "corrupt-journal fixture begins with a durable pending event")
	var corrupt_file := FileAccess.open(journal_path, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("not-json")
		corrupt_file.close()
	_fake_http.responses = [
		{"ok": true, "status": 409, "body": {"code": "SAVE_COMMIT_ID_REUSED", "error": "synthetic conflict"}},
	]
	await remote.call("_flush_pending")
	_expect(_same_content(remote.call("_load_pending"), [item]), "journal persistence failure leaves the original event queued")
	_expect(_read_text(journal_path) == "not-json", "malformed journal is not overwritten while preserving the event")
	remote.free()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _reserve_new_files(paths: Array[String]) -> bool:
	for path in paths:
		if FileAccess.file_exists(path):
			return false
	_created_files.append_array(paths)
	return true


func _same_content(left: Variant, right: Variant) -> bool:
	return JSON.stringify(_canonicalize(left)) == JSON.stringify(_canonicalize(right))


func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var normalized := {}
		for key: Variant in keys:
			normalized[String(key)] = _canonicalize(value[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for item: Variant in value:
			normalized_array.append(_canonicalize(item))
		return normalized_array
	return value


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	print("REMOTE_SYNC_SAVE_COMMIT_CONFLICT_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	for path in _created_files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _fake_http != null and is_instance_valid(_fake_http):
		_fake_http.free()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
