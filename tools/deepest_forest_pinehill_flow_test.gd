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
	_expect(_complete_canonical_progression_to_city(state), "Public progression boundaries unlock City and the School/Forest route")
	var city := (load(CITY_PATH) as PackedScene).instantiate() as Node2D
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(get_tree().current_scene.scene_file_path == CITY_PATH, "QA progression starts in the actual City of Knowledge scene")
	_expect(state.current_task_index == GameState.CITY_SCHOOL_TASK_INDEX, "Canonical City arrival activates the School objective")
	var school_door: Door = null
	for candidate in city.find_children("*", "Door", true, false):
		var candidate_door := candidate as Door
		if candidate_door != null and candidate_door.destination_scene_path == "res://interiors/school.tscn":
			school_door = candidate_door
			break
	var player := _get_live_player()
	_expect(school_door != null and player != null, "The canonical City School entrance and live player are present")
	if school_door == null or player == null:
		return
	school_door.play_fade_transition = false
	var entered_school := await _walk_player_into_door(school_door, player)
	_expect(entered_school, "Player walks through the canonical City School entrance using gameplay movement and door physics")
	await _wait_for_scene("res://interiors/school.tscn")
	_expect(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://interiors/school.tscn", "City School is entered through its actual door")
	_expect(state.current_task_index == GameState.CITY_SCHOOL_TEACHER_TASK_INDEX, "Entering School activates the Math Teacher objective")
	var school := get_tree().current_scene as Node2D
	var teacher := school.get_node_or_null("Teacher")
	var teacher_sensor := school.get_node_or_null("Teacher/Area2D2") as Area2D
	var school_dialogue := school.get_node_or_null("CanvasLayer/Panel")
	player = _get_live_player()
	_expect(teacher != null and teacher_sensor != null and school_dialogue != null and player != null, "Math Teacher, ACT sensor, dialogue host, and live player are present in School")
	if teacher == null or teacher_sensor == null or school_dialogue == null or player == null:
		return
	var teacher_approach := await _walk_player_to_collision_safe_point(player, teacher_sensor.global_position + Vector2(-8, 8))
	_expect(teacher_approach, "Player walks from the School arrival spawn along collision-checked movement waypoints without position injection")
	if not teacher_approach:
		return
	await _wait_for_physics_frames(4)
	_expect(teacher_sensor.overlaps_body(player) and bool(teacher.call("can_interact")), "The live Teacher interaction is available from a valid nearby position")
	var teacher_interaction_started := bool(teacher.call("interact"))
	await _wait_for_physics_frames(2)
	_expect(teacher_interaction_started and bool(school_dialogue.call("is_dialogue_active")), "The live Math Teacher interaction starts the canonical dialogue")
	for _line in range(24):
		if not bool(school_dialogue.call("is_dialogue_active")):
			break
		await _tap_interact()
	await _wait_for_physics_frames(8)
	_expect(not bool(school_dialogue.call("is_dialogue_active")) and state.current_task_index == GameState.CITY_NEXT_PATH_TASK_INDEX, "Finishing the actual Teacher dialogue activates the Deepest Forest route task")
	var city_return_door: Door = null
	for candidate in school.find_children("*", "Door", true, false):
		var candidate_door := candidate as Door
		if candidate_door != null and candidate_door.destination_scene_path == CITY_PATH:
			city_return_door = candidate_door
			break
	player = _get_live_player()
	_expect(city_return_door != null and player != null, "The canonical School return door and live player are present")
	if city_return_door == null or player == null:
		return
	city_return_door.play_fade_transition = false
	var exited_school := await _walk_player_into_door(city_return_door, player)
	_expect(exited_school, "Player walks through the real School exit door using gameplay movement and door physics")
	await _wait_for_scene(CITY_PATH)
	city = get_tree().current_scene as Node2D
	player = _get_live_player()
	_expect(city != null and state.current_task_index == GameState.DEEP_FOREST_BANDIT_TASK_INDEX, "Returning from School activates the Forest objective through canonical City scene entry")
	for actor_name in ["Bandits", "Bandits2", "Bandits3", "Bandits4", "Bandits5"]:
		var city_actor := city.get_node_or_null(actor_name) as Node2D if city != null else null
		_expect(city_actor != null and not city_actor.is_visible_in_tree(), "Deepest Forest actor %s remains hidden in the normal City hub" % actor_name)
	await _wait_for_physics_frames(3)
	for actor_name in ["Bandits", "Bandits2", "Bandits3", "Bandits4", "Bandits5"]:
		var city_actor := city.get_node_or_null(actor_name) as Node2D if city != null else null
		var npc_body := city_actor.get_node_or_null("NpcBodyCollision") as StaticBody2D if city_actor != null else null
		_expect(npc_body == null or (npc_body.collision_layer == 0 and npc_body.collision_mask == 0), "Hidden City actor %s has no active gameplay collision" % actor_name)
	await RenderingServer.frame_post_draw
	var city_image := get_viewport().get_texture().get_image()
	var city_capture_path := "user://qa_test_artifacts/city_after_school_exit_%s.png" % qa_run_id
	var city_capture_absolute := ProjectSettings.globalize_path(city_capture_path)
	DirAccess.make_dir_recursive_absolute(city_capture_absolute.get_base_dir())
	if city_image != null and not city_image.is_empty():
		city_image.save_png(city_capture_absolute)
	print("CITY_AFTER_SCHOOL_EXIT_CAPTURE %s player=%s" % [city_capture_path, str(player.global_position) if player != null else "missing"])
	var city_exit: Door = null
	for candidate in city.find_children("*", "Door", true, false):
		var candidate_door := candidate as Door
		if candidate_door != null and candidate_door.destination_scene_path == FOREST_PATH:
			city_exit = candidate_door
			break
	player = _get_live_player()
	_expect(city_exit != null, "The canonical City exit node is present in the live City scene")
	_expect(player != null, "A live player body exists in the City scene")
	if city_exit == null or player == null:
		print("CITY_RUNTIME_DIAGNOSTIC exit_found=%s player_found=%s" % [str(city_exit != null), str(player != null)])
		return
	city_exit.play_fade_transition = false
	var walked_into_forest_route := await _walk_player_into_door(city_exit, player)
	_expect(walked_into_forest_route, "Player walks through the canonical City Forest entrance using gameplay movement and door physics")
	if not walked_into_forest_route:
		return
	await _wait_for_scene(FOREST_PATH)
	var forest := get_tree().current_scene as Node2D
	_expect(forest != null and forest.scene_file_path == FOREST_PATH, "Using the City exit enters res://scenes/deepest_forest_path.tscn")
	if forest == null or forest.scene_file_path != FOREST_PATH:
		return
	await _wait_for_physics_frames(8)
	await RenderingServer.frame_post_draw
	var forest_image := get_viewport().get_texture().get_image()
	var forest_capture_path := "user://qa_test_artifacts/deepest_forest_first_entry_%s.png" % qa_run_id
	var forest_capture_absolute := ProjectSettings.globalize_path(forest_capture_path)
	DirAccess.make_dir_recursive_absolute(forest_capture_absolute.get_base_dir())
	_expect(forest_image != null and not forest_image.is_empty() and forest_image.save_png(forest_capture_absolute) == OK, "First-entry Forest viewport capture is saved for visual inspection")
	print("DEEPEST_FOREST_FIRST_ENTRY_CAPTURE %s" % forest_capture_path)
	_expect(state.current_task_index == GameState.DEEP_FOREST_BANDIT_TASK_INDEX, "The completed Math Teacher quest activates the bandit objective on first Forest entry without a reload")
	_expect(String(state.current_quest) == "Defeat the Bandits in the Deepest Forest.", "The first Forest entry retains the canonical active bandit objective")
	player = _get_live_player()
	_expect(player != null, "Forest scene creates its current live player")
	if player == null:
		return
	var forest_spawn := forest.get_node_or_null("spawn_from_city") as Marker2D
	var first_bandit := forest.get_node_or_null("ForestBackdrop/Bandits") as Node2D
	_expect(forest_spawn != null and player.global_position.is_equal_approx(forest_spawn.global_position), "First Forest entry places the player at its dedicated City arrival marker")
	_expect(player.global_position.x >= 220.0 and player.global_position.y > 0.0 and player.global_position.y < 640.0, "Forest entry is inside the playable map rather than at the extreme left edge")
	_expect(first_bandit != null and player.global_position.distance_to(first_bandit.global_position) >= 80.0, "Forest entry gives the player safe space before Bandit 1")
	_expect(forest.get_node_or_null("DeepestForestToCity") is Door and player.global_position.distance_to((forest.get_node("DeepestForestToCity") as Door).global_position) >= 80.0, "Forest entry is away from the City-return door")
	_expect(not _blocking_body_overlaps(player, player.global_position), "Forest arrival position does not overlap a wall, tree, or actor collision")
	var visible_forest_bandits := 0
	for index in 5:
		var actor_name := "Bandits" if index == 0 else "Bandits%d" % (index + 1)
		var forest_actor := forest.get_node_or_null("ForestBackdrop/" + actor_name) as Node2D
		var encounter_component := forest_actor.get_node_or_null("ProgressionBattleEncounter") if forest_actor != null else null
		var visible_bandit_art := false
		if forest_actor != null:
			for visual in forest_actor.find_children("*", "AnimatedSprite2D", true, false):
				if (visual as AnimatedSprite2D).is_visible_in_tree():
					visible_bandit_art = true
		if visible_bandit_art:
			visible_forest_bandits += 1
		_expect(forest_actor != null and forest_actor.is_visible_in_tree() and visible_bandit_art, "Forest actor %s is visibly rendered on first entry" % actor_name)
		_expect(encounter_component != null, "Forest actor %s has its progression encounter enabled on first entry" % actor_name)
	_expect(visible_forest_bandits == 5, "All five undefeated Forest Bandits are visibly present on first entry")
	if first_bandit != null:
		var approach_start_distance := player.global_position.distance_to(first_bandit.global_position)
		await _walk_toward_actor(player, first_bandit, 24)
		_expect(get_tree().current_scene == forest and player.global_position.distance_to(first_bandit.global_position) < approach_start_distance - 8.0, "Player can intentionally walk toward Bandit 1 without a reload or forced encounter")
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
			_expect(forest_city_exit != null and forest_city_exit.destination_scene_path == CITY_PATH and forest_city_exit.destination_spawn_marker_name == "spawn_from_deepest_forest", "Deepest Forest returns through the canonical dedicated City marker")
			if forest_city_exit != null and player != null:
				forest_city_exit.play_fade_transition = false
				player.global_position = forest_city_exit.global_position
				forest_city_exit.call("_begin_transition", player)
				await _wait_for_scene(CITY_PATH)
				var returned_city := get_tree().current_scene as Node2D
				var city_return_marker := returned_city.find_child("spawn_from_deepest_forest", true, false) as Node2D if returned_city != null else null
				var city_forest_entrance: Door = null
				if returned_city != null:
					for candidate in returned_city.find_children("*", "Door", true, false):
						var candidate_door := candidate as Door
						if candidate_door != null and candidate_door.destination_scene_path == FOREST_PATH:
							city_forest_entrance = candidate_door
							break
				player = _get_live_player()
				var entrance_shape := city_forest_entrance.find_child("CollisionShape2D", true, false) as CollisionShape2D if city_forest_entrance != null else null
				_expect(returned_city != null and returned_city.scene_file_path == CITY_PATH, "Deepest Forest return enters City without an unintended reload")
				_expect(city_return_marker != null and player != null and player.global_position.is_equal_approx(city_return_marker.global_position), "Forest return spawns at the dedicated lower City entrance marker, not the upper-map fallback")
				_expect(city_forest_entrance != null and player != null and not city_forest_entrance.overlaps_body(player), "City return marker does not overlap the Forest entrance and cannot immediately retrigger it")
				await _wait_for_physics_frames(12)
				_expect(get_tree().current_scene == returned_city and city_forest_entrance != null and not city_forest_entrance.is_transitioning, "Player remains in City after settling at the dedicated Forest return spawn")


func _complete_canonical_progression_to_city(state: Node) -> bool:
	if not bool(state.call("complete_tutorial_activity")):
		return false
	var teacher_house_arrival: Dictionary = state.call("advance_task_and_save", {
		"type": "task_trigger",
		"key": "qa:canonical:teacher-house-arrival",
	})
	if not bool(teacher_house_arrival.get("advanced", false)):
		return false
	var teacher_task: Dictionary = state.call("advance_task_and_save", {
		"type": "quest_completed",
		"key": "qa:canonical:teacher-task-complete",
	})
	if not bool(teacher_task.get("advanced", false)):
		return false
	var first_bandit: Dictionary = state.call("record_oakleaf_encounter_victory", "oakleaf_bandits1")
	if not bool(first_bandit.get("changed", false)):
		return false
	var first_battle_task: Dictionary = state.call("advance_task_and_save", {
		"type": "task_completed",
		"key": "qa:canonical:first-bandit-complete",
	})
	if not bool(first_battle_task.get("advanced", false)):
		return false
	for encounter_id in ["oakleaf_bandits2", "oakleaf_bandits3", "oakleaf_bandits4", "oakleaf_bandits5"]:
		var victory: Dictionary = state.call("record_oakleaf_encounter_victory", String(encounter_id))
		if not bool(victory.get("changed", false)):
			return false
	var boss: Dictionary = state.call("record_oakleaf_encounter_victory", "oakleaf_boss_bandit")
	if not bool(boss.get("changed", false)):
		return false
	var teacher_return: Dictionary = state.call("complete_oakleaf_teacher_return")
	return bool(teacher_return.get("changed", false)) \
			and bool(state.get("city_of_knowledge_unlocked")) \
			and int(state.get("current_task_index")) == GameState.CITY_OF_KNOWLEDGE_TASK_INDEX


func _wait_for_scene(scene_path: String) -> void:
	for _attempt in range(200):
		await get_tree().process_frame
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == scene_path:
			await get_tree().process_frame
			await get_tree().process_frame
			return
	await get_tree().create_timer(0.1).timeout


func _wait_for_physics_frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().physics_frame


func _walk_player_into_door(door: Door, player: Node2D) -> bool:
	var source_scene := get_tree().current_scene
	var destination_scene_path := door.destination_scene_path
	var activation_point := _door_activation_point(door)
	var route := _collision_safe_grid_path(player, activation_point, door)
	if route.is_empty():
		print("CITY_FOREST_WALK_DIAGNOSTIC path=unavailable start=%s target=%s" % [str(player.global_position), str(activation_point)])
		return false
	var route_bounds := Rect2(route[0], Vector2.ZERO)
	for destination in route:
		route_bounds = route_bounds.expand(destination)
	print("CITY_FOREST_WALK_DIAGNOSTIC route_bounds=%s" % str(route_bounds))
	print("CITY_FOREST_WALK_DIAGNOSTIC path_cells=%d start=%s target=%s" % [route.size(), str(player.global_position), str(activation_point)])
	for destination in route:
		if get_tree().current_scene != source_scene or door.is_transitioning:
			InputManager.clear_mobile_state()
			return _door_destination_reached(destination_scene_path)
		if not await _walk_player_to_point(player, destination):
			print("CITY_FOREST_WALK_DIAGNOSTIC stuck_at=%s waypoint=%s locked=%s" % [str(player.global_position), str(destination), str(InputManager.is_input_locked())])
			InputManager.clear_mobile_state()
			return false
	if get_tree().current_scene != source_scene or door.is_transitioning:
		InputManager.clear_mobile_state()
		return _door_destination_reached(destination_scene_path)
	# The final grid cell can be just outside the Area2D. Walk the remaining
	# distance through normal CharacterBody2D movement so body_entered owns entry.
	if not await _walk_player_to_point(player, activation_point, 80):
		InputManager.clear_mobile_state()
		return false
	InputManager.clear_mobile_state()
	return _door_destination_reached(destination_scene_path)


func _door_activation_point(door: Door) -> Vector2:
	for collision_variant in door.find_children("*", "CollisionShape2D", true, false):
		var collision := collision_variant as CollisionShape2D
		if collision != null and not collision.disabled and collision.shape != null:
			return collision.global_position
	return door.global_position


func _door_destination_reached(destination_scene_path: String) -> bool:
	var current := get_tree().current_scene
	return current != null and current.scene_file_path == destination_scene_path


func _walk_player_to_collision_safe_point(player: Node2D, target: Vector2) -> bool:
	var route := _collision_safe_grid_path(player, target, null)
	if route.is_empty():
		print("CITY_FOREST_WALK_DIAGNOSTIC interaction_path_unavailable start=%s target=%s" % [str(player.global_position), str(target)])
		return false
	var source_scene := get_tree().current_scene
	for destination in route:
		if get_tree().current_scene != source_scene:
			InputManager.clear_mobile_state()
			return false
		if not await _walk_player_to_point(player, destination):
			print("CITY_FOREST_WALK_DIAGNOSTIC approach_waypoint_stuck at=%s waypoint=%s target=%s" % [str(player.global_position), str(destination), str(target)])
			InputManager.clear_mobile_state()
			return false
	# The grid goal is the nearest collision-free cell around the target; the
	# requested point itself may be inside the Teacher's body/desk while the
	# neighboring cell is still inside the real interaction Area2D.
	await get_tree().physics_frame
	InputManager.clear_mobile_state()
	var reached_approach := get_tree().current_scene == source_scene and player.global_position.distance_to(target) <= 18.0
	if not reached_approach:
		print("CITY_FOREST_WALK_DIAGNOSTIC approach_not_reached at=%s target=%s distance=%.1f" % [str(player.global_position), str(target), player.global_position.distance_to(target)])
	return reached_approach


func _collision_safe_grid_path(player: Node2D, target: Vector2, target_door: Door = null) -> Array[Vector2]:
	var grid := AStarGrid2D.new()
	const GRID_CELL_SIZE := 8.0
	grid.region = Rect2i(-40, -40, 200, 135)
	grid.cell_size = Vector2(GRID_CELL_SIZE, GRID_CELL_SIZE)
	grid.offset = Vector2(GRID_CELL_SIZE / 2.0, GRID_CELL_SIZE / 2.0)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	var safe_shape := RectangleShape2D.new()
	# Match the instantiated player's scaled foot collider (8×2 world units).
	safe_shape.size = Vector2(8, 2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = safe_shape
	query.collision_mask = int(player.get("collision_mask"))
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]
	var space := get_viewport().world_2d.direct_space_state
	var door_query := PhysicsShapeQueryParameters2D.new()
	door_query.shape = safe_shape
	door_query.collision_mask = int(player.get("collision_mask"))
	door_query.collide_with_areas = true
	door_query.collide_with_bodies = false
	var blocked_cell_count := 0
	for x in range(grid.region.position.x, grid.region.end.x):
		for y in range(grid.region.position.y, grid.region.end.y):
			var cell := Vector2i(x, y)
			var center := Vector2((x + 0.5) * GRID_CELL_SIZE - 1.0, (y + 0.5) * GRID_CELL_SIZE + 1.0)
			query.transform = Transform2D(0.0, center)
			if not space.intersect_shape(query, 64).is_empty():
				grid.set_point_solid(cell)
				blocked_cell_count += 1
				continue
			door_query.transform = query.transform
			var area_hits := space.intersect_shape(door_query, 64)
			for hit in area_hits:
				var collider: Object = hit.get("collider")
				if collider is Door:
					if collider != target_door:
						grid.set_point_solid(cell)
						blocked_cell_count += 1
						break
	var start := Vector2i(floori(player.global_position.x / GRID_CELL_SIZE), floori(player.global_position.y / GRID_CELL_SIZE))
	var goal := Vector2i(floori(target.x / GRID_CELL_SIZE), floori(target.y / GRID_CELL_SIZE))
	if not grid.region.has_point(start) or not grid.region.has_point(goal):
		print("CITY_FOREST_WALK_DIAGNOSTIC outside_region start=%s goal=%s blocked=%d" % [str(start), str(goal), blocked_cell_count])
		return []
	# The player's actual spawn can sit on a cell boundary. Preserve the actual
	# starting cell, while all subsequent cells remain collision-checked.
	grid.set_point_solid(start, false)
	var candidate_goals: Array[Vector2i] = []
	if not grid.is_point_solid(goal):
		candidate_goals.append(goal)
	# Door/interactable origins can sit just across a collision boundary while an
	# adjacent cell still overlaps their Area2D. Try nearby free cells in nearest
	# first order, but require each candidate to be reachable from the live body.
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var candidate := goal + Vector2i(dx, dy)
			if candidate == goal or not grid.region.has_point(candidate) or grid.is_point_solid(candidate):
				continue
			candidate_goals.append(candidate)
	candidate_goals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return grid.get_point_position(a).distance_squared_to(target) < grid.get_point_position(b).distance_squared_to(target)
	)
	var ids: Array[Vector2i] = []
	var requested_goal := goal
	for candidate_goal in candidate_goals:
		ids = _breadth_first_grid_path(grid, start, candidate_goal, player)
		if not ids.is_empty():
			goal = candidate_goal
			break
	if ids.is_empty():
		print("CITY_FOREST_WALK_DIAGNOSTIC no_grid_path start=%s goal=%s start_solid=%s goal_solid=%s blocked=%d" % [str(start), str(requested_goal), str(grid.is_point_solid(start)), str(grid.is_point_solid(requested_goal)), blocked_cell_count])
		var map_image := Image.create(grid.region.size.x * 8, grid.region.size.y * 8, false, Image.FORMAT_RGBA8)
		map_image.fill(Color(0.16, 0.65, 0.22, 1.0))
		for image_x in range(grid.region.size.x):
			for image_y in range(grid.region.size.y):
				var cell := grid.region.position + Vector2i(image_x, image_y)
				var color := Color(0.12, 0.12, 0.16, 1.0) if grid.is_point_solid(cell) else Color(0.16, 0.65, 0.22, 1.0)
				for pixel_x in range(image_x * 8, image_x * 8 + 8):
					for pixel_y in range(image_y * 8, image_y * 8 + 8):
						map_image.set_pixel(pixel_x, pixel_y, color)
		for marker in [{"cell": start, "color": Color(0.1, 0.4, 1.0, 1.0)}, {"cell": goal, "color": Color(1.0, 0.8, 0.1, 1.0)}]:
			var marker_cell: Vector2i = marker.get("cell") - grid.region.position
			for pixel_x in range(marker_cell.x * 8, marker_cell.x * 8 + 8):
				for pixel_y in range(marker_cell.y * 8, marker_cell.y * 8 + 8):
					map_image.set_pixel(pixel_x, pixel_y, marker.get("color"))
		var map_path := "user://qa_test_artifacts/city_collision_grid_%s.png" % qa_run_id
		map_image.save_png(ProjectSettings.globalize_path(map_path))
		print("CITY_COLLISION_GRID_CAPTURE %s" % map_path)
	var result: Array[Vector2] = []
	for cell in ids:
		result.append(grid.get_point_position(cell))
	return result


