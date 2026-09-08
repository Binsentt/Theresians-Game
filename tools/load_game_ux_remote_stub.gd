extends Node

func request_learning_cycle(_student_id: String, _parent_id: String) -> Dictionary:
	return {"ok": true, "learning_cycle": {"version": 0, "started_at": ""}}

func request_playtime_session(_payload: Dictionary) -> Dictionary:
	return {"ok": true, "can_play": true, "should_block": false}
