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
signal canonical_activity_boundary(event: Dictionary)
signal progression_session_reset(source: String)
signal time_limit_reached
signal playtime_warning(remaining_minutes: int)

enum GameMode { EXPLORATION, DIALOGUE, CUTSCENE, BATTLE, MENU }

const SAVE_VERSION := 9
const TELEMETRY_CONTRACT_VERSION := "2.0"
const QUEST_GRAPH_VERSION := "oakleaf-city-pinehill-v1"
const START_SCENE_PATH := "res://interiors/player_house.tscn"
const DEFAULT_QUEST := "No active quest"
const TUTORIAL_QUEST := "Tutorial"
const SAVE_DIRECTORY := "user://saves"
const DEVICE_INSTALLATION_ID_PATH := "user://device_installation_id.txt"
const TERMS_VERSION := "1.0"
const TERMS_ACCEPTANCE_PATH := "user://terms_acceptance.json"
const VALID_REGISTRATION_GRADES := ["Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"]
const OAKLEAF_BANDIT_IDS: Array[String] = [
	"oakleaf_bandits1",
	"oakleaf_bandits2",
	"oakleaf_bandits3",
	"oakleaf_bandits4",
	"oakleaf_bandits5",
]
const OAKLEAF_BOSS_ID := "oakleaf_boss_bandit"
const OAKLEAF_BANDIT_TASK_INDEX := 3
const OAKLEAF_BOSS_TASK_INDEX := 4
const OAKLEAF_RETURN_TEACHER_TASK_INDEX := 5
const CITY_OF_KNOWLEDGE_TASK_INDEX := 6
const CITY_SCHOOL_TASK_INDEX := 7
const CITY_SCHOOL_TEACHER_TASK_INDEX := 8
const CITY_NEXT_PATH_TASK_INDEX := 9
const DEEP_FOREST_BANDIT_TASK_INDEX := 10
const PINEHILL_ARRIVAL_TASK_INDEX := 11
const PINEHILL_OLD_MAN_TASK_INDEX := 12
const PINEHILL_BANDIT_TASK_INDEX := 13
const WIZARD_TASK_INDEX := 14
const RETURN_CITY_TASK_INDEX := 15
const FINAL_SCHOOL_TASK_INDEX := 16
const FINAL_TEACHER_TASK_INDEX := 17

