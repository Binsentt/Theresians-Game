extends Node

signal lives_changed(current_lives: int, max_lives: int)
signal quest_changed(current_quest: String)
signal save_created(save_data: Dictionary)
signal game_over
signal battle_started(enemy: Node)
signal battle_enemy_changed(enemy: Node)
signal battle_ended
signal mode_changed(previous_mode: GameMode, current_mode: GameMode)
signal task_state_changed(previous_index: int, current_index: int, event: Dictionary)
signal progression_session_reset(source: String)

enum GameMode { EXPLORATION, DIALOGUE, CUTSCENE, BATTLE, MENU }

const SAVE_VERSION := 6
const START_SCENE_PATH := "res://interiors/player_house.tscn"
const DEFAULT_QUEST := "No active quest"
const SAVE_DIRECTORY := "user://saves"
const VALID_REGISTRATION_GRADES := ["Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"]

const PLAYER_SCENES := {
	"male": "res://player/player_male.tscn",
	"female": "res://player/player_female.tscn"
}

const LARGE_HEART_SCENES := {
	"res://scenes/oak_leaf_village.tscn": true,
	"res://scenes/city_of_knowledge.tscn": true,
	"res://scenes/2nd Village/Pinehill Village.tscn": true
}

const LEGACY_SCENE_ALIASES := {
	"res://interiors/players_house.tscn": "res://interiors/player_house.tscn",
	"res://world/player_house_outside_door.tscn": "res://scenes/oak_leaf_village.tscn",
	"res://world/teacher_house_outside_door.tscn": "res://scenes/oak_leaf_village.tscn",
	"res://world/npc_house_outside_door.tscn": "res://scenes/oak_leaf_village.tscn"
}

const SCENE_FALLBACK_SPAWNS := {
	"res://interiors/player_house.tscn": Vector2(297, 45),
	"res://scenes/oak_leaf_village.tscn": Vector2(682, 286),
	"res://scenes/city_of_knowledge.tscn": Vector2(608, 272),
	"res://scenes/2nd Village/Pinehill Village.tscn": Vector2(176, 368)
}

var player_name := ""
var gender := "male"
var grade_level := ""
var student_id := ""
var parent_id := ""
var _new_game_registration: Dictionary = {}

var current_quest := DEFAULT_QUEST
var current_lives := 3
var max_lives := 3

var current_scene_path := START_SCENE_PATH
var player_position := Vector2.ZERO
var battle_active: bool = false
var current_battle_enemy_path: NodePath = NodePath()

var city_of_knowledge_unlocked := false

var _pending_scene_spawn: Dictionary = {}
var _return_context: Dictionary = {}
var _resume_on_next_scene_load := false
var _resume_scene_path: String = ""
var _resume_player_position: Vector2 = Vector2.ZERO
var _resume_facing_direction: String = ""
var _current_battle_enemy: Node = null

var score: int = 0
var player_won: bool = false
var enemy_hp: int = 100

var _mode_stack: Array[GameMode] = [GameMode.MENU]

var current_task_index: int = 0
var tasks = [
	{
		"quest_text": "Go to the Teacher’s house",
		"dialogue": ["Get inside the house", "The teacher is waiting."]
	},
	{
		"quest_text": "Talk to the Teacher",
		"dialogue": ["You are ready. Travel through the forest and reach the City of Knowledge.", "Reward: Forest Path unlocked"]
	},
	{
		"quest_text": "Challenge the player with math questions ",
		"dialogue": ["You want to pass? Solve this first!"],
		"next_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn",
		"complete_after_battle": true
	}
]


func get_mode() -> GameMode:
	return _mode_stack.back()


func set_mode(mode: GameMode) -> void:
	var previous_mode := get_mode()
	_mode_stack = [mode]
	if previous_mode != mode:
		mode_changed.emit(previous_mode, mode)


func push_mode(mode: GameMode) -> GameMode:
	var previous_mode := get_mode()
	if previous_mode != mode:
		_mode_stack.append(mode)
		mode_changed.emit(previous_mode, mode)
	return get_mode()


func pop_mode() -> GameMode:
	var previous_mode := get_mode()
	if _mode_stack.size() > 1:
		_mode_stack.pop_back()
		mode_changed.emit(previous_mode, get_mode())
	return get_mode()


func reset():
	score = 0
	player_won = false
	enemy_hp = 100


func complete_task() -> void:
	if current_task_index < tasks.size():
		current_task_index += 1


