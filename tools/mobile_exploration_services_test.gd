extends SceneTree

const GameStateScript = preload("res://scripts/game_state.gd")
const InteractableAreaScript = preload("res://scripts/interactable_area.gd")
const InteractionManagerScript = preload("res://scripts/interaction_manager.gd")
const MOBILE_CONTROLS_SCENE = preload("res://ui/mobile_controls.tscn")
const CANONICAL_PLAYER_HOUSE_PATH := "res://interiors/player_house.tscn"
const LEGACY_PLAYER_HOUSE_PATH := "res://interiors/players_house.tscn"

var _failures := 0


class FakeInteractable extends Node2D:
	var interaction_priority: int = 0
	var enabled: bool = true
	var available: bool = true
	var activation_count: int = 0


	func can_interact() -> bool:
		return enabled and available


	func is_registration_valid() -> bool:
		return enabled


	func interact() -> bool:
		activation_count += 1
		return true


	func get_interaction_position() -> Vector2:
		return global_position


	func get_interaction_priority() -> int:
		return interaction_priority


class FakeInteractionTarget extends Node2D:
	func can_interact() -> bool:
		return true


	func interact() -> bool:
		return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_state = GameStateScript.new()
	var interaction_test_original_mode = GameState.get_mode()
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	InputManager.clear_mobile_state()

	# Checkpoint 4 fixtures: these source-level contracts run without keyboard/InputMap
	# synthesis and keep the trigger/teacher adapters independently verifiable.
	var trigger_source := _read_fixture("res://world/task_progress_trigger.gd")
	_assert_equal(trigger_source.is_empty(), false, "TaskProgressTrigger fixture exists")
	_assert_equal(trigger_source.contains("extends Area2D"), true, "TaskProgressTrigger extends Area2D")
	_assert_equal(trigger_source.contains("@export var required_task_index: int = 0"), true, "TaskProgressTrigger defaults to task zero")
	_assert_equal(trigger_source.contains("event_key"), true, "TaskProgressTrigger exposes an event key")
	_assert_equal(trigger_source.contains("advance_task_and_save"), true, "TaskProgressTrigger uses persisted task advancement")
	_assert_equal(trigger_source.count("advance_task_and_save"), 1, "TaskProgressTrigger advances exactly once per entry path")
	_assert_source_order(trigger_source, "_is_valid_player", "advance_task_and_save", "trigger validates the player before advancing")
	_assert_source_order(trigger_source, "advance_task_and_save", "_consumed = true", "trigger consumes only after a successful advancement result")
	var game_state_source := _read_fixture("res://scripts/game_state.gd")
	_assert_source_order(game_state_source, "current_task_index += 1", "var save_path := save_game()", "GameState increments before saving")
	_assert_source_order(game_state_source, "var save_path := save_game()", "task_state_changed.emit", "GameState saves before emitting the task signal")

	var teacher_source := _read_fixture("res://scripts/teacher_task_interaction.gd")
	_assert_equal(teacher_source.is_empty(), false, "TeacherTaskInteraction fixture exists")
	_assert_equal(teacher_source.contains("func can_interact"), true, "Teacher adapter exposes can_interact")
	_assert_equal(teacher_source.contains("current_task_index != 1"), true, "Teacher adapter rejects every task except task one")
	_assert_equal(teacher_source.contains("GameState.GameMode.EXPLORATION"), true, "Teacher adapter requires exploration mode")
	_assert_equal(teacher_source.contains("GameState.GameMode.DIALOGUE"), true, "Teacher adapter pushes dialogue mode")
	_assert_equal(teacher_source.contains("pop_mode"), true, "Teacher adapter pops its dialogue mode")
	_assert_equal(teacher_source.contains("_active = true"), true, "Teacher adapter guards duplicate interaction")
	_assert_equal(teacher_source.contains("if _active or"), true, "Teacher adapter rejects interaction while active")
	_assert_equal(teacher_source.contains("return false"), true, "Teacher adapter reports duplicate interaction as rejected")
	_assert_equal(teacher_source.contains("func _exit_tree()"), true, "Teacher adapter cleans up when its scene is freed")
	_assert_source_order(teacher_source, "_active = true", "play_teacher_dialogue", "Teacher adapter guards before delegating dialogue")
	_assert_source_order(teacher_source, "GameState.push_mode(GameState.GameMode.DIALOGUE)", "_finish_interaction", "Teacher adapter releases dialogue mode after completion")

	var oak_source := _read_fixture("res://scenes/oak_leaf_village.tscn")
	_assert_equal(oak_source.contains("res://world/task_progress_trigger.gd"), true, "Oak Leaf uses TaskProgressTrigger")
	_assert_equal(oak_source.contains("TeacherHouseTaskTrigger"), true, "Oak Leaf retains the Teacher House trigger node")
	_assert_equal(oak_source.contains("res://world/Task1.gd"), true, "Oak Leaf preserves the unrelated Bandit Task1 script")
	_assert_equal(oak_source.contains("script = ExtResource(\"28_teacher_trigger\")"), true, "Teacher House trigger points to the new script")
	var teacher_trigger_start := oak_source.find("[node name=\"TeacherHouseTaskTrigger\"")
	var teacher_trigger_end := oak_source.find("[node name=\"CollisionShape2D\"", teacher_trigger_start)
	var teacher_trigger_block := oak_source.substr(teacher_trigger_start, teacher_trigger_end - teacher_trigger_start)
	_assert_equal(teacher_trigger_block.contains("trigger_for_task_index"), false, "Teacher House trigger has no old Task1 index property")
	_assert_equal(teacher_trigger_block.contains("ui_panel"), false, "Teacher House trigger has no old QuestUI proximity path")
	var teacher_house_source := _read_fixture("res://interiors/teacher_house.tscn")
	_assert_equal(teacher_house_source.contains("res://scripts/teacher_task_interaction.gd"), true, "Teacher House uses TeacherTaskInteraction")
	_assert_equal(teacher_house_source.contains("res://scripts/interactable_area.gd"), true, "Teacher House wires the reusable InteractableArea")
	_assert_equal(teacher_house_source.contains("interaction_target_path = NodePath(\"..\")"), true, "Teacher interaction targets its parent Teacher node")
	_assert_equal(teacher_house_source.contains("interaction_method = &\"interact\""), true, "Teacher interaction delegates interact")
	_assert_equal(teacher_house_source.contains("availability_method = &\"can_interact\""), true, "Teacher interaction delegates can_interact")
	_assert_equal(teacher_house_source.contains("interaction_priority = 100"), true, "Teacher interaction has priority one hundred")
	_assert_equal(teacher_house_source.contains("res://world/Task1.gd"), false, "Teacher House removes the old Task1 resource")
	var teacher_house_teacher_start := teacher_house_source.find("[node name=\"Teacher\"")
	var teacher_house_teacher_end := teacher_house_source.find("[node name=\"CollisionShape2D\"", teacher_house_teacher_start)
	var teacher_house_teacher_block := teacher_house_source.substr(teacher_house_teacher_start, teacher_house_teacher_end - teacher_house_teacher_start)
	_assert_equal(teacher_house_teacher_block.contains("script = ExtResource(\"27_teacher\")"), true, "Teacher node uses TeacherTaskInteraction")
	_assert_equal(teacher_house_source.contains("[connection signal=\"body_entered\" from=\"Teacher/Area2D2\""), false, "Teacher House has no duplicate automatic body-entered path")
	var quest_ui_source := _read_fixture("res://world/QuestUI.gd")
	_assert_equal(quest_ui_source.contains("func play_teacher_dialogue()"), true, "QuestUI exposes the Teacher dialogue wrapper")
	_assert_source_order(quest_ui_source, "await show_completed_with_dialogue()", "GameState.save_game()", "Teacher completion saves after the existing dialogue routine advances the task")
	_assert_source_order(quest_ui_source, "GameState.save_game()", "GameState.task_state_changed.emit", "Teacher completion emits its task signal after saving")
	_assert_equal(quest_ui_source.contains("\"type\": \"quest_completed\""), true, "Teacher completion emits a notification-compatible event type")
	_assert_equal(quest_ui_source.contains("\"key\": \"quest:main:task:%d:complete\""), true, "Teacher completion emits a stable notification key")

	# The candidate-ranking fixtures below are test-only; production Teacher
	# wiring is verified above and remains outside these fake targets.
	var test_player := Node2D.new()
	test_player.add_to_group("player_character")
	test_player.global_position = Vector2.ZERO
	get_root().add_child(test_player)
	var interaction_manager = InteractionManagerScript.new()
	get_root().add_child(interaction_manager)
	interaction_manager.set_process(false)
	var priority_near := FakeInteractable.new()
	priority_near.global_position = Vector2(10, 0)
	var priority_far := FakeInteractable.new()
	priority_far.global_position = Vector2(100, 0)
	priority_far.interaction_priority = 10
	get_root().add_child(priority_near)
	get_root().add_child(priority_far)
	interaction_manager.register(priority_near)
	interaction_manager.register(priority_far)
	await process_frame
	_assert_equal(interaction_manager.get_active_interactable(), priority_far, "higher-priority fake wins even when farther away")

	interaction_manager.unregister(priority_near)
	interaction_manager.unregister(priority_far)
	priority_near.interaction_priority = 0
	priority_far.interaction_priority = 0
	interaction_manager.register(priority_far)
	interaction_manager.register(priority_near)
	await process_frame
	_assert_equal(interaction_manager.get_active_interactable(), priority_near, "nearer fake wins when priorities are equal")

	interaction_manager.unregister(priority_near)
	interaction_manager.unregister(priority_far)
	priority_near.global_position = Vector2(30, 0)
	priority_far.global_position = Vector2(30, 0)
	interaction_manager.register(priority_far)
	interaction_manager.register(priority_near)
	await process_frame
	_assert_equal(interaction_manager.get_active_interactable(), priority_far, "earlier registration wins when priority and distance are equal")

	interaction_manager.set_process(true)
	InputManager.set_mobile_interact_pressed(true)
	await process_frame
	_assert_equal(priority_far.activation_count, 1, "the manager process dispatches a mobile Interact press to the selected fake")
	_assert_equal(interaction_manager.request_interaction(), false, "a held mobile Interact press cannot activate twice")
	InputManager.set_mobile_interact_pressed(false)
	await process_frame
	InputManager.set_mobile_interact_pressed(true)
	await process_frame
	_assert_equal(priority_far.activation_count, 2, "a release followed by a new mobile press dispatches exactly once more")
	_assert_equal(priority_far.activation_count, 2, "a second press causes exactly one additional activation")
	InputManager.set_mobile_interact_pressed(false)

	interaction_manager.unregister(priority_near)
	priority_far.available = false
	await process_frame
	_assert_equal(interaction_manager.has_active_interactable(), false, "temporarily unavailable fakes clear the active interaction")
	priority_far.available = true
	await process_frame
	_assert_equal(interaction_manager.get_active_interactable(), priority_far, "a fake reappears after availability returns without re-registering")
	priority_far.enabled = false
	await process_frame
	_assert_equal(interaction_manager.has_active_interactable(), false, "disabled fake candidates clear the active interaction")
	interaction_manager.unregister(priority_far)
	interaction_manager.unregister(priority_near)
	await process_frame
	_assert_equal(interaction_manager.has_active_interactable(), false, "unregistered fake candidates clear the active interaction")
	interaction_manager.register(priority_near)
	await process_frame
	priority_near.queue_free()
	await process_frame
	_assert_equal(interaction_manager.has_active_interactable(), false, "freed fake candidates clear the active interaction")
	var interaction_host := Node2D.new()
	var interaction_target := FakeInteractionTarget.new()
	interaction_target.name = "Target"
	var interaction_area := InteractableAreaScript.new()
	interaction_area.interaction_target_path = NodePath("../Target")
	interaction_host.add_child(interaction_target)
	interaction_host.add_child(interaction_area)
	get_root().add_child(interaction_host)
	interaction_area._on_body_entered(test_player)
	_assert_equal(interaction_area.can_interact(), true, "a fake target with its configured availability method is interactable")
	interaction_area.availability_method = &"missing_availability"
	_assert_equal(interaction_area.can_interact(), false, "a configured missing availability method rejects interaction")
	_assert_equal(interaction_area.is_registration_valid(), false, "a configured missing availability method is not structurally valid")
	interaction_area.availability_method = &""
	_assert_equal(interaction_area.can_interact(), true, "an intentionally empty availability method remains optional")
	interaction_host.remove_child(interaction_target)
	_assert_equal(interaction_area.can_interact(), false, "a detached fake target rejects interaction")
	interaction_target.queue_free()
	interaction_host.queue_free()
	priority_far.queue_free()
	interaction_manager.queue_free()
	test_player.queue_free()
	InputManager.clear_mobile_state()
	GameState.set_mode(interaction_test_original_mode)

	# Exercise the autoload's touch-facing API directly; never synthesize InputMap actions.
	InputManager.clear_mobile_state()
	InputManager.set_mobile_direction("right", true)
	InputManager.set_mobile_direction("up", true)
	await process_frame
	_assert_equal(InputManager.get_movement_vector() != Vector2.ZERO, true, "two held mobile directions produce movement")
	_assert_equal(InputManager.get_movement_vector().length() <= 1.0, true, "two held mobile directions are normalized to movement speed")
	InputManager.clear_mobile_state()
	_assert_equal(InputManager.get_movement_vector(), Vector2.ZERO, "clearing mobile state stops movement immediately")
	_assert_equal(InputManager.has_method("consume_interact_just_pressed"), true, "InputManager exposes a consuming Interact edge API")
	if InputManager.has_method("consume_interact_just_pressed"):
		InputManager.set_mobile_direction("right", true)
		InputManager.set_mobile_interact_pressed(true)
		await process_frame
		_assert_equal(InputManager.get_movement_vector() != Vector2.ZERO, true, "movement remains active while Interact is held")
		_assert_equal(InputManager.consume_interact_just_pressed(), true, "Interact exposes one press edge independently of movement")
		_assert_equal(InputManager.consume_interact_just_pressed(), false, "consuming the Interact edge clears it")
		InputManager.set_mobile_interact_pressed(false)
		_assert_equal(InputManager.is_interact_just_pressed(), false, "releasing Interact leaves no stale edge after consumption")
		InputManager.set_mobile_interact_pressed(true)
		await process_frame
		_assert_equal(InputManager.is_interact_just_pressed(), true, "legacy Interact reads consume one real press edge")
		_assert_equal(InputManager.is_interact_just_pressed(), false, "a second legacy Interact read has no stale edge")
		InputManager.set_mobile_interact_pressed(false)
		InputManager.set_mobile_interact_pressed(true)
		await process_frame
		InputManager.set_mobile_interact_pressed(false)
		_assert_equal(InputManager.consume_interact_just_pressed(), false, "releasing Interact clears an unconsumed pending edge")
		InputManager.clear_mobile_state()

	# A lock must release the widgets themselves, not only the manager's state.
	var original_mode = GameState.get_mode()
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	var mobile_controls := MOBILE_CONTROLS_SCENE.instantiate() as CanvasLayer
	get_root().add_child(mobile_controls)
	await process_frame
	mobile_controls.configure(true)
	await process_frame
	var action_margin := mobile_controls.get_node_or_null("Root/ActionMargin") as Control
	var action_panel := mobile_controls.get_node_or_null("Root/ActionMargin/ActionPanel") as Control
	_assert_equal(action_margin != null and not action_margin.visible, true, "the hidden Interact action margin has no visible or interactive region")
	_assert_equal(action_panel != null and not action_panel.visible, true, "the hidden Interact action panel has no visible or interactive region")
	var right_button := mobile_controls.get_node_or_null("Root/MovementMargin/MovementPanel/MovementBox/MiddleRow/RightButton") as TouchHoldButton
	_assert_equal(right_button != null, true, "mobile controls expose the right touch-hold button")
	if right_button != null:
		var hold_changes: Array[bool] = []
		right_button.hold_changed.connect(func(is_held: bool) -> void: hold_changes.append(is_held))
		var touch_press := InputEventScreenTouch.new()
		touch_press.index = 41
		touch_press.pressed = true
		right_button._gui_input(touch_press)
		await process_frame
		_assert_equal(InputManager.get_movement_vector() != Vector2.ZERO, true, "a held touch button feeds mobile movement before a lock")
		InputManager.lock_input("touch_hold_lock_test")
		await process_frame
		_assert_equal(InputManager.get_movement_vector(), Vector2.ZERO, "locking clears InputManager mobile movement")
		_assert_equal(hold_changes.has(false), true, "locking force-releases the held touch button")
		InputManager.unlock_input("touch_hold_lock_test")
		await process_frame
		_assert_equal(InputManager.get_movement_vector(), Vector2.ZERO, "unlocking does not restore a stale held touch")

	mobile_controls.queue_free()
	await process_frame
	GameState.set_mode(original_mode)

	game_state.set_mode(GameStateScript.GameMode.EXPLORATION)
	game_state.push_mode(GameStateScript.GameMode.DIALOGUE)
	game_state.push_mode(GameStateScript.GameMode.CUTSCENE)
	_assert_equal(game_state.get_mode(), GameStateScript.GameMode.CUTSCENE, "mode is CUTSCENE after pushes")

	game_state.pop_mode()
	_assert_equal(game_state.get_mode(), GameStateScript.GameMode.DIALOGUE, "mode is DIALOGUE after first pop")

	game_state.pop_mode()
	_assert_equal(game_state.get_mode(), GameStateScript.GameMode.EXPLORATION, "mode is EXPLORATION after second pop")

	var battle_enemy := Node.new()
	get_root().add_child(battle_enemy)
	game_state.begin_battle(battle_enemy)
	_assert_equal(game_state.get_mode(), GameStateScript.GameMode.BATTLE, "begin_battle enters BATTLE mode")

	game_state.end_battle()
	_assert_equal(game_state.get_mode(), GameStateScript.GameMode.EXPLORATION, "end_battle restores EXPLORATION mode")
	battle_enemy.queue_free()

	var loaded_game_state = GameStateScript.new()
	_assert_equal(loaded_game_state.get_mode(), GameStateScript.GameMode.MENU, "fresh game state starts in MENU mode")
	loaded_game_state.apply_save_data({
		"save_version": 6,
		"player_name": "Test Player",
		"gender": "male",
		"grade_level": "6",
		"current_quest": "No active quest",
		"scene_path": CANONICAL_PLAYER_HOUSE_PATH,
		"player_position": {"x": 64, "y": 96},
		"current_lives": 3,
		"max_lives": 3,
		"city_of_knowledge_unlocked": false,
		"current_task_index": 0
	})
	_assert_equal(loaded_game_state.get_mode(), GameStateScript.GameMode.EXPLORATION, "restoring a normal save enters EXPLORATION mode")

	var loaded_battle_enemy := Node.new()
	get_root().add_child(loaded_battle_enemy)
	loaded_game_state.begin_battle(loaded_battle_enemy)
	_assert_equal(loaded_game_state.get_mode(), GameStateScript.GameMode.BATTLE, "restored games enter BATTLE mode")
	loaded_game_state.end_battle()
	_assert_equal(loaded_game_state.get_mode(), GameStateScript.GameMode.EXPLORATION, "restored games return to EXPLORATION after battle")
	loaded_battle_enemy.queue_free()

	game_state.apply_save_data({"save_version": 5, "current_quest": ""})
	_assert_equal(game_state.current_task_index, 0, "version 5 saves default task index to zero")

	var canonical_scene_paths := [
		CANONICAL_PLAYER_HOUSE_PATH,
		"res://scenes/oak_leaf_village.tscn",
		"res://scenes/city_of_knowledge.tscn",
		"res://scenes/2nd Village/Pinehill Village.tscn"
	]
	for scene_path in canonical_scene_paths:
		_assert_equal(ResourceLoader.exists(scene_path), true, "canonical scene exists: %s" % scene_path)

	game_state.start_new_game({})
	_assert_equal(game_state.current_scene_path, CANONICAL_PLAYER_HOUSE_PATH, "new games use the canonical Player House scene")

	game_state.apply_save_data({"scene_path": "res://world/player_house_outside_door.tscn"})
	_assert_equal(game_state.current_scene_path, "res://scenes/oak_leaf_village.tscn", "player-house door legacy path maps to Oak Leaf")
	_assert_equal(ResourceLoader.exists(game_state.current_scene_path), true, "player-house door target exists")

	game_state.apply_save_data({"scene_path": "res://world/npc_house_outside_door.tscn"})
	_assert_equal(game_state.current_scene_path, "res://scenes/oak_leaf_village.tscn", "NPC-house door legacy path maps to Oak Leaf")
	_assert_equal(ResourceLoader.exists(game_state.current_scene_path), true, "NPC-house door target exists")

	game_state.apply_save_data({"scene_path": "res://world/teacher_house_outside_door.tscn"})
	_assert_equal(game_state.current_scene_path, "res://scenes/oak_leaf_village.tscn", "teacher-house door legacy path maps to Oak Leaf")
	_assert_equal(ResourceLoader.exists(game_state.current_scene_path), true, "teacher-house door target exists")

	game_state.apply_save_data({"scene_path": "res://scenes/2nd Village/Pinehill Village.tscn"})
	_assert_equal(game_state.current_scene_path, "res://scenes/2nd Village/Pinehill Village.tscn", "Pinehill remains canonical")
	_assert_equal(game_state.get_scene_fallback_spawn(game_state.current_scene_path), Vector2(176, 368), "Pinehill fallback remains unchanged")

	var legacy_save_path := "user://mobile_exploration_legacy_scene_test.json"
	var legacy_save_file := FileAccess.open(legacy_save_path, FileAccess.WRITE)
	if legacy_save_file == null:
		_failures += 1
		push_error("could not create legacy scene-path test save")
	else:
		legacy_save_file.store_string(JSON.stringify({
			"save_version": 5,
			"current_quest": "",
			"scene_path": LEGACY_PLAYER_HOUSE_PATH
		}))
		legacy_save_file.close()
		var loaded_save := game_state.load_save(legacy_save_path)
		_assert_equal(loaded_save.get("scene_path", ""), CANONICAL_PLAYER_HOUSE_PATH, "load_save migrates the legacy Player House scene path")
		_assert_equal(game_state.current_scene_path, CANONICAL_PLAYER_HOUSE_PATH, "load_save applies the canonical Player House scene path")

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		push_error("%s: expected %s, got %s" % [message, expected, actual])


func _assert_source_order(source: String, first_token: String, second_token: String, message: String) -> void:
	var first_index := source.find(first_token)
	var second_index := source.find(second_token)
	_assert_equal(first_index >= 0 and second_index > first_index, true, message)


func _read_fixture(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
