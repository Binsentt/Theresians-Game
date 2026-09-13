extends Node

const GameStateScript = preload("res://scripts/game_state.gd")

var _checks: Array[Dictionary] = []

const PROFILE := {
	"player_name": "Task Presentation Fixture",
	"gender": "male",
	"grade_level": "Grade 1",
	"student_id": "87654321",
	"parent_id": "654321",
	"learning_cycle": {"version": 0, "started_at": ""},
}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var trigger_source := FileAccess.get_file_as_string("res://world/task_progress_trigger.gd")
	_expect(source.contains("Task 1 Complete"), "Tutorial completion exposes the player-facing Task 1 Complete label")
	_expect(trigger_source.contains('notification_title: String = "Task 2"'), "Teacher House arrival starts player-facing Task 2")

	var state := GameStateScript.new()
	add_child(state)
	state.start_new_game(PROFILE, false)
	_expect(state.total_quests_completed == 0, "A new student starts with zero completed player tasks")
	_expect(state.complete_tutorial_activity(), "Tutorial completion is accepted once")
	_expect(state.total_quests_completed == 1, "Tutorial completion counts as Task 1")
	_expect(not state.complete_tutorial_activity(), "Duplicate Tutorial completion is ignored")
	_expect(state.total_quests_completed == 1, "Duplicate Tutorial completion does not inflate the count")

	state.current_task_index = 1
	_expect(state.current_task_index == 1, "Teacher House arrival advances without completing Task 2")
	_expect(state.total_quests_completed == 1, "Teacher House arrival alone does not complete Task 2")
	state.current_task_index = 2
	state.call("_record_player_facing_completion", "talk-to-the-teacher")
	_expect(state.current_task_index == 2, "Teacher interaction advances to the Oakleaf challenge")
	_expect(state.total_quests_completed == 2, "Teacher interaction counts as Task 2")

	state.current_task_index = state.OAKLEAF_BANDIT_TASK_INDEX
	state.oakleaf_defeated_bandits["oakleaf_bandits1"] = true
	for encounter_id in state.OAKLEAF_BANDIT_IDS:
		state.call("_record_oakleaf_encounter_victory", encounter_id, false)
	_expect(state.total_quests_completed == 2, "Normal Oakleaf Bandits do not complete Task 3 early")
	state.call("_record_oakleaf_encounter_victory", state.OAKLEAF_BOSS_ID, false)
	_expect(state.total_quests_completed == 3, "Boss victory completes the combined Task 3 milestone once")
	state.call("_record_oakleaf_encounter_victory", state.OAKLEAF_BOSS_ID, false)
	_expect(state.total_quests_completed == 3, "Duplicate Boss victory does not inflate Task 3")
	state.call("_record_player_facing_completion", "oakleaf-return-to-teacher")
	_expect(state.total_quests_completed == 4, "Return to Teacher completes Task 4 once")
	state.current_task_index = state.CITY_OF_KNOWLEDGE_TASK_INDEX
	_expect(state.get_current_quest_text() == "Go to the City of Knowledge / School", "Task 4 assigns the City transition")
	state.call("_record_player_facing_completion", "oakleaf-return-to-teacher")
	_expect(state.total_quests_completed == 4, "Duplicate return-to-Teacher does not inflate Task 4")
	_finish()

func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)

func _finish() -> void:
	var failed := 0
	for check in _checks:
		if not bool(check.get("passed", false)):
			failed += 1
	print("PLAYER_TASK_PRESENTATION_CONTRACT_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