const DEEP_FOREST_BANDIT_IDS: Array[String] = [
	"deep_forest_bandits1",
	"deep_forest_bandits2",
	"deep_forest_bandits3",
	"deep_forest_bandits4",
	"deep_forest_bandits5",
]
const PINEHILL_BANDIT_IDS: Array[String] = [
	"pinehill_bandits1",
	"pinehill_bandits2",
	"pinehill_bandits3",
	"pinehill_bandits4",
]
const RETURN_PATH_BANDIT_IDS: Array[String] = []
const PROGRESSION_BANDIT_IDS: Array[String] = DEEP_FOREST_BANDIT_IDS + PINEHILL_BANDIT_IDS + RETURN_PATH_BANDIT_IDS

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
	"res://world/npc_house_outside_door.tscn": "res://scenes/oak_leaf_village.tscn",
	"res://scenes/pinehill_village.tscn": "res://scenes/2nd Village/Pinehill Village.tscn"
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
var device_installation_id := ""
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
var city_first_arrival_seen := false
var city_school_stage_complete := false
var city_next_path_unlocked := false
var city_school_stage: int = 0
var deep_forest_defeated_bandits: Dictionary = {}
var pinehill_unlocked := false
var pinehill_old_man_completed := false
var pinehill_defeated_bandits: Dictionary = {}
var wizard_defeated := false
var return_to_city_stage: int = 0
var return_path_defeated_bandits: Dictionary = {}
var final_teacher_defeated := false
var journey_complete := false
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
var oakleaf_defeated_bandits: Dictionary = {}
var oakleaf_boss_defeated: bool = false
var oakleaf_return_to_teacher: bool = false
var _tutorial_activity_started: bool = false
var _tutorial_activity_completed: bool = false
var _started_task_activity_ids: Dictionary = {}
var _activity_started_at: Dictionary = {}
var _completed_player_facing_tasks: Dictionary = {}
var tasks = [
	{
		"activity_id": "go-to-teachers-house",
		# The activity endpoint accepts a conservative task-id character set, so
		# retain the player-facing quest text below and use this safe audit label.
		"activity_label": "Go to Teacher House",
		"tutorial_activity": {
			"activity_id": "tutorial",
			"activity_label": "Tutorial",
		},
		"quest_text": "Go to the Teacher's House",
		"dialogue": ["Get inside the house", "The teacher is waiting."]
	},
	{
		"activity_id": "talk-to-the-teacher",
		"activity_label": "Talk to the Teacher",
		"quest_text": "Talk to the Teacher",
		"dialogue": ["You are ready. Travel through the forest and reach the City of Knowledge.", "Reward: Forest Path unlocked"]
	},
	{
		"activity_id": "first-bandit-math-challenge",
		"activity_label": "Challenge the Player with Math Questions",
		"quest_text": "Challenge the player with math questions ",
		"dialogue": ["You want to pass? Solve this first!"],
		"next_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn",
		"complete_after_battle": true,
		"question_scope": {
			"grade": "Grade 1",
			"difficulty": "Easy",
		}
	},
	{
		"activity_id": "oakleaf-bandits",
		"activity_label": "Defeat the Oakleaf Bandits",
		"quest_text": "Defeat All Bandits",
	},
	{
		"activity_id": "oakleaf-boss-bandit",
		"activity_label": "Defeat the Boss Bandit",
		"quest_text": "Defeat the Boss Bandit",
	},
	{
		"activity_id": "oakleaf-return-to-teacher",
		"activity_label": "Return to the Teacher",
		"quest_text": "Return to the Teacher",
		"dialogue": [
			"Teacher: You defeated the Oakleaf Bandits and their Boss.",
			"Teacher: The City of Knowledge and School are now open to you.",
		],
	},
	{
		"activity_id": "go-to-city-of-knowledge",
		"activity_label": "Go to the City of Knowledge",
		"quest_text": "Go to the City of Knowledge / School",
	},
	{
		"activity_id": "go-to-school",
		"activity_label": "Go to the School",
		"quest_text": "Go to the School",
		"dialogue": ["To continue, you must pass a greater challenge."],
	},
	{
		"activity_id": "talk-to-city-school-teacher",
		"activity_label": "Talk to the Math Teacher",
		"quest_text": "Talk to the Math Teacher",
		"dialogue": ["Teacher: To continue, you must pass a greater challenge."]
	},
	{
		"activity_id": "go-to-pinehill-village",
		"activity_label": "Go to Pinehill Village",
		"quest_text": "Go to Pinehill Village",
	},
	{
		"activity_id": "deep-forest-bandits",
		"activity_label": "Defeat the Deep Forest Bandits",
		"quest_text": "Defeat All Bandits",
	},
	{
		"activity_id": "pinehill-arrival",
		"activity_label": "Reach Pinehill Village",
		"quest_text": "Go to Pinehill Village",
	},
	{
		"activity_id": "talk-to-old-man",
		"activity_label": "Talk to the Old Man",
		"quest_text": "Talk to the Old Man",
		"dialogue": ["Old Man: A powerful Wizard is ahead.", "Old Man: The Bandits guard the way. Defeat them first."]
	},
	{
		"activity_id": "pinehill-bandits",
		"activity_label": "Defeat the Pinehill Bandits",
		"quest_text": "Defeat All Bandits",
	},
	{
		"activity_id": "defeat-the-wizard",
		"activity_label": "Defeat the Wizard",
		"quest_text": "Defeat the Wizard",
		"dialogue": ["Wizard: Your final challenge awaits in the City of Knowledge.", "Wizard: Return to the School and face the Teacher."]
	},
	{
		"activity_id": "return-to-city-of-knowledge",
		"activity_label": "Return to the City of Knowledge",
		"quest_text": "Return to the City of Knowledge",
	},
	{
		"activity_id": "return-to-city-school",
		"activity_label": "Go to the School",
		"quest_text": "Go to the School",
	},
	{
		"activity_id": "final-teacher",
		"activity_label": "Talk to the Master Teacher",
		"quest_text": "Talk to the Master Teacher",
		"dialogue": ["Teacher: Welcome back. This is your final Math challenge."]
	},
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


func _reset_oakleaf_progression() -> void:
	oakleaf_defeated_bandits.clear()
	for encounter_id in OAKLEAF_BANDIT_IDS:
		oakleaf_defeated_bandits[encounter_id] = false
	oakleaf_boss_defeated = false
	oakleaf_return_to_teacher = false


func _reset_world_progression() -> void:
	city_school_stage = 0
	deep_forest_defeated_bandits.clear()
	for encounter_id in DEEP_FOREST_BANDIT_IDS:
		deep_forest_defeated_bandits[encounter_id] = false
	pinehill_unlocked = false
	pinehill_old_man_completed = false
	pinehill_defeated_bandits.clear()
	for encounter_id in PINEHILL_BANDIT_IDS:
		pinehill_defeated_bandits[encounter_id] = false
	wizard_defeated = false
	return_to_city_stage = 0
	return_path_defeated_bandits.clear()
	for encounter_id in RETURN_PATH_BANDIT_IDS:
		return_path_defeated_bandits[encounter_id] = false
	final_teacher_defeated = false
	journey_complete = false


func is_oakleaf_bandit_defeated(encounter_id: String) -> bool:
	return bool(oakleaf_defeated_bandits.get(encounter_id.strip_edges(), false))


func is_oakleaf_encounter_defeated(encounter_id: String) -> bool:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id == OAKLEAF_BOSS_ID:
		return oakleaf_boss_defeated
	return is_oakleaf_bandit_defeated(normalized_id)


func get_oakleaf_defeated_bandit_count() -> int:
	var defeated_count := 0
	for encounter_id in OAKLEAF_BANDIT_IDS:
		if is_oakleaf_bandit_defeated(encounter_id):
			defeated_count += 1
	return defeated_count


func are_all_oakleaf_bandits_defeated() -> bool:
	return get_oakleaf_defeated_bandit_count() == OAKLEAF_BANDIT_IDS.size()


func can_start_oakleaf_encounter(encounter_id: String) -> bool:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id in OAKLEAF_BANDIT_IDS:
		if is_oakleaf_bandit_defeated(normalized_id):
			return false
		if normalized_id == OAKLEAF_BANDIT_IDS[0]:
			return current_task_index == 2
		return current_task_index == OAKLEAF_BANDIT_TASK_INDEX
	if normalized_id == OAKLEAF_BOSS_ID:
		return current_task_index == OAKLEAF_BOSS_TASK_INDEX \
				and are_all_oakleaf_bandits_defeated() \
				and not oakleaf_boss_defeated
	return false


func record_oakleaf_encounter_victory(encounter_id: String) -> Dictionary:
	return _record_oakleaf_encounter_victory(encounter_id, true)


func _record_oakleaf_encounter_victory(encounter_id: String, persist: bool) -> Dictionary:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id in OAKLEAF_BANDIT_IDS:
		if not can_start_oakleaf_encounter(normalized_id):
			return {"changed": false, "action": "blocked", "encounter_id": normalized_id}
		oakleaf_defeated_bandits[normalized_id] = true
		var previous_index := current_task_index
		var bandit_number := OAKLEAF_BANDIT_IDS.find(normalized_id) + 1
		var bandit_event := build_canonical_activity_event({
			"type": "task_completed",
			"key": "quest:oakleaf:bandit:%d:complete" % bandit_number,
			"title": "Oakleaf Bandit Defeated",
			"description": "Defeat the remaining Oakleaf Bandits.",
			"canonical_task_id": "oakleaf-bandits",
			"canonical_milestone_id": "oakleaf.bandits.bandit_%d" % bandit_number,
			"is_player_facing": false,
		}, OAKLEAF_BANDIT_TASK_INDEX, "task_completed")
		canonical_activity_boundary.emit(bandit_event)
		if normalized_id != OAKLEAF_BANDIT_IDS[0] and are_all_oakleaf_bandits_defeated():
			current_task_index = OAKLEAF_BOSS_TASK_INDEX
		current_quest = get_current_quest_text()
		quest_changed.emit(current_quest)
		if current_task_index != previous_index:
			var all_bandits_event := build_canonical_activity_event({
				"type": "task_completed",
				"key": "quest:oakleaf:normal-bandits:complete",
				"title": "Oakleaf Bandits Complete",
				"description": "The Boss Bandit is now available.",
				"canonical_task_id": "oakleaf-bandits",
				"canonical_milestone_id": "oakleaf.bandits.complete",
			}, OAKLEAF_BANDIT_TASK_INDEX, "task_completed")
			task_state_changed.emit(previous_index, current_task_index, all_bandits_event)
		if persist and normalized_id != OAKLEAF_BANDIT_IDS[0]:
			save_game()
		return {
			"changed": true,
			"action": "bandit_defeated",
			"encounter_id": normalized_id,
			"defeated_count": get_oakleaf_defeated_bandit_count(),
			"current_index": current_task_index,
		}

	if normalized_id == OAKLEAF_BOSS_ID:
		if not can_start_oakleaf_encounter(normalized_id):
			return {"changed": false, "action": "blocked", "encounter_id": normalized_id}
		oakleaf_boss_defeated = true
		oakleaf_return_to_teacher = true
		var previous_index := current_task_index
		current_task_index = OAKLEAF_RETURN_TEACHER_TASK_INDEX
		current_quest = get_current_quest_text()
		quest_changed.emit(current_quest)
		var boss_event := build_canonical_activity_event({
			"type": "task_completed",
			"key": "quest:oakleaf:boss:complete",
			"title": "Task 3 Complete",
			"description": "Return to the Teacher.",
			"canonical_task_id": "oakleaf-boss-bandit",
			"canonical_milestone_id": "oakleaf.boss.complete",
		}, OAKLEAF_BOSS_TASK_INDEX, "task_completed")
		# Boss completion closes the combined Oakleaf challenge. Normal Bandits
		# are internal milestones and must not create a second player-facing task.
		_record_player_facing_completion("oakleaf-bandits")
		task_state_changed.emit(previous_index, current_task_index, boss_event)
		if persist:
			save_game()
		return {
			"changed": true,
			"action": "boss_defeated",
			"encounter_id": normalized_id,
			"current_index": current_task_index,
		}

	return {"changed": false, "action": "ignored", "encounter_id": normalized_id}


func is_oakleaf_return_to_teacher_active() -> bool:
	return oakleaf_return_to_teacher and current_task_index == OAKLEAF_RETURN_TEACHER_TASK_INDEX


func complete_oakleaf_teacher_return() -> Dictionary:
	if not is_oakleaf_return_to_teacher_active():
		return {"changed": false, "action": "blocked"}
	var previous_index := current_task_index
	oakleaf_return_to_teacher = false
	city_of_knowledge_unlocked = true
	current_task_index = CITY_OF_KNOWLEDGE_TASK_INDEX
	current_quest = get_current_quest_text()
	quest_changed.emit(current_quest)
	var event := {
		"type": "task_completed",
		"key": "quest:oakleaf:return-teacher:complete",
		"title": "Task 4 Complete",
		"description": "Go to the City of Knowledge / School.",
		"source": "teacher_task_interaction",
		"reason": "oakleaf_boss_return",
	}
	_record_player_facing_completion("oakleaf-return-to-teacher")
	event = build_canonical_activity_event(event, previous_index, "task_completed")
	task_state_changed.emit(previous_index, current_task_index, event)
	_notify_progress(event)
	var save_path := save_game()
	return {
		"changed": true,
		"action": "oakleaf_complete",
		"current_index": current_task_index,
		"save_path": save_path,
	}


func is_city_school_active() -> bool:
	return city_of_knowledge_unlocked \
			and city_first_arrival_seen \
			and not city_school_stage_complete \
			and current_task_index in [CITY_SCHOOL_TASK_INDEX, CITY_SCHOOL_TEACHER_TASK_INDEX]


func is_city_next_path_unlocked() -> bool:
	return city_next_path_unlocked


func is_pinehill_unlocked() -> bool:
	return pinehill_unlocked


func mark_city_first_arrival() -> Dictionary:
	if not city_of_knowledge_unlocked \
			or city_first_arrival_seen \
			or city_school_stage_complete \
			or city_next_path_unlocked \
			or current_task_index != CITY_OF_KNOWLEDGE_TASK_INDEX:
		return {"changed": false, "action": "blocked"}

	city_first_arrival_seen = true
	city_school_stage = 1
	var previous_index := current_task_index
	current_task_index = CITY_SCHOOL_TASK_INDEX
	current_quest = get_current_quest_text()
	quest_changed.emit(current_quest)
	var event := {
		"type": "task_completed",
		"key": "quest:city:first-arrival:complete",
		"title": "City of Knowledge Reached",
		"description": "Go to the School.",
		"source": "city_scene_entry",
		"reason": "city_unlocked_arrival",
	}
	event = build_canonical_activity_event(event, previous_index, "task_completed")
	task_state_changed.emit(previous_index, current_task_index, event)
	_notify_progress(event)
	var save_path := save_game()
	return {
		"changed": true,
		"action": "city_first_arrival",
		"current_index": current_task_index,
		"save_path": save_path,
	}


func complete_city_school_teacher() -> Dictionary:
	if not is_city_school_active():
		return {"changed": false, "action": "blocked"}

	city_school_stage_complete = true
	city_next_path_unlocked = true
	city_school_stage = 2
	var previous_index := current_task_index
	# Preserve the established School completion checkpoint. The City scene entry
	# below activates the newly restored deep-forest encounter stage.
	current_task_index = CITY_NEXT_PATH_TASK_INDEX
	current_quest = get_current_quest_text()
	quest_changed.emit(current_quest)
	var event := {
		"type": "task_completed",
		"key": "quest:city:school-teacher:complete",
		"title": "School Complete",
		"description": "Defeat All Bandits on the forest path.",
		"source": "teacher_task_interaction",
		"reason": "city_school_teacher",
	}
	_record_player_facing_completion(String(get_task_activity_metadata(previous_index).get("canonical_task_id", "talk-to-city-school-teacher")))
	event = build_canonical_activity_event(event, previous_index, "task_completed")
	task_state_changed.emit(previous_index, current_task_index, event)
	_notify_progress(event)
	var save_path := save_game()
	return {
		"changed": true,
		"action": "city_school_complete",
		"current_index": current_task_index,
		"save_path": save_path,
	}


func is_final_teacher_active() -> bool:
	return current_task_index == FINAL_TEACHER_TASK_INDEX \
			and not final_teacher_defeated \
			and not journey_complete \
			and return_to_city_stage >= 2


func _progression_group_for_id(encounter_id: String) -> String:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id in DEEP_FOREST_BANDIT_IDS:
		return "deep_forest"
	if normalized_id in PINEHILL_BANDIT_IDS:
		return "pinehill"
	if normalized_id in RETURN_PATH_BANDIT_IDS:
		return "return_path"
	return ""


func _progression_defeat_map(group: String) -> Dictionary:
	match group:
		"deep_forest":
			return deep_forest_defeated_bandits
		"pinehill":
			return pinehill_defeated_bandits
		"return_path":
			return return_path_defeated_bandits
		_:
			return {}


func is_progression_encounter_defeated(encounter_id: String) -> bool:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id == "pinehill_wizard":
		return wizard_defeated
	if normalized_id == "final_teacher":
		return final_teacher_defeated
	var group := _progression_group_for_id(normalized_id)
	if group.is_empty():
		return false
	return bool(_progression_defeat_map(group).get(normalized_id, false))


func are_all_progression_bandits_defeated(group: String) -> bool:
	var normalized_group := group.strip_edges().to_lower()
	var ids: Array[String] = []
	match normalized_group:
		"deep_forest":
			ids = DEEP_FOREST_BANDIT_IDS
		"pinehill":
			ids = PINEHILL_BANDIT_IDS
		"return_path":
			ids = RETURN_PATH_BANDIT_IDS
		_:
			return false
	var defeated := _progression_defeat_map(normalized_group)
	for encounter_id in ids:
		if not bool(defeated.get(encounter_id, false)):
			return false
	return true


func can_start_progression_encounter(encounter_id: String) -> bool:
	var normalized_id := encounter_id.strip_edges()
	if is_progression_encounter_defeated(normalized_id):
		return false
	var group := _progression_group_for_id(normalized_id)
	if group == "deep_forest":
		return current_task_index == DEEP_FOREST_BANDIT_TASK_INDEX
	if group == "pinehill":
		return current_task_index == PINEHILL_BANDIT_TASK_INDEX and pinehill_old_man_completed
	if normalized_id == "pinehill_wizard":
		return current_task_index == WIZARD_TASK_INDEX \
				and are_all_progression_bandits_defeated("pinehill") \
				and not wizard_defeated
	if normalized_id == "final_teacher":
		return is_final_teacher_active()
	return false


func _advance_progression_checkpoint(previous_index: int, next_index: int, key: String, title: String, description: String) -> void:
	if next_index <= previous_index:
		return
	current_task_index = next_index
	current_quest = get_current_quest_text()
	quest_changed.emit(current_quest)
	var task_id := String(get_task_activity_metadata(previous_index).get("canonical_task_id", ""))
	var completion_event := build_canonical_activity_event({
		"type": "task_completed",
		"key": key,
		"title": title,
		"description": description,
		"canonical_task_id": task_id,
	}, previous_index, "task_completed")
	_record_player_facing_completion(task_id)
	task_state_changed.emit(previous_index, current_task_index, completion_event)


func record_progression_encounter_victory(encounter_id: String, persist: bool = true) -> Dictionary:
	var normalized_id := encounter_id.strip_edges()
	if not can_start_progression_encounter(normalized_id):
		return {"changed": false, "action": "blocked", "encounter_id": normalized_id}
	var group := _progression_group_for_id(normalized_id)
	if not group.is_empty():
		_progression_defeat_map(group)[normalized_id] = true
	var previous_index := current_task_index
	var action := "progression_encounter_defeated"
	if group == "deep_forest" and are_all_progression_bandits_defeated(group):
		pinehill_unlocked = true
		current_task_index = PINEHILL_ARRIVAL_TASK_INDEX
		action = "deep_forest_complete"
	elif group == "pinehill" and are_all_progression_bandits_defeated(group):
		current_task_index = WIZARD_TASK_INDEX
		action = "pinehill_bandits_complete"
	elif normalized_id == "pinehill_wizard":
		wizard_defeated = true
		return_to_city_stage = 2
		current_task_index = RETURN_CITY_TASK_INDEX
		action = "wizard_complete"
	elif normalized_id == "final_teacher":
		final_teacher_defeated = true
		journey_complete = true
		city_school_stage = 4
		current_task_index = tasks.size()
		action = "journey_complete"
	var encounter_number := 0
	if group == "deep_forest":
		encounter_number = DEEP_FOREST_BANDIT_IDS.find(normalized_id) + 1
	elif group == "pinehill":
		encounter_number = PINEHILL_BANDIT_IDS.find(normalized_id) + 1
	if encounter_number > 0:
		var internal_event := build_canonical_activity_event({
			"type": "task_completed",
			"key": "quest:%s:bandit:%d:complete" % [group, encounter_number],
			"canonical_task_id": String(get_task_activity_metadata(previous_index).get("canonical_task_id", "")),
			"canonical_milestone_id": "%s.bandit_%d" % [group, encounter_number],
			"is_player_facing": false,
		}, previous_index, "task_completed")
		canonical_activity_boundary.emit(internal_event)
	if current_task_index != previous_index:
		_advance_progression_checkpoint(previous_index, current_task_index,
			"quest:world:%s" % action, action.replace("_", " ").capitalize(), get_current_quest_text())
	else:
		current_quest = get_current_quest_text()
		quest_changed.emit(current_quest)
	var save_path := ""
	if persist:
		save_path = save_game()
	return {
		"changed": true,
		"action": action,
		"encounter_id": normalized_id,
		"current_index": current_task_index,
		"save_path": save_path,
	}


func complete_pinehill_old_man() -> Dictionary:
	if pinehill_old_man_completed or current_task_index != PINEHILL_OLD_MAN_TASK_INDEX:
		return {"changed": false, "action": "blocked"}
	pinehill_old_man_completed = true
	var previous_index := current_task_index
	_advance_progression_checkpoint(previous_index, PINEHILL_BANDIT_TASK_INDEX,
		"quest:pinehill:old-man", "Old Man", "Defeat All Bandits.")
	var save_path := save_game()
	return {"changed": true, "action": "old_man_complete", "current_index": current_task_index, "save_path": save_path}


func get_current_quest_text() -> String:
	if is_tutorial_active():
		return TUTORIAL_QUEST
	if journey_complete:
		return "Math Champion"
	if current_task_index == DEEP_FOREST_BANDIT_TASK_INDEX or current_task_index == PINEHILL_BANDIT_TASK_INDEX:
		return "Defeat All Bandits"
	if current_task_index == WIZARD_TASK_INDEX:
		return "Defeat the Wizard"
	if current_task_index == FINAL_TEACHER_TASK_INDEX:
		return "Talk to the Master Teacher"
	if current_task_index >= PINEHILL_OLD_MAN_TASK_INDEX and current_task_index < PINEHILL_BANDIT_TASK_INDEX:
		return "Talk to the Old Man"
	if current_task_index == CITY_NEXT_PATH_TASK_INDEX or (city_next_path_unlocked and current_task_index < DEEP_FOREST_BANDIT_TASK_INDEX):
		return "Go to Pinehill Village"
	if current_task_index == PINEHILL_ARRIVAL_TASK_INDEX:
		return "Go to Pinehill Village"
	if current_task_index == RETURN_CITY_TASK_INDEX:
		return "Return to the City of Knowledge"
	if current_task_index == FINAL_SCHOOL_TASK_INDEX:
		return "Go to the School"
	if city_first_arrival_seen:
		if current_task_index == CITY_SCHOOL_TEACHER_TASK_INDEX:
			return "Talk to the Math Teacher"
		return "Go to the School"
	if current_task_index == OAKLEAF_BANDIT_TASK_INDEX:
		return "Defeat All Bandits"
	if current_task_index >= 0 and current_task_index < tasks.size():
		return String(tasks[current_task_index].get("quest_text", ""))
	return current_quest.strip_edges()


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
	current_quest = get_current_quest_text()
	var event_type := String(event.get("type", ""))
	if event_type in ["task_completed", "quest_completed"]:
		var completion_task_id := String(event.get("canonical_task_id", ""))
		if completion_task_id.is_empty():
			completion_task_id = String(get_task_activity_metadata(previous_index).get("canonical_task_id", ""))
		_record_player_facing_completion(completion_task_id)
		event = build_canonical_activity_event(event, previous_index, event_type)
	var save_path := save_game()
	task_state_changed.emit(previous_index, current_task_index, event)
	_notify_progress(event)
	return {
		"advanced": true,
		"save_path": save_path,
		"previous_index": previous_index,
		"current_index": current_task_index
	}


func get_task_activity_metadata(task_index: int) -> Dictionary:
	if task_index < 0 or task_index >= tasks.size():
		return {}
	var task: Variant = tasks[task_index]
	if not (task is Dictionary):
		return {}
	var activity_id := String(task.get("activity_id", "")).strip_edges()
	var activity_label := String(task.get("activity_label", task.get("quest_text", ""))).strip_edges()
	if activity_id.is_empty() or activity_label.is_empty():
		return {}
	return {
		"activity_id": activity_id,
		"activity_label": activity_label,
		"canonical_task_id": activity_id,
	}


func canonical_map_id() -> String:
	var candidate := String(current_map).to_lower()
	if candidate.contains("pinehill"):
		return "pinehill_village"
	if candidate.contains("city"):
		return "city_of_knowledge"
	if candidate.contains("oak") or candidate.contains("teacher"):
		return "oakleaf_village"
	var scene_candidate := String(current_scene_path).to_lower()
	if scene_candidate.contains("pinehill"):
		return "pinehill_village"
	if scene_candidate.contains("city"):
		return "city_of_knowledge"
	return "oakleaf_village"


func canonical_difficulty_for_map(map_id: String) -> String:
	match map_id:
		"oakleaf_village":
			return "Easy"
		"city_of_knowledge":
			return "Normal"
		"pinehill_village":
			return "Difficult"
		_:
			return "Unknown"


func _utc_timestamp() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


func _activity_phase(event_type: String) -> String:
	return "complete" if event_type in ["task_completed", "quest_completed"] else "start"


func _activity_started_duration(activity_id: String) -> Dictionary:
	var started: Variant = _activity_started_at.get(activity_id, {})
	return started if started is Dictionary else {}


func build_canonical_activity_event(event: Dictionary, task_index: int, event_type: String = "") -> Dictionary:
	var result := event.duplicate(true)
	var metadata := get_task_activity_metadata(task_index)
	var activity_id := String(result.get("canonical_activity_id", result.get("activity_id", metadata.get("activity_id", "")))).strip_edges()
	if activity_id.is_empty():
		activity_id = String(metadata.get("canonical_task_id", "")).strip_edges()
	var canonical_task_id := String(result.get("canonical_task_id", metadata.get("canonical_task_id", activity_id))).strip_edges()
	var resolved_type := String(event_type if not event_type.is_empty() else result.get("type", "")).strip_edges()
	var phase := _activity_phase(resolved_type)
	var map_id := String(result.get("map_id", canonical_map_id())).strip_edges()
	var milestone_id := String(result.get("canonical_milestone_id", "%s.complete" % canonical_task_id)).strip_edges()
	var stable_event_id := String(result.get("activity_event_id", "")).strip_edges()
	if stable_event_id.is_empty():
		stable_event_id = "cycle:%d:activity:%s:%s" % [learning_cycle_version, activity_id, phase]
	var started := _activity_started_duration(activity_id)
	var started_at := String(result.get("started_at", started.get("started_at", ""))).strip_edges()
	var completed_at := String(result.get("completed_at", _utc_timestamp() if phase == "complete" else "")).strip_edges()
	var duration_seconds := int(result.get("duration_seconds", -1))
	if duration_seconds < 0 and phase == "complete" and started.has("started_unix"):
		duration_seconds = maxi(0, int(Time.get_unix_time_from_system() - float(started.get("started_unix", 0.0))))
	result["telemetry_contract_version"] = TELEMETRY_CONTRACT_VERSION
	result["quest_graph_version"] = QUEST_GRAPH_VERSION
	result["activity_event_id"] = stable_event_id
	result["canonical_activity_id"] = activity_id
	result["canonical_quest_id"] = String(result.get("canonical_quest_id", "main"))
	result["canonical_task_id"] = canonical_task_id
	result["canonical_milestone_id"] = milestone_id
	result["map_id"] = map_id
	result["difficulty"] = canonical_difficulty_for_map(map_id)
	result["started_at"] = started_at
	result["completed_at"] = completed_at
	result["duration_seconds"] = duration_seconds if duration_seconds >= 0 else null
	result["is_player_facing"] = bool(result.get("is_player_facing", true))
	return result


func _record_player_facing_completion(task_id: String) -> void:
	var normalized := task_id.strip_edges()
	if normalized.is_empty() or _completed_player_facing_tasks.has(normalized):
		return
	_completed_player_facing_tasks[normalized] = true
	total_quests_completed = _completed_player_facing_tasks.size()


func emit_tutorial_activity_started() -> bool:
	if _tutorial_activity_started or not is_tutorial_active():
		return false
	var tutorial_metadata := _get_tutorial_activity_metadata()
	if tutorial_metadata.is_empty():
		return false
	_tutorial_activity_started = true
	_activity_started_at["tutorial"] = {
		"started_at": _utc_timestamp(),
		"started_unix": Time.get_unix_time_from_system(),
	}
	var start_event := build_canonical_activity_event({
		"type": "task_trigger",
		"key": "tutorial:start",
		"previous_index": -1,
		"current_index": 0,
		"activity": tutorial_metadata,
	}, 0, "task_trigger")
	canonical_activity_boundary.emit(start_event)
	return true


func is_tutorial_active() -> bool:
	return current_task_index == 0 and not _tutorial_activity_completed


func complete_tutorial_activity() -> bool:
	if not is_tutorial_active():
		return false
	var tutorial_metadata := _get_tutorial_activity_metadata()
	if tutorial_metadata.is_empty():
		return false
	_tutorial_activity_completed = true
	_record_player_facing_completion("tutorial")
	current_quest = String(tasks[0].get("quest_text", ""))
	quest_changed.emit(current_quest)
	var completion_event := build_canonical_activity_event({
		"type": "task_completed",
		"key": "tutorial:complete",
		"title": "Task 1 Complete",
		"description": "Tutorial complete. Go to the Teacher's House.",
		"previous_index": 0,
		"current_index": 0,
		"activity": tutorial_metadata,
	}, 0, "task_completed")
	canonical_activity_boundary.emit(completion_event)
	_notify_progress(completion_event)
	emit_current_task_activity_started()
	return true


func emit_current_task_activity_started() -> bool:
	var metadata := get_task_activity_metadata(current_task_index)
	var activity_id := String(metadata.get("activity_id", ""))
	if activity_id.is_empty() or _started_task_activity_ids.has(activity_id):
		return false
	_started_task_activity_ids[activity_id] = true
	_activity_started_at[activity_id] = {
		"started_at": _utc_timestamp(),
		"started_unix": Time.get_unix_time_from_system(),
	}
	var start_event := build_canonical_activity_event({
		"type": "task_trigger",
		"key": "task:%s:start" % activity_id,
		"previous_index": current_task_index,
		"current_index": current_task_index,
		"activity": metadata,
	}, current_task_index, "task_trigger")
	canonical_activity_boundary.emit(start_event)
	return true


func _get_tutorial_activity_metadata() -> Dictionary:
	if tasks.is_empty() or not (tasks[0] is Dictionary):
		return {}
	var metadata: Variant = tasks[0].get("tutorial_activity", {})
	if not (metadata is Dictionary):
		return {}
	var activity_id := String(metadata.get("activity_id", "")).strip_edges()
	var activity_label := String(metadata.get("activity_label", "")).strip_edges()
	if activity_id.is_empty() or activity_label.is_empty():
		return {}
	return {
		"activity_id": activity_id,
		"activity_label": activity_label,
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


func is_valid_existing_student_id(value: String) -> bool:
	return is_valid_six_digit_id(value) or is_valid_new_student_id(value)


func is_valid_new_student_id(value: String) -> bool:
	if value.length() != 8:
		return false
	for character in value:
		var codepoint := character.unicode_at(0)
		if codepoint < 48 or codepoint > 57:
			return false
	return true


func sanitize_student_id(value: String) -> String:
	var digits := ""
	for character in value:
		var codepoint := character.unicode_at(0)
		if codepoint >= 48 and codepoint <= 57:
			digits += character
			if digits.length() == 8:
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
		and is_valid_existing_student_id(String(values.get("student_id", "")))
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

	current_quest = TUTORIAL_QUEST
	current_lives = max_lives
	current_scene_path = START_SCENE_PATH
	player_position = get_scene_fallback_spawn(START_SCENE_PATH)
	city_of_knowledge_unlocked = false
	city_first_arrival_seen = false
	city_school_stage_complete = false
	city_next_path_unlocked = false
	current_task_index = 0
	_reset_oakleaf_progression()
	_reset_world_progression()
	_tutorial_activity_started = false
	_tutorial_activity_completed = false
	_started_task_activity_ids.clear()
	_activity_started_at.clear()
	_completed_player_facing_tasks.clear()
	total_quests_completed = 0
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
	var normalized_id := String(student_id)
	if not is_valid_existing_student_id(normalized_id):
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

func finalize_new_game_registration(server_authorized: bool = false) -> bool:
	var values := get_new_game_registration()
	if not is_valid_new_game_registration(values):
		return false
	# New Game normally protects a device-local profile. The canonical New Game
	# controller may override that guard only after the backend has explicitly
	# authorized this Student/Parent pair and issued the playtime decision.
	if not server_authorized and has_existing_game_profile_for_student_id(String(values.get("student_id", ""))):
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
	if current_scene_path == "res://scenes/city_of_knowledge.tscn":
		if return_to_city_stage >= 2 and current_task_index == RETURN_CITY_TASK_INDEX:
			current_task_index = FINAL_SCHOOL_TASK_INDEX
			current_quest = get_current_quest_text()
			quest_changed.emit(current_quest)
			save_game()
		elif city_school_stage_complete and current_task_index == CITY_NEXT_PATH_TASK_INDEX:
			current_task_index = DEEP_FOREST_BANDIT_TASK_INDEX
			current_quest = get_current_quest_text()
			quest_changed.emit(current_quest)
			save_game()
		else:
			mark_city_first_arrival()
	elif current_scene_path == "res://interiors/school.tscn":
		if current_task_index == CITY_SCHOOL_TASK_INDEX and city_first_arrival_seen and not city_school_stage_complete:
			current_task_index = CITY_SCHOOL_TEACHER_TASK_INDEX
			current_quest = get_current_quest_text()
			quest_changed.emit(current_quest)
			save_game()
		elif current_task_index == FINAL_SCHOOL_TASK_INDEX and return_to_city_stage >= 2:
			current_task_index = FINAL_TEACHER_TASK_INDEX
			current_quest = get_current_quest_text()
			quest_changed.emit(current_quest)
			save_game()
	elif current_scene_path == "res://scenes/2nd Village/Pinehill Village.tscn" \
			and pinehill_unlocked and current_task_index == PINEHILL_ARRIVAL_TASK_INDEX:
		current_task_index = PINEHILL_OLD_MAN_TASK_INDEX
		current_quest = get_current_quest_text()
		quest_changed.emit(current_quest)
		save_game()

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
	var requested_question_scope: Variant = options.get("question_scope", encounter_context.get("question_scope", {}))
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
		"question_scope": _normalize_question_scope(requested_question_scope, source_scene_path),
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
	var oakleaf_result := _record_oakleaf_encounter_victory(
		String(completed_context.get("encounter_id", "")),
		true
	)
	var progression_result := record_progression_encounter_victory(
		String(completed_context.get("encounter_id", "")),
		true
	)
	return {
		"success": true,
		"action": "victory",
		"context": completed_context,
		"oakleaf": oakleaf_result,
		"progression": progression_result,
	}


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
	var owner_id := _get_current_save_owner_id()
	if owner_id.is_empty():
		push_warning("Save skipped because no valid Student identity is active.")
		return ""
	_ensure_save_directory()

	var now: Dictionary = Time.get_datetime_dict_from_system()
	var save_stem: String = "%s/save_%s_%04d%02d%02d_%02d%02d%02d" % [
		SAVE_DIRECTORY,
		owner_id,
		int(now.get("year", 0)),
		int(now.get("month", 0)),
		int(now.get("day", 0)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0))
	]
	var save_path := save_stem + ".json"
	var collision_suffix := 2
	while FileAccess.file_exists(save_path):
		save_path = "%s_%03d.json" % [save_stem, collision_suffix]
		collision_suffix += 1
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
		"device_installation_id": get_device_installation_id(),
		"learning_cycle_version": learning_cycle_version,
		"learning_cycle_started_at": learning_cycle_started_at,
		"current_quest": TUTORIAL_QUEST if is_tutorial_active() else current_quest,
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
		"city_first_arrival_seen": city_first_arrival_seen,
		"city_school_stage_complete": city_school_stage_complete,
		"city_next_path_unlocked": city_next_path_unlocked,
		"city_school_stage": city_school_stage,
		"deep_forest_defeated_bandits": deep_forest_defeated_bandits.duplicate(true),
		"pinehill_unlocked": pinehill_unlocked,
		"pinehill_old_man_completed": pinehill_old_man_completed,
		"pinehill_defeated_bandits": pinehill_defeated_bandits.duplicate(true),
		"wizard_defeated": wizard_defeated,
		"return_to_city_stage": return_to_city_stage,
		"return_path_defeated_bandits": return_path_defeated_bandits.duplicate(true),
		"final_teacher_defeated": final_teacher_defeated,
		"journey_complete": journey_complete,
		"oakleaf_defeated_bandits": oakleaf_defeated_bandits.duplicate(true),
		"oakleaf_boss_defeated": oakleaf_boss_defeated,
		"oakleaf_return_to_teacher": oakleaf_return_to_teacher,
		"activity_started_at": _activity_started_at.duplicate(true),
		"completed_player_facing_tasks": _completed_player_facing_tasks.duplicate(true),
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
	if _get_current_save_owner_id().is_empty():
		return saves
	var directory := DirAccess.open(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	if directory == null:
		return saves

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var save_path := SAVE_DIRECTORY + "/" + file_name
			var save_data := _read_save_file(save_path)
			# Ownership must be proven from the canonical Student ID saved after
			# profile validation. Ownerless legacy files remain untouched and hidden.
			if _is_save_owned_by_current_student(save_data):
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
	if not _is_save_owned_by_current_student(data):
		return {}
	return _prepare_save_entry(data, save_path)


func delete_save(path: String) -> bool:
	var save_path := _validated_save_path(path)
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return false
	if not _is_save_owned_by_current_student(_read_save_file(save_path)):
		return false

	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path)) == OK


