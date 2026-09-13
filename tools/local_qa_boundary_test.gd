extends Node

const LOCAL_BACKEND_URL := "http://127.0.0.1:5001"

func _ready() -> void:
	var http := get_node_or_null("/root/HttpApi")
	var sync := get_node_or_null("/root/RemoteSync")
	if http == null or sync == null:
		push_error("LOCAL QA boundary requires HttpApi and RemoteSync autoloads.")
		get_tree().quit(1)
		return
	var local_enabled := bool(http.call("enable_local_qa_mode", LOCAL_BACKEND_URL))
	if not local_enabled or not bool(http.get("local_qa_only")):
		push_error("LOCAL QA boundary did not enable loopback-only HttpApi mode.")
		get_tree().quit(1)
		return
	sync.call("enable_local_qa_mode")
	if not bool(sync.get("local_qa_only")) or String(http.get("base_url")).contains("theresiansquest.com"):
		push_error("LOCAL QA boundary did not disable production sync/write paths.")
		get_tree().quit(1)
		return
	print("PASS: Godot LOCAL QA boundary enforced; API=" + String(http.get("base_url")) + "; RemoteSync writes disabled")
	await get_tree().create_timer(5.0).timeout
	get_tree().quit(0)
