extends Control

const EXIT_PROMPT_TEXT := "Are you sure you want to exit the game?"
const SAVE_PROMPT_TEXT := "Do you want to save this game?"
const EXIT_DIALOG_SIZE := Vector2i(460, 170)
const SAVE_DIALOG_SIZE := Vector2i(460, 170)
const BUTTON_HOVER_SCALE := Vector2(1.04, 1.04)
const BUTTON_PRESSED_SCALE := Vector2(0.97, 0.97)
const BUTTON_NORMAL_SCALE := Vector2.ONE
const BUTTON_HOVER_DURATION := 0.12
const BUTTON_PRESS_DURATION := 0.06
const BUTTON_RELEASE_DURATION := 0.10
const SAVE_TOAST_FADE_IN_DURATION := 0.18
const SAVE_TOAST_VISIBLE_DURATION := 2.2
const SAVE_TOAST_FADE_OUT_DURATION := 0.32
const ENABLED_BUTTON_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const DISABLED_BUTTON_MODULATE := Color(1.0, 1.0, 1.0, 0.45)

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
	_configure_popup()
	_configure_save_toast()
	_build_exit_dialog()
	_build_save_dialog()
	_connect_controls()
	_sync_volume_controls()
	_refresh_load_button_state()
	call_deferred("_center_popup")
	call_deferred("_configure_button_animations")

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
	settings_button.offset_left = -124.0
	settings_button.offset_top = 12.0
	settings_button.offset_right = -16.0
	settings_button.offset_bottom = 120.0
	settings_button.visible = true

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
	_exit_dialog.title = "Exit Game"
	_exit_dialog.ok_button_text = "Yes"
	_exit_dialog.cancel_button_text = "Cancel"
	_exit_dialog.exclusive = true
	add_child(_exit_dialog)

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
	if not _exit_dialog.confirmed.is_connected(_on_exit_confirmed):
		_exit_dialog.confirmed.connect(_on_exit_confirmed)
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

	button.pivot_offset = button.size * 0.5
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
	_tween_button(button, BUTTON_HOVER_SCALE, BUTTON_HOVER_DURATION)

func _on_button_hover_exited(button: Button) -> void:
	_button_hover_states[button.get_instance_id()] = false
	_tween_button(button, BUTTON_NORMAL_SCALE, BUTTON_HOVER_DURATION)

func _on_button_down(button: Button) -> void:
	if button.disabled:
		return
	_tween_button(button, BUTTON_PRESSED_SCALE, BUTTON_PRESS_DURATION)

func _on_button_up(button: Button) -> void:
	var is_hovered := bool(_button_hover_states.get(button.get_instance_id(), false))
	var target_scale := BUTTON_HOVER_SCALE if is_hovered and not button.disabled else BUTTON_NORMAL_SCALE
	_tween_button(button, target_scale, BUTTON_RELEASE_DURATION)

func _tween_button(button: Button, target_scale: Vector2, duration: float) -> void:
	if button == null:
		return

	var key := button.get_instance_id()
	var existing_tween: Tween = _button_tweens.get(key)
	if existing_tween != null and existing_tween.is_valid():
		existing_tween.kill()

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, duration)
	_button_tweens[key] = tween

func _on_settings_button_pressed() -> void:
	_sync_volume_controls()
	_refresh_load_button_state()
	_center_popup()
	settings_popup.visible = true
	get_tree().paused = true

func _resume_game() -> void:
	if _exit_dialog != null and _exit_dialog.visible:
		_exit_dialog.hide()
	if _save_dialog != null and _save_dialog.visible:
		_save_dialog.hide()
	settings_popup.visible = false
	get_tree().paused = false

func _on_save_pressed() -> void:
	if _save_dialog == null:
		return
	_save_dialog.popup_centered(SAVE_DIALOG_SIZE)

func _on_load_pressed() -> void:
	if load_button.disabled:
		return

	var save_data := GameState.load_latest_save()
	var scene_path := String(save_data.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		_refresh_load_button_state()
		return

	settings_popup.visible = false
	get_tree().paused = false
	if _save_dialog != null:
		_save_dialog.hide()
	if _exit_dialog != null:
		_exit_dialog.hide()
	get_tree().change_scene_to_file(scene_path)

func _on_exit_pressed() -> void:
	if _exit_dialog == null:
		return
	_exit_dialog.popup_centered(EXIT_DIALOG_SIZE)

func _on_exit_confirmed() -> void:
	get_tree().quit()

func _on_save_confirmed() -> void:
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	var current_scene := get_tree().current_scene
	if player == null or current_scene == null:
		settings_popup.visible = true
		return

	GameState.capture_runtime(current_scene.scene_file_path, player.global_position)
	var save_path := GameState.save_game()
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

	var content_center_offset := popup_texture.position + (popup_texture.size * 0.5)
	settings_popup.position = (size * 0.5) - content_center_offset
	settings_popup.pivot_offset = content_center_offset

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
	load_button.mouse_filter = Control.MOUSE_FILTER_STOP if has_save else Control.MOUSE_FILTER_IGNORE
	load_button.modulate = ENABLED_BUTTON_MODULATE if has_save else DISABLED_BUTTON_MODULATE
