extends Node2D

const GAME_HUD_SCENE := preload("res://ui/game_hud.tscn")
const MOBILE_CONTROLS_SCENE := preload("res://ui/mobile_controls.tscn")
const OAKLEAF_BATTLE_ENCOUNTER := preload("res://scripts/oakleaf_battle_encounter.gd")
const TEACHER_TASK_INTERACTION := preload("res://scripts/teacher_task_interaction.gd")
const PROGRESSION_BATTLE_ENCOUNTER := preload("res://scripts/progression_battle_encounter.gd")
const PROGRESSION_OLD_MAN_INTERACTION := preload("res://scripts/progression_old_man_interaction.gd")
const CITY_OF_KNOWLEDGE_PATH := "res://scenes/city_of_knowledge.tscn"
const FOREST_BANDIT_COLLISION_LAYER := 2
const FOREST_BANDIT_COLLISION_MASK := 1
const FOREST_BANDIT_ACTORS := [
	{"node": "Bandits", "encounter_id": "deep_forest_bandits1"},
	{"node": "Bandits2", "encounter_id": "deep_forest_bandits2"},
	{"node": "Bandits3", "encounter_id": "deep_forest_bandits3"},
	{"node": "Bandits4", "encounter_id": "deep_forest_bandits4"},
	{"node": "Bandits5", "encounter_id": "deep_forest_bandits5"},
]
const NON_PHYSICAL_TRIGGER_COLLISIONS := {
	"res://scenes/oak_leaf_village.tscn": [
		"Bandits/BanditTaskTrigger/StaticBody2D/CollisionShape2D",
	],
}

var _player: Node2D = null
var _oakleaf_prefetch_queued := false

func _ready() -> void:
	var active_scene_path := scene_file_path
	if HttpApi.is_local_qa_mode():
		var actor_state: Array[String] = []
		for actor_name in ["Bandits", "Bandits2", "Bandits3", "Bandits4", "Bandits5"]:
			var actor := get_node_or_null(actor_name) as Node2D
			actor_state.append("%s:%s" % [actor_name, str(actor.is_visible_in_tree()) if actor != null else "missing"])
		print("F5_FLOW_TRACE gameplay_ready scene=%s node=%s current=%s task=%d quest=%s actors=%s" % [
			active_scene_path,
			get_path(),
			get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "none",
			GameState.current_task_index,
			GameState.current_quest,
			",".join(actor_state),
		])
	GameState.handle_scene_entered(active_scene_path)
	MusicManager.play_for_scene(active_scene_path)
	_disable_non_physical_trigger_collisions(active_scene_path)
	_sync_city_deep_forest_actors(active_scene_path)

	_player = _ensure_player_instance()
	_apply_spawn_state(_player)
	_ensure_hud()
	_ensure_mobile_controls()
	NpcCollisionManager.ensure_scene_collisions(self)
	OAKLEAF_BATTLE_ENCOUNTER.install_for_scene(self, OAKLEAF_BATTLE_ENCOUNTER)
	if active_scene_path == "res://interiors/teacher_house.tscn" \
			or active_scene_path == "res://interiors/school.tscn":
		TEACHER_TASK_INTERACTION.install_for_scene(self, TEACHER_TASK_INTERACTION)
	PROGRESSION_BATTLE_ENCOUNTER.install_for_scene(self, PROGRESSION_BATTLE_ENCOUNTER)
	PROGRESSION_OLD_MAN_INTERACTION.install_for_scene(self, PROGRESSION_OLD_MAN_INTERACTION)
	var progression_task_callback := Callable(self, "_on_progression_task_state_changed")
	if not GameState.task_state_changed.is_connected(progression_task_callback):
		GameState.task_state_changed.connect(progression_task_callback)
	_connect_oakleaf_prefetch(active_scene_path)

	InputManager.unlock_input("door_transition")


func _on_progression_task_state_changed(_previous_index: int, _current_index: int, _event: Dictionary) -> void:
	# Progression encounters can become available while this map stays loaded
	# (Old Lady -> Guards -> Wizard). Refresh adapters at the canonical state
	# boundary instead of requiring a scene reload to make the next actor usable.
	_sync_city_deep_forest_actors(scene_file_path)
	PROGRESSION_BATTLE_ENCOUNTER.install_for_scene(self, PROGRESSION_BATTLE_ENCOUNTER)
	PROGRESSION_OLD_MAN_INTERACTION.install_for_scene(self, PROGRESSION_OLD_MAN_INTERACTION)


