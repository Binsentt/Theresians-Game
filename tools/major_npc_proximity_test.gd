extends "res://tools/gameplay_civilian_expansion_test.gd"
## Real map actors/player, isolated transport, and interaction-only geometry gate.
## This harness never rewrites the older immutable civilian expansion baseline.

const MAJOR_RESULT := "res://docs/qa/2026-09-07-major-npc-runtime.json"
const MAJOR_BEFORE := "res://docs/qa/2026-09-07-major-npc-runtime-before-revision3.json"
const FIXTURE_REVISION := 3
const OAK_CIVILIANS := ["NPC1", "NPC", "girl_npc", "villager-female"]
const CORRECTED_CIVILIANS := ["girl_npc", "villager-female"]
const SIDES := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const SIDE_NAMES := ["left", "right", "top", "bottom"]
const APPROACH_INPUTS := ["right", "left", "down", "up"]
const NEAR_GAP := 0.5
const FAR_GAP := 32.0
const TARGET_SIZE := Vector2(12.0, 10.0)
const TARGET_CENTER := Vector2(0.0, 4.0)

var proximity_observations: Array[Dictionary] = []
var collision_observations: Array[Dictionary] = []
var source_snapshots: Dictionary = {}
var geometry_ready: Dictionary = {}
var deferred_range_assertions := 0
var http_request_count := 0


func _ready() -> void:
	get_tree().node_added.connect(_reject_http_request)
	# Disable live transports immediately while root startup finishes; _run
	# removes them before any profile, save, world scene, state change or await.
	var live_http := get_node_or_null("/root/HttpApi")
	if live_http != null:
		live_http.set("base_url", "")
		live_http.process_mode = Node.PROCESS_MODE_DISABLED
	var live_sync := get_node_or_null("/root/RemoteSync")
	if live_sync != null:
		live_sync.process_mode = Node.PROCESS_MODE_DISABLED
	_run.call_deferred()


func _reject_http_request(node: Node) -> void:
	if node is HTTPRequest:
		http_request_count += 1
		node.free()
		push_error("Major NPC fixture rejected a live HTTPRequest node")
		get_tree().quit(2)


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		var live_node := get_node_or_null("/root/" + autoload_name)
		if live_node != null:
			live_node.free()
	_expect(get_tree().root.find_children("*", "HTTPRequest", true, false).is_empty(), "No HTTPRequest exists before any NPC fixture profile")
	_expect(get_node_or_null("/root/RemoteSync") == null and get_node_or_null("/root/HttpApi") == null and get_node_or_null("/root/QuestionProvider") == null, "All real production transports and QuestionProvider are absent before fixture gameplay")
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.fixture_path = "user://saves/major_npc_proximity_%d.json" % Time.get_ticks_usec()
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	state.start_new_game(PROFILE, false)
	state.current_task_index = 2
	state.current_quest = String(state.tasks[2].get("quest_text", ""))
	state._tutorial_activity_completed = true
	state.canonical_activity_boundary.connect(func(_event: Dictionary) -> void: activity_events += 1)
	var scene := await _load(OAK)
	_freeze_actors(scene)
	var player := get_tree().get_first_node_in_group("player_character") as CharacterBody2D
	_expect(player != null, "Canonical Oakleaf creates the actual selected player")
	if player == null:
		_finish_major()
		return
	player.set_physics_process(false)
	player.global_position = OUTSIDE
	await _physics_frames(5)
	var player_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_expect(player_shape != null and player_shape.shape != null, "Actual player physical footprint is available")
	if player_shape == null or player_shape.shape == null:
		_finish_major()
		return
	source_snapshots.before = _snapshot_map(scene, MAP_CASES[0])
	source_snapshots.player_foot = _geometry_snapshot(player_shape)
	_expect(player_shape.shape is RectangleShape2D and _world_rect(player_shape).size.distance_to(Vector2(2.0, 8.0)) < 0.002, "Actual male player rectangle includes its preserved 90-degree rotation and measures 2x8 world pixels")
	_source_contracts(scene)
	var clones: Array[CharacterBody2D] = []
	for index in OAK_CIVILIANS.size():
		var actor_name: String = OAK_CIVILIANS[index]
		var original := scene.get_node_or_null(actor_name) as CharacterBody2D
		if original == null:
			continue
		var actor := original.duplicate() as CharacterBody2D
		actor.name = "ProximityFixture_" + actor_name
		actor.position = Vector2(-8000.0 - float(index) * 240.0, -8000.0)
		actor.set_physics_process(false)
		scene.add_child(actor)
		actor.owner = null
		actor.set_physics_process(false)
		clones.append(actor)
		await _physics_frames(3)
		_expect(_same(_foot_local(original), _foot_local(actor)), actor_name + " fixture preserves original solid foot size, local position and scale")
		var target := _visual(actor)
		_expect(target != null and target.has_method("_get_quest_ui") and target.call("_get_quest_ui") == scene.get_node("CanvasLayer/Panel"), actor_name + " direct-child clone resolves the real shared dialogue host")
		await _probe_actor(scene, actor, actor_name, player, player_shape)
	player.global_position = OUTSIDE
	player.velocity = Vector2.ZERO
	await _physics_frames(4)
	var clone_names: Array = []
	for actor in clones:
		clone_names.append(String(actor.name))
	# The inherited movement helper touches only these off-map clones.
	await _world_motion(scene, {"path": "off-map canonical Oakleaf fixtures", "civilians": clone_names})
	for actor in clones:
		actor.queue_free()
	await _physics_frames(4)
	source_snapshots.after = _snapshot_map(scene, MAP_CASES[0])
	_expect(_same(source_snapshots.before, source_snapshots.after), "Every original civilian and protected map node is unchanged by clone/range/movement probes")
	_expect(state.current_task_index == 2 and state.fixture_save_count == 0 and activity_events == 0 and not state.battle_active, "NPC probes create no quest advance, save, activity or battle")
	_expect(http_request_count == 0, "No live HTTPRequest was created during all NPC probes")
	_finish_major()


