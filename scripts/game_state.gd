extends Node

signal lives_changed(current_lives: int, max_lives: int)
signal quest_changed(current_quest: String)
signal save_created(save_data: Dictionary)
signal game_over
signal battle_started(enemy: Node)
signal battle_enemy_changed(enemy: Node)
signal battle_ended
signal encounter_lifecycle_changed(context: Dictionary)
signal encounter_game_over(context: Dictionary)
signal mode_changed(previous_mode: GameMode, current_mode: GameMode)
signal task_state_changed(previous_index: int, current_index: int, event: Dictionary)
signal progression_session_reset(source: String)
signal time_limit_reached
signal playtime_warning(remaining_minutes: int)

enum GameMode { EXPLORATION, DIALOGUE, CUTSCENE, BATTLE, MENU }

const SAVE_VERSION := 8
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
var learning_cycle_version: int = 0
var learning_cycle_started_at: String = ""
var _new_game_registration: Dictionary = {}

var current_quest := DEFAULT_QUEST
var current_lives := 3
var max_lives := 3

var current_scene_path := START_SCENE_PATH
var current_map := ""
var player_position := Vector2.ZERO
var battle_active: bool = false
var current_battle_enemy_path: NodePath = NodePath()
var encounter_context: Dictionary = {}

var city_of_knowledge_unlocked := false
var score: int = 0
var correct_answers: int = 0
var incorrect_answers: int = 0
var total_questions: int = 0
var progress_percentage: int = 0
var lesson_progress: int = 0
var total_quests_completed: int = 0
var total_play_time: int = 0
var difficulty_level: String = "Unknown"

var current_task_index: int = 0
var tasks = [
	{
		"quest_text": "Go to the Teacher's House",
		"dialogue": ["Get inside the house", "The teacher is waiting."]
	},
	{
		"quest_text": "Talk to the Teacher",
		"dialogue": ["You are ready. Travel through the forest and reach the City of Knowledge.", "Reward: Forest Path unlocked"]
	},
	{
		"quest_text": "Challenge the player with math questions ",
		"dialogue": ["You want to pass? Solve this first!"],
		"question_scope": {
			"topic": "Basic Addition",
		},
		"next_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn",
		"complete_after_battle": true
	}
]

const DEFAULT_PLAYTIME_LIMIT_MINUTES := 60
const MAX_ENCOUNTER_LOSSES := 3
const PLAYTIME_WARNING_MINUTES := [30, 20, 15, 5, 1]
var playtime_limit_minutes: int = DEFAULT_PLAYTIME_LIMIT_MINUTES
var playtime_remaining_minutes: int = DEFAULT_PLAYTIME_LIMIT_MINUTES
var playtime_remaining_seconds: float = DEFAULT_PLAYTIME_LIMIT_MINUTES * 60.0
var playtime_authorized: bool = true
var playtime_countdown_active: bool = false
var _playtime_limit_triggered: bool = false
var _playtime_warning_notified: Dictionary = {}

var _pending_scene_spawn: Dictionary = {}
var _return_context: Dictionary = {}
var _resume_on_next_scene_load := false
var _resume_scene_path: String = ""
var _resume_player_position: Vector2 = Vector2.ZERO
var _resume_facing_direction: String = ""
var _current_battle_enemy: Node = null

var player_won: bool = false
var enemy_hp: int = 100

var _mode_stack: Array[GameMode] = [GameMode.MENU]


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
	var event_key := String(event.get("key", ""))
	if event_type == "task_trigger":
		notification_manager.call(
			"show_task_trigger",
			title,
			description,
			event_key,
			String(event.get("portrait_path", ""))
		)
	elif event_type == "quest_completed":
		notification_manager.call("show_quest_completed", title, description, event_key)
	elif event_type == "task_completed":
		notification_manager.call("show_task_completed", title, description, event_key)
	else:
		notification_manager.call("show_quest_updated", title, description, event_key)


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
		"grade": "",
		"section": "",
		"learning_cycle": {}
	}


func get_new_game_registration() -> Dictionary:
	return _new_game_registration.duplicate(true)


func update_new_game_registration(values: Dictionary) -> void:
	for key in ["gender", "student_id", "parent_id", "student_name", "grade", "section", "learning_cycle"]:
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