func _breadth_first_grid_path(grid: AStarGrid2D, start: Vector2i, goal: Vector2i, player: Node2D) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	var queue_index := 0
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	while queue_index < queue.size():
		var current := queue[queue_index]
		queue_index += 1
		if current == goal:
			break
		for direction in directions:
			var next: Vector2i = current + direction
			if not grid.region.has_point(next) or grid.is_point_solid(next) or previous.has(next):
				continue
			var current_position := grid.get_point_position(current)
			var next_position := grid.get_point_position(next)
			var motion_parameters := PhysicsTestMotionParameters2D.new()
			motion_parameters.from = player.global_transform
			motion_parameters.from.origin = current_position
			motion_parameters.motion = next_position - current_position
			motion_parameters.margin = (player as CharacterBody2D).safe_margin if player is CharacterBody2D else 0.08
			var motion_result := PhysicsTestMotionResult2D.new()
			if PhysicsServer2D.body_test_motion(player.get_rid(), motion_parameters, motion_result):
					continue
			previous[next] = current
			queue.append(next)
	if not previous.has(goal):
		print("CITY_FOREST_WALK_DIAGNOSTIC bfs_unreachable visited=%d start=%s goal=%s" % [previous.size(), str(start), str(goal)])
		var reachable_min := start
		var reachable_max := start
		for reachable_variant in previous.keys():
			var reachable_cell: Vector2i = reachable_variant
			reachable_min.x = mini(reachable_min.x, reachable_cell.x)
			reachable_min.y = mini(reachable_min.y, reachable_cell.y)
			reachable_max.x = maxi(reachable_max.x, reachable_cell.x)
			reachable_max.y = maxi(reachable_max.y, reachable_cell.y)
		print("CITY_FOREST_WALK_DIAGNOSTIC reachable_cell_bounds=%s..%s" % [str(reachable_min), str(reachable_max)])
		var reachable_image := Image.create(grid.region.size.x * 8, grid.region.size.y * 8, false, Image.FORMAT_RGBA8)
		for image_x in range(grid.region.size.x):
			for image_y in range(grid.region.size.y):
				var cell := grid.region.position + Vector2i(image_x, image_y)
				var color := Color(0.12, 0.12, 0.16, 1.0) if grid.is_point_solid(cell) else (Color(0.08, 0.28, 0.95, 1.0) if previous.has(cell) else Color(0.16, 0.65, 0.22, 1.0))
				for pixel_x in range(image_x * 8, image_x * 8 + 8):
					for pixel_y in range(image_y * 8, image_y * 8 + 8):
						reachable_image.set_pixel(pixel_x, pixel_y, color)
		for marker in [{"cell": start, "color": Color(0.1, 0.4, 1.0, 1.0)}, {"cell": goal, "color": Color(1.0, 0.8, 0.1, 1.0)}]:
			var marker_cell: Vector2i = marker.get("cell") - grid.region.position
			for pixel_x in range(marker_cell.x * 8, marker_cell.x * 8 + 8):
				for pixel_y in range(marker_cell.y * 8, marker_cell.y * 8 + 8):
					reachable_image.set_pixel(pixel_x, pixel_y, marker.get("color"))
		var reachable_path := "user://qa_test_artifacts/city_reachable_region_%s.png" % qa_run_id
		reachable_image.save_png(ProjectSettings.globalize_path(reachable_path))
		print("CITY_REACHABLE_REGION_CAPTURE %s" % reachable_path)
		return []
	var result: Array[Vector2i] = []
	var cursor := goal
	while cursor != start:
		result.push_front(cursor)
		cursor = previous[cursor]
	result.push_front(start)
	return result


