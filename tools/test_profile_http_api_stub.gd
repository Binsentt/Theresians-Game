extends Node

signal request_recorded(kind: String, path: String, payload: Dictionary)

var requests: Array[Dictionary] = []
var parent_result: Dictionary = {
	"ok": true,
	"status": 200,
	"body": {"ok": true},
}
var profile_result: Dictionary = {
	"ok": true,
	"status": 200,
	"body": {"ok": true, "should_block": false, "error": ""},
}


func request_get(path: String, params: Dictionary = {}, _timeout_ms: int = -1) -> Dictionary:
	var payload := params.duplicate(true)
	requests.append({"kind": "get", "path": path, "payload": payload})
	request_recorded.emit("get", path, payload)
	if path.begins_with("/api/game/profile/check/"):
		return profile_result.duplicate(true)
	return {"ok": true, "status": 200, "body": {"ok": true}}


func request_post(path: String, payload: Dictionary, _timeout_ms: int = -1) -> Dictionary:
	var request_payload := payload.duplicate(true)
	requests.append({"kind": "post", "path": path, "payload": request_payload})
	request_recorded.emit("post", path, request_payload)
	if path == "/api/game/parent/validate":
		return parent_result.duplicate(true)
	return {"ok": true, "status": 200, "body": {"ok": true}}
