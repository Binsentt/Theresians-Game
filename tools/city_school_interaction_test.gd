extends Node

## Project-context interaction check for the existing E/Space + mobile ACT
## input path used by the School Teacher interaction.

const SCHOOL := "res://interiors/school.tscn"
const PROFILE := {
	"player_name": "City Interaction Fixture",
	"gender": "male",
	"grade_level": "Grade 1",
	"student_id": "87654321",
	"parent_id": "123456",
	"learning_cycle": {"version": 0, "started_at": ""},
}

var _checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
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

	_expect(await _load_scene(SCHOOL), "School loads through the existing scene architecture")
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

	player.global_position = area.global_position
	area.call("_on_body_entered", player)
	await _wait_frames(2)
	_expect(teacher.can_interact(), "Teacher is interactable only at nearby School range")
	_expect(area.can_interact(), "School interaction sensor registers the nearby player")

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


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if check.get("passed", false) != true:
			failed += 1
	print("CITY_SCHOOL_INTERACTION_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(10.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
