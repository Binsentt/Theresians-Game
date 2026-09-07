extends "res://tools/preservation_restoration_test.gd"
## Canonical MCP-only test. Inherits existing tutorial, teacher, controller,
## keyboard, and isolated save fixtures; all map and actor resources stay real.

const NPC_CASES := [
	{"actor": "girl_npc", "target": "Visual"},
	{"actor": "villager-female", "target": "Visual"},
	{"actor": "NPC", "target": "Visual"},
	{"actor": "NPC1", "target": "Visual"},
]
const OUTSIDE_NPC_REGIONS := Vector2(-2000, -2000)
const SCENE_DIRECTORY_FOR_BANDIT := "res://Battle/Battle-Enemy/"
var observations: Array[Dictionary] = []


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		var live_node := get_node_or_null("/root/" + autoload_name)
		if live_node != null:
			live_node.free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	var stub = load("res://tools/first_bandit_interaction_project_context_test.gd").QuestionProviderStub.new()
	stub.name = "QuestionProvider"
	get_tree().root.add_child(stub)
	# Keep this runner alive across the inherited real scene transitions.
	get_tree().current_scene = null
	state.start_new_game(PROFILE, false)
	_roundtrip_wrapped_npc_bindings()
	await _tutorial()
	await _teacher()
	_check_dialogue_placement(get_tree().current_scene, "Teacher")
	for npc_case in NPC_CASES:
		await _npc_proximity(npc_case)
	for selected_gender in ["male", "female"]:
		await _actual_bandit(selected_gender)
	var failed := 0
	for check in checks:
		if not bool(check.passed):
			failed += 1
	var result := {"checks": checks, "observed": observations, "failed": failed, "passed": checks.size() - failed}
	var output := FileAccess.open("res://docs/qa/2026-09-07-original-interaction-tests.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(result, "\t"))
		output.close()
	# Only the new fixture created by this isolated test process is removed.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	print("ORIGINAL_INTERACTION_REGRESSION_TEST " + JSON.stringify({"failed": failed, "passed": checks.size() - failed}))
	get_tree().quit(0 if failed == 0 else 1)


func _npc_proximity(npc_case: Dictionary) -> void:
	state.current_task_index = 2
	var scene := await _load(OAK)
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	var ui := scene.get_node_or_null("CanvasLayer/Panel")
	var actor := scene.get_node_or_null(String(npc_case.actor))
	_expect(player != null and ui != null and actor != null, String(npc_case.actor) + ": real actor, player, and quest host exist")
	if player == null or ui == null or actor == null:
		return
	player.set_physics_process(false)
	# Freeze only fixture motion so physical entry/exit remains deterministic.
	for wanderer in get_tree().get_nodes_in_group("decorative_wanderer"):
		wanderer.set_physics_process(false)
	var target: Node = actor if String(npc_case.target).is_empty() else actor.get_node_or_null(String(npc_case.target))
	var sensor := actor.find_child("Area2D", true, false) as Area2D
	var collider := sensor.get_node_or_null("CollisionShape2D") as CollisionShape2D if sensor != null else null
	var component := actor.find_child("InteractableArea", true, false)
	var structures_present := target != null and sensor != null and collider != null and component != null
	_expect(structures_present, String(npc_case.actor) + ": original physical sensor and interaction component exist")
	if not structures_present:
		return
	var binding_present := target.has_method("can_interact") and target.has_method("interact") and target.has_method("_get_quest_ui")
	_expect(binding_present, String(npc_case.actor) + ": existing greeting script is bound to the actual interaction target")
	if binding_present:
		_expect(target.call("_get_quest_ui") == ui, String(npc_case.actor) + ": greeting resolves the canonical shared quest host")
	var component_available := component.has_method("can_interact")
	var ui_available := ui.has_method("is_dialogue_active") and ui.has_method("get_dialogue_line_index")
	_expect(component_available and ui_available, String(npc_case.actor) + ": component and host expose their original interaction contract")
	if not component_available or not ui_available:
		return
	_check_dialogue_placement(scene, String(npc_case.actor))
	player.global_position = OUTSIDE_NPC_REGIONS
	await _physics_frames(6)
	_expect(not sensor.get_overlapping_bodies().has(player), String(npc_case.actor) + ": initial player position is physically outside")
	player.global_position = collider.global_position
	await _physics_frames(6)
	var entered := sensor.get_overlapping_bodies().has(player)
	var can_enter: bool = bool(component.call("can_interact"))
	_expect(entered, String(npc_case.actor) + ": actual collision overlap enters the original NPC region")
	_expect(can_enter, String(npc_case.actor) + ": actual entry enables greeting")
	_expect(interactions.get_active_interactable() == component, String(npc_case.actor) + ": proximity selects this NPC")
	var closed := [0]
	ui.connect("dialogue_closed", func() -> void: closed[0] += 1)
	_touch(scene, true)
	await _frames(20)
	var opened: bool = bool(ui.call("is_dialogue_active"))
	_expect(opened and int(ui.call("get_dialogue_line_index")) == 0, String(npc_case.actor) + ": one held ACT opens exactly one greeting line")
	_expect(closed[0] == 0 and state.current_task_index == 2, String(npc_case.actor) + ": held opening ACT neither closes greeting nor advances quest")
	if opened:
		_expect(_button(scene).is_visible_in_tree() and not _button(scene, "up").is_visible_in_tree(), String(npc_case.actor) + ": dialogue retains ACT and hides movement")
	_touch(scene, false)
	await _frames(4)
	if opened:
		await _tap(scene)
		_expect(not bool(ui.call("is_dialogue_active")) and closed[0] == 1, String(npc_case.actor) + ": one further ACT closes greeting exactly once")
		_expect(state.get_mode() == state.GameMode.EXPLORATION, String(npc_case.actor) + ": greeting close restores exploration")
	player.global_position = OUTSIDE_NPC_REGIONS
	await _physics_frames(6)
	var physically_outside := not sensor.get_overlapping_bodies().has(player)
	var can_after_exit: bool = bool(component.call("can_interact"))
	var active_after_exit = interactions.get_active_interactable()
	_expect(physically_outside, String(npc_case.actor) + ": actual body exit leaves the original NPC region")
	_expect(not can_after_exit, String(npc_case.actor) + ": physical exit clears nearby-player registration")
	_expect(active_after_exit == null, String(npc_case.actor) + ": no NPC stays active outside all regions")
	await _tap(scene)
	_expect(not bool(ui.call("is_dialogue_active")), String(npc_case.actor) + ": ACT outside every region cannot reopen a remote greeting")
	var detail := {
		"actor": String(npc_case.actor), "binding_present": binding_present,
		"physically_entered": entered, "can_interact_on_entry": can_enter,
		"greeting_opened": opened, "physically_outside": physically_outside,
		"can_interact_after_exit": can_after_exit,
		"active_after_exit": str(active_after_exit.get_path()) if is_instance_valid(active_after_exit) else "",
		"exit_connection_present": sensor.body_exited.is_connected(Callable(component, "_on_body_exited")),
	}
	observations.append(detail)
	print("ORIGINAL_NPC_INTERACTION_CASE " + JSON.stringify(detail))
	# Close a diagnosed stale greeting before changing scenes, using its normal
	# deliberate input. Do not repair bindings or registrations in the test.
	if bool(ui.call("is_dialogue_active")):
		await _tap(scene)
	player.set_physics_process(true)


func _actual_bandit(selected_gender: String) -> void:
	var profile: Dictionary = PROFILE.duplicate(true)
	profile.gender = selected_gender
	state.start_new_game(profile, false)
	state.complete_tutorial_activity()
	state.current_task_index = 2
	state.current_quest = String(state.tasks[2].quest_text)
	var scene := await _load(OAK)
	await _controls(scene)
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	var ui := scene.get_node_or_null("CanvasLayer/Panel")
	var trigger := scene.get_node_or_null("Bandits/BanditTaskTrigger") as Area2D
	var collider := scene.get_node_or_null("Bandits/BanditTaskTrigger/CollisionShape2D") as CollisionShape2D
	_expect(player != null and ui != null and trigger != null and collider != null, selected_gender + ": real First Bandit entry contract exists")
	if player == null or ui == null or trigger == null or collider == null:
		return
	player.set_physics_process(false)
	player.global_position = OUTSIDE_NPC_REGIONS
	await _physics_frames(4)
	player.global_position = collider.global_position
	await _physics_frames(6)
	_expect(trigger.get_overlapping_bodies().has(player) and trigger.has_method("can_interact") and bool(trigger.call("can_interact")), selected_gender + ": physical First Bandit entry enables interaction")
	await _tap(scene)
	_expect(bool(ui.call("is_dialogue_active")) and not state.battle_active, selected_gender + ": ACT first opens Bandit dialogue")
	_check_dialogue_placement(scene, selected_gender + " Bandit")
	await _tap(scene)
	await _frames(8)
	var battle: Node = state.get_current_battle_enemy()
	_expect(is_instance_valid(battle), selected_gender + ": final dialogue ACT starts actual battle")
	if not is_instance_valid(battle):
		return
	_expect(battle.scene_file_path == SCENE_DIRECTORY_FOR_BANDIT + selected_gender + "_vs_bandit.tscn", selected_gender + ": original matching VS scene is routed")
	_expect(not scene.get_node("MobileControls").visible, selected_gender + ": battle hides original exploration controller")
	var scope: Dictionary = state.get_encounter_question_scope()
	_expect(scope.get("grade") == "Grade 1" and scope.get("difficulty") == "Easy" and not scope.has("topic"), selected_gender + ": First Bandit exact question scope retained")
	var outcomes: Array[bool] = []
	var signal_count := [0]
	battle.connect("battle_finished", func(_won: bool) -> void: signal_count[0] += 1)
	_await_actual_battle_finished(battle, outcomes)
	var question_label := battle.get_node_or_null("CanvasLayer/Panel/QuestionLabel") as Label
	_expect(question_label != null and question_label.text == "1 + 1 = ?", selected_gender + ": offline provider fills original question UI")
	for answer_index in 3:
		battle.call("answer_selected", 0)
	battle.call("answer_selected", 0)
	var timeout := get_tree().create_timer(4.0)
	while outcomes.is_empty() and timeout.time_left > 0.0:
		await get_tree().process_frame
	await _frames(4)
	_expect(outcomes == [true] and signal_count[0] == 1, selected_gender + ": real correct answers and duplicate click complete once after terminal effect")
	_expect(state.current_task_index == state.tasks.size() and state.current_quest == state.DEFAULT_QUEST, selected_gender + ": battle victory preserves authoritative terminal quest state")
	_expect(state.get_mode() == state.GameMode.EXPLORATION and not state.battle_active, selected_gender + ": victory restores exploration mode")
	_expect(scene.get_node("MobileControls").visible and _button(scene, "up").is_visible_in_tree(), selected_gender + ": victory restores original controller")
	_expect(scene.get_node("GameHUD")._get_active_quest_text().is_empty(), selected_gender + ": victory does not redisplay Teacher House")


func _await_actual_battle_finished(battle: Node, outcomes: Array[bool]) -> void:
	var won: bool = await battle.battle_finished
	outcomes.append(won)


func _check_dialogue_placement(scene: Node, label: String) -> void:
	var panel := scene.get_node_or_null("CanvasLayer/DialoguePanel") as Control
	_expect(panel != null, label + ": existing shared dialogue panel exists")
	if panel != null:
		_expect(is_equal_approx(panel.anchor_top, 1.0) and is_equal_approx(panel.anchor_bottom, 1.0) and absf(panel.get_viewport_rect().size.y - panel.get_global_rect().end.y - 40.0) < 1.5, label + ": authorized dialogue bottom-center placement is retained")


func _physics_frames(count: int) -> void:
	for frame_index in count:
		await get_tree().physics_frame
	await _frames(2)


func _roundtrip_wrapped_npc_bindings() -> void:
	# Pack a detached instance into one unique fixture. This exercises inherited
	# editable-child serialization without saving or running another project.
	var source_text := FileAccess.get_file_as_string(OAK)
	var source_resource := load(OAK) as PackedScene
	_expect(source_resource != null, "NPC roundtrip: canonical Oakleaf scene resource loads")
	if source_resource == null:
		return
	var source := source_resource.instantiate()
	_check_packed_npc_bindings(source, "before packing")
	var packed := PackedScene.new()
	var pack_error := packed.pack(source)
	_expect(pack_error == OK, "NPC roundtrip: detached canonical Oakleaf instance packs")
	if pack_error != OK:
		source.free()
		return
	var fixture_path := "user://original_interaction_roundtrip_%d.tscn" % Time.get_ticks_usec()
	var save_error := ResourceSaver.save(packed, fixture_path)
	_expect(save_error == OK, "NPC roundtrip: packed scene saves only to a unique test fixture")
	source.free()
	if save_error == OK:
		var reloaded := ResourceLoader.load(fixture_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		_expect(reloaded != null, "NPC roundtrip: saved fixture reloads without resource cache")
		if reloaded != null:
			var restored := reloaded.instantiate()
			_check_packed_npc_bindings(restored, "after save and reload")
			restored.free()
	if FileAccess.file_exists(fixture_path):
		_expect(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path)) == OK, "NPC roundtrip: only the newly created fixture is removed")
	_expect(FileAccess.get_file_as_string(OAK) == source_text, "NPC roundtrip: canonical Oakleaf product scene is unchanged")


func _check_packed_npc_bindings(scene: Node, phase: String) -> void:
	var ui := scene.get_node_or_null("CanvasLayer/Panel")
	for actor_name in ["girl_npc", "villager-female", "NPC", "NPC1"]:
		var actor := scene.get_node_or_null(actor_name)
		var visual := scene.get_node_or_null(actor_name + "/Visual")
		_expect(actor != null and scene.is_editable_instance(actor), actor_name + ": proper editable-instance metadata persists " + phase)
		var has_binding := visual != null and visual.has_method("interact") and visual.has_method("can_interact") and visual.has_method("_get_quest_ui")
		_expect(has_binding, actor_name + ": original greeting script survives " + phase)
		if has_binding:
			_expect(visual.call("_get_quest_ui") == ui and ui != null, actor_name + ": original shared quest host path resolves " + phase)
