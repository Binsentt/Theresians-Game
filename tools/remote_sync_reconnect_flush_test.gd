extends Node

const RemoteSyncScript := preload("res://scripts/remote_sync.gd")


class FakeHttpApi extends Node:
	var heartbeat_attempts := 0
	var result_attempts := 0
	var result_event_ids: Array[String] = []

	func request_post(path: String, payload: Dictionary) -> Dictionary:
		if path == "/api/playtime/heartbeat":
			heartbeat_attempts += 1
			await get_tree().create_timer(0.02).timeout
			if heartbeat_attempts == 1:
				return {"ok": false, "status": 0, "body": {}, "error": "synthetic offline"}
			return {"ok": true, "status": 200, "body": {"can_play": true, "daily_limit_minutes": 60, "remaining_minutes": 60, "remaining_seconds": 3600}}
		if path == "/api/game/result":
			result_attempts += 1
			result_event_ids.append(String(payload.get("result_event_id", "")))
			await get_tree().create_timer(0.02).timeout
			if result_attempts == 1:
				return {"ok": true, "status": 0, "body": {}}
			return {"ok": true, "status": 201, "body": {}}
		return {"ok": true, "status": 204, "body": {}}


var _checks: Array[Dictionary] = []
var _pending_file := ""
var _transport: FakeHttpApi
var _remote: Node
var _run_id := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_id = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var http := get_node_or_null("/root/HttpApi")
	var remote_autoload := get_node_or_null("/root/RemoteSync")
	var state := get_node_or_null("/root/GameState")
	var loopback_mode_enabled := http != null and bool(http.call("enable_local_qa_mode", "http://127.0.0.1:5000"))
	var local_only := loopback_mode_enabled and bool(http.call("is_local_qa_mode")) \
			and String(http.get("base_url")) == "http://127.0.0.1:5000"
	_expect(local_only, "reconnect fixture forces a verified loopback-only API mode")
	if remote_autoload != null and remote_autoload.has_method("enable_local_qa_mode"):
		remote_autoload.call("enable_local_qa_mode")
	_expect(remote_autoload != null and bool(remote_autoload.get("local_qa_only")), "real RemoteSync autoload suppresses writes in this fixture")
	if not local_only or state == null:
		_finish()
		return

	state.call("enable_local_qa_mode")
	if http != null:
		http.free()
	_transport = FakeHttpApi.new()
	_transport.name = "HttpApi"
	get_tree().root.add_child(_transport)

	_pending_file = "user://qa_local_saves/remote_sync_reconnect_%s.json" % str(Time.get_ticks_usec())
	_remote = RemoteSyncScript.new()
	_remote.set("_pending_file", _pending_file)
	_remote.set("_current_playtime_session_id", 42)
	_remote.set("_current_playtime_session_credential", "synthetic-lease")
	_remote.set("_current_playtime_student_id", "98765432")
	_remote.set("_current_playtime_parent_id", "654321")
	_remote.set("_current_playtime_learning_cycle_version", 0)
	get_tree().root.add_child(_remote)

	state.set("student_id", "98765432")
	state.set("parent_id", "654321")
	state.set("learning_cycle_version", 0)
	state.set("playtime_authorized", true)
	var result_payload := {
		"student_id": "98765432",
		"parent_id": "654321",
		"learning_cycle_version": 0,
		"result_event_id": "qa-reconnect-result-001",
		"question_id": "synthetic-question-1",
		"score": 1,
		"total_items": 1,
	}
	_remote.call("_enqueue_pending_result", result_payload)
	_remote.call("_enqueue_pending_result", result_payload)
	var initial_queue: Array = _remote.call("_load_pending")
	_expect(initial_queue.size() == 1, "re-enqueueing the same result ID does not duplicate the local outbox item")

	await _remote.call("_refresh_playtime_lease")
	_expect(_transport.heartbeat_attempts == 1 and _transport.result_attempts == 0, "an offline heartbeat leaves results queued without sending them")
	_expect((_remote.call("_load_pending") as Array).size() == 1, "an offline heartbeat preserves the pending result")
	_expect(bool(_remote.call("_has_active_playtime_lease")) and bool(state.get("playtime_authorized")), "a temporary transport failure preserves the existing lease for reconnect")

	await _remote.call("_refresh_playtime_lease")
	await get_tree().create_timer(0.1).timeout
	_expect(_transport.heartbeat_attempts == 2 and _transport.result_attempts == 1, "a restored heartbeat resumes the pending result drain")
	_expect((_remote.call("_load_pending") as Array).size() == 1, "a failed replay remains queued for the next reconnect check")

	await _remote.call("_refresh_playtime_lease")
	await get_tree().create_timer(0.1).timeout
	_expect(_transport.result_attempts == 2 and _transport.result_event_ids == ["qa-reconnect-result-001", "qa-reconnect-result-001"], "retry reuses the same idempotent result identity")
	_expect((_remote.call("_load_pending") as Array).is_empty(), "a successful replay removes the acknowledged result from the outbox")
	_finish()


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	var report := {
		"passed": _checks.size() - failed,
		"failed": failed,
		"checks": _checks,
		"qa_local_only": true,
		"production_writes": 0,
	}
	var report_file := FileAccess.open("user://qa_local_saves/remote_sync_reconnect_%s.json" % _run_id, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("REMOTE_SYNC_RECONNECT_FLUSH_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	if not _pending_file.is_empty():
		var path := ProjectSettings.globalize_path(_pending_file)
		if FileAccess.file_exists(_pending_file):
			DirAccess.remove_absolute(path)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
