extends Node

const SETTINGS_SCENE := preload("res://scenes/Settings-Ingame/settings_ingame.tscn")
const GAME_OVER_SCENE := preload("res://scenes/game_over_scene.tscn")
const NEW_GAME_SCENE := preload("res://scenes/new_game_scene.tscn")
const PROFILE_HTTP_STUB := preload("res://tools/test_profile_http_api_stub.gd")
const EXIT_REMOTE_STUB := preload("res://tools/settings_exit_wait_remote_stub.gd")
const OAKLEAF_SCENE := "res://scenes/oak_leaf_village.tscn"
const PINEHILL_SCENE := "res://scenes/2nd Village/Pinehill Village.tscn"

var _checks := 0
var _failures: Array[String] = []
var _save_directory := ""
var _previous_save_directory := ""
var _created_save_directory := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	if not HttpApi.is_local_qa_profile_active():
		push_error("Game Over QA refused to run without local-only startup selected before autoload initialization.")
		get_tree().quit(1)
		return
	HttpApi.enable_local_qa_mode("http://127.0.0.1:5000")
	RemoteSync.enable_local_qa_mode()
	var state := get_node("/root/GameState")
	_previous_save_directory = state.get_save_directory()
	_save_directory = "user://qa_local_saves/game_over_retry_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_directory := ProjectSettings.globalize_path(_save_directory)
	_assert(not DirAccess.dir_exists_absolute(absolute_directory), "Refuse to reuse an existing Game Over QA save directory")
	if DirAccess.dir_exists_absolute(absolute_directory):
		await _finish()
		return
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		_failures.append("Could not create the isolated Game Over QA save directory")
		await _finish()
		return
	_created_save_directory = true
	state.set("_save_directory", _save_directory)
	state.device_installation_id = "game-over-qa-device-%d" % OS.get_process_id()

	_assert(HttpApi.is_local_qa_mode(), "QA API startup is local-only before gameplay tests")
	var game_over_ready := await _assert_game_over_yes_is_enabled_and_connected()
	_assert(game_over_ready, "Game Over YES is enabled and connected independently of manual saves")
	await _assert_settings_geometry()
	await _assert_battle_lives_shared_pool()
	await _assert_linked_student_reuse()
	_assert_teacher_quest_retry()
	_assert_later_quest_retry()
	_assert_manual_save_and_student_isolation()
	await _assert_exit_flow()

	_cleanup_save_directory()
	state.set("_save_directory", _previous_save_directory)
	await _finish()


func _assert_game_over_yes_is_enabled_and_connected() -> bool:
	var game_over := GAME_OVER_SCENE.instantiate() as Control
	add_child(game_over)
	await get_tree().process_frame
	var yes_button := game_over.get_node_or_null("CenterContainer/PanelContainer/VBoxContainer/ButtonsRow/YesButton") as Button
	if yes_button == null:
		_assert(false, "Game Over YES button exists")
		game_over.queue_free()
		return false
	_assert(not yes_button.disabled, "Game Over YES remains enabled without a manual save")
	_assert(yes_button.pressed.is_connected(Callable(game_over, "_on_yes_button_pressed")), "Game Over YES invokes hidden checkpoint recovery")
	var sound := game_over.get_node_or_null("GameOverSound") as AudioStreamPlayer
	if sound != null:
		sound.stop()
	game_over.queue_free()
	return true


