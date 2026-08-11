extends Button

@export var target_scene: String = "res://scenes/main_menu.tscn"
@export var normal_scale: Vector2 = Vector2.ONE
@export var hover_scale: Vector2 = Vector2(1.04, 1.04)
@export var pressed_scale: Vector2 = Vector2(0.96, 0.96)
@export var hover_duration: float = 0.10
@export var press_duration: float = 0.05
@export var release_duration: float = 0.10

@onready var fade: CanvasItem = get_tree().current_scene.get_node_or_null("Fade") as CanvasItem
@onready var menu: CanvasItem = get_tree().current_scene.get_node_or_null("TextureRect") as CanvasItem

var _tween: Tween
var _is_hovered := false
var _is_pressed := false
var _should_change_scene := false

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
			_should_change_scene = true
			_animate_to(pressed_scale, press_duration)
		else:
			_is_pressed = false
			_animate_to(_target_scale(), release_duration)
			if _should_change_scene:
				await _tween.finished
				await _fade_and_change_scene()

func _fade_and_change_scene() -> void:
	if menu is Control:
		(menu as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	if menu != null:
		tween.tween_property(menu, "modulate:a", 0.0, 0.15)
	if fade != null:
		tween.parallel().tween_property(fade, "modulate:a", 1.0, 0.25)

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
