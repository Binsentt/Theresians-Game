extends "res://tools/preservation_restoration_test.gd"
## Real physics entry exercises the product's collision-signal call stack.
## All live transports are removed before fixture state or gameplay is opened.

var transitions: Array[Dictionary] = []
var scene_changes := 0

func _ready() -> void:
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is HTTPRequest:
			node.free()
			push_error("Physics fixture rejected a live HTTPRequest node")
			get_tree().quit(2)
	)
	_run.call_deferred()

func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		get_node("/root/" + autoload_name).free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.fixture_path = "user://saves/major_physics_%d.json" % Time.get_ticks_usec()
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	get_tree().scene_changed.connect(func() -> void: scene_changes += 1)
	state.start_new_game(PROFILE, false)
	state.complete_tutorial_activity()
	await _load(HOUSE)
	await _enter_door(OAK, "Player House exit")
	await _arrival_trigger()
	await _enter_door(TEACHER, "Teacher House animated entrance")
	await _enter_door(OAK, "Teacher House immediate exit")
	await _enter_door(HOUSE, "Player House animated entrance")
	var failed := checks.filter(func(row: Dictionary) -> bool: return not row.passed).size()
	var result := {"passed":checks.size() - failed, "failed":failed, "checks":checks,
		"transitions":transitions, "live_network_calls":0, "scene_changes":scene_changes,
		"canonical_root":ProjectSettings.globalize_path("res://")}
	var output := FileAccess.open("res://docs/qa/2026-09-07-major-physics-runtime.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	print("MAJOR_PHYSICS_TRANSITION_TEST " + JSON.stringify({"passed":checks.size() - failed, "failed":failed}))
	get_tree().quit(1 if failed else 0)

func _physics_frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame

func _enter_door(destination: String, label: String) -> void:
	var source := get_tree().current_scene
	var door: Area2D = null
	for candidate in source.find_children("*", "Area2D", true, false):
		if candidate.has_method("_resolve_destination_scene_path") and candidate._resolve_destination_scene_path() == destination:
			door = candidate
			break
	_expect(door != null, label + ": original door binding exists")
	if door == null:
		return
	var physical_events := [0]
	door.body_entered.connect(func(_body: Node2D) -> void: physical_events[0] += 1)
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	player.set_physics_process(false)
	player.global_position = Vector2(-4000, -4000)
	await _physics_frames(4)
	var shape := door.find_child("CollisionShape2D", true, false) as CollisionShape2D
	_expect(shape != null and not shape.disabled, label + ": original active collision sensor exists")
	if shape == null:
		return
	var row := {"label":label, "source":source.scene_file_path, "destination":destination,
		"door":str(door.get_path()), "open_animation":door.play_open_animation_before_transition,
		"fade":door.play_fade_transition, "frame_duration":door.animation_step_duration, "fade_duration":door.fade_duration}
	var changes_before := scene_changes
	var checkpoint: int = state.current_task_index
	player.global_position = shape.global_position
	var deadline := Time.get_ticks_msec() + 8000
	while scene_changes == changes_before and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _frames(8)
	var arrived := get_tree().current_scene
	_expect(physical_events[0] == 1, label + ": engine body_entered occurs once")
	_expect(scene_changes == changes_before + 1 and arrived != null and arrived.scene_file_path == destination, label + ": one transition reaches the preserved destination")
	_expect(state.current_task_index == checkpoint, label + ": door preserves quest checkpoint")
	_expect(not inputs.is_input_locked(), label + ": destination restores input")
	_expect(arrived.get_node_or_null("MobileControls") != null and arrived.get_node("MobileControls").visible, label + ": approved world controls restore")
	row.physical_entries = physical_events[0]
	row.scene_changes = scene_changes - changes_before
	row.checkpoint = state.current_task_index
	transitions.append(row)

func _arrival_trigger() -> void:
	var scene := get_tree().current_scene
	_expect(scene.scene_file_path == OAK, "Arrival fixture uses canonical Oakleaf")
	var trigger := scene.get_node("TeacherHouseTaskTrigger") as Area2D
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	player.set_physics_process(false)
	player.global_position = Vector2(-4000, -4000)
	await _physics_frames(4)
	var events := [0]
	trigger.task_triggered.connect(func(_event: Dictionary) -> void: events[0] += 1)
	var saves_before: int = state.fixture_save_count
	player.global_position = trigger.get_node("CollisionShape2D").global_position
	await _physics_frames(6)
	_expect(events[0] == 1 and state.current_task_index == 1, "Physical Teacher House arrival advances exactly once")
	_expect(state.fixture_save_count == saves_before + 1, "Physical arrival saves exactly once")
	_expect(not trigger.monitoring and not trigger.monitorable, "Consumed arrival disables its existing sensor")
	player.global_position = Vector2(-4000, -4000)
	await _physics_frames(4)
	player.global_position = trigger.get_node("CollisionShape2D").global_position
	await _physics_frames(4)
	_expect(events[0] == 1 and state.current_task_index == 1 and state.fixture_save_count == saves_before + 1, "Reentry cannot duplicate arrival, save, or progression")
