extends Node

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	var game_state := get_node_or_null("/root/GameState")
	if http == null or remote == null or game_state == null:
		_failures.append("Canonical autoloads are required.")
		_finish()
		return
	http.enable_local_qa_mode("http://127.0.0.1:5000")
	remote.enable_local_qa_mode()
	game_state.enable_local_qa_mode()

	var cases := [
		{"label": "integer", "value": 15, "expected": 15},
		{"label": "zero", "value": 0, "expected": 0},
		{"label": "float", "value": 15.8, "expected": 15},
		{"label": "numeric string", "value": "15", "expected": 15},
		{"label": "empty string", "value": "", "expected": null},
		{"label": "null", "value": null, "expected": null},
		{"label": "missing", "missing": true, "expected": null},
		{"label": "dictionary", "value": {}, "expected": null},
		{"label": "array", "value": [], "expected": null},
		{"label": "object", "value": Node.new(), "expected": null},
	]
	for case in cases:
		var event := {
			"type": "task_completed",
			"key": "duration:%s" % case.label,
			"activity": {"activity_id": "tutorial", "activity_label": "Tutorial"},
		}
		if not bool(case.get("missing", false)):
			event["duration_seconds"] = case.get("value")
		var result: Dictionary = game_state.build_canonical_activity_event(event, 0, "task_completed")
		var actual: Variant = result.get("duration_seconds", null)
		_expect(actual == case.expected, "%s duration normalizes to %s, got %s" % [case.label, str(case.expected), str(actual)])

	var profile := {
		"student_id": "17000087",
		"parent_id": "170001",
		"player_name": "QA Duration",
		"grade_level": "Grade 1",
		"gender": "male",
	}
	game_state.start_new_game(profile, false)
	var completed: bool = bool(game_state.complete_tutorial_activity())
	_expect(completed, "Tutorial completion remains valid with local telemetry boundary enabled")
	_expect(game_state._tutorial_activity_completed, "Tutorial completion flag is committed before telemetry handling")
	_expect(game_state.current_quest == String(game_state.tasks[0].get("quest_text", "")), "Tutorial completion preserves the next playable quest state")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("ACTIVITY_DURATION_NORMALIZATION_TEST {\"failed\":0,\"passed\":13}")
		await get_tree().create_timer(3.0).timeout
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ACTIVITY_DURATION_NORMALIZATION_TEST {\"failed\":%d,\"passed\":%d}" % [_failures.size(), 13 - _failures.size()])
	await get_tree().create_timer(3.0).timeout
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
