extends Node

const MobileControlsScene := preload("res://ui/mobile_controls.tscn")
const PlayerScript := preload("res://scripts/top_down_player.gd")

var _failures: Array[String] = []


class FakeInteractable extends Node2D:
	var activation_count := 0

	func can_interact() -> bool:
		return true

	func is_registration_valid() -> bool:
		return true

	func get_interaction_position() -> Vector2:
		return global_position

	func get_interaction_priority() -> int:
		return 0

	func interact() -> bool:
		activation_count += 1
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	var original_mode := GameState.get_mode()
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	InputManager.clear_mobile_state()

	var player := Node2D.new()
	player.name = "ProjectContextPlayer"
	player.add_to_group("player_character")
	get_tree().root.add_child(player)
	var target := FakeInteractable.new()
	target.name = "ProjectContextInteractable"
	target.global_position = Vector2.ZERO
	get_tree().root.add_child(target)
	InteractionManager.register(target)

	var controls := MobileControlsScene.instantiate()
	get_tree().root.add_child(controls)
	controls.configure(true)
	await _wait_frames(3)

	var up_button := controls.get_node_or_null("Root/MovementMargin/MovementPanel/MovementBox/TopRow/UpButton") as Button
	var right_button := controls.get_node_or_null("Root/MovementMargin/MovementPanel/MovementBox/MiddleRow/RightButton") as Button
	var action_button := controls.get_node_or_null("Root/ActionMargin/ActionPanel/ActionButton") as Button
	_assert(controls.visible, "D-pad is available in exploration mode")
	_assert(up_button != null and right_button != null and action_button != null, "Mobile D-pad and Interact controls exist")
	_assert(action_button != null and action_button.visible and not action_button.disabled, "Interact is available for an active target")

	if right_button != null:
		_send_hold(right_button, true)
		await _wait_frames(1)
		_assert(InputManager.get_movement_vector() == Vector2.RIGHT, "D-pad routes right movement through InputManager")
		_send_hold(right_button, false)
	if up_button != null and right_button != null:
		_send_hold(up_button, true)
		_send_hold(right_button, true)
		await _wait_frames(1)
		_assert(InputManager.get_movement_vector().length() <= 1.0, "Two held D-pad directions remain normalized")
		_send_hold(up_button, false)
		_send_hold(right_button, false)

	Input.action_press("ui_right")
	var keyboard_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	Input.action_release("ui_right")
	_assert(keyboard_vector == Vector2.RIGHT, "Keyboard movement semantics match D-pad right movement")

	if action_button != null:
		_send_hold(action_button, true)
		_assert(InteractionManager.request_interaction(), "Interact button routes through the project InteractionManager")
		_assert(target.activation_count == 1, "Interact activates the selected target once")
		_send_hold(action_button, false)

	var baseline_player := PlayerScript.new()
	_assert(is_equal_approx(baseline_player.move_speed, 60.0), "Player movement speed remains the approved value of 60 px/s")
	baseline_player.free()

	GameState.set_mode(GameState.GameMode.DIALOGUE)
	await _wait_frames(2)
	_assert(not up_button.is_visible_in_tree() and action_button.is_visible_in_tree(), "Dialogue hides movement and retains the existing Interact continuation")
	_assert(InputManager.get_movement_vector() == Vector2.ZERO, "Dialogue mode clears held mobile movement")
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	InputManager.lock_input("project_context_mobile_test")
	await _wait_frames(2)
	_assert(action_button != null and (not action_button.visible or action_button.disabled), "Input lock disables mobile Interact")
	_assert(InputManager.get_movement_vector() == Vector2.ZERO, "Input lock clears mobile movement")
	InputManager.unlock_input("project_context_mobile_test")

	InteractionManager.unregister(target)
	controls.queue_free()
	target.queue_free()
	player.queue_free()
	GameState.set_mode(original_mode)
	InputManager.clear_mobile_state()
	await _wait_frames(2)
	_finish()


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _send_hold(button: Button, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	button._gui_input(event)


func _wait_frames(frame_count: int) -> void:
	for _index in frame_count:
		await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MOBILE_CONTROLS_PROJECT_CONTEXT_TEST PASSED")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("MOBILE_CONTROLS_PROJECT_CONTEXT_TEST FAILED")
	get_tree().quit(1)
