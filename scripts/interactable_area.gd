extends Area2D

## Reusable proximity component. An empty target path uses the component's parent.
## Adapter results are interpreted as follows: bool results are authoritative; a void/null
## result counts as accepted after dispatch; other values use their normal bool conversion.
@export var interaction_target_path: NodePath = NodePath()
@export var interaction_method: StringName = &"interact"
@export var availability_method: StringName = &"can_interact"
@export var interaction_priority: int = 0
@export var interaction_enabled: bool = true:
	set(value):
		interaction_enabled = value
		if not interaction_enabled:
			_unregister_from_manager()
		elif is_inside_tree():
			_register_if_needed()

var _nearby_players: Array[Node] = []


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	call_deferred("_connect_lifecycle_signals")


func _exit_tree() -> void:
	_unregister_from_manager()
	_nearby_players.clear()


func can_interact() -> bool:
	if not interaction_enabled or not _has_nearby_player():
		return false
	if not _is_exploration_mode() or _is_input_locked():
		return false

	var target := _get_interaction_target()
	if target == null or not target.is_inside_tree() \
			or interaction_method.is_empty() or not target.has_method(interaction_method):
		return false
	if not availability_method.is_empty():
		if not target.has_method(availability_method):
			return false
		return target.call(availability_method) != false
	return true


func interact() -> bool:
	if not can_interact():
		return false

	var target := _get_interaction_target()
	if target == null or not target.is_inside_tree() or not target.has_method(interaction_method):
		return false
	var result: Variant = target.call(interaction_method)
	if result is bool:
		return result
	if result == null:
		return true
	return bool(result)


func get_interaction_position() -> Vector2:
	return global_position


func get_interaction_priority() -> int:
	return interaction_priority


func is_registration_valid() -> bool:
	if not interaction_enabled or interaction_method.is_empty():
		return false
	var target := _get_interaction_target()
	if target == null or not target.is_inside_tree() or not target.has_method(interaction_method):
		return false
	return availability_method.is_empty() or target.has_method(availability_method)


func _connect_lifecycle_signals() -> void:
	if not is_inside_tree():
		return

	var game_state := _get_game_state()
	if game_state != null and game_state.has_signal("mode_changed"):
		var mode_callback := Callable(self, "_on_game_mode_changed")
		if not game_state.is_connected("mode_changed", mode_callback):
			game_state.connect("mode_changed", mode_callback)

	var input_manager := _get_input_manager()
	if input_manager != null and input_manager.has_signal("input_lock_changed"):
		var lock_callback := Callable(self, "_on_input_lock_changed")
		if not input_manager.is_connected("input_lock_changed", lock_callback):
			input_manager.connect("input_lock_changed", lock_callback)

	_register_if_needed()


func _on_body_entered(body: Node2D) -> void:
	if not _is_player(body) or _nearby_players.has(body):
		return
	_nearby_players.append(body)
	_register_if_needed()


func _on_body_exited(body: Node2D) -> void:
	if not _is_player(body):
		return
	_nearby_players.erase(body)
	if not _has_nearby_player():
		_unregister_from_manager()


func _on_game_mode_changed(_previous_mode: Variant, current_mode: Variant) -> void:
	if current_mode != GameState.GameMode.EXPLORATION:
		_unregister_from_manager()
		return
	_register_if_needed()


func _on_input_lock_changed(is_locked: bool) -> void:
	if is_locked:
		_unregister_from_manager()
		return
	_register_if_needed()


func _register_if_needed() -> void:
	if not interaction_enabled or not _has_nearby_player() or not _is_exploration_mode() or _is_input_locked():
		return
	var interaction_manager := _get_interaction_manager()
	if interaction_manager != null and interaction_manager.has_method("register"):
		interaction_manager.call("register", self)


func _unregister_from_manager() -> void:
	var interaction_manager := _get_interaction_manager()
	if interaction_manager != null and interaction_manager.has_method("unregister"):
		interaction_manager.call("unregister", self)


func _has_nearby_player() -> bool:
	for index in range(_nearby_players.size() - 1, -1, -1):
		var player := _nearby_players[index]
		if not is_instance_valid(player) or not player.is_inside_tree() or not _is_player(player):
			_nearby_players.remove_at(index)
	return not _nearby_players.is_empty()


func _get_interaction_target() -> Node:
	var target: Node = get_parent() if interaction_target_path.is_empty() else get_node_or_null(interaction_target_path)
	if target == self or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	return target


func _is_player(body: Node) -> bool:
	return body != null and is_instance_valid(body) \
			and (body.is_in_group("player") or body.is_in_group("player_character"))


func _is_exploration_mode() -> bool:
	var game_state := _get_game_state()
	return game_state != null \
			and game_state.has_method("get_mode") \
			and game_state.get_mode() == GameState.GameMode.EXPLORATION


func _is_input_locked() -> bool:
	var input_manager := _get_input_manager()
	return input_manager == null \
			or not input_manager.has_method("is_input_locked") \
			or bool(input_manager.call("is_input_locked"))


func _get_interaction_manager() -> Node:
	return get_node_or_null("/root/InteractionManager")


func _get_game_state() -> Node:
	return get_node_or_null("/root/GameState")


func _get_input_manager() -> Node:
	return get_node_or_null("/root/InputManager")
