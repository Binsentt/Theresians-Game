extends Node

signal input_lock_changed(is_locked: bool)

const DIRECTION_LEFT := "left"
const DIRECTION_RIGHT := "right"
const DIRECTION_UP := "up"
const DIRECTION_DOWN := "down"
const ACTION_INTERACT: StringName = &"interact"

var movement_vector: Vector2 = Vector2.ZERO
var interact_pressed: bool = false
var interact_just_pressed: bool = false
var _input_lock_reasons: Dictionary = {}

var _mobile_left: bool = false
var _mobile_right: bool = false
var _mobile_up: bool = false
var _mobile_down: bool = false
var _mobile_interact_pressed: bool = false
var _interact_edge_frame: int = -1


func _ready() -> void:
	# Restore the preserved E/Space interaction mapping only when absent.
	# Keep existing configured bindings and menu/text-entry actions intact.
	if not InputMap.has_action(ACTION_INTERACT):
		InputMap.add_action(ACTION_INTERACT)
		var letter := InputEventKey.new()
		letter.physical_keycode = KEY_E
		InputMap.action_add_event(ACTION_INTERACT, letter)
		var space := InputEventKey.new()
		space.keycode = KEY_SPACE
		InputMap.action_add_event(ACTION_INTERACT, space)
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

func _input(event: InputEvent) -> void:
	# Capture short keyboard taps even when both events arrive between frames.
	if not is_input_locked() and event.is_action(ACTION_INTERACT):
		_update_interact_state()


func _process(_delta: float) -> void:
	if is_input_locked():
		clear_mobile_state()
		return

	movement_vector = _get_mobile_vector()
	if Engine.get_process_frames() > _interact_edge_frame + 1:
		interact_just_pressed = false
	_update_interact_state()


func _update_interact_state() -> void:
	var held := _mobile_interact_pressed or _keyboard_interact_held()
	if held and not interact_pressed:
		interact_just_pressed = true
		_interact_edge_frame = Engine.get_process_frames()
	interact_pressed = held


func _keyboard_interact_held() -> bool:
	return InputMap.has_action(ACTION_INTERACT) and Input.is_action_pressed(ACTION_INTERACT)

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

	_mobile_interact_pressed = held
	_update_interact_state()

func clear_mobile_state() -> void:
	_mobile_left = false
	_mobile_right = false
	_mobile_up = false
	_mobile_down = false
	_mobile_interact_pressed = false
	movement_vector = Vector2.ZERO
	interact_pressed = _keyboard_interact_held()
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
	interact_pressed = _keyboard_interact_held()
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
	if current_mode == GameState.GameMode.DIALOGUE:
		_mobile_left = false
		_mobile_right = false
		_mobile_up = false
		_mobile_down = false
		movement_vector = Vector2.ZERO
	elif current_mode != GameState.GameMode.EXPLORATION:
		clear_mobile_state()


func _on_scene_changed() -> void:
	clear_mobile_state()
