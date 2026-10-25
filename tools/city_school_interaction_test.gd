extends Node

## Project-context interaction check for the existing E/Space + mobile ACT
## input path used by the School Teacher interaction.

const SCHOOL := "res://interiors/school.tscn"
const CITY := "res://scenes/city_of_knowledge.tscn"
const PROFILE := {
	"player_name": "City Interaction Fixture",
	"gender": "male",
	"grade_level": "Grade 1",
	"student_id": "87654321",
	"parent_id": "123456",
	"learning_cycle": {"version": 0, "started_at": ""},
}

var _checks: Array[Dictionary] = []
var _diagnostics: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	_expect(http != null and bool(http.call("is_local_qa_mode")), "runtime remains in local QA mode before City transitions")
	_expect(remote != null and bool(remote.call("_remote_writes_blocked")), "RemoteSync blocks every remote write during City transitions")
	var state := get_node("/root/GameState")
	state.start_new_game(PROFILE, false)
	state.city_of_knowledge_unlocked = true
	state.city_first_arrival_seen = true
	state.current_task_index = state.CITY_SCHOOL_TASK_INDEX
	state.current_quest = state.get_current_quest_text()
	state.set_mode(state.GameMode.EXPLORATION)
	InputManager.unlock_input("door_transition")
	InputManager.clear_mobile_state()

	_expect(InputMap.has_action("interact"), "shared interact action exists")
	var has_e := false
	var has_space := false
	for event in InputMap.action_get_events("interact"):
		var key_event := event as InputEventKey
		if key_event == null:
			continue
		has_e = has_e or key_event.physical_keycode == KEY_E or key_event.keycode == KEY_E
		has_space = has_space or key_event.physical_keycode == KEY_SPACE or key_event.keycode == KEY_SPACE
	_expect(has_e and has_space, "E and Space remain mapped to the shared interact action")

	_expect(await _load_scene(CITY), "City of Knowledge loads through the existing scene architecture")
	var city := get_tree().current_scene
	var city_player := get_tree().get_first_node_in_group("player_character") as Node2D
	var school_door := city.get_node_or_null("SchoolDoor") as Door if city != null else null
	var city_school_spawn := city.get_node_or_null("spawn_from_school") as Marker2D if city != null else null
	_expect(city_player != null and school_door != null and city_school_spawn != null, "City exposes its live player, School entrance, and normal School-return spawn")
	if city_player == null or school_door == null or city_school_spawn == null:
		_finish()
		return
	var city_school_door_shape := school_door.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var city_school_rect := city_school_door_shape.shape.get_rect() if city_school_door_shape != null and city_school_door_shape.shape != null else Rect2()
	var city_school_trigger_rect := Rect2(city_school_door_shape.global_position + city_school_rect.position - Vector2(8, 8), city_school_rect.size + Vector2(16, 16)) if city_school_door_shape != null else Rect2()
	_expect(not city_school_trigger_rect.has_point(city_school_spawn.global_position), "Normal City School-return spawn is outside the entrance trigger")
	var entered_school := await _walk_into_door(city_player, school_door, city_school_spawn.global_position, InputManager.DIRECTION_UP, SCHOOL, "City → School")
	_expect(entered_school, "Joystick-equivalent walking enters School through its real touch door")
	await _wait_frames(4)
	var school := get_tree().current_scene
	var teacher := school.get_node_or_null("Teacher")
	var area := school.get_node_or_null("Teacher/Area2D2") as Area2D
	var panel := school.get_node_or_null("CanvasLayer/Panel")
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	_expect(teacher != null and area != null and panel != null and player != null, "School exposes the existing Teacher, interaction sensor, dialogue host, and player")
	if teacher == null or area == null or panel == null or player == null:
		_finish()
		return

	player.global_position = teacher.global_position + Vector2(28, 0)
	await _wait_physics_frames(3)
	var teacher_sensor_shape := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_diagnostics = {
		"teacher_position": teacher.global_position,
		"teacher_global_scale": teacher.global_scale,
		"sensor_global_scale": area.global_scale,
		"sensor_shape_size": (teacher_sensor_shape.shape as RectangleShape2D).size if teacher_sensor_shape != null and teacher_sensor_shape.shape is RectangleShape2D else Vector2.ZERO,
		"sensor_global_position": teacher_sensor_shape.global_position if teacher_sensor_shape != null else area.global_position,
		"player_position": player.global_position,
		"sensor_overlaps_player": area.overlaps_body(player),
		"sensor_nearby_players": Array(area.get("_nearby_players")).size(),
		"teacher_available": teacher.can_interact(),
		"sensor_enabled": bool(area.get("interaction_enabled")),
		"active_interactable_is_teacher": InteractionManager.get_active_interactable() == area,
		"game_mode": state.get_mode(),
	}
	var sensor_world_size: Vector2 = teacher_sensor_shape.shape.size * area.global_scale.abs() if teacher_sensor_shape != null and teacher_sensor_shape.shape is RectangleShape2D else Vector2.ZERO
	_expect(sensor_world_size.is_equal_approx(Vector2(72.0, 40.0)), "School Teacher has a usable world-sized proximity sensor")
	_expect(teacher.can_interact(), "Teacher is interactable only at nearby School range")
	_expect(area.can_interact() and InteractionManager.get_active_interactable() == area, "real physics overlap selects the Math Teacher from a reasonable beside-the-Teacher position")

	InputManager.set_mobile_interact_pressed(true)
	await _wait_frames(2)
	InputManager.set_mobile_interact_pressed(false)
	await _wait_frames(2)
	_expect(panel.is_dialogue_active(), "mobile ACT opens the existing School dialogue")
	_expect(state.get_mode() == state.GameMode.DIALOGUE, "School Teacher interaction enters the shared dialogue mode")
	if panel.is_dialogue_active():
		panel.call("_close_dialogue")
	await _wait_frames(3)
	InputManager.clear_mobile_state()
	_expect(state.get_mode() == state.GameMode.EXPLORATION, "closing School dialogue restores exploration")
	_expect(int(area.get("interaction_priority")) > 20, "Math Teacher priority beats nearby decorative NPC interactions")
	var exit_door := school.get_node_or_null("ExitDoor") as Door
	_expect(exit_door != null and exit_door.destination_scene_path == "res://scenes/city_of_knowledge.tscn" and exit_door.destination_spawn_marker_name == "spawn_from_school" and not exit_door.use_return_context, "School exit uses its dedicated City spawn instead of stale return context")
	var school_player_spawn := school.get_node_or_null("PlayerSpawn") as Marker2D
	_expect(exit_door != null and school_player_spawn != null, "School exposes the live exit and normal interior spawn")
	if exit_door != null and school_player_spawn != null:
		var exited_city := await _walk_into_door(player, exit_door, school_player_spawn.global_position, InputManager.DIRECTION_LEFT, CITY, "School → City")
		_expect(exited_city, "Joystick-equivalent walking exits School through its real touch door")
		city = get_tree().current_scene
		player = get_tree().get_first_node_in_group("player_character") as Node2D
		var school_spawn := city.get_node_or_null("spawn_from_school") as Marker2D if city != null else null
		_expect(city != null and school_spawn != null and player != null and player.global_position.is_equal_approx(school_spawn.global_position), "School → City spawns at the dedicated exterior School marker")
		school_door = city.get_node_or_null("SchoolDoor") as Door if city != null else null
		var entrance_shape := school_door.get_node_or_null("CollisionShape2D") as CollisionShape2D if school_door != null else null
		var entrance_rect := entrance_shape.shape.get_rect() if entrance_shape != null and entrance_shape.shape != null else Rect2()
		var safe_rect := Rect2(entrance_shape.global_position + entrance_rect.position - Vector2(8, 8), entrance_rect.size + Vector2(16, 16)) if entrance_shape != null else Rect2()
		_expect(school_spawn != null and not safe_rect.has_point(school_spawn.global_position), "School arrival marker is outside the entrance trigger with a player-clearance margin")
		await _wait_physics_frames(4)
		_expect(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == CITY, "School arrival is outside the School transition trigger and does not immediately re-enter")
		var second_school_entrance := city.get_node_or_null("SchoolDoor") as Door if city != null else null
		_expect(second_school_entrance != null and player != null and school_spawn != null, "School entrance is available for a second visit")
		if second_school_entrance != null and player != null and school_spawn != null:
			var reentered_school := await _walk_into_door(player, second_school_entrance, school_spawn.global_position, InputManager.DIRECTION_UP, SCHOOL, "City → School (re-entry)")
			_expect(reentered_school, "Second City → School entry completes by player movement")
			var second_school := get_tree().current_scene
			var second_player := get_tree().get_first_node_in_group("player_character") as Node2D
			_expect(second_school != null and second_school.scene_file_path == SCHOOL and second_player != null, "Re-entered School has a live player")
			var second_exit := second_school.get_node_or_null("ExitDoor") as Door if second_school != null else null
			var second_player_spawn := second_school.get_node_or_null("PlayerSpawn") as Marker2D if second_school != null else null
			_expect(second_exit != null and second_player_spawn != null, "Second School visit retains its exit and spawn")
			if second_exit != null and second_player_spawn != null and second_player != null:
				var exited_again := await _walk_into_door(second_player, second_exit, second_player_spawn.global_position, InputManager.DIRECTION_LEFT, CITY, "School → City (second exit)")
				_expect(exited_again, "Second School → City exit completes by player movement")
				var second_city := get_tree().current_scene
				var second_city_player := get_tree().get_first_node_in_group("player_character") as Node2D
				var second_school_spawn := second_city.get_node_or_null("spawn_from_school") as Marker2D if second_city != null else null
				_expect(second_city != null and second_city.scene_file_path == CITY and second_city_player != null and second_school_spawn != null and second_city_player.global_position.is_equal_approx(second_school_spawn.global_position), "Second School → City exit returns to the dedicated spawn")
				await _wait_physics_frames(4)
				_expect(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == CITY, "Repeated School entry and exit rearms triggers without retrigger or transition lock")
	_finish()


