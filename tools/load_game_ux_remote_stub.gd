extends Node

var learning_cycle_request_count := 0
var playtime_request_count := 0

func request_learning_cycle(_student_id: String, _parent_id: String) -> Dictionary:
	learning_cycle_request_count += 1
	return {"ok": true, "learning_cycle": {"version": 0, "started_at": ""}}

func request_playtime_session(_payload: Dictionary) -> Dictionary:
	playtime_request_count += 1
	return {"ok": true, "can_play": true, "should_block": false}
