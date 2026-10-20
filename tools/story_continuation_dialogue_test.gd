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
	_expect(String(state.tasks[state.WIZARD_TASK_INDEX].quest_text) == "Talk to the Wizard", "Four guards completion points to the Wizard interaction")
	_expect(String(state.tasks[state.RETURN_CITY_TASK_INDEX].quest_text) == "Return to the City of Knowledge.", "Wizard completion points back to City")
	_expect(String(state.tasks[state.FINAL_SCHOOL_TASK_INDEX].quest_text) == "Return to the School.", "City return points to School")
	_expect(String(state.tasks[state.FINAL_TEACHER_TASK_INDEX].quest_text) == "Face the Teacher's Final Challenge.", "School return points to final Teacher")

	_expect(OLD_LADY.DIALOGUE_LINES.size() == 4, "Old Lady uses the four-line conversation")
	_expect(OLD_LADY.WIZARD_THANKS_LINES == ["Old Lady: Thank you for defeating the Wizard.", "Old Lady: Good luck on the rest of your journey."], "Post-Wizard Old Lady thanks uses the two approved lines")
	_expect(OLD_LADY.WIZARD_THANKS_TRIGGER_RANGE > OLD_LADY.INTERACTION_RANGE and OLD_LADY.WIZARD_THANKS_STOP_DISTANCE <= OLD_LADY.INTERACTION_RANGE, "Post-Wizard event starts on approach and stops at normal conversation distance")
	_expect(String(FileAccess.get_file_as_string("res://scripts/progression_old_man_interaction.gd")).contains("body.move_and_slide()"), "Old Lady approaches by collision-aware movement instead of teleporting")
	_expect(ROUTER.WIZARD_INTRO_DIALOGUE.size() == 3, "Wizard intro uses the short three-line conversation")
	_expect(ROUTER.WIZARD_REVELATION_DIALOGUE.size() == 5, "Wizard revelation uses the five-line conversation")
	_expect(ROUTER.DEEP_FOREST_COMPLETE_DIALOGUE.size() == 1, "Deep Forest completion has a short notification")
	_expect(ROUTER.PINEHILL_GUARDS_COMPLETE_DIALOGUE.size() == 1, "Pinehill guard completion has a short notification")
	_expect(String(state.tasks[state.CITY_SCHOOL_TASK_INDEX].dialogue[0]) == "Teacher: You made it to the City of Knowledge.", "City Teacher opening line is canonical")
	_expect(String(state.tasks[state.FINAL_TEACHER_TASK_INDEX].dialogue[0]) == "Teacher: You finally discovered the truth.", "Final Teacher opening line is canonical")

	state.city_of_knowledge_unlocked = true
	state.city_school_stage_complete = true
	state.city_next_path_unlocked = true
	state.current_task_index = state.CITY_NEXT_PATH_TASK_INDEX
	state.handle_scene_entered("res://scenes/city_of_knowledge.tscn")
	_expect(state.current_task_index == state.DEEP_FOREST_BANDIT_TASK_INDEX, "City return activates the Deepest Forest objective after School completion")
	for encounter_id in state.DEEP_FOREST_BANDIT_IDS:
		state.record_progression_encounter_victory(encounter_id, false)
	_expect(state.pinehill_unlocked and state.current_task_index == state.PINEHILL_ARRIVAL_TASK_INDEX, "Five Deep Forest encounters unlock Pinehill")
	state.handle_scene_entered("res://scenes/pinehill_village.tscn")
	_expect(state.current_task_index == state.PINEHILL_OLD_MAN_TASK_INDEX, "Pinehill arrival opens the Old Lady stage")
	state.complete_pinehill_old_lady()
	_expect(state.current_task_index == state.PINEHILL_BANDIT_TASK_INDEX, "Old Lady gates the four guards")
	for encounter_id in state.PINEHILL_BANDIT_IDS:
		state.record_progression_encounter_victory(encounter_id, false)
	_expect(state.current_task_index == state.WIZARD_TASK_INDEX, "Four guards unlock the outdoor Wizard challenge")
	state.record_progression_encounter_victory("pinehill_wizard", false)
	_expect(state.current_task_index == state.RETURN_CITY_TASK_INDEX, "Wizard victory unlocks the City return")
	var quests_completed_before_thanks := int(state.total_quests_completed)
	state.call("complete_wizard_thanks_event")
	_expect(bool(state.get("wizard_thanks_complete")), "Post-Wizard Old Lady beat persists its one-time completion flag")
	_expect(int(state.total_quests_completed) == quests_completed_before_thanks, "Post-Wizard thank-you is story state, not a fabricated academic quest completion")
	var thanks_snapshot: Dictionary = state.call("build_save_data")
	state.set("wizard_thanks_complete", false)
	state.call("apply_save_data", thanks_snapshot, false)
	_expect(bool(state.get("wizard_thanks_complete")), "Post-Wizard one-time flag survives save/load and defaults compatibly")
	var legacy_snapshot: Dictionary = state.call("build_save_data")
	legacy_snapshot["scene_path"] = "res://scenes/pinehill_village.tscn"
	state.call("apply_save_data", legacy_snapshot, false)
	_expect(state.current_scene_path == "res://scenes/2nd Village/Pinehill Village.tscn" and not ResourceLoader.exists("res://scenes/pinehill_village.tscn"), "An old Pinehill save opens the canonical scene without the retired wrapper")
	state.handle_scene_entered("res://scenes/city_of_knowledge.tscn")
	_expect(state.current_task_index == state.FINAL_SCHOOL_TASK_INDEX, "City return opens the School stage")
	state.handle_scene_entered("res://interiors/school.tscn")
	_expect(state.current_task_index == state.FINAL_TEACHER_TASK_INDEX, "School opens the final Teacher stage")
	state.record_progression_encounter_victory("final_teacher", false)
	_expect(state.journey_complete and state.get_current_quest_text() == "Math Champion", "Final victory is monotonic and ends at Math Champion")
	await _verify_cutscene_dialogue_input()
	await _verify_interrupted_thanks_releases_control()
	await _verify_old_lady_road_approach()
	_verify_pinehill_lamp_depth()

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


