extends SceneTree

const WALK_SPEED := 30.0
const WANDER_RADIUS := 42.0

const WRAPPER_SCENES := {
	"existing city decorative NPC": "res://NPC/Npc/decorative_wandering_city_npc.tscn",
	"oakleaf girl": "res://NPC/Npc/wandering_girl_npc.tscn",
	"oakleaf villager": "res://NPC/Npc/wandering_villager_female.tscn",
	"pinehill elder": "res://NPC/Npc/wandering_old_npc.tscn",
	"pinehill villager": "res://NPC/Npc/wandering_villager_male.tscn",
	"city bandit": "res://NPC/Enemy/wandering_bandit.tscn",
}


func _init() -> void:
	var failed := false
	for label: String in WRAPPER_SCENES:
		var scene_path: String = WRAPPER_SCENES[label]
		failed = not _expect(
			ResourceLoader.exists(scene_path),
			"%s uses the approved bounded-wander wrapper: %s" % [label, scene_path]
		) or failed

	if failed:
		quit(1)
		return

	call_deferred("_run")


func _run() -> void:
	var failed := false
	for label: String in WRAPPER_SCENES:
		var scene := ResourceLoader.load(WRAPPER_SCENES[label]) as PackedScene
		var wanderer := scene.instantiate() as CharacterBody2D if scene != null else null
		failed = not _expect(wanderer != null, "%s wrapper instantiates a CharacterBody2D" % label) or failed
		if wanderer == null:
			continue

		root.add_child(wanderer)
		await physics_frame
		failed = not _expect(wanderer.is_in_group("decorative_wanderer"), "%s opts into the single collision-aware wanderer contract" % label) or failed
		failed = not _expect(is_equal_approx(float(wanderer.get("walk_speed")), WALK_SPEED), "%s uses the approved ambient speed" % label) or failed
		failed = not _expect(is_equal_approx(float(wanderer.get("wander_radius")), WANDER_RADIUS), "%s uses the approved home radius" % label) or failed
		failed = not _expect(wanderer.get_node_or_null("FootCollision") is CollisionShape2D, "%s has a foot collision shape" % label) or failed

		wanderer.call("_begin_leg", Vector2.RIGHT)
		var home: Vector2 = wanderer.get("_home_position")
		var target: Vector2 = wanderer.get("_target_position")
		failed = not _expect(target.distance_to(home) <= WANDER_RADIUS, "%s target stays inside its home radius" % label) or failed
		wanderer.queue_free()

	failed = not await _verify_dialogue_pause() or failed
	failed = not await _verify_collision_blocking_and_home_bounds() or failed
	failed = not _expect(_map_contract_is_preserved(), "Selected bindings move only approved decorative NPCs and leave fixed actors/triggers intact") or failed
	failed = not _expect(_runtime_scene_bindings_are_preserved(), "Runtime map bindings keep selected movers and fixed quest actors distinct") or failed
	if failed:
		quit(1)
		return

	print("npc_bounded_wanderer_expansion_test: PASS")
	quit(0)


func _verify_dialogue_pause() -> bool:
	var scene := ResourceLoader.load(WRAPPER_SCENES["city bandit"]) as PackedScene
	var bandit := scene.instantiate() as CharacterBody2D if scene != null else null
	if bandit == null:
		return _expect(false, "City Bandit wrapper instantiates for dialogue-pause coverage")
	bandit.set("idle_seconds", 0.0)
	root.add_child(bandit)
	await physics_frame
	bandit.call("_begin_leg", Vector2.RIGHT)

	var game_state := root.get_node_or_null("GameState")
	if game_state == null:
		bandit.queue_free()
		return _expect(false, "GameState is available to pause wandering during dialogue")
	var previous_mode: Variant = game_state.call("get_mode")
	game_state.call("set_mode", GameState.GameMode.DIALOGUE)
	bandit.call("_physics_process", 0.1)
	var stopped := bandit.velocity.is_zero_approx()
	game_state.call("set_mode", previous_mode)
	bandit.queue_free()
	return _expect(stopped, "Dialogue state stops City Bandit movement")


func _verify_collision_blocking_and_home_bounds() -> bool:
	var scene := ResourceLoader.load(WRAPPER_SCENES["city bandit"]) as PackedScene
	var bandit := scene.instantiate() as CharacterBody2D if scene != null else null
	if bandit == null:
		return _expect(false, "City Bandit wrapper instantiates for collision coverage")
	var game_state := root.get_node_or_null("GameState")
	if game_state == null:
		return _expect(false, "GameState is available for bounded movement coverage")
	var previous_mode: Variant = game_state.call("get_mode")
	game_state.call("set_mode", GameState.GameMode.EXPLORATION)

	bandit.position = Vector2.ZERO
	bandit.set("idle_seconds", 0.0)
	root.add_child(bandit)
	var player_blocker := _make_player_blocker(Vector2(12, 0))
	root.add_child(player_blocker)
	await physics_frame

	bandit.call("_begin_leg", Vector2.RIGHT)
	for _frame in range(30):
		await physics_frame
	var blocked_position := bandit.global_position
	var stayed_before_player := blocked_position.x < player_blocker.global_position.x

	for _frame in range(12):
		await physics_frame
	var remained_blocked := bandit.global_position.distance_to(blocked_position) <= 0.25

	player_blocker.queue_free()
	await physics_frame
	bandit.set("_idle_remaining", 0.0)
	for _frame in range(30):
		await physics_frame
	var resumed_without_teleport := bandit.global_position.x > blocked_position.x and bandit.global_position.x <= WANDER_RADIUS

	for _frame in range(240):
		await physics_frame
	var stayed_home_bounded := bandit.global_position.distance_to(Vector2.ZERO) <= WANDER_RADIUS + 0.5
	bandit.queue_free()
	game_state.call("set_mode", previous_mode)

	return _expect(stayed_before_player, "City Bandit does not pass through the player collision body") \
		and _expect(remained_blocked, "City Bandit remains physically blocked without positional drift") \
		and _expect(resumed_without_teleport, "City Bandit resumes bounded movement after the blocker is removed") \
		and _expect(stayed_home_bounded, "City Bandit never drifts beyond its home roaming radius")


