extends Node

const RemoteSyncScript = preload("res://scripts/remote_sync.gd")
const TEST_QUEUE_DIRECTORY := "res://.godot/remote_sync_response_type_test"
const TEST_QUEUE_PATH := TEST_QUEUE_DIRECTORY + "/queue.json"
const TEST_RECORD := {"save_slot": "remote-sync-test"}


class HttpApiStub extends Node:
	var response: Dictionary = {"ok": false, "status": 0}
	var request_count := 0

	func request_post(_path: String, _payload: Dictionary) -> Dictionary:
		request_count += 1
		return response.duplicate(true)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_test_queue()
	if not _prepare_test_queue_directory():
		get_tree().quit(1)
		return
	var remote_sync: Node = RemoteSyncScript.new()
	remote_sync.set("_pending_file", TEST_QUEUE_PATH)
	remote_sync.name = "RemoteSyncResponseTypeTest"
	get_tree().root.add_child(remote_sync)

	var failed := false
	failed = not _assert_loaded(remote_sync, JSON.stringify([TEST_RECORD]), [TEST_RECORD], "valid Array payload loads queued records") or failed
	failed = not _assert_loaded(remote_sync, JSON.stringify({"error": OK, "result": [TEST_RECORD]}), [TEST_RECORD], "valid Dictionary success wrapper loads queued records") or failed
	failed = not _assert_loaded(remote_sync, JSON.stringify({"error": ERR_CANT_CONNECT, "result": [TEST_RECORD]}), [], "valid Dictionary error wrapper fails closed") or failed
	failed = not _assert_loaded(remote_sync, JSON.stringify(["not-a-queued-record"]), [], "malformed Array fails closed without property access") or failed
	failed = not _assert_loaded(remote_sync, "null", [], "null payload fails closed") or failed
	_remove_test_queue()
	failed = not _assert_equal(_load_pending(remote_sync), [], "missing payload fails closed") or failed
	failed = not _assert_retry_preserves_queue(remote_sync) or failed

	_remove_test_queue()
	_remove_test_queue_directory()
	remote_sync.free()
	if not failed:
		print("[RemoteSync Response Type Test] PASS")
	get_tree().quit(1 if failed else 0)


func _assert_loaded(remote_sync: Node, serialized_payload: String, expected: Array, message: String) -> bool:
	if not _write_test_payload(serialized_payload):
		return _assert(false, "%s: test queue could not be written" % message)
	return _assert_equal(_load_pending(remote_sync), expected, message)


func _assert_retry_preserves_queue(remote_sync: Node) -> bool:
	if not _write_test_payload(JSON.stringify([TEST_RECORD])):
		return _assert(false, "retry path: test queue could not be written")
	var root := get_tree().root
	var active_http: Node = root.get_node_or_null("HttpApi")
	var original_http_name := ""
	if active_http != null:
		original_http_name = active_http.name
		active_http.name = "_remote_sync_response_type_original_http"
	var http_stub := HttpApiStub.new()
	http_stub.name = "HttpApi"
	root.add_child(http_stub)
	remote_sync.call("_flush_pending")
	var result := _assert_equal(http_stub.request_count, 1, "retry path posts the queued record once") \
		and _assert_equal(_load_pending(remote_sync), [TEST_RECORD], "retry path preserves the queued record after a failed response")
	http_stub.free()
	if active_http != null:
		active_http.name = original_http_name
	return result


func _load_pending(remote_sync: Node) -> Array:
	var loaded: Variant = remote_sync.call("_load_pending")
	return loaded if loaded is Array else []


func _write_test_payload(serialized_payload: String) -> bool:
	var file := FileAccess.open(TEST_QUEUE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("[RemoteSync Response Type Test] test queue open error code %s" % FileAccess.get_open_error())
		return false
	file.store_string(serialized_payload)
	file.close()
	return true


func _prepare_test_queue_directory() -> bool:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_QUEUE_DIRECTORY))
	return _assert_equal(error, OK, "test queue directory is available")


func _remove_test_queue() -> void:
	if FileAccess.file_exists(TEST_QUEUE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_QUEUE_PATH))


func _remove_test_queue_directory() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_QUEUE_DIRECTORY))


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[RemoteSync Response Type Test] %s" % message)
		return false
	return true


func _assert_equal(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		printerr("[RemoteSync Response Type Test] %s" % message)
		return false
	return true