func _verify_cutscene_dialogue_input() -> void:
	var original_mode: int = GameState.get_mode()
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	GameState.push_mode(GameState.GameMode.CUTSCENE)
	var controls := load("res://ui/mobile_controls.tscn").instantiate() as CanvasLayer
	add_child(controls)
	controls.call("configure", true)
	var overlay := load("res://ui/progression_dialogue_overlay.tscn").instantiate() as CanvasLayer
	add_child(overlay)
	var panel := overlay.get_node("DialoguePanel") as Control
	var label := overlay.get_node("DialoguePanel/DialogueContent/DialogueLabel") as Label
	var closed := [0]
	overlay.dialogue_closed.connect(func() -> void: closed[0] += 1)
	overlay.show_lines(OLD_LADY.WIZARD_THANKS_LINES)
	await get_tree().process_frame
	_expect(not controls.get_node("Root/ActionMargin/ActionPanel/ActionButton").is_visible_in_tree(), "CUTSCENE hides normal mobile ACT during the automatic Old Lady dialogue")
	_expect(label.text == OLD_LADY.WIZARD_THANKS_LINES[0], "Automatic thank-you begins with the first approved line")
	_tap_dialogue_panel(panel)
	await get_tree().process_frame
	_expect(label.text == OLD_LADY.WIZARD_THANKS_LINES[1] and closed[0] == 0, "One mobile panel tap advances exactly one thank-you line without ACT")
	_tap_dialogue_panel(panel)
	await get_tree().process_frame
	_expect(not panel.visible and closed[0] == 1, "A second mobile panel tap closes the automatic dialogue once")
	overlay.queue_free()
	await get_tree().process_frame
	var keyboard_overlay := load("res://ui/progression_dialogue_overlay.tscn").instantiate() as CanvasLayer
	add_child(keyboard_overlay)
	keyboard_overlay.show_lines(OLD_LADY.WIZARD_THANKS_LINES)
	await get_tree().process_frame
	Input.action_press("interact")
	await get_tree().process_frame
	_expect(keyboard_overlay.get_node("DialoguePanel/DialogueContent/DialogueLabel").text == OLD_LADY.WIZARD_THANKS_LINES[1], "Keyboard interact advances the automatic dialogue")
	Input.action_release("interact")
	await get_tree().process_frame
	Input.action_press("interact")
	await get_tree().process_frame
	_expect(not keyboard_overlay.get_node("DialoguePanel").visible, "Keyboard interact closes the automatic dialogue")
	Input.action_release("interact")
	keyboard_overlay.queue_free()
	await get_tree().process_frame
	var controller_overlay := load("res://ui/progression_dialogue_overlay.tscn").instantiate() as CanvasLayer
	add_child(controller_overlay)
	controller_overlay.show_lines(OLD_LADY.WIZARD_THANKS_LINES)
	await get_tree().process_frame
	Input.action_press("ui_accept")
	await get_tree().process_frame
	_expect(controller_overlay.get_node("DialoguePanel/DialogueContent/DialogueLabel").text == OLD_LADY.WIZARD_THANKS_LINES[1], "Controller accept advances the automatic dialogue")
	Input.action_release("ui_accept")
	await get_tree().process_frame
	Input.action_press("ui_accept")
	await get_tree().process_frame
	_expect(not controller_overlay.get_node("DialoguePanel").visible, "Controller accept closes the automatic dialogue")
	Input.action_release("ui_accept")
	controller_overlay.queue_free()
	controls.queue_free()
	await get_tree().process_frame
	GameState.set_mode(original_mode)


