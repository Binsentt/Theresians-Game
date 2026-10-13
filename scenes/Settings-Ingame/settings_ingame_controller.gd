extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const LOAD_GAME_SCENE := "res://load_game_scene.tscn"
const CONFIRMATION_FONT: Font = preload("res://Font/PressStart2P.ttf")

const EXIT_PROMPT_TEXT := "Your current progress will be saved before leaving."
const SAVE_PROMPT_TEXT := "Do you want to save this game?"
const EXIT_DIALOG_SIZE := Vector2i(460, 170)
const SAVE_DIALOG_SIZE := Vector2i(460, 170)
const BUTTON_HOVER_MODULATE := Color(1.0, 0.95, 0.78, 1.0)
const BUTTON_PRESSED_MODULATE := Color(0.82, 0.82, 0.82, 1.0)
const BUTTON_NORMAL_MODULATE := Color.WHITE
const BUTTON_HOVER_DURATION := 0.12
const BUTTON_PRESS_DURATION := 0.06
const BUTTON_RELEASE_DURATION := 0.10
const SAVE_TOAST_FADE_IN_DURATION := 0.18
const SAVE_TOAST_VISIBLE_DURATION := 2.2
const SAVE_TOAST_FADE_OUT_DURATION := 0.32
const ENABLED_BUTTON_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const DISABLED_BUTTON_MODULATE := Color(1.0, 1.0, 1.0, 0.45)
const POPUP_SAFE_MARGIN := Vector2(24.0, 24.0)
const SETTINGS_COMPOSITION_SIZE := Vector2(1008.0, 680.0)
const SETTINGS_BUTTON_SIZE := Vector2(52.0, 52.0)
const SETTINGS_BUTTON_TOP_RIGHT_MARGIN := Vector2(16.0, 12.0)
const COMPACT_GRABBER_SIZE := Vector2i(30, 29)
const GRABBER_TEXTURE: Texture2D = preload("res://Images/grabber.png")

@onready var settings_button: Button = $"Settings-Logo-Button"
@onready var settings_popup: Control = $SettingsPopup
@onready var popup_texture: TextureRect = $SettingsPopup/TextureRect
@onready var close_button: Button = $SettingsPopup/TextureRect/X
@onready var music_slider: HSlider = $SettingsPopup/TextureRect/MusicVolume
@onready var sfx_slider: HSlider = $SettingsPopup/TextureRect/SfxVolume
@onready var load_button: Button = $SettingsPopup/TextureRect/LoadGameBtn
@onready var exit_button: Button = $SettingsPopup/TextureRect/ExitBtn
@onready var resume_button: Button = $SettingsPopup/TextureRect/ResumeBtn
@onready var save_button: Button = $SettingsPopup/TextureRect/SaveBtn
@onready var save_toast: Control = $SaveToast
@onready var save_toast_label: Label = $SaveToast/Label

var _exit_dialog: ConfirmationDialog
var _save_dialog: ConfirmationDialog
var _exit_in_progress := false
var _button_tweens: Dictionary = {}
var _button_hover_states: Dictionary = {}
var _save_toast_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	_configure_button_positions()
	_configure_action_buttons()
	_configure_compact_volume_sliders()
	_configure_popup()
	_configure_save_toast()
	_build_exit_dialog()
	_build_save_dialog()
	_connect_controls()
	_sync_volume_controls()
	_refresh_load_button_state()
	call_deferred("_center_popup")
	call_deferred("_configure_button_animations")


func _exit_tree() -> void:
	InputManager.unlock_input("settings_pause")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_center_popup()
		_position_save_toast()

func _configure_button_positions() -> void:
	settings_button.process_mode = Node.PROCESS_MODE_ALWAYS
	settings_button.focus_mode = Control.FOCUS_NONE
	settings_button.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_button.anchor_left = 1.0
	settings_button.anchor_top = 0.0
	settings_button.anchor_right = 1.0
	settings_button.anchor_bottom = 0.0
	settings_button.custom_minimum_size = SETTINGS_BUTTON_SIZE
	settings_button.expand_icon = true
	settings_button.offset_left = -SETTINGS_BUTTON_TOP_RIGHT_MARGIN.x - SETTINGS_BUTTON_SIZE.x
	settings_button.offset_top = SETTINGS_BUTTON_TOP_RIGHT_MARGIN.y
	settings_button.offset_right = -SETTINGS_BUTTON_TOP_RIGHT_MARGIN.x
	settings_button.offset_bottom = SETTINGS_BUTTON_TOP_RIGHT_MARGIN.y + SETTINGS_BUTTON_SIZE.y
	settings_button.visible = true


