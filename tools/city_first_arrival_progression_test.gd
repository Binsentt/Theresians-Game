extends Node

## Focused City first-arrival -> School Teacher -> next-path fixture.
## This intentionally exercises only the authoritative GameState handoff and
## existing scenes; it does not create or replace any battle presentation.

const CITY := "res://scenes/city_of_knowledge.tscn"
const SCHOOL := "res://interiors/school.tscn"
const SAVE_DIRECTORY := "user://saves"
const PROFILE := {
	"player_name": "City Fixture",
	"gender": "female",
	"grade_level": "Grade 1",
	"student_id": "98765432",
	"parent_id": "654321",
	"learning_cycle": {"version": 0, "started_at": ""},
}

var _checks: Array[Dictionary] = []
var _initial_save_paths: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	var state := get_node("/root/GameState")
	for save_entry in state.list_saves():
		_initial_save_paths[String(save_entry.get("save_path", ""))] = true

	_expect(state.has_method("mark_city_first_arrival"), "GameState exposes City first-arrival transition")
	_expect(state.has_method("complete_city_school_teacher"), "GameState exposes School Teacher completion")
	_expect(state.has_method("is_city_school_active"), "GameState exposes School objective gate")
	_expect(state.has_method("is_city_next_path_unlocked"), "GameState exposes next-path gate")
	_expect(ResourceLoader.exists(CITY), "canonical City scene exists")
	_expect(ResourceLoader.exists(SCHOOL), "canonical School scene exists")
	_expect(_city_entry_is_gated(), "existing Oakleaf-to-City door remains gated by Oakleaf unlock")
	_expect(_pinehill_return_is_gated(), "existing Pinehill-to-City door remains gated by Oakleaf unlock")
	_expect(_scene_contains_school_teacher(), "existing School scene provides one Teacher and QuestUI host")
	_expect(_city_path_is_gated(), "existing City-to-Pinehill door is gated until School completion")

	if not _has_required_api(state):
		_cleanup_fixture(state)
		_finish()
		return

	state.start_new_game(PROFILE, false)
	state.current_task_index = int(state.get("CITY_OF_KNOWLEDGE_TASK_INDEX"))
	state.city_of_knowledge_unlocked = false
	state.handle_scene_entered(CITY)
	_expect(state.current_task_index == int(state.get("CITY_OF_KNOWLEDGE_TASK_INDEX")), "City remains unavailable before Oakleaf unlock")
	_expect(state.get("city_first_arrival_seen") != true, "locked City does not mark first arrival")

	state.city_of_knowledge_unlocked = true
	state.current_task_index = int(state.get("CITY_OF_KNOWLEDGE_TASK_INDEX"))
	state.current_quest = state.get_current_quest_text()
	state.handle_scene_entered(CITY)
	_expect(state.get("city_first_arrival_seen") == true, "first legitimate City arrival is persisted in state")
	_expect(state.current_task_index == int(state.get("CITY_SCHOOL_TASK_INDEX")), "first City arrival advances to School objective")
	_expect(state.get_current_quest_text() == "Go to the School", "Current Quest becomes Go to the School")

	var repeated_arrival: Dictionary = state.mark_city_first_arrival()
	_expect(repeated_arrival.get("changed", false) != true, "repeated City arrival emits no duplicate transition")
	var city_stage_save: Dictionary = state.build_save_data()
	state.start_new_game(PROFILE, false)
	state.apply_save_data(city_stage_save, false)
	_expect(state.get("city_first_arrival_seen") == true and state.current_task_index == int(state.get("CITY_SCHOOL_TASK_INDEX")), "Save/Load preserves the first-arrival School objective")
	_expect(state.get_current_quest_text() == "Go to the School", "Save/Load preserves the City School quest text")
	state.handle_scene_entered(SCHOOL)
	_expect(state.is_city_school_active(), "School Teacher gate remains active inside School")
	var teacher_result: Dictionary = state.complete_city_school_teacher()
	_expect(teacher_result.get("changed", false) == true, "School Teacher completion advances the City quest")
	_expect(state.get("city_school_stage_complete") == true, "School stage completes exactly once")
	_expect(state.is_city_next_path_unlocked(), "City next path unlocks after School Teacher")
	_expect(state.get_current_quest_text() == "Go to Pinehill Village", "Current Quest becomes the next travel objective")
	var duplicate_teacher: Dictionary = state.complete_city_school_teacher()
	_expect(duplicate_teacher.get("changed", false) != true, "repeated School Teacher interaction does not duplicate completion")
	state.current_task_index = int(state.get("CITY_OF_KNOWLEDGE_TASK_INDEX"))
	_expect(state.get_current_quest_text() == "Go to Pinehill Village", "completed City School state cannot regress its authoritative quest")
	_expect(state.mark_city_first_arrival().get("changed", false) != true, "completed City School state cannot replay first arrival")

	var saved: Dictionary = state.build_save_data()
	_expect(saved.has("city_first_arrival_seen") and saved.has("city_school_stage_complete") and saved.has("city_next_path_unlocked"), "City progression fields are serialized")
	state.start_new_game(PROFILE, false)
	state.apply_save_data(saved, false)
	_expect(state.get("city_first_arrival_seen") == true and state.get("city_school_stage_complete") == true, "Save/Load preserves City School completion")
	_expect(state.get("city_next_path_unlocked") == true and state.get_current_quest_text() == "Go to Pinehill Village", "Save/Load preserves the next-path objective")

	var legacy := {
		"save_version": 9,
		"player_name": "Legacy City",
		"gender": "male",
		"grade_level": "Grade 1",
		"student_id": "12345678",
		"parent_id": "123456",
		"scene_path": CITY,
		"current_task_index": int(state.get("CITY_OF_KNOWLEDGE_TASK_INDEX")),
		"city_of_knowledge_unlocked": true,
	}
	state.apply_save_data(legacy, false)
	_expect(state.get("city_first_arrival_seen") != true and state.get("city_school_stage_complete") != true, "legacy saves load with optional City fields defaulted")

	_cleanup_fixture(state)
	_finish()


