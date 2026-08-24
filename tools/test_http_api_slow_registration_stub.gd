extends Node


func request_post(path: String, _payload: Dictionary, _timeout_ms: int = -1) -> Dictionary:
	if path == "/api/game/parent/validate":
		await get_tree().create_timer(0.12).timeout
		return {"ok": true, "status": 200, "body": {"ok": true, "success": true}}
	return {"ok": false, "status": 0, "body": {}, "error": "Unexpected request."}


func request_get(path: String, _params: Dictionary = {}, _timeout_ms: int = -1) -> Dictionary:
	if path.begins_with("/api/game/profile/check/"):
		await get_tree().create_timer(0.12).timeout
		return {
			"ok": true,
			"status": 200,
			"body": {
				"ok": true,
				"can_play": true,
				"should_block": false,
				"canonical_profile": {
					"name": "Ava Santos",
					"grade_level": "Grade 3",
					"section": null,
				},
			},
		}
	return {"ok": false, "status": 0, "body": {}, "error": "Unexpected request."}
