extends Node

const GAME_HUD_SCENE := preload("res://ui/game_hud.tscn")
const MOBILE_CONTROLS_SCENE := preload("res://ui/mobile_controls.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_mode := GameState.get_mode()
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	InputManager.clear_mobile_state()

	await _assert_mobile_controls()
	await _assert_compact_settings_pause_and_audio()

	InputManager.clear_mobile_state()
	GameState.set_mode(original_mode)
	get_tree().paused = false

	if _failures.is_empty():
		print("controls_pause_regression_test: PASS")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _assert_mobile_controls() -> void:
	var controls := MOBILE_CONTROLS_SCENE.instantiate() as CanvasLayer
	get_tree().root.add_child(controls)
	await get_tree().process_frame
	controls.configure(true)
	await get_tree().process_frame

	var root := controls.get_node_or_null("Root") as Control
	var interact := controls.get_node_or_null("Root/ActionMargin/ActionPanel/ActionButton") as TouchHoldButton
	var right := controls.get_node_or_null("Root/MovementMargin/MovementPanel/MovementBox/MiddleRow/RightButton") as TouchHoldButton
	_expect(root != null and root.visible, "Forced test mode makes mobile controls visible during exploration.")
	_expect(interact != null and interact.visible and not interact.disabled, "Mobile exploration keeps the shared Interact control available.")
	_expect(right != null, "Mobile exploration exposes the Right D-pad button.")
	if right != null:
		var press := InputEventScreenTouch.new()
		press.index = 7
		press.pressed = true
		right._gui_input(press)
		await get_tree().process_frame
		_expect(InputManager.get_movement_vector() == Vector2.RIGHT, "Right D-pad input reaches the shared InputManager.")
		var release := InputEventScreenTouch.new()
		release.index = 7
		release.pressed = false
		right._gui_input(release)
		await get_tree().process_frame
		_expect(InputManager.get_movement_vector() == Vector2.ZERO, "Releasing the Right D-pad button clears movement.")
	controls.queue_free()
	await get_tree().process_frame


func _assert_compact_settings_pause_and_audio() -> void:
	var hud := GAME_HUD_SCENE.instantiate() as CanvasLayer
	get_tree().root.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var settings := hud.get_node_or_null("Settings-Ingame") as Control
	var gear := hud.get_node_or_null("Settings-Ingame/Settings-Logo-Button") as Button
	var popup := hud.get_node_or_null("Settings-Ingame/SettingsPopup") as Control
	var music := hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/MusicVolume") as HSlider
	var sfx := hud.get_node_or_null("Settings-Ingame/SettingsPopup/TextureRect/SfxVolume") as HSlider
	_expect(settings != null and popup != null, "Game HUD owns exactly one in-game settings overlay.")
	_expect(gear != null and gear.expand_icon and gear.size.x <= 64.0 and gear.size.y <= 64.0 and is_equal_approx(gear.size.x, gear.size.y), "Settings gear remains a compact square control.")
	_expect(music != null and music.size == Vector2(280.0, 38.0), "Music volume remains compact at 280x38.")
	_expect(sfx != null and sfx.size == Vector2(280.0, 38.0), "SFX volume remains compact at 280x38.")

	if gear != null:
		gear.emit_signal("pressed")
		await get_tree().process_frame
		_expect(get_tree().paused, "Opening Settings pauses gameplay.")
		_expect(InputManager.is_input_locked(), "Opening Settings locks gameplay input.")
		_expect(popup != null and popup.visible, "Opening Settings shows the existing popup.")
		_expect(not gear.visible, "Opening Settings hides the external gear.")
		_assert_volume_binding(music, true)
		_assert_volume_binding(sfx, false)
		settings.call("_resume_game")
		await get_tree().process_frame
		_expect(not get_tree().paused, "Resume unpauses gameplay.")
		_expect(not InputManager.is_input_locked(), "Resume unlocks gameplay input.")
		_expect(gear.visible, "Resume restores the compact gear.")

	hud.queue_free()
	await get_tree().process_frame


func _assert_volume_binding(slider: HSlider, is_music: bool) -> void:
	if slider == null:
		return
	var original := AudioSettingsManager.get_music_volume() if is_music else AudioSettingsManager.get_sfx_volume()
	var target := 0.37 if not is_equal_approx(original, 0.37) else 0.62
	slider.value = target
	var actual := AudioSettingsManager.get_music_volume() if is_music else AudioSettingsManager.get_sfx_volume()
	_expect(is_equal_approx(actual, target), "%s slider remains bound to its existing audio setting." % ("Music" if is_music else "SFX"))
	slider.set_value_no_signal(original)
	if is_music:
		AudioSettingsManager.set_music_volume(original, false)
	else:
		AudioSettingsManager.set_sfx_volume(original, false)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
