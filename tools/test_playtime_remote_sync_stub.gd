extends Node

signal request_recorded(payload: Dictionary)

var requests: Array[Dictionary] = []
var response: Dictionary = {
	"ok": true,
	"status": 200,
	"body": {
		"ok": true,
		"can_play": true,
		"should_block": false,
		"session_id": 42,
		"remaining_minutes": 60,
		"daily_limit_minutes": 60,
	},
	"can_play": true,
	"should_block": false,
	"error": "",
	"session_id": 42,
}


func request_playtime_session(override_payload: Dictionary = {}) -> Dictionary:
	var payload := override_payload.duplicate(true)
	requests.append(payload)
	request_recorded.emit(payload)
	return response.duplicate(true)