func _make_player_blocker(position_value: Vector2) -> CharacterBody2D:
	var player_blocker := CharacterBody2D.new()
	player_blocker.name = "PlayerCollisionBlocker"
	player_blocker.add_to_group("player")
	player_blocker.collision_layer = 1
	player_blocker.collision_mask = 2
	player_blocker.position = position_value
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 36)
	collision.shape = shape
	player_blocker.add_child(collision)
	return player_blocker


func _map_contract_is_preserved() -> bool:
	var oakleaf := FileAccess.get_file_as_string("res://scenes/oak_leaf_village.tscn")
	var city := FileAccess.get_file_as_string("res://scenes/city_of_knowledge.tscn")
	var pinehill := FileAccess.get_file_as_string("res://scenes/2nd Village/Pinehill Village.tscn")
	return oakleaf.contains("res://NPC/Npc/wandering_girl_npc.tscn") \
		and oakleaf.contains("res://NPC/Npc/wandering_villager_female.tscn") \
		and oakleaf.contains("[node name=\"Bandits\" parent=\".\"") \
		and oakleaf.contains("[node name=\"BanditTaskTrigger\" type=\"Area2D\" parent=\"Bandits\"") \
		and oakleaf.contains("[node name=\"Boss-Bandit\"") \
		and city.contains("res://NPC/Npc/decorative_wandering_city_npc.tscn") \
		and city.contains("res://NPC/Enemy/wandering_bandit.tscn") \
		and not city.contains("BanditTaskTrigger") \
		and pinehill.contains("res://NPC/Npc/wandering_old_npc.tscn") \
		and pinehill.contains("res://NPC/Npc/wandering_villager_male.tscn") \
		and pinehill.contains("[node name=\"Boss-Wizard\"")


func _runtime_scene_bindings_are_preserved() -> bool:
	var oakleaf_scene := ResourceLoader.load("res://scenes/oak_leaf_village.tscn") as PackedScene
	var city_scene := ResourceLoader.load("res://scenes/city_of_knowledge.tscn") as PackedScene
	var pinehill_scene := ResourceLoader.load("res://scenes/2nd Village/Pinehill Village.tscn") as PackedScene
	var oakleaf := oakleaf_scene.instantiate() if oakleaf_scene != null else null
	var city := city_scene.instantiate() if city_scene != null else null
	var pinehill := pinehill_scene.instantiate() if pinehill_scene != null else null
	if oakleaf == null or city == null or pinehill == null:
		return false

	var valid: bool = oakleaf.get_node_or_null("girl_npc") is CharacterBody2D \
		and oakleaf.get_node_or_null("villager-female") is CharacterBody2D \
		and oakleaf.get_node_or_null("girl_npc/Visual") != null \
		and oakleaf.get_node_or_null("girl_npc/Visual").has_method("interact") \
		and oakleaf.get_node_or_null("girl_npc/InteractableArea").get("interaction_target_path") == NodePath("../Visual") \
		and oakleaf.get_node_or_null("girl_npc").position == Vector2(1174, 176) \
		and oakleaf.get_node_or_null("villager-female").position == Vector2(976.99994, 468.99997) \
		and oakleaf.get_node_or_null("Bandits") is AnimatedSprite2D \
		and oakleaf.get_node_or_null("Bandits/BanditTaskTrigger") is Area2D \
		and oakleaf.get_node_or_null("Boss-Bandit") is AnimatedSprite2D \
		and city.get_node_or_null("city_npc") is CharacterBody2D \
		and city.get_node_or_null("city_npc").position == Vector2(936, 306) \
		and city.get_node_or_null("Bandits") is CharacterBody2D \
		and city.get_node_or_null("Bandits2") is CharacterBody2D \
		and city.get_node_or_null("Bandits3") is CharacterBody2D \
		and city.get_node_or_null("Bandits4") is CharacterBody2D \
		and city.get_node_or_null("Bandits5") is CharacterBody2D \
		and city.get_node_or_null("Bandits").position == Vector2(114, 487) \
		and city.get_node_or_null("Bandits5").position == Vector2(327, 237) \
		and city.get_node_or_null("Bandits/BanditTaskTrigger") == null \
		and pinehill.get_node_or_null("old_npc") is CharacterBody2D \
		and pinehill.get_node_or_null("villager-male") is CharacterBody2D \
		and pinehill.get_node_or_null("old_npc").position == Vector2(178, 284) \
		and pinehill.get_node_or_null("villager-male").position == Vector2(235, 328) \
		and pinehill.get_node_or_null("Boss-Wizard") is AnimatedSprite2D

	oakleaf.queue_free()
	city.queue_free()
	pinehill.queue_free()
	return valid


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[NPC Bounded Wanderer Test] %s" % message)
		return false
	return true