func _sync_city_deep_forest_actors(active_scene_path: String) -> void:
	# City and Deepest Forest are one continuous map. The teacher quest activates
	# the five authored encounters in the forest portion without a scene change.
	if active_scene_path != CITY_OF_KNOWLEDGE_PATH:
		return
	if HttpApi.is_local_qa_mode():
		print("F5_FLOW_TRACE city_bandits scene=%s node=%s task=%d quest_active=%s" % [active_scene_path, get_path(), GameState.current_task_index, str(GameState.current_task_index == GameState.DEEP_FOREST_BANDIT_TASK_INDEX)])
	for encounter in FOREST_BANDIT_ACTORS:
		var actor := get_node_or_null(String(encounter.get("node", ""))) as CollisionObject2D
		if actor == null:
			continue
		var can_start := GameState.has_method("can_start_progression_encounter") \
				and bool(GameState.call("can_start_progression_encounter", String(encounter.get("encounter_id", ""))))
		if not can_start:
			actor.visible = false
			actor.set_deferred("collision_layer", 0)
			actor.set_deferred("collision_mask", 0)
			continue
		actor.visible = true
		actor.set_deferred("collision_layer", FOREST_BANDIT_COLLISION_LAYER)
		actor.set_deferred("collision_mask", FOREST_BANDIT_COLLISION_MASK)


func _connect_oakleaf_prefetch(active_scene_path: String) -> void:
	if active_scene_path != OAKLEAF_BATTLE_ENCOUNTER.OAKLEAF_SCENE_PATH:
		return
	var lifecycle_callback := Callable(self, "_on_oakleaf_prefetch_state_changed")
	if not GameState.encounter_lifecycle_changed.is_connected(lifecycle_callback):
		GameState.encounter_lifecycle_changed.connect(lifecycle_callback)
	var task_callback := Callable(self, "_on_oakleaf_task_state_changed")
	if not GameState.task_state_changed.is_connected(task_callback):
		GameState.task_state_changed.connect(task_callback)
	_queue_oakleaf_prefetch()


func _on_oakleaf_prefetch_state_changed(_context: Dictionary) -> void:
	_queue_oakleaf_prefetch()


func _on_oakleaf_task_state_changed(_previous_index: int, _current_index: int, _event: Dictionary) -> void:
	_queue_oakleaf_prefetch()


func _queue_oakleaf_prefetch() -> void:
	if _oakleaf_prefetch_queued:
		return
	_oakleaf_prefetch_queued = true
	_prefetch_oakleaf_questions.call_deferred()


func _prefetch_oakleaf_questions() -> void:
	_oakleaf_prefetch_queued = false
	if not is_inside_tree() or scene_file_path != OAKLEAF_BATTLE_ENCOUNTER.OAKLEAF_SCENE_PATH:
		return
	if GameState.battle_active or GameState.get_mode() != GameState.GameMode.EXPLORATION \
			or not GameState.playtime_authorized:
		return
	var encounter_available := false
	for encounter_id in GameState.OAKLEAF_BANDIT_IDS + [GameState.OAKLEAF_BOSS_ID]:
		if GameState.can_start_oakleaf_encounter(encounter_id):
			encounter_available = true
			break
	if not encounter_available:
		return
	var provider := get_node_or_null("/root/QuestionProvider")
	if provider == null or not provider.has_method("prefetch_questions"):
		return
	provider.call("prefetch_questions", {
		"grade": GameState.grade_level,
		"difficulty": "Easy",
	})

func _disable_non_physical_trigger_collisions(active_scene_path: String) -> void:
	var collision_paths: Array = NON_PHYSICAL_TRIGGER_COLLISIONS.get(active_scene_path, [])
	for collision_path_value in collision_paths:
		var collision_path := String(collision_path_value)
		var collision_shape := get_node_or_null(collision_path) as CollisionShape2D
		if collision_shape == null:
			push_warning("Missing non-physical trigger collision: %s" % collision_path)
			continue
		collision_shape.set_deferred("disabled", true)

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