func delete_all_saves() -> Dictionary:
	var deleted_count := 0
	var failed_count := 0
	for save_data in list_saves():
		var save_path := String(save_data.get("save_path", ""))
		if save_path.is_empty():
			continue
		if delete_save(save_path):
			deleted_count += 1
		else:
			failed_count += 1
	return {
		"deleted_count": deleted_count,
		"failed_count": failed_count,
	}


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
	city_first_arrival_seen = bool(data.get("city_first_arrival_seen", false))
	city_school_stage_complete = bool(data.get("city_school_stage_complete", false))
	city_next_path_unlocked = bool(data.get("city_next_path_unlocked", false))
	city_school_stage = clampi(int(data.get("city_school_stage", 0)), 0, 4)
	var loaded_task_index := clampi(int(data.get("current_task_index", 0)), 0, tasks.size())
	current_task_index = loaded_task_index
	if not data.has("city_first_arrival_seen"):
		city_first_arrival_seen = loaded_task_index >= CITY_SCHOOL_TASK_INDEX
	if not data.has("city_school_stage_complete"):
		city_school_stage_complete = loaded_task_index >= CITY_NEXT_PATH_TASK_INDEX
	if not data.has("city_next_path_unlocked"):
		city_next_path_unlocked = loaded_task_index >= CITY_NEXT_PATH_TASK_INDEX
	if city_next_path_unlocked or city_school_stage_complete:
		current_task_index = maxi(current_task_index, CITY_NEXT_PATH_TASK_INDEX)
	elif city_first_arrival_seen:
		current_task_index = maxi(current_task_index, CITY_SCHOOL_TASK_INDEX)
	if not data.has("city_school_stage"):
		city_school_stage = 2 if city_school_stage_complete else (1 if city_first_arrival_seen else 0)
	oakleaf_defeated_bandits = _normalize_oakleaf_defeated_bandits(
		data.get("oakleaf_defeated_bandits", null),
		loaded_task_index
	)
	oakleaf_boss_defeated = bool(data.get("oakleaf_boss_defeated", false))
	oakleaf_return_to_teacher = bool(data.get("oakleaf_return_to_teacher", false))
	deep_forest_defeated_bandits = _normalize_progression_defeated_bandits(
		data.get("deep_forest_defeated_bandits", null), DEEP_FOREST_BANDIT_IDS
	)
	pinehill_unlocked = bool(data.get("pinehill_unlocked", false))
	pinehill_old_man_completed = bool(data.get("pinehill_old_man_completed", false))
	pinehill_defeated_bandits = _normalize_progression_defeated_bandits(
		data.get("pinehill_defeated_bandits", null), PINEHILL_BANDIT_IDS
	)
	wizard_defeated = bool(data.get("wizard_defeated", false))
	return_to_city_stage = clampi(int(data.get("return_to_city_stage", 0)), 0, 2)
	return_path_defeated_bandits = _normalize_progression_defeated_bandits(
		data.get("return_path_defeated_bandits", null), RETURN_PATH_BANDIT_IDS
	)
	final_teacher_defeated = bool(data.get("final_teacher_defeated", false))
	journey_complete = bool(data.get("journey_complete", false))
	# Monotonic migration for SAVE_VERSION 9 records that predate the extended
	# world timeline. Optional fields default safely and never move a checkpoint
	# backward or replay an already completed stage.
	if journey_complete or final_teacher_defeated:
		journey_complete = journey_complete or final_teacher_defeated
		final_teacher_defeated = true
		city_school_stage = 4
		current_task_index = tasks.size()
	elif return_to_city_stage >= 2:
		current_task_index = maxi(current_task_index, RETURN_CITY_TASK_INDEX)
	elif wizard_defeated:
		return_to_city_stage = 2
		current_task_index = maxi(current_task_index, RETURN_CITY_TASK_INDEX)
	elif are_all_progression_bandits_defeated("pinehill"):
		current_task_index = maxi(current_task_index, WIZARD_TASK_INDEX)
	elif pinehill_old_man_completed:
		current_task_index = maxi(current_task_index, PINEHILL_BANDIT_TASK_INDEX)
	elif pinehill_unlocked:
		current_task_index = maxi(current_task_index, PINEHILL_ARRIVAL_TASK_INDEX)
	elif are_all_progression_bandits_defeated("deep_forest"):
		current_task_index = maxi(current_task_index, PINEHILL_ARRIVAL_TASK_INDEX)
	# Existing saves persist current_quest. Unmarked legacy saves retain
	# their existing task checkpoint rather than replaying an unrecorded tutorial.
	_tutorial_activity_completed = current_task_index > 0 or current_quest != TUTORIAL_QUEST
	# Older saves can carry a completed checkpoint with an obsolete quest title.
	# The checkpoint is authoritative; reconcile presentation without replaying tasks.
	current_quest = get_current_quest_text()
	_tutorial_activity_started = false
	_started_task_activity_ids.clear()
	_activity_started_at = data.get("activity_started_at", {}).duplicate(true) if data.get("activity_started_at", {}) is Dictionary else {}
	_completed_player_facing_tasks = data.get("completed_player_facing_tasks", {}).duplicate(true) if data.get("completed_player_facing_tasks", {}) is Dictionary else {}
	score = int(data.get("score", 0))
	correct_answers = int(data.get("correct_answers", 0))
	incorrect_answers = int(data.get("incorrect_answers", 0))
	total_questions = int(data.get("total_questions", 0))
	progress_percentage = int(data.get("progress_percentage", 0))
	lesson_progress = int(data.get("lesson_progress", 0))
	total_quests_completed = _completed_player_facing_tasks.size() if not _completed_player_facing_tasks.is_empty() else int(data.get("total_quests_completed", 0))
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
	for save_data in list_saves():
		if bool(save_data.get("loadable", false)):
			return String(save_data.get("save_path", ""))
	return ""

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
		if not grade.is_empty():
			normalized["grade"] = grade
		if not difficulty.is_empty():
			normalized["difficulty"] = difficulty
	if not normalized.has("grade") and not grade_level.strip_edges().is_empty():
		normalized["grade"] = grade_level.strip_edges()
	if not normalized.has("difficulty"):
		normalized["difficulty"] = _difficulty_for_scene(source_scene_path)
	return normalized


