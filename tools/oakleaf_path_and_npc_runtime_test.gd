extends Node

const OAKLEAF := "res://scenes/oak_leaf_village.tscn"
const BLOCKER_PATH := "Bandits/BanditTaskTrigger/StaticBody2D/CollisionShape2D"
const TRIGGER_PATH := "Bandits/BanditTaskTrigger"
const CIVILIANS := ["NPC1", "NPC", "girl_npc", "villager-female"]
const REQUIRED_MOVERS := ["NPC", "girl_npc", "villager-female"]

var _failures: Array[String] = []
var _observed: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	_remove_live_services()
	GameState.start_new_game({
		"player_name": "Oakleaf Path QA",
		"gender": "male",
		"grade_level": "Grade 1",
		"student_id": "88000003",
		"parent_id": "880003",
	}, false)
	GameState.current_task_index = 2
	GameState.current_quest = GameState.get_current_quest_text()
	_assert(await _load_scene(OAKLEAF), "Canonical Oakleaf scene loads")
	await _physics_frames(5)

	var scene := get_tree().current_scene
	var blocker_shape := scene.get_node_or_null(BLOCKER_PATH) as CollisionShape2D
	var blocker_body := blocker_shape.get_parent() as StaticBody2D if blocker_shape != null else null
	var trigger := scene.get_node_or_null(TRIGGER_PATH) as Area2D
	var trigger_shape := trigger.get_node_or_null("CollisionShape2D") as CollisionShape2D if trigger != null else null
	var player := get_tree().get_first_node_in_group("player_character") as CharacterBody2D
	_assert(blocker_shape != null and blocker_body != null, "Legacy path blocker is identified at the exact canonical node")
	_assert(trigger != null and trigger_shape != null and trigger.get_script().resource_path == "res://scripts/interactable_area.gd", "First Bandit uses a separate interaction Area2D sensor")
	_assert(blocker_body.collision_layer == 1 and blocker_body.collision_mask == 1, "Legacy nested StaticBody uses physical world collision layer 1")
	if blocker_shape != null and blocker_shape.shape is RectangleShape2D:
		var rectangle := blocker_shape.shape as RectangleShape2D
		_observed["blocker"] = {
			"node_path": str(blocker_shape.get_path()),
			"parent": str(blocker_body.get_path()),
			"disabled": blocker_shape.disabled,
			"local_size": str(rectangle.size),
			"world_size": str(rectangle.size * blocker_shape.global_scale.abs()),
			"world_position": str(blocker_shape.global_position),
			"collision_layer": blocker_body.collision_layer,
			"collision_mask": blocker_body.collision_mask,
		}
	_assert(blocker_shape != null and blocker_shape.disabled, "Interaction trigger's legacy StaticBody is non-physical")
	_assert(player != null, "Canonical Oakleaf creates the actual player CharacterBody2D")
	if player != null and blocker_shape != null:
		player.set_physics_process(false)
		# The legacy wall spans several existing props. Probe its full height and
		# require an actual open path in both directions, rather than mistaking a
		# legitimate prop/foot collision for the obsolete trigger wall.
		var crossing_attempts: Array[Dictionary] = []
		var open_crossing: Dictionary = {}
		for y_offset in [-32.0, -24.0, -16.0, -8.0, 0.0, 8.0, 16.0, 24.0, 32.0]:
			var center := blocker_shape.global_position + Vector2(0, y_offset)
			var left_to_right := await _cross_path(player, center, Vector2.RIGHT)
			var right_to_left := await _cross_path(player, center, Vector2.LEFT)
			var attempt := {
				"y_offset": y_offset,
				"left_to_right": left_to_right,
				"right_to_left": right_to_left,
			}
			crossing_attempts.append(attempt)
			if bool(left_to_right.get("passed", false)) and bool(right_to_left.get("passed", false)):
				open_crossing = attempt
				break
		_observed["path_crossing_attempts"] = crossing_attempts
		_assert(not open_crossing.is_empty(), "Player crosses an actual former-wall path from both directions")
		player.global_position = trigger_shape.global_position
		await _physics_frames(4)
		_assert(trigger.can_interact(), "First Bandit interaction Area2D still detects the nearby player")
		player.global_position = Vector2(-4000, -4000)
		await _physics_frames(3)

	await _verify_actual_civilian_cycles(scene)
	await _verify_collision_recovery(scene)
	_verify_interaction_and_foot_geometry(scene)
	_finish()


