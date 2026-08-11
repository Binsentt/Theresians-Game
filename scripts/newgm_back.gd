extends Button

@export var target_scene: String = "res://scenes/main_menu.tscn"
@export var normal_scale: Vector2 = Vector2.ONE
@export var hover_scale: Vector2 = Vector2(1.04, 1.04)
@export var pressed_scale: Vector2 = Vector2(0.96, 0.96)
@export var hover_duration: float = 0.10
@export var press_duration: float = 0.05
@export var release_duration: float = 0.10

@onready var fade: CanvasItem = get_tree().current_scene.get_node_or_null("Fade") as CanvasItem
@onready var menu: Control = get_tree().current_scene.get_node_or_null("TextureRect2") as Control

var _tween: Tween
var _is_hovered := false
var _is_pressed := false
var _should_change_scene := false
var _transitioning := false

func _ready() -> void:
	flat = true
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
	_should_change_scene = true
	_animate_to(pressed_scale, press_duration)

func _on_button_up() -> void:
	if _transitioning:
		return

	var should_change_scene := _should_change_scene
	_is_pressed = false
	_should_change_scene = false
	_animate_to(_target_scale(), release_duration)

	if should_change_scene:
		_begin_back_transition()

func _on_button_pressed() -> void:
	if _transitioning or disabled:
		return

	if not _should_change_scene:
		_on_button_down()
	_on_button_up()

func _begin_back_transition() -> void:
	if _transitioning or disabled:
		return

	_transitioning = true
	disabled = true

	var release_tween := _tween
	if release_tween != null and release_tween.is_valid():
		await release_tween.finished

	if menu != null and menu.has_method("handle_back"):
		await menu.call("handle_back")
		_transitioning = false
		disabled = false
		return

	GameState.clear_new_game_registration()
	await _fade_and_change_scene()

func _fade_and_change_scene() -> void:
	if menu != null:
		menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	var has_tween := false

	if menu != null:
		tween.tween_property(menu, "modulate:a", 0.0, 0.15)
		has_tween = true
	if fade != null:
		if has_tween:
			tween.parallel().tween_property(fade, "modulate:a", 1.0, 0.25)
		else:
			tween.tween_property(fade, "modulate:a", 1.0, 0.25)
			has_tween = true

	if has_tween:
		await tween.finished
	get_tree().change_scene_to_file(target_scene)

func _on_mouse_entered() -> void:
	_is_hovered = true
	if not _is_pressed:
		_animate_to(hover_scale, hover_duration)

func _on_mouse_exited() -> void:
	_is_hovered = false
	if not _is_pressed:
		_animate_to(normal_scale, hover_duration)
