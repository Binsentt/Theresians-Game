extends Node


func request_post(path: String, _payload: Dictionary, _timeout_ms: int = -1) -> Dictionary:
	if path == "/api/game/parent/validate":
		return {"ok": true, "status": 200, "body": {"ok": true, "success": true}}
	return {"ok": false, "status": 404, "body": {"error": "Unexpected test request."}}


func request_get(path: String, _params: Dictionary = {}, _timeout_ms: int = -1) -> Dictionary:
	if path.begins_with("/api/game/profile/check/"):
		return {"ok": true, "status": 200, "body": {"ok": true, "can_play": true, "should_block": false}}
	return {"ok": false, "status": 404, "body": {"error": "Unexpected test request."}}
