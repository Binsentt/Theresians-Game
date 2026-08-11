extends CanvasLayer

const DIRECTION_BUTTON_SCALE := Vector2(1.0, 1.0)
const DIRECTION_BUTTON_PRESSED_SCALE := Vector2(0.94, 0.94)

@export var force_visible_for_testing: bool = false

@onready var root: Control = $Root
@onready var up_button: TouchHoldButton = $Root/MovementMargin/MovementPanel/MovementBox/TopRow/UpButton
@onready var left_button: TouchHoldButton = $Root/MovementMargin/MovementPanel/MovementBox/MiddleRow/LeftButton
@onready var right_button: TouchHoldButton = $Root/MovementMargin/MovementPanel/MovementBox/MiddleRow/RightButton
@onready var down_button: TouchHoldButton = $Root/MovementMargin/MovementPanel/MovementBox/BottomRow/DownButton
@onready var action_margin: Control = $Root/ActionMargin
@onready var action_panel: Control = $Root/ActionMargin/ActionPanel
@onready var interact_button: TouchHoldButton = $Root/ActionMargin/ActionPanel/ActionButton

func _ready() -> void:
	_connect_direction_button(up_button, InputManager.DIRECTION_UP)
	_connect_direction_button(left_button, InputManager.DIRECTION_LEFT)
	_connect_direction_button(right_button, InputManager.DIRECTION_RIGHT)
	_connect_direction_button(down_button, InputManager.DIRECTION_DOWN)
	if not root.visibility_changed.is_connected(_on_root_visibility_changed):
		root.visibility_changed.connect(_on_root_visibility_changed)
	_connect_interact_button(interact_button)
	_connect_game_state()
	_connect_input_manager()
	_connect_interaction_manager()

	_update_visibility()

func configure(show_for_testing: bool) -> void:
	force_visible_for_testing = show_for_testing
	_update_visibility()

func _on_root_visibility_changed() -> void:
	if not root.visible:
		_force_release_all()

func _exit_tree() -> void:
	_force_release_all()
	InputManager.clear_mobile_state()

func _connect_direction_button(button: TouchHoldButton, direction: StringName) -> void:
	var callback := _on_direction_hold_changed.bind(direction, button)
	if not button.hold_changed.is_connected(callback):
		button.hold_changed.connect(callback)

func _connect_interact_button(button: TouchHoldButton) -> void:
	if not button.hold_changed.is_connected(_on_interact_hold_changed):
		button.hold_changed.connect(_on_interact_hold_changed)

func _on_direction_hold_changed(held: bool, direction: StringName, button: TouchHoldButton) -> void:
	InputManager.set_mobile_direction(direction, held)
	button.scale = DIRECTION_BUTTON_PRESSED_SCALE if held else DIRECTION_BUTTON_SCALE

func _on_interact_hold_changed(held: bool) -> void:
	InputManager.set_mobile_interact_pressed(held)
	interact_button.scale = DIRECTION_BUTTON_PRESSED_SCALE if held else DIRECTION_BUTTON_SCALE

func _connect_game_state() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state == null or not game_state.has_signal("mode_changed"):
		return

	var callback := Callable(self, "_on_game_mode_changed")
	if not game_state.is_connected("mode_changed", callback):
		game_state.connect("mode_changed", callback)


func _connect_input_manager() -> void:
	var callback := Callable(self, "_on_input_lock_changed")
	if not InputManager.is_connected("input_lock_changed", callback):
		InputManager.connect("input_lock_changed", callback)
	if InputManager.is_input_locked():
		_on_input_lock_changed(true)


func _connect_interaction_manager() -> void:
	var interaction_manager := get_node_or_null("/root/InteractionManager")
	if interaction_manager == null or not interaction_manager.has_signal("active_interactable_changed"):
		return

	var callback := Callable(self, "_on_active_interactable_changed")
	if not interaction_manager.is_connected("active_interactable_changed", callback):
		interaction_manager.connect("active_interactable_changed", callback)


func _on_game_mode_changed(_previous_mode: Variant, _current_mode: Variant) -> void:
	_update_visibility()


func _on_input_lock_changed(is_locked: bool) -> void:
	if is_locked:
		_force_release_all()
	_update_visibility()


func _on_active_interactable_changed(_component: Node) -> void:
	_update_visibility()


func _hide_interact_control() -> void:
	action_margin.visible = false
	action_panel.visible = false
	interact_button.visible = false
	interact_button.disabled = true
	interact_button.force_release()


func _force_release_all() -> void:
	if not is_instance_valid(up_button):
		return

	up_button.force_release()
	left_button.force_release()
	right_button.force_release()
	down_button.force_release()
	interact_button.force_release()
	InputManager.clear_mobile_state()


func _is_exploration_mode() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state != null and game_state.get_mode() == GameState.GameMode.EXPLORATION


func _has_active_interactable() -> bool:
	var interaction_manager := get_node_or_null("/root/InteractionManager")
	return interaction_manager != null \
			and interaction_manager.has_method("has_active_interactable") \
			and bool(interaction_manager.call("has_active_interactable"))

func _update_visibility() -> void:
	if not is_inside_tree():
		return

	var should_show: bool = _is_exploration_mode() and (force_visible_for_testing or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available())
	var should_show_interact: bool = should_show and not InputManager.is_input_locked() and _has_active_interactable()
	if should_show_interact:
		action_margin.visible = true
		action_panel.visible = true
		interact_button.visible = true
		interact_button.disabled = false
	else:
		_hide_interact_control()
	if not should_show:
		_force_release_all()
	root.visible = should_show
	visible = should_show
