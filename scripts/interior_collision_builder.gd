extends Node

const DEFAULT_WIDTH_RATIO: float = 0.8
const DEFAULT_HEIGHT_RATIO: float = 0.35
const MIN_COLLIDER_SIZE: Vector2 = Vector2(8.0, 6.0)
const SKIPPED_SCENES := {
	"activity_board.tscn": true,
	"books.tscn": true,
	"carpet.tscn": true,
	"ceiling-decor.tscn": true,
	"door-carpet.tscn": true,
	"living-clock.tscn": true
}

const FOOTPRINT_OVERRIDES := {
	"bed-1.tscn": Vector2(0.82, 0.28),
	"bed-2.tscn": Vector2(0.82, 0.28),
	"bed-3.tscn": Vector2(0.82, 0.28),
	"black-board-side.tscn": Vector2(0.9, 0.2),
	"bookshell.tscn": Vector2(0.82, 0.3),
	"cabinet-decot.tscn": Vector2(0.76, 0.32),
	"clock.tscn": Vector2(0.55, 0.24),
	"computer.tscn": Vector2(0.62, 0.3),
	"computertable.tscn": Vector2(0.85, 0.32),
	"diningtable.tscn": Vector2(0.88, 0.38),
	"heater.tscn": Vector2(0.72, 0.28),
	"kitchen.tscn": Vector2(0.86, 0.3),
	"living-tv.tscn": Vector2(0.72, 0.26),
	"locker.tscn": Vector2(0.86, 0.32),
	"long-cabinet.tscn": Vector2(0.88, 0.3),
	"longchair-1.tscn": Vector2(0.8, 0.32),
	"longchair-2.tscn": Vector2(0.8, 0.32),
	"plate-cabinet.tscn": Vector2(0.72, 0.3),
	"side-sofa.tscn": Vector2(0.84, 0.34),
	"stair.tscn": Vector2(0.88, 0.24),
	"stove.tscn": Vector2(0.76, 0.28),
	"student_chair.tscn": Vector2(0.72, 0.42),
	"teacher_table.tscn": Vector2(0.92, 0.32)
}

func _ready() -> void:
	call_deferred("_build_colliders")

func _build_colliders() -> void:
	var owner_node: Node = get_parent()
	if owner_node == null:
		return

	for child_node: Node in owner_node.get_children():
		if child_node == self:
			continue
		if not (child_node is Sprite2D):
			continue

		var sprite: Sprite2D = child_node as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		if _should_skip(sprite):
			continue

		var body_name: String = "%sCollider" % sprite.name
		if owner_node.get_node_or_null(body_name) != null:
			continue

		var body: StaticBody2D = StaticBody2D.new()
		body.name = body_name
		body.position = sprite.position
		body.rotation = sprite.rotation

		var rectangle_shape: RectangleShape2D = _build_rectangle_shape(sprite)
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.shape = rectangle_shape
		collider.position = _get_shape_position(sprite, rectangle_shape)

		body.add_child(collider)
		owner_node.add_child(body)
		body.owner = owner_node
		collider.owner = owner_node

func _build_rectangle_shape(sprite: Sprite2D) -> RectangleShape2D:
	var scene_key: String = _get_scene_key(sprite)
	var ratio: Vector2 = FOOTPRINT_OVERRIDES.get(scene_key, Vector2(DEFAULT_WIDTH_RATIO, DEFAULT_HEIGHT_RATIO))
	var sprite_size: Vector2 = _get_scaled_sprite_size(sprite)
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(
		maxf(sprite_size.x * ratio.x, MIN_COLLIDER_SIZE.x),
		maxf(sprite_size.y * ratio.y, MIN_COLLIDER_SIZE.y)
	)
	return shape

func _get_shape_position(sprite: Sprite2D, shape: RectangleShape2D) -> Vector2:
	var sprite_size: Vector2 = _get_scaled_sprite_size(sprite)
	var rect: Rect2 = sprite.get_rect()
	var shape_size: Vector2 = shape.size
	var scaled_rect_position: Vector2 = Vector2(
		rect.position.x * absf(sprite.scale.x),
		rect.position.y * absf(sprite.scale.y)
	)
	return Vector2(
		scaled_rect_position.x + (sprite_size.x * 0.5),
		scaled_rect_position.y + sprite_size.y - (shape_size.y * 0.5)
	)

func _get_scaled_sprite_size(sprite: Sprite2D) -> Vector2:
	var rect: Rect2 = sprite.get_rect()
	return Vector2(
		absf(rect.size.x * sprite.scale.x),
		absf(rect.size.y * sprite.scale.y)
	)

func _should_skip(sprite: Sprite2D) -> bool:
	var scene_key: String = _get_scene_key(sprite)
	return SKIPPED_SCENES.has(scene_key)

func _get_scene_key(sprite: Sprite2D) -> String:
	return String(sprite.scene_file_path).get_file().to_lower()
