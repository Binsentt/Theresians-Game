extends Node

func request_playtime_session(override_payload: Dictionary = {}) -> Dictionary:
	return {
		"ok": true,
		"status": 200,
		"body": {"ok": true, "can_play": true, "should_block": false, "session_id": 42},
		"can_play": true,
		"should_block": false,
		"error": "",
		"session_id": 42
	}
