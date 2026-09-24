extends "res://scripts/gameplay_scene.gd"

## The project does not contain a separate authored forest map. This stage
## reuses the existing City map as a backdrop while giving the five authored
## deep-forest encounters their own scene path and save checkpoint.

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
				node.queue_free()
	super._ready()
