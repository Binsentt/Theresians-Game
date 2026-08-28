extends Node

const RemoteSyncScript = preload("res://scripts/remote_sync.gd")
const TEST_PENDING_FILE := "user://canonical_activity_payload_test.json"


class HttpApiStub extends Node:
	var responses: Array[Dictionary] = []
	var requests: Array[Dictionary] = []

	func request_post(path: String, payload: Dictionary) -> Dictionary:
		requests.append({"path": path, "payload": payload.duplicate(true)})
		return responses.pop_front() if not responses.is_empty() else {"ok": true, "status": 201, "body": {}}


var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := get_tree().root
	var game_state := root.get_node_or_null("GameState")
	var original_http := root.get_node_or_null("HttpApi")
	if game_state == null:
		_failures.append("The test runner must provide the GameState autoload.")
		_finish()
		return
	var original_http_name := ""
	if original_http != null:
		original_http_name = original_http.name
		original_http.name = "_canonical_activity_original_http"

	var http_stub := HttpApiStub.new()
	http_stub.name = "HttpApi"
	http_stub.responses = [
		{"ok": false, "status": 503, "body": {}},
		{"ok": true, "status": 201, "body": {}},
		{"ok": true, "status": 200, "body": {"duplicate": true}},
		{"ok": true, "status": 201, "body": {}},
	]
	root.add_child(http_stub)

	var remote_sync := RemoteSyncScript.new()
	remote_sync.set("_pending_file", TEST_PENDING_FILE)
	root.add_child(remote_sync)
	game_state.set("learning_cycle_version", 4)
	game_state.set("playtime_authorized", true)
	remote_sync.set("_current_playtime_session_id", 321)
	remote_sync.set("_current_playtime_session_credential", "test-lease")

	var tutorial_event := {
		"type": "task_trigger",
		"key": "tutorial:start",
		"previous_index": -1,
		"current_index": 0,
		"activity": {"activity_id": "tutorial", "activity_label": "Tutorial"},
	}
	await remote_sync._on_canonical_activity_boundary(tutorial_event)
	_expect(http_stub.requests.size() == 1, "A valid leased Tutorial start sends one canonical request.")
	if http_stub.requests.size() == 1:
		var first_payload: Dictionary = http_stub.requests[0].get("payload", {})
		_expect(String(http_stub.requests[0].get("path", "")) == "/api/game/activity", "Canonical activity uses only the approved activity endpoint.")
		_expect(String(first_payload.get("event_key", "")) == "cycle:4:task:-1:0:task_triggered:tutorial:start", "Tutorial retries must begin with the deterministic event key.")
		_expect(not first_payload.has("student_id") and not first_payload.has("parent_id") and not first_payload.has("student_name"), "Canonical activity payload does not trust caller identity metadata.")

	await remote_sync._on_canonical_activity_boundary(tutorial_event)
	_expect(http_stub.requests.size() == 3, "A transient failure retries with the same key and flushes one queued duplicate safely.")
	if http_stub.requests.size() >= 2:
		_expect(String((http_stub.requests[1].get("payload", {}) as Dictionary).get("event_key", "")) == "cycle:4:task:-1:0:task_triggered:tutorial:start", "Network retry preserves the Tutorial event key.")
	var pending: Array = remote_sync._load_pending()
	_expect(pending.is_empty(), "Acknowledge/duplicate responses remove the pending Tutorial event.")

	var teacher_house_completion := {
		"type": "task_trigger",
		"activity_type": "task_completed",
		"key": "quest:main:task:0:arrival",
	}
	await remote_sync._on_task_state_changed(0, 1, teacher_house_completion)
	_expect(http_stub.requests.size() == 4, "Teacher House completion produces one canonical request.")
	if http_stub.requests.size() == 4:
		var completion_payload: Dictionary = http_stub.requests[3].get("payload", {})
		_expect(String(completion_payload.get("event_type", "")) == "task_completed", "Teacher House completion uses canonical task_completed semantics.")
		_expect(String(completion_payload.get("task_id", "")) == "Go to Teacher House", "Teacher House completion derives metadata from the existing first task.")
	await remote_sync._on_task_state_changed(0, 1, teacher_house_completion)
	_expect(http_stub.requests.size() == 4, "An acknowledged collision retry cannot create a second Teacher House completion request.")

	remote_sync.set("_current_playtime_session_id", 0)
	await remote_sync._on_canonical_activity_boundary({
		"type": "task_completed",
		"key": "tutorial:complete",
		"previous_index": 0,
		"current_index": 0,
		"activity": {"activity_id": "tutorial", "activity_label": "Tutorial"},
	})
	_expect(http_stub.requests.size() == 4, "No activity is emitted without an active lease.")

	remote_sync.queue_free()
	http_stub.queue_free()
	if original_http != null:
		original_http.name = original_http_name
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PENDING_FILE))
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("canonical_activity_payload_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
