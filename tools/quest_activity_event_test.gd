extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	_expect(source.contains("task_state_changed"), "RemoteSync must subscribe to the canonical GameState task transition signal.")
	_expect(source.contains("func _on_task_state_changed"), "RemoteSync must own one canonical task-transition handler.")
	_expect(source.contains("/api/game/activity"), "Canonical quest activity must use the lease-authenticated game endpoint.")
	_expect(source.contains("cycle:%d:task:%d:%d:%s:%s"), "Quest activity event keys must be deterministic per learning-cycle transition.")
	_expect(source.contains("\"task_trigger\": \"task_triggered\""), "Existing task triggers must map to the approved canonical activity type.")
	_expect(source.contains("_enqueue_pending_activity"), "Transient canonical activity failures must reuse the existing RemoteSync pending queue.")
	_expect(source.contains("session_credential") and source.contains("learning_cycle_version"), "Canonical activity requests must be authenticated by lease and cycle.")
	_expect(not _function_block(source, "func _submit_canonical_task_activity").contains("student_id"), "Canonical activity payloads must not include caller-supplied Student identity.")
	_expect(not _function_block(source, "func _submit_canonical_task_activity").contains("parent_id"), "Canonical activity payloads must not include caller-supplied Parent identity.")
	_finish()


func _function_block(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + signature.length())
	return source.substr(start) if next < 0 else source.substr(start, next - start)


func _finish() -> void:
	if _failures.is_empty():
		print("quest_activity_event_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
