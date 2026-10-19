extends "res://scripts/gameplay_scene.gd"

## The project does not contain a separate authored forest map. This stage
## reuses the existing City map as a backdrop while giving the five authored
## deep-forest encounters their own scene path and save checkpoint.

const FOREST_BANDITS := [
	{"node": "Bandits", "encounter": "deep_forest_bandits1"},
	{"node": "Bandits2", "encounter": "deep_forest_bandits2"},
	{"node": "Bandits3", "encounter": "deep_forest_bandits3"},
	{"node": "Bandits4", "encounter": "deep_forest_bandits4"},
	{"node": "Bandits5", "encounter": "deep_forest_bandits5"},
]

const BANDIT_COLLISION_LAYER := 2
const BANDIT_COLLISION_MASK := 1

func _ready() -> void:
	var backdrop := get_node_or_null("ForestBackdrop")
	if backdrop != null:
		# The nested City instance is scenery only; its gameplay script must not
		# install a second player, HUD, doors, or encounter adapters.
		backdrop.set_script(null)
		for node_name in [
			"School",
			"SchoolDoor",
			"Go-to-Oak-Leaf-Village",
			"City-of-knowlwedge-to-PineHill",
			"BlueHotelDoor",
			"RedHotelDoor",
		]:
			var node := backdrop.get_node_or_null(node_name)
			if node != null:
				# queue_free() alone leaves an Area2D in the physics tree until the
				# frame ends. Detach City-only triggers now so entering the Forest
				# cannot accidentally reload this wrapper through the City door.
				backdrop.remove_child(node)
				node.queue_free()
		_activate_forest_bandits(backdrop)
	super._ready()


func _activate_forest_bandits(backdrop: Node) -> void:
	if backdrop == null:
		return
	for encounter in FOREST_BANDITS:
		var actor := backdrop.get_node_or_null(String(encounter.node)) as CollisionObject2D
		if actor == null:
			continue
		var encounter_id := String(encounter.encounter)
		var defeated := GameState.has_method("is_progression_encounter_defeated") \
				and bool(GameState.call("is_progression_encounter_defeated", encounter_id))
		if defeated:
			continue
		# These shared actors may have been hidden/de-collided by an ordinary City
		# scene instance. Restore only the authored Bandit body state in the Forest
		# wrapper, before the Forest-specific encounter adapters are installed.
		actor.visible = true
		actor.set_deferred("collision_layer", BANDIT_COLLISION_LAYER)
		actor.set_deferred("collision_mask", BANDIT_COLLISION_MASK)