func _assert_settings_geometry() -> void:
	for viewport_size in [Vector2i(1215, 545), Vector2i(844, 390), Vector2i(640, 360), Vector2i(390, 844)]:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var settings := SETTINGS_SCENE.instantiate() as Control
		viewport.add_child(settings)
		await get_tree().process_frame
		await get_tree().process_frame
		settings.call("_center_popup")
		var controls: Array[Control] = []
		for node_path in [
			"SettingsPopup/TextureRect/ResumeBtn",
			"SettingsPopup/TextureRect/SaveBtn",
			"SettingsPopup/TextureRect/LoadGameBtn",
			"SettingsPopup/TextureRect/ExitBtn",
			"SettingsPopup/TextureRect/MusicVolume",
			"SettingsPopup/TextureRect/SfxVolume",
		]:
			var control := settings.get_node_or_null(node_path) as Control
			_assert(control != null, "%s exists at %s" % [node_path, viewport_size])
			if control != null:
				controls.append(control)
		for index in range(mini(4, controls.size())):
			var button := controls[index]
			_assert(button.size.is_equal_approx(Vector2(220.0, 52.0)), "%s stays full size at %s" % [button.name, viewport_size])
			_assert(button.get_global_rect().size.is_equal_approx(Vector2(220.0, 52.0)), "%s touch hitbox stays full size at %s" % [button.name, viewport_size])
			_assert(_rect_inside(button.get_global_rect(), Rect2(Vector2.ZERO, Vector2(viewport_size))), "%s stays inside the viewport at %s" % [button.name, viewport_size])
			var label := button.get_node_or_null("Label") as Label
			_assert(label != null and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "%s label remains centered at %s" % [button.name, viewport_size])
		var load_button := settings.get_node("SettingsPopup/TextureRect/LoadGameBtn") as Button
		var enabled_rect := load_button.get_global_rect()
		load_button.disabled = true
		_assert(load_button.get_global_rect().is_equal_approx(enabled_rect), "Disabled Load remains full-size at %s" % viewport_size)
		load_button.disabled = false
		for index in range(4, controls.size()):
			var slider := controls[index]
			_assert(slider.get_global_rect().size.is_equal_approx(Vector2(220.0, 30.0)), "%s touch area stays full size at %s" % [slider.name, viewport_size])
			_assert(_rect_inside(slider.get_global_rect(), Rect2(Vector2.ZERO, Vector2(viewport_size))), "%s stays inside the viewport at %s" % [slider.name, viewport_size])
		for index in range(controls.size()):
			for other_index in range(index + 1, controls.size()):
				_assert(not controls[index].get_global_rect().intersects(controls[other_index].get_global_rect()), "%s and %s do not overlap at %s" % [controls[index].name, controls[other_index].name, viewport_size])
		viewport.queue_free()
		await get_tree().process_frame


func _assert_linked_student_reuse() -> void:
	var http := get_node("/root/HttpApi")
	http.set_script(PROFILE_HTTP_STUB)
	http.set("profile_result", {
		"ok": true,
		"status": 200,
		"body": {
			"ok": true,
			"exists": true,
			"should_block": true,
			"error": "Student ID already has an existing game profile. Please use Load Game.",
			"canonical_profile": {"name": "Linked QA Student", "grade_level": "Grade 4", "section": "Amethyst"},
		},
	})
	var new_game := NEW_GAME_SCENE.instantiate() as Control
	add_child(new_game)
	await get_tree().process_frame
	var controller := new_game.get_node("TextureRect2")
	controller.get_node("StudentParentId/StudentIdInput").text = "12345678"
	controller.get_node("StudentParentId/ParentIdInput").text = "654321"
	var first: Dictionary = await controller.call("_validate_ids_with_backend")
	var second: Dictionary = await controller.call("_validate_ids_with_backend")
	_assert(bool(first.get("ok", false)) and bool(second.get("ok", false)), "Same valid linked Student/Parent pair can be reused without treating it as a new registration")
	controller.get_node("StudentParentId/ParentIdInput").text = "999999"
	http.set("profile_result", {
		"ok": true,
		"status": 200,
		"body": {"ok": true, "should_block": true, "error": "Parent ID is not linked to this Student."},
	})
	var wrong_parent: Dictionary = await controller.call("_validate_ids_with_backend")
	_assert(not bool(wrong_parent.get("ok", false)), "Reusing an existing Student profile does not bypass Parent-link validation")
	var requests: Array = http.get("requests")
	_assert(requests.size() == 3, "Linked-pair reuse and invalid-parent checks use only the canonical profile check")
	for request in requests:
		_assert(String(request.get("kind", "")) == "get" and String(request.get("path", "")).begins_with("/api/game/profile/check/"), "Linked-pair retry performs no duplicate account-registration request")
	new_game.queue_free()
	await get_tree().process_frame


