@tool
extends StaticBody2D

var _texture_override: Texture2D
var _flip_h_override: bool = false
var _flip_v_override: bool = false

@export var texture: Texture2D:
	get:
		return _texture_override
	set(value):
		_texture_override = value
		_apply_visual_overrides()

@export var flip_h: bool = false:
	get:
		return _flip_h_override
	set(value):
		_flip_h_override = value
		_apply_visual_overrides()

@export var flip_v: bool = false:
	get:
		return _flip_v_override
	set(value):
		_flip_v_override = value
		_apply_visual_overrides()

func _ready() -> void:
	_apply_visual_overrides()

func _apply_visual_overrides() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return

	if _texture_override != null:
		sprite.texture = _texture_override

	sprite.flip_h = _flip_h_override
	sprite.flip_v = _flip_v_override
