extends Node

## Offline continuation contract. It exercises the real GameState serializer,
## route adapters, canonical/wrapper scenes, and original VS scene references.
## HttpApi/RemoteSync are removed before any fixture work.

const PROFILE := {"player_name": "Continuation Fixture", "gender": "male", "grade_level": "Grade 1", "student_id": "87654321", "parent_id": "123456"}
const RESULT_PATH := "res://tools/deepest_forest_pinehill_flow_result.json"
const ROUTER := preload("res://scripts/progression_battle_encounter.gd")
const OLD_LADY := preload("res://scripts/progression_old_man_interaction.gd")

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

	_expect(ResourceLoader.exists("res://scenes/deepest_forest_path.tscn"), "Deepest Forest scene exists")
	_expect(ResourceLoader.exists("res://Door-Navigations-Scene2Scene/deepest_forest_to_pinehill.tscn"), "Deepest Forest exit door exists")
	_expect(ResourceLoader.exists("res://scenes/2nd Village/Pinehill Village.tscn"), "canonical Pinehill scene exists")
	_expect(ResourceLoader.exists("res://scenes/pinehill_village.tscn"), "Pinehill compatibility wrapper exists")
	_expect(ResourceLoader.exists("res://Door-Navigations-Scene2Scene/city_of_knowlwedge_to_pine_hill.tscn"), "legacy typo door remains present")
	_check_forest_routes()
	_check_pinehill_routes()
	_check_state_and_save_load()

	var failed := 0
	for check in checks:
		if not bool(check.get("passed", false)):
			failed += 1
	var evidence := {"passed": checks.size() - failed, "failed": failed, "checks": checks, "live_network_calls": 0}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	print("DEEPEST_FOREST_PINEHILL_FLOW_TEST " + JSON.stringify({"passed": checks.size() - failed, "failed": failed}))
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(1 if failed else 0)

