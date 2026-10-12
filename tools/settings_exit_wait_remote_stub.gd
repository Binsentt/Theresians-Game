extends Node

var request_count := 0

func request_end_playtime_session() -> Dictionary:
	request_count += 1
	# Model the real HTTPRequest's pause-sensitive wait without making a network call.
	await get_tree().create_timer(0.08, false).timeout
	return {"ok": true, "status": 200}
