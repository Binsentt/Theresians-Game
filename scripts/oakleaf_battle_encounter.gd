extends Node

## Runtime-only encounter route for the five original Oakleaf enemy actors that
## ship without a task adapter. Keeping this out of the scene avoids changing
## the map, the actors' foot collisions, and their interaction sensor geometry.

const OAKLEAF_SCENE_PATH := "res://scenes/oak_leaf_village.tscn"
const COMPONENT_NAME := "OakleafBattleEncounter"
const INTERACTION_RANGE := 24.0
const INTERACTION_PRIORITY := 10
const BATTLE_TRANSITION := preload("res://scripts/battle_transition.gd")
const BANDIT_CHALLENGE_DIALOGUE := {
	"oakleaf_bandits2": ["Bandit: You will have to get past me first!"],
	"oakleaf_bandits3": ["Bandit: Let's see if your answers can beat me."],
	"oakleaf_bandits4": ["Bandit: I won't let you pass!"],
	"oakleaf_bandits5": ["Bandit: Prove you can defeat me!"],
}
const BOSS_CHALLENGE_DIALOGUE := [
	"Boss Bandit: So, you defeated my bandits.",
	"Boss Bandit: Now face me!",
]
const BOSS_DEFEAT_DIALOGUE := [
	"Boss Bandit: You defeated me.",
	"Boss Bandit: My bandits will leave the road.",
	"Boss Bandit: Return to the Teacher for your next direction.",
]
const ROUTES := {
	"Bandits2": {
		"encounter_id": "oakleaf_bandits2",
		"male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn",
		"female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn",
	},
	"Bandits3": {
		"encounter_id": "oakleaf_bandits3",
		"male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn",
		"female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn",
	},
	"Bandits4": {
		"encounter_id": "oakleaf_bandits4",
		"male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn",
		"female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn",
	},
	"Bandits5": {
		"encounter_id": "oakleaf_bandits5",
		"male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn",
		"female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn",
	},
	"Boss-Bandit": {
		"encounter_id": "oakleaf_boss_bandit",
		"male_scene": "res://Battle/Battle-Enemy/male_vs_boss.tscn",
		"female_scene": "res://Battle/Battle-Enemy/female_vs_boss_bandit.tscn",
	},
}

var _actor: Node2D
var _route: Dictionary = {}
var _starting := false
var _defeated := false
var _boss_dialogue_active := false


static func install_for_scene(world: Node2D, component_script: Script) -> void:
	if world == null or world.scene_file_path != OAKLEAF_SCENE_PATH:
		return
	if component_script == null:
		return
	var first_bandit := world.get_node_or_null("Bandits") as Node2D
	if GameState.has_method("is_oakleaf_encounter_defeated") \
			and bool(GameState.call("is_oakleaf_encounter_defeated", GameState.OAKLEAF_BOSS_ID)):
		_remove_completed_encounter_actors(world)
		return
	if first_bandit != null:
		first_bandit.show()
		if GameState.has_method("is_oakleaf_encounter_defeated") \
				and bool(GameState.call("is_oakleaf_encounter_defeated", "oakleaf_bandits1")):
			var first_trigger := first_bandit.get_node_or_null("BanditTaskTrigger") as Area2D
			if first_trigger != null:
				first_trigger.set("interaction_enabled", false)
	for actor_name in ROUTES:
		var actor := world.get_node_or_null(String(actor_name)) as Node2D
		if actor == null or actor.get_node_or_null(COMPONENT_NAME) != null:
			continue
		# ROUTES is a constant dictionary. Never mutate the shared route template
		# while installing one scene instance; each actor gets its own state copy.
		var route: Dictionary = ROUTES[actor_name].duplicate(true)
		var encounter_id := String(route.get("encounter_id", ""))
		var encounter_defeated := GameState.has_method("is_oakleaf_encounter_defeated") \
				and bool(GameState.call("is_oakleaf_encounter_defeated", encounter_id))
		actor.show()
		var encounter := component_script.new() as Node
		if encounter == null:
			continue
		encounter.name = COMPONENT_NAME
		route["is_defeated"] = encounter_defeated
		encounter.call("configure", actor, route)
		actor.add_child(encounter)


func configure(actor: Node2D, route: Dictionary) -> void:
	_actor = actor
	_route = route.duplicate(true)
	_defeated = bool(_route.get("is_defeated", false))


func _ready() -> void:
	if _actor == null or _route.is_empty():
		queue_free()
		return
	if not _defeated:
		InteractionManager.register(self)


func _exit_tree() -> void:
	InteractionManager.unregister(self)
	if _boss_dialogue_active and GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
	_boss_dialogue_active = false


func is_registration_valid() -> bool:
	return not _defeated \
			and _actor != null \
			and is_instance_valid(_actor) \
			and _actor.is_inside_tree()


func can_interact() -> bool:
	if _starting or not is_registration_valid() or not _can_start_encounter() or not GameState.playtime_authorized:
		return false
	if GameState.get_mode() != GameState.GameMode.EXPLORATION:
		return false
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	return player != null and player.global_position.distance_to(_actor.global_position) <= INTERACTION_RANGE