func _configure_action_buttons() -> void:
	for button: Button in [resume_button, save_button, load_button, exit_button]:
		button.icon = null
		button.expand_icon = false
		button.flat = true
		button.clip_contents = true
		var label := button.get_node_or_null("Label") as Label
		if label != null:
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label_path in ["SettingsPopup/TextureRect/MusicLabel", "SettingsPopup/TextureRect/SfxLabel"]:
		var label := get_node_or_null(label_path) as Label
		if label != null:
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _configure_compact_volume_sliders() -> void:
	# Keep the existing gold-and-blue orb art while matching the authored 220×30
	# slider control, so neither the visual knob nor its hitbox reaches adjacent UI.
	var compact_grabber := _create_compact_grabber()
	for slider: HSlider in [music_slider, sfx_slider]:
		slider.add_theme_icon_override(&"grabber", compact_grabber)
		slider.add_theme_icon_override(&"grabber_highlight", compact_grabber)
		slider.add_theme_icon_override(&"grabber_disabled", compact_grabber)


func _create_compact_grabber() -> ImageTexture:
	var image := GRABBER_TEXTURE.get_image()
	image.resize(COMPACT_GRABBER_SIZE.x, COMPACT_GRABBER_SIZE.y, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


func _configure_popup() -> void:
	settings_popup.process_mode = Node.PROCESS_MODE_ALWAYS
	settings_popup.visible = false
	settings_popup.modulate.a = 1.0
	settings_popup.scale = Vector2.ONE
	settings_popup.mouse_filter = Control.MOUSE_FILTER_STOP

	for button in [close_button, load_button, exit_button, resume_button, save_button]:
		button.process_mode = Node.PROCESS_MODE_ALWAYS
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP

	music_slider.process_mode = Node.PROCESS_MODE_ALWAYS
	sfx_slider.process_mode = Node.PROCESS_MODE_ALWAYS

func _configure_save_toast() -> void:
	save_toast.process_mode = Node.PROCESS_MODE_ALWAYS
	save_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_toast.visible = false
	save_toast.modulate.a = 0.0
	save_toast_label.text = "Successfully saved game"
	call_deferred("_position_save_toast")

func _build_exit_dialog() -> void:
	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.name = "ExitConfirmationDialog"
	_exit_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_exit_dialog.dialog_text = EXIT_PROMPT_TEXT
	_exit_dialog.title = "Return to Main Menu?"
	_exit_dialog.ok_button_text = "YES / RETURN"
	_exit_dialog.cancel_button_text = "NO / CANCEL"
	_exit_dialog.exclusive = true
	add_child(_exit_dialog)
	_apply_confirmation_theme(_exit_dialog)

func _build_save_dialog() -> void:
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.name = "SaveConfirmationDialog"
	_save_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_dialog.dialog_text = SAVE_PROMPT_TEXT
	_save_dialog.title = "Save Game"
	_save_dialog.ok_button_text = "YES"
	_save_dialog.cancel_button_text = "NO"
	_save_dialog.exclusive = true
	add_child(_save_dialog)
	_apply_confirmation_theme(_save_dialog)

func _connect_controls() -> void:
	if not settings_button.pressed.is_connected(_on_settings_button_pressed):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if not close_button.pressed.is_connected(_resume_game):
		close_button.pressed.connect(_resume_game)
	if not resume_button.pressed.is_connected(_resume_game):
		resume_button.pressed.connect(_resume_game)
	if not exit_button.pressed.is_connected(_on_exit_pressed):
		exit_button.pressed.connect(_on_exit_pressed)
	if not save_button.pressed.is_connected(_on_save_pressed):
		save_button.pressed.connect(_on_save_pressed)
	if not load_button.pressed.is_connected(_on_load_pressed):
		load_button.pressed.connect(_on_load_pressed)
	if not music_slider.value_changed.is_connected(_on_music_volume_changed):
		music_slider.value_changed.connect(_on_music_volume_changed)
	if not sfx_slider.value_changed.is_connected(_on_sfx_volume_changed):
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	if GameState.has_signal("save_created") and not GameState.save_created.is_connected(_on_save_created):
		GameState.save_created.connect(_on_save_created)
	if not _exit_dialog.confirmed.is_connected(_on_exit_confirmed):
		_exit_dialog.confirmed.connect(_on_exit_confirmed)
	if not _exit_dialog.canceled.is_connected(_on_exit_canceled):
		_exit_dialog.canceled.connect(_on_exit_canceled)
	if not _save_dialog.confirmed.is_connected(_on_save_confirmed):
		_save_dialog.confirmed.connect(_on_save_confirmed)
	if not _save_dialog.canceled.is_connected(_on_save_canceled):
		_save_dialog.canceled.connect(_on_save_canceled)

func _configure_button_animations() -> void:
	for button: Button in [settings_button, close_button, load_button, resume_button, save_button, exit_button]:
		_prepare_button_animation(button)

func _prepare_button_animation(button: Button) -> void:
	if button == null:
		return

	button.self_modulate = BUTTON_NORMAL_MODULATE
	_button_hover_states[button.get_instance_id()] = false
	var entered_callable := Callable(self, "_on_button_hover_entered").bind(button)
	var exited_callable := Callable(self, "_on_button_hover_exited").bind(button)
	var down_callable := Callable(self, "_on_button_down").bind(button)
	var up_callable := Callable(self, "_on_button_up").bind(button)
	if not button.mouse_entered.is_connected(entered_callable):
		button.mouse_entered.connect(entered_callable)
	if not button.mouse_exited.is_connected(exited_callable):
		button.mouse_exited.connect(exited_callable)
	if not button.button_down.is_connected(down_callable):
		button.button_down.connect(down_callable)
	if not button.button_up.is_connected(up_callable):
		button.button_up.connect(up_callable)

func _on_button_hover_entered(button: Button) -> void:
	_button_hover_states[button.get_instance_id()] = true
	if button.disabled:
		return
	_tween_button_feedback(button, BUTTON_HOVER_MODULATE, BUTTON_HOVER_DURATION)

func _on_button_hover_exited(button: Button) -> void:
	_button_hover_states[button.get_instance_id()] = false
	_tween_button_feedback(button, BUTTON_NORMAL_MODULATE, BUTTON_HOVER_DURATION)

func _on_button_down(button: Button) -> void:
	if button.disabled:
		return
	_tween_button_feedback(button, BUTTON_PRESSED_MODULATE, BUTTON_PRESS_DURATION)

func _on_button_up(button: Button) -> void:
	var is_hovered := bool(_button_hover_states.get(button.get_instance_id(), false))
	var target_modulate := BUTTON_HOVER_MODULATE if is_hovered and not button.disabled else BUTTON_NORMAL_MODULATE
	_tween_button_feedback(button, target_modulate, BUTTON_RELEASE_DURATION)

func _tween_button_feedback(button: Button, target_modulate: Color, duration: float) -> void:
	if button == null:
		return

	var key := button.get_instance_id()
	var existing_tween: Tween = _button_tweens.get(key)
	if existing_tween != null and existing_tween.is_valid():
		existing_tween.kill()

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "self_modulate", target_modulate, duration)
	_button_tweens[key] = tween