func _tap_dialogue_panel(panel: Control) -> void:
	var press := InputEventScreenTouch.new()
	press.pressed = true
	panel.gui_input.emit(press)
	var release := InputEventScreenTouch.new()
	release.pressed = false
	panel.gui_input.emit(release)


func _verify_interrupted_thanks_releases_control() -> void:
	var original_mode: int = GameState.get_mode()
	var original_thanks: bool = bool(GameState.wizard_thanks_complete)
	GameState.wizard_thanks_complete = false
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	var actor := Node2D.new()
	actor.name = "InterruptedOldLady"
	add_child(actor)
	var component := OLD_LADY.new() as Node
	component.call("configure", actor)
	actor.add_child(component)
	component.set("_active", true)
	GameState.push_mode(GameState.GameMode.CUTSCENE)
	component.call("_show_wizard_thanks_dialogue")
	await get_tree().process_frame
	var overlay := get_node_or_null("ProgressionDialogueOverlay") as CanvasLayer
	_expect(overlay != null, "The post-Wizard event creates its progression dialogue overlay")
	if overlay != null:
		overlay.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(GameState.get_mode() == GameState.GameMode.EXPLORATION, "Unexpected thank-you overlay closure releases CUTSCENE control")
		_expect(not bool(GameState.wizard_thanks_complete), "Interrupted thank-you does not mark its one-time story flag complete")
	actor.queue_free()
	await get_tree().process_frame
	GameState.wizard_thanks_complete = original_thanks
	GameState.set_mode(original_mode)


