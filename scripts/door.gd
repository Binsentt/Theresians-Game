extends Area2D

class_name Door

@export_file("*.tscn") var destination_scene_path: String = ""
@export var destination_spawn_position: Vector2 = Vector2.ZERO
@export var destination_spawn_marker_name: String = ""
@export var destination_facing_direction: String = ""
@export var play_open_animation_before_transition: bool = false
@export var play_fade_transition: bool = false
@export var requires_city_of_knowledge_unlock: bool = false
@export var animation_target_path: NodePath = NodePath()
@export_range(0.01, 0.3, 0.01) var animation_step_duration: float = 0.06
@export_range(0.05, 3.0, 0.05) var fade_duration: float = 0.25
@export_enum("touch", "interact", "touch_or_interact") var trigger_mode: String = "touch"
@export var use_return_context: bool = false
@export var set_return_context_on_enter: bool = false
@export_file("*.tscn") var return_scene_path: String = ""
@export var return_spawn_position: Vector2 = Vector2.ZERO
@export var return_facing_direction: String = ""

var is_transitioning: bool = false
var _player_in_range: Node2D = null
var _touch_trigger_consumed: bool = false

func _ready() -> void:
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	set_process(trigger_mode == "interact" or trigger_mode == "touch_or_interact")

func _process(_delta: float) -> void:
	if is_transitioning or _player_in_range == null:
		return
	if trigger_mode == "touch":
		return
	if trigger_mode == "touch_or_interact" and _touch_trigger_consumed:
		return
	if not InputManager.is_interact_just_pressed():
		return
	_begin_transition(_player_in_range)

func _on_body_entered(body: Node2D) -> void:
	if body == null or not _is_player(body):
		return
	_player_in_range = body
	if trigger_mode == "interact":
		return
	if _touch_trigger_consumed:
		return
	_touch_trigger_consumed = true
	_begin_transition(body)

func _on_body_exited(body: Node2D) -> void:
	if body == null or body != _player_in_range:
		return
	_player_in_range = null
	_touch_trigger_consumed = false

func _begin_transition(body: Node2D) -> void:
	if is_transitioning:
		return
	if body == null or not _is_player(body):
		return
	if requires_city_of_knowledge_unlock and not GameState.city_of_knowledge_unlocked:
		return

	var resolved_destination := _resolve_destination_scene_path()
	if resolved_destination.is_empty():
		push_error("Door destination scene path is empty for %s." % name)
		return

	var resolved_spawn_position := _resolve_destination_spawn_position()
	var resolved_facing_direction := _resolve_destination_facing_direction()

	is_transitioning = true
	monitoring = false
	InputManager.lock_input("door_transition")
	if set_return_context_on_enter and not return_scene_path.is_empty():
		GameState.set_return_context(return_scene_path, return_spawn_position, return_facing_direction)

	if play_open_animation_before_transition:
		await _play_open_animation()
	if play_fade_transition:
		await _play_fade_transition()

	GameState.queue_scene_spawn(
		resolved_destination,
		resolved_spawn_position,
		resolved_facing_direction,
		destination_spawn_marker_name
	)

	var result := get_tree().change_scene_to_file(resolved_destination)
	if result != OK:
		InputManager.unlock_input("door_transition")
		monitoring = true
		is_transitioning = false
		push_error("Failed to change scene to %s for door %s." % [resolved_destination, name])

func play_open_animation_once() -> void:
	var animated_sprite := _get_animation_target()
	if animated_sprite != null:
		await _play_open_animation()
		return
	await get_tree().create_timer(animation_step_duration * 2.0).timeout

func _play_fade_transition() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var fade_layer := CanvasLayer.new()
	fade_layer.name = "DoorFadeTransitionLayer"
	fade_layer.layer = 128

	var fade_rect := ColorRect.new()
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(fade_rect)
	current_scene.add_child(fade_layer)

	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, fade_duration)
	await tween.finished

func _play_open_animation() -> void:
	var animated_sprite: AnimatedSprite2D = _get_animation_target()
	if animated_sprite == null:
		return

	animated_sprite.stop()
	animated_sprite.animation = &"default"
	animated_sprite.frame = 0
	await get_tree().create_timer(animation_step_duration).timeout
	if not is_instance_valid(animated_sprite):
		return
	animated_sprite.frame = 1
	await get_tree().create_timer(animation_step_duration).timeout
	if not is_instance_valid(animated_sprite):
		return
	animated_sprite.frame = 2

func _get_animation_target() -> AnimatedSprite2D:
	if not animation_target_path.is_empty():
		return get_node_or_null(animation_target_path) as AnimatedSprite2D
	return get_parent() as AnimatedSprite2D

func _resolve_destination_scene_path() -> String:
	if use_return_context and GameState.has_return_context():
		return GameState.get_return_scene_path()
	return destination_scene_path.strip_edges()

func _resolve_destination_spawn_position() -> Vector2:
	if use_return_context and GameState.has_return_context():
		return GameState.get_return_spawn_position()
	return destination_spawn_position

func _resolve_destination_facing_direction() -> String:
	if use_return_context and GameState.has_return_context():
		return GameState.get_return_facing_direction()
	return destination_facing_direction.to_lower().strip_edges()

func _is_player(body: Node2D) -> bool:
	return body.is_in_group("player") or body.is_in_group("player_character")
