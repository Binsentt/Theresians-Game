extends SceneTree

const ACTIVE_SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/new_game_scene.tscn",
	"res://scenes/loading_screen.tscn",
	"res://scenes/oak_leaf_village.tscn",
	"res://world/player_house_outside_door.tscn",
	"res://world/npc_house_outside_door.tscn",
	"res://world/teacher_house_outside_door.tscn",
	"res://scenes/city_of_knowledge.tscn",
	"res://scenes/2nd Village/Pinehill Village.tscn",
	"res://interiors/player_house.tscn",
	"res://interiors/npc_house.tscn",
	"res://interiors/teacher_house.tscn",
	"res://interiors/school.tscn",
	"res://interiors/hotel.tscn",
	"res://leaderboard_scene.tscn"
]

var _failures: Array[String] = []
var _log_lines: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for scene_path in ACTIVE_SCENES:
		_log_lines.append("SMOKE_TEST %s" % scene_path)
		print(_log_lines.back())
		if not await _load_scene(scene_path):
			break

	_write_output()
	if _failures.is_empty():
		_log_lines.append("SMOKE_TEST PASSED")
		print("SMOKE_TEST PASSED")
		_write_output()
		quit(0)
		return

	_log_lines.append("SMOKE_TEST FAILED")
	print("SMOKE_TEST FAILED")
	_write_output()
	push_error("Scene smoke test failed:\n%s" % "\n".join(_failures))
	quit(1)

func _load_scene(scene_path: String) -> bool:
	if not ResourceLoader.exists(scene_path):
		_failures.append("Missing scene: %s" % scene_path)
		return false

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		_failures.append("Unable to load scene resource: %s" % scene_path)
		return false

	var result := change_scene_to_packed(packed_scene)
	if result != OK:
		_failures.append("Unable to change scene: %s (code %d)" % [scene_path, result])
		return false

	await process_frame
	await process_frame
	return true

func _write_output() -> void:
	var output_path := ProjectSettings.globalize_path("res://tools/scene_smoke_test_output.txt")
	var output_file := FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		return

	output_file.store_string("\n".join(_log_lines + _failures))
	output_file.close()
