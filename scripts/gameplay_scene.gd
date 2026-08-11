extends Node2D

const GAME_HUD_SCENE := preload("res://ui/game_hud.tscn")
const MOBILE_CONTROLS_SCENE := preload("res://ui/mobile_controls.tscn")

var _player: Node2D = null

func _ready() -> void:
	var active_scene_path := scene_file_path
	GameState.handle_scene_entered(active_scene_path)
	MusicManager.play_for_scene(active_scene_path)

	_player = _ensure_player_instance()
	_apply_spawn_state(_player)
	_ensure_hud()
	_ensure_mobile_controls()
	NpcCollisionManager.ensure_scene_collisions(self)

	InputManager.unlock_input("door_transition")

func _ensure_player_instance() -> Node2D:
	var existing_player := get_tree().get_first_node_in_group("player_character") as Node2D
	if existing_player != null:
		return existing_player

	var player_scene_path := GameState.get_player_scene_path()
	if not ResourceLoader.exists(player_scene_path):
		push_error("Missing player scene: %s" % player_scene_path)
		return null

	var player_scene := load(player_scene_path) as PackedScene
	if player_scene == null:
		push_error("Unable to load player scene: %s" % player_scene_path)
		return null

	var player_instance := player_scene.instantiate() as Node2D
	if player_instance == null:
		push_error("Unable to instantiate player scene: %s" % player_scene_path)
		return null

	add_child(player_instance)
	return player_instance

func _apply_spawn_state(player: Node2D) -> void:
	if player == null:
		return

	var pending_spawn := GameState.consume_pending_scene_spawn(scene_file_path)
	var spawn_position := GameState.get_scene_fallback_spawn(scene_file_path)
	var marker_name := String(pending_spawn.get("marker_name", "")).strip_edges()
	var facing_direction := String(pending_spawn.get("facing_direction", "")).strip_edges()
	var found_marker := false

	if not marker_name.is_empty():
		var marker := find_child(marker_name, true, false) as Node2D
		if marker != null:
			spawn_position = marker.global_position
			found_marker = true

	if pending_spawn.has("position") and not found_marker:
		var queued_position := pending_spawn.get("position", Vector2.ZERO) as Vector2
		if queued_position != Vector2.ZERO or marker_name.is_empty():
			spawn_position = queued_position

	if pending_spawn.is_empty():
		var default_spawn := find_child("PlayerSpawn", true, false) as Node2D
		if default_spawn != null:
			spawn_position = default_spawn.global_position

	player.global_position = spawn_position
	if player.has_method("set_facing_direction") and not facing_direction.is_empty():
		player.call("set_facing_direction", facing_direction)

	GameState.capture_runtime(scene_file_path, player.global_position)

func _ensure_hud() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	if current_scene.get_node_or_null("GameHUD") != null:
		return
	if current_scene.get_node_or_null("SceneHUDHost") != null:
		return

	var hud := GAME_HUD_SCENE.instantiate() as CanvasLayer
	if hud == null:
		push_error("Unable to instantiate game HUD.")
		return

	hud.name = "GameHUD"
	current_scene.add_child.call_deferred(hud)

func _ensure_mobile_controls() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	if current_scene.get_node_or_null("MobileControls") != null:
		return

	var mobile_controls := MOBILE_CONTROLS_SCENE.instantiate() as CanvasLayer
	if mobile_controls == null:
		push_error("Unable to instantiate mobile controls.")
		return

	mobile_controls.name = "MobileControls"
	current_scene.add_child.call_deferred(mobile_controls)
