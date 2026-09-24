extends Node

const PROFILE := {"player_name": "Final Flow", "gender": "male", "grade_level": "Grade 1", "student_id": "98765432", "parent_id": "654321"}
const REQUIRED_ORIGINAL_VS_SCENES := [
	"res://Battle/Battle-Enemy/male_vs_bandit.tscn",
	"res://Battle/Battle-Enemy/female_vs_bandit.tscn",
	"res://Battle/Battle-Enemy/male_vs_wizard.tscn",
	"res://Battle/Battle-Enemy/female_vs_wizard1.tscn",
	"res://Battle/Battle-Enemy/male_vs_teacher.tscn",
	"res://Battle/Battle-Enemy/female_vs_teacher.tscn",
]
const RESULT_PATH := "res://tools/final_game_flow_state_test_result.json"
var checks: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _expect(value: bool, label: String) -> void:
	checks.append({"label": label, "passed": value})
	if not value:
		push_error(label)

func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	var state: Node = load("res://tools/preservation_regression_state.gd").new()
	state.fixture_path = "user://saves/final_game_flow_%d.json" % Time.get_ticks_usec()
	add_child(state)
	for scene_path in REQUIRED_ORIGINAL_VS_SCENES:
		_expect(ResourceLoader.exists(scene_path), "original VS exists: " + scene_path)
	state.start_new_game(PROFILE, false)
	_expect(state.get_current_quest_text() == "Tutorial", "initial Tutorial")
	state.current_task_index = state.CITY_OF_KNOWLEDGE_TASK_INDEX
	state.city_of_knowledge_unlocked = true
	state.handle_scene_entered("res://scenes/city_of_knowledge.tscn")
	_expect(state.current_task_index == state.CITY_SCHOOL_TASK_INDEX, "City arrival")
	state.handle_scene_entered("res://interiors/school.tscn")
	_expect(state.current_task_index == state.CITY_SCHOOL_TEACHER_TASK_INDEX, "School teacher stage")
	state.complete_city_school_teacher()
	_expect(state.current_task_index == state.CITY_NEXT_PATH_TASK_INDEX and state.get_current_quest_text() == "Go to Pinehill Village", "City School path checkpoint")
	state.handle_scene_entered("res://scenes/deepest_forest_path.tscn")
	_expect(state.current_task_index == state.DEEP_FOREST_BANDIT_TASK_INDEX and state.get_current_quest_text() == "Defeat All Bandits", "Deep Forest stage")
	_roundtrip(state, "Deep Forest Save/Load", state.DEEP_FOREST_BANDIT_TASK_INDEX)
	for encounter_id in state.DEEP_FOREST_BANDIT_IDS:
		_expect(state.can_start_progression_encounter(encounter_id), encounter_id + " available")
		_expect(bool(state.record_progression_encounter_victory(encounter_id, false).get("changed", false)), encounter_id + " records")
		_expect(state.is_progression_encounter_defeated(encounter_id), encounter_id + " independent defeated state")
	_expect(state.pinehill_unlocked, "Pinehill unlock")
	_expect(not bool(state.record_progression_encounter_victory(state.DEEP_FOREST_BANDIT_IDS[0], false).get("changed", false)), "Deep Forest duplicate blocked")
	_roundtrip(state, "Pinehill-unlocked Save/Load", state.PINEHILL_ARRIVAL_TASK_INDEX)
	state.handle_scene_entered("res://scenes/pinehill_village.tscn")
	_expect(state.current_task_index == state.PINEHILL_OLD_MAN_TASK_INDEX, "Pinehill arrival")
	_expect(bool(state.complete_pinehill_old_lady().get("changed", false)), "Old Lady advances exactly once")
	_expect(not bool(state.complete_pinehill_old_lady().get("changed", false)), "Old Lady duplicate blocked")
	for encounter_id in state.PINEHILL_BANDIT_IDS:
		_expect(state.can_start_progression_encounter(encounter_id), encounter_id + " available")
		_expect(bool(state.record_progression_encounter_victory(encounter_id, false).get("changed", false)), encounter_id + " records")
		_expect(state.is_progression_encounter_defeated(encounter_id), encounter_id + " independent defeated state")
	_expect(state.current_task_index == state.WIZARD_TASK_INDEX, "Wizard unlock")
	_expect(state.can_start_progression_encounter("pinehill_wizard"), "Wizard prerequisite satisfied")
	_expect(bool(state.record_progression_encounter_victory("pinehill_wizard", false).get("changed", false)), "Wizard victory records")
	_expect(not bool(state.record_progression_encounter_victory("pinehill_wizard", false).get("changed", false)), "Wizard duplicate blocked")
	_roundtrip(state, "post-Wizard Save/Load", state.RETURN_CITY_TASK_INDEX)
	for encounter_id in state.RETURN_PATH_BANDIT_IDS:
		state.record_progression_encounter_victory(encounter_id, false)
	_expect(state.current_task_index == state.RETURN_CITY_TASK_INDEX, "Return City")
	state.handle_scene_entered("res://scenes/city_of_knowledge.tscn")
	_expect(state.current_task_index == state.FINAL_SCHOOL_TASK_INDEX, "City return opens School objective")
	_roundtrip(state, "return-City Save/Load", state.FINAL_SCHOOL_TASK_INDEX)
	state.handle_scene_entered("res://interiors/school.tscn")
	_expect(state.current_task_index == state.FINAL_TEACHER_TASK_INDEX, "Final Teacher")
	_roundtrip(state, "pre-Final-Teacher Save/Load", state.FINAL_TEACHER_TASK_INDEX)
	_expect(state.can_start_progression_encounter("final_teacher"), "Final Teacher gate active")
	_expect(bool(state.record_progression_encounter_victory("final_teacher", false).get("changed", false)), "Final Teacher victory records")
	_expect(not bool(state.record_progression_encounter_victory("final_teacher", false).get("changed", false)), "Final Teacher duplicate blocked")
	_expect(state.journey_complete and state.get_current_quest_text() == "Math Champion", "Completion")
	var saved: Dictionary = state.build_save_data()
	state.start_new_game(PROFILE, false)
	state.apply_save_data(saved, false)
	_expect(state.journey_complete and state.city_school_stage == 4, "Save/load completion")
	var failed := 0
	for check in checks:
		if not check.passed:
			failed += 1
	var evidence := {"passed": checks.size() - failed, "failed": failed, "checks": checks, "live_network_calls": 0}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	print("FINAL_GAME_FLOW_STATE_TEST " + JSON.stringify(evidence))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	state.queue_free()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)


func _roundtrip(state: Node, label: String, expected_task_index: int) -> void:
	var saved: Dictionary = state.build_save_data()
	state.start_new_game(PROFILE, false)
	state.apply_save_data(saved, false)
	_expect(state.current_task_index == expected_task_index, label)