func _normalize_difficulty(value: String) -> String:
	match value.strip_edges().to_lower():
		"easy":
			return "Easy"
		"medium", "average", "normal":
			return "Normal"
		"hard", "difficult":
			return "Difficult"
		_:
			return ""


func _difficulty_for_scene(scene_path: String) -> String:
	var normalized_scene_path := _normalize_scene_path(scene_path).to_lower()
	if normalized_scene_path.contains("city_of_knowledge"):
		return "Normal"
	if normalized_scene_path.contains("pinehill") or normalized_scene_path.contains("2nd village"):
		return "Difficult"
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


func _normalize_oakleaf_defeated_bandits(value: Variant, loaded_task_index: int) -> Dictionary:
	var normalized: Dictionary = {}
	for encounter_id in OAKLEAF_BANDIT_IDS:
		normalized[encounter_id] = false
	if value is Dictionary:
		for encounter_id in OAKLEAF_BANDIT_IDS:
			normalized[encounter_id] = bool(value.get(encounter_id, false))
		return normalized
	# Version 8 saves have no per-encounter field, but checkpoint 3 is only
	# reachable after the original First Bandit task has completed.
	if loaded_task_index >= OAKLEAF_BANDIT_TASK_INDEX:
		normalized[OAKLEAF_BANDIT_IDS[0]] = true
	return normalized


