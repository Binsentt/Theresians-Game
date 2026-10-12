extends Node

## Offline continuation contract. It exercises the real GameState serializer,
## route adapters, canonical/wrapper scenes, and original VS scene references.
## HttpApi/RemoteSync are removed before any fixture work.

const PROFILE := {"player_name": "Continuation QA Fixture", "gender": "male", "grade_level": "Grade 1", "student_id": "88002021", "parent_id": "880202"}
const CITY_PATH := "res://scenes/city_of_knowledge.tscn"
const FOREST_PATH := "res://scenes/deepest_forest_path.tscn"
const PINEHILL_PATH := "res://scenes/2nd Village/Pinehill Village.tscn"
const ROUTER := preload("res://scripts/progression_battle_encounter.gd")
const OLD_LADY := preload("res://scripts/progression_old_man_interaction.gd")

var checks: Array[Dictionary] = []
var qa_directory := ""
var qa_run_id := ""
var visible_forest_bandit_count := 0
var visible_pinehill_guard_count := 0

func _ready() -> void:
	call_deferred("_run")

func _expect(value: bool, label: String) -> void:
	checks.append({"label": label, "passed": value})
	if not value:
		push_error(label)

func _run() -> void:
	qa_run_id = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_cleanup_aborted_qa_attempts()
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	var state := get_node_or_null("/root/GameState")
	_expect(http != null and bool(http.get("local_qa_only")), "HTTP autoload starts in local-only mode before the progression test")
	_expect(remote != null and bool(remote.get("local_qa_only")), "RemoteSync starts with production writes disabled")
	_expect(state != null, "Canonical GameState autoload remains active for scene runtime")
	qa_directory = "user://qa_local_saves/forest_pinehill_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(qa_directory))
	if state != null:
		state.call("enable_local_qa_mode")
		state.set("_save_directory", qa_directory)
	if remote != null:
		remote.set("_pending_file", qa_directory + "/pending.json")

	_expect(ResourceLoader.exists("res://scenes/deepest_forest_path.tscn"), "Deepest Forest scene exists")
	_expect(ResourceLoader.exists("res://Door-Navigations-Scene2Scene/deepest_forest_to_pinehill.tscn"), "Deepest Forest exit door exists")
	_expect(ResourceLoader.exists("res://scenes/2nd Village/Pinehill Village.tscn"), "canonical Pinehill scene exists")
	_expect(ResourceLoader.exists("res://scenes/pinehill_village.tscn"), "Pinehill compatibility wrapper exists")
	_expect(ResourceLoader.exists("res://Door-Navigations-Scene2Scene/city_of_knowlwedge_to_pine_hill.tscn"), "legacy typo door remains present")
	await _check_progression_dialogue_layout()
	_check_forest_routes()
	_check_pinehill_routes()
	await _run_live_city_forest_pinehill_flow()
	_check_state_and_save_load()

	var failed := 0
	for check in checks:
		if not bool(check.get("passed", false)):
			failed += 1
	var report := {"passed": checks.size() - failed, "failed": failed, "visible_forest_bandits": visible_forest_bandit_count, "visible_pinehill_guards": visible_pinehill_guard_count, "live_network_calls": 0, "qa_local_only": true, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa_test_artifacts"))
	var report_file := FileAccess.open("user://qa_test_artifacts/deepest_forest_pinehill_%s.json" % qa_run_id, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("DEEPEST_FOREST_PINEHILL_FLOW_TEST " + JSON.stringify({"passed": report.passed, "failed": report.failed, "visible_forest_bandits": visible_forest_bandit_count, "visible_pinehill_guards": visible_pinehill_guard_count, "live_network_calls": 0, "qa_report": "user://qa_test_artifacts/deepest_forest_pinehill_%s.json" % qa_run_id}))
	_cleanup_qa_directory()
	await get_tree().create_timer(45.0).timeout
	get_tree().quit(1 if failed else 0)


func _run_live_city_forest_pinehill_flow() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	state.call("start_new_game", PROFILE, false)
	state.set("playtime_authorized", true)
	state.set("city_of_knowledge_unlocked", true)
	state.set("city_first_arrival_seen", true)
	state.set("city_school_stage_complete", true)
	state.set("city_next_path_unlocked", true)
	state.set("current_task_index", GameState.CITY_NEXT_PATH_TASK_INDEX)
	var city := (load(CITY_PATH) as PackedScene).instantiate() as Node2D
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(get_tree().current_scene.scene_file_path == CITY_PATH, "QA progression starts in the actual City of Knowledge scene")
	var city_exit: Door = null
	for candidate in city.find_children("*", "Door", true, false):
		var candidate_door := candidate as Door
		if candidate_door != null and candidate_door.destination_scene_path == FOREST_PATH:
			city_exit = candidate_door
			break
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node2D
	_expect(city_exit != null, "The canonical City exit node is present in the live City scene")
	_expect(player != null, "A live player body exists in the City scene")
	if city_exit == null or player == null:
		print("CITY_RUNTIME_DIAGNOSTIC exit_found=%s player_found=%s" % [str(city_exit != null), str(player != null)])
		return
	city_exit.play_fade_transition = false
	player.global_position = city_exit.global_position
	city_exit.body_entered.emit(player)
	await _wait_for_scene(FOREST_PATH)
	var forest := get_tree().current_scene as Node2D
	_expect(forest != null and forest.scene_file_path == FOREST_PATH, "Using the City exit enters res://scenes/deepest_forest_path.tscn")
	if forest == null or forest.scene_file_path != FOREST_PATH:
		return
	_expect(state.current_task_index == GameState.DEEP_FOREST_BANDIT_TASK_INDEX, "The completed Math Teacher quest activates the bandit objective on first Forest entry without a reload")
	_expect(String(state.current_quest) == "Defeat the Bandits in the Deepest Forest.", "The first Forest entry retains the canonical active bandit objective")
	player = _get_live_player()
	_expect(player != null, "Forest scene creates its current live player")
	if player == null:
		return
	await get_tree().process_frame
	var forest_exit := forest.find_child("DeepestForestToPinehill", true, false) as Door
	_expect(forest_exit != null and not bool(state.get("pinehill_unlocked")), "Pinehill exit exists but starts locked before any Forest victories")
	if forest_exit != null:
		var blocked_player_position := player.global_position
		forest_exit.call("_begin_transition", player)
		await get_tree().process_frame
		_expect(get_tree().current_scene == forest and state.current_scene_path == FOREST_PATH, "Attempting Pinehill before the five-bandit objective leaves the player in Deepest Forest")
		_expect(player.global_position.is_equal_approx(blocked_player_position), "Blocked Pinehill transition preserves the valid Forest player position")
		_expect(not bool(forest_exit.get("is_transitioning")), "Blocked Pinehill transition does not start a scene-change lifecycle")
	var objective_save: Dictionary = state.build_save_data()
	state.apply_save_data(objective_save, false)
	await get_tree().process_frame
	_expect(state.current_task_index == GameState.DEEP_FOREST_BANDIT_TASK_INDEX and not bool(state.get("pinehill_unlocked")), "Save/Load midway through the objective preserves the locked Forest stage")
	var forest_ids: Array = GameState.DEEP_FOREST_BANDIT_IDS
	for index in range(5):
		var actor_path := "ForestBackdrop/Bandits" if index == 0 else "ForestBackdrop/Bandits%d" % (index + 1)
		var actor := forest.get_node_or_null(actor_path) as Node2D
		var component := actor.get_node_or_null("ProgressionBattleEncounter") if actor != null else null
		var route: Dictionary = component.get("_route") if component != null else {}
		if actor != null and actor.is_visible_in_tree():
			visible_forest_bandit_count += 1
		_expect(actor != null and actor.is_visible_in_tree(), "Deepest Forest progression actor %d is visible in the live scene" % (index + 1))
		_expect(component != null, "Deepest Forest progression actor %d has a live adapter" % (index + 1))
		if component == null or actor == null:
			continue
		_expect(String(route.get("encounter_id", "")) == String(forest_ids[index]), "Deepest Forest actor %d keeps its canonical encounter ID" % (index + 1))
		_expect(String(route.get("difficulty", "")) == "Normal" and ResourceLoader.exists(String(route.get("male_scene", ""))) and ResourceLoader.exists(String(route.get("female_scene", ""))), "Deepest Forest actor %d routes to the existing Normal battle" % (index + 1))
		player.global_position = actor.global_position
		_expect(bool(component.call("can_interact")), "Deepest Forest actor %d is reachable/interactable at its authored position" % (index + 1))
		var result: Dictionary = state.call("record_progression_encounter_victory", String(forest_ids[index]), false)
		_expect(bool(result.get("changed", false)), "QA-only victory seed records Deepest Forest actor %d" % (index + 1))
	_expect(bool(state.get("pinehill_unlocked")), "Five seeded Deepest Forest victories unlock Pinehill")
	_expect(forest_exit != null, "Canonical forest-to-Pinehill door exists")
	if forest_exit == null:
		return
	forest_exit.play_fade_transition = false
	forest_exit.call("_begin_transition", player)
	await _wait_for_scene(PINEHILL_PATH)
	var pinehill := get_tree().current_scene as Node2D
	_expect(pinehill != null and pinehill.scene_file_path == PINEHILL_PATH, "Unlocked route enters canonical Pinehill Village")
	if pinehill == null or pinehill.scene_file_path != PINEHILL_PATH:
		return
	player = _get_live_player()
	_expect(player != null, "Pinehill scene creates its current live player")
	if player == null:
		return
	var pinehill_arrival_marker := pinehill.find_child("spawn_from_deepest_forest", true, false) as Node2D
	_expect(pinehill_arrival_marker != null and player.global_position.is_equal_approx(pinehill_arrival_marker.global_position), "Unlocked Pinehill transition uses its canonical arrival marker")
	await get_tree().process_frame
	var old_lady := pinehill.get_node_or_null("old_adult_women/ProgressionOldManInteraction")
	var old_lady_actor := pinehill.get_node_or_null("old_adult_women") as Node2D
	_expect(old_lady_actor != null and old_lady_actor.is_visible_in_tree(), "Old Lady is visible in live Pinehill")
	if old_lady != null and old_lady_actor != null:
		player.global_position = old_lady_actor.global_position
		_expect(bool(old_lady.call("can_interact")), "Old Lady is reachable/interactable at her authored position")
		old_lady.call("interact")
		for _line in range(4):
			await _tap_interact()
		for _frame in range(10):
			await get_tree().process_frame
	_expect(bool(state.get("pinehill_old_man_completed")), "Actual Old Lady dialogue interaction completes QA progression and unlocks the guard task")
	await get_tree().process_frame
	var locked_wizard := pinehill.get_node_or_null("Boss-Wizard") as Node2D
	var locked_wizard_component := locked_wizard.get_node_or_null("ProgressionBattleEncounter") if locked_wizard != null else null
	if locked_wizard != null and locked_wizard_component != null:
		player.global_position = locked_wizard.global_position
		_expect(locked_wizard.is_visible_in_tree(), "Outdoor Wizard remains visible before the guards are defeated")
		_expect(not bool(locked_wizard_component.call("can_interact")), "Outdoor Wizard cannot be interacted with before all four guards are defeated")
	var pinehill_ids: Array = GameState.PINEHILL_BANDIT_IDS
	for index in range(4):
		var actor_name := "Bandits" if index == 0 else "Bandits%d" % (index + 1)
		var actor := pinehill.get_node_or_null(actor_name) as Node2D
		var component := actor.get_node_or_null("ProgressionBattleEncounter") if actor != null else null
		var route: Dictionary = component.get("_route") if component != null else {}
		if actor != null and actor.is_visible_in_tree():
			visible_pinehill_guard_count += 1
		_expect(actor != null and actor.is_visible_in_tree(), "Pinehill progression guard %d is visible in the live scene" % (index + 1))
		_expect(component != null, "Pinehill guard %d has a live adapter" % (index + 1))
		if component == null or actor == null:
			continue
		_expect(String(route.get("encounter_id", "")) == String(pinehill_ids[index]), "Pinehill guard %d keeps its canonical encounter ID" % (index + 1))
		_expect(String(route.get("difficulty", "")) == "Difficult" and ResourceLoader.exists(String(route.get("male_scene", ""))) and ResourceLoader.exists(String(route.get("female_scene", ""))), "Pinehill guard %d routes to the existing Difficult battle" % (index + 1))
		player.global_position = actor.global_position
		_expect(bool(component.call("can_interact")), "Pinehill guard %d is reachable/interactable at its authored position" % (index + 1))
		var result: Dictionary = state.call("record_progression_encounter_victory", String(pinehill_ids[index]), false)
		_expect(bool(result.get("changed", false)), "QA-only victory seed records Pinehill guard %d" % (index + 1))
	var house := pinehill.get_node_or_null("display-kase yung wizard sa labas lang") as Node2D
	var wizard := pinehill.get_node_or_null("Boss-Wizard") as Node2D
	var wizard_component := wizard.get_node_or_null("ProgressionBattleEncounter") if wizard != null else null
	_expect(bool(state.call("can_start_progression_encounter", "pinehill_wizard")), "Four guard victories unlock one outdoor Wizard encounter")
	_expect(house != null and house.get_node_or_null("ProgressionBattleEncounter") == null, "The Wizard House remains scenery, not an encounter trigger")
	_expect(wizard != null and wizard.is_visible_in_tree() and wizard_component != null, "The single outdoor Wizard NPC remains visible with its trigger")
	if wizard_component != null and wizard != null:
		player.global_position = wizard.global_position
		_expect(bool(wizard_component.call("can_interact")), "Outdoor Wizard becomes reachable/interactable only after guard victories")
		var wizard_route: Dictionary = wizard_component.get("_route")
		_expect(String(wizard_route.get("encounter_id", "")) == "pinehill_wizard" and String(wizard_route.get("difficulty", "")) == "Difficult", "Outdoor Wizard keeps its single canonical Difficult encounter")
		_expect(ResourceLoader.exists(String(wizard_route.get("male_scene", ""))) and ResourceLoader.exists(String(wizard_route.get("female_scene", ""))), "Outdoor Wizard routes to existing gender-specific battles")
		_expect(bool(wizard_component.call("interact")), "Interacting with the outdoor Wizard starts the existing battle flow")
		var context: Dictionary = state.call("get_active_encounter_context")
		var question_scope: Dictionary = context.get("question_scope", {})
		_expect(String(context.get("encounter_id", "")) == "pinehill_wizard" and String(question_scope.get("difficulty", "")) == "Difficult", "Outdoor Wizard interaction starts its canonical encounter without entering a building")
		for _line in range(3):
			await _tap_interact()
		var battle_layer: Node = null
		for _attempt in range(120):
			await get_tree().process_frame
			battle_layer = pinehill.get_node_or_null("OriginalBattlePresentation")
			if battle_layer != null:
				break
		_expect(battle_layer != null and battle_layer.get_child_count() == 1, "Outdoor Wizard interaction presents one existing battle scene")
		if battle_layer != null and battle_layer.get_child_count() == 1:
			var battle_scene := battle_layer.get_child(0)
			_expect(String(battle_scene.scene_file_path) == "res://Battle/Battle-Enemy/male_vs_wizard.tscn", "Outdoor Wizard interaction loads the existing male Wizard battle")
			if battle_scene.has_signal("battle_finished"):
				battle_scene.emit_signal("battle_finished", false)
			else:
				battle_layer.queue_free()
				state.call("record_encounter_loss")
		for _frame in range(3):
			await get_tree().process_frame
		var wizard_victory: Dictionary = state.call("record_encounter_victory")
		if state.get_active_encounter_context().is_empty() and not bool(state.get("wizard_defeated")):
			wizard_victory = state.call("record_progression_encounter_victory", "pinehill_wizard", false)
		_expect(bool(state.get("wizard_defeated")) and int(state.get("return_to_city_stage")) == 2, "Wizard victory unlocks the canonical return route through Deepest Forest")
		var pinehill_forest_exit := pinehill.find_child("Pinehill-to-Deepest-Forest", true, false) as Door
		_expect(pinehill_forest_exit != null and pinehill_forest_exit.destination_scene_path == FOREST_PATH, "Pinehill returns through Deepest Forest, not directly to City")
		if pinehill_forest_exit != null:
			pinehill_forest_exit.play_fade_transition = false
			player.global_position = pinehill_forest_exit.global_position
			pinehill_forest_exit.call("_begin_transition", player)
			await _wait_for_scene(FOREST_PATH)
			var return_forest := get_tree().current_scene as Node2D
			var forest_return_marker := return_forest.find_child("spawn_from_pinehill", true, false) as Node2D if return_forest != null else null
			player = _get_live_player()
			_expect(return_forest != null and return_forest.scene_file_path == FOREST_PATH, "Leaving Pinehill returns to the canonical Deepest Forest")
			_expect(forest_return_marker != null and player != null and player.global_position.is_equal_approx(forest_return_marker.global_position), "Pinehill return uses the Forest's Pinehill arrival marker")
			var forest_city_exit := return_forest.find_child("DeepestForestToCity", true, false) as Door if return_forest != null else null
			_expect(forest_city_exit != null and forest_city_exit.destination_scene_path == CITY_PATH, "Deepest Forest has the canonical return door to City")
			if forest_city_exit != null and player != null:
				forest_city_exit.play_fade_transition = false
				player.global_position = forest_city_exit.global_position
				forest_city_exit.call("_begin_transition", player)
				await _wait_for_scene(CITY_PATH)
				var returned_city := get_tree().current_scene as Node2D
				var city_return_marker := returned_city.find_child("spawn_from_deepest_forest", true, false) as Node2D if returned_city != null else null
				player = _get_live_player()
				_expect(returned_city != null and returned_city.scene_file_path == CITY_PATH, "Deepest Forest return enters City without an unintended reload")
				_expect(city_return_marker != null and player != null and player.global_position.is_equal_approx(city_return_marker.global_position), "Forest return spawns at the dedicated lower City entrance marker, not the upper-map fallback")


func _wait_for_scene(scene_path: String) -> void:
	for _attempt in range(200):
		await get_tree().process_frame
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == scene_path:
			await get_tree().process_frame
			await get_tree().process_frame
			return
	await get_tree().create_timer(0.1).timeout


func _tap_interact() -> void:
	InputManager.set_mobile_interact_pressed(false)
	await get_tree().process_frame
	InputManager.set_mobile_interact_pressed(true)
	await get_tree().process_frame
	InputManager.set_mobile_interact_pressed(false)
	await get_tree().process_frame


func _get_live_player() -> Node2D:
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node2D
	return player


func _cleanup_aborted_qa_attempts() -> void:
	# These three process IDs are the exact failed runs of this local-only QA
	# harness in this task. Refuse cleanup if an unexpected filename is present.
	var known_prefixes := ["forest_pinehill_13176_", "forest_pinehill_40308_", "forest_pinehill_5532_"]
	var parent := "user://qa_local_saves"
	for directory_name in DirAccess.get_directories_at(parent):
		var owned_attempt := false
		for prefix in known_prefixes:
			if String(directory_name).begins_with(prefix):
				owned_attempt = true
				break
		if not owned_attempt:
			continue
		var attempt_path := parent.path_join(String(directory_name))
		var files := DirAccess.get_files_at(attempt_path)
		var safe_to_remove := true
		for file_name in files:
			var file := String(file_name)
			if file != "pending.json" and not file.begins_with("save_88002021_") and not file.begins_with("save_87654321_") and not file.begins_with("preservation_regression_"):
				safe_to_remove = false
				break
		if not safe_to_remove:
			push_warning("Leaving an aborted QA folder untouched because it contains an unexpected file")
			continue
		var absolute_attempt_path := ProjectSettings.globalize_path(attempt_path)
		for file_name in files:
			DirAccess.remove_absolute(absolute_attempt_path.path_join(String(file_name)))
		DirAccess.remove_absolute(absolute_attempt_path)
	InputManager.set_mobile_interact_pressed(true)
	await get_tree().process_frame
	InputManager.set_mobile_interact_pressed(false)
	await get_tree().process_frame


func _cleanup_qa_directory() -> void:
	if qa_directory.is_empty():
		return
	var absolute_dir := ProjectSettings.globalize_path(qa_directory)
	if not DirAccess.dir_exists_absolute(absolute_dir):
		return
	for file_name in DirAccess.get_files_at(absolute_dir):
		DirAccess.remove_absolute(absolute_dir.path_join(file_name))
	DirAccess.remove_absolute(absolute_dir)

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
	var house := pinehill.get_node_or_null("display-kase yung wizard sa labas lang")
	_expect(house != null and house.get_node_or_null("ProgressionBattleEncounter") == null, "Wizard House artwork is not an encounter trigger")
	var wizard := pinehill.get_node_or_null("Boss-Wizard") as Node2D
	var wizard_component := wizard.get_node_or_null("ProgressionBattleEncounter") if wizard != null else null
	_expect(wizard != null and wizard.visible, "The authored outdoor Wizard NPC remains visible")
	_expect(wizard_component != null, "The outdoor Wizard NPC owns the single progression trigger")
	if wizard_component != null:
		var route: Dictionary = wizard_component.get("_route")
		_expect(String(route.get("encounter_id", "")) == "pinehill_wizard", "Outdoor Wizard encounter ID is preserved")
		GameState.gender = "male"
		_expect(String(wizard_component.call("_battle_scene_path")) == "res://Battle/Battle-Enemy/male_vs_wizard.tscn", "male Wizard route preserved")
		GameState.gender = "female"
		_expect(String(wizard_component.call("_battle_scene_path")) == "res://Battle/Battle-Enemy/female_vs_wizard1.tscn", "female Wizard route preserved")
	pinehill.free()
	var wrapper := (load("res://scenes/pinehill_village.tscn") as PackedScene).instantiate() as Node2D
	_expect(wrapper != null, "Pinehill wrapper instantiates")
	if wrapper != null:
		ROUTER.install_for_scene(wrapper, ROUTER)
		OLD_LADY.install_for_scene(wrapper, OLD_LADY)
		_expect(wrapper.get_node_or_null("old_adult_women/ProgressionOldManInteraction") != null, "Pinehill wrapper binds the Old Lady")
		_expect(wrapper.get_node_or_null("Boss-Wizard/ProgressionBattleEncounter") != null, "Pinehill wrapper binds the outdoor Wizard NPC")
		_expect(wrapper.get_node_or_null("display-kase yung wizard sa labas lang/ProgressionBattleEncounter") == null, "Pinehill wrapper leaves the Wizard House non-interactive")
		wrapper.free()

func _check_progression_dialogue_layout() -> void:
	var packed := load("res://ui/progression_dialogue_overlay.tscn") as PackedScene
	var overlay := packed.instantiate() as CanvasLayer if packed != null else null
	_expect(overlay != null, "Progression dialogue overlay instantiates")
	if overlay == null:
		return
	add_child(overlay)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := overlay.get_node_or_null("DialoguePanel") as Control
	var prompt := overlay.get_node_or_null("DialoguePanel/DialogueContent/ContinuePrompt") as Label
	_expect(panel != null, "Progression dialogue has a panel")
	if panel != null:
		var viewport_size := get_viewport().get_visible_rect().size
		var panel_rect := panel.get_global_rect()
		var height_ratio := panel_rect.size.y / viewport_size.y if viewport_size.y > 0.0 else 0.0
		var left_margin_ratio := panel_rect.position.x / viewport_size.x if viewport_size.x > 0.0 else 0.0
		_expect(height_ratio >= 0.25 and height_ratio <= 0.35, "Progression dialogue occupies 25–35% of live viewport height")
		var action_rect := Rect2(Vector2(viewport_size.x - 262.0, viewport_size.y - 262.0), Vector2(200.0, 160.0))
		_expect(left_margin_ratio >= 0.04 and left_margin_ratio <= 0.1 and panel_rect.end.x <= action_rect.position.x - 12.0 and panel_rect.size.x >= 300.0 and not panel_rect.intersects(action_rect), "Progression dialogue keeps a readable left margin and reserves the ACT control area")
	_expect(prompt != null, "Progression dialogue keeps its ACT/continue prompt inside the panel")
	if prompt != null:
		var prompt_rect := prompt.get_global_rect()
		var panel_rect := panel.get_global_rect() if panel != null else Rect2()
		_expect(prompt.visible and prompt.text.contains("ACT") and prompt.text.contains("CONTINUE") and prompt.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "ACT/continue prompt is visible, readable, and aligned inside the dialogue")
		_expect(panel_rect.encloses(prompt_rect), "ACT/continue prompt stays fully inside the dialogue panel")
	overlay.queue_free()
	await get_tree().process_frame

func _check_state_and_save_load() -> void:
	var state: Node = load("res://tools/preservation_regression_state.gd").new()
	state.set("_save_directory", qa_directory)
	state.fixture_path = "%s/preservation_regression_%d.json" % [qa_directory, Time.get_ticks_usec()]
	add_child(state)
	state.start_new_game(PROFILE, false)
	var old_lady_task: Dictionary = state.tasks[state.PINEHILL_OLD_MAN_TASK_INDEX]
	var old_lady_lines: Array = old_lady_task.get("dialogue", [])
	_expect(old_lady_lines.size() == 4 and String(old_lady_lines[1]).to_lower().contains("outside"), "Canonical Old Lady dialogue directs the player to the Wizard outside")
	_expect(not String(old_lady_lines[1]).to_lower().contains("inside the tower"), "Canonical Old Lady dialogue does not imply a tower interior step")
	_expect(String(OLD_LADY.DIALOGUE_LINES[1]).to_lower().contains("outside") and String(OLD_LADY.DIALOGUE_LINES[3]).to_lower().contains("challenge the wizard"), "Live Old Lady adapter points to the outdoor Wizard after the guards")
	_expect(not String(ROUTER.PINEHILL_GUARDS_COMPLETE_DIALOGUE[0]).to_lower().contains("tower"), "Guard completion does not announce a tower/interior unlock")
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
	_expect(state.current_task_index == state.WIZARD_TASK_INDEX and state.can_start_progression_encounter("pinehill_wizard"), "all four guards unlock the outdoor Wizard challenge")
	_expect(String(state.get_current_quest_text()) == "Talk to the Wizard", "Wizard objective displays the concise interaction prompt without a tower step")
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