func _on_settings_button_pressed() -> void:
	_sync_volume_controls()
	_refresh_load_button_state()
	_center_popup()
	settings_popup.visible = true
	settings_button.visible = false
	InputManager.lock_input("settings_pause")
	get_tree().paused = true

func _resume_game() -> void:
	if _exit_dialog != null and _exit_dialog.visible:
		_exit_dialog.hide()
	if _save_dialog != null and _save_dialog.visible:
		_save_dialog.hide()
	settings_popup.visible = false
	settings_button.visible = true
	InputManager.unlock_input("settings_pause")
	get_tree().paused = false

func _on_save_pressed() -> void:
	if _save_dialog == null:
		return
	_save_dialog.popup_centered(SAVE_DIALOG_SIZE)

func _on_load_pressed() -> void:
	if load_button.disabled:
		return
	var origin_scene_path := String(GameState.current_scene_path)
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	var origin_position := GameState.player_position
	if player != null:
		origin_position = player.global_position
	if not GameState.begin_load_game_browse(origin_scene_path, origin_position):
		return

	settings_popup.visible = false
	InputManager.unlock_input("settings_pause")
	get_tree().paused = false
	if _save_dialog != null:
		_save_dialog.hide()
	if _exit_dialog != null:
		_exit_dialog.hide()
	var transition_error := get_tree().change_scene_to_file(LOAD_GAME_SCENE)
	if transition_error != OK:
		GameState.clear_load_game_browse_context()
		settings_popup.visible = true
		settings_button.visible = false
		InputManager.lock_input("settings_pause")
		get_tree().paused = true
		_refresh_load_button_state()