func _source_contracts(scene: Node) -> void:
	var reference := scene.get_node("NPC1") as CharacterBody2D
	for actor_name in OAK_CIVILIANS:
		var actor := scene.get_node_or_null(actor_name) as CharacterBody2D
		_expect(actor != null, String(actor_name) + " is the actual bounded civilian CharacterBody2D")
		if actor == null:
			continue
		var script := actor.get_script() as Script
		_expect(script != null and script.resource_path == "res://scripts/decorative_npc_wanderer.gd" and actor.get_script() == reference.get_script(), String(actor_name) + " shares NPC1's exact approved movement script")
		_expect(is_equal_approx(float(actor.get("walk_speed")), 30.0) and is_equal_approx(float(actor.get("wander_radius")), 42.0) and is_equal_approx(float(actor.get("idle_seconds")), 1.5), String(actor_name) + " retains NPC1's 30 px/s, 42px home bound and 1.5s idle")
		_expect(actor.collision_layer == 2 and actor.collision_mask == 1 and _foot(actor) != null, String(actor_name) + " retains separate solid foot collision and original layers")
		var visual := _visual(actor)
		var rates_match := visual != null and visual.sprite_frames != null
		for animation_name in [&"walk_down", &"walk_left", &"walk_right", &"walk_up"]:
			rates_match = rates_match and visual.sprite_frames.has_animation(animation_name) and is_equal_approx(visual.sprite_frames.get_animation_speed(animation_name), 5.0)
		_expect(rates_match, String(actor_name) + " retains all four original directional animations at NPC1's 5fps")
		var sensor := _find_component(actor, "Area2D") as Area2D
		var sensor_shape := sensor.get_node_or_null("CollisionShape2D") as CollisionShape2D if sensor != null else null
		_expect(sensor_shape != null and sensor_shape.shape != null, String(actor_name) + " retains the separate interaction-only shape")
		if sensor_shape == null or sensor_shape.shape == null:
			continue
		var world_size := sensor_shape.shape.get_rect().size * sensor_shape.global_scale.abs()
		var relative_center := sensor_shape.global_position - actor.global_position
		var sized := world_size.distance_to(TARGET_SIZE) < 0.002
		var centered := relative_center.distance_to(TARGET_CENTER) < 0.002
		geometry_ready[String(actor_name)] = sized and centered
		if actor_name in CORRECTED_CIVILIANS:
			_expect(sized, String(actor_name) + " interaction target is 12x10 world pixels")
			_expect(centered, String(actor_name) + " interaction target is centered at actor-local (0,4)")