func _cross_path(player: CharacterBody2D, center: Vector2, direction: Vector2) -> Dictionary:
	var start := center - direction * 22.0
	var target := center + direction * 22.0
	player.global_position = start
	player.velocity = Vector2.ZERO
	await _physics_frames(3)
	for _step in 45:
		player.velocity = direction * 120.0
		player.move_and_slide()
		await get_tree().physics_frame
		if (player.global_position - target).dot(direction) >= 0.0:
			break
	player.velocity = Vector2.ZERO
	return {
		"start": str(start),
		"target": str(target),
		"end": str(player.global_position),
		"passed": (player.global_position - center).dot(direction) > 12.0,
	}


func _verify_actual_civilian_cycles(scene: Node) -> void:
	var actors: Dictionary = {}
	var motion: Dictionary = {}
	for actor_name in CIVILIANS:
		var actor := scene.get_node_or_null(actor_name) as CharacterBody2D
		_assert(actor != null, "%s exists as the canonical CharacterBody2D" % actor_name)
		if actor == null:
			continue
		actor.set_physics_process(false)
		actors[actor_name] = actor
		motion[actor_name] = {
			"home": actor.get("_home_position"),
			"last": actor.global_position,
			"moving": false,
			"movement_segments": 0,
			"movement_frames": 0,
			"max_idle_streak": 0,
			"idle_streak": 0,
			"last_move_step": -1,
			"max_radius": 0.0,
			"cardinal": true,
		}
		_assert(actor.get_script().resource_path == "res://scripts/decorative_npc_wanderer.gd", "%s shares NPC1's bounded wander script" % actor_name)
		_assert(is_equal_approx(float(actor.get("walk_speed")), 30.0) and is_equal_approx(float(actor.get("wander_radius")), 42.0), "%s preserves speed 30 and home radius 42" % actor_name)

	for step in 900:
		for actor_name in actors:
			var actor: CharacterBody2D = actors[actor_name]
			var row: Dictionary = motion[actor_name]
			var before := actor.global_position
			actor.call("_physics_process", 0.1)
			var moved := actor.global_position.distance_to(before) > 0.005
			if moved:
				row.movement_frames = int(row.movement_frames) + 1
				row.last_move_step = step
				if not bool(row.moving):
					row.movement_segments = int(row.movement_segments) + 1
				row.moving = true
				row.idle_streak = 0
			else:
				row.moving = false
				row.idle_streak = int(row.idle_streak) + 1
				row.max_idle_streak = maxi(int(row.max_idle_streak), int(row.idle_streak))
			var velocity: Vector2 = actor.velocity
			if not velocity.is_zero_approx() and not (is_zero_approx(velocity.x) or is_zero_approx(velocity.y)):
				row.cardinal = false
			row.max_radius = maxf(float(row.max_radius), actor.global_position.distance_to(row.home))
			row.last = actor.global_position
			motion[actor_name] = row
		await get_tree().physics_frame

	for actor_name in actors:
		var actor: CharacterBody2D = actors[actor_name]
		var row: Dictionary = motion[actor_name]
		_observed["movement_" + actor_name] = row.duplicate(true)
		_assert(int(row.movement_segments) >= 3 and int(row.last_move_step) >= 650, "%s repeatedly resumes walking after natural idle periods" % actor_name)
		_assert(float(row.max_radius) <= float(actor.get("wander_radius")) + 0.75, "%s remains inside its home bound" % actor_name)
		_assert(bool(row.cardinal), "%s retains four-direction movement" % actor_name)

	GameState.set_mode(GameState.GameMode.DIALOGUE)
	for actor_name in actors:
		var actor: CharacterBody2D = actors[actor_name]
		var before := actor.global_position
		actor.call("_physics_process", 0.1)
		_assert(actor.velocity.is_zero_approx() and actor.global_position.distance_to(before) < 0.001, "%s pauses during dialogue" % actor_name)
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	for actor_name in actors:
		var actor: CharacterBody2D = actors[actor_name]
		var before := actor.global_position
		for _step in 30:
			actor.call("_physics_process", 0.1)
			await get_tree().physics_frame
		_assert(actor.global_position.distance_to(before) > 0.5, "%s resumes after dialogue" % actor_name)


