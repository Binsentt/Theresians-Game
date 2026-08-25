extends Node


func request_post(path: String, _payload: Dictionary, _timeout_ms: int = -1) -> Dictionary:
	if path == "/api/game/parent/validate":
		return {
			"ok": false,
			"status": 0,
			"body": {"error": "Registration service is unavailable."},
			"error": "Registration service is unavailable.",
		}
	return {"ok": false, "status": 0, "body": {}, "error": "Unexpected request."}


func request_get(_path: String, _params: Dictionary = {}, _timeout_ms: int = -1) -> Dictionary:
	return {
		"ok": false,
		"status": 0,
		"body": {"error": "Registration service is unavailable."},
		"error": "Registration service is unavailable.",
	}
