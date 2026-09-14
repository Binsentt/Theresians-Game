extends Node

var start_request_count := 0
var last_start_payload: Dictionary = {}
var respond_with_lease := true
var profile_request_count := 0
var last_profile_request_path := ""


func request_post(path: String, payload: Dictionary, _timeout_ms: int = -1) -> Dictionary:
	if path == "/api/game/parent/validate":
		return {"ok": true, "status": 200, "body": {"ok": true, "success": true}}
	if path == "/api/playtime/start":
		start_request_count += 1
		last_start_payload = payload.duplicate(true)
		await get_tree().create_timer(0.12).timeout
		if not respond_with_lease:
			return {
				"ok": false,
				"status": 503,
				"body": {"error": "Playtime service is temporarily unavailable."},
				"error": "Playtime service is temporarily unavailable.",
			}
		return {
			"ok": true,
			"status": 201,
			"body": {
				"success": true,
				"can_play": true,
				"session_id": 9001,
				"session_credential": "test-issued-lease-credential",
				"remaining_seconds": 3599,
				"remaining_minutes": 60,
				"daily_limit_minutes": 60,
				"expires_at": "2030-01-01T01:00:00.000Z",
				"learning_cycle": {
					"version": 2.0,
					"started_at": "2030-01-01T00:00:00.000Z",
				},
			},
		}
	if path == "/api/activity-logs":
		return {"ok": true, "status": 201, "body": {"success": true}}
	if path == "/api/playtime/end":
		return {"ok": true, "status": 200, "body": {"success": true}}
	return {"ok": true, "status": 200, "body": {"success": true}}


func request_get(path: String, _params: Dictionary = {}, _timeout_ms: int = -1) -> Dictionary:
	if path.begins_with("/api/game/profile/check/"):
		profile_request_count += 1
		last_profile_request_path = path
		await get_tree().create_timer(0.05).timeout
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
				"learning_cycle": {"version": 1.0, "started_at": "2029-01-01T00:00:00.000Z"},
			},
		}
	return {"ok": false, "status": 404, "body": {"error": "Unexpected test request."}}