func _notify_progress(event: Dictionary) -> void:
	var notification_manager := get_node_or_null("/root/QuestNotificationManager")
	if notification_manager == null:
		return
	if not notification_manager.has_method("show_quest_updated"):
		return
	var event_type := String(event.get("type", ""))
	var title := String(event.get("title", "Quest Update"))
	var description := String(event.get("description", ""))
	if event_type == "quest_completed":
		notification_manager.call("show_quest_completed", title, description)
	elif event_type == "task_completed":
		notification_manager.call("show_task_completed", title, description)
	else:
		notification_manager.call("show_quest_updated", title, description)


func advance_task_and_save(event: Dictionary) -> Dictionary:
	if current_task_index >= tasks.size():
		return {"advanced": false, "save_path": ""}

	var previous_index := current_task_index
	current_task_index += 1
	var save_path := save_game()
	task_state_changed.emit(previous_index, current_task_index, event)
	_notify_progress(event)
	return {
		"advanced": true,
		"save_path": save_path,
		"previous_index": previous_index,
		"current_index": current_task_index
	}


func is_valid_six_digit_id(value: String) -> bool:
	if value.length() != 6:
		return false
	for character in value:
		var codepoint := character.unicode_at(0)
		if codepoint < 48 or codepoint > 57:
			return false
	return true


func sanitize_six_digit_id(value: String) -> String:
	var digits := ""
	for character in value:
		var codepoint := character.unicode_at(0)
		if codepoint >= 48 and codepoint <= 57:
			digits += character
			if digits.length() == 6:
				break
	return digits


func begin_new_game_registration() -> void:
	_new_game_registration = {
		"gender": "",
		"student_id": "",
		"parent_id": "",
		"student_name": "",
		"grade": ""
	}


func get_new_game_registration() -> Dictionary:
	return _new_game_registration.duplicate(true)


func update_new_game_registration(values: Dictionary) -> void:
	for key in ["gender", "student_id", "parent_id", "student_name", "grade"]:
		if values.has(key):
			_new_game_registration[key] = values[key]


func clear_new_game_registration() -> void:
	_new_game_registration.clear()


func is_valid_new_game_registration(values: Dictionary) -> bool:
	var gender_value := String(values.get("gender", "")).to_lower()
	var grade_value := String(values.get("grade", ""))
	return (
		gender_value in ["male", "female"]
		and is_valid_six_digit_id(String(values.get("student_id", "")))
		and is_valid_six_digit_id(String(values.get("parent_id", "")))
		and not String(values.get("student_name", "")).strip_edges().is_empty()
		and grade_value in VALID_REGISTRATION_GRADES
	)


func start_new_game(profile: Dictionary) -> void:
	player_name = String(profile.get("player_name", "")).strip_edges()
	gender = String(profile.get("gender", "male")).to_lower()
	grade_level = String(profile.get("grade_level", "")).strip_edges()
	student_id = String(profile.get("student_id", ""))
	parent_id = String(profile.get("parent_id", ""))

	current_quest = DEFAULT_QUEST
	current_lives = max_lives
	current_scene_path = START_SCENE_PATH
	player_position = get_scene_fallback_spawn(START_SCENE_PATH)
	city_of_knowledge_unlocked = false
	current_task_index = 0
	_pending_scene_spawn.clear()
	_return_context.clear()
	_clear_battle_state()
	_clear_resume_state()
	set_mode(GameMode.EXPLORATION)

	lives_changed.emit(current_lives, max_lives)
	quest_changed.emit(current_quest)
	progression_session_reset.emit("new_game")


func finalize_new_game_registration() -> bool:
	var values := get_new_game_registration()
	if not is_valid_new_game_registration(values):
		return false

	start_new_game({
		"player_name": String(values.get("student_name", "")).strip_edges(),
		"gender": String(values.get("gender", "")).to_lower(),
		"student_id": String(values.get("student_id", "")),
		"parent_id": String(values.get("parent_id", "")),
		"grade_level": String(values.get("grade", ""))
	})
	clear_new_game_registration()
	return true


func handle_scene_entered(scene_path: String) -> void:
	current_scene_path = _normalize_scene_path(scene_path)

func get_player_scene_path() -> String:
	return PLAYER_SCENES.get(gender, PLAYER_SCENES["male"])

func capture_runtime(scene_path: String, position: Vector2) -> void:
	current_scene_path = _normalize_scene_path(scene_path)
	player_position = position


