extends SceneTree

const WANDERER_SCENE_PATH := "res://NPC/Npc/decorative_wandering_city_npc.tscn"
const EXPECTED_SPEED := 30.0
const EXPECTED_RADIUS := 42.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var wanderer_scene := ResourceLoader.load(WANDERER_SCENE_PATH) as PackedScene
	failed = not _expect(wanderer_scene != null, "The one opt-in decorative City NPC uses its dedicated wrapper scene.") or failed
	if wanderer_scene == null:
		quit(1)
		return

	var wanderer := wanderer_scene.instantiate() as CharacterBody2D
	failed = not _expect(wanderer != null, "The decorative wrapper is a CharacterBody2D.") or failed
	if wanderer == null:
		quit(1)
		return
	root.add_child(wanderer)
	await process_frame

	var sprite := wanderer.get_node_or_null("CityNpc") as AnimatedSprite2D
	var collision := wanderer.get_node_or_null("FootCollision") as CollisionShape2D
	failed = not _expect(sprite != null, "The wrapper contains the existing City NPC sprite exactly once.") or failed
	failed = not _expect(collision != null and collision.shape != null, "The wrapper owns one foot collision shape.") or failed
	failed = not _expect(float(wanderer.get("walk_speed")) == EXPECTED_SPEED and EXPECTED_SPEED < 60.0, "Decorative movement is below the 60 px/s player speed.") or failed
	failed = not _expect(float(wanderer.get("wander_radius")) == EXPECTED_RADIUS, "The City NPC retains its bounded local radius.") or failed

	var collision_manager := root.get_node_or_null("NpcCollisionManager")
	failed = not _expect(collision_manager != null, "The existing collision manager is available as an autoload.") or failed
	if collision_manager != null:
		collision_manager.call("_ensure_npc_collisions", wanderer)
	failed = not _expect(sprite == null or sprite.get_node_or_null("NpcBodyCollision") == null, "The opt-in CharacterBody wrapper does not receive a duplicate static NPC collision.") or failed

	wanderer.call("_begin_leg", Vector2.RIGHT)
	var velocity := wanderer.velocity
	failed = not _expect(is_equal_approx(velocity.length(), EXPECTED_SPEED), "A decorative walking leg uses the configured speed.") or failed
	failed = not _expect(absf(velocity.x) == EXPECTED_SPEED and is_zero_approx(velocity.y), "A decorative walking leg is cardinal.") or failed
	var target: Vector2 = wanderer.get("_target_position")
	failed = not _expect(target.distance_to(wanderer.get("_home_position")) <= EXPECTED_RADIUS, "A selected wander target remains inside the home radius.") or failed

	var game_state := root.get_node_or_null("GameState")
	failed = not _expect(game_state != null, "The existing GameState autoload controls interaction modes.") or failed
	if game_state != null:
		var original_mode: Variant = game_state.call("get_mode")
		game_state.call("set_mode", 1) # GameState.GameMode.DIALOGUE
		wanderer.call("_physics_process", 0.1)
		failed = not _expect(wanderer.velocity.is_zero_approx(), "Dialogue mode stops the decorative NPC without changing dialogue behavior.") or failed
		game_state.call("set_mode", 0) # GameState.GameMode.EXPLORATION
		wanderer.call("_physics_process", 0.0)
		failed = not _expect(wanderer.velocity.is_zero_approx(), "Exploration resumes through a normal idle boundary, not an immediate movement jump.") or failed
		game_state.call("set_mode", original_mode)

	wanderer.queue_free()
	if failed:
		quit(1)
		return
	print("decorative_npc_wanderer_test: PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[Decorative NPC Wanderer Test] %s" % message)
		return false
	return true
