extends Node

var request_count := 0

func request_end_playtime_session() -> Dictionary:
	request_count += 1
	await get_tree().process_frame
	return {"ok": true, "status": 200}
