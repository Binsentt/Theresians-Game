extends Node

const ROUTER := preload("res://scripts/progression_battle_encounter.gd")
const OLD_LADY := preload("res://scripts/progression_old_man_interaction.gd")
const RESULT_PATH := "res://tools/story_continuation_dialogue_test_result.json"
const PROFILE := {
	"player_name": "Story Continuation Fixture",
	"gender": "male",
	"grade_level": "Grade 1",
	"student_id": "87654321",
	"parent_id": "123456",
}

var _checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, label: String) -> void:
	_checks.append({"label": label, "passed": condition})
	if not condition:
		push_error(label)


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()

	var state: Node = load("res://tools/preservation_regression_state.gd").new()
	state.fixture_path = "user://saves/story_continuation_%d.json" % Time.get_ticks_usec()
	add_child(state)
	state.start_new_game(PROFILE, false)
	_expect(String(state.tasks[state.CITY_NEXT_PATH_TASK_INDEX].quest_text) == "Go to the Deepest Forest Path.", "City School points to Deepest Forest Path")
	_expect(String(state.tasks[state.DEEP_FOREST_BANDIT_TASK_INDEX].quest_text) == "Defeat the Bandits in the Deepest Forest.", "Deep Forest objective is explicit")
	_expect(String(state.tasks[state.PINEHILL_ARRIVAL_TASK_INDEX].quest_text) == "Continue to Pinehill Village.", "Deep Forest completion points to Pinehill")
	_expect(String(state.tasks[state.PINEHILL_OLD_MAN_TASK_INDEX].quest_text) == "Find someone who knows about the Wizard.", "Pinehill arrival points to the Old Lady")
	_expect(String(state.tasks[state.PINEHILL_BANDIT_TASK_INDEX].quest_text) == "Defeat the Wizard's 4 Guards.", "Old Lady completion points to four guards")
	_expect(String(state.tasks[state.WIZARD_TASK_INDEX].quest_text) == "Enter the Wizard Tower.", "Four guards completion points to Wizard Tower")
	_expect(String(state.tasks[state.RETURN_CITY_TASK_INDEX].quest_text) == "Return to the City of Knowledge.", "Wizard completion points back to City")
	_expect(String(state.tasks[state.FINAL_SCHOOL_TASK_INDEX].quest_text) == "Return to the School.", "City return points to School")
	_expect(String(state.tasks[state.FINAL_TEACHER_TASK_INDEX].quest_text) == "Face the Teacher's Final Challenge.", "School return points to final Teacher")

	_expect(OLD_LADY.DIALOGUE_LINES.size() == 4, "Old Lady uses the four-line conversation")
	_expect(ROUTER.WIZARD_INTRO_DIALOGUE.size() == 3, "Wizard intro uses the short three-line conversation")
	_expect(ROUTER.WIZARD_REVELATION_DIALOGUE.size() == 4, "Wizard revelation uses the four-line conversation")
	_expect(ROUTER.DEEP_FOREST_COMPLETE_DIALOGUE.size() == 1, "Deep Forest completion has a short notification")
	_expect(ROUTER.PINEHILL_GUARDS_COMPLETE_DIALOGUE.size() == 1, "Pinehill guard completion has a short notification")
	_expect(String(state.tasks[state.CITY_SCHOOL_TASK_INDEX].dialogue[0]) == "Teacher: You made it to the City of Knowledge.", "City Teacher opening line is canonical")
	_expect(String(state.tasks[state.FINAL_TEACHER_TASK_INDEX].dialogue[0]) == "Teacher: You finally discovered the truth.", "Final Teacher opening line is canonical")

	state.city_of_knowledge_unlocked = true
	state.city_school_stage_complete = true
	state.city_next_path_unlocked = true
	state.current_task_index = state.CITY_NEXT_PATH_TASK_INDEX
	state.handle_scene_entered("res://scenes/deepest_forest_path.tscn")
	_expect(state.current_task_index == state.DEEP_FOREST_BANDIT_TASK_INDEX, "Deep Forest stage remains gated by School completion")
	for encounter_id in state.DEEP_FOREST_BANDIT_IDS:
		state.record_progression_encounter_victory(encounter_id, false)
	_expect(state.pinehill_unlocked and state.current_task_index == state.PINEHILL_ARRIVAL_TASK_INDEX, "Five Deep Forest encounters unlock Pinehill")
	state.handle_scene_entered("res://scenes/pinehill_village.tscn")
	_expect(state.current_task_index == state.PINEHILL_OLD_MAN_TASK_INDEX, "Pinehill arrival opens the Old Lady stage")
	state.complete_pinehill_old_lady()
	_expect(state.current_task_index == state.PINEHILL_BANDIT_TASK_INDEX, "Old Lady gates the four guards")
	for encounter_id in state.PINEHILL_BANDIT_IDS:
		state.record_progression_encounter_victory(encounter_id, false)
	_expect(state.current_task_index == state.WIZARD_TASK_INDEX, "Four guards unlock the Wizard Tower")
	state.record_progression_encounter_victory("pinehill_wizard", false)
	_expect(state.current_task_index == state.RETURN_CITY_TASK_INDEX, "Wizard victory unlocks the City return")
	state.handle_scene_entered("res://scenes/city_of_knowledge.tscn")
	_expect(state.current_task_index == state.FINAL_SCHOOL_TASK_INDEX, "City return opens the School stage")
	state.handle_scene_entered("res://interiors/school.tscn")
	_expect(state.current_task_index == state.FINAL_TEACHER_TASK_INDEX, "School opens the final Teacher stage")
	state.record_progression_encounter_victory("final_teacher", false)
	_expect(state.journey_complete and state.get_current_quest_text() == "Math Champion", "Final victory is monotonic and ends at Math Champion")

	var failed := _checks.filter(func(row: Dictionary) -> bool: return not bool(row.get("passed", false))).size()
	var evidence := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks, "live_network_calls": 0}
	var result_file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(evidence, "\t"))
		result_file.close()
	print("STORY_CONTINUATION_DIALOGUE_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "live_network_calls": 0}))
	if FileAccess.file_exists(state.fixture_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	state.queue_free()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(1 if failed else 0)
