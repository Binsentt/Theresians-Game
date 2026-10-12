extends Node

var parent_response: Dictionary = {"ok": true, "status": 200, "body": {"ok": true, "success": true, "message": "Parent ID is valid."}}
var profile_response: Dictionary = {"ok": true, "status": 200, "body": {"ok": true, "exists": false, "should_block": false, "can_play": true, "message": "Student ID is available for a new game."}}

func request_get(path: String, params: Dictionary = {}, timeout_ms: int = -1) -> Dictionary:
	if path.begins_with("/api/game/profile/check/"):
		return profile_response.duplicate(true)
	return {
		"ok": true,
		"status": 200,
		"body": {"ok": true, "should_block": false, "error": ""}
	}

func request_post(path: String, payload: Dictionary, timeout_ms: int = -1) -> Dictionary:
	if path == "/api/game/parent/validate":
		return parent_response.duplicate(true)
	if path == "/api/playtime/start":
		return {"ok": true, "status": 200, "body": {"ok": true, "can_play": true, "should_block": false, "session_id": 42, "remaining_minutes": 60, "daily_limit_minutes": 60}}
	return {"ok": true, "status": 200, "body": {"ok": true}}
