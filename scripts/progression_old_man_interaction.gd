extends Node

## The Pinehill map already contains the adult NPC. This adapter supplies only
## the source-supported quest conversation and state transition; it does not
## create another NPC or dialogue surface.

const INTERACTION_RANGE := 32.0
const INTERACTION_PRIORITY := 20
const DIALOGUE_OVERLAY := preload("res://ui/progression_dialogue_overlay.tscn")
var _actor: Node2D
var _active := false


static func install_for_scene(world: Node2D, component_script: Script) -> void:
	if world == null or component_script == null:
		return
	if world.scene_file_path not in ["res://scenes/2nd Village/Pinehill Village.tscn", "res://scenes/pinehill_village.tscn"]:
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
	await overlay.show_lines([
		"Old Lady: A powerful Wizard is ahead.",
		"Old Lady: The guards protect the tower. Defeat them first.",
	])
	overlay.queue_free()
	if GameState.has_method("complete_pinehill_old_lady"):
		GameState.call("complete_pinehill_old_lady")
	else:
		GameState.call("complete_pinehill_old_man")
	if GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
	_active = false
	return true
