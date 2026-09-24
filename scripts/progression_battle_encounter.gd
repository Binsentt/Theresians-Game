extends Node

## Runtime adapter for the already-authored City/Pinehill actors. It mirrors
## the Oakleaf encounter lifecycle and instantiates only the original VS scenes.

const COMPONENT_NAME := "ProgressionBattleEncounter"
const INTERACTION_RANGE := 32.0
const INTERACTION_PRIORITY := 10
const DIALOGUE_OVERLAY := preload("res://ui/progression_dialogue_overlay.tscn")
const DEEP_FOREST_COMPLETE_DIALOGUE: Array[String] = [
	"The path to Pinehill Village is now clear.",
]
const PINEHILL_GUARDS_COMPLETE_DIALOGUE: Array[String] = [
	"The Wizard Tower is now accessible.",
]
const WIZARD_INTRO_DIALOGUE: Array[String] = [
	"Wizard: So you defeated all of my guards.",
	"Wizard: You have come far, but knowledge alone will not be enough.",
	"Wizard: Show me what you have learned.",
]
const WIZARD_REVELATION_DIALOGUE: Array[String] = [
	"Wizard: You are stronger than I expected.",
	"Wizard: But I am not the one behind your greatest challenge.",
	"Wizard: The true Math Master has been guiding you from the beginning.",
	"Wizard: Your Teacher is waiting for you in the City of Knowledge.",
	"Wizard: Return to the School.",
]
const CITY_PATH := "res://scenes/city_of_knowledge.tscn"
const DEEPEST_FOREST_PATH := "res://scenes/deepest_forest_path.tscn"
const PINEHILL_PATH := "res://scenes/2nd Village/Pinehill Village.tscn"
const PINEHILL_WRAPPER_PATH := "res://scenes/pinehill_village.tscn"

