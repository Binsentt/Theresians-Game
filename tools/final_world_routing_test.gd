extends Node

## Offline structural fixture for the runtime adapters added to the existing
## City, Pinehill, and School scenes. No scene is entered and no save is made.

const CITY := "res://scenes/city_of_knowledge.tscn"
const DEEPEST_FOREST := "res://scenes/deepest_forest_path.tscn"
const PINEHILL := "res://scenes/2nd Village/Pinehill Village.tscn"
const ENCOUNTER_SCRIPT := preload("res://scripts/progression_battle_encounter.gd")
const OLD_MAN_SCRIPT := preload("res://scripts/progression_old_man_interaction.gd")
const NORMAL_MALE := "res://Battle/Battle-Enemy/male_vs_bandit.tscn"
const NORMAL_FEMALE := "res://Battle/Battle-Enemy/female_vs_bandit.tscn"
const WIZARD_MALE := "res://Battle/Battle-Enemy/male_vs_wizard.tscn"
const WIZARD_FEMALE := "res://Battle/Battle-Enemy/female_vs_wizard1.tscn"
const TEACHER_MALE := "res://Battle/Battle-Enemy/male_vs_teacher.tscn"
const TEACHER_FEMALE := "res://Battle/Battle-Enemy/female_vs_teacher.tscn"
const RESULT_PATH := "res://tools/final_world_routing_test_result.json"

var checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _expect(value: bool, label: String) -> void:
	checks.append({"label": label, "passed": value})
	if not value:
		push_error(label)


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	for scene_path in [NORMAL_MALE, NORMAL_FEMALE, WIZARD_MALE, WIZARD_FEMALE, TEACHER_MALE, TEACHER_FEMALE]:
		_expect(ResourceLoader.exists(scene_path), "original VS route exists: " + scene_path)

	var city := (load(CITY) as PackedScene).instantiate() as Node2D
	_expect(city != null, "canonical City instantiates")
	if city != null:
		ENCOUNTER_SCRIPT.install_for_scene(city, ENCOUNTER_SCRIPT)
		_expect(city.get_node_or_null("Bandits") == null or city.get_node("Bandits").get_node_or_null("ProgressionBattleEncounter") == null, "City hub does not install deep-forest encounter triggers")
		city.free()

	var forest := (load(DEEPEST_FOREST) as PackedScene).instantiate() as Node2D
	_expect(forest != null, "dedicated Deepest Forest Path instantiates")
	if forest != null:
		ENCOUNTER_SCRIPT.install_for_scene(forest, ENCOUNTER_SCRIPT)
		var expected_forest_ids := ["deep_forest_bandits1", "deep_forest_bandits2", "deep_forest_bandits3", "deep_forest_bandits4", "deep_forest_bandits5"]
		for index in expected_forest_ids.size():
			_check_route(forest, "ForestBackdrop/Bandits" if index == 0 else "ForestBackdrop/Bandits%d" % (index + 1), expected_forest_ids[index], "Normal", NORMAL_MALE, NORMAL_FEMALE)
		forest.free()

	var pinehill := (load(PINEHILL) as PackedScene).instantiate() as Node2D
	_expect(pinehill != null, "canonical Pinehill instantiates")
	if pinehill != null:
		var old_lady := pinehill.get_node_or_null("old_adult_women") as CharacterBody2D
		var old_lady_foot_size := Vector2.ZERO
		if old_lady != null:
			var foot := old_lady.get_node_or_null("FootCollision") as CollisionShape2D
			if foot != null and foot.shape is RectangleShape2D:
				old_lady_foot_size = (foot.shape as RectangleShape2D).size
		ENCOUNTER_SCRIPT.install_for_scene(pinehill, ENCOUNTER_SCRIPT)
		ENCOUNTER_SCRIPT.install_for_scene(pinehill, ENCOUNTER_SCRIPT)
		OLD_MAN_SCRIPT.install_for_scene(pinehill, OLD_MAN_SCRIPT)
		OLD_MAN_SCRIPT.install_for_scene(pinehill, OLD_MAN_SCRIPT)
		var expected_pinehill_ids := ["pinehill_bandits1", "pinehill_bandits2", "pinehill_bandits3", "pinehill_bandits4"]
		for index in expected_pinehill_ids.size():
			_check_route(pinehill, "Bandits" if index == 0 else "Bandits%d" % (index + 1), expected_pinehill_ids[index], "Difficult", NORMAL_MALE, NORMAL_FEMALE)
		_check_route(pinehill, "display-kase yung wizard sa labas lang", "pinehill_wizard", "Difficult", WIZARD_MALE, WIZARD_FEMALE)
		_expect(old_lady != null and old_lady.get_children().filter(func(child: Node) -> bool: return child.name == "ProgressionOldManInteraction").size() == 1, "existing Old Lady receives one interaction adapter")
		_expect(old_lady != null and not old_lady.is_physics_processing(), "quest-critical Old Lady is stationary")
		var foot_after := old_lady.get_node_or_null("FootCollision") as CollisionShape2D if old_lady != null else null
		_expect(foot_after != null and foot_after.shape is RectangleShape2D and (foot_after.shape as RectangleShape2D).size == old_lady_foot_size, "Old Lady foot collision is unchanged")
		pinehill.free()

	var quest_source := FileAccess.get_file_as_string("res://world/QuestUI.gd")
	_expect(quest_source.contains(TEACHER_MALE) and quest_source.contains(TEACHER_FEMALE), "final Teacher keeps both original gender routes")
	_expect(not quest_source.to_lower().contains("questioncontainer"), "final Teacher adds no replacement question container")

	var failed := 0
	for check in checks:
		if not bool(check.get("passed", false)):
			failed += 1
	var evidence := {"passed": checks.size() - failed, "failed": failed, "checks": checks, "live_network_calls": 0}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	print("FINAL_WORLD_ROUTING_TEST " + JSON.stringify(evidence))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)


func _check_route(world: Node2D, actor_name: String, encounter_id: String, difficulty: String, male_scene: String, female_scene: String) -> void:
	var actor := world.get_node_or_null(actor_name)
	var components: Array[Node] = []
	if actor != null:
		components.assign(actor.get_children().filter(func(child: Node) -> bool: return child.name == "ProgressionBattleEncounter"))
	_expect(actor != null and components.size() == 1, actor_name + " receives exactly one encounter trigger")
	if components.size() != 1:
		return
	var component := components[0]
	var route: Dictionary = component.get("_route")
	_expect(String(route.get("encounter_id", "")) == encounter_id, encounter_id + " has stable independent ID")
	_expect(String(route.get("difficulty", "")) == difficulty, encounter_id + " uses " + difficulty + " difficulty")
	GameState.gender = "male"
	_expect(String(component.call("_battle_scene_path")) == male_scene, encounter_id + " male route")
	GameState.gender = "female"
	_expect(String(component.call("_battle_scene_path")) == female_scene, encounter_id + " female route")