func _load_scene(path: String) -> bool:
	if get_tree().change_scene_to_file(path) != OK:
		return false
	for _index in 240:
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _wait_physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _wait_for_scene(scene_path: String) -> void:
	for _index in 240:
		await get_tree().process_frame
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == scene_path:
			await _wait_physics_frames(2)
			return


func _walk_into_door(player: Node2D, door: Door, spawn_position: Vector2, direction: String, expected_scene_path: String, route_label: String) -> bool:
	if player == null or door == null:
		_expect(false, "%s has a player and Door" % route_label)
		return false
	var origin_scene := get_tree().current_scene
	if origin_scene == null:
		_expect(false, "%s begins in a live scene" % route_label)
		return false
	player.global_position = spawn_position
	await _wait_physics_frames(2)
	var start_position := player.global_position
	var last_player_position := start_position
	var fade_was_visible := false
	var scene_reached := false
	InputManager.set_mobile_direction(StringName(direction), true)
	for _frame in 180:
		await get_tree().process_frame
		var fade_layer := origin_scene.get_node_or_null("DoorFadeTransitionLayer")
		var fade_rect := fade_layer.get_child(0) as ColorRect if fade_layer != null and fade_layer.get_child_count() > 0 else null
		if fade_rect != null and fade_rect.color.a > 0.0:
			fade_was_visible = true
		await get_tree().physics_frame
		if is_instance_valid(player):
			last_player_position = player.global_position
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == expected_scene_path:
			scene_reached = true
			break
	InputManager.set_mobile_direction(StringName(direction), false)
	InputManager.clear_mobile_state()
	var travel_distance := start_position.distance_to(last_player_position)
	_expect(travel_distance > 0.0, "%s moved the real player body before triggering" % route_label)
	_expect(fade_was_visible, "%s displayed the existing black fade before scene change" % route_label)
	return scene_reached


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if check.get("passed", false) != true:
			failed += 1
	var report := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks, "diagnostics": _diagnostics}
	var report_json := JSON.stringify(report)
	print("CITY_SCHOOL_INTERACTION_TEST " + report_json)
	var report_file := FileAccess.open("user://city_school_interaction_result.json", FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(report_json)
		report_file.close()
	await get_tree().create_timer(10.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
