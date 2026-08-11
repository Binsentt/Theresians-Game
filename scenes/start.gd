extends TextureButton 

@export var normal_scale: Vector2 = Vector2(1.0, 1.0)
@export var hover_scale: Vector2 = Vector2(1.08, 1.08)
@export var pressed_scale: Vector2 = Vector2(1.14, 1.14)

@export var hover_duration: float = 0.10
@export var press_duration: float = 0.05
@export var release_duration: float = 0.10

var tween: Tween
var custom_is_pressed := false
var _button_is_down := false
var _is_hovered := false

func _ready():
	pivot_offset = size / 2.0
	

	if not mouse_entered.is_connected(_on_hover):
		mouse_entered.connect(_on_hover)
	if not mouse_exited.is_connected(_on_exit):
		mouse_exited.connect(_on_exit)
	if not button_down.is_connected(_on_button_down):
		button_down.connect(_on_button_down)
	if not button_up.is_connected(_on_button_up):
		button_up.connect(_on_button_up)

func _animate(target: Vector2, duration: float):
	if tween:
		tween.kill()

	tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", target, duration)

func _on_hover():
	_is_hovered = true
	if custom_is_pressed:
		_animate(Vector2(1.18, 1.18), hover_duration)
	else:
		_animate(hover_scale, hover_duration)

func _on_exit():
	_is_hovered = false
	if custom_is_pressed:
		_animate(pressed_scale, release_duration)
	else:
		_animate(normal_scale, release_duration)

func _on_target_scale() -> Vector2:
	return hover_scale if _is_hovered else normal_scale

func _on_button_down() -> void:
	if _button_is_down:
		return

	_button_is_down = true
	custom_is_pressed = true
	_animate(pressed_scale, press_duration)

func _on_button_up() -> void:
	if not _button_is_down and not custom_is_pressed:
		return

	_button_is_down = false
	custom_is_pressed = false
	_animate(_on_target_scale(), release_duration)