func _assert_teacher_quest_retry() -> void:
	var state := get_node("/root/GameState")
	_configure_student(state, "88001001", "880101", GameState.OAKLEAF_BANDIT_TASK_INDEX, OAKLEAF_SCENE, Vector2(710.0, 292.0))
	state.oakleaf_defeated_bandits = {}
	state.oakleaf_boss_defeated = false
	var expected_quest := String(state.current_quest)
	_assert(not state.save_checkpoint().is_empty(), "Teacher-given Oakleaf quest writes a hidden checkpoint")
	state.capture_runtime(OAKLEAF_SCENE, Vector2(990.0, 440.0))
	var game_over_result: Dictionary = _lose_three_encounters(state, "oakleaf_bandits1", GameState.OAKLEAF_BANDIT_TASK_INDEX)
	_assert(bool(game_over_result.get("game_over", false)), "Three failed Oakleaf encounters reach Game Over")
	var recovery: Dictionary = state.call("restore_game_over_checkpoint")
	_assert(bool(recovery.get("ok", false)), "Game Over retry restores a hidden checkpoint without a manual save")
	_assert(String(recovery.get("source", "")) == "quest_start_checkpoint", "Teacher quest retry selects its saved quest-start checkpoint")
	_assert(String(state.student_id) == "88001001" and String(state.parent_id) == "880101", "Game Over retry preserves the linked Student identity")
	_assert(int(state.current_lives) == 3, "Game Over retry restores three lives")
	_assert(String(state.current_quest) == expected_quest and int(state.current_task_index) == GameState.OAKLEAF_BANDIT_TASK_INDEX, "The active Teacher-given quest remains active")
	_assert(String(state.current_scene_path) == OAKLEAF_SCENE and state.player_position.is_equal_approx(Vector2(710.0, 292.0)), "Teacher quest returns to its quest-start scene and position")
	_assert(not state.is_oakleaf_bandit_defeated("oakleaf_bandits1"), "The failed Oakleaf encounter is not marked complete")
	_assert(state.list_saves().is_empty(), "Hidden Game Over recovery does not create a visible manual save")
	var retry_context: Dictionary = state.begin_encounter({"encounter_id": "oakleaf_bandits1", "quest_checkpoint": GameState.OAKLEAF_BANDIT_TASK_INDEX})
	_assert(String(retry_context.get("encounter_id", "")) == "oakleaf_bandits1", "The failed Oakleaf battle can be attempted again")
	state.end_battle()


func _assert_later_quest_retry() -> void:
	var state := get_node("/root/GameState")
	_configure_student(state, "88001002", "880102", GameState.PINEHILL_BANDIT_TASK_INDEX, PINEHILL_SCENE, Vector2(258.0, 348.0))
	state.pinehill_unlocked = true
	state.pinehill_old_man_completed = true
	state.pinehill_defeated_bandits = {}
	var expected_quest := String(state.current_quest)
	_assert(not state.save_checkpoint().is_empty(), "Later Pinehill quest writes its own hidden checkpoint")
	state.capture_runtime(PINEHILL_SCENE, Vector2(860.0, 490.0))
	var game_over_result: Dictionary = _lose_three_encounters(state, "pinehill_bandits1", GameState.PINEHILL_BANDIT_TASK_INDEX)
	_assert(bool(game_over_result.get("game_over", false)), "Three failed Pinehill encounters reach Game Over")
	var recovery: Dictionary = state.call("restore_game_over_checkpoint")
	_assert(bool(recovery.get("ok", false)), "Later-story Game Over retry restores a hidden checkpoint")
	_assert(String(recovery.get("source", "")) == "quest_start_checkpoint", "Later quest retry selects its own quest-start checkpoint")
	_assert(String(state.current_quest) == expected_quest and int(state.current_task_index) == GameState.PINEHILL_BANDIT_TASK_INDEX, "Later retry keeps the Pinehill guard quest active")
	_assert(String(state.current_scene_path) == PINEHILL_SCENE and state.player_position.is_equal_approx(Vector2(258.0, 348.0)), "Later retry returns to Pinehill, not Teacher House")
	_assert(not state.is_progression_encounter_defeated("pinehill_bandits1"), "Failed Pinehill guard is not marked complete")
	_assert(int(state.current_lives) == 3 and String(state.student_id) == "88001002", "Later retry restores lives and preserves Student identity")