func _foot_local(actor: Node) -> Dictionary:
	var foot := _foot(actor)
	if foot == null or foot.shape == null:
		return {}
	return {"size": _vector(foot.shape.get_rect().size), "position": _vector(foot.position), "scale": _vector(foot.scale), "disabled": foot.disabled}


func _world_rect(collision: CollisionShape2D) -> Rect2:
	# A scaled local size is not a world AABB: the actual male foot is rotated
	# 90 degrees. Transform every corner so approach and stop support are real.
	var local_rect := collision.shape.get_rect()
	var world_rect := Rect2(collision.global_transform * local_rect.position, Vector2.ZERO)
	for corner in [local_rect.end, Vector2(local_rect.end.x, local_rect.position.y), Vector2(local_rect.position.x, local_rect.end.y)]:
		world_rect = world_rect.expand(collision.global_transform * corner)
	return world_rect


func _geometry_snapshot(collision: CollisionShape2D) -> Dictionary:
	var snapshot := _shape_snapshot(collision)
	var world_rect := _world_rect(collision)
	snapshot.shape_class = collision.shape.get_class()
	snapshot.local_size = _vector(collision.shape.get_rect().size)
	snapshot.world_aabb_position = _vector(world_rect.position)
	snapshot.world_aabb_size = _vector(world_rect.size)
	return snapshot


func _shapes_overlap(first: CollisionShape2D, second: CollisionShape2D) -> bool:
	# Use the physics shapes themselves, not an AABB corner approximation.
	return first.shape.collide(first.global_transform, second.shape, second.global_transform)


func _approach_position(actor_foot: CollisionShape2D, player: CharacterBody2D, player_shape: CollisionShape2D, side: Vector2, gap: float) -> Vector2:
	var actor_rect := _world_rect(actor_foot)
	var player_rect := _world_rect(player_shape)
	var support := actor_rect.size * 0.5 + player_rect.size * 0.5 + Vector2(gap, gap)
	var player_offset := player_shape.global_position - player.global_position
	return actor_rect.get_center() + side * support - player_offset


func _probe_actor(scene: Node, actor: CharacterBody2D, actor_name: String, player: CharacterBody2D, player_shape: CollisionShape2D) -> void:
	var sensor := _find_component(actor, "Area2D") as Area2D
	var component := _find_component(actor, "InteractableArea")
	var actor_foot := _foot(actor)
	var sensor_shape := sensor.get_node_or_null("CollisionShape2D") as CollisionShape2D if sensor != null else null
	if sensor == null or component == null or actor_foot == null or sensor_shape == null:
		_expect(false, actor_name + " fixture contains source sensor/component/foot")
		return
	for side_index in SIDES.size():
		var side: Vector2 = SIDES[side_index]
		var label: String = actor_name + " " + String(SIDE_NAMES[side_index])
		player.global_position = OUTSIDE
		await _physics_frames(4)
		player.global_position = _approach_position(actor_foot, player, player_shape, side, NEAR_GAP)
		await _physics_frames(5)
		var physical_overlap := _shapes_overlap(actor_foot, player_shape)
		var expected_overlap := _shapes_overlap(sensor_shape, player_shape)
		var actual_overlap := sensor.get_overlapping_bodies().has(player)
		var can_interact: bool = component.call("can_interact")
		_expect(not physical_overlap, label + " near probe remains 0.5px outside the real solid feet")
		_expect(actual_overlap == expected_overlap and can_interact == actual_overlap, label + " real sensor entry and component eligibility match preserved geometry")
		var corrected := actor_name in CORRECTED_CIVILIANS
		var ready: bool = bool(geometry_ready.get(actor_name, false))
		if corrected and ready:
			_expect(actual_overlap and can_interact, label + " corrected proximity is reachable without entering solid collision")
		elif corrected:
			deferred_range_assertions += 1
		proximity_observations.append({"actor": actor_name, "side": SIDE_NAMES[side_index], "near_gap": NEAR_GAP, "near_sensor_overlap": actual_overlap, "near_can_interact": can_interact, "near_solid_overlap": physical_overlap, "target_geometry_ready": ready, "reference_side_physically_reachable": expected_overlap, "sensor": _geometry_snapshot(sensor_shape), "npc_foot": _geometry_snapshot(actor_foot), "player_foot": _geometry_snapshot(player_shape)})
		if actual_overlap and can_interact:
			for input_kind in ["ACT", "E", "Space"]:
				await _near_dialogue(scene, actor, label, String(input_kind))
		player.global_position = _approach_position(actor_foot, player, player_shape, side, FAR_GAP)
		await _physics_frames(5)
		_expect(not sensor.get_overlapping_bodies().has(player) and not bool(component.call("can_interact")), label + " 32px gap exits the sensor and rejects far interaction")
		for input_kind in ["ACT", "E", "Space"]:
			_press(scene, String(input_kind), true)
			await _frames(3)
			_expect(not bool(scene.get_node("CanvasLayer/Panel").call("is_dialogue_active")), label + " far " + String(input_kind) + " cannot open dialogue")
			_press(scene, String(input_kind), false)
			await _frames(3)
		await _physical_stop(scene, actor, actor_name, player, player_shape, side_index)
	player.global_position = OUTSIDE
	await _physics_frames(4)