func _normalize_progression_defeated_bandits(value: Variant, ids: Array[String]) -> Dictionary:
	var normalized: Dictionary = {}
	for encounter_id in ids:
		normalized[encounter_id] = false
	if value is Dictionary:
		for encounter_id in ids:
			normalized[encounter_id] = bool(value.get(encounter_id, false))
	return normalized


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


func _get_current_save_owner_id() -> String:
	var owner_id := student_id.strip_edges()
	if not is_valid_existing_student_id(owner_id):
		return ""
	return owner_id


func _is_save_owned_by_current_student(data: Dictionary) -> bool:
	var owner_id := _get_current_save_owner_id()
	if owner_id.is_empty() or data.is_empty():
		return false
	if String(data.get("student_id", "")).strip_edges() != owner_id:
		return false
	# New saves are device-scoped. A legacy Student-owned save without the new
	# metadata remains readable for compatibility; ownerless records are still
	# hidden because they cannot prove either identity.
	var saved_device_id := String(data.get("device_installation_id", "")).strip_edges()
	return saved_device_id.is_empty() or saved_device_id == get_device_installation_id()


func get_device_installation_id() -> String:
	if not device_installation_id.is_empty():
		return device_installation_id
	if FileAccess.file_exists(DEVICE_INSTALLATION_ID_PATH):
		var existing := FileAccess.open(DEVICE_INSTALLATION_ID_PATH, FileAccess.READ)
		if existing != null:
			device_installation_id = existing.get_as_text().strip_edges()
			existing.close()
	if device_installation_id.is_empty():
		var runtime_identity := OS.get_unique_id().strip_edges()
		if runtime_identity.is_empty():
			runtime_identity = "%s-%d-%d" % [OS.get_name().to_lower(), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		device_installation_id = "device-%s" % runtime_identity
		var created := FileAccess.open(DEVICE_INSTALLATION_ID_PATH, FileAccess.WRITE)
		if created != null:
			created.store_string(device_installation_id)
			created.close()
	return device_installation_id


func has_current_terms_acceptance(for_student_id: String = "") -> bool:
	var owner_id := for_student_id.strip_edges() if not for_student_id.strip_edges().is_empty() else student_id.strip_edges()
	if owner_id.is_empty() or not FileAccess.file_exists(TERMS_ACCEPTANCE_PATH):
		return false
	var file := FileAccess.open(TERMS_ACCEPTANCE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return false
	return String(parsed.get("student_id", "")).strip_edges() == owner_id \
			and String(parsed.get("device_installation_id", "")).strip_edges() == get_device_installation_id() \
			and String(parsed.get("terms_version", "")).strip_edges() == TERMS_VERSION \
			and not String(parsed.get("accepted_at", "")).strip_edges().is_empty()


func record_terms_acceptance(for_student_id: String = "") -> bool:
	var owner_id := for_student_id.strip_edges() if not for_student_id.strip_edges().is_empty() else student_id.strip_edges()
	if owner_id.is_empty():
		return false
	var file := FileAccess.open(TERMS_ACCEPTANCE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"student_id": owner_id,
		"device_installation_id": get_device_installation_id(),
		"terms_version": TERMS_VERSION,
		"accepted_at": _utc_timestamp(),
	}))
	file.close()
	return true


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
	if not is_valid_existing_student_id(String(data.get("student_id", ""))):
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
	var a_timestamp := int(a.get("save_timestamp", 0))
	var b_timestamp := int(b.get("save_timestamp", 0))
	if a_timestamp != b_timestamp:
		return a_timestamp > b_timestamp

	# Timestamp is authoritative for current saves. Date/time remains the
	# truthful fallback for legacy entries or same-second saves.
	var a_date_time := "%sT%s" % [
		String(a.get("save_date", "")).strip_edges(),
		String(a.get("save_time", "")).strip_edges()
	]
	var b_date_time := "%sT%s" % [
		String(b.get("save_date", "")).strip_edges(),
		String(b.get("save_time", "")).strip_edges()
	]
	return a_date_time > b_date_time