func _assert_manual_save_and_student_isolation() -> void:
	var state := get_node("/root/GameState")
	_configure_student(state, "88001003", "880103", GameState.CITY_SCHOOL_TASK_INDEX, "res://scenes/city_of_knowledge.tscn", Vector2(608.0, 272.0))
	state.city_of_knowledge_unlocked = true
	var manual_path := String(state.save_manual_game())
	_assert(not manual_path.is_empty(), "Manual save fixture is created only in the isolated QA directory")
	var before_data := FileAccess.get_file_as_string(manual_path) if not manual_path.is_empty() else ""
	state.capture_runtime("res://scenes/city_of_knowledge.tscn", Vector2(900.0, 410.0))
	_lose_three_encounters(state, "city_school_teacher", GameState.CITY_SCHOOL_TASK_INDEX)
	var recovery: Dictionary = state.call("restore_game_over_checkpoint")
	_assert(bool(recovery.get("ok", false)), "Student with a manual save can still use hidden Game Over recovery")
	_assert(FileAccess.get_file_as_string(manual_path) == before_data, "Game Over recovery leaves existing manual saves byte-for-byte unchanged")
	_assert(state.list_saves().size() == 1, "Existing manual save remains the only visible slot")
	var owner_a_checkpoint := "%s/save_88001003_current.json" % _save_directory
	_configure_student(state, "88001004", "880104", GameState.OAKLEAF_BANDIT_TASK_INDEX, OAKLEAF_SCENE, Vector2(300.0, 200.0))
	state.oakleaf_defeated_bandits = {}
	var isolated_recovery: Dictionary = state.call("restore_game_over_checkpoint")
	_assert(bool(isolated_recovery.get("ok", false)) and String(isolated_recovery.get("student_id", "")) == "88001004", "Another Student receives only their own safe fallback/checkpoint")
	_assert(state.peek_save_data(owner_a_checkpoint).is_empty(), "Another Student cannot read the first Student's checkpoint as a manual save")


func _assert_battle_lives_shared_pool() -> void:
	var state := get_node("/root/GameState")
	_configure_student(state, "88001005", "880105", GameState.OAKLEAF_BANDIT_TASK_INDEX, OAKLEAF_SCENE, Vector2(710.0, 292.0))
	state.oakleaf_defeated_bandits = {}
	state.save_checkpoint()
	_assert(state.list_saves().is_empty(), "Life-persistence QA uses no visible manual save")

	var first_health := await _create_player_health()
	_assert(int(first_health.get("health")) == 3, "First battle initializes the shared starting life pool")
	state.begin_encounter({"encounter_id": "qa_life_first", "quest_checkpoint": state.current_task_index})
	first_health.call("take_damage")
	_assert(int(state.current_lives) == 2 and int(first_health.get("health")) == 2, "First incorrect battle answer consumes one shared life")
	state.record_encounter_victory()
	first_health.queue_free()
	await get_tree().process_frame

	var second_health := await _create_player_health()
	_assert(int(second_health.get("health")) == 2, "Next Bandit battle starts with the two lives remaining after a win")
	state.begin_encounter({"encounter_id": "qa_life_second", "quest_checkpoint": state.current_task_index})
	second_health.call("take_damage")
	_assert(int(state.current_lives) == 1 and int(second_health.get("health")) == 1, "Second incorrect answer reduces the same pool to one")
	state.record_encounter_victory()
	var save_data: Dictionary = state.build_save_data()
	state.apply_save_data(save_data, false)
	_assert(int(state.current_lives) == 1, "Save/Load restores the remaining shared life count")
	second_health.queue_free()
	await get_tree().process_frame

	var third_health := await _create_player_health()
	_assert(int(third_health.get("health")) == 1, "A later battle starts with the one life restored by Save/Load")
	state.begin_encounter({"encounter_id": "qa_life_third", "quest_checkpoint": state.current_task_index})
	third_health.call("take_damage")
	_assert(int(state.current_lives) == 0 and int(third_health.get("health")) == 0, "Third incorrect answer exhausts the shared pool and reaches Game Over")
	third_health.queue_free()
	var recovery: Dictionary = state.restore_game_over_checkpoint()
	_assert(bool(recovery.get("ok", false)) and int(state.current_lives) == 3, "Game Over YES recovery restores exactly three lives")
	_assert(state.list_saves().is_empty(), "Shared life and Game Over recovery never create a manual save slot")
	await get_tree().process_frame