func _on_exit_pressed() -> void:
	if _exit_dialog == null or _exit_in_progress:
		return
	_exit_dialog.popup_centered(EXIT_DIALOG_SIZE)

func _on_exit_confirmed() -> void:
	if _exit_in_progress:
		return
	_exit_in_progress = true
	# ConfirmationDialog can receive a second release while the first async
	# cleanup is still pending (especially with touch-to-mouse emulation).
	# Lock every exit control before the first await so the lifecycle is one-shot.
	exit_button.disabled = true
	if _exit_dialog != null:
		_exit_dialog.get_ok_button().disabled = true
		_exit_dialog.get_cancel_button().disabled = true
		_exit_dialog.hide()
	print("Settings: exit confirmed; discarding unsaved academic progress and closing playtime once")
	# Close the paused overlay and unpause the SceneTree before awaiting the
	# Screen Time request. HTTPRequest inherits the tree pause state; awaiting it
	# while paused otherwise stalls Exit until another UI action resumes gameplay.
	settings_popup.visible = false
	settings_button.visible = false
	get_tree().paused = false
	if RemoteSync != null and RemoteSync.has_method("request_end_playtime_session"):
		await RemoteSync.request_end_playtime_session()
	var discard_result: Dictionary = GameState.discard_unsaved_run()
	if not bool(discard_result.get("ok", false)):
		print("Settings: no valid active run was available to discard; Student identity was preserved.")
	InputManager.unlock_input("settings_pause")
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_exit_canceled() -> void:
	if _exit_in_progress:
		return
	_resume_game()

func _apply_confirmation_theme(dialog: ConfirmationDialog, destructive_action: bool = false) -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.055, 0.16, 1.0)
	panel_style.border_color = Color(0.94902, 0.823529, 0.443137, 1.0)
	panel_style.set_border_width_all(4)
	panel_style.content_margin_left = 20.0
	panel_style.content_margin_right = 20.0
	panel_style.content_margin_top = 18.0
	panel_style.content_margin_bottom = 18.0
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	panel_style.shadow_size = 6
	panel_style.shadow_offset = Vector2(3.0, 3.0)
	dialog.add_theme_stylebox_override("panel", panel_style)
	dialog.add_theme_color_override("font_color", Color(0.96, 0.91, 0.77, 1.0))
	dialog.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.78, 1.0))
	dialog.add_theme_font_override("font", CONFIRMATION_FONT)
	dialog.add_theme_font_size_override("font_size", 10)
	for button: Button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
		button.custom_minimum_size = Vector2(142.0, 42.0)
		button.add_theme_font_override("font", CONFIRMATION_FONT)
		button.add_theme_font_size_override("font_size", 8)
		button.add_theme_color_override("font_color", Color(0.98, 0.86, 0.5, 1.0))
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.82, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(0.93, 0.75, 0.32, 1.0))
		button.add_theme_stylebox_override("normal", _make_confirmation_button_style(false, destructive_action and button == dialog.get_ok_button()))
		button.add_theme_stylebox_override("hover", _make_confirmation_button_style(true, destructive_action and button == dialog.get_ok_button()))
		button.add_theme_stylebox_override("pressed", _make_confirmation_button_style(false, destructive_action and button == dialog.get_ok_button(), true))


