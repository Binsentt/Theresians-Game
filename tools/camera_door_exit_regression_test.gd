extends Node

const OAKLEAF := "res://scenes/oak_leaf_village.tscn"
const CITY := "res://scenes/city_of_knowledge.tscn"
const PLAYER_SCENES := {
	"male": "res://player/player_male.tscn",
	"female": "res://player/player_female.tscn",
}
const CITY_SPAWN := Vector2(1172, 96)
const OAKLEAF_RETURN_SPAWN := Vector2(44, 508)

var _checks: Array[Dictionary] = []
var _state: Node
var _remote_stub: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_live_services()
	_state = get_node("/root/GameState")
	_state.set_script(load("res://tools/preservation_regression_state.gd"))
	_state.fixture_path = "user://saves/camera_door_exit_%d.json" % Time.get_ticks_usec()
	_state.start_new_game({
		"player_name": "Camera Door Exit Fixture",
		"gender": "male",
		"grade_level": "Grade 1",
		"student_id": "88000003",
		"parent_id": "880003",
	}, false)

	await _test_player_cameras()
	_test_door_bindings()
	await _test_exit_lifecycle()

	var failed := _checks.filter(func(row: Dictionary) -> bool: return not bool(row.get("passed", false))).size()
	print("CAMERA_DOOR_EXIT_REGRESSION_TEST " + JSON.stringify({
		"passed": _checks.size() - failed,
		"failed": failed,
		"checks": _checks,
		"live_network_calls": 0,
	}))
	if FileAccess.file_exists(_state.fixture_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_state.fixture_path))
	# Keep the Godot process alive long enough for MCP to collect the result;
	# the first exit call may legitimately transition the current scene.
	print("CAMERA_DOOR_EXIT_REGRESSION_STATUS " + ("PASS" if failed == 0 else "FAIL"))


func _remove_live_services() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	_remote_stub = Node.new()
	_remote_stub.name = "RemoteSync"
	_remote_stub.set_script(load("res://tools/camera_door_exit_remote_stub.gd"))
	get_tree().root.add_child(_remote_stub)


func _test_player_cameras() -> void:
	var bounds := MapCameraBounds.new()
	bounds.limit_left = 0
	bounds.limit_right = 1280
	bounds.limit_top = -16
	bounds.limit_bottom = 640
	get_tree().root.add_child(bounds)
	for gender in PLAYER_SCENES:
		_state.gender = gender
		var player := (load(PLAYER_SCENES[gender]) as PackedScene).instantiate() as Node2D
		get_tree().root.add_child(player)
		await get_tree().process_frame
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		_expect(camera != null, gender + " Player keeps its Camera2D")
		if camera != null:
			_expect(camera.limit_left <= -1000000 and camera.limit_right >= 1000000 and camera.limit_top <= -1000000 and camera.limit_bottom >= 1000000, gender + " camera is not clamped by map bounds")
			camera.position_smoothing_enabled = false
			for position in [Vector2(0, 0), Vector2(1280, 0), Vector2(0, 640), Vector2(1280, 640)]:
				player.global_position = position
				await get_tree().process_frame
				_expect(camera.global_position.distance_to(player.global_position) < 0.1, gender + " camera follows player at " + str(position))
		player.queue_free()
		await get_tree().process_frame
	bounds.queue_free()


func _test_door_bindings() -> void:
	var oak := (load(OAKLEAF) as PackedScene).instantiate() as Node2D
	var city_door := (load("res://Door-Navigations-Scene2Scene/go_to_city_of_knowledge.tscn") as PackedScene).instantiate()
	var oak_return_door := (load("res://Door-Navigations-Scene2Scene/go_to_oak_leaf_village.tscn") as PackedScene).instantiate()
	var source_door := oak.get_node_or_null("Go-to-City-of-Knowledge") as Node
	_expect(source_door != null, "Oakleaf City door exists")
	if source_door != null:
		_expect(String(source_door.get("destination_scene_path")) == CITY, "Oakleaf City door stores the canonical City scene path")
	_expect(Vector2(city_door.get("destination_spawn_position")) == CITY_SPAWN, "City entrance uses the beside-exit spawn")
	_expect(String(city_door.get("destination_scene_path")) == CITY, "Canonical City door destination remains City")
	_expect(Vector2(oak_return_door.get("destination_spawn_position")) == OAKLEAF_RETURN_SPAWN, "City return uses the beside-exit Oakleaf spawn")
	_expect(String(oak_return_door.get("destination_scene_path")) == OAKLEAF, "City return destination remains Oakleaf")
	if source_door != null:
		_state.queue_scene_spawn(String(source_door.get("destination_scene_path")), Vector2.ZERO, "left")
		var pending: Dictionary = _state.consume_pending_scene_spawn(CITY)
		_expect(not pending.is_empty() and Vector2(pending.get("position", Vector2.ZERO)) == Vector2.ZERO, "Oakleaf City handoff is consumable by the canonical City scene")
	oak.free()
	city_door.free()
	oak_return_door.free()


func _test_exit_lifecycle() -> void:
	var settings_scene := load("res://scenes/Settings-Ingame/settings_ingame.tscn") as PackedScene
	var settings := settings_scene.instantiate() as Control
	get_tree().root.add_child(settings)
	await get_tree().process_frame
	var player := CharacterBody2D.new()
	player.add_to_group("player_character")
	get_tree().root.add_child(player)
	get_tree().current_scene = self
	settings.call("_on_exit_confirmed")
	settings.call("_on_exit_confirmed")
	var exit_state: Variant = settings.get("_exit_in_progress")
	_expect(exit_state != null, "Exit lifecycle exposes a guarded in-progress state")
	_expect(int(_state.fixture_save_count) == 1, "Repeated YES input saves exactly once before async cleanup")
	var controller_source := FileAccess.get_file_as_string("res://scenes/Settings-Ingame/settings_ingame_controller.gd")
	_expect(controller_source.contains("request_end_playtime_session"), "Exit lifecycle retains the playtime-session close request")


func _expect(condition: bool, label: String) -> void:
	_checks.append({"label": label, "passed": condition})
	if not condition:
		push_error(label)
