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
var _settings_screenshot_path := ""
var _action_click_counts: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not HttpApi.is_local_qa_profile_active():
		push_error("Settings QA refused to run without local-only startup selected before autoload initialization.")
		get_tree().quit(1)
		return
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
	_assert(_qa_directory.begins_with(GameState.LOCAL_QA_SAVE_DIRECTORY + "/"), "Settings fixtures stay under the dedicated local-QA save namespace")
	_assert(not _qa_directory.begins_with(GameState.SAVE_DIRECTORY + "/"), "Settings fixtures never target the normal player save namespace")
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
	_assert(not GameState.save_checkpoint().is_empty(), "Hidden checkpoint fixture is created in the isolated Settings UI QA directory")
	_assert(GameState.list_saves().is_empty(), "Hidden checkpoints are not visible as manual Load Game slots")

	var settings := SETTINGS_SCENE.instantiate() as Control
	get_tree().root.add_child(settings)
	get_tree().current_scene = settings
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_authored_geometry_preserved(settings)
	await _capture_settings_runtime_frame(settings)
	_assert_action_hitboxes_do_not_overlap(settings)
	_assert_action_button_artwork_fills_hitboxes(settings)
	_assert_volume_track_art_fills_hitboxes(settings)
	await _assert_responsive_settings_layout(settings)
	_assert_child_labels_do_not_intercept(settings)
	_assert_confirmation_theme_and_modal_flags(settings)
	await _assert_button_and_slider_input_isolation(settings)
	await _assert_modal_blocks_background(settings)
	var load_button := settings.get_node("SettingsPopup/TextureRect/LoadGameBtn") as Button
	_assert(load_button.disabled, "Load Game is disabled when only a hidden checkpoint exists")
	await _dispatch_click(load_button)
	_assert(get_tree().current_scene == settings, "Disabled Load Game cannot leave gameplay for the Load Game scene")
	_assert(_action_click_counts["LoadGameBtn"] == 0, "Disabled Load Game does not dispatch its load action")

	var settings_source := FileAccess.get_file_as_string("res://scenes/Settings-Ingame/settings_ingame_controller.gd")
	var load_handler := _function_block(settings_source, "func _on_load_pressed()")
	var routes_to_load_list := load_handler.contains("change_scene_to_file(LOAD_GAME_SCENE)")
	_assert(routes_to_load_list, "Settings Load routes to the canonical Load Game scene instead of auto-loading the latest save")
	if routes_to_load_list:
		var manual_save_path := String(GameState.save_manual_game())
		_assert(manual_save_path.begins_with(_qa_directory + "/"), "Manual save fixture is created only after Settings is open")
		_assert(not load_button.disabled, "Creating a visible manual save enables Settings Load Game")
		await _dispatch_click(settings.get_node("SettingsPopup/TextureRect/LoadGameBtn") as Control)
		for _frame in range(12):
			await get_tree().process_frame
		_assert(_action_click_counts["LoadGameBtn"] == 1 and _action_click_counts["ResumeBtn"] == 2 and _action_click_counts["SaveBtn"] == 1 and _action_click_counts["ExitBtn"] == 1, "Load click triggers Load only after isolated Resume, Save, Exit, and slider input")
		var load_scene := get_tree().current_scene
		_assert(load_scene != null and load_scene.scene_file_path == LOAD_SCENE_PATH, "Settings Load opens the canonical Load Game scene")
		_assert(GameState.student_id == QA_STUDENT_ID and GameState.parent_id == QA_PARENT_ID, "Opening Load Game preserves the authenticated Student identity")
		var saves_container := load_scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer") as VBoxContainer
		_assert(saves_container != null and saves_container.get_child_count() == 1, "Canonical Load Game shows the authenticated Student's one manual save")
		if saves_container != null and saves_container.get_child_count() == 1:
			_assert(String(saves_container.get_child(0).get("save_path")).begins_with(_qa_directory + "/"), "Visible Load Game card resolves to the authenticated Student's manual save")
		_assert_delete_dialogs_themed_and_modal(load_scene)
		var back_button := load_scene.get_node_or_null("Button") as Button
		_assert(back_button != null, "Canonical Load Game exposes its Back/X button")
		if back_button != null:
			back_button.call("_fade_and_change_scene")
			for _frame in range(45):
				await get_tree().process_frame
				if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://interiors/player_house.tscn":
					break
			_assert(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://interiors/player_house.tscn", "In-game Load Game Back returns to the gameplay scene that opened it")
		var menu_load_scene := load("res://load_game_scene.tscn").instantiate() as Node
		_assert(String(menu_load_scene.call("resolve_back_navigation")) == "res://scenes/main_menu.tscn", "Main Menu Load Game Back/X falls back to Main Menu without a gameplay browse context")
		menu_load_scene.free()
	else:
		# The old behavior immediately entered gameplay. Do not execute that path
		# in this test because the canonical project has production QA enabled.
		settings.queue_free()
		await get_tree().process_frame

	_cleanup_qa_fixture()
	GameState.set("_save_directory", _previous_save_directory)
	await _finish()


func _assert_authored_geometry_preserved(settings: Control) -> void:
	# The scene owns every child rectangle. Runtime fitting is allowed to transform
	# the parent composition only; it must not reflow/resize controls or artwork.
	var expected_geometry := {
		"SettingsPopup": {"size": Vector2(1008, 680)},
		"SettingsPopup/TextureRect": {"position": Vector2(0, 46), "size": Vector2(1008, 680)},
		"SettingsPopup/TextureRect/X": {"position": Vector2(791, 181), "size": Vector2(38, 38)},
		"SettingsPopup/TextureRect/MusicLabel": {"position": Vector2(239, 450), "size": Vector2(220, 13)},
		"SettingsPopup/TextureRect/SfxLabel": {"position": Vector2(549, 450), "size": Vector2(220, 13)},
		"SettingsPopup/TextureRect/MusicVolume": {"position": Vector2(239, 468), "size": Vector2(220, 30)},
		"SettingsPopup/TextureRect/SfxVolume": {"position": Vector2(549, 468), "size": Vector2(220, 30)},
		"SettingsPopup/TextureRect/ResumeBtn": {"position": Vector2(390, 175), "size": Vector2(220, 52)},
		"SettingsPopup/TextureRect/SaveBtn": {"position": Vector2(390, 240), "size": Vector2(220, 52)},
		"SettingsPopup/TextureRect/LoadGameBtn": {"position": Vector2(390, 305), "size": Vector2(220, 52)},
		"SettingsPopup/TextureRect/ExitBtn": {"position": Vector2(390, 370), "size": Vector2(220, 52)},
	}
	for path: Variant in expected_geometry.keys():
		var expected: Dictionary = expected_geometry[path]
		var control := settings.get_node_or_null(String(path)) as Control
		_assert(control != null, "Authored Settings control exists: %s" % String(path))
		if control == null:
			continue
		_assert(control.position.is_equal_approx(expected.get("position", control.position)), "%s keeps its authored local position" % String(path))
		if expected.has("size"):
			_assert(control.size.is_equal_approx(expected.get("size")), "%s keeps its approved authored size" % String(path))
	for path in ["SettingsPopup/TextureRect/ResumeBtn", "SettingsPopup/TextureRect/SaveBtn", "SettingsPopup/TextureRect/LoadGameBtn", "SettingsPopup/TextureRect/ExitBtn"]:
		var button := settings.get_node(path) as Button
		_assert(button.custom_minimum_size == Vector2(220, 52), "%s retains its authored 220×52 minimum size" % button.name)
	for path in ["SettingsPopup/TextureRect/MusicVolume", "SettingsPopup/TextureRect/SfxVolume"]:
		var slider := settings.get_node(path) as HSlider
		_assert(slider.custom_minimum_size == Vector2(220, 30), "%s hitbox matches the compact visible 220×30 slider" % slider.name)
	_assert_authored_button_stack_spacing(settings)
	_assert_volume_labels_clear_of_controls(settings)


func _assert_authored_button_stack_spacing(settings: Control) -> void:
	var button_paths := [
		"SettingsPopup/TextureRect/ResumeBtn",
		"SettingsPopup/TextureRect/SaveBtn",
		"SettingsPopup/TextureRect/LoadGameBtn",
		"SettingsPopup/TextureRect/ExitBtn",
	]
	var buttons: Array[Control] = []
	for path in button_paths:
		buttons.append(settings.get_node(path) as Control)
	for index in range(buttons.size()):
		_assert(buttons[index].size.is_equal_approx(Vector2(220, 52)), "%s actual authored rectangle is 220×52" % buttons[index].name)
		if index > 0:
			var gap := buttons[index].position.y - buttons[index - 1].position.y - buttons[index - 1].size.y
			_assert(is_equal_approx(gap, 13.0), "%s follows the consistent 13px button gap" % buttons[index].name)


func _assert_volume_labels_clear_of_controls(settings: Control) -> void:
	var panel := settings.get_node("SettingsPopup/TextureRect") as Control
	var exit_button := panel.get_node("ExitBtn") as Control
	for control_pair in [["MusicLabel", "MusicVolume"], ["SfxLabel", "SfxVolume"]]:
		var label := panel.get_node(control_pair[0]) as Control
		var slider := panel.get_node(control_pair[1]) as Control
		_assert(label.position.y >= exit_button.position.y + exit_button.size.y, "%s remains below the action-button stack" % label.name)
		_assert(label.position.y + label.size.y <= slider.position.y, "%s remains above its decorative volume control" % label.name)
		_assert(not Rect2(label.position, label.size).intersects(Rect2(slider.position, slider.size)), "%s text does not overlap its knob/track hitbox" % label.name)
		_assert(_rect_inside(Rect2(label.position, label.size), Rect2(Vector2.ZERO, panel.size)), "%s remains inside the authored popup panel" % label.name)


func _capture_settings_runtime_frame(settings: Control) -> void:
	var popup := settings.get_node_or_null("SettingsPopup") as Control
	if popup == null:
		return
	popup.visible = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var action_rects: Array[String] = []
	for button_name in ["ResumeBtn", "SaveBtn", "LoadGameBtn", "ExitBtn"]:
		var button := settings.get_node("SettingsPopup/TextureRect/%s" % button_name) as Control
		var frame := button.get_node_or_null("ButtonFrame") as Control
		action_rects.append("%s button=%s frame=%s" % [button_name, str(button.get_global_rect()), str(frame.get_global_rect() if frame != null else Rect2())])
	var music_slider := settings.get_node("SettingsPopup/TextureRect/MusicVolume") as Control
	var sfx_slider := settings.get_node("SettingsPopup/TextureRect/SfxVolume") as Control
	print("SETTINGS_QA_GEOMETRY viewport=%s popup_rect=%s popup_scale=%s buttons=[%s] music=%s sfx=%s" % [
		str(get_viewport().get_visible_rect().size),
		str(popup.get_global_transform() * Rect2(Vector2.ZERO, popup.size)),
		str(popup.scale),
		", ".join(action_rects),
		str(music_slider.get_global_rect()),
		str(sfx_slider.get_global_rect()),
	])
	var screenshot := get_viewport().get_texture().get_image()
	_settings_screenshot_path = "user://qa_test_artifacts/settings_runtime_%d_%d.png" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_output_path := ProjectSettings.globalize_path(_settings_screenshot_path)
	if FileAccess.file_exists(_settings_screenshot_path):
		_assert(false, "Settings screenshot path is unique and will not overwrite an earlier QA artifact")
		popup.visible = false
		return
	_assert(true, "Settings screenshot path is unique and will not overwrite an earlier QA artifact")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa_test_artifacts"))
	var save_error := screenshot.save_png(absolute_output_path)
	_assert(save_error == OK, "Captures the actual 1215×545 Settings runtime layout for visual inspection")
	if save_error == OK:
		print("SETTINGS_QA_SCREENSHOT " + absolute_output_path)
	popup.visible = false


func _assert_action_button_artwork_fills_hitboxes(settings: Control) -> void:
	for button_name in ["ResumeBtn", "SaveBtn", "LoadGameBtn", "ExitBtn"]:
		var button := settings.get_node("SettingsPopup/TextureRect/%s" % button_name) as Button
		var frame := button.get_node_or_null("ButtonFrame") as TextureRect
		_assert(button.icon == null, "%s does not render the frame as a tiny Button icon" % button_name)
		_assert(frame != null and frame.texture != null, "%s uses the existing fantasy frame as a background texture" % button_name)
		_assert(frame != null and frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s background art does not intercept pointer input" % button_name)
		if frame != null:
			_assert(frame.owner == settings, "%s frame is authored in the scene instead of created at runtime" % button_name)
			_assert(frame.get_parent() == button, "%s frame is clipped by its owning button" % button_name)
			_assert(button.clip_contents, "%s clips artwork to its own clickable rectangle" % button_name)
			_assert(frame.anchor_left == 0.0 and frame.anchor_top == 0.0 and frame.anchor_right == 1.0 and frame.anchor_bottom == 1.0, "%s frame is authored to full-rect anchors" % button_name)
			_assert(frame.offset_left == 0.0 and frame.offset_top == 0.0 and frame.offset_right == 0.0 and frame.offset_bottom == 0.0, "%s frame has zero full-rect offsets" % button_name)
			_assert(frame.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and frame.stretch_mode == TextureRect.STRETCH_SCALE, "%s frame texture is stretched only into its exact button bounds" % button_name)
			_assert(frame.get_global_rect().is_equal_approx(button.get_global_rect()), "%s background art fills exactly its clickable rectangle" % button_name)
			var label := button.get_node_or_null("Label") as Label
			_assert(label != null and Rect2(Vector2.ZERO, button.size).encloses(label.get_rect()), "%s label remains inside the visible button frame" % button_name)
		if button_name == "LoadGameBtn":
			var was_disabled := button.disabled
			button.disabled = true
			_assert(button.size == Vector2(220.0, 52.0) and frame != null and frame.get_global_rect().is_equal_approx(button.get_global_rect()), "Disabled Load Game keeps the full-size themed frame and click bounds")
			button.disabled = was_disabled


func _assert_volume_track_art_fills_hitboxes(settings: Control) -> void:
	var panel := settings.get_node("SettingsPopup/TextureRect") as Control
	for slider_name in ["MusicVolume", "SfxVolume"]:
		var slider := panel.get_node(slider_name) as HSlider
		var track := panel.get_node("%sTrack" % slider_name) as TextureRect
		_assert(track != null and track.texture == load("res://Images/slide bar.png"), "%s uses the existing fantasy slider-rail texture" % slider_name)
		if track == null:
			continue
		_assert(track.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s rail artwork never intercepts slider/action input" % slider_name)
		_assert(track.get_global_rect().is_equal_approx(slider.get_global_rect()), "%s artwork fills exactly its 220×30 slider hitbox" % slider_name)
		_assert(track.get_index() < slider.get_index(), "%s rail is drawn behind its interactive slider" % slider_name)


func _assert_responsive_settings_layout(settings: Control) -> void:
	var viewport_sizes := [Vector2i(1215, 545), Vector2i(640, 360), Vector2i(844, 390), Vector2i(915, 412), Vector2i(360, 640)]
	var texture_rect := settings.get_node("SettingsPopup/TextureRect") as Control
	var popup := settings.get_node("SettingsPopup") as Control
	var action_names := ["ResumeBtn", "SaveBtn", "LoadGameBtn", "ExitBtn"]
	for viewport_size: Vector2i in viewport_sizes:
		settings.call("_fit_popup_to_viewport", Vector2(viewport_size))
		await get_tree().process_frame
		_assert_authored_geometry_preserved(settings)
		var scale_factor := popup.scale.x
		_assert(is_equal_approx(popup.scale.x, popup.scale.y), "Settings composition scales uniformly at viewport %s" % str(viewport_size))
		_assert(scale_factor > 0.0 and scale_factor <= 1.0, "Settings composition remains in a safe scale range at viewport %s" % str(viewport_size))
		var popup_rect := popup.get_global_transform() * Rect2(Vector2.ZERO, popup.size)
		_assert(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(popup_rect), "Settings composition rect %s remains inside viewport %s" % [str(popup_rect), str(viewport_size)])
		for button_name in action_names:
			var button := settings.get_node("SettingsPopup/TextureRect/%s" % button_name) as Button
			_assert(button.size == Vector2(220.0, 52.0), "%s authored size remains 220×52 at viewport %s" % [button_name, str(viewport_size)])
			_assert(_rect_inside(Rect2(button.position, button.size), Rect2(Vector2.ZERO, texture_rect.size)), "%s remains within the Settings panel at viewport %s" % [button_name, str(viewport_size)])
			var transformed_button := button.get_global_transform() * Rect2(Vector2.ZERO, button.size)
			var expected_global_size := Vector2(220.0, 52.0) * scale_factor
			_assert(transformed_button.size.is_equal_approx(expected_global_size), "%s hitbox follows the uniform composition scale at viewport %s" % [button_name, str(viewport_size)])
		var music_label := settings.get_node("SettingsPopup/TextureRect/MusicLabel") as Control
		var sfx_label := settings.get_node("SettingsPopup/TextureRect/SfxLabel") as Control
		var music_slider := settings.get_node("SettingsPopup/TextureRect/MusicVolume") as Control
		var sfx_slider := settings.get_node("SettingsPopup/TextureRect/SfxVolume") as Control
		for button_name in action_names:
			var button := settings.get_node("SettingsPopup/TextureRect/%s" % button_name) as Control
			_assert(not button.get_global_rect().intersects(music_label.get_global_rect()) and not button.get_global_rect().intersects(sfx_label.get_global_rect()), "%s does not overlap volume labels at viewport %s" % [button_name, str(viewport_size)])
			_assert(not button.get_global_rect().intersects(music_slider.get_global_rect()) and not button.get_global_rect().intersects(sfx_slider.get_global_rect()), "%s does not overlap volume controls at viewport %s" % [button_name, str(viewport_size)])
	settings.call("_center_popup")
	await get_tree().process_frame


func _assert_action_hitboxes_do_not_overlap(settings: Control) -> void:
	var panel := settings.get_node("SettingsPopup/TextureRect") as Control
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
		_assert(_rect_inside(Rect2(button.position, button.size), Rect2(Vector2.ZERO, panel.size)), "%s hitbox stays within the visible settings panel" % button.name)
		_assert(button.size == Vector2(220, 52), "%s clickable rectangle remains exactly 220×52" % button.name)
		_assert(is_equal_approx(button.size.y, button.custom_minimum_size.y), "%s hitbox height matches its visible button height" % button.name)
		_assert(button.mouse_filter == Control.MOUSE_FILTER_STOP, "%s receives clicks inside its own visible hitbox" % button.name)
	for path in paths.slice(4, 6):
		var slider := settings.get_node(path) as HSlider
		_assert(_rect_inside(Rect2(slider.position, slider.size), Rect2(Vector2.ZERO, panel.size)), "%s hitbox %s stays within visible settings panel %s" % [slider.name, str(Rect2(slider.position, slider.size)), str(Rect2(Vector2.ZERO, panel.size))])
		_assert(slider.size == Vector2(220, 30), "%s hitbox matches its visible 220×30 slider, got %s" % [slider.name, str(slider.size)])


func _rect_inside(rect: Rect2, bounds: Rect2) -> bool:
	return bounds.encloses(rect)


func _assert_button_and_slider_input_isolation(settings: Control) -> void:
	var popup := settings.get_node("SettingsPopup") as Control
	var texture_rect := settings.get_node("SettingsPopup/TextureRect") as Control
	_action_click_counts = {"ResumeBtn": 0, "SaveBtn": 0, "LoadGameBtn": 0, "ExitBtn": 0}
	for button_name in _action_click_counts.keys():
		var captured_name := String(button_name)
		var button := texture_rect.get_node(captured_name) as Button
		button.pressed.connect(func() -> void: _action_click_counts[captured_name] += 1)

	popup.visible = true
	await _dispatch_click(texture_rect.get_node("ResumeBtn") as Control)
	_assert(_action_click_counts["ResumeBtn"] == 1 and _action_click_counts["SaveBtn"] == 0 and _action_click_counts["LoadGameBtn"] == 0 and _action_click_counts["ExitBtn"] == 0, "Resume click triggers Resume only")
	_assert(not popup.visible, "Resume click closes Settings without activating a neighboring action")
	popup.visible = true

	await _dispatch_click(texture_rect.get_node("SaveBtn") as Control)
	_assert(_action_click_counts["SaveBtn"] == 1 and _action_click_counts["ResumeBtn"] == 1 and _action_click_counts["LoadGameBtn"] == 0 and _action_click_counts["ExitBtn"] == 0, "Save click triggers Save only")
	var save_dialog := settings.get("_save_dialog") as ConfirmationDialog
	_assert(save_dialog.visible, "Save click opens only the Save confirmation")
	save_dialog.hide()

	await _dispatch_click(texture_rect.get_node("ExitBtn") as Control)
	_assert(_action_click_counts["ExitBtn"] == 1 and _action_click_counts["ResumeBtn"] == 1 and _action_click_counts["SaveBtn"] == 1 and _action_click_counts["LoadGameBtn"] == 0, "Exit click triggers Exit only")
	var exit_dialog := settings.get("_exit_dialog") as ConfirmationDialog
	_assert(exit_dialog.visible, "Exit click opens only the Exit confirmation")
	exit_dialog.hide()

	var music := texture_rect.get_node("MusicVolume") as HSlider
	var sfx := texture_rect.get_node("SfxVolume") as HSlider
	var before := _action_click_counts.duplicate()
	var prior_music := music.value
	var prior_sfx := sfx.value
	await _dispatch_click(music)
	await _dispatch_slider_drag(sfx)
	_assert(_action_click_counts == before, "Music and SFX slider pointer input triggers no action button")
	music.value = prior_music
	sfx.value = prior_sfx
	popup.visible = true


func _dispatch_slider_drag(slider: HSlider) -> void:
	var rect := slider.get_global_rect()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = Vector2(rect.position.x + 20.0, rect.get_center().y)
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(rect.end.x - 20.0, rect.get_center().y)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame


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
