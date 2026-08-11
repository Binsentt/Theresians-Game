extends CharacterBody2D

@export var move_speed: float = 100.0

var last_direction: String = "down"
var can_move: bool = true

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("player")
	add_to_group("player_character")
	if not GameState.game_over.is_connected(_on_game_over):
		GameState.game_over.connect(_on_game_over)
	_play_animation("idle_%s" % last_direction)

func set_facing_direction(direction: String) -> void:
	var normalized_direction: String = direction.to_lower().strip_edges()
	if normalized_direction not in ["up", "down", "left", "right"]:
		return

	last_direction = normalized_direction
	_play_animation("idle_%s" % last_direction)

func _physics_process(_delta: float) -> void:
	var input_vector: Vector2 = Vector2.ZERO
	if can_move:
		input_vector = InputManager.get_movement_vector()

	velocity = input_vector * move_speed
	move_and_slide()
	_update_animation(input_vector)

func _update_animation(input_vector: Vector2) -> void:
	if input_vector == Vector2.ZERO:
		_play_animation("idle_%s" % last_direction)
		return

	last_direction = _get_dominant_direction(input_vector)
	_play_animation("walk_%s" % last_direction)

func _get_dominant_direction(input_vector: Vector2) -> String:
	var horizontal_direction: String = "right" if input_vector.x > 0.0 else "left"
	var vertical_direction: String = "down" if input_vector.y > 0.0 else "up"
	var horizontal_strength: float = absf(input_vector.x)
	var vertical_strength: float = absf(input_vector.y)

	if horizontal_strength > vertical_strength:
		return horizontal_direction
	if vertical_strength > horizontal_strength:
		return vertical_direction

	if last_direction == horizontal_direction or last_direction == vertical_direction:
		return last_direction

	return vertical_direction

func _play_animation(animation_name: String) -> void:
	if animated_sprite.animation == animation_name and animated_sprite.is_playing():
		return

	animated_sprite.play(animation_name)

func take_damage(amount: int = 1) -> void:
	GameState.lose_life(amount)

func lose_round() -> void:
	take_damage(1)

func _on_game_over() -> void:
	can_move = false
	velocity = Vector2.ZERO
