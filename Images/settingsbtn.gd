extends Button

@export var normal_scale: Vector2 = Vector2(1.0, 1.0)
@export var hover_scale: Vector2 = Vector2(1.03, 1.03) # subtle bump
@export var pressed_scale: Vector2 = Vector2(1.06, 1.06) # subtle press

@export var hover_duration: float = 0.15
@export var press_duration: float = 0.08
@export var release_duration: float = 0.12
@export var popup_show_duration: float = 0.20

# Correct path to popupRect
@onready var popup: Control = get_tree().current_scene.get_node_or_null("SettingsPopup")

var _tween: Tween
var _is_hovered := false
var _is_pressed := false
var _should_open_popup := false

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_update_pivot)
	_update_pivot()

func _update_pivot() -> void:
	pivot_offset = size / 2.0

func _animate_to(target_scale: Vector2, duration: float, trans := Tween.TRANS_SINE, ease := Tween.EASE_OUT) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(trans)
	_tween.set_ease(ease)
	_tween.tween_property(self, "scale", target_scale, duration)

func _on_target_scale() -> Vector2:
	if _is_pressed:
		return pressed_scale
	elif _is_hovered:
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
			_animate_to(_on_target_scale(), release_duration)
			if _should_open_popup:
				await _tween.finished
				await _show_popup()

func _show_popup() -> void:
	if not popup:
		push_warning("popupRect node not found in current scene.")
		return

	popup.visible = true
	popup.pivot_offset = popup.size / 2.0
	popup.modulate.a = 0.0
	popup.scale = Vector2(0.7, 0.7)

	# Blob effect: fade in + grow then settle
	var t = create_tween()
	t.set_trans(Tween.TRANS_BACK)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(popup, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(popup, "scale", Vector2(1.05, 1.05), popup_show_duration)
	await t.finished

	var t2 = create_tween()
	t2.set_trans(Tween.TRANS_SINE)
	t2.set_ease(Tween.EASE_OUT)
	t2.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.10)
	await t2.finished

	_should_open_popup = false

func _on_mouse_entered() -> void:
	_is_hovered = true
	if not _is_pressed:
		# subtle bounce effect
		_animate_to(hover_scale, hover_duration, Tween.TRANS_BACK, Tween.EASE_OUT)

func _on_mouse_exited() -> void:
	_is_hovered = false
	if not _is_pressed:
		_animate_to(normal_scale, hover_duration)