func _has_required_api(_state: Node) -> bool:
	for check in _checks:
		if check.get("passed", false) != true:
			return false
	return true


func _scene_contains_school_teacher() -> bool:
	var packed := load(SCHOOL) as PackedScene
	if packed == null:
		return false
	var scene := packed.instantiate()
	var teacher := scene.get_node_or_null("Teacher")
	var quest_ui := scene.get_node_or_null("CanvasLayer/Panel")
	var dialogue := scene.get_node_or_null("CanvasLayer/DialoguePanel")
	var area := scene.get_node_or_null("Teacher/Area2D2")
	var result := teacher != null and quest_ui != null and dialogue != null and area != null
	scene.free()
	return result


func _pinehill_return_is_gated() -> bool:
	var packed := load("res://Door-Navigations-Scene2Scene/pinehill_to_city_of_knowledge.tscn") as PackedScene
	if packed == null:
		return false
	var door := packed.instantiate()
	var gated: bool = door.get("requires_city_of_knowledge_unlock") == true
	door.free()
	return gated


func _city_entry_is_gated() -> bool:
	var packed := load("res://Door-Navigations-Scene2Scene/go_to_city_of_knowledge.tscn") as PackedScene
	if packed == null:
		return false
	var door := packed.instantiate()
	var gated: bool = door.get("requires_city_of_knowledge_unlock") == true
	door.free()
	return gated


func _city_path_is_gated() -> bool:
	var packed := load("res://Door-Navigations-Scene2Scene/city_of_knowledge_to_pine_hill.tscn") as PackedScene
	if packed == null:
		return false
	var door := packed.instantiate()
	var gated: bool = door.get("requires_city_school_completion") == true
	door.free()
	return gated


func _cleanup_fixture(state: Node) -> void:
	for save_entry in state.list_saves():
		var save_path := String(save_entry.get("save_path", ""))
		if save_path.begins_with(SAVE_DIRECTORY + "/") and not _initial_save_paths.has(save_path):
			state.delete_save(save_path)


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if check.get("passed", false) != true:
			failed += 1
	print("CITY_FIRST_ARRIVAL_PROGRESSION_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(10.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
