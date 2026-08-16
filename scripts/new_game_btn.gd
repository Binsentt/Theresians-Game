extends Button

@export var target_scene: String = "res://scenes/new_game_scene.tscn"
@export var normal_scale: Vector2 = Vector2.ONE
@export var hover_scale: Vector2 = Vector2(1.04, 1.04)
@export var pressed_scale: Vector2 = Vector2(0.96, 0.96)
@export var hover_duration: float = 0.10
@export var press_duration: float = 0.05
@export var release_duration: float = 0.10

var _tween: Tween
var _is_hovered := false
var _is_pressed := false
var _transitioning := false

func _ready() -> void:
	flat = false
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not resized.is_connected(_update_pivot):
		resized.connect(_update_pivot)
	_update_pivot()
	if not button_down.is_connected(_on_button_down):
		button_down.connect(_on_button_down)
	if not button_up.is_connected(_on_button_up):
		button_up.connect(_on_button_up)
	if not pressed.is_connected(_on_button_pressed):
		pressed.connect(_on_button_pressed)

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

func _on_button_down() -> void:
	if _transitioning or disabled:
		return

	_is_pressed = true
	_animate_to(pressed_scale, press_duration)

func _on_button_up() -> void:
	if _transitioning:
		return

	_is_pressed = false
	_animate_to(_target_scale(), release_duration)
	_begin_scene_transition()

func _on_button_pressed() -> void:
	if _transitioning or disabled:
		return

	if not _is_pressed:
		_on_button_down()
	_on_button_up()

func _begin_scene_transition() -> void:
	if _transitioning or disabled:
		return

	_transitioning = true
	disabled = true
	GameState.begin_new_game_registration()

	var active_tween := _tween
	if active_tween != null and active_tween.is_valid() and active_tween.is_running():
		await active_tween.finished

	var result := get_tree().change_scene_to_file(target_scene)
	if result != OK:
		_transitioning = false
		disabled = false
		_is_pressed = false
		_animate_to(normal_scale, release_duration)

func _on_mouse_entered() -> void:
	_is_hovered = true
	if not _is_pressed:
		_animate_to(hover_scale, hover_duration)

func _on_mouse_exited() -> void:
	_is_hovered = false
	if not _is_pressed:
		_animate_to(normal_scale, hover_duration)
