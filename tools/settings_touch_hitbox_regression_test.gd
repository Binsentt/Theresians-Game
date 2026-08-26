extends Node

const GAME_HUD_SCENE := preload("res://ui/game_hud.tscn")
const ACTION_BUTTON_SIZE := Vector2(220.0, 52.0)
const HOVER_MODULATE := Color(1.0, 0.95, 0.78, 1.0)
const PRESSED_MODULATE := Color(0.82, 0.82, 0.82, 1.0)

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var hud := GAME_HUD_SCENE.instantiate() as CanvasLayer
	get_tree().root.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var settings := hud.get_node_or_null("Settings-Ingame") as Control
	var gear := hud.get_node_or_null("Settings-Ingame/Settings-Logo-Button") as Button
	var popup := hud.get_node_or_null("Settings-Ingame/SettingsPopup") as Control
	var texture_rect := hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect") as TextureRect
	var close_button := hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/X") as Button
	var music := hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/MusicVolume") as HSlider
	var sfx := hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/SfxVolume") as HSlider
	var actions: Array[Button] = [
		hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/ResumeBtn") as Button,
		hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/SaveBtn") as Button,
		hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/LoadGameBtn") as Button,
		hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/ExitBtn") as Button,
	]

	_expect(settings != null and popup != null and texture_rect != null, "Settings HUD exposes the canonical popup path.")
	_expect(settings != null and settings.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Settings root does not intercept gameplay until its popup is opened.")
	_expect(popup != null and popup.mouse_filter == Control.MOUSE_FILTER_STOP, "Settings popup blocks input from reaching gameplay behind it.")
	_expect(music != null and music.size == Vector2(220.0, 30.0), "Music slider remains compact at 220x30.")
	_expect(sfx != null and sfx.size == Vector2(220.0, 30.0), "SFX slider remains compact at 220x30.")
	for action: Button in actions:
		_expect(action != null, "Each Settings action button exists.")
		if action != null:
			_expect(action.size == ACTION_BUTTON_SIZE, "%s uses the compact 220x52 interactive rectangle." % action.name)
			_expect(action.mouse_filter == Control.MOUSE_FILTER_STOP, "%s stops touch/click input at its own rectangle." % action.name)

	if actions.all(func(action: Button) -> bool: return action != null) and music != null and sfx != null:
		_assert_action_rects_are_isolated(actions, music, sfx)
		await _assert_hover_and_pressed_feedback(settings, actions[0])
		await _assert_settings_actions_preserve_pause_behavior(settings, gear, close_button, popup, actions)

	hud.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("settings_touch_hitbox_regression_test: PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)


func _assert_action_rects_are_isolated(actions: Array[Button], music: HSlider, sfx: HSlider) -> void:
	for first_index in range(actions.size()):
		var first := actions[first_index]
		var first_rect := first.get_global_rect()
		_expect(_buttons_at_point(actions, first_rect.get_center()) == [first], "%s center targets only %s." % [first.name, first.name])
		_expect(not first_rect.intersects(music.get_global_rect()), "%s does not cover MusicVolume." % first.name)
		_expect(not first_rect.intersects(sfx.get_global_rect()), "%s does not cover SfxVolume." % first.name)
		for second_index in range(first_index + 1, actions.size()):
			var second := actions[second_index]
			_expect(not first_rect.intersects(second.get_global_rect()), "%s and %s have no overlapping hitbox." % [first.name, second.name])

	var resume_rect := actions[0].get_global_rect()
	var save_rect := actions[1].get_global_rect()
	var load_rect := actions[2].get_global_rect()
	_expect(_buttons_at_point(actions, resume_rect.position + Vector2(resume_rect.size.x * 0.5, resume_rect.size.y - 1.0)) == [actions[0]], "Resume lower edge targets Resume only.")
	_expect(_buttons_at_point(actions, save_rect.position + Vector2(save_rect.size.x * 0.5, 1.0)) == [actions[1]], "Save upper edge targets Save only.")
	_expect(_buttons_at_point(actions, load_rect.get_center()) == [actions[2]], "Load Game center targets Load Game only.")


func _assert_hover_and_pressed_feedback(settings: Control, action: Button) -> void:
	_expect(action.self_modulate.is_equal_approx(Color.WHITE), "Normal state preserves the original button appearance.")
	settings.call("_on_button_hover_entered", action)
	await get_tree().create_timer(0.16).timeout
	_expect(action.scale == Vector2.ONE, "Hover feedback does not resize the interactive rectangle with Transform Scale.")
	_expect(action.self_modulate.is_equal_approx(HOVER_MODULATE), "Hover feedback uses the visible hover color.")
	settings.call("_on_button_down", action)
	await get_tree().create_timer(0.10).timeout
	_expect(action.scale == Vector2.ONE, "Pressed feedback does not resize the interactive rectangle with Transform Scale.")
	_expect(action.self_modulate.is_equal_approx(PRESSED_MODULATE), "Pressed feedback uses the visible pressed color.")
	settings.call("_on_button_up", action)
	await get_tree().create_timer(0.14).timeout
	_expect(action.self_modulate.is_equal_approx(HOVER_MODULATE), "Releasing a hovered button restores the hover color.")
	settings.call("_on_button_hover_exited", action)
	await get_tree().create_timer(0.14).timeout
	_expect(action.self_modulate.is_equal_approx(Color.WHITE), "Leaving the button restores the normal appearance.")


func _assert_settings_actions_preserve_pause_behavior(settings: Control, gear: Button, close_button: Button, popup: Control, actions: Array[Button]) -> void:
	if gear == null or close_button == null or popup == null:
		return
	gear.emit_signal("pressed")
	await get_tree().process_frame
	_expect(get_tree().paused, "Opening Settings pauses gameplay.")
	_expect(InputManager.is_input_locked(), "Opening Settings locks gameplay input.")
	_expect(popup.visible, "Opening Settings reveals the popup.")

	actions[1].emit_signal("pressed")
	await get_tree().process_frame
	var save_dialog := settings.get_node_or_null("SaveConfirmationDialog") as ConfirmationDialog
	_expect(save_dialog != null and save_dialog.visible, "Save triggers only the existing save confirmation.")
	if save_dialog != null:
		save_dialog.hide()

	actions[3].emit_signal("pressed")
	await get_tree().process_frame
	var exit_dialog := settings.get_node_or_null("ExitConfirmationDialog") as ConfirmationDialog
	_expect(exit_dialog != null and exit_dialog.visible, "Exit triggers only the existing exit confirmation.")
	if exit_dialog != null:
		exit_dialog.hide()

	close_button.emit_signal("pressed")
	await get_tree().process_frame
	_expect(not get_tree().paused and not InputManager.is_input_locked(), "Close resumes only the paused gameplay state.")
	_expect(not popup.visible and gear.visible, "Close restores the compact gear without changing other Settings actions.")


func _buttons_at_point(actions: Array[Button], point: Vector2) -> Array[Button]:
	var matches: Array[Button] = []
	for action: Button in actions:
		if action.get_global_rect().has_point(point):
			matches.append(action)
	return matches


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