func start_new_game(profile: Dictionary, emit_progression_session_reset: bool = true) -> void:
	player_name = String(profile.get("player_name", "")).strip_edges()
	gender = String(profile.get("gender", "male")).to_lower()
	grade_level = String(profile.get("grade_level", "")).strip_edges()
	student_id = String(profile.get("student_id", ""))
	parent_id = String(profile.get("parent_id", ""))
	set_learning_cycle(profile.get("learning_cycle", {}))

	current_quest = DEFAULT_QUEST
	current_lives = max_lives
	current_scene_path = START_SCENE_PATH
	player_position = get_scene_fallback_spawn(START_SCENE_PATH)
	city_of_knowledge_unlocked = false
	current_task_index = 0
	_pending_scene_spawn.clear()
	_return_context.clear()
	encounter_context.clear()
	_clear_battle_state()
	_clear_resume_state()
	set_mode(GameMode.EXPLORATION)

	lives_changed.emit(current_lives, max_lives)
	quest_changed.emit(current_quest)
	if emit_progression_session_reset:
		progression_session_reset.emit("new_game")


func set_learning_cycle(descriptor: Variant) -> bool:
	if not (descriptor is Dictionary):
		return false
	var raw_version: Variant = descriptor.get("version", 0)
	var normalized_version: Variant = _normalize_learning_cycle_version(raw_version)
	if normalized_version == null:
		return false
	learning_cycle_version = int(normalized_version)
	var raw_started_at: Variant = descriptor.get("started_at", "")
	learning_cycle_started_at = raw_started_at.strip_edges() if raw_started_at is String else ""
	return true


func _normalize_learning_cycle_version(raw_version: Variant) -> Variant:
	if raw_version is int:
		if raw_version < 0:
			return null
		return raw_version
	if raw_version is float:
		if raw_version < 0.0 or not is_equal_approx(raw_version, round(raw_version)):
			return null
		return int(raw_version)
	if raw_version is String:
		var version_text: String = String(raw_version).strip_edges()
		if version_text.is_empty() or not version_text.is_valid_int():
			return null
		var parsed_version: int = version_text.to_int()
		if parsed_version < 0:
			return null
		return parsed_version
	return null


func get_learning_cycle_descriptor() -> Dictionary:
	return {
		"version": learning_cycle_version,
		"started_at": learning_cycle_started_at,
	}


func configure_playtime_allowance(response_body: Dictionary, reset_warning_state: bool = false) -> void:
	if response_body.is_empty():
		playtime_authorized = false
		playtime_countdown_active = false
		playtime_remaining_minutes = 0
		playtime_remaining_seconds = 0.0
		playtime_limit_minutes = DEFAULT_PLAYTIME_LIMIT_MINUTES
		_playtime_limit_triggered = false
		_playtime_warning_notified.clear()
		return

	var daily_limit := int(response_body.get("daily_limit_minutes", DEFAULT_PLAYTIME_LIMIT_MINUTES))
	if daily_limit <= 0:
		daily_limit = DEFAULT_PLAYTIME_LIMIT_MINUTES

	var remaining_minutes := int(response_body.get("remaining_minutes", daily_limit))
	var response_remaining_seconds := float(response_body.get("remaining_seconds", remaining_minutes * 60))
	var api_authorized := bool(response_body.get("can_play", true))
	if response_body.has("should_block"):
		api_authorized = api_authorized and not bool(response_body.get("should_block", false))

	var previous_remaining_seconds := playtime_remaining_seconds
	if reset_warning_state:
		_playtime_warning_notified.clear()
		_playtime_limit_triggered = false
		previous_remaining_seconds = response_remaining_seconds

	playtime_limit_minutes = max(0, daily_limit)
	playtime_remaining_seconds = maxf(0.0, response_remaining_seconds)
	playtime_remaining_minutes = int(ceil(playtime_remaining_seconds / 60.0))
	playtime_authorized = api_authorized
	playtime_countdown_active = api_authorized and playtime_limit_minutes > 0 and playtime_remaining_seconds > 0.0
	_emit_crossed_playtime_warnings(previous_remaining_seconds, playtime_remaining_seconds)

	if playtime_remaining_seconds <= 0.0:
		playtime_countdown_active = false
		playtime_authorized = false
		playtime_remaining_minutes = 0
		playtime_remaining_seconds = 0.0
		_emit_time_limit_reached_once()