func _make_confirmation_button_style(hovered: bool, destructive: bool, pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if destructive:
		style.bg_color = Color(0.40, 0.075, 0.11, 1.0) if not pressed else Color(0.28, 0.045, 0.07, 1.0)
		if hovered:
			style.bg_color = Color(0.58, 0.12, 0.15, 1.0)
	else:
		style.bg_color = Color(0.035, 0.16, 0.43, 1.0) if not pressed else Color(0.02, 0.095, 0.29, 1.0)
		if hovered:
			style.bg_color = Color(0.08, 0.27, 0.58, 1.0)
	style.border_color = Color(1.0, 0.78, 0.24, 1.0)
	style.set_border_width_all(3)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

func _on_save_confirmed() -> void:
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	var current_scene := get_tree().current_scene
	if player == null or current_scene == null:
		settings_popup.visible = true
		return

	GameState.capture_runtime(current_scene.scene_file_path, player.global_position)
	var save_path := GameState.save_manual_game()
	if save_path.is_empty():
		return

	if _save_dialog != null:
		_save_dialog.hide()
	_resume_game()
	_refresh_load_button_state()
	_show_save_success_toast()

func _on_save_canceled() -> void:
	if _save_dialog != null:
		_save_dialog.hide()
	settings_popup.visible = true

func _on_music_volume_changed(value: float) -> void:
	AudioSettingsManager.set_music_volume(value, false)

func _on_sfx_volume_changed(value: float) -> void:
	AudioSettingsManager.set_sfx_volume(value, false)

func _sync_volume_controls() -> void:
	music_slider.set_value_no_signal(AudioSettingsManager.get_music_volume())
	sfx_slider.set_value_no_signal(AudioSettingsManager.get_sfx_volume())

func _center_popup() -> void:
	if settings_popup == null or popup_texture == null:
		return
	_fit_popup_to_viewport(get_viewport_rect().size)


func _fit_popup_to_viewport(viewport_size: Vector2) -> void:
	var available_size := Vector2(
		maxf(viewport_size.x - POPUP_SAFE_MARGIN.x * 2.0, 1.0),
		maxf(viewport_size.y - POPUP_SAFE_MARGIN.y * 2.0, 1.0)
	)
	var scale_factor := minf(
		minf(available_size.x / SETTINGS_COMPOSITION_SIZE.x, available_size.y / SETTINGS_COMPOSITION_SIZE.y),
		1.0
	)
	settings_popup.scale = Vector2.ONE * scale_factor
	settings_popup.pivot_offset = Vector2.ZERO
	settings_popup.size = SETTINGS_COMPOSITION_SIZE
	settings_popup.position = (viewport_size - SETTINGS_COMPOSITION_SIZE * scale_factor) * 0.5

func _show_save_success_toast() -> void:
	if save_toast == null:
		return

	if _save_toast_tween != null and _save_toast_tween.is_valid():
		_save_toast_tween.kill()

	_position_save_toast()
	save_toast.visible = true
	save_toast.modulate.a = 0.0

	_save_toast_tween = create_tween()
	_save_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_save_toast_tween.set_trans(Tween.TRANS_SINE)
	_save_toast_tween.set_ease(Tween.EASE_OUT)
	_save_toast_tween.tween_property(save_toast, "modulate:a", 1.0, SAVE_TOAST_FADE_IN_DURATION)
	_save_toast_tween.tween_interval(SAVE_TOAST_VISIBLE_DURATION)
	_save_toast_tween.tween_property(save_toast, "modulate:a", 0.0, SAVE_TOAST_FADE_OUT_DURATION)
	_save_toast_tween.finished.connect(_on_save_toast_finished, CONNECT_ONE_SHOT)

func _on_save_toast_finished() -> void:
	if save_toast != null:
		save_toast.visible = false

func _position_save_toast() -> void:
	if save_toast == null:
		return

	var toast_width := save_toast.size.x
	if toast_width <= 0.0:
		toast_width = save_toast.get_combined_minimum_size().x

	save_toast.position = Vector2(maxf((size.x - toast_width) * 0.5, 12.0), 18.0)

func _refresh_load_button_state() -> void:
	var has_save := GameState.has_latest_save()
	load_button.disabled = not has_save
	load_button.mouse_filter = Control.MOUSE_FILTER_STOP
	load_button.modulate = ENABLED_BUTTON_MODULATE if has_save else DISABLED_BUTTON_MODULATE


func _on_save_created(_save_data: Dictionary) -> void:
	_refresh_load_button_state()