func _create_player_health() -> Node:
	var player_health := Node.new()
	player_health.name = "PlayerHealthQA"
	player_health.set_script(load("res://Battle/Battle-Enemy/PlayerHealth.gd"))
	var hearts := HBoxContainer.new()
	hearts.name = "Hearts"
	player_health.add_child(hearts)
	for heart_name in ["Heart1", "Heart2", "Heart3"]:
		var heart := TextureRect.new()
		heart.name = heart_name
		hearts.add_child(heart)
	add_child(player_health)
	await get_tree().process_frame
	return player_health


func _assert_exit_flow() -> void:
	var state := get_node("/root/GameState")
	var remote := get_node("/root/RemoteSync")
	var original_remote_script: Script = remote.get_script()
	remote.set_script(EXIT_REMOTE_STUB)
	remote.set("request_count", 0)

	_configure_student(state, "88001006", "880106", GameState.CITY_SCHOOL_TASK_INDEX, "res://scenes/city_of_knowledge.tscn", Vector2(608.0, 272.0))
	var empty_saves_before: Array = state.list_saves()
	_assert(empty_saves_before.is_empty(), "Exit-without-Save fixture starts with no manual saves")
	var current_scene := Node2D.new()
	current_scene.name = "SettingsExitQAContext"
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
	var settings := SETTINGS_SCENE.instantiate() as Control
	add_child(settings)
	await get_tree().process_frame
	settings.call("_on_settings_button_pressed")
	settings.call("_on_exit_pressed")
	_assert(settings.get("_exit_dialog").visible, "Exit opens exactly one confirmation before acting")
	settings.call("_on_exit_canceled")
	await get_tree().process_frame
	_assert(not get_tree().paused and get_tree().current_scene == current_scene, "Exit No resumes the same gameplay scene")
	_assert(int(remote.get("request_count")) == 0, "Exit No does not finalize Screen Time or invoke Exit")

	settings.call("_on_settings_button_pressed")
	settings.call("_on_exit_pressed")
	settings.call("_on_exit_confirmed")
	await get_tree().create_timer(0.2, true).timeout
	var exited_without_resume := get_tree().current_scene != current_scene \
			and get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn"
	_assert(exited_without_resume, "Exit Yes reaches Main Menu immediately without a Resume action")
	_assert(int(remote.get("request_count")) == 1, "Exit Yes finalizes Screen Time exactly once")
	_assert(state.list_saves().is_empty(), "Exit Yes without a prior manual save does not create one")
	if get_tree().paused:
		get_tree().paused = false
	if not exited_without_resume:
		await get_tree().create_timer(0.2, true).timeout
		var after_manual_unpause := get_tree().current_scene != current_scene \
				and get_tree().current_scene != null \
				and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn"
		_assert(after_manual_unpause, "Exit Yes eventually completes only after the test manually unpauses the tree (diagnostic)")
	if is_instance_valid(settings):
		settings.queue_free()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await get_tree().process_frame

	_configure_student(state, "88001007", "880107", GameState.CITY_SCHOOL_TASK_INDEX, "res://scenes/city_of_knowledge.tscn", Vector2(608.0, 272.0))
	var manual_path := String(state.save_manual_game())
	var manual_before := FileAccess.get_file_as_string(manual_path) if not manual_path.is_empty() else ""
	var saved_scene := Node2D.new()
	saved_scene.name = "SettingsExitWithSaveQAContext"
	get_tree().root.add_child(saved_scene)
	get_tree().current_scene = saved_scene
	var saved_settings := SETTINGS_SCENE.instantiate() as Control
	add_child(saved_settings)
	await get_tree().process_frame
	saved_settings.call("_on_settings_button_pressed")
	saved_settings.call("_on_exit_pressed")
	saved_settings.call("_on_exit_confirmed")
	await get_tree().create_timer(0.2, true).timeout
	var saved_exit_completed := get_tree().current_scene != saved_scene \
			and get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn"
	_assert(saved_exit_completed, "Exit Yes with a prior manual save also returns directly to Main Menu")
	_assert(not manual_path.is_empty() and FileAccess.get_file_as_string(manual_path) == manual_before, "Exit Yes leaves the prior manual save byte-for-byte unchanged")
	_assert(int(remote.get("request_count")) == 2, "The second Exit Yes finalizes Screen Time once for that session")
	if get_tree().paused:
		get_tree().paused = false
	if is_instance_valid(saved_settings):
		saved_settings.queue_free()
	if is_instance_valid(saved_scene):
		saved_scene.queue_free()
	remote.set_script(original_remote_script)
	await get_tree().process_frame