func consume_playtime_clock(delta: float) -> void:
	if not playtime_countdown_active:
		return
	if delta <= 0.0:
		return
	if playtime_remaining_seconds <= 0.0:
		playtime_countdown_active = false
		playtime_authorized = false
		playtime_remaining_minutes = 0
		playtime_remaining_seconds = 0.0
		_emit_time_limit_reached_once()
		return

	var previous_remaining_seconds := playtime_remaining_seconds
	playtime_remaining_seconds = maxf(0.0, playtime_remaining_seconds - delta)
	_emit_crossed_playtime_warnings(previous_remaining_seconds, playtime_remaining_seconds)
	if playtime_remaining_seconds <= 0.0:
		playtime_remaining_seconds = 0.0
		playtime_remaining_minutes = 0
		playtime_authorized = false
		playtime_countdown_active = false
		_emit_time_limit_reached_once()
		return

	playtime_remaining_minutes = int(ceil(playtime_remaining_seconds / 60.0))

func get_playtime_remaining_seconds() -> float:
	return playtime_remaining_seconds


func _emit_crossed_playtime_warnings(previous_seconds: float, current_seconds: float) -> void:
	if previous_seconds <= 0.0 or current_seconds >= previous_seconds:
		return
	for warning_minutes in PLAYTIME_WARNING_MINUTES:
		var threshold_seconds := float(warning_minutes * 60)
		if previous_seconds > threshold_seconds and current_seconds <= threshold_seconds and not _playtime_warning_notified.has(warning_minutes):
			_playtime_warning_notified[warning_minutes] = true
			playtime_warning.emit(warning_minutes)


func _emit_time_limit_reached_once() -> void:
	if _playtime_limit_triggered:
		return
	_playtime_limit_triggered = true
	time_limit_reached.emit()

