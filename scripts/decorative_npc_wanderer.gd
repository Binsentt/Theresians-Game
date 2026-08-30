extends CharacterBody2D

# Opt-in ambient motion for a single decorative City NPC. Quest, dialogue, and
# enemy NPCs continue to use their existing static/interaction implementations.
@export var walk_speed: float = 30.0
@export var wander_radius: float = 42.0
@export var idle_seconds: float = 1.5

const CARDINAL_DIRECTIONS := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]

@onready var animated_sprite: AnimatedSprite2D = $CityNpc

var _home_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _idle_remaining := 0.0
var _next_direction_index := 0
var _resuming_from_dialogue := false


func _ready() -> void:
	_home_position = global_position
	_target_position = _home_position
	_enter_idle()


func _physics_process(delta: float) -> void:
	if GameState.get_mode() == GameState.GameMode.DIALOGUE:
		velocity = Vector2.ZERO
		_resuming_from_dialogue = true
		_play_idle()
		return

	if _resuming_from_dialogue:
		_resuming_from_dialogue = false
		_enter_idle()
		return

	if _idle_remaining > 0.0:
		_idle_remaining = maxf(0.0, _idle_remaining - delta)
		velocity = Vector2.ZERO
		return

	if global_position.distance_to(_target_position) <= 0.5:
		_begin_next_leg()
		return

	var direction := global_position.direction_to(_target_position)
	velocity = direction * walk_speed
	_play_walking(direction)
	move_and_slide()
	if get_slide_collision_count() > 0:
		_enter_idle()


func _begin_next_leg() -> void:
	_begin_leg(CARDINAL_DIRECTIONS[_next_direction_index])
	_next_direction_index = (_next_direction_index + 1) % CARDINAL_DIRECTIONS.size()


func _begin_leg(direction: Vector2) -> void:
	var cardinal_direction := _to_cardinal_direction(direction)
	_target_position = _home_position + cardinal_direction * wander_radius
	velocity = cardinal_direction * walk_speed
	_play_walking(cardinal_direction)


func _enter_idle() -> void:
	velocity = Vector2.ZERO
	_idle_remaining = idle_seconds
	_play_idle()


func _to_cardinal_direction(direction: Vector2) -> Vector2:
	if absf(direction.x) >= absf(direction.y):
		return Vector2.RIGHT if direction.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if direction.y >= 0.0 else Vector2.UP


func _play_walking(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		animated_sprite.play("walk_right" if direction.x > 0.0 else "walk_left")
		return
	animated_sprite.play("walk_down" if direction.y > 0.0 else "walk_up")


func _play_idle() -> void:
	animated_sprite.stop()
