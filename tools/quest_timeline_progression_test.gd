extends Node

## Focused source-of-truth fixture for the City/School/Deep Forest/Pinehill
## continuation. It exercises GameState only; battle presentation remains in
## the original VS scenes and is covered by the existing battle fixtures.

const CITY := "res://scenes/city_of_knowledge.tscn"
const SCHOOL := "res://interiors/school.tscn"
const PINEHILL := "res://scenes/pinehill_village.tscn"
const PROFILE := {
	"player_name": "Timeline Fixture",
	"gender": "male",
	"grade_level": "Grade 1",
	"student_id": "98765432",
	"parent_id": "654321",
	"learning_cycle": {"version": 0, "started_at": ""},
}
const DEEP_IDS := [
	"deep_forest_bandits1", "deep_forest_bandits2", "deep_forest_bandits3",
	"deep_forest_bandits4", "deep_forest_bandits5",
]
const PINE_IDS := [
	"pinehill_bandits1", "pinehill_bandits2", "pinehill_bandits3",
	"pinehill_bandits4",
]
const RETURN_IDS := []

var _checks: Array[Dictionary] = []
var _qa_save_directory := ""
var _qa_save_directory_created := false
var _run_id := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_id = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var http := get_node_or_null("/root/HttpApi")
	var loopback_mode_enabled := http != null and bool(http.call("enable_local_qa_mode", "http://127.0.0.1:5000"))
	var local_api_only := loopback_mode_enabled and bool(http.call("is_local_qa_mode")) \
			and String(http.get("base_url")) == "http://127.0.0.1:5000"
	_expect(local_api_only, "timeline fixture forces a verified loopback-only API mode before gameplay state changes")
	if not local_api_only:
		_finish()
		return

	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	var state := get_node("/root/GameState")
	state.enable_local_qa_mode()
	_qa_save_directory = "%s/quest_timeline_%d_%d" % [
		state.LOCAL_QA_SAVE_DIRECTORY,
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	var absolute_qa_save_directory := ProjectSettings.globalize_path(_qa_save_directory)
	if DirAccess.dir_exists_absolute(absolute_qa_save_directory):
		_expect(false, "timeline fixture refuses to reuse an existing QA save directory")
		_finish()
		return
	_qa_save_directory_created = DirAccess.make_dir_recursive_absolute(absolute_qa_save_directory) == OK
	_expect(_qa_save_directory_created, "timeline fixture creates a unique disposable QA save directory")
	if not _qa_save_directory_created:
		_finish()
		return
	state.set("_save_directory", _qa_save_directory)
	var required_methods := [
		"is_progression_encounter_defeated",
		"can_start_progression_encounter",
		"record_progression_encounter_victory",
		"are_all_progression_bandits_defeated",
		"complete_city_school_teacher",
		"complete_pinehill_old_man",
	]
	for method_name in required_methods:
		_expect(state.has_method(method_name), "GameState exposes %s" % method_name)
	_expect(state.get_current_quest_text() == "Tutorial", "Tutorial remains the initial objective")
	if not _has_required_methods(state):
		_finish()
		return

	state.start_new_game(PROFILE, false)
	state.current_task_index = state.CITY_OF_KNOWLEDGE_TASK_INDEX
	state.city_of_knowledge_unlocked = true
	state.current_quest = state.get_current_quest_text()
	_expect(state.current_quest == "Go to the City of Knowledge School.", "Oakleaf completion uses canonical City objective")
	state.handle_scene_entered(CITY)
	_expect(state.current_task_index == state.CITY_SCHOOL_TASK_INDEX and state.city_school_stage == 1, "City entry advances to School")
	state.handle_scene_entered(SCHOOL)
	_expect(state.current_task_index == state.CITY_SCHOOL_TEACHER_TASK_INDEX, "School entry exposes Math Teacher")
	_expect(state.complete_city_school_teacher().get("changed", false), "Math Teacher unlocks Deep Forest")
	_expect(state.current_task_index == state.CITY_NEXT_PATH_TASK_INDEX and state.get_current_quest_text() == "Go to the Deepest Forest Path.", "School completion stages the Deep Forest path")
	state.handle_scene_entered(CITY)
	_expect(state.current_task_index == state.DEEP_FOREST_BANDIT_TASK_INDEX and state.get_current_quest_text() == "Defeat the Bandits in the Deepest Forest.", "City return activates Deep Forest")

	for encounter_id in DEEP_IDS:
		_expect(state.can_start_progression_encounter(encounter_id), "%s is available in Deep Forest" % encounter_id)
		_expect(state.record_progression_encounter_victory(encounter_id).get("changed", false), "%s persists" % encounter_id)
	_expect(state.are_all_progression_bandits_defeated("deep_forest") and state.pinehill_unlocked, "Deep Forest completion unlocks Pinehill")
	state.handle_scene_entered(PINEHILL)
	_expect(state.current_task_index == state.PINEHILL_OLD_MAN_TASK_INDEX, "Pinehill entry exposes Old Man")
	_expect(state.complete_pinehill_old_man().get("changed", false), "Old Man unlocks Pinehill Bandits")

	for encounter_id in PINE_IDS:
		_expect(state.record_progression_encounter_victory(encounter_id).get("changed", false), "%s persists" % encounter_id)
	_expect(state.current_task_index == state.WIZARD_TASK_INDEX, "Pinehill Bandit completion unlocks Wizard")
	_expect(state.record_progression_encounter_victory("pinehill_wizard").get("changed", false), "Wizard victory persists")
	_expect(state.wizard_defeated and state.return_to_city_stage, "Wizard victory opens return path")

	if RETURN_IDS.is_empty():
		_expect(state.current_task_index == state.RETURN_CITY_TASK_INDEX, "Source has no return-path Bandit IDs; City return remains the authoritative next task")
	else:
		for encounter_id in RETURN_IDS:
			_expect(state.record_progression_encounter_victory(encounter_id).get("changed", false), "%s persists" % encounter_id)
		_expect(state.current_task_index == state.RETURN_CITY_TASK_INDEX, "Return-path Bandits unlock City return")
	state.handle_scene_entered(CITY)
	state.handle_scene_entered(SCHOOL)
	_expect(state.current_task_index == state.FINAL_TEACHER_TASK_INDEX, "Return to City and School exposes Master Teacher")
	_expect(state.record_progression_encounter_victory("final_teacher").get("changed", false), "Final Teacher victory persists")
	_expect(state.final_teacher_defeated and state.journey_complete, "Final victory completes the journey")

	var saved: Dictionary = state.build_save_data()
	_expect(saved.has("city_school_stage") and saved.has("deep_forest_defeated_bandits") and saved.has("pinehill_unlocked"), "City/Forest persistence fields are serialized")
	_expect(saved.has("pinehill_old_man_completed") and saved.has("pinehill_defeated_bandits") and saved.has("wizard_defeated"), "Pinehill/Wizard persistence fields are serialized")
	_expect(saved.has("return_to_city_stage") and saved.has("return_path_defeated_bandits") and saved.has("final_teacher_defeated"), "Return/Final persistence fields are serialized")
	var timeline_saves: Array[Dictionary] = state.list_saves()
	_expect(timeline_saves.is_empty(), "Quest/battle progression autosaves do not create visible manual saves")
	var timeline_checkpoint_path := String(state.call("_get_current_student_save_path", String(state.get("student_id"))))
	var persisted_timeline: Dictionary = state.peek_save_data(timeline_checkpoint_path)
	_expect(not persisted_timeline.is_empty(), "Progression autosaves keep a hidden current checkpoint available")
	_expect(bool(persisted_timeline.get("journey_complete", false)) and bool(persisted_timeline.get("wizard_defeated", false)), "The hidden checkpoint retains final quest and battle progression")
	state.start_new_game(PROFILE, false)
	state.apply_save_data(saved, false)
	_expect(state.journey_complete and state.final_teacher_defeated and state.city_school_stage == 4, "Save/Load preserves complete timeline state")
	_expect(state.get_current_quest_text() == "Math Champion", "Completed journey has the Math Champion ending")
	_finish()


func _has_required_methods(state: Node) -> bool:
	for check in _checks:
		if not bool(check.get("passed", false)):
			return false
	return true


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	_cleanup_qa_save_directory()
	var failed := 0
	for check in _checks:
		if not bool(check.get("passed", false)):
			failed += 1
	var report := {
		"passed": _checks.size() - failed,
		"failed": failed,
		"checks": _checks,
		"qa_local_only": true,
		"production_writes": 0,
		"cleanup": "unique QA-local save directory removed",
	}
	var report_file := FileAccess.open("user://qa_local_saves/quest_timeline_progression_%s.json" % _run_id, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("QUEST_TIMELINE_PROGRESSION_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	# Keep the Godot MCP debug stream available long enough to collect the report.
	await get_tree().create_timer(30.0).timeout
	get_tree().quit(0 if failed == 0 else 1)


func _cleanup_qa_save_directory() -> void:
	if not _qa_save_directory_created:
		return
	var absolute_directory := ProjectSettings.globalize_path(_qa_save_directory)
	var directory := DirAccess.open(absolute_directory)
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
			file_name = directory.get_next()
		directory.list_dir_end()
	DirAccess.remove_absolute(absolute_directory)
	_qa_save_directory_created = false