func _near_dialogue(scene: Node, actor: CharacterBody2D, label: String, input_kind: String) -> void:
	var ui := scene.get_node("CanvasLayer/Panel")
	var before_events := activity_events
	var before_saves: int = state.fixture_save_count
	var closed := [0]
	var callback := func() -> void: closed[0] += 1
	ui.connect("dialogue_closed", callback)
	_press(scene, input_kind, true)
	await _frames(10)
	var opened: bool = ui.call("is_dialogue_active")
	_expect(opened and int(ui.call("get_dialogue_line_index")) == 0 and closed[0] == 0, label + " near " + input_kind + " held press opens exactly one line")
	if opened:
		_expect(String(scene.get_node("CanvasLayer/DialoguePanel/DialogueLabel").text) == "Hello traveler! Welcome to our town.", label + " " + input_kind + " preserves original greeting")
		_expect(_button(scene).is_visible_in_tree() and not _button(scene, "up").is_visible_in_tree(), label + " dialogue preserves ACT and movement hide rules")
		var before := actor.global_position
		actor.set("_idle_remaining", 0.0)
		actor.call("_begin_leg", Vector2.RIGHT)
		actor.set_physics_process(true)
		await _physics_frames(5)
		_expect(actor.global_position.distance_to(before) < 0.001 and actor.velocity.is_zero_approx(), label + " dialogue pauses an otherwise ready moving actor")
	_press(scene, input_kind, false)
	await _frames(4)
	if opened:
		_press(scene, input_kind, true)
		await _frames(8)
		_expect(not bool(ui.call("is_dialogue_active")) and closed[0] == 1, label + " " + input_kind + " next held press closes exactly once")
		_press(scene, input_kind, false)
		await _frames(4)
		await _physics_frames(3)
		_expect(state.get_mode() == state.GameMode.EXPLORATION and _button(scene, "up").is_visible_in_tree(), label + " close restores exploration and world controls")
		_expect(float(actor.get("_idle_remaining")) > 0.0, label + " dialogue resume starts the approved idle phase")
	actor.set_physics_process(false)
	actor.velocity = Vector2.ZERO
	_expect(activity_events == before_events and state.fixture_save_count == before_saves and state.current_task_index == 2, label + " greeting leaves quest/save/activity state unchanged")
	ui.disconnect("dialogue_closed", callback)


