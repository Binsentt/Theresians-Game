extends Node

var _pending_file := "user://pending_syncs.json"

func _ready() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state:
		game_state.connect("save_created", Callable(self, "_on_save_created"))
	_load_pending()

func _on_save_created(save_data: Dictionary) -> void:
	# Always allow local save to complete; attempt remote sync but do not block
	_async_send_progress(save_data)

func _async_send_progress(save_data: Dictionary) -> void:
	# perform non-blocking via thread? We'll do simple call and rely on HttpApi's await behavior
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		print("RemoteSync: HttpApi unavailable; queueing sync")
		_enqueue_pending(save_data)
		return
	# build payload mapping to backend expectations
	var payload := {
		"parent_id": String(save_data.get("parent_id", "")),
		"student_name": String(save_data.get("player_name", "")),
		"grade_level": String(save_data.get("grade_level", "")),
		"current_quest": String(save_data.get("current_quest", "")),
		"current_scene": String(save_data.get("scene_path", "")),
		"current_map": String(save_data.get("scene_path", "")),
		"save_timestamp": int(save_data.get("save_timestamp", 0)),
		"save_time": String(save_data.get("save_time", "")),
		"score": int(save_data.get("score", 0)),
		"total_play_time": int(save_data.get("total_play_time", 0)),
		"save_status": "saved"
	}
	var result = http.post("/api/game/progress", payload)
	if not result.ok:
		print("RemoteSync: progress sync failed, queuing: %s" % str(result))
		_enqueue_pending(save_data)
		return
	if result.status >= 200 and result.status < 300:
		print("RemoteSync: progress synced")
		# try flushing pending
		_flush_pending()
	else:
		print("RemoteSync: unexpected status %s" % str(result))
		_enqueue_pending(save_data)

func _enqueue_pending(save_data: Dictionary) -> void:
	var pending := _load_pending()
	pending.append(save_data)
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pending))
		file.close()

func _load_pending() -> Array:
	var pending := []
	var file := FileAccess.open(_pending_file, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var j = JSON.parse_string(text)
		if j.error == OK and typeof(j.result) == TYPE_ARRAY:
			pending = j.result
	return pending

func _flush_pending() -> void:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return
	var pending := _load_pending()
	if pending.size() == 0:
		return
	var remaining := []
	for item in pending:
		var result = http.post("/api/game/progress", item)
		if not result.ok or result.status < 200 or result.status >= 300:
			remaining.append(item)
	# overwrite pending file
	var file := FileAccess.open(_pending_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(remaining))
		file.close()