func _walk_player_to_point(player: Node2D, target: Vector2, max_frames: int = 50) -> bool:
	var source_scene := get_tree().current_scene
	for _frame in range(max_frames):
		if player == null or not is_instance_valid(player):
			return false
		var direction := player.global_position.direction_to(target)
		if player.global_position.distance_to(target) <= 2.5:
			InputManager.clear_mobile_state()
			return true
		_set_qa_movement(direction)
		await get_tree().physics_frame
		if get_tree().current_scene != source_scene:
			InputManager.clear_mobile_state()
			return true
	InputManager.clear_mobile_state()
	var reached := player.global_position.distance_to(target) <= 2.5
	if not reached:
		var collision_detail := "none"
		var body := player as CharacterBody2D
		if body != null and body.get_slide_collision_count() > 0:
			var hit := body.get_slide_collision(0)
			var collider := hit.get_collider() as Node
			collision_detail = "%s@%s" % [collider.name if collider != null else "unknown", str(hit.get_position())]
		print("CITY_FOREST_WALK_DIAGNOSTIC waypoint_timeout at=%s target=%s distance=%.1f collision=%s" % [str(player.global_position), str(target), player.global_position.distance_to(target), collision_detail])
	return reached


func _walk_toward_actor(player: Node2D, actor: Node2D, frames: int) -> void:
	_set_qa_movement(player.global_position.direction_to(actor.global_position))
	await _wait_for_physics_frames(frames)
	InputManager.clear_mobile_state()
	await _wait_for_physics_frames(2)