const ROUTES := {
	CITY_PATH: {
		"Bandits": {"encounter_id": "deep_forest_bandits1", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits2": {"encounter_id": "deep_forest_bandits2", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits3": {"encounter_id": "deep_forest_bandits3", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits4": {"encounter_id": "deep_forest_bandits4", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits5": {"encounter_id": "deep_forest_bandits5", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
	},
	DEEPEST_FOREST_PATH: {
		"Bandits": {"node_path": "ForestBackdrop/Bandits", "encounter_id": "deep_forest_bandits1", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits2": {"node_path": "ForestBackdrop/Bandits2", "encounter_id": "deep_forest_bandits2", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits3": {"node_path": "ForestBackdrop/Bandits3", "encounter_id": "deep_forest_bandits3", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits4": {"node_path": "ForestBackdrop/Bandits4", "encounter_id": "deep_forest_bandits4", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits5": {"node_path": "ForestBackdrop/Bandits5", "encounter_id": "deep_forest_bandits5", "difficulty": "Normal", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
	},
	PINEHILL_PATH: {
		"Bandits": {"encounter_id": "pinehill_bandits1", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits2": {"encounter_id": "pinehill_bandits2", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits3": {"encounter_id": "pinehill_bandits3", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits4": {"encounter_id": "pinehill_bandits4", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"WizardTower": {"node_path": "display-kase yung wizard sa labas lang", "encounter_id": "pinehill_wizard", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_wizard.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_wizard1.tscn"},
	},
	PINEHILL_WRAPPER_PATH: {
		"Bandits": {"encounter_id": "pinehill_bandits1", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits2": {"encounter_id": "pinehill_bandits2", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits3": {"encounter_id": "pinehill_bandits3", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"Bandits4": {"encounter_id": "pinehill_bandits4", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn"},
		"WizardTower": {"node_path": "display-kase yung wizard sa labas lang", "encounter_id": "pinehill_wizard", "difficulty": "Difficult", "male_scene": "res://Battle/Battle-Enemy/male_vs_wizard.tscn", "female_scene": "res://Battle/Battle-Enemy/female_vs_wizard1.tscn"},
	},
}

var _actor: Node2D
var _route: Dictionary = {}
var _starting := false
var _defeated := false


static func install_for_scene(world: Node2D, component_script: Script) -> void:
	if world == null or component_script == null:
		return
	var scene_path := world.scene_file_path
	if not ROUTES.has(scene_path):
		return
	if scene_path == CITY_PATH:
		# City is now the hub; the five authored actors are mounted in the
		# dedicated forest wrapper instead of being encounter points here.
		return
	for actor_name in ROUTES[scene_path]:
		var route: Dictionary = ROUTES[scene_path][actor_name]
		var actor_path := String(route.get("node_path", actor_name))
		var actor := world.get_node_or_null(actor_path) as Node2D
		if actor == null or actor.get_node_or_null(COMPONENT_NAME) != null:
			continue
		var encounter_id := String(route.get("encounter_id", ""))
		if GameState.has_method("is_progression_encounter_defeated") \
				and bool(GameState.call("is_progression_encounter_defeated", encounter_id)):
			actor.queue_free()
			continue
		var encounter := component_script.new() as Node
		if encounter == null:
			continue
		encounter.name = COMPONENT_NAME
		encounter.call("configure", actor, route)
		actor.add_child(encounter)
	if scene_path in [PINEHILL_PATH, PINEHILL_WRAPPER_PATH]:
		# Preserve the authored scene node for compatibility, but prevent the
		# legacy outside Wizard instance from becoming a second trigger.
		var legacy_wizard := world.get_node_or_null("Boss-Wizard")
		if legacy_wizard != null:
			legacy_wizard.visible = false
			legacy_wizard.process_mode = Node.PROCESS_MODE_DISABLED
			legacy_wizard.queue_free()


func configure(actor: Node2D, route: Dictionary) -> void:
	_actor = actor
	_route = route.duplicate(true)


func _ready() -> void:
	if _actor == null or _route.is_empty():
		queue_free()
		return
	InteractionManager.register(self)


func _exit_tree() -> void:
	InteractionManager.unregister(self)


func is_registration_valid() -> bool:
	return not _defeated and _actor != null and is_instance_valid(_actor) \
			and _actor.is_inside_tree() and _can_start_encounter()


func can_interact() -> bool:
	if _starting or not is_registration_valid() or not GameState.playtime_authorized:
		return false
	if GameState.get_mode() != GameState.GameMode.EXPLORATION:
		return false
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	return player != null and player.global_position.distance_to(_actor.global_position) <= INTERACTION_RANGE


func _can_start_encounter() -> bool:
	return GameState.has_method("can_start_progression_encounter") \
			and bool(GameState.call("can_start_progression_encounter", String(_route.get("encounter_id", ""))))


func get_interaction_position() -> Vector2:
	return _actor.global_position if _actor != null else Vector2.ZERO


func get_interaction_priority() -> int:
	return INTERACTION_PRIORITY


func interact() -> bool:
	if not can_interact():
		return false
	var battle_scene_path := _battle_scene_path()
	if battle_scene_path.is_empty() or not ResourceLoader.exists(battle_scene_path):
		push_error("Missing original progression battle scene: %s" % battle_scene_path)
		return false
	var world := get_tree().current_scene as Node2D
	if world == null:
		return false
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	var source_position := player.global_position if player != null else GameState.player_position
	_starting = true
	GameState.begin_encounter({
		"encounter_id": String(_route.get("encounter_id", "")),
		"source_scene_path": world.scene_file_path,
		"source_position": source_position,
		"quest_checkpoint": GameState.current_task_index,
		"question_scope": {"difficulty": String(_route.get("difficulty", ""))},
	})
	_present_original_battle.call_deferred(world, battle_scene_path)
	return true


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
		push_error("Unable to instantiate original progression battle scene: %s" % battle_scene_path)
		return
	if String(_route.get("encounter_id", "")) == "pinehill_wizard":
		await _show_progression_dialogue(WIZARD_INTRO_DIALOGUE)
	var battle_scene: Node = packed_scene.instantiate()
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
		var victory_result: Dictionary = GameState.record_encounter_victory()
		match String(victory_result.get("action", "")):
			"deep_forest_complete":
				await _show_progression_dialogue(DEEP_FOREST_COMPLETE_DIALOGUE)
			"pinehill_bandits_complete":
				await _show_progression_dialogue(PINEHILL_GUARDS_COMPLETE_DIALOGUE)
			"wizard_complete":
				await _show_wizard_revelation()
		if _actor != null and is_instance_valid(_actor):
			_actor.queue_free()
	else:
		GameState.record_encounter_loss()


func _show_wizard_revelation() -> void:
	await _show_progression_dialogue(WIZARD_REVELATION_DIALOGUE)


func _show_progression_dialogue(lines: Array[String]) -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	GameState.push_mode(GameState.GameMode.DIALOGUE)
	var overlay: CanvasLayer = DIALOGUE_OVERLAY.instantiate()
	world.add_child(overlay)
	await overlay.show_lines(lines)
	overlay.queue_free()
	if GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
