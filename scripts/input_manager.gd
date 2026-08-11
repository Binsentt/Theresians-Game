extends Node

signal input_lock_changed(is_locked: bool)

const DIRECTION_LEFT := "left"
const DIRECTION_RIGHT := "right"
const DIRECTION_UP := "up"
const DIRECTION_DOWN := "down"

var movement_vector: Vector2 = Vector2.ZERO
var interact_pressed: bool = false
var interact_just_pressed: bool = false
var _input_lock_reasons: Dictionary = {}

var _mobile_left: bool = false
var _mobile_right: bool = false
var _mobile_up: bool = false
var _mobile_down: bool = false
var _mobile_interact_pressed: bool = false


func _ready() -> void:
	call_deferred("_connect_lifecycle_signals")


func _exit_tree() -> void:
	clear_mobile_state()


func _connect_lifecycle_signals() -> void:
	if not is_inside_tree():
		return

	var game_state := get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_signal("mode_changed"):
		var mode_changed_callback := Callable(self, "_on_game_mode_changed")
		if not game_state.is_connected("mode_changed", mode_changed_callback):
			game_state.connect("mode_changed", mode_changed_callback)

	var scene_tree := get_tree()
	if scene_tree != null and not scene_tree.scene_changed.is_connected(_on_scene_changed):
		scene_tree.scene_changed.connect(_on_scene_changed)

func _process(_delta: float) -> void:
	if is_input_locked():
		clear_mobile_state()
		return

	movement_vector = _get_mobile_vector()
	interact_pressed = _mobile_interact_pressed

func get_movement_vector() -> Vector2:
	return movement_vector

func is_interact_pressed() -> bool:
	return interact_pressed

func is_interact_just_pressed() -> bool:
	return consume_interact_just_pressed()

func consume_interact_just_pressed() -> bool:
	var was_just_pressed := interact_just_pressed
	interact_just_pressed = false
	return was_just_pressed

func set_mobile_direction(direction: StringName, held: bool) -> void:
	if is_input_locked():
		return

	match String(direction):
		DIRECTION_LEFT:
			_mobile_left = held
		DIRECTION_RIGHT:
			_mobile_right = held
		DIRECTION_UP:
			_mobile_up = held
		DIRECTION_DOWN:
			_mobile_down = held

func set_mobile_interact_pressed(held: bool) -> void:
	if is_input_locked():
		return

	if held and not _mobile_interact_pressed:
		interact_just_pressed = true
	_mobile_interact_pressed = held
	if not held:
		interact_pressed = false
		interact_just_pressed = false

func clear_mobile_state() -> void:
	_mobile_left = false
	_mobile_right = false
	_mobile_up = false
	_mobile_down = false
	_mobile_interact_pressed = false
	movement_vector = Vector2.ZERO
	interact_pressed = false
	interact_just_pressed = false

func lock_input(reason: String = "global") -> void:
	var was_locked := is_input_locked()
	var normalized_reason := reason.strip_edges()
	if normalized_reason.is_empty():
		normalized_reason = "global"
	_input_lock_reasons[normalized_reason] = true
	clear_mobile_state()
	if not was_locked:
		input_lock_changed.emit(true)

func unlock_input(reason: String = "global") -> void:
	var was_locked := is_input_locked()
	var normalized_reason := reason.strip_edges()
	if normalized_reason.is_empty():
		normalized_reason = "global"
	_input_lock_reasons.erase(normalized_reason)
	interact_pressed = false
	interact_just_pressed = false
	if was_locked and not is_input_locked():
		input_lock_changed.emit(false)

func is_input_locked() -> bool:
	return not _input_lock_reasons.is_empty()

func _get_mobile_vector() -> Vector2:
	var x_axis: float = float(_mobile_right) - float(_mobile_left)
	var y_axis: float = float(_mobile_down) - float(_mobile_up)
	return Vector2(x_axis, y_axis).limit_length(1.0)

func _on_game_mode_changed(_previous_mode: Variant, current_mode: Variant) -> void:
	if current_mode != GameState.GameMode.EXPLORATION:
		clear_mobile_state()


func _on_scene_changed(_new_scene: Node) -> void:
	clear_mobile_state()