func _set_qa_movement(direction: Vector2) -> void:
	InputManager.set_mobile_direction(&"left", direction.x < -0.1)
	InputManager.set_mobile_direction(&"right", direction.x > 0.1)
	InputManager.set_mobile_direction(&"up", direction.y < -0.1)
	InputManager.set_mobile_direction(&"down", direction.y > 0.1)


func _blocking_body_overlaps(player: Node2D, body_position: Vector2) -> bool:
	var collision := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.collision_mask = int(player.get("collision_mask"))
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]
	var body_transform := player.global_transform
	body_transform.origin = body_position
	query.transform = body_transform * collision.transform
	return not get_viewport().world_2d.direct_space_state.intersect_shape(query, 1).is_empty()


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
	var city_scene := (load(CITY_PATH) as PackedScene).instantiate() as Node2D
	var city_return_marker := city_scene.get_node_or_null("spawn_from_deepest_forest") as Marker2D if city_scene != null else null
	_expect(city_return_marker != null and city_return_marker.position.is_equal_approx(Vector2(128, 508)), "City has its dedicated safe return marker from Deepest Forest")
	if city_scene != null:
		city_scene.free()
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
	_expect(_complete_canonical_progression_to_city(state), "Serializer fixture reaches the City through valid Oakleaf progression")
	state.mark_city_first_arrival()
	state.complete_city_school_teacher()
	state.handle_scene_entered(CITY_PATH)
	_expect(state.current_task_index == state.DEEP_FOREST_BANDIT_TASK_INDEX, "Serializer fixture reaches the Forest stage through the canonical School return boundary")
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
