extends Node

## The Pinehill map already contains the adult NPC. This adapter supplies only
## the source-supported quest conversation and state transition; it does not
## create another NPC or dialogue surface.

const INTERACTION_RANGE := 32.0
const INTERACTION_PRIORITY := 20
const WIZARD_THANKS_TRIGGER_RANGE := 112.0
const WIZARD_THANKS_STOP_DISTANCE := 30.0
const WIZARD_THANKS_WALK_SPEED := 42.0
const WIZARD_THANKS_APPROACH_TIMEOUT := 3.0
const DIALOGUE_OVERLAY := preload("res://ui/progression_dialogue_overlay.tscn")
const DIALOGUE_LINES: Array[String] = [
	"Old Lady: You must be the young traveler from the City of Knowledge.",
	"Old Lady: A powerful Wizard waits outside the house ahead.",
	"Old Lady: But four guards protect the path to him.",
	"Old Lady: Defeat them first, then challenge the Wizard outside.",
]
const WIZARD_THANKS_LINES: Array[String] = [
	"Old Lady: Thank you for defeating the Wizard.",
	"Old Lady: Good luck on the rest of your journey.",
]
var _actor: Node2D
var _active := false
var _wizard_thanks_approaching := false
var _wizard_thanks_player: Node2D
var _wizard_thanks_route: Array[Vector2] = []
var _wizard_thanks_waypoint_index := 0
var _wizard_thanks_elapsed := 0.0
var _wizard_thanks_cooldown := 0.0


static func install_for_scene(world: Node2D, component_script: Script) -> void:
	if world == null or component_script == null:
		return
	if world.scene_file_path != "res://scenes/2nd Village/Pinehill Village.tscn":
		return
	# Keep the legacy component/function name for save compatibility, but bind
	# the authored quest NPC to the Old Lady asset.
	var actor := world.get_node_or_null("old_adult_women") as Node2D
	if actor == null or actor.get_node_or_null("ProgressionOldManInteraction") != null:
		return
	# The Old Lady is quest-critical in Pinehill. Keep the existing actor and
	# collision exactly as authored, but stop its generic civilian wander loop so
	# the interaction point cannot walk away while the player approaches it.
	actor.set_physics_process(false)
	if actor is CharacterBody2D:
		(actor as CharacterBody2D).velocity = Vector2.ZERO
	var component := component_script.new() as Node
	if component == null:
		return
	component.name = "ProgressionOldManInteraction"
	component.call("configure", actor)
	actor.add_child(component)


func configure(actor: Node2D) -> void:
	_actor = actor


func _ready() -> void:
	if _actor == null:
		queue_free()
		return
	InteractionManager.register(self)


func _exit_tree() -> void:
	InteractionManager.unregister(self)
	if _active and GameState.get_mode() in [GameState.GameMode.CUTSCENE, GameState.GameMode.DIALOGUE]:
		GameState.pop_mode()


func is_registration_valid() -> bool:
	return _actor != null and is_instance_valid(_actor) and _actor.is_inside_tree()


func can_interact() -> bool:
	if _active or not is_registration_valid() or GameState.get_mode() != GameState.GameMode.EXPLORATION:
		return false
	if not GameState.has_method("complete_pinehill_old_man") \
			or GameState.current_task_index != GameState.PINEHILL_OLD_MAN_TASK_INDEX:
		return false
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	return player != null and player.global_position.distance_to(_actor.global_position) <= INTERACTION_RANGE


func _physics_process(delta: float) -> void:
	if not is_registration_valid():
		return
	if _wizard_thanks_cooldown > 0.0:
		_wizard_thanks_cooldown = maxf(0.0, _wizard_thanks_cooldown - delta)
	if _wizard_thanks_approaching:
		_advance_wizard_thanks_approach(delta)
		return
	if _active or _wizard_thanks_cooldown > 0.0 or not _can_start_wizard_thanks_event():
		return
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	if player == null or player.global_position.distance_to(_actor.global_position) > WIZARD_THANKS_TRIGGER_RANGE:
		return
	_begin_wizard_thanks_event(player)


func _can_start_wizard_thanks_event() -> bool:
	return bool(GameState.get("wizard_defeated")) \
			and int(GameState.get("return_to_city_stage")) >= 2 \
			and int(GameState.current_task_index) == int(GameState.RETURN_CITY_TASK_INDEX) \
			and not bool(GameState.get("wizard_thanks_complete")) \
			and GameState.playtime_authorized \
			and GameState.get_mode() == GameState.GameMode.EXPLORATION


func _begin_wizard_thanks_event(player: Node2D) -> void:
	if player == null or not is_instance_valid(player) or not _can_start_wizard_thanks_event():
		return
	var world := _actor.get_parent()
	var first := world.get_node_or_null("WizardThanksPath/Waypoint1") as Marker2D
	var meeting := world.get_node_or_null("WizardThanksPath/MeetingPoint") as Marker2D
	if first == null or meeting == null:
		push_warning("Pinehill Old Lady road waypoints are missing; thank-you event will retry safely.")
		_wizard_thanks_cooldown = 1.0
		return
	_wizard_thanks_route.clear()
	if _actor.global_position.distance_to(first.global_position) > 2.0:
		_wizard_thanks_route.append(first.global_position)
	_wizard_thanks_route.append(meeting.global_position)
	_wizard_thanks_waypoint_index = 0
	_active = true
	_wizard_thanks_approaching = true
	_wizard_thanks_player = player
	_wizard_thanks_elapsed = 0.0
	GameState.push_mode(GameState.GameMode.CUTSCENE)