func _can_start_encounter() -> bool:
	if not GameState.has_method("can_start_oakleaf_encounter"):
		return true
	return bool(GameState.call("can_start_oakleaf_encounter", String(_route.get("encounter_id", ""))))


func get_interaction_position() -> Vector2:
	return _actor.global_position if _actor != null else Vector2.ZERO


func get_interaction_priority() -> int:
	return INTERACTION_PRIORITY


func interact() -> bool:
	if not can_interact():
		return false
	var battle_scene_path := _battle_scene_path()
	if battle_scene_path.is_empty() or not ResourceLoader.exists(battle_scene_path):
		push_error("Missing original Oakleaf battle scene: %s" % battle_scene_path)
		return false
	var world := get_tree().current_scene as Node2D
	if world == null or world.scene_file_path != OAKLEAF_SCENE_PATH:
		return false
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	var source_position := player.global_position if player != null else GameState.player_position
	_starting = true
	var dialogue_lines: Array = BOSS_CHALLENGE_DIALOGUE if String(_route.get("encounter_id", "")) == GameState.OAKLEAF_BOSS_ID \
			else BANDIT_CHALLENGE_DIALOGUE.get(String(_route.get("encounter_id", "")), ["Bandit: You will have to get past me first!"])
	_present_dialogue_then_battle.call_deferred(world, battle_scene_path, source_position, dialogue_lines)
	return true


func _present_dialogue_then_battle(world: Node2D, battle_scene_path: String, source_position: Vector2, dialogue_lines: Array) -> void:
	if not await _show_oakleaf_dialogue(world, dialogue_lines):
		_starting = false
		return
	if not is_instance_valid(world) or not _can_start_encounter() or not GameState.playtime_authorized:
		_starting = false
		return
	GameState.begin_encounter({
		"encounter_id": String(_route.get("encounter_id", "")),
		"source_scene_path": world.scene_file_path,
		"source_position": source_position,
		"quest_checkpoint": GameState.current_task_index,
		"question_scope": {},
	})
	_present_original_battle.call_deferred(world, battle_scene_path)


func _battle_scene_path() -> String:
	var route_key := "female_scene" if GameState.gender == "female" else "male_scene"
	return String(_route.get(route_key, "")).strip_edges()


func _present_original_battle(world: Node2D, battle_scene_path: String) -> void:
	if not is_instance_valid(world):
		_starting = false
		GameState.record_encounter_loss()
		return
	var packed_scene := load(battle_scene_path) as PackedScene
	if packed_scene == null:
		_starting = false
		GameState.record_encounter_loss()
		push_error("Unable to instantiate original Oakleaf battle scene: %s" % battle_scene_path)
		return
	await BATTLE_TRANSITION.play(world)
	if not is_instance_valid(world):
		_starting = false
		GameState.record_encounter_loss()
		return
	var battle_scene := packed_scene.instantiate()
	var battle_layer := CanvasLayer.new()
	battle_layer.name = "OriginalBattlePresentation"
	battle_layer.layer = -1
	var world_was_visible := world.visible
	world.hide()
	world.add_child(battle_layer)
	var question_layer := battle_scene.get_node_or_null("CanvasLayer") as CanvasLayer
	if question_layer != null:
		question_layer.layer = 0
	battle_layer.add_child(battle_scene)
	GameState.begin_battle(battle_scene)

	var battle_won: bool = await battle_scene.battle_finished
	if is_instance_valid(battle_layer):
		battle_layer.queue_free()
	if is_instance_valid(world):
		world.visible = world_was_visible
	_starting = false
	if battle_won:
		_defeated = true
		var encounter_id := String(_route.get("encounter_id", ""))
		GameState.record_encounter_victory()
		if encounter_id == GameState.OAKLEAF_BOSS_ID:
			await _show_boss_defeat_dialogue(world)
			_remove_completed_encounter_actors(world)
		return
	GameState.record_encounter_loss()


func _show_oakleaf_dialogue(world: Node2D, lines: Array) -> bool:
	if not is_instance_valid(world):
		return false
	var quest_ui := world.get_node_or_null("CanvasLayer/Panel")
	if quest_ui == null or not quest_ui.has_method("begin_dialogue"):
		push_error("Oakleaf encounter dialogue host is missing; battle will not start without its challenge dialogue.")
		return false
	_boss_dialogue_active = true
	GameState.push_mode(GameState.GameMode.DIALOGUE)
	await quest_ui.call("begin_dialogue", lines)
	if _boss_dialogue_active and GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
	_boss_dialogue_active = false
	return is_instance_valid(world)


func _show_boss_defeat_dialogue(world: Node2D) -> void:
	await _show_oakleaf_dialogue(world, BOSS_DEFEAT_DIALOGUE)


static func _remove_completed_encounter_actors(world: Node2D) -> void:
	if world == null:
		return
	for actor_name in ["Bandits", "Bandits2", "Bandits3", "Bandits4", "Bandits5", "Boss-Bandit"]:
		var actor := world.get_node_or_null(actor_name)
		if actor != null:
			actor.queue_free()