func _configure_student(state: Node, id: String, parent: String, task_index: int, scene_path: String, position: Vector2) -> void:
	state.call("start_new_game", {
		"player_name": "QA Retry Student",
		"gender": "female",
		"student_id": id,
		"parent_id": parent,
		"grade_level": "Grade 4",
	})
	state.set("_save_directory", _save_directory)
	state.device_installation_id = "game-over-qa-device-%d" % OS.get_process_id()
	state.current_task_index = task_index
	state.current_quest = state.get_current_quest_text()
	state.current_scene_path = scene_path
	state.player_position = position
	state.current_lives = state.max_lives
	state.encounter_context.clear()
	state.battle_active = false
	state.current_battle_enemy_path = NodePath()
	state.call("set_mode", GameState.GameMode.EXPLORATION)


func _lose_three_encounters(state: Node, encounter_id: String, task_index: int) -> Dictionary:
	var result: Dictionary = {}
	for attempt in range(3):
		state.call("begin_encounter", {
			"encounter_id": encounter_id,
			"quest_checkpoint": task_index,
			"source_scene_path": state.current_scene_path,
			"source_position": state.player_position,
		})
		state.current_lives = 0
		result = state.call("record_encounter_loss")
	return result


func _rect_inside(rect: Rect2, bounds: Rect2) -> bool:
	return bounds.encloses(rect)


func _cleanup_save_directory() -> void:
	if not _created_save_directory:
		return
	var absolute_directory := ProjectSettings.globalize_path(_save_directory)
	if not absolute_directory.replace("\\", "/").contains("/qa_local_saves/game_over_retry_"):
		push_error("Refusing Game Over QA cleanup outside its unique local QA directory")
		return
	var directory := DirAccess.open(absolute_directory)
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
			file_name = directory.get_next()
		directory.list_dir_end()
	DirAccess.remove_absolute(absolute_directory)
	_created_save_directory = false


func _assert(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GAME_OVER_SETTINGS_IDENTITY_QA_TEST passed=%d failed=0" % _checks)
	else:
		print("GAME_OVER_SETTINGS_IDENTITY_QA_TEST passed=%d failed=%d" % [_checks - _failures.size(), _failures.size()])
		for failure in _failures:
			push_error(failure)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
