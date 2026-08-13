extends Node

## Central selection service for reusable exploration interactions.
signal active_interactable_changed(component)

const PLAYER_GROUPS: Array[StringName] = [&"player_character", &"player"]

var _registrations: Dictionary = {}
var _next_registration_ordinal: int = 0
var _active_interactable: Node = null
var _interaction_locked_until_release: bool = false


func _ready() -> void:
	call_deferred("_connect_lifecycle_signals")


func _exit_tree() -> void:
	_registrations.clear()
	_set_active_interactable(null)


func _process(_delta: float) -> void:
	if _interaction_locked_until_release and not _is_interact_held():
		_interaction_locked_until_release = false
	_refresh_active_interactable()
	request_interaction()


func register(component: Node) -> bool:
	if component == null or not is_instance_valid(component) or _registrations.has(component):
		return false

	_registrations[component] = _next_registration_ordinal
	_next_registration_ordinal += 1
	_refresh_active_interactable()
	return true


func unregister(component: Node) -> bool:
	if component == null or not _registrations.has(component):
		return false

	_registrations.erase(component)
	if _active_interactable == component:
		_set_active_interactable(null)
	else:
		_refresh_active_interactable()
	return true


func has_active_interactable() -> bool:
	return get_active_interactable() != null


func get_active_interactable() -> Node:
	_refresh_active_interactable()
	return _active_interactable


func request_interaction() -> bool:
	if _interaction_locked_until_release:
		if _is_interact_held():
			return false
		_interaction_locked_until_release = false

	if not _is_exploration_mode() or _is_input_locked():
		_set_active_interactable(null)
		return false

	_refresh_active_interactable()
	var component := _active_interactable
	if component == null or not is_instance_valid(component):
		return false

	var input_manager := _get_input_manager()
	if input_manager == null or not input_manager.has_method("consume_interact_just_pressed"):
		return false
	if not bool(input_manager.call("consume_interact_just_pressed")):
		return false

	# One physical touch can issue one request even if an adapter rejects it.
	_interaction_locked_until_release = true
	if not component.has_method("interact"):
		unregister(component)
		return false
	return bool(component.call("interact"))


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

	var scene_tree := get_tree()
	if scene_tree != null and not scene_tree.scene_changed.is_connected(_on_scene_changed):
		scene_tree.scene_changed.connect(_on_scene_changed)

	_refresh_active_interactable()


func _on_game_mode_changed(_previous_mode: Variant, current_mode: Variant) -> void:
	if current_mode != GameState.GameMode.EXPLORATION:
		_set_active_interactable(null)
		return
	_refresh_active_interactable()


func _on_input_lock_changed(is_locked: bool) -> void:
	if is_locked:
		_interaction_locked_until_release = false
		_set_active_interactable(null)
		return
	_refresh_active_interactable()


func _on_scene_changed() -> void:
	var current_scene: Node = get_tree().current_scene if get_tree() != null else null
	var stale_components: Array = []
	for component in _registrations.keys():
		if not _is_component_in_current_scene(component, current_scene):
			stale_components.append(component)
	for component in stale_components:
		_registrations.erase(component)
	_refresh_active_interactable()


func _refresh_active_interactable() -> void:
	if not _is_exploration_mode() or _is_input_locked():
		_set_active_interactable(null)
		return

	var player := _get_current_player()
	if player == null:
		_set_active_interactable(null)
		return

	var stale_components: Array = []
	var best_component: Node = null
	var best_priority: int = 0
	var best_distance_squared: float = 0.0
	var best_ordinal: int = 0

	for component in _registrations.keys():
		if not _is_candidate_registration_valid(component):
			stale_components.append(component)
			continue
		if not _can_candidate_interact(component):
			continue

		var position_value: Variant = component.call("get_interaction_position")
		var priority_value: Variant = component.call("get_interaction_priority")
		if not (position_value is Vector2) or not _is_numeric(priority_value):
			stale_components.append(component)
			continue

		var priority := int(priority_value)
		var distance_squared := player.global_position.distance_squared_to(position_value)
		var ordinal := int(_registrations[component])
		if best_component == null \
				or priority > best_priority \
				or (priority == best_priority and distance_squared < best_distance_squared) \
				or (priority == best_priority and is_equal_approx(distance_squared, best_distance_squared) and ordinal < best_ordinal):
			best_component = component
			best_priority = priority
			best_distance_squared = distance_squared
			best_ordinal = ordinal

	for component in stale_components:
		_registrations.erase(component)

	_set_active_interactable(best_component)


func _is_candidate_registration_valid(component: Variant) -> bool:
	if not (component is Node) or not is_instance_valid(component) or not component.is_inside_tree():
		return false
	if not component.has_method("can_interact") \
				or not component.has_method("get_interaction_position") \
				or not component.has_method("get_interaction_priority"):
		return false
	if component.has_method("is_registration_valid"):
		return component.call("is_registration_valid") == true
	return true


func _can_candidate_interact(component: Node) -> bool:
	return component.call("can_interact") == true


func _is_component_in_current_scene(component: Variant, current_scene: Node) -> bool:
	if not (component is Node) or not is_instance_valid(component) or not component.is_inside_tree():
		return false
	if current_scene == null:
		return true
	return component == current_scene or current_scene.is_ancestor_of(component)


func _get_current_player() -> Node2D:
	var scene_tree := get_tree()
	if scene_tree == null:
		return null
	var seen_players: Dictionary = {}
	for player_group in PLAYER_GROUPS:
		for player in scene_tree.get_nodes_in_group(player_group):
			if seen_players.has(player):
				continue
			seen_players[player] = true
			if player is Node2D and is_instance_valid(player) and player.is_inside_tree():
				return player
	return null


func _is_numeric(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _set_active_interactable(component: Node) -> void:
	if _active_interactable == component:
		return
	_active_interactable = component
	active_interactable_changed.emit(component)


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


func _is_interact_held() -> bool:
	var input_manager := _get_input_manager()
	return input_manager != null \
			and input_manager.has_method("is_interact_pressed") \
			and bool(input_manager.call("is_interact_pressed"))


func _get_game_state() -> Node:
	return get_node_or_null("/root/GameState")


func _get_input_manager() -> Node:
	return get_node_or_null("/root/InputManager")
