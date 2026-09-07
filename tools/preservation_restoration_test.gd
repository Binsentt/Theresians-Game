extends Node

const HOUSE := "res://interiors/player_house.tscn"
const OAK := "res://scenes/oak_leaf_village.tscn"
const TEACHER := "res://interiors/teacher_house.tscn"
const CITY := "res://scenes/city_of_knowledge.tscn"
const PROFILE := {"student_id": "12345678", "parent_id": "123456", "player_name": "Local preservation fixture", "grade_level": "Grade 1"}
const BUTTONS := {
	"up": "Root/MovementMargin/MovementPanel/MovementBox/TopRow/UpButton",
	"down": "Root/MovementMargin/MovementPanel/MovementBox/BottomRow/DownButton",
	"left": "Root/MovementMargin/MovementPanel/MovementBox/MiddleRow/LeftButton",
	"right": "Root/MovementMargin/MovementPanel/MovementBox/MiddleRow/RightButton",
	"interact": "Root/ActionMargin/ActionPanel/ActionButton"
}
var state
var inputs
var interactions
var checks: Array[Dictionary] = []
var battle_count := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_node("/root/RemoteSync").free()
	get_node("/root/HttpApi").base_url = ""
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	var provider := get_node("/root/QuestionProvider")
	provider.free()
	var stub = load("res://tools/first_bandit_interaction_project_context_test.gd").QuestionProviderStub.new()
	stub.name = "QuestionProvider"
	get_tree().root.add_child(stub)
	get_tree().current_scene = null
	state.start_new_game(PROFILE, false)
	await _tutorial()
	await _teacher()
	await _npc_and_bandit()
	await _city_and_maps()
	var failed := 0
	for check in checks:
		if not check.passed:
			failed += 1
	var result := {"checks": checks, "failed": failed, "passed": checks.size() - failed}
	var output := FileAccess.open("res://docs/qa/2026-09-07-restoration-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	print("PRESERVATION_RESTORATION_TEST " + JSON.stringify({"failed": failed, "passed": checks.size() - failed}))
	get_tree().quit(0 if failed == 0 else 1)

func _expect(condition: bool, label: String) -> void:
	checks.append({"name": label, "passed": condition})
	print(("PASS " if condition else "FAIL ") + label)

func _frames(count: int = 4) -> void:
	for frame_index in count:
		await get_tree().process_frame

func _load(path: String) -> Node:
	inputs.clear_mobile_state()
	state.set_mode(state.GameMode.EXPLORATION)
	get_tree().change_scene_to_file(path)
	await get_tree().scene_changed
	await _frames(8)
	return get_tree().current_scene

func _button(scene: Node, direction: String = "interact") -> Control:
	return scene.get_node("MobileControls/" + BUTTONS[direction]) as Control

func _touch(scene: Node, pressed: bool, direction: String = "interact") -> void:
	var event := InputEventScreenTouch.new()
	event.index = 71
	event.pressed = pressed
	_button(scene, direction)._gui_input(event)

func _tap(scene: Node) -> void:
	_touch(scene, true)
	await _frames(4)
	_touch(scene, false)
	await _frames(4)

func _controls(scene: Node) -> void:
	_expect(scene.find_children("MobileControls", "", true, false).size() == 1, scene.scene_file_path + " one controller")
	_expect(_button(scene).is_visible_in_tree(), scene.scene_file_path + " native debug Interact visible")
	var expected := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
	for direction in expected:
		_touch(scene, true, direction)
		await _frames(2)
		_expect(inputs.get_movement_vector().is_equal_approx(expected[direction]), scene.scene_file_path + " D-pad " + direction)
		_touch(scene, false, direction)
		await _frames(2)
	state.set_mode(state.GameMode.MENU)
	await _frames()
	_expect(not scene.get_node("MobileControls").visible, scene.scene_file_path + " menu hides controller")
	state.set_mode(state.GameMode.EXPLORATION)
	await _frames()
	_expect(_button(scene).is_visible_in_tree(), scene.scene_file_path + " exploration restores controller")

func _tutorial() -> void:
	var scene := await _load(HOUSE)
	var teacher := scene.get_node("NPCTeacher")
	teacher.set_physics_process(false)
	teacher.start_tutorial()
	await _controls(scene)
	_expect(scene.get_node("GameHUD")._get_active_quest_text() == "Tutorial", "Tutorial HUD before completion")
	_touch(scene, true)
	await _frames(16)
	_expect(teacher.step == 1, "Tutorial Teacher one held touch advances exactly one instruction")
	_touch(scene, false)
	await _frames()
	var keys_before: Array = state.build_save_data().keys()
	var path: String = state.save_game()
	state.start_new_game(PROFILE, false)
	_expect(not state.load_save(path, false).is_empty(), "Save during Tutorial loads through canonical loader")
	scene = await _load(HOUSE)
	teacher = scene.get_node("NPCTeacher")
	teacher.set_physics_process(false)
	teacher.start_tutorial()
	_expect(not state._tutorial_activity_completed and scene.get_node("GameHUD")._get_active_quest_text() == "Tutorial", "Load during Tutorial preserves unfinished quest")
	for step_index in 8:
		await _tap(scene)
	_expect(state._tutorial_activity_completed, "Eight deliberate Tutorial interactions complete once")
	# Continue diagnosing persistence even on the red baseline with no tutorial interaction adapter.
	if not state._tutorial_activity_completed:
		for step_index in 8:
			teacher.next_step()
	_expect(not state.complete_tutorial_activity(), "Duplicate Tutorial completion rejected")
	_expect(state.current_task_index == 0, "Tutorial completion does not skip Teacher House task")
	_expect(scene.get_node("GameHUD")._get_active_quest_text() == "Go to the Teacher's House", "Tutorial HUD after completion")
	path = state.save_game()
	var keys_after: Array = state.build_save_data().keys()
	_expect(keys_before == keys_after and state.SAVE_VERSION == 8, "Save schema keys and version unchanged")
	state.start_new_game(PROFILE, false)
	state.load_save(path, false)
	scene = await _load(HOUSE)
	_expect(state._tutorial_activity_completed, "Save after Tutorial loads completed state")
	_expect(not scene.get_node("NPCTeacher").visible, "Completed Tutorial does not replay after loading Player House")
	_expect(scene.get_node("GameHUD")._get_active_quest_text() == "Go to the Teacher's House", "Completed save restores Teacher House HUD")
	var legacy: Dictionary = state.build_save_data()
	legacy.current_quest = state.DEFAULT_QUEST
	legacy.current_task_index = 1
	state.apply_save_data(legacy, false)
	_expect(state.current_task_index == 1 and state._tutorial_activity_completed, "Legacy progressed save keeps checkpoint")
	state.load_save(path, false)

func _teacher() -> void:
	state.current_task_index = 1
	var scene := await _load(TEACHER)
	await _controls(scene)
	var area := scene.get_node("Teacher/Area2D2")
	area._on_body_entered(get_tree().get_first_node_in_group("player_character"))
	var ui := scene.get_node("CanvasLayer/Panel")
	_touch(scene, true)
	await _frames(20)
	_expect(ui.is_dialogue_active() and ui.get_dialogue_line_index() == 0, "Teacher held opening press leaves line one intact")
	_expect(_button(scene).is_visible_in_tree() and not _button(scene, "up").is_visible_in_tree(), "Dialogue retains Interact while hiding movement")
	_expect(not interactions.request_interaction(), "Teacher duplicate trigger rejected")
	_touch(scene, false)
	await _frames()
	_touch(scene, true)
	await _frames(20)
	_expect(ui.get_dialogue_line_index() == 1 and state.current_task_index == 1, "Teacher next held press advances only one line")
	_touch(scene, false)
	await _frames()
	var saves_before: int = state.fixture_save_count
	await _tap(scene)
	_expect(not ui.is_dialogue_active() and state.current_task_index == 2, "Teacher final deliberate close advances correct task once")
	_expect(state.fixture_save_count == saves_before + 1, "Teacher final close saves once")
	_expect(state.get_mode() == state.GameMode.EXPLORATION and _button(scene, "up").is_visible_in_tree(), "Teacher close restores exploration controls")
	await _keyboard_dialogue(scene)
	await _interact_edges(scene)

func _key(pressed: bool, keycode: Key = KEY_E, echo_event: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo_event
	Input.parse_input_event(event)

func _keyboard_dialogue(scene: Node) -> void:
	var ui := scene.get_node("CanvasLayer/Panel")
	state.push_mode(state.GameMode.DIALOGUE)
	ui.begin_dialogue(["First", "Second"])
	await _frames()
	_expect(InputMap.has_action("interact"), "Canonical keyboard interact action exists")
	_key(true)
	await _frames(12)
	_key(true, KEY_E, true)
	await _frames(8)
	_expect(ui.get_dialogue_line_index() == 1 and ui.is_dialogue_active(), "Keyboard E and echo advance only one line")
	_key(false)
	await _frames()
	_key(true, KEY_SPACE)
	await _frames(12)
	_expect(not ui.is_dialogue_active(), "Keyboard Space performs final deliberate close")
	_key(false, KEY_SPACE)
	state.pop_mode()
	await _frames()
	state.push_mode(state.GameMode.DIALOGUE)
	ui.begin_dialogue(["Quick key", "Second"])
	await _frames()
	_key(true)
	_key(false)
	await _frames(6)
	_expect(ui.get_dialogue_line_index() == 1, "Quick keyboard press/release between frames advances once")
	ui._close_dialogue()
	state.pop_mode()
	await _frames()

func _interact_edges(scene: Node) -> void:
	var ui := scene.get_node("CanvasLayer/Panel")
	state.push_mode(state.GameMode.DIALOGUE)
	ui.begin_dialogue(["First", "Second", "Third"])
	await _frames()
	_touch(scene, true)
	_touch(scene, false)
	await _frames(12)
	_expect(ui.get_dialogue_line_index() == 1, "Quick touch press/release between frames advances once")
	_key(true)
	await _frames()
	await _tap(scene)
	_expect(ui.get_dialogue_line_index() == 2 and ui.is_dialogue_active(), "Simultaneous keyboard and touch share one held action")
	_key(false)
	await _frames()
	await _tap(scene)
	_expect(not ui.is_dialogue_active(), "Release then touch closes final line once")
	state.pop_mode()
	inputs.lock_input("restoration_test")
	_key(true)
	await _frames()
	inputs.unlock_input("restoration_test")
	await _frames(2)
	_expect(not inputs.consume_interact_just_pressed(), "Unlock does not turn a held keyboard key into a new press")
	_key(false)
	await _frames()

func _npc_and_bandit() -> void:
	state.current_task_index = 2
	var scene := await _load(OAK)
	await _controls(scene)
	var player := get_tree().get_first_node_in_group("player_character")
	var ui := scene.get_node("CanvasLayer/Panel")
	for npc_name in ["girl_npc", "villager-female"]:
		var target := scene.get_node(npc_name + "/Visual")
		var area := scene.get_node(npc_name + "/InteractableArea")
		_expect(target._get_quest_ui() == ui, npc_name + " restored canonical dialogue binding")
		area._on_body_entered(player)
		await _tap(scene)
		_expect(ui.is_dialogue_active(), npc_name + " mobile greeting opens")
		await _tap(scene)
		_expect(not ui.is_dialogue_active() and state.current_task_index == 2, npc_name + " final close preserves quest")
		area._on_body_exited(player)
	state.set_mode(state.GameMode.EXPLORATION)
	scene.get_node("Bandits/BanditTaskTrigger")._on_body_entered(player)
	state.battle_started.connect(func(_enemy: Node): battle_count += 1)
	_touch(scene, true)
	await _frames(20)
	_expect(ui.is_dialogue_active() and battle_count == 0, "First Bandit held opening press does not start battle")
	_touch(scene, false)
	await _frames()
	_touch(scene, true)
	await _frames(30)
	_expect(battle_count == 1 and state.current_task_index == 2, "First Bandit final close starts one battle without advancing quest")
	_expect(not scene.get_node("MobileControls").visible, "Battle hides exploration controller")
	_touch(scene, false)
	var scope: Dictionary = state.get_encounter_question_scope()
	_expect(scope.get("grade") == "Grade 1" and scope.get("difficulty") == "Easy" and not scope.has("topic"), "First Bandit Grade Difficulty and optional Topic preserved")
	await _frames(15)
	_expect(battle_count == 1, "Held Interact never duplicates battle trigger")
	var battle: Node = state._current_battle_enemy
	if is_instance_valid(battle):
		battle.battle_finished.emit(true)
		await _frames(8)
	_expect(state.current_task_index == state.tasks.size(), "First Bandit victory completes the existing task sequence")
	_expect(scene.get_node("GameHUD")._get_active_quest_text().is_empty(), "Completed task sequence does not redisplay obsolete Teacher House quest")
	state.set_mode(state.GameMode.EXPLORATION)

func _city_and_maps() -> void:
	var scene := await _load(CITY)
	var expected := {"Bandits": "right", "Bandits2": "left", "Bandits3": "right", "Bandits4": "up", "Bandits5": "down"}
	for bandit_name in expected:
		var bandit := scene.get_node(bandit_name)
		_expect(String(bandit.get_node("Visual").animation) == expected[bandit_name], bandit_name + " original initial facing")
		_expect(bandit.walk_speed == 30.0 and bandit.wander_radius == 42.0, bandit_name + " wandering speed and radius preserved")
	await _controls(scene)
	for path in ["res://scenes/2nd Village/Pinehill Village.tscn", "res://interiors/school.tscn"]:
		scene = await _load(path)
		await _controls(scene)
	var arena := Node2D.new()
	arena.position = Vector2(10000, 10000)
	add_child(arena)
	var bandit = load("res://NPC/Enemy/wandering_bandit.tscn").instantiate()
	arena.add_child(bandit)
	var wall := StaticBody2D.new()
	wall.position = Vector2(15, 0)
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(4, 100)
	collision.shape = rectangle
	wall.add_child(collision)
	arena.add_child(wall)
	await get_tree().physics_frame
	bandit._idle_remaining = 0.0
	bandit._begin_leg(Vector2.RIGHT)
	_expect(bandit.get_node("Visual").is_playing(), "City Bandit walking animation plays")
	for frame_index in 40:
		await get_tree().physics_frame
	_expect(bandit.position.x > 0 and bandit.position.x < wall.position.x and bandit.velocity.is_zero_approx(), "City Bandit walks then stops at collision")
	_expect(bandit.global_position.distance_to(bandit._home_position) <= bandit.wander_radius, "City Bandit remains inside home radius")
	arena.queue_free()