func has_existing_game_profile_for_student_id(student_id: String) -> bool:
	var normalized_id := String(student_id).strip_edges()
	if not is_valid_six_digit_id(normalized_id):
		return false

	var directory := DirAccess.open(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	if directory == null:
		return false

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var save_path := SAVE_DIRECTORY + "/" + file_name
			var save_data := _read_save_file(save_path)
			if not save_data.is_empty():
				var saved_student_id := String(save_data.get("student_id", ""))
				if saved_student_id == normalized_id:
					directory.list_dir_end()
					return true
		file_name = directory.get_next()
	directory.list_dir_end()
	return false

func finalize_new_game_registration() -> bool:
	var values := get_new_game_registration()
	if not is_valid_new_game_registration(values):
		return false
	if has_existing_game_profile_for_student_id(String(values.get("student_id", ""))):
		return false

	start_new_game({
		"player_name": String(values.get("student_name", "")).strip_edges(),
		"gender": String(values.get("gender", "")).to_lower(),
		"student_id": String(values.get("student_id", "")),
		"parent_id": String(values.get("parent_id", "")),
		"grade_level": String(values.get("grade", "")),
		"learning_cycle": values.get("learning_cycle", {})
	}, false)
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


func begin_encounter(options: Dictionary = {}) -> Dictionary:
	var encounter_id := String(options.get("encounter_id", "")).strip_edges()
	if encounter_id.is_empty():
		encounter_id = "encounter:%d" % current_task_index
	var preserved_retry_count := 0
	if String(encounter_context.get("encounter_id", "")) == encounter_id \
			and int(encounter_context.get("quest_checkpoint", -1)) == current_task_index:
		preserved_retry_count = maxi(0, int(encounter_context.get("retry_count", 0)))
	var source_scene_path := _normalize_scene_path(String(options.get("source_scene_path", current_scene_path)))
	var source_position := player_position
	var requested_position: Variant = options.get("source_position", source_position)
	if requested_position is Vector2:
		source_position = requested_position
	elif requested_position is Dictionary:
		source_position = _dictionary_to_vector2(requested_position)

	encounter_context = {
		"encounter_id": encounter_id,
		"source_scene_path": source_scene_path,
		"source_position": _vector2_to_dictionary(source_position),
		"quest_checkpoint": clampi(int(options.get("quest_checkpoint", current_task_index)), 0, tasks.size()),
		"retry_count": maxi(0, int(options.get("retry_count", preserved_retry_count))),
		"question_scope": _normalize_question_scope(options.get("question_scope", {}), source_scene_path),
	}
	battle_active = true
	if get_mode() != GameMode.BATTLE:
		push_mode(GameMode.BATTLE)
	encounter_lifecycle_changed.emit(encounter_context.duplicate(true))
	return encounter_context.duplicate(true)


func get_active_encounter_context() -> Dictionary:
	return encounter_context.duplicate(true)


func get_encounter_question_scope() -> Dictionary:
	if encounter_context.is_empty():
		return _normalize_question_scope({}, current_scene_path)
	return _normalize_question_scope(
		encounter_context.get("question_scope", {}),
		String(encounter_context.get("source_scene_path", current_scene_path))
	)


func record_encounter_loss() -> Dictionary:
	if encounter_context.is_empty():
		return {"retry_count": 0, "game_over": false, "action": "none"}

	var retry_count := int(encounter_context.get("retry_count", 0)) + 1
	encounter_context["retry_count"] = retry_count
	_clear_battle_state()
	if get_mode() == GameMode.BATTLE:
		pop_mode()

	if retry_count < MAX_ENCOUNTER_LOSSES:
		_restore_encounter_return_position()
		var retry_result := {
			"retry_count": retry_count,
			"game_over": false,
			"action": "retry",
			"context": encounter_context.duplicate(true),
		}
		encounter_lifecycle_changed.emit(encounter_context.duplicate(true))
		battle_ended.emit()
		return retry_result

	var game_over_context := encounter_context.duplicate(true)
	current_task_index = clampi(int(encounter_context.get("quest_checkpoint", current_task_index)), 0, tasks.size())
	encounter_context.clear()
	quest_changed.emit(current_quest)
	battle_ended.emit()
	encounter_game_over.emit(game_over_context)
	game_over.emit()
	return {
		"retry_count": retry_count,
		"game_over": true,
		"action": "game_over",
		"context": game_over_context,
	}


func record_encounter_victory() -> Dictionary:
	if encounter_context.is_empty():
		return {"success": true, "action": "none"}
	var completed_context := encounter_context.duplicate(true)
	encounter_context.clear()
	_clear_battle_state()
	if get_mode() == GameMode.BATTLE:
		pop_mode()
	battle_ended.emit()
	encounter_lifecycle_changed.emit({})
	return {"success": true, "action": "victory", "context": completed_context}


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
		"learning_cycle_version": learning_cycle_version,
		"learning_cycle_started_at": learning_cycle_started_at,
		"current_quest": current_quest,
		"scene_path": current_scene_path,
		"current_map": current_map,
		"player_position": {
			"x": player_position.x,
			"y": player_position.y
		},
		"current_lives": current_lives,
		"max_lives": max_lives,
		"encounter_context": encounter_context.duplicate(true),
		"city_of_knowledge_unlocked": city_of_knowledge_unlocked,
		"current_task_index": current_task_index,
		"score": score,
		"correct_answers": correct_answers,
		"incorrect_answers": incorrect_answers,
		"total_questions": total_questions,
		"progress_percentage": progress_percentage,
		"lesson_progress": lesson_progress,
		"total_quests_completed": total_quests_completed,
		"total_play_time": total_play_time,
		"difficulty_level": difficulty_level,
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
			if save_data.is_empty():
				saves.append(_build_unavailable_save_entry(save_path, "This save file is malformed or unavailable."))
			else:
				saves.append(_prepare_save_entry(save_data, save_path))
		file_name = directory.get_next()

	directory.list_dir_end()
	saves.sort_custom(Callable(self, "_sort_saves_desc"))
	return saves


func load_save(path: String, emit_progression_session_reset: bool = true) -> Dictionary:
	var data := peek_save_data(path)
	if data.is_empty() or not bool(data.get("loadable", false)):
		return {}

	apply_save_data(data, emit_progression_session_reset)
	data["scene_path"] = current_scene_path
	return data

func peek_save_data(path: String) -> Dictionary:
	var save_path := _validated_save_path(path)
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return {}
	var data := _read_save_file(save_path)
	if data.is_empty():
		return _build_unavailable_save_entry(save_path, "This save file is malformed or unavailable.")
	return _prepare_save_entry(data, save_path)


func delete_save(path: String) -> bool:
	var save_path := _validated_save_path(path)
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return false

	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path)) == OK


