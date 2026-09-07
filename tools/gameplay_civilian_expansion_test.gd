extends "res://tools/preservation_restoration_test.gd"
## Node-root canonical MCP harness. Product scenes stay real; transport is removed
## before any fixture profile. The first run records the immutable pre-edit geometry.

const BASELINE_PATH := "res://docs/qa/2026-09-07-civilian-expansion-runtime-baseline.json"
const RESULT_PATH := "res://docs/qa/2026-09-07-civilian-expansion-runtime-tests.json"
const MAP_CASES := [
	{"path": "res://scenes/oak_leaf_village.tscn", "civilians": ["girl_npc", "NPC", "villager-female", "NPC1"], "enemies": ["Bandits", "Bandits2", "Bandits3", "Bandits4", "Bandits5", "Boss-Bandit"]},
	{"path": "res://scenes/city_of_knowledge.tscn", "civilians": ["adult-male_npc", "city_npc", "old_adult_women", "old_npc", "girl_npc"], "enemies": ["Bandits", "Bandits2", "Bandits3", "Bandits4", "Bandits5"]},
	{"path": "res://scenes/pinehill_village.tscn", "civilians": ["old_adult_women", "old_npc", "male-npc", "girl_npc", "villager-male", "villager-female"], "enemies": ["Bandits", "Bandits2", "Bandits3", "Bandits4", "Boss-Wizard"]},
]
const OUTSIDE := Vector2(-4000, -4000)
var captured: Dictionary = {}
var baseline: Dictionary = {}
var observed: Array[Dictionary] = []
var activity_events := 0


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		var live_node := get_node_or_null("/root/" + autoload_name)
		if live_node != null:
			live_node.free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.fixture_path = "user://saves/gameplay_civilian_expansion_%d.json" % Time.get_ticks_usec()
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	state.start_new_game(PROFILE, false)
	state.current_task_index = 2
	state._tutorial_activity_completed = true
	state.canonical_activity_boundary.connect(func(_event: Dictionary) -> void: activity_events += 1)
	if FileAccess.file_exists(BASELINE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
		if parsed is Dictionary:
			baseline = parsed
	_expect(get_node_or_null("/root/RemoteSync") == null and get_node_or_null("/root/HttpApi") == null, "Real production transports are absent before world fixtures")
	var actor_count := 0
	var civilian_count := 0
	for map_case in MAP_CASES:
		var scene := await _load(String(map_case.path))
		_freeze_actors(scene)
		var player := get_tree().get_first_node_in_group("player_character") as Node2D
		if player != null:
			player.set_physics_process(false)
			player.global_position = OUTSIDE
		await _physics_frames(3)
		var snapshot := _snapshot_map(scene, map_case)
		captured[String(map_case.path)] = snapshot
		if baseline.has(String(map_case.path)):
			_expect(_same(snapshot, baseline[String(map_case.path)]), String(map_case.path) + " preserves every civilian visual/sensor/foot footprint and all protected serialized map nodes")
		actor_count += map_case.civilians.size() + map_case.enemies.size()
		civilian_count += map_case.civilians.size()
		_contracts(scene, map_case)
		await _world_motion(scene, map_case)
	_expect(actor_count == 31 and civilian_count == 15, "Inventory covers all 31 outdoor actors and all 15 civilians without double-counting nested Visual instances")
	if baseline.is_empty():
		_write_json(BASELINE_PATH, captured)
		print("CIVILIAN_BASELINE_CAPTURED " + BASELINE_PATH)
	else:
		_expect(baseline.size() == MAP_CASES.size(), "Pre-edit baseline contains exactly the three canonical outdoor maps")
	await _oakleaf_dialogue()
	await _physics_collision_fixtures()
	var failed := 0
	for check in checks:
		if not bool(check.passed):
			failed += 1
	_write_json(RESULT_PATH, {"checks": checks, "observed": observed, "captured": captured, "failed": failed, "passed": checks.size() - failed, "baseline": BASELINE_PATH, "production_transports_present": false, "human_recheck_pending": true})
	# This path is a unique test-owned save, never a human save or recovery artifact.
	if FileAccess.file_exists(state.fixture_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	print("GAMEPLAY_CIVILIAN_EXPANSION_TEST " + JSON.stringify({"failed": failed, "passed": checks.size() - failed}))
	get_tree().quit(0 if failed == 0 else 1)


func _physics_frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame


func _write_json(path: String, data: Variant) -> void:
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		_expect(false, "Test evidence file opens: " + path)
	if output != null:
		output.store_string(JSON.stringify(data, "\t"))
		output.close()


func _freeze_actors(scene: Node) -> void:
	for candidate in scene.find_children("*", "CharacterBody2D", true, false):
		candidate.set_physics_process(false)


func _visual(actor: Node) -> AnimatedSprite2D:
	if actor is AnimatedSprite2D:
		return actor as AnimatedSprite2D
	if actor == null:
		return null
	for child in actor.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D
	return null


func _find_component(actor: Node, node_name: String) -> Node:
	if actor == null:
		return null
	return actor.find_child(node_name, true, false)


func _vector(value: Vector2) -> Array:
	return [value.x, value.y]


func _transform(value: Transform2D) -> Array:
	return [_vector(value.x), _vector(value.y), _vector(value.origin)]


func _shape_snapshot(collision: CollisionShape2D) -> Dictionary:
	if collision == null or collision.shape == null:
		return {}
	return {"center": _vector(collision.global_position), "size": _vector(collision.shape.get_rect().size * collision.global_scale.abs()), "rotation": collision.global_rotation, "disabled": collision.disabled}


func _foot(actor: Node) -> CollisionShape2D:
	if actor == null:
		return null
	var collision := actor.get_node_or_null("FootCollision") as CollisionShape2D
	if collision != null:
		return collision
	var sprite := _visual(actor)
	return sprite.get_node_or_null("NpcBodyCollision/CollisionShape2D") as CollisionShape2D if sprite != null else null


func _snapshot_map(scene: Node, map_case: Dictionary) -> Dictionary:
	var civilians := {}
	for actor_name in map_case.civilians:
		var actor := scene.get_node_or_null(String(actor_name)) as Node2D
		var sprite := _visual(actor)
		_expect(actor != null and sprite != null, String(actor_name) + " actor and preserved visual exist for baseline")
		if actor == null or sprite == null:
			continue
		var sensor := _find_component(actor, "Area2D")
		var sensor_shape := sensor.get_node_or_null("CollisionShape2D") as CollisionShape2D if sensor != null else null
		civilians[String(actor_name)] = {"home": _vector(actor.global_position), "visual_transform": _transform(sprite.global_transform), "animation": String(sprite.animation), "frame": sprite.frame, "sprite_frames": sprite.sprite_frames.resource_path, "foot": _shape_snapshot(_foot(actor)), "sensor": _shape_snapshot(sensor_shape)}
	var protected_nodes := {}
	_capture_protected(scene, scene, map_case.civilians, protected_nodes)
	return {"civilians": civilians, "protected_nodes": protected_nodes}


func _capture_protected(scene: Node, node: Node, civilians: Array, result: Dictionary) -> void:
	var path := String(scene.get_path_to(node))
	for actor_name in civilians:
		if path == String(actor_name) or path.begins_with(String(actor_name) + "/"):
			return
	# owner-free children are runtime HUD/player/collision instances, not map content.
	if node == scene or node.owner != null:
		var row := {"class": node.get_class(), "scene_file_path": node.scene_file_path}
		var script := node.get_script() as Script
		row.script = script.resource_path if script != null else ""
		if node is Node2D:
			row.transform = _transform((node as Node2D).transform)
		if node is CollisionShape2D:
			row.collision = _shape_snapshot(node as CollisionShape2D)
		if node is CollisionObject2D:
			row.collision_layer = (node as CollisionObject2D).collision_layer
			row.collision_mask = (node as CollisionObject2D).collision_mask
		if node is AnimatedSprite2D:
			row.animation = String((node as AnimatedSprite2D).animation)
			row.frame = (node as AnimatedSprite2D).frame
		if node is TileMapLayer:
			var tile_bytes: PackedByteArray = node.get("tile_map_data")
			row.tile_cells_sha256 = tile_bytes.hex_encode().sha256_text()
			row.tile_set = (node as TileMapLayer).tile_set.resource_path
		result[path] = row
	for child in node.get_children():
		if child.owner != null:
			_capture_protected(scene, child, civilians, result)


func _same(left: Variant, right: Variant) -> bool:
	if (left is float or left is int) and (right is float or right is int):
		return absf(float(left) - float(right)) < 0.002
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _same(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _same(left[index], right[index]):
				return false
		return true
	return left == right


func _contracts(scene: Node, map_case: Dictionary) -> void:
	for actor_name in map_case.civilians:
		var actor := scene.get_node_or_null(String(actor_name))
		var label: String = String(map_case.path) + "/" + String(actor_name)
		_expect(actor is CharacterBody2D, label + " is an opt-in collision-aware civilian CharacterBody2D")
		if not actor is CharacterBody2D:
			continue # Red baseline: exactly ten static actors must fail cleanly here.
		var script := actor.get_script() as Script
		var approved := script != null and script.resource_path == "res://scripts/decorative_npc_wanderer.gd"
		_expect(approved and actor.is_in_group("decorative_wanderer"), label + " uses the existing shared movement implementation")
		if not approved:
			continue
		_expect(is_equal_approx(float(actor.get("walk_speed")), 30.0) and is_equal_approx(float(actor.get("wander_radius")), 42.0) and float(actor.get("idle_seconds")) > 0.0, label + " retains 30 px/s, home-relative radius and idle periods")
		_expect((actor as CharacterBody2D).collision_layer == 2 and (actor as CharacterBody2D).collision_mask == 1 and _foot(actor) != null, label + " has explicit solid foot collision on the approved layers")
		_expect(not actor.is_in_group("player") and not actor.is_in_group("player_character"), label + " cannot impersonate the player in door/task triggers")
		if String(map_case.path) != OAK:
			_expect(_find_component(actor, "InteractableArea") == null and not _visual(actor).has_method("interact"), label + " remains NO SOURCE-SUPPORTED DIALOGUE without invented interaction")
	for enemy_name in map_case.enemies:
		var enemy := scene.get_node_or_null(String(enemy_name))
		_expect(enemy != null, String(enemy_name) + " protected encounter actor remains present")
		if enemy == null:
			continue
		if String(map_case.path) == CITY:
			_expect(enemy is CharacterBody2D and enemy.is_in_group("decorative_wanderer"), String(enemy_name) + " preserves approved City Bandit movement")
		else:
			_expect(enemy is AnimatedSprite2D, String(enemy_name) + " stays fixed and outside civilian wandering")


func _world_motion(scene: Node, map_case: Dictionary) -> void:
	var movers: Array[CharacterBody2D] = []
	var observations := {}
	for actor_name in map_case.civilians:
		var actor := scene.get_node_or_null(String(actor_name)) as CharacterBody2D
		if actor == null or not actor.has_method("_enter_idle"):
			continue
		movers.append(actor)
		actor.call("_enter_idle")
		observations[String(actor.name)] = {"home": actor.global_position, "previous": actor.global_position, "moved": false, "blocked": false, "bounded": true, "speed": true, "initial_idle": true}
		actor.set_physics_process(true)
	state.set_mode(state.GameMode.EXPLORATION)
	for frame in 420:
		await get_tree().physics_frame
		for actor in movers:
			var row: Dictionary = observations[String(actor.name)]
			var distance: float = actor.global_position.distance_to(row.previous)
			row.moved = bool(row.moved) or distance > 0.01
			row.blocked = bool(row.blocked) or actor.get_slide_collision_count() > 0
			row.bounded = bool(row.bounded) and actor.global_position.distance_to(row.home) <= 42.5
			row.speed = bool(row.speed) and distance <= 30.0 * actor.get_physics_process_delta_time() + 0.15
			if frame < 20:
				row.initial_idle = bool(row.initial_idle) and actor.global_position.distance_to(row.home) < 0.01
			row.previous = actor.global_position
	for actor in movers:
		actor.set_physics_process(false)
		var row: Dictionary = observations[String(actor.name)]
		_expect(bool(row.initial_idle) and bool(row.bounded) and bool(row.speed) and (bool(row.moved) or bool(row.blocked)), String(map_case.path) + "/" + String(actor.name) + " idles then moves or physically blocks inside its home bounds at the approved speed")
		observed.append({"map": map_case.path, "actor": actor.name, "motion": {"moved": row.moved, "blocked": row.blocked, "bounded": row.bounded, "speed": row.speed, "initial_idle": row.initial_idle}})


func _oakleaf_dialogue() -> void:
	for actor_name in ["girl_npc", "villager-female", "NPC", "NPC1"]:
		for input_kind in ["ACT", "E", "Space"]:
			state.current_task_index = 2
			var scene := await _load(OAK)
			_freeze_actors(scene)
			var actor := scene.get_node_or_null(actor_name) as Node2D
			var target := _visual(actor)
			var component := _find_component(actor, "InteractableArea")
			var sensor := _find_component(actor, "Area2D") as Area2D
			var sensor_shape := sensor.get_node_or_null("CollisionShape2D") as CollisionShape2D if sensor != null else null
			var player := get_tree().get_first_node_in_group("player_character") as Node2D
			var ui := scene.get_node_or_null("CanvasLayer/Panel")
			var label: String = actor_name + " " + input_kind
			var valid: bool = actor != null and target != null and component != null and sensor_shape != null and player != null and ui != null
			_expect(valid, label + " has actual source target, sensor, player and dialogue host")
			if not valid:
				continue
			_expect(target.has_method("interact") and target.has_method("_get_quest_ui") and target.call("_get_quest_ui") == ui, label + " resolves the preserved shared greeting host")
			if not target.has_method("interact") or not component.has_method("can_interact"):
				continue
			if actor_name == "NPC1":
				_expect(target.is_in_group("Player") and not actor.is_in_group("player") and not actor.is_in_group("player_character"), "NPC1 preserves only its legacy uppercase Player group on the visual")
			player.global_position = OUTSIDE
			await _physics_frames(5)
			player.global_position = sensor_shape.global_position
			await _physics_frames(5)
			_expect(sensor.get_overlapping_bodies().has(player) and bool(component.call("can_interact")), label + " real physical entry enables interaction")
			var prior_events := activity_events
			var prior_saves: int = state.fixture_save_count
			var prior_quest: String = state.current_quest
			var closed := [0]
			ui.connect("dialogue_closed", func() -> void: closed[0] += 1)
			_press(scene, input_kind, true)
			await _frames(16)
			var opened: bool = ui.call("is_dialogue_active")
			_expect(opened and int(ui.call("get_dialogue_line_index")) == 0 and closed[0] == 0, label + " one held opening press shows exactly one preserved greeting")
			if opened:
				_expect(String(scene.get_node("CanvasLayer/DialoguePanel/DialogueLabel").text) == "Hello traveler! Welcome to our town.", label + " displays the exact source-supported text")
				_expect(_button(scene).is_visible_in_tree() and not _button(scene, "up").is_visible_in_tree(), label + " dialogue retains ACT and hides movement")
				var dialogue_panel := scene.get_node("CanvasLayer/DialoguePanel") as Control
				var center := dialogue_panel.get_global_rect().get_center()
				var viewport_size := dialogue_panel.get_viewport_rect().size
				_expect(absf(center.x - viewport_size.x * 0.5) < 2.0 and absf(viewport_size.y - dialogue_panel.get_global_rect().end.y - 40.0) < 1.5, label + " retains the authorized bottom-center dialogue placement")
				if actor is CharacterBody2D:
					actor.set_physics_process(true)
					var before := actor.global_position
					await _physics_frames(10)
					_expect(actor.global_position.distance_to(before) < 0.01 and (actor as CharacterBody2D).velocity.is_zero_approx(), label + " actual dialogue mode pauses bounded movement")
			_press(scene, input_kind, false)
			await _frames(4)
			if opened:
				_press(scene, input_kind, true)
				await _frames(12)
				_expect(not bool(ui.call("is_dialogue_active")) and closed[0] == 1, label + " one deliberate next press closes once")
				_press(scene, input_kind, false)
				await _frames(4)
			_expect(state.current_task_index == 2 and String(state.current_quest) == prior_quest and state.fixture_save_count == prior_saves and activity_events == prior_events and not state.battle_active, label + " greeting causes no quest, save, activity or battle side effect")
			player.global_position = OUTSIDE
			await _physics_frames(5)
			_expect(not sensor.get_overlapping_bodies().has(player) and not bool(component.call("can_interact")), label + " leaving the real sensor unregisters interaction")
			if actor is CharacterBody2D and opened:
				var before_resume := actor.global_position
				await _physics_frames(120)
				_expect(state.get_mode() == state.GameMode.EXPLORATION and actor.global_position.distance_to(actor.get("_home_position")) <= 42.5 and (actor.global_position.distance_to(before_resume) > 0.01 or (actor as CharacterBody2D).get_slide_collision_count() > 0), label + " safely resumes bounded movement after dialogue")


func _press(scene: Node, kind: String, pressed: bool) -> void:
	if kind == "ACT":
		_touch(scene, pressed)
	else:
		_key(pressed, KEY_E if kind == "E" else KEY_SPACE)


func _physics_collision_fixtures() -> void:
	# A separate collision lane uses copies of the actual configured map actors.
	# Their _ready home initializes at the lane; no live product actor is teleported.
	for map_case in MAP_CASES:
		var scene := await _load(String(map_case.path))
		_freeze_actors(scene)
		for actor_name in map_case.civilians:
			var original := scene.get_node_or_null(String(actor_name)) as CharacterBody2D
			if original == null or not original.has_method("_begin_leg"):
				continue
			var lane := Node2D.new()
			lane.position = Vector2(-8000, -8000)
			add_child(lane)
			var actor := original.duplicate() as CharacterBody2D
			actor.position = Vector2.ZERO
			actor.set_physics_process(false)
			lane.add_child(actor)
			var foot := _foot(actor)
			if foot == null or foot.shape == null:
				_expect(false, String(actor_name) + " cloned physical actor retains its foot collider")
				lane.queue_free()
				await _physics_frames(2)
				continue
			var blocker := CharacterBody2D.new()
			blocker.name = "PlayerCollisionFixture"
			blocker.add_to_group("player")
			blocker.collision_layer = 1
			blocker.collision_mask = 2
			var collision := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(10, 36)
			collision.shape = rectangle
			blocker.add_child(collision)
			lane.add_child(blocker)
			blocker.global_position = foot.global_position + Vector2(foot.shape.get_rect().size.x * absf(foot.global_scale.x) * 0.5 + 8.0, 0)
			await _physics_frames(2)
			actor.set("_idle_remaining", 0.0)
			actor.call("_begin_leg", Vector2.RIGHT)
			actor.set_physics_process(true)
			var hit_player := false
			var bounded := true
			for frame in 45:
				await get_tree().physics_frame
				bounded = bounded and actor.global_position.distance_to(actor.get("_home_position")) <= 42.5
				for index in actor.get_slide_collision_count():
					hit_player = hit_player or actor.get_slide_collision(index).get_collider() == blocker
			var stopped := actor.global_position
			_expect(hit_player and bounded and foot.global_position.x < blocker.global_position.x, String(map_case.path) + "/" + String(actor_name) + " move_and_slide collides with player layer and never passes through")
			blocker.queue_free()
			await _physics_frames(2)
			actor.set("_idle_remaining", 0.0)
			await _physics_frames(30)
			_expect(actor.global_position.x > stopped.x and actor.global_position.distance_to(actor.get("_home_position")) <= 42.5, String(actor_name) + " resumes without teleport after the player blocker leaves")
			lane.queue_free()
			await _physics_frames(2)
