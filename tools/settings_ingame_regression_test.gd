extends Node

const SETTINGS_SCENE := preload("res://scenes/Settings-Ingame/settings_ingame.tscn")
const LOAD_SCENE_PATH := "res://load_game_scene.tscn"
const QA_STUDENT_ID := "88001001"
const QA_PARENT_ID := "880101"

var _failures: Array[String] = []
var _checks := 0
var _qa_directory := ""
var _created_qa_directory := false
var _previous_save_directory := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Force all activity into local QA before writing any test save or opening a
	# scene with gameplay-side integrations.
	HttpApi.enable_local_qa_mode("http://127.0.0.1:5000")
	RemoteSync.enable_local_qa_mode()
	GameState.enable_local_qa_mode()
	_previous_save_directory = GameState.get_save_directory()
	_qa_directory = "%s/settings_ui_%d_%d" % [
		GameState.LOCAL_QA_SAVE_DIRECTORY,
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	var absolute_qa_directory := ProjectSettings.globalize_path(_qa_directory)
	if DirAccess.dir_exists_absolute(absolute_qa_directory):
		_failures.append("Refusing to reuse an existing Settings UI QA directory")
		await _finish()
		return
	if DirAccess.make_dir_recursive_absolute(absolute_qa_directory) != OK:
		_failures.append("Could not create the isolated Settings UI QA directory")
		await _finish()
		return
	_created_qa_directory = true
	GameState.set("_save_directory", _qa_directory)
	GameState.student_id = QA_STUDENT_ID
	GameState.parent_id = QA_PARENT_ID
	GameState.device_installation_id = "settings-ui-qa-device"
	GameState.player_name = "Settings QA Student"
	GameState.grade_level = "Grade 3"
	GameState.current_scene_path = "res://interiors/player_house.tscn"
	GameState.current_map = "Player House"
	_assert(GameState.save_manual_game().begins_with(_qa_directory + "/"), "Fixture creation uses the isolated Settings UI QA directory")

	var settings := SETTINGS_SCENE.instantiate() as Control
	get_tree().root.add_child(settings)
	get_tree().current_scene = settings
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_action_hitboxes_do_not_overlap(settings)
	_assert_child_labels_do_not_intercept(settings)
	_assert_confirmation_theme_and_modal_flags(settings)
	await _assert_modal_blocks_background(settings)

	var settings_source := FileAccess.get_file_as_string("res://scenes/Settings-Ingame/settings_ingame_controller.gd")
	var load_handler := _function_block(settings_source, "func _on_load_pressed()")
	var routes_to_load_list := load_handler.contains("change_scene_to_file(LOAD_GAME_SCENE)")
	_assert(routes_to_load_list, "Settings Load routes to the canonical Load Game scene instead of auto-loading the latest save")
	if routes_to_load_list:
		settings.call("_on_load_pressed")
		for _frame in range(12):
			await get_tree().process_frame
		var load_scene := get_tree().current_scene
		_assert(load_scene != null and load_scene.scene_file_path == LOAD_SCENE_PATH, "Settings Load opens the canonical Load Game scene")
		_assert(GameState.student_id == QA_STUDENT_ID and GameState.parent_id == QA_PARENT_ID, "Opening Load Game preserves the authenticated Student identity")
		var saves_container := load_scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer") as VBoxContainer
		_assert(saves_container != null and saves_container.get_child_count() == 1, "Canonical Load Game shows the authenticated Student's one manual save")
		if saves_container != null and saves_container.get_child_count() == 1:
			_assert(String(saves_container.get_child(0).get("save_path")).begins_with(_qa_directory + "/"), "Visible Load Game card resolves to the authenticated Student's manual save")
		_assert_delete_dialogs_themed_and_modal(load_scene)
	else:
		# The old behavior immediately entered gameplay. Do not execute that path
		# in this test because the canonical project has production QA enabled.
		settings.queue_free()
		await get_tree().process_frame

	_cleanup_qa_fixture()
	GameState.set("_save_directory", _previous_save_directory)
	await _finish()


func _assert_action_hitboxes_do_not_overlap(settings: Control) -> void:
	var paths := [
		"SettingsPopup/TextureRect/ResumeBtn",
		"SettingsPopup/TextureRect/SaveBtn",
		"SettingsPopup/TextureRect/LoadGameBtn",
		"SettingsPopup/TextureRect/ExitBtn",
		"SettingsPopup/TextureRect/MusicVolume",
		"SettingsPopup/TextureRect/SfxVolume",
	]
	var controls: Array[Control] = []
	for path in paths:
		var control := settings.get_node_or_null(path) as Control
		_assert(control != null, "Settings action/volume control exists: %s" % path)
		if control != null:
			controls.append(control)
	for index in range(controls.size()):
		for other_index in range(index + 1, controls.size()):
			var first := controls[index]
			var second := controls[other_index]
			_assert(not first.get_global_rect().intersects(second.get_global_rect()), "%s and %s clickable rectangles do not overlap" % [first.name, second.name])
	for path in paths.slice(0, 4):
		var button := settings.get_node(path) as Button
		_assert(is_equal_approx(button.size.y, button.custom_minimum_size.y), "%s hitbox height matches its visible button height" % button.name)


func _assert_child_labels_do_not_intercept(settings: Control) -> void:
	for button_name in ["ResumeBtn", "SaveBtn", "LoadGameBtn", "ExitBtn"]:
		var label := settings.get_node("SettingsPopup/TextureRect/%s/Label" % button_name) as Label
		_assert(label != null and label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s label lets clicks reach its visible button" % button_name)


func _assert_confirmation_theme_and_modal_flags(settings: Control) -> void:
	for property_name in ["_save_dialog", "_exit_dialog"]:
		var dialog := settings.get(property_name) as ConfirmationDialog
		_assert(dialog != null, "%s exists" % property_name)
		if dialog == null:
			continue
		_assert(dialog.exclusive, "%s is modal and blocks controls behind it" % property_name)
		var panel := dialog.get_theme_stylebox("panel")
		_assert(panel is StyleBoxFlat and (panel as StyleBoxFlat).bg_color.is_equal_approx(Color(0.025, 0.055, 0.16, 1.0)), "%s uses the pixel-fantasy navy panel" % property_name)
		_assert(dialog.get_theme_font("font") == load("res://Font/PressStart2P.ttf"), "%s uses the game's pixel font" % property_name)


func _assert_modal_blocks_background(settings: Control) -> void:
	var popup := settings.get_node("SettingsPopup") as Control
	var resume_button := settings.get_node("SettingsPopup/TextureRect/ResumeBtn") as Button
	var save_dialog := settings.get("_save_dialog") as ConfirmationDialog
	var background_clicks := [0]
	resume_button.pressed.connect(func() -> void: background_clicks[0] += 1)
	popup.visible = true
	await _dispatch_click(resume_button)
	_assert(background_clicks[0] == 1 and not popup.visible, "Settings Resume receives an ordinary click before modal blocking is tested")
	popup.visible = true
	settings.call("_on_save_pressed")
	await get_tree().process_frame
	_assert(save_dialog.visible and save_dialog.exclusive, "Save confirmation opens as a blocking modal")
	await _dispatch_click(resume_button)
	_assert(background_clicks[0] == 1 and popup.visible, "Clicking a Resume control behind the Save modal does not activate it")
	save_dialog.hide()


func _dispatch_click(control: Control) -> void:
	var click_position := control.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = click_position
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = click_position
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame


func _assert_delete_dialogs_themed_and_modal(load_scene: Node) -> void:
	for path in ["DeleteSaveConfirmation", "DeleteAllSaveConfirmation"]:
		var dialog := load_scene.get_node_or_null(path) as ConfirmationDialog
		_assert(dialog != null, "%s exists" % path)
		if dialog == null:
			continue
		_assert(dialog.exclusive, "%s is modal and blocks controls behind it" % path)
		var panel := dialog.get_theme_stylebox("panel")
		_assert(panel is StyleBoxFlat and (panel as StyleBoxFlat).bg_color.is_equal_approx(Color(0.025, 0.055, 0.16, 1.0)), "%s uses the pixel-fantasy navy panel" % path)
		_assert(dialog.get_theme_font("font") == load("res://Font/PressStart2P.ttf"), "%s uses the game's pixel font" % path)


func _function_block(source: String, function_header: String) -> String:
	var start := source.find(function_header)
	if start < 0:
		return ""
	var next_function := source.find("\nfunc ", start + function_header.length())
	if next_function < 0:
		return source.substr(start)
	return source.substr(start, next_function - start)


func _cleanup_qa_fixture() -> void:
	if not _created_qa_directory:
		return
	var student_id := QA_STUDENT_ID
	var owned_files := [
		"%s/save_%s_manual_000001.json" % [_qa_directory, student_id],
		"%s/save_%s_current.json" % [_qa_directory, student_id],
		"%s/save_%s_recovery.json" % [_qa_directory, student_id],
	]
	var safe_prefix := _qa_directory.rstrip("/") + "/"
	for path in owned_files:
		if not path.begins_with(safe_prefix):
			push_error("Refusing Settings UI test cleanup outside its unique QA directory")
			continue
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_qa_directory))
	_created_qa_directory = false


func _assert(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SETTINGS_INGAME_REGRESSION_TEST PASSED checks=%d failures=0" % _checks)
	else:
		for failure in _failures:
			push_error(failure)
		print("SETTINGS_INGAME_REGRESSION_TEST FAILED checks=%d failures=%d" % [_checks, _failures.size()])
	# Keep the MCP debug stream available long enough to read the test report.
	await get_tree().create_timer(45.0).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
