extends Node

func request_get(path: String, params: Dictionary = {}, timeout_ms: int = -1) -> Dictionary:
	return {
		"ok": true,
		"status": 200,
		"body": {"ok": true, "should_block": false, "error": ""}
	}

func request_post(path: String, payload: Dictionary, timeout_ms: int = -1) -> Dictionary:
	var normalized_parent := String(payload.get("parent_id", ""))
	var normalized_student := String(payload.get("student_id", ""))
	if path == "/api/game/parent/validate":
		return {"ok": true, "status": 200, "body": {"ok": true, "parent_id": normalized_parent}}
	if path == "/api/game/profile/check/" + normalized_student:
		return {"ok": true, "status": 200, "body": {"ok": true, "should_block": false, "error": ""}}
	if path == "/api/playtime/start":
		return {"ok": true, "status": 200, "body": {"ok": true, "can_play": true, "should_block": false, "session_id": 42, "remaining_minutes": 60, "daily_limit_minutes": 60}}
	return {"ok": true, "status": 200, "body": {"ok": true}}
