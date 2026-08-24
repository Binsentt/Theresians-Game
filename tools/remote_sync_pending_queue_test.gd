extends Node

const RemoteSyncScript = preload("res://scripts/remote_sync.gd")
const TEST_PENDING_FILE := "user://remote_sync_pending_queue_test.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var file := FileAccess.open(TEST_PENDING_FILE, FileAccess.WRITE)
	if file == null:
		printerr("[Remote Sync Pending Queue Test] Could not create the isolated pending queue fixture.")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify([{"student_id": "123456", "current_quest": "Teacher House"}]))
	file.close()

	var remote_sync: Node = RemoteSyncScript.new()
	remote_sync.set("_pending_file", TEST_PENDING_FILE)
	var pending: Variant = remote_sync.call("_load_pending")
	failed = not _assert(pending is Array, "A valid pending-sync JSON array must load without a runtime error.") or failed
	if pending is Array:
		failed = not _assert(pending.size() == 1, "The pending queue must retain its saved entry.") or failed
		if pending.size() == 1:
			failed = not _assert(pending[0] is Dictionary and pending[0].get("student_id") == "123456", "The pending queue must preserve saved payload data.") or failed

	remote_sync.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PENDING_FILE))
	print("remote_sync_pending_queue_test: %s" % ("FAIL" if failed else "PASS"))
	get_tree().quit(1 if failed else 0)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[Remote Sync Pending Queue Test] %s" % message)
	return condition
