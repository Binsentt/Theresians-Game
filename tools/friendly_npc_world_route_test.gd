extends Node

## Offline contract for the friendly-civilian dialogue adapters and the
## symmetric City <-> Deepest Forest <-> Pinehill route. No network calls or
## gameplay writes are performed.

const CITY_PATH := "res://scenes/city_of_knowledge.tscn"
const FOREST_PATH := "res://scenes/deepest_forest_path.tscn"
const PINEHILL_PATH := "res://scenes/2nd Village/Pinehill Village.tscn"
const OAKLEAF_PATH := "res://scenes/oak_leaf_village.tscn"
const DEFAULT_GREETING := "Hello traveler! Welcome to our town."
const RESULT_PATH := "res://tools/friendly_npc_world_route_test_result.json"

var _checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _expect(value: bool, label: String) -> void:
	_checks.append({"label": label, "passed": value})
	if not value:
		push_error(label)


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()

	_check_scene_dialogue(OAKLEAF_PATH, {
		"girl_npc/Visual": "Hi! The teacher's house is nearby if you need help.",
		"NPC/Visual": "Be careful on the forest road. Bandits have been seen nearby.",
		"villager-female/Visual": "Welcome to Oakleaf. Everyone here is cheering for you.",
		"NPC1/Visual": "Take your time, young traveler. Think carefully and keep going.",
	}, "Oakleaf")
	_check_scene_dialogue(CITY_PATH, {
		"adult-male_npc/Visual": "Welcome to the City of Knowledge. The school is just ahead.",
		"city_npc/CityNpc": "The city is busy today. Good luck with your studies!",
		"old_adult_women/Visual": "Every challenge teaches you something new.",
		"old_npc/Visual": "The path beyond the city leads to the Deepest Forest.",
		"girl_npc/Visual": "I heard Pinehill Village is past the forest.",
	}, "City")
	_check_scene_dialogue(PINEHILL_PATH, {
		"old_npc/Visual": "Pinehill is quiet, but the Wizard's tower worries everyone.",
		"male-npc/Visual": "Those guards near the tower are tough. Be ready.",
		"girl_npc/Visual": "At night, strange lights shine from the Wizard's tower.",
		"villager-male/Visual": "If you're heading to the tower, prepare before you go.",
		"villager-female/Visual": "The Old Lady knows more about the Wizard than anyone here.",
	}, "Pinehill")

	_check_routes()

	var failed := 0
	for check in _checks:
		if not bool(check.get("passed", false)):
			failed += 1
	var evidence := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks, "live_network_calls": 0}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	print("FRIENDLY_NPC_WORLD_ROUTE_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed}))
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(1 if failed else 0)


func _check_scene_dialogue(scene_path: String, expected: Dictionary, label: String) -> void:
	var packed := load(scene_path) as PackedScene
	var scene := packed.instantiate() as Node2D if packed != null else null
	_expect(scene != null, label + " scene instantiates")
	if scene == null:
		return
	var greetings: Array[String] = []
	for node_path in expected:
		var node_path_string := "%s" % node_path
		var target := scene.get_node_or_null(NodePath(node_path_string))
		var greeting := "%s" % target.get("greeting_message") if target != null else ""
		_expect(target != null and target.has_method("interact"), label + " " + node_path_string + " has deliberate interaction")
		_expect(target != null and not greeting.is_empty() and greeting != DEFAULT_GREETING, label + " " + node_path_string + " has a unique greeting")
		if not greeting.is_empty():
			greetings.append(greeting)
		var sensor_path := node_path_string + "/InteractableArea" if node_path_string.ends_with("/Visual") else node_path_string.get_base_dir() + "/InteractableArea"
		var sensor := scene.get_node_or_null(sensor_path)
		if sensor == null and node_path_string.ends_with("/Visual"):
			sensor_path = node_path_string.get_base_dir() + "/InteractableArea"
			sensor = scene.get_node_or_null(sensor_path)
		_expect(sensor != null, label + " " + node_path_string + " has an interaction sensor")
		_expect(greeting == ("%s" % expected[node_path]), label + " " + node_path_string + " uses the approved line")
	_expect(greetings.size() == expected.size(), label + " greetings are all present")
	_expect(greetings.size() == _unique_count(greetings), label + " greetings are not duplicated")
	if label == "Pinehill":
		var old_lady := scene.get_node_or_null("old_adult_women")
		_expect(old_lady != null and old_lady.get_node_or_null("Visual/InteractableArea") == null, "Pinehill Old Lady has no competing generic greeting sensor")
	scene.free()


func _unique_count(values: Array[String]) -> int:
	var unique := {}
	for value in values:
		unique[value] = true
	return unique.size()


func _check_routes() -> void:
	var city := (load(CITY_PATH) as PackedScene).instantiate() as Node2D
	var forest := (load(FOREST_PATH) as PackedScene).instantiate() as Node2D
	var pinehill := (load(PINEHILL_PATH) as PackedScene).instantiate() as Node2D
	_expect(city != null and forest != null and pinehill != null, "world route scenes instantiate")
	if city == null or forest == null or pinehill == null:
		return

	var city_gate := city.get_node_or_null("City-of-knowlwedge-to-PineHill")
	_expect(city_gate != null and String(city_gate.get("destination_scene_path")) == FOREST_PATH, "City gate enters Deepest Forest")
	_expect(city_gate != null and String(city_gate.get("destination_spawn_marker_name")) == "spawn_from_city", "City gate uses the Forest city-side marker")
	_expect(city.get_node_or_null("spawn_from_deepest_forest") != null, "City has a named Forest-return marker")

	var forest_city_gate := forest.get_node_or_null("DeepestForestToCity")
	_expect(forest_city_gate != null and String(forest_city_gate.get("destination_scene_path")) == CITY_PATH, "Forest left exit returns to City")
	_expect(forest_city_gate != null and String(forest_city_gate.get("destination_spawn_marker_name")) == "spawn_from_deepest_forest", "Forest City exit uses the City return marker")
	var forest_pine_gate := forest.get_node_or_null("DeepestForestToPinehill")
	_expect(forest_pine_gate != null and String(forest_pine_gate.get("destination_scene_path")) == PINEHILL_PATH, "Forest right exit enters Pinehill")
	_expect(forest_pine_gate != null and String(forest_pine_gate.get("destination_spawn_marker_name")) == "spawn_from_deepest_forest", "Forest Pinehill exit uses the Pinehill entrance marker")
	_expect(forest.get_node_or_null("spawn_from_city") != null, "Forest keeps its City-side marker")

	var pine_gate := pinehill.get_node_or_null("Pinehill-to-Deepest-Forest")
	_expect(pine_gate != null and String(pine_gate.get("destination_scene_path")) == FOREST_PATH, "Pinehill entrance returns to Deepest Forest")
	_expect(pine_gate != null and String(pine_gate.get("destination_spawn_marker_name")) == "spawn_from_pinehill", "Pinehill exit uses the Forest Pinehill-side marker")
	_expect(pinehill.get_node_or_null("spawn_from_deepest_forest") != null, "Pinehill has a named Forest entrance marker")
	_expect(pinehill.get_node_or_null("Pinehill-to-City-of-Knowledge") == null, "Pinehill no longer has a direct City gate")

	city.free()
	forest.free()
	pinehill.free()
