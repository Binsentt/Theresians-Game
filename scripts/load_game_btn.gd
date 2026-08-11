extends Button

@export var target_scene: String = "res://load_game_scene.tscn"

@export var normal_scale: Vector2 = Vector2(1.0, 1.0)
@export var hover_scale: Vector2 = Vector2(1.04, 1.04)
@export var pressed_scale: Vector2 = Vector2(1.12, 1.12)

@export var hover_duration: float = 0.10
@export var press_duration: float = 0.05
@export var release_duration: float = 0.10

@onready var fade = get_tree().current_scene.get_node("Fade")
@onready var menu = get_tree().current_scene.get_node("VBoxContainer")

var _tween: Tween
var _is_hovered: bool = false
var _is_pressed: bool = false
var _should_change_scene: bool = false

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	resized.connect(_update_pivot)
	_update_pivot()

func _update_pivot() -> void:
	pivot_offset = size / 2.0

func _animate_to(target_scale: Vector2, duration: float, ease_type: Tween.EaseType = Tween.EASE_OUT) -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(ease_type)
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
			_should_change_scene = true
			_animate_to(pressed_scale, press_duration)
		else:
			_is_pressed = false
			_animate_to(_on_target_scale(), release_duration)
			
			if _should_change_scene:
				await _tween.finished
				await _fade_and_change_scene()

func _fade_and_change_scene() -> void:
	# disable input para walang weird hover habang nagfa-fade
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var t = create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_OUT)

	# fade UI + fade screen sabay
	t.tween_property(menu, "modulate:a", 0.0, 0.15)
	t.parallel().tween_property(fade, "modulate:a", 1.0, 0.25)

	await t.finished

	get_tree().change_scene_to_file(target_scene)

func _on_mouse_entered() -> void:
	_is_hovered = true
	if not _is_pressed:
		_animate_to(hover_scale, hover_duration)

func _on_mouse_exited() -> void:
	_is_hovered = false
	if not _is_pressed:
		_animate_to(normal_scale, hover_duration)