func _check_forest_routes() -> void:
	var forest := (load("res://scenes/deepest_forest_path.tscn") as PackedScene).instantiate() as Node2D
	_expect(forest != null, "Deepest Forest scene instantiates")
	if forest == null:
		return
	ROUTER.install_for_scene(forest, ROUTER)
	for index in 5:
		var actor_path := "ForestBackdrop/Bandits" if index == 0 else "ForestBackdrop/Bandits%d" % (index + 1)
		var actor := forest.get_node_or_null(actor_path)
		var component := actor.get_node_or_null("ProgressionBattleEncounter") if actor != null else null
		_expect(component != null, "deep forest trigger %d installed once" % (index + 1))
		if component != null:
			var route: Dictionary = component.get("_route")
			_expect(String(route.get("encounter_id", "")) == "deep_forest_bandits%d" % (index + 1), "deep forest ID %d is stable" % (index + 1))
			_expect(String(route.get("difficulty", "")) == "Normal", "deep forest difficulty is Normal")
			GameState.gender = "male"
			_expect(String(component.call("_battle_scene_path")) == "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "deep forest male route %d" % (index + 1))
			GameState.gender = "female"
			_expect(String(component.call("_battle_scene_path")) == "res://Battle/Battle-Enemy/female_vs_bandit.tscn", "deep forest female route %d" % (index + 1))
	forest.free()

func _check_pinehill_routes() -> void:
	var pinehill := (load("res://scenes/2nd Village/Pinehill Village.tscn") as PackedScene).instantiate() as Node2D
	_expect(pinehill != null, "canonical Pinehill instantiates")
	if pinehill == null:
		return
	ROUTER.install_for_scene(pinehill, ROUTER)
	OLD_LADY.install_for_scene(pinehill, OLD_LADY)
	var lady := pinehill.get_node_or_null("old_adult_women")
	_expect(lady != null and lady.get_node_or_null("ProgressionOldManInteraction") != null, "Old Lady receives the legacy-compatible adapter")
	for index in 4:
		var actor_name := "Bandits" if index == 0 else "Bandits%d" % (index + 1)
		var actor := pinehill.get_node_or_null(actor_name)
		_expect(actor != null and actor.get_node_or_null("ProgressionBattleEncounter") != null, "Pinehill guard trigger %d installed once" % (index + 1))
	var tower := pinehill.get_node_or_null("display-kase yung wizard sa labas lang")
	var tower_component := tower.get_node_or_null("ProgressionBattleEncounter") if tower != null else null
	_expect(tower_component != null, "Wizard Tower artwork owns the wizard trigger")
	var legacy_wizard := pinehill.get_node_or_null("Boss-Wizard")
	_expect(legacy_wizard == null or legacy_wizard.is_queued_for_deletion() or not legacy_wizard.visible, "legacy outside Wizard trigger removed to prevent duplicate battle")
	if tower_component != null:
		var route: Dictionary = tower_component.get("_route")
		_expect(String(route.get("encounter_id", "")) == "pinehill_wizard", "Wizard encounter ID is preserved")
		GameState.gender = "male"
		_expect(String(tower_component.call("_battle_scene_path")) == "res://Battle/Battle-Enemy/male_vs_wizard.tscn", "male Wizard route preserved")
		GameState.gender = "female"
		_expect(String(tower_component.call("_battle_scene_path")) == "res://Battle/Battle-Enemy/female_vs_wizard1.tscn", "female Wizard route preserved")
	pinehill.free()
	var wrapper := (load("res://scenes/pinehill_village.tscn") as PackedScene).instantiate() as Node2D
	_expect(wrapper != null, "Pinehill wrapper instantiates")
	if wrapper != null:
		ROUTER.install_for_scene(wrapper, ROUTER)
		OLD_LADY.install_for_scene(wrapper, OLD_LADY)
		_expect(wrapper.get_node_or_null("old_adult_women/ProgressionOldManInteraction") != null, "Pinehill wrapper binds the Old Lady")
		_expect(wrapper.get_node_or_null("display-kase yung wizard sa labas lang/ProgressionBattleEncounter") != null, "Pinehill wrapper binds Wizard Tower")
		wrapper.free()

func _check_state_and_save_load() -> void:
	var state: Node = load("res://tools/preservation_regression_state.gd").new()
	state.fixture_path = "user://saves/deepest_forest_pinehill_%d.json" % Time.get_ticks_usec()
	add_child(state)
	state.start_new_game(PROFILE, false)
	state.city_of_knowledge_unlocked = true
	state.city_school_stage_complete = true
	state.city_next_path_unlocked = true
	state.current_task_index = state.CITY_NEXT_PATH_TASK_INDEX
	state.handle_scene_entered("res://scenes/deepest_forest_path.tscn")
	_expect(state.current_task_index == state.DEEP_FOREST_BANDIT_TASK_INDEX, "City School enters Deepest Forest task")
	for encounter_id in state.DEEP_FOREST_BANDIT_IDS:
		state.record_progression_encounter_victory(encounter_id, false)
	_expect(state.pinehill_unlocked and state.current_task_index == state.PINEHILL_ARRIVAL_TASK_INDEX, "all five deep-forest victories unlock Pinehill")
	var saved: Dictionary = state.build_save_data()
	state.current_task_index = 0
	state.deep_forest_defeated_bandits.clear()
	state.pinehill_unlocked = false
	state.apply_save_data(saved, false)
	_expect(state.pinehill_unlocked and state.deep_forest_defeated_bandits.size() == 5, "deep-forest defeated state survives load")
	state.handle_scene_entered("res://scenes/pinehill_village.tscn")
	_expect(state.current_task_index == state.PINEHILL_OLD_MAN_TASK_INDEX, "Pinehill wrapper advances to Old Lady task")
	state.complete_pinehill_old_lady()
	_expect(state.current_task_index == state.PINEHILL_BANDIT_TASK_INDEX, "Old Lady gates the four guards")
	for encounter_id in state.PINEHILL_BANDIT_IDS:
		state.record_progression_encounter_victory(encounter_id, false)
	_expect(state.current_task_index == state.WIZARD_TASK_INDEX and state.can_start_progression_encounter("pinehill_wizard"), "all four guards unlock Wizard Tower")
	state.record_progression_encounter_victory("pinehill_wizard", false)
	_expect(state.wizard_defeated and state.current_task_index == state.RETURN_CITY_TASK_INDEX, "Wizard victory requires return to City")
	state.handle_scene_entered("res://scenes/city_of_knowledge.tscn")
	_expect(state.current_task_index == state.FINAL_SCHOOL_TASK_INDEX, "return City advances to final School")
	state.handle_scene_entered("res://interiors/school.tscn")
	_expect(state.current_task_index == state.FINAL_TEACHER_TASK_INDEX, "final Teacher remains gated behind School")
	state.record_progression_encounter_victory("final_teacher", false)
	_expect(state.journey_complete and state.get_current_quest_text() == "Math Champion", "final Teacher completes journey once")
	var completed: Dictionary = state.build_save_data()
	state.apply_save_data(completed, false)
	_expect(state.journey_complete and state.current_task_index >= state.tasks.size(), "completion is monotonic after reload")
	state.queue_free()