func _advance_wizard_thanks_approach(delta: float) -> void:
	if _actor == null or not is_instance_valid(_wizard_thanks_player):
		_finish_wizard_thanks_event(false)
		return
	_wizard_thanks_elapsed += delta
	while _wizard_thanks_waypoint_index < _wizard_thanks_route.size() \
			and _actor.global_position.distance_to(_wizard_thanks_route[_wizard_thanks_waypoint_index]) <= 0.1:
		_wizard_thanks_waypoint_index += 1
	if _wizard_thanks_waypoint_index >= _wizard_thanks_route.size():
		_finish_wizard_thanks_approach()
		return
	var to_waypoint := _wizard_thanks_route[_wizard_thanks_waypoint_index] - _actor.global_position
	var direction := Vector2.ZERO
	if _wizard_thanks_waypoint_index == 0 and absf(to_waypoint.y) > 0.1:
		direction.y = signf(to_waypoint.y)
	elif absf(to_waypoint.x) > 0.1:
		direction.x = signf(to_waypoint.x)
	else:
		direction.y = signf(to_waypoint.y)
	var distance := absf(to_waypoint.x) if direction.x != 0.0 else absf(to_waypoint.y)
	_play_wizard_thanks_walk(direction)
	if _actor is CharacterBody2D:
		var body := _actor as CharacterBody2D
		body.velocity = direction * minf(WIZARD_THANKS_WALK_SPEED, distance / maxf(delta, 0.001))
		body.move_and_slide()
	else:
		_actor.global_position += direction * minf(WIZARD_THANKS_WALK_SPEED * delta, distance)
	if _wizard_thanks_elapsed >= WIZARD_THANKS_APPROACH_TIMEOUT:
		_finish_wizard_thanks_event(false)


func _finish_wizard_thanks_approach() -> void:
	_wizard_thanks_approaching = false
	if _actor is CharacterBody2D:
		(_actor as CharacterBody2D).velocity = Vector2.ZERO
	var visual := _actor.get_node_or_null("Visual") as AnimatedSprite2D
	if visual != null:
		var toward_player := _wizard_thanks_player.global_position - _actor.global_position
		_play_wizard_thanks_walk(toward_player)
		visual.stop()
		visual.frame = 0
	_show_wizard_thanks_dialogue.call_deferred()


func _play_wizard_thanks_walk(direction: Vector2) -> void:
	var visual := _actor.get_node_or_null("Visual") as AnimatedSprite2D
	if visual == null or visual.sprite_frames == null:
		return
	var animation := "walk_down"
	if absf(direction.x) >= absf(direction.y):
		animation = "walk_right" if direction.x > 0.0 else "walk_left"
	else:
		animation = "walk_down" if direction.y > 0.0 else "walk_up"
	if visual.sprite_frames.has_animation(animation):
		visual.play(animation)


func _show_wizard_thanks_dialogue() -> void:
	if not _active or not is_registration_valid():
		_finish_wizard_thanks_event(false)
		return
	var overlay: CanvasLayer = DIALOGUE_OVERLAY.instantiate()
	get_tree().current_scene.add_child(overlay)
	overlay.tree_exiting.connect(_on_thanks_overlay_exiting)
	var completed: bool = await overlay.show_lines(WIZARD_THANKS_LINES)
	if is_instance_valid(overlay):
		overlay.queue_free()
	if not completed:
		_finish_wizard_thanks_event(false)
		return
	if GameState.has_method("complete_wizard_thanks_event"):
		GameState.call("complete_wizard_thanks_event")
	_finish_wizard_thanks_event(true)


func _on_thanks_overlay_exiting() -> void:
	if _active and GameState.get_mode() == GameState.GameMode.CUTSCENE:
		_finish_wizard_thanks_event(false)


func _finish_wizard_thanks_event(completed: bool) -> void:
	_wizard_thanks_approaching = false
	_wizard_thanks_player = null
	_wizard_thanks_route.clear()
	_wizard_thanks_waypoint_index = 0
	if _actor is CharacterBody2D:
		(_actor as CharacterBody2D).velocity = Vector2.ZERO
	if _active and GameState.get_mode() == GameState.GameMode.CUTSCENE:
		GameState.pop_mode()
	_active = false
	if not completed:
		_wizard_thanks_cooldown = 1.0


func get_interaction_position() -> Vector2:
	return _actor.global_position if _actor != null else Vector2.ZERO


func get_interaction_priority() -> int:
	return INTERACTION_PRIORITY


func interact() -> bool:
	if not can_interact():
		return false
	_active = true
	GameState.push_mode(GameState.GameMode.DIALOGUE)
	var overlay: CanvasLayer = DIALOGUE_OVERLAY.instantiate()
	get_tree().current_scene.add_child(overlay)
	overlay.tree_exiting.connect(_on_intro_overlay_exiting)
	var completed: bool = await overlay.show_lines(DIALOGUE_LINES)
	if is_instance_valid(overlay):
		overlay.queue_free()
	if completed:
		if GameState.has_method("complete_pinehill_old_lady"):
			GameState.call("complete_pinehill_old_lady")
		else:
			GameState.call("complete_pinehill_old_man")
	if GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
	_active = false
	return true


func _on_intro_overlay_exiting() -> void:
	if _active and GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
		_active = false
