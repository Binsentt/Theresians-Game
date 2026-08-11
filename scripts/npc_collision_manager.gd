extends Node

const NPC_SCENE_PREFIXES := [
	"res://NPC/Npc/",
	"res://NPC/Enemy/"
]
const NPC_SCENE_PATHS := [
	"res://NPC/Teacher.tscn"
]
const NPC_NAME_HINTS := [
	"teacher",
	"wizard"
]
const NPC_COLLISION_LAYER := 2
const NPC_COLLISION_MASK := 1
const FOOT_WIDTH_RATIO := 0.45
const FOOT_HEIGHT_RATIO := 0.16
const FOOT_Y_RATIO := 0.44
const MIN_FOOT_COLLISION_SIZE := Vector2(24, 16)
const DEFAULT_FRAME_SIZE := Vector2(120, 160)

func ensure_scene_collisions(root: Node) -> void:
	if root == null:
		return
	_ensure_npc_collisions.call_deferred(root)

func _ensure_npc_collisions(root: Node) -> void:
	for node: Node in root.find_children("*", "AnimatedSprite2D", true, false):
		var sprite := node as AnimatedSprite2D
		if sprite == null:
			continue
		if not _is_npc_sprite(sprite):
			continue
		_ensure_foot_collision(sprite)

func _ensure_foot_collision(sprite: AnimatedSprite2D) -> void:
	var body := sprite.get_node_or_null("NpcBodyCollision") as StaticBody2D
	if body == null:
		body = StaticBody2D.new()
		body.name = "NpcBodyCollision"
		sprite.add_child(body)

	body.collision_layer = NPC_COLLISION_LAYER
	body.collision_mask = NPC_COLLISION_MASK

	var collision := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		body.add_child(collision)

	var rectangle := collision.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		collision.shape = rectangle

	var frame_size := _get_sprite_frame_size(sprite)
	rectangle.size = Vector2(
		maxf(frame_size.x * FOOT_WIDTH_RATIO, MIN_FOOT_COLLISION_SIZE.x),
		maxf(frame_size.y * FOOT_HEIGHT_RATIO, MIN_FOOT_COLLISION_SIZE.y)
	)
	collision.position = Vector2(0, frame_size.y * FOOT_Y_RATIO)

func _is_npc_sprite(sprite: AnimatedSprite2D) -> bool:
	var scene_path := String(sprite.scene_file_path)
	for prefix: String in NPC_SCENE_PREFIXES:
		if scene_path.begins_with(prefix):
			return true
	for npc_scene_path: String in NPC_SCENE_PATHS:
		if scene_path == npc_scene_path:
			return true

	var normalized_name := sprite.name.to_lower()
	for hint: String in NPC_NAME_HINTS:
		if normalized_name.contains(hint):
			return true

	return false

func _get_sprite_frame_size(sprite: AnimatedSprite2D) -> Vector2:
	var frames := sprite.sprite_frames
	if frames == null:
		return DEFAULT_FRAME_SIZE

	var animation_name: StringName = sprite.animation
	if not frames.has_animation(animation_name):
		var animation_names := frames.get_animation_names()
		if animation_names.is_empty():
			return DEFAULT_FRAME_SIZE
		animation_name = animation_names[0]

	var frame_count := frames.get_frame_count(animation_name)
	if frame_count <= 0:
		return DEFAULT_FRAME_SIZE

	var frame_index := clampi(sprite.frame, 0, frame_count - 1)
	var texture := frames.get_frame_texture(animation_name, frame_index)
	if texture == null:
		return DEFAULT_FRAME_SIZE

	return texture.get_size()