func _physical_stop(scene: Node, actor: CharacterBody2D, actor_name: String, player: CharacterBody2D, player_shape: CollisionShape2D, side_index: int) -> void:
	var actor_foot := _foot(actor)
	var side: Vector2 = SIDES[side_index]
	player.global_position = _approach_position(actor_foot, player, player_shape, side, NEAR_GAP)
	await _physics_frames(3)
	var hit_actor := false
	var collision_frames := 0
	var never_passed_through := true
	var minimum_support_gap := INF
	var actor_before := actor.global_position
	var player_before := player.global_position
	player.set_physics_process(true)
	_touch(scene, true, String(APPROACH_INPUTS[side_index]))
	var commanded_direction := Vector2.ZERO
	var commanded_frames := 0
	var unexpected_direction_frames := 0
	for frame in 24:
		await get_tree().physics_frame
		# Mobile press flags are synchronous, but InputManager publishes its
		# movement vector in _process. Observe the held input during actual
		# physics instead of reading the preceding frame immediately on press.
		commanded_direction = inputs.get_movement_vector()
		if commanded_direction.is_equal_approx(-side):
			commanded_frames += 1
		elif not commanded_direction.is_zero_approx():
			unexpected_direction_frames += 1
		var frame_hit := false
		for collision_index in player.get_slide_collision_count():
			frame_hit = frame_hit or player.get_slide_collision(collision_index).get_collider() == actor
		hit_actor = hit_actor or frame_hit
		if frame_hit:
			collision_frames += 1
		var support_gap := _physical_support_gap(actor_foot, player_shape, side)
		minimum_support_gap = minf(minimum_support_gap, support_gap)
		never_passed_through = never_passed_through and support_gap >= -0.01
	_touch(scene, false, String(APPROACH_INPUTS[side_index]))
	await _physics_frames(2)
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	var final_support_gap := _physical_support_gap(actor_foot, player_shape, side)
	var separated := final_support_gap >= -0.01
	collision_observations.append({"actor": actor_name, "side": SIDE_NAMES[side_index], "commanded_direction": _vector(commanded_direction), "commanded_frames": commanded_frames, "unexpected_direction_frames": unexpected_direction_frames, "player_start": _vector(player_before), "player_end": _vector(player.global_position), "collision_frames": collision_frames, "minimum_support_gap": minimum_support_gap, "final_support_gap": final_support_gap, "never_passed_through": never_passed_through, "actor_displacement": actor.global_position.distance_to(actor_before), "player_foot": _geometry_snapshot(player_shape), "npc_foot": _geometry_snapshot(actor_foot)})
	_expect(commanded_frames > 0 and unexpected_direction_frames == 0 and commanded_direction.is_equal_approx(-side) and hit_actor and never_passed_through and separated and actor.global_position.distance_to(actor_before) < 0.001, actor_name + " " + String(SIDE_NAMES[side_index]) + " actual player D-pad motion collides with unchanged foot and cannot pass through")


func _physical_support_gap(actor_foot: CollisionShape2D, player_shape: CollisionShape2D, side: Vector2) -> float:
	var gap_vector := (_world_rect(player_shape).get_center() - _world_rect(actor_foot).get_center()) * side
	var support := (_world_rect(player_shape).size + _world_rect(actor_foot).size) * 0.5
	return gap_vector.x - support.x if absf(side.x) > 0.0 else gap_vector.y - support.y


func _finish_major() -> void:
	var failed := 0
	for check in checks:
		if not bool(check.passed):
			failed += 1
	var target_ready := true
	for actor_name in CORRECTED_CIVILIANS:
		target_ready = target_ready and bool(geometry_ready.get(actor_name, false))
	var result := {"fixture_revision": FIXTURE_REVISION, "checks": checks, "passed": checks.size() - failed, "failed": failed, "source_snapshots": source_snapshots, "proximity_observations": proximity_observations, "collision_observations": collision_observations, "movement_observations": observed, "target_geometry_ready": target_ready, "deferred_range_assertions": deferred_range_assertions, "http_request_count": http_request_count, "live_network_calls": 0, "human_recheck_pending": true}
	_write_json(MAJOR_RESULT, result)
	if not target_ready and not FileAccess.file_exists(MAJOR_BEFORE):
		_write_json(MAJOR_BEFORE, result)
	print("MAJOR_NPC_PROXIMITY_TEST " + JSON.stringify({"failed": failed, "passed": checks.size() - failed, "target_geometry_ready": target_ready, "deferred_range_assertions": deferred_range_assertions}))
	get_tree().quit(1 if failed > 0 else 0)
