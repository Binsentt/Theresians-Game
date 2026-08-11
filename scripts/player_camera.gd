extends Camera2D

@export var camera_smoothing_enabled: bool = true
@export_range(5.0, 10.0, 0.1) var camera_smoothing_speed: float = 6.0
@export var camera_zoom: Vector2 = Vector2(5.0, 5.0)

func _ready() -> void:
	position = Vector2.ZERO
	_neutralize_parent_scale()
	enabled = true
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = camera_smoothing_enabled
	position_smoothing_speed = camera_smoothing_speed
	zoom = camera_zoom
	make_current()
	_apply_map_limits()

func _neutralize_parent_scale() -> void:
	var parent_node := get_parent() as Node2D
	if parent_node == null:
		return

	if is_zero_approx(parent_node.scale.x) or is_zero_approx(parent_node.scale.y):
		return

	# The current player scenes are scaled at the root, so cancel that on the
	# camera to keep the view at a normal zoom while remaining parented.
	scale = Vector2(1.0 / parent_node.scale.x, 1.0 / parent_node.scale.y)

func _apply_map_limits() -> void:
	var bounds: MapCameraBounds = get_tree().get_first_node_in_group("map_camera_bounds") as MapCameraBounds
	if bounds == null:
		return

	limit_left = bounds.limit_left
	limit_right = bounds.limit_right
	limit_top = bounds.limit_top
	limit_bottom = bounds.limit_bottom