func _verify_collision_recovery(scene: Node) -> void:
	var source := scene.get_node_or_null("NPC") as CharacterBody2D
	if source == null:
		return
	var actor := source.duplicate() as CharacterBody2D
	actor.name = "CollisionRecoveryFixture"
	actor.global_position = Vector2(-5000, -5000)
	actor.set("idle_seconds", 0.1)
	scene.add_child(actor)
	actor.set_physics_process(false)
	await _physics_frames(2)
	var home: Vector2 = actor.get("_home_position")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 2
	var wall_collision := CollisionShape2D.new()
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(4, 36)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	scene.add_child(wall)
	wall.global_position = home + Vector2(14, 0)
	await _physics_frames(2)
	actor.call("_begin_leg", Vector2.RIGHT)
	var collided := false
	var moved_after_collision := false
	var collision_position := Vector2.ZERO
	for _step in 420:
		actor.call("_physics_process", 0.1)
		if actor.get_slide_collision_count() > 0 and not collided:
			collided = true
			collision_position = actor.global_position
		elif collided and actor.global_position.distance_to(collision_position) > 4.0:
			moved_after_collision = true
		await get_tree().physics_frame
	var within_home := actor.global_position.distance_to(home) <= float(actor.get("wander_radius")) + 0.75
	_observed["collision_recovery"] = {
		"collided": collided,
		"moved_after_collision": moved_after_collision,
		"home": str(home),
		"collision_position": str(collision_position),
		"end": str(actor.global_position),
	}
	_assert(collided, "Collision fixture reaches a real StaticBody obstacle")
	_assert(moved_after_collision, "Wanderer abandons a blocked leg and resumes another valid cycle")
	_assert(within_home, "Collision recovery does not drift outside the home bound")
	actor.queue_free()
	wall.queue_free()
	await _physics_frames(2)


func _verify_interaction_and_foot_geometry(scene: Node) -> void:
	for actor_name in ["girl_npc", "villager-female"]:
		var actor := scene.get_node_or_null(actor_name) as CharacterBody2D
		var sensor := actor.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D if actor != null else null
		var foot := actor.get_node_or_null("FootCollision") as CollisionShape2D if actor != null else null
		var sensor_size := Vector2.ZERO
		var foot_size := Vector2.ZERO
		if sensor != null and sensor.shape is RectangleShape2D:
			sensor_size = (sensor.shape as RectangleShape2D).size * sensor.global_scale.abs()
		if foot != null and foot.shape is RectangleShape2D:
			foot_size = (foot.shape as RectangleShape2D).size * foot.global_scale.abs()
		_assert(sensor != null and sensor_size.distance_to(Vector2(12, 10)) < 0.01, "%s keeps the nearby-only 12x10 interaction sensor" % actor_name)
		_assert(foot != null and foot_size.distance_to(Vector2(10, 8)) < 0.01, "%s keeps its separate unchanged 10x8 solid foot collision" % actor_name)


func _load_scene(path: String) -> bool:
	if get_tree().change_scene_to_file(path) != OK:
		return false
	for _step in 240:
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _physics_frames(count: int) -> void:
	for _step in count:
		await get_tree().physics_frame


func _remove_live_services() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		var service := get_node_or_null("/root/" + autoload_name)
		if service != null:
			service.free()


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var report := {
		"passed": 33 - _failures.size(),
		"failed": _failures.size(),
		"failures": _failures,
		"observed": _observed,
	}
	var file := FileAccess.open("res://tools/oakleaf_path_and_npc_runtime_test_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if _failures.is_empty():
		print("OAKLEAF_PATH_AND_NPC_RUNTIME_TEST PASSED")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("OAKLEAF_PATH_AND_NPC_RUNTIME_TEST FAILED")
	get_tree().quit(1)