func apply_save_data(data: Dictionary, emit_progression_session_reset: bool = true) -> void:
	_clear_battle_state()
	player_name = String(data.get("player_name", ""))
	gender = String(data.get("gender", "male")).to_lower()
	grade_level = String(data.get("grade_level", ""))
	student_id = String(data.get("student_id", ""))
	parent_id = String(data.get("parent_id", ""))
	set_learning_cycle({
		"version": int(data.get("learning_cycle_version", 0)),
		"started_at": String(data.get("learning_cycle_started_at", "")),
	})

	current_quest = String(data.get("current_quest", DEFAULT_QUEST))
	current_scene_path = _normalize_scene_path(String(data.get("scene_path", START_SCENE_PATH)))
	current_map = String(data.get("current_map", ""))
	if current_map.strip_edges().is_empty():
		current_map = String(data.get("scene_path", ""))

	var pos = data.get("player_position", {})
	player_position = Vector2(
		float(pos.get("x", 0)),
		float(pos.get("y", 0))
	)

	current_lives = int(data.get("current_lives", 3))
	max_lives = maxi(1, int(data.get("max_lives", 3)))
	current_lives = clampi(current_lives, 0, max_lives)
	encounter_context = _normalize_encounter_context(data.get("encounter_context", {}))
	city_of_knowledge_unlocked = bool(data.get("city_of_knowledge_unlocked", false))
	current_task_index = clampi(int(data.get("current_task_index", 0)), 0, tasks.size())
	score = int(data.get("score", 0))
	correct_answers = int(data.get("correct_answers", 0))
	incorrect_answers = int(data.get("incorrect_answers", 0))
	total_questions = int(data.get("total_questions", 0))
	progress_percentage = int(data.get("progress_percentage", 0))
	lesson_progress = int(data.get("lesson_progress", 0))
	total_quests_completed = int(data.get("total_quests_completed", 0))
	total_play_time = int(data.get("total_play_time", 0))
	difficulty_level = String(data.get("difficulty_level", "Unknown"))
	set_mode(GameMode.EXPLORATION)
	queue_scene_spawn(current_scene_path, player_position)

	lives_changed.emit(current_lives, max_lives)
	quest_changed.emit(current_quest)
	if emit_progression_session_reset:
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


func _normalize_question_scope(scope: Variant, source_scene_path: String) -> Dictionary:
	var normalized: Dictionary = {}
	if scope is Dictionary:
		var grade := String(scope.get("grade", scope.get("grade_level", ""))).strip_edges()
		var difficulty := _normalize_difficulty(String(scope.get("difficulty", "")))
		var topic := String(scope.get("topic", scope.get("math_topic", ""))).strip_edges()
		if not grade.is_empty():
			normalized["grade"] = grade
		if not difficulty.is_empty():
			normalized["difficulty"] = difficulty
		if not topic.is_empty():
			normalized["topic"] = topic
	if not normalized.has("grade") and not grade_level.strip_edges().is_empty():
		normalized["grade"] = grade_level.strip_edges()
	if not normalized.has("difficulty"):
		normalized["difficulty"] = _difficulty_for_scene(source_scene_path)
	return normalized


func _normalize_difficulty(value: String) -> String:
	match value.strip_edges().to_lower():
		"easy":
			return "Easy"
		"medium", "normal":
			return "Medium"
		"hard", "difficult":
			return "Hard"
		_:
			return ""


func _difficulty_for_scene(scene_path: String) -> String:
	var normalized_scene_path := _normalize_scene_path(scene_path).to_lower()
	if normalized_scene_path.contains("city_of_knowledge"):
		return "Medium"
	if normalized_scene_path.contains("pinehill") or normalized_scene_path.contains("2nd village"):
		return "Hard"
	return "Easy"


func _restore_encounter_return_position() -> void:
	if encounter_context.is_empty():
		return
	var source_scene_path := _normalize_scene_path(String(encounter_context.get("source_scene_path", current_scene_path)))
	var source_position := _dictionary_to_vector2(encounter_context.get("source_position", {}))
	current_scene_path = source_scene_path
	player_position = source_position
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var current_scene := tree.current_scene
	if current_scene != null and _normalize_scene_path(current_scene.scene_file_path) == source_scene_path:
		var player := tree.get_first_node_in_group("player_character") as Node2D
		if player != null:
			player.global_position = source_position
		return
	queue_scene_spawn(source_scene_path, source_position)


func _normalize_encounter_context(value: Variant) -> Dictionary:
	if not (value is Dictionary) or value.is_empty():
		return {}
	var source_scene_path := _normalize_scene_path(String(value.get("source_scene_path", current_scene_path)))
	return {
		"encounter_id": String(value.get("encounter_id", "")).strip_edges(),
		"source_scene_path": source_scene_path,
		"source_position": _vector2_to_dictionary(_dictionary_to_vector2(value.get("source_position", {}))),
		"quest_checkpoint": clampi(int(value.get("quest_checkpoint", current_task_index)), 0, tasks.size()),
		"retry_count": maxi(0, int(value.get("retry_count", 0))),
		"question_scope": _normalize_question_scope(value.get("question_scope", {}), source_scene_path),
	}