func begin_battle(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	battle_active = true
	_current_battle_enemy = enemy
	current_battle_enemy_path = enemy.get_path()
	if get_mode() != GameMode.BATTLE:
		push_mode(GameMode.BATTLE)
	battle_started.emit(enemy)
	battle_enemy_changed.emit(enemy)


func end_battle() -> void:
	if not battle_active and current_battle_enemy_path.is_empty():
		_clear_battle_state()
		if get_mode() == GameMode.BATTLE:
			pop_mode()
		return

	_clear_battle_state()
	if get_mode() == GameMode.BATTLE:
		pop_mode()
	battle_ended.emit()


func is_battle_active() -> bool:
	return battle_active and get_current_battle_enemy() != null


func get_current_battle_enemy() -> Node:
	if _current_battle_enemy != null and is_instance_valid(_current_battle_enemy):
		return _current_battle_enemy

	if current_battle_enemy_path.is_empty():
		return null

	var enemy: Node = get_node_or_null(current_battle_enemy_path)
	if enemy == null:
		_clear_battle_state()
		return null

	_current_battle_enemy = enemy
	return enemy


func save_game() -> String:
	_ensure_save_directory()

	var now: Dictionary = Time.get_datetime_dict_from_system()
	var save_path: String = "%s/save_%04d%02d%02d_%02d%02d%02d.json" % [
		SAVE_DIRECTORY,
		int(now.get("year", 0)),
		int(now.get("month", 0)),
		int(now.get("day", 0)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0))
	]
	var data := build_save_data()

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to create save file: %s" % save_path)
		return ""

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	data["save_path"] = save_path
	save_created.emit(data)
	return save_path


func build_save_data() -> Dictionary:
	var datetime := Time.get_datetime_dict_from_system()
	var timestamp := int(Time.get_unix_time_from_system())
	var save_date := "%04d-%02d-%02d" % [
		int(datetime.get("year", 0)),
		int(datetime.get("month", 0)),
		int(datetime.get("day", 0))
	]
	var save_time := "%02d:%02d:%02d" % [
		int(datetime.get("hour", 0)),
		int(datetime.get("minute", 0)),
		int(datetime.get("second", 0))
	]

	return {
		"save_version": SAVE_VERSION,
		"player_name": player_name,
		"gender": gender,
		"grade_level": grade_level,
		"student_id": student_id,
		"parent_id": parent_id,
		"current_quest": current_quest,
		"scene_path": current_scene_path,
		"player_position": {
			"x": player_position.x,
			"y": player_position.y
		},
		"current_lives": current_lives,
		"max_lives": max_lives,
		"city_of_knowledge_unlocked": city_of_knowledge_unlocked,
		"current_task_index": current_task_index,
		"save_date": save_date,
		"save_time": save_time,
		"save_timestamp": timestamp
	}

