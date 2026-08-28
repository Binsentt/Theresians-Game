extends SceneTree

const GameStateScript = preload("res://scripts/game_state.gd")

var _activity_events: Array[Dictionary] = []
var _task_transitions: Array[Dictionary] = []
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := GameStateScript.new()
	get_root().add_child(state)
	state.canonical_activity_boundary.connect(_on_activity_boundary)
	state.task_state_changed.connect(_on_task_transition)
	state.start_new_game({
		"player_name": "Test Student",
		"grade_level": "Grade 1",
		"learning_cycle": {"version": 3, "started_at": ""},
	}, false)

	_expect(state.emit_tutorial_activity_started(), "Tutorial start must emit after the caller has established a valid lease.")
	_expect(not state.emit_tutorial_activity_started(), "A retry must not emit Tutorial start twice.")
	_expect(_activity_events.size() == 1, "Tutorial start must produce one canonical event.")
	_expect(String(_activity_events[0].get("type", "")) == "task_trigger", "Tutorial start must use the normal task-trigger event family.")
	_expect(String((_activity_events[0].get("activity", {}) as Dictionary).get("activity_id", "")) == "tutorial", "Tutorial start must use the canonical Tutorial metadata.")

	_expect(state.complete_tutorial_activity(), "The real Tutorial completion boundary must emit once.")
	_expect(not state.complete_tutorial_activity(), "Repeated Tutorial completion input must be ignored.")
	_expect(_activity_events.size() == 3, "Tutorial completion and the first existing task start must each be distinct canonical boundaries.")
	_expect(String(_activity_events[1].get("type", "")) == "task_completed", "Tutorial completion must use the normal task-completed event family.")
	_expect(String((_activity_events[1].get("activity", {}) as Dictionary).get("activity_id", "")) == "tutorial", "Tutorial completion must retain the Tutorial identity.")
	_expect(String(_activity_events[2].get("type", "")) == "task_trigger", "The existing Teacher House task must start using the normal task-trigger event family.")
	_expect(String((_activity_events[2].get("activity", {}) as Dictionary).get("activity_id", "")) == "go-to-teachers-house", "The existing Teacher House task must remain first in canonical task order.")
	_expect(state.current_task_index == 0, "Activity observability must not advance the existing task state.")

	var teacher_house_completion := state.advance_task_and_save({
		"type": "task_trigger",
		"activity_type": "task_completed",
		"key": "quest:main:task:0:arrival",
	})
	_expect(bool(teacher_house_completion.get("advanced", false)), "The real Teacher House trigger must still advance through GameState.")
	_expect(_task_transitions.size() == 1, "Teacher House completion must emit one canonical task transition.")
	_expect(int(_task_transitions[0].get("previous_index", -1)) == 0 and int(_task_transitions[0].get("current_index", -1)) == 1, "Teacher House completion must preserve task ordering.")
	state.queue_free()
	_finish()


func _on_activity_boundary(event: Dictionary) -> void:
	_activity_events.append(event.duplicate(true))


func _on_task_transition(previous_index: int, current_index: int, event: Dictionary) -> void:
	_task_transitions.append({
		"previous_index": previous_index,
		"current_index": current_index,
		"event": event.duplicate(true),
	})


func _finish() -> void:
	if _failures.is_empty():
		print("tutorial_activity_flow_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
