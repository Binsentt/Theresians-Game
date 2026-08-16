extends Button

@export var normal_scale: Vector2 = Vector2.ONE
@export var hover_scale: Vector2 = Vector2(1.04, 1.04)
@export var pressed_scale: Vector2 = Vector2(0.96, 0.96)
@export var hover_duration: float = 0.10
@export var press_duration: float = 0.05
@export var release_duration: float = 0.10
@export var popup_show_duration: float = 0.18

@onready var popup: Control = get_tree().current_scene.get_node_or_null("OptionsPopup") as Control

var _tween: Tween
var _is_hovered := false
var _is_pressed := false
var _should_open_popup := false

func _ready() -> void:
	flat = false
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_update_pivot)
	_update_pivot()

func _update_pivot() -> void:
	pivot_offset = size / 2.0

func _animate_to(target_scale: Vector2, duration: float) -> void:
	if _tween != null:
		_tween.kill()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", target_scale, duration)

func _target_scale() -> Vector2:
	if _is_pressed:
		return pressed_scale
	if _is_hovered:
		return hover_scale
	return normal_scale

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_pressed = true
			_should_open_popup = true
			_animate_to(pressed_scale, press_duration)
		else:
			_is_pressed = false
			_animate_to(_target_scale(), release_duration)
			if _should_open_popup:
				await _tween.finished
				await _show_popup()

func _show_popup() -> void:
	if popup == null:
		return

	popup.visible = true
	popup.pivot_offset = popup.size / 2.0
	popup.modulate.a = 0.0
	popup.scale = Vector2(0.86, 0.86)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 1.0, 0.10)
	tween.parallel().tween_property(popup, "scale", Vector2(1.02, 1.02), popup_show_duration)

	await tween.finished

	var settle := create_tween()
	settle.set_trans(Tween.TRANS_SINE)
	settle.set_ease(Tween.EASE_OUT)
	settle.tween_property(popup, "scale", Vector2.ONE, 0.08)

	await settle.finished
	_should_open_popup = false

func _on_mouse_entered() -> void:
	_is_hovered = true
	if not _is_pressed:
		_animate_to(hover_scale, hover_duration)

func _on_mouse_exited() -> void:
	_is_hovered = false
	if not _is_pressed:
		_animate_to(normal_scale, hover_duration)