func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var directory := DirAccess.open(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	if directory == null:
		return saves

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var save_path := SAVE_DIRECTORY + "/" + file_name
			var save_data := _read_save_file(save_path)
			if not save_data.is_empty():
				save_data["save_path"] = save_path
				saves.append(save_data)
		file_name = directory.get_next()

	directory.list_dir_end()
	saves.sort_custom(Callable(self, "_sort_saves_desc"))
	return saves


func load_save(path: String) -> Dictionary:
	var data := _read_save_file(path)
	if data.is_empty():
		return {}

	apply_save_data(data)
	data["scene_path"] = current_scene_path
	return data


func apply_save_data(data: Dictionary) -> void:
	_clear_battle_state()
	player_name = String(data.get("player_name", ""))
	gender = String(data.get("gender", "male")).to_lower()
	grade_level = String(data.get("grade_level", ""))
	student_id = String(data.get("student_id", ""))
	parent_id = String(data.get("parent_id", ""))

	current_quest = String(data.get("current_quest", DEFAULT_QUEST))
	current_scene_path = _normalize_scene_path(String(data.get("scene_path", START_SCENE_PATH)))

	var pos = data.get("player_position", {})
	player_position = Vector2(
		float(pos.get("x", 0)),
		float(pos.get("y", 0))
	)

	current_lives = int(data.get("current_lives", 3))
	max_lives = maxi(1, int(data.get("max_lives", 3)))
	current_lives = clampi(current_lives, 0, max_lives)
	city_of_knowledge_unlocked = bool(data.get("city_of_knowledge_unlocked", false))
	current_task_index = clampi(int(data.get("current_task_index", 0)), 0, tasks.size())
	set_mode(GameMode.EXPLORATION)
	queue_scene_spawn(current_scene_path, player_position)

	lives_changed.emit(current_lives, max_lives)
	quest_changed.emit(current_quest)
	progression_session_reset.emit("load")

# ================================
# HELPERS
# ================================
func should_use_large_player_hearts(scene_path: String, in_battle: bool = false) -> bool:
	if in_battle:
		return false

	scene_path = _normalize_scene_path(scene_path)
	if scene_path.begins_with("res://interiors/"):
		return true

	return LARGE_HEART_SCENES.has(scene_path)


func get_scene_fallback_spawn(scene_path: String) -> Vector2:
	scene_path = _normalize_scene_path(scene_path)
	return SCENE_FALLBACK_SPAWNS.get(scene_path, Vector2.ZERO)

func has_latest_save() -> bool:
	return not get_latest_save_path().is_empty()

func get_latest_save_path() -> String:
	var directory := DirAccess.open(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	if directory == null:
		return ""

	var latest_save_path := ""
	var latest_modified_time := -1
	directory.list_dir_begin()

	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var candidate_path := SAVE_DIRECTORY + "/" + file_name
			var modified_time := FileAccess.get_modified_time(ProjectSettings.globalize_path(candidate_path))
			if modified_time > latest_modified_time or (modified_time == latest_modified_time and candidate_path > latest_save_path):
				latest_modified_time = modified_time
				latest_save_path = candidate_path
		file_name = directory.get_next()

	directory.list_dir_end()
	return latest_save_path

func load_latest_save() -> Dictionary:
	var latest_save_path := get_latest_save_path()
	if latest_save_path.is_empty():
		return {}

	var data := load_save(latest_save_path)
	if data.is_empty():
		return {}

	var scene_path := _normalize_scene_path(String(data.get("scene_path", START_SCENE_PATH)))
	if not ResourceLoader.exists(scene_path):
		scene_path = START_SCENE_PATH

	queue_scene_spawn(
		scene_path,
		player_position,
		"",
		""
	)
	current_scene_path = scene_path
	return data

func queue_scene_spawn(scene_path: String, position: Vector2, facing_direction: String = "", marker_name: String = "") -> void:
	var normalized_scene_path := _normalize_scene_path(scene_path)
	var normalized_facing_direction := facing_direction.to_lower().strip_edges()
	_pending_scene_spawn = {
		"scene_path": normalized_scene_path,
		"position": position,
		"facing_direction": normalized_facing_direction,
		"marker_name": marker_name.strip_edges()
	}
	_resume_scene_path = normalized_scene_path
	_resume_player_position = position
	_resume_facing_direction = normalized_facing_direction
	_resume_on_next_scene_load = true
	current_scene_path = normalized_scene_path
	player_position = position

func consume_pending_scene_spawn(scene_path: String) -> Dictionary:
	var normalized_scene_path := _normalize_scene_path(scene_path)
	if _pending_scene_spawn.is_empty():
		return {}

	var pending_scene_path := _normalize_scene_path(String(_pending_scene_spawn.get("scene_path", "")))
	if pending_scene_path != normalized_scene_path:
		return {}

	var pending_spawn: Dictionary = _pending_scene_spawn.duplicate(true)
	_pending_scene_spawn.clear()
	return pending_spawn


func consume_spawn_position(scene_path: String, default_position: Vector2) -> Vector2:
	if _resume_on_next_scene_load and _resume_scene_path == _normalize_scene_path(scene_path):
		return _resume_player_position

	return default_position


func consume_spawn_facing_direction(scene_path: String, default_direction: String = "") -> String:
	if _resume_on_next_scene_load and _resume_scene_path == _normalize_scene_path(scene_path):
		var facing_direction: String = _resume_facing_direction if not _resume_facing_direction.is_empty() else default_direction
		_clear_resume_state()
		return facing_direction

	return default_direction

func set_return_context(scene_path: String, position: Vector2, facing_direction: String = "") -> void:
	_return_context = {
		"scene_path": _normalize_scene_path(scene_path),
		"position": position,
		"facing_direction": facing_direction.to_lower().strip_edges()
	}

func has_return_context() -> bool:
	return not _return_context.is_empty()

func get_return_scene_path() -> String:
	return String(_return_context.get("scene_path", ""))

func get_return_spawn_position() -> Vector2:
	return _return_context.get("position", Vector2.ZERO)

func get_return_facing_direction() -> String:
	return String(_return_context.get("facing_direction", ""))

func reset_lives() -> void:
	current_lives = max_lives
	lives_changed.emit(current_lives, max_lives)

func _normalize_scene_path(scene_path: String) -> String:
	return String(LEGACY_SCENE_ALIASES.get(scene_path, scene_path))


func _ensure_save_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))

func lose_life(amount: int = 1) -> void:
	current_lives = max(0, current_lives - amount)
	lives_changed.emit(current_lives, max_lives)

	if current_lives <= 0:
		game_over.emit()


func _read_save_file(save_path: String) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if parsed is Dictionary:
		return parsed

	return {}


func _dictionary_to_vector2(value: Variant) -> Vector2:
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))

	return Vector2.ZERO


func _clear_resume_state() -> void:
	_resume_on_next_scene_load = false
	_resume_scene_path = ""
	_resume_player_position = Vector2.ZERO
	_resume_facing_direction = ""


func _clear_battle_state() -> void:
	battle_active = false
	current_battle_enemy_path = NodePath()
	_current_battle_enemy = null


func _sort_saves_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("save_timestamp", 0)) > int(b.get("save_timestamp", 0))