func _verify_old_lady_road_approach() -> void:
	var packed := load("res://scenes/2nd Village/Pinehill Village.tscn") as PackedScene
	var pinehill := packed.instantiate() as Node2D
	var first := pinehill.get_node_or_null("WizardThanksPath/Waypoint1") as Marker2D
	var meeting := pinehill.get_node_or_null("WizardThanksPath/MeetingPoint") as Marker2D
	var road := pinehill.get_node_or_null("Background/road") as TileMapLayer
	_expect(first != null and meeting != null, "Canonical Pinehill authors the Old Lady's road approach waypoints")
	if first != null and meeting != null and road != null:
		_expect(is_equal_approx(first.position.x, 336.0) and is_equal_approx(meeting.position.y, first.position.y), "Old Lady's route is vertical then horizontal, never diagonal")
		_expect(road.get_cell_source_id(road.local_to_map(first.position)) >= 0 and road.get_cell_source_id(road.local_to_map(meeting.position)) >= 0, "Old Lady's waypoints lie on authored Pinehill road tiles")
	pinehill.free()
	var original := {
		"mode": GameState.get_mode(),
		"wizard_defeated": GameState.wizard_defeated,
		"wizard_thanks_complete": GameState.wizard_thanks_complete,
		"return_to_city_stage": GameState.return_to_city_stage,
		"task": GameState.current_task_index,
		"playtime_authorized": GameState.playtime_authorized,
	}
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	GameState.wizard_defeated = true
	GameState.wizard_thanks_complete = false
	GameState.return_to_city_stage = 2
	GameState.current_task_index = GameState.RETURN_CITY_TASK_INDEX
	GameState.playtime_authorized = true
	var world := Node2D.new()
	add_child(world)
	var path := Node2D.new()
	path.name = "WizardThanksPath"
	world.add_child(path)
	for entry in [{"name": "Waypoint1", "position": Vector2(336, 288)}, {"name": "MeetingPoint", "position": Vector2(384, 288)}]:
		var marker := Marker2D.new()
		marker.name = String(entry.name)
		marker.position = entry.position
		path.add_child(marker)
	var actor := Node2D.new()
	actor.position = Vector2(336, 253)
	world.add_child(actor)
	var player := Node2D.new()
	player.position = Vector2(400, 320)
	world.add_child(player)
	var component := OLD_LADY.new() as Node
	component.call("configure", actor)
	actor.add_child(component)
	component.set_physics_process(false)
	component.call("_begin_wizard_thanks_event", player)
	var cardinal := true
	var stayed_on_road := true
	for _step in range(24):
		if not bool(component.get("_wizard_thanks_approaching")):
			break
		var before := actor.position
		component.call("_advance_wizard_thanks_approach", 0.1)
		var change := actor.position - before
		cardinal = cardinal and (is_zero_approx(change.x) or is_zero_approx(change.y))
		stayed_on_road = stayed_on_road and (is_equal_approx(actor.position.x, 336.0) or is_equal_approx(actor.position.y, 288.0))
	_expect(cardinal, "Old Lady moves along cardinal segments only")
	_expect(stayed_on_road, "Old Lady approach stays on the Pinehill road corridor")
	_expect(actor.position.distance_to(Vector2(384, 288)) <= 5.0, "Old Lady reaches the authored meeting point near the frozen player")
	world.queue_free()
	await get_tree().process_frame
	GameState.wizard_defeated = bool(original.wizard_defeated)
	GameState.wizard_thanks_complete = bool(original.wizard_thanks_complete)
	GameState.return_to_city_stage = int(original.return_to_city_stage)
	GameState.current_task_index = int(original.task)
	GameState.playtime_authorized = bool(original.playtime_authorized)
	GameState.set_mode(int(original.mode))


func _verify_pinehill_lamp_depth() -> void:
	var pinehill := (load("res://scenes/2nd Village/Pinehill Village.tscn") as PackedScene).instantiate() as Node2D
	_expect(pinehill.y_sort_enabled, "Pinehill world shares Y sorting between the player and lamps")
	var authored_positions := [Vector2(216, 192), Vector2(160, 192), Vector2(344, 224), Vector2(216, 16), Vector2(216, 144), Vector2(312, 16), Vector2(312, 64), Vector2(344, 304), Vector2(344, 352), Vector2(264, 176), Vector2(264, 64), Vector2(392, 216), Vector2(391.99997, 352), Vector2(344, 432)]
	for index in range(57, 71):
		var lamp := pinehill.get_node_or_null("Sprite2D%d" % index) as Node2D
		_expect(lamp != null and lamp.z_index == 0 and lamp.position.is_equal_approx(authored_positions[index - 57]), "Pinehill lamp %d keeps its authored position and normal depth" % index)
		if lamp != null:
			var foot := lamp.get_node_or_null("CollisionShape2D") as CollisionShape2D
			_expect(foot != null and foot.shape != null and lamp.scale.is_equal_approx(Vector2(0.45, 0.38953486)), "Pinehill lamp %d keeps its original foot collision and scale" % index)
	pinehill.free()
