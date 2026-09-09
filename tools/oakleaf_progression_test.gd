extends Node

## Focused state/progression fixture for the authorized Oakleaf -> City unlock.
## It exercises the real GameState serializer/loader and existing route contracts;
## it does not instantiate or replace any battle UI.

const SAVE_DIRECTORY := "user://saves"
const FIXTURE_PATH := SAVE_DIRECTORY + "/oakleaf_progression_fixture.json"
const OAKLEAF := "res://scenes/oak_leaf_village.tscn"
const NORMAL_IDS := [
	"oakleaf_bandits1",
	"oakleaf_bandits2",
	"oakleaf_bandits3",
	"oakleaf_bandits4",
	"oakleaf_bandits5",
]
const PROFILE := {
	"player_name": "Oakleaf Fixture",
	"gender": "male",
	"grade_level": "Grade 1",
	"student_id": "12345678",
	"parent_id": "123456",
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
	state.student_id = String(PROFILE.student_id)
	state.parent_id = String(PROFILE.parent_id)
	for save_entry in state.list_saves():
		_initial_save_paths[String(save_entry.get("save_path", ""))] = true
	if not _has_required_api(state):
		_cleanup_fixture(state)
		_finish()
		return
	_expect(FileAccess.get_file_as_string("res://scripts/teacher_task_interaction.gd").contains("is_oakleaf_return_to_teacher_active"), "existing Teacher interaction adapter owns the Return to Teacher gate")
	_expect(FileAccess.get_file_as_string("res://world/QuestUI.gd").contains("complete_oakleaf_teacher_return"), "existing Teacher dialogue host completes Oakleaf once")

	var legacy := {
		"save_version": 8,
		"player_name": "Legacy Oakleaf",
		"gender": "male",
		"grade_level": "Grade 1",
		"student_id": "12345678",
		"parent_id": "123456",
		"scene_path": OAKLEAF,
		"current_task_index": 3,
		"current_quest": "No active quest",
		"player_position": {"x": 100.0, "y": 100.0},
	}
	state.apply_save_data(legacy, false)
	_expect(state.current_task_index == 3, "old save keeps its completed First Bandit checkpoint")
	_expect(state.is_oakleaf_bandit_defeated("oakleaf_bandits1"), "old save migrates checkpoint 3 to Bandit1 defeated")
	_expect(state.get_oakleaf_defeated_bandit_count() == 1, "old save defaults only the source-supported Bandit1 defeat")

	state.start_new_game(PROFILE, false)
	_expect(state.current_task_index == 0 and state.is_tutorial_active(), "new game starts at Tutorial")
	state.complete_tutorial_activity()
	_expect(state.current_task_index == 0 and state.current_quest == "Go to the Teacher's House", "Tutorial completion exposes Teacher House objective")
	state.current_task_index = 1
	state.current_quest = "Talk to the Teacher"
	state.advance_task_and_save({"type": "task_completed", "key": "fixture:teacher"})
	_expect(state.current_task_index == 2 and state.current_quest == String(state.tasks[2].quest_text), "Teacher completion exposes First Bandit stage")

	state.begin_encounter({"encounter_id": "oakleaf_bandits1", "source_scene_path": OAKLEAF, "quest_checkpoint": 2})
	state.record_encounter_victory()
	state.advance_task_and_save({"type": "task_completed", "key": "fixture:bandit1"})
	_expect(state.is_oakleaf_bandit_defeated("oakleaf_bandits1") and state.current_task_index == 3, "Bandit1 defeat persists and opens normal Oakleaf bandits")
	_expect(state.get_oakleaf_defeated_bandit_count() == 1 and state.get_current_quest_text() == "Defeat All Bandits", "Bandit1 alone keeps Quest 3 at Defeat All Bandits")
	_expect(not state.can_start_oakleaf_encounter("oakleaf_boss_bandit"), "1/5 normal Bandits keeps the Boss blocked")
	_expect(not state.city_of_knowledge_unlocked and not state.is_oakleaf_return_to_teacher_active(), "Bandit1 alone cannot unlock City or the Teacher return")

	var bandit1_save: Dictionary = state.build_save_data()
	state.start_new_game(PROFILE, false)
	state.apply_save_data(bandit1_save, false)
	_expect(state.is_oakleaf_bandit_defeated("oakleaf_bandits1") and state.get_oakleaf_defeated_bandit_count() == 1, "Save/Load after Bandit1 preserves only Bandit1")
	_expect(not state.is_oakleaf_bandit_defeated("oakleaf_bandits2") and not state.is_oakleaf_bandit_defeated("oakleaf_bandits3") and not state.is_oakleaf_bandit_defeated("oakleaf_bandits4") and not state.is_oakleaf_bandit_defeated("oakleaf_bandits5"), "Save/Load after Bandit1 leaves Bandits2-5 required")
	_expect(state.current_task_index == 3 and state.get_current_quest_text() == "Defeat All Bandits" and not state.city_of_knowledge_unlocked, "Save/Load after Bandit1 preserves Quest 3 and the City gate")

	for index in range(1, NORMAL_IDS.size()):
		var encounter_id: String = NORMAL_IDS[index]
		state.begin_encounter({"encounter_id": encounter_id, "source_scene_path": OAKLEAF, "quest_checkpoint": 3})
		var result: Dictionary = state.record_encounter_victory()
		_expect(bool(result.get("oakleaf", {}).get("changed", false)) and state.is_oakleaf_bandit_defeated(encounter_id), "%s defeat is recorded independently" % encounter_id)
		_expect(state.get_oakleaf_defeated_bandit_count() == index + 1, "%d/5 normal Bandits is counted from unique encounter IDs" % (index + 1))
		if index < NORMAL_IDS.size() - 1:
			_expect(state.current_task_index == 3 and state.get_current_quest_text() == "Defeat All Bandits", "normal bandit stage remains active until all five are defeated")
			_expect(not state.can_start_oakleaf_encounter("oakleaf_boss_bandit") and not state.city_of_knowledge_unlocked, "%d/5 normal Bandits keeps the Boss blocked and City locked" % (index + 1))
		else:
			_expect(state.current_task_index == 4 and state.are_all_oakleaf_bandits_defeated() and state.get_current_quest_text() == "Defeat the Boss Bandit", "all normal Bandits unlock only the Boss stage")
			_expect(not state.oakleaf_boss_defeated and not state.is_oakleaf_return_to_teacher_active() and not state.city_of_knowledge_unlocked, "5/5 without Boss victory does not complete Quest 3 or unlock City")
		if index == 2:
			var bandit3_save: Dictionary = state.build_save_data()
			state.start_new_game(PROFILE, false)
			state.apply_save_data(bandit3_save, false)
			_expect(state.get_oakleaf_defeated_bandit_count() == 3 and state.is_oakleaf_bandit_defeated("oakleaf_bandits1") and state.is_oakleaf_bandit_defeated("oakleaf_bandits2") and state.is_oakleaf_bandit_defeated("oakleaf_bandits3"), "Save/Load after Bandit3 preserves Bandits1-3")
			_expect(not state.is_oakleaf_bandit_defeated("oakleaf_bandits4") and not state.is_oakleaf_bandit_defeated("oakleaf_bandits5") and not state.can_start_oakleaf_encounter("oakleaf_boss_bandit"), "Save/Load after Bandit3 leaves Bandits4-5 required and Boss blocked")

	var duplicate_result: Dictionary = state.record_oakleaf_encounter_victory("oakleaf_bandits5")
	_expect(not bool(duplicate_result.get("changed", false)) and state.get_oakleaf_defeated_bandit_count() == 5, "duplicate Bandit defeat awards no second progression")
	var normal_complete_save: Dictionary = state.build_save_data()
	state.start_new_game(PROFILE, false)
	state.apply_save_data(normal_complete_save, false)
	_expect(state.are_all_oakleaf_bandits_defeated() and state.get_oakleaf_defeated_bandit_count() == 5, "Save/Load after Bandit5 preserves all five normal defeats")
	_expect(not state.oakleaf_boss_defeated and state.current_task_index == 4 and state.get_current_quest_text() == "Defeat the Boss Bandit", "Save/Load after Bandit5 keeps the Boss required")
	_expect(not state.city_of_knowledge_unlocked and not state.is_oakleaf_return_to_teacher_active(), "Save/Load after Bandit5 cannot bypass Boss or unlock City")

	_verify_count_gates_and_unusual_order(state)
	# The Boss gate is checked before and after the required-normal condition.
	state.start_new_game(PROFILE, false)
	state.current_task_index = 3
	_expect(not state.can_start_oakleaf_encounter("oakleaf_boss_bandit"), "Boss is locked before all normal Bandits")
	var early_boss_result: Dictionary = state.record_oakleaf_encounter_victory("oakleaf_boss_bandit")
	_expect(not bool(early_boss_result.get("changed", false)) and not state.oakleaf_boss_defeated, "Boss victory cannot be recorded before all five normal Bandits")
	var early_teacher_result: Dictionary = state.complete_oakleaf_teacher_return()
	_expect(not bool(early_teacher_result.get("changed", false)) and not state.city_of_knowledge_unlocked, "Teacher handoff cannot bypass the Boss")
	for encounter_id in NORMAL_IDS:
		state.oakleaf_defeated_bandits[encounter_id] = true
	state.current_task_index = 4
	_expect(state.can_start_oakleaf_encounter("oakleaf_boss_bandit"), "Boss is available after all normal Bandits")
	_expect(not state.oakleaf_boss_defeated and not state.city_of_knowledge_unlocked and state.get_current_quest_text() == "Defeat the Boss Bandit", "5/5 without Boss remains an incomplete Quest 3")
	_expect(ResourceLoader.exists("res://Battle/Battle-Enemy/male_vs_boss.tscn") and ResourceLoader.exists("res://Battle/Battle-Enemy/female_vs_boss_bandit.tscn"), "Boss male/female original VS routes remain available")

	state.begin_encounter({"encounter_id": "oakleaf_boss_bandit", "source_scene_path": OAKLEAF, "quest_checkpoint": 4})
	var boss_result: Dictionary = state.record_encounter_victory()
	_expect(bool(boss_result.get("oakleaf", {}).get("changed", false)) and state.oakleaf_boss_defeated, "Boss victory records exactly once")
	_expect(state.current_task_index == 5 and state.is_oakleaf_return_to_teacher_active(), "Boss victory advances to Return to Teacher")
	_expect(not state.city_of_knowledge_unlocked, "Boss victory alone still requires the Teacher handoff before City")
	var duplicate_boss: Dictionary = state.record_oakleaf_encounter_victory("oakleaf_boss_bandit")
	_expect(not bool(duplicate_boss.get("changed", false)) and state.oakleaf_boss_defeated and state.current_task_index == 5, "duplicate Boss defeat cannot complete or advance Quest 3 twice")

	var boss_save: Dictionary = state.build_save_data()
	state.start_new_game(PROFILE, false)
	state.apply_save_data(boss_save, false)
	_expect(state.oakleaf_boss_defeated and state.current_task_index == 5 and state.is_oakleaf_return_to_teacher_active(), "Save/Load preserves Boss and Return to Teacher state")
	_expect(state.is_oakleaf_encounter_defeated("oakleaf_boss_bandit"), "Boss defeated state is independent from normal Bandit flags")

	var teacher_result: Dictionary = state.complete_oakleaf_teacher_return()
	_expect(bool(teacher_result.get("changed", false)) and state.city_of_knowledge_unlocked, "Teacher return completes Oakleaf and unlocks City")
	_expect(state.current_task_index == 6 and state.current_quest == "Go to the City of Knowledge / School", "City objective becomes the current quest")
	var duplicate_teacher: Dictionary = state.complete_oakleaf_teacher_return()
	_expect(not bool(duplicate_teacher.get("changed", false)), "Teacher completion emits no duplicate completion")

	var city_save: Dictionary = state.build_save_data()
	state.start_new_game(PROFILE, false)
	state.apply_save_data(city_save, false)
	_expect(state.city_of_knowledge_unlocked and state.current_task_index == 6, "Save/Load preserves City unlock")
	_expect(_city_door_is_gated(), "existing City door remains gated by the authoritative unlock flag")
	_expect(state.current_task_index >= 3 and state.current_task_index <= 6, "Oakleaf progression never regresses to an earlier task")
	_expect(state.SAVE_VERSION >= 9 and city_save.has("oakleaf_defeated_bandits") and city_save.has("oakleaf_boss_defeated") and city_save.has("oakleaf_return_to_teacher"), "only the authorized Oakleaf fields extend persistence")

	_cleanup_fixture(state)
	_finish()


func _verify_count_gates_and_unusual_order(state: Node) -> void:
	for defeated_count in range(0, NORMAL_IDS.size() + 1):
		state.start_new_game(PROFILE, false)
		state.current_task_index = 3 if defeated_count < NORMAL_IDS.size() else 4
		for index in defeated_count:
			state.oakleaf_defeated_bandits[NORMAL_IDS[index]] = true
		state.current_quest = state.get_current_quest_text()
		_expect(state.get_oakleaf_defeated_bandit_count() == defeated_count, "%d/5 gate fixture retains the exact unique defeat count" % defeated_count)
		if defeated_count < NORMAL_IDS.size():
			_expect(not state.can_start_oakleaf_encounter("oakleaf_boss_bandit"), "%d/5 normal Bandits blocks the Boss" % defeated_count)
		else:
			_expect(state.can_start_oakleaf_encounter("oakleaf_boss_bandit"), "5/5 normal Bandits enables the Boss")
			_expect(not state.oakleaf_boss_defeated and not state.city_of_knowledge_unlocked and state.get_current_quest_text() == "Defeat the Boss Bandit", "5/5 normal Bandits still requires the Boss")

	state.start_new_game(PROFILE, false)
	state.current_task_index = 3
	state.oakleaf_defeated_bandits["oakleaf_bandits1"] = true
	var out_of_order: Dictionary = state.record_oakleaf_encounter_victory("oakleaf_bandits5")
	_expect(bool(out_of_order.get("changed", false)) and state.get_oakleaf_defeated_bandit_count() == 2, "an available out-of-order Bandit records only its own unique ID")
	for attempt in 5:
		var repeated: Dictionary = state.record_oakleaf_encounter_victory("oakleaf_bandits5")
		_expect(not bool(repeated.get("changed", false)), "repeat defeat attempt %d for one Bandit is blocked" % (attempt + 1))
	_expect(state.get_oakleaf_defeated_bandit_count() == 2 and not state.can_start_oakleaf_encounter("oakleaf_boss_bandit"), "defeating one Bandit repeatedly cannot count as five or bypass the Boss")
	var skipped_boss: Dictionary = state.record_oakleaf_encounter_victory("oakleaf_boss_bandit")
	_expect(not bool(skipped_boss.get("changed", false)) and not state.oakleaf_boss_defeated and not state.city_of_knowledge_unlocked, "unusual normal-Bandit order cannot skip the remaining Bandits, Boss, or City gate")


func _has_required_api(state: Node) -> bool:
	var required := [
		"is_oakleaf_bandit_defeated",
		"is_oakleaf_encounter_defeated",
		"get_oakleaf_defeated_bandit_count",
		"are_all_oakleaf_bandits_defeated",
		"can_start_oakleaf_encounter",
		"record_oakleaf_encounter_victory",
		"is_oakleaf_return_to_teacher_active",
		"complete_oakleaf_teacher_return",
	]
	for method_name in required:
		_expect(state.has_method(method_name), "GameState exposes %s" % method_name)
	return _checks.filter(func(row: Dictionary) -> bool: return not bool(row.get("passed", false))).is_empty()


func _city_door_is_gated() -> bool:
	var packed := load("res://Door-Navigations-Scene2Scene/go_to_city_of_knowledge.tscn") as PackedScene
	if packed == null:
		return false
	var door := packed.instantiate()
	var gated := bool(door.get("requires_city_of_knowledge_unlock"))
	door.free()
	return gated


func _cleanup_fixture(state: Node) -> void:
	if FileAccess.file_exists(FIXTURE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
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
		if not bool(check.get("passed", false)):
			failed += 1
	var report := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks}
	print("OAKLEAF_PROGRESSION_TEST " + JSON.stringify(report))
	await get_tree().create_timer(10.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