func _vector2_to_dictionary(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _read_save_file(save_path: String) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()

	if parse_error == OK and json.data is Dictionary:
		return json.data

	return {}


func _prepare_save_entry(data: Dictionary, save_path: String) -> Dictionary:
	var prepared := data.duplicate(true)
	prepared["save_path"] = save_path
	prepared["player_name"] = String(prepared.get("player_name", "Unknown")).strip_edges()
	if String(prepared.get("player_name", "")).is_empty():
		prepared["player_name"] = "Unknown"
	prepared["gender"] = String(prepared.get("gender", "male")).to_lower()
	prepared["grade_level"] = String(prepared.get("grade_level", ""))
	prepared["current_quest"] = String(prepared.get("current_quest", DEFAULT_QUEST))
	prepared["save_date"] = String(prepared.get("save_date", "----/--/--"))
	prepared["save_time"] = String(prepared.get("save_time", "--:--:--"))
	prepared["save_timestamp"] = int(prepared.get("save_timestamp", 0))
	prepared["learning_cycle_version"] = maxi(0, int(prepared.get("learning_cycle_version", 0)))
	prepared["learning_cycle_started_at"] = String(prepared.get("learning_cycle_started_at", "")).strip_edges()
	var scene_path := _normalize_scene_path(String(prepared.get("scene_path", "")).strip_edges())
	if scene_path.is_empty():
		scene_path = START_SCENE_PATH
	prepared["scene_path"] = scene_path

	var load_error := _get_save_load_error(prepared)
	prepared["loadable"] = load_error.is_empty()
	prepared["save_valid"] = load_error.is_empty()
	prepared["save_error"] = load_error
	return prepared


func annotate_save_learning_cycle(data: Dictionary, descriptor: Dictionary) -> Dictionary:
	var prepared := _prepare_save_entry(data, String(data.get("save_path", "")))
	if not bool(prepared.get("loadable", false)):
		return prepared
	if not set_learning_cycle_descriptor_is_valid(descriptor):
		prepared["loadable"] = false
		prepared["save_valid"] = false
		prepared["save_error"] = "Unable to verify Learning Cycle. Connect to continue."
		return prepared
	var saved_version := maxi(0, int(prepared.get("learning_cycle_version", 0)))
	var current_version := maxi(0, int(descriptor.get("version", 0)))
	if saved_version != current_version:
		prepared["loadable"] = false
		prepared["save_valid"] = false
		prepared["save_error"] = "Previous Learning Cycle"
		return prepared
	prepared["loadable"] = true
	prepared["save_valid"] = true
	prepared["save_error"] = ""
	return prepared


func set_learning_cycle_descriptor_is_valid(descriptor: Variant) -> bool:
	if not (descriptor is Dictionary):
		return false
	var raw_version: Variant = descriptor.get("version", null)
	return _normalize_learning_cycle_version(raw_version) != null


func _build_unavailable_save_entry(save_path: String, message: String) -> Dictionary:
	return {
		"save_path": save_path,
		"player_name": "Unknown",
		"gender": "male",
		"grade_level": "",
		"current_quest": DEFAULT_QUEST,
		"save_date": "----/--/--",
		"save_time": "--:--:--",
		"save_timestamp": 0,
		"scene_path": "",
		"loadable": false,
		"save_valid": false,
		"save_error": message,
	}


func _get_save_load_error(data: Dictionary) -> String:
	if not is_valid_six_digit_id(String(data.get("student_id", "")).strip_edges()):
		return "This save is missing a valid Student ID and cannot be loaded."
	if not is_valid_six_digit_id(String(data.get("parent_id", "")).strip_edges()):
		return "This save is missing a valid Parent ID and cannot be loaded."
	var scene_path := String(data.get("scene_path", "")).strip_edges()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return "This save references an unavailable game scene and cannot be loaded."
	return ""


func _validated_save_path(path: String) -> String:
	var requested_path := path.strip_edges()
	var save_prefix := SAVE_DIRECTORY + "/"
	if not requested_path.begins_with(save_prefix):
		return ""

	var file_name := requested_path.get_file()
	var relative_path := requested_path.substr(save_prefix.length())
	if file_name.is_empty() or file_name != relative_path or not file_name.ends_with(".json"):
		return ""

	return save_prefix + file_name


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
