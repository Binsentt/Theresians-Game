extends Node

## QA-local state walkthrough for the complete Oakleaf chapter.
##
## This intentionally uses the real GameState singleton and its real JSON
## Save/Load path.  It does not simulate input or move a player through the
## maps; those physical interactions remain part of the owner F5 walkthrough.

const PROFILE := {
	"player_name": "Oakleaf Story Runtime Fixture",
	"gender": "male",
	"grade_level": "Grade 4",
	"student_id": "91827364",
	"parent_id": "564738",
	"learning_cycle": {"version": 0, "started_at": ""},
}
const PLAYER_HOUSE_SCENE := "res://interiors/player_house.tscn"
const TEACHER_HOUSE_SCENE := "res://interiors/teacher_house.tscn"
const OAKLEAF_SCENE := "res://scenes/oak_leaf_village.tscn"
const LOCAL_API := "http://127.0.0.1:5000"
const QuestNotificationManagerScript := preload("res://scripts/quest_notification_manager.gd")

var _checks: Array[Dictionary] = []
var _task_events: Array[Dictionary] = []
var _activity_events: Array[Dictionary] = []
var _baseline_save_paths: Dictionary = {}
var _checkpoint_labels: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_assert_qa_boundary()

	GameState.enable_local_qa_mode()
	GameState.start_new_game(PROFILE, false)
	_baseline_save_paths = _current_save_paths()
	_connect_progression_observers()

	_verify_new_game_and_tutorial()
	_checkpoint("after Tutorial")
	_verify_teacher_house_arrival_and_interaction()
	_checkpoint("after Teacher interaction")
	_verify_regular_bandits()
	_verify_boss_and_return_teacher()
	await _verify_notification_and_dialogue_placement()
	_verify_final_completion_identity()
	await _finish()


func _assert_qa_boundary() -> void:
	_expect(HttpApi != null and HttpApi.is_local_qa_profile_active(), "runtime selects the explicit QA-local profile before any autoload can write")
	_expect(HttpApi != null and HttpApi.is_local_qa_mode(), "HttpApi is in local-only mode")
	_expect(HttpApi != null and HttpApi.get_resolved_api_base_url() == LOCAL_API, "API base is the expected loopback backend")
	_expect(RemoteSync != null and bool(RemoteSync.get("local_qa_only")), "RemoteSync disables every telemetry/progress write in QA-local mode")
	_expect(ResourceLoader.exists(PLAYER_HOUSE_SCENE), "Player House checkpoint scene exists")
	_expect(ResourceLoader.exists(TEACHER_HOUSE_SCENE), "Teacher House checkpoint scene exists")
	_expect(ResourceLoader.exists(OAKLEAF_SCENE), "Oakleaf checkpoint scene exists")


func _connect_progression_observers() -> void:
	var task_callback := Callable(self, "_on_task_state_changed")
	if not GameState.task_state_changed.is_connected(task_callback):
		GameState.task_state_changed.connect(task_callback)
	var activity_callback := Callable(self, "_on_canonical_activity_boundary")
	if not GameState.canonical_activity_boundary.is_connected(activity_callback):
		GameState.canonical_activity_boundary.connect(activity_callback)


func _verify_new_game_and_tutorial() -> void:
	GameState.current_scene_path = PLAYER_HOUSE_SCENE
	GameState.current_map = PLAYER_HOUSE_SCENE
	GameState.player_position = Vector2(297.0, 45.0)
	_expect(GameState.current_task_index == 0, "new game begins at the Tutorial checkpoint")
	_expect(GameState.get_current_quest_text() == "Tutorial", "Task 1 current quest is Tutorial")
	_expect(GameState.total_quests_completed == 0, "no player-facing task is completed at task start")
	_expect(GameState.emit_tutorial_activity_started(), "Tutorial start is emitted once")
	_expect(not GameState.emit_tutorial_activity_started(), "duplicate Tutorial start is ignored")
	_expect(GameState.complete_tutorial_activity(), "actual Tutorial completion is accepted")
	_expect(not GameState.complete_tutorial_activity(), "duplicate Tutorial completion is ignored")
	_expect(GameState.current_task_index == 0, "Tutorial completion assigns travel without skipping the Teacher House arrival checkpoint")
	_expect(GameState.get_current_quest_text() == "Go to the Teacher's House", "post-Tutorial objective is Go to Teacher House")
	_expect(GameState.total_quests_completed == 1, "Tutorial counts once as Task 1")
	_expect(_count_event_title("Task 1 Complete") == 1, "Task 1 Complete is emitted exactly once and only after completion")


func _verify_teacher_house_arrival_and_interaction() -> void:
	GameState.current_scene_path = TEACHER_HOUSE_SCENE
	GameState.current_map = TEACHER_HOUSE_SCENE
	GameState.player_position = Vector2(88.0, 112.0)
	var arrival := GameState.advance_task_and_save({
		"type": "task_trigger",
		"key": "qa:oakleaf:teacher-house-arrival",
		"title": "Task 2",
		"description": "Talk to the Teacher",
		"source": "task_progress_trigger",
	})
	_expect(bool(arrival.get("advanced", false)), "entering Teacher House advances only to the interaction checkpoint")
	_expect(GameState.current_task_index == 1, "Teacher House arrival does not auto-complete Task 2")
	_expect(GameState.get_current_quest_text() == "Talk to the Teacher", "Teacher interaction remains the active requirement after arrival")
	_expect(GameState.total_quests_completed == 1, "Teacher House arrival does not inflate completed tasks")
	_expect(_count_event_title("Task 2 Complete") == 0, "Task 2 Complete is absent before Teacher interaction")

	var teacher_interaction := GameState.advance_task_and_save({
		"type": "quest_completed",
		"key": "qa:oakleaf:teacher-interaction-complete",
		"title": "Task 2 Complete",
		"description": "Teacher conversation completed",
		"source": "quest_ui",
		"reason": "teacher_task_completed",
		"canonical_task_id": "talk-to-the-teacher",
	})
	_expect(bool(teacher_interaction.get("advanced", false)), "Teacher interaction completes Task 2 through the canonical transition")
	_expect(GameState.current_task_index == 2, "Teacher interaction unlocks the First Bandit checkpoint")
	_expect(GameState.get_current_quest_text().strip_edges() == "Challenge the player with math questions", "Teacher dialogue assigns the First Bandit math challenge")
	_expect(GameState.total_quests_completed == 2, "Teacher interaction counts once as Task 2")
	_expect(_count_event_title("Task 2 Complete") == 1, "Task 2 Complete is emitted exactly once after interaction")
	_expect(not bool(GameState.complete_oakleaf_teacher_return().get("changed", false)), "return-to-Teacher completion is blocked before the Boss")
	_expect(not GameState.city_of_knowledge_unlocked, "City stays locked before all Bandits and Boss")
	_expect(GameState.can_start_oakleaf_encounter("oakleaf_bandits1"), "First Bandit is available after Teacher interaction")
	for encounter_id in GameState.OAKLEAF_BANDIT_IDS.slice(1):
		_expect(not GameState.can_start_oakleaf_encounter(encounter_id), "%s waits for the First Bandit checkpoint" % encounter_id)
	_expect(not GameState.can_start_oakleaf_encounter(GameState.OAKLEAF_BOSS_ID), "Boss remains unavailable before all regular Bandits")
	var blocked_second := GameState.record_oakleaf_encounter_victory("oakleaf_bandits2")
	_expect(String(blocked_second.get("action", "")) == "blocked", "Bandits2 cannot skip the First Bandit prerequisite")
	_expect(GameState.get_oakleaf_defeated_bandit_count() == 0, "blocked encounters cannot mutate an independent defeated flag")


func _verify_regular_bandits() -> void:
	GameState.current_scene_path = OAKLEAF_SCENE
	GameState.current_map = OAKLEAF_SCENE
	var source_positions := {
		"oakleaf_bandits1": Vector2(295.0, 301.0),
		"oakleaf_bandits2": Vector2(456.0, 312.0),
		"oakleaf_bandits3": Vector2(624.0, 289.0),
		"oakleaf_bandits4": Vector2(782.0, 330.0),
		"oakleaf_bandits5": Vector2(947.0, 298.0),
	}

	_win_encounter("oakleaf_bandits1", source_positions["oakleaf_bandits1"])
	_expect(GameState.current_task_index == 2, "First Bandit victory alone does not complete or skip Task 3")
	var first_transition := GameState.advance_task_and_save({
		"type": "quest_updated",
		"key": "quest:oakleaf:first-bandit:defeated",
		"title": "Defeat All Bandits",
		"description": "First Bandit defeated. Continue defeating the Oakleaf Bandits.",
		"source": "quest_ui",
		"reason": "first_bandit_victory",
	})
	_expect(bool(first_transition.get("advanced", false)), "First Bandit activates the combined regular-Bandit checkpoint")
	_expect(GameState.current_task_index == GameState.OAKLEAF_BANDIT_TASK_INDEX, "Task 3 stays active after First Bandit")
	_expect(GameState.get_current_quest_text() == "Defeat All Bandits", "current quest remains Defeat All Bandits after First Bandit")
	_expect(GameState.total_quests_completed == 2, "First Bandit is an internal milestone, not an extra completed quest")
	_expect(_count_event_title("Task 3 Complete") == 0, "Task 3 Complete is not emitted after First Bandit")
	_expect(GameState.is_oakleaf_bandit_defeated("oakleaf_bandits1"), "Bandit 1 owns its defeated flag")
	for encounter_id in GameState.OAKLEAF_BANDIT_IDS.slice(1):
		_expect(GameState.can_start_oakleaf_encounter(encounter_id), "%s remains independently available after Bandit 1" % encounter_id)
	_checkpoint("after Bandit 1")

	_win_encounter("oakleaf_bandits2", source_positions["oakleaf_bandits2"])
	_assert_duplicate_bandit_is_idempotent("oakleaf_bandits2")
	_expect(GameState.current_task_index == GameState.OAKLEAF_BANDIT_TASK_INDEX, "Task 3 stays active after Bandit 2")
	_expect(GameState.total_quests_completed == 2, "Bandit 2 does not inflate player-facing completed quests")
	_expect(not GameState.can_start_oakleaf_encounter("oakleaf_bandits2"), "defeated Bandit 2 is no longer available")
	_expect(GameState.can_start_oakleaf_encounter("oakleaf_bandits3"), "undefeated Bandit 3 remains available")
	_expect(not GameState.can_start_oakleaf_encounter(GameState.OAKLEAF_BOSS_ID), "Boss stays locked after only two regular Bandits")
	_checkpoint("after Bandit 2")

	_win_encounter("oakleaf_bandits3", source_positions["oakleaf_bandits3"])
	_expect(GameState.current_task_index == GameState.OAKLEAF_BANDIT_TASK_INDEX, "Task 3 stays active after Bandit 3")
	_expect(GameState.total_quests_completed == 2, "Bandit 3 remains an internal milestone")
	_expect(_count_event_title("Task 3 Complete") == 0, "Task 3 Complete is absent after Bandit 3")

	_win_encounter("oakleaf_bandits4", source_positions["oakleaf_bandits4"])
	_expect(GameState.current_task_index == GameState.OAKLEAF_BANDIT_TASK_INDEX, "Task 3 stays active after Bandit 4")
	_expect(GameState.get_oakleaf_defeated_bandit_count() == 4, "four independent Bandit flags are persisted after Bandit 4")
	_expect(GameState.can_start_oakleaf_encounter("oakleaf_bandits5"), "Bandit 5 remains available after Bandit 4")
	_expect(not GameState.can_start_oakleaf_encounter(GameState.OAKLEAF_BOSS_ID), "Boss remains unavailable until Bandit 5")
	_expect(_count_event_title("Task 3 Complete") == 0, "Task 3 Complete is absent after Bandit 4")
	_checkpoint("after Bandit 4")

	_win_encounter("oakleaf_bandits5", source_positions["oakleaf_bandits5"])
	_expect(GameState.are_all_oakleaf_bandits_defeated(), "all five regular Bandits have independent defeated flags")
	_expect(GameState.get_oakleaf_defeated_bandit_count() == 5, "regular Bandit count is exactly five")
	_expect(GameState.current_task_index == GameState.OAKLEAF_BOSS_TASK_INDEX, "all five regular Bandits unlock the Boss checkpoint")
	_expect(GameState.get_current_quest_text() == "Defeat the Boss Bandit", "current quest becomes Defeat the Boss Bandit")
	_expect(GameState.total_quests_completed == 2, "all five normal Bandits still do not complete Task 3 without Boss")
	_expect(_count_event_title("Task 3 Complete") == 0, "Task 3 Complete remains absent before Boss victory")
	for encounter_id in GameState.OAKLEAF_BANDIT_IDS:
		_expect(not GameState.can_start_oakleaf_encounter(encounter_id), "%s cannot replay after its independent victory" % encounter_id)
	_expect(GameState.can_start_oakleaf_encounter(GameState.OAKLEAF_BOSS_ID), "Boss becomes available only after five-of-five")
	_checkpoint("after all five regular Bandits")


func _verify_boss_and_return_teacher() -> void:
	var boss_position := Vector2(1088.0, 302.0)
	_win_encounter(GameState.OAKLEAF_BOSS_ID, boss_position)
	_expect(GameState.oakleaf_boss_defeated, "Boss defeated state persists independently")
	_expect(GameState.oakleaf_return_to_teacher, "Boss victory activates the required Teacher return")
	_expect(GameState.current_task_index == GameState.OAKLEAF_RETURN_TEACHER_TASK_INDEX, "Boss victory advances to Return to the Teacher")
	_expect(GameState.get_current_quest_text() == "Return to the Teacher", "post-Boss current quest is Return to the Teacher")
	_expect(GameState.total_quests_completed == 3, "all five Bandits plus Boss complete Task 3 exactly once")
	_expect(_count_event_title("Task 3 Complete") == 1, "Task 3 Complete is emitted once after Boss victory")
	_expect(not GameState.can_start_oakleaf_encounter(GameState.OAKLEAF_BOSS_ID), "Boss cannot trigger a duplicate battle after victory")
	var duplicate_boss := GameState.record_oakleaf_encounter_victory(GameState.OAKLEAF_BOSS_ID)
	_expect(String(duplicate_boss.get("action", "")) == "blocked", "duplicate Boss completion is rejected")
	_expect(GameState.total_quests_completed == 3 and _count_event_title("Task 3 Complete") == 1, "duplicate Boss completion cannot inflate task state or notification count")
	_checkpoint("after Boss")

	GameState.current_scene_path = TEACHER_HOUSE_SCENE
	GameState.current_map = TEACHER_HOUSE_SCENE
	GameState.player_position = Vector2(84.0, 111.0)
	var teacher_return := GameState.complete_oakleaf_teacher_return()
	_expect(bool(teacher_return.get("changed", false)), "actual post-Boss Teacher interaction completes the Oakleaf return")
	_expect(GameState.city_of_knowledge_unlocked, "Teacher interaction unlocks the City of Knowledge")
	_expect(not GameState.oakleaf_return_to_teacher, "Teacher return flag is consumed exactly once")
	_expect(GameState.current_task_index == GameState.CITY_OF_KNOWLEDGE_TASK_INDEX, "Teacher return advances to the City objective")
	_expect(GameState.get_current_quest_text() == "Go to the City of Knowledge / School", "current quest becomes Go to City of Knowledge")
	_expect(GameState.total_quests_completed == 4, "Teacher return counts once as Task 4")
	_expect(_count_event_title("Task 4 Complete") == 1, "Task 4 completion is emitted once after Teacher interaction")
	var duplicate_return := GameState.complete_oakleaf_teacher_return()
	_expect(not bool(duplicate_return.get("changed", false)), "duplicate Teacher return is rejected")
	_expect(GameState.total_quests_completed == 4 and _count_event_title("Task 4 Complete") == 1, "duplicate Teacher return cannot inflate completion or notifications")
	_checkpoint("after Return Teacher / City unlock")


func _win_encounter(encounter_id: String, source_position: Vector2) -> void:
	_expect(GameState.can_start_oakleaf_encounter(encounter_id), "%s satisfies its exact story prerequisite" % encounter_id)
	GameState.player_position = source_position
	var context := GameState.begin_encounter({
		"encounter_id": encounter_id,
		"source_scene_path": OAKLEAF_SCENE,
		"source_position": source_position,
		"quest_checkpoint": GameState.current_task_index,
		"question_scope": {"difficulty": "Easy"},
	})
	_expect(String(context.get("encounter_id", "")) == encounter_id, "%s keeps its canonical encounter identity" % encounter_id)
	_expect(context.get("question_scope", {}) == {"grade": "Grade 4", "difficulty": "Easy"}, "%s resolves current Student Grade + Oakleaf Easy question scope" % encounter_id)
	var result := GameState.record_encounter_victory()
	var oakleaf: Variant = result.get("oakleaf", {})
	_expect(oakleaf is Dictionary and bool(oakleaf.get("changed", false)), "%s records one canonical victory" % encounter_id)
	_expect(GameState.get_active_encounter_context().is_empty(), "%s clears only its completed encounter context" % encounter_id)
	_expect(GameState.current_scene_path == OAKLEAF_SCENE, "%s restores the canonical Oakleaf source scene" % encounter_id)
	_expect(GameState.player_position.is_equal_approx(source_position), "%s restores its exact valid source spawn" % encounter_id)
	_expect(GameState.get_mode() == GameState.GameMode.EXPLORATION, "%s returns to exploration mode after victory" % encounter_id)


func _assert_duplicate_bandit_is_idempotent(encounter_id: String) -> void:
	var defeated_before := GameState.get_oakleaf_defeated_bandit_count()
	var completed_before := GameState.total_quests_completed
	var duplicate_result := GameState.record_oakleaf_encounter_victory(encounter_id)
	_expect(String(duplicate_result.get("action", "")) == "blocked", "%s duplicate victory is rejected" % encounter_id)
	_expect(GameState.get_oakleaf_defeated_bandit_count() == defeated_before, "%s duplicate cannot mutate another Bandit's state" % encounter_id)
	_expect(GameState.total_quests_completed == completed_before, "%s duplicate cannot inflate completed tasks" % encounter_id)


func _checkpoint(label: String) -> void:
	var expected := _snapshot_oakleaf_state()
	var save_path := GameState.save_game()
	_expect(not save_path.is_empty(), "%s creates a QA-local JSON save" % label)
	if save_path.is_empty():
		return
	_checkpoint_labels.append(label)
	_expect(save_path.begins_with(GameState.LOCAL_QA_SAVE_DIRECTORY + "/"), "%s never writes the production save namespace" % label)
	_expect(FileAccess.file_exists(save_path), "%s save exists before reload" % label)
	var serialized := GameState.peek_save_data(save_path)
	_expect(bool(serialized.get("loadable", false)), "%s save passes the canonical ownership/resource validator" % label)
	_expect(int(serialized.get("current_task_index", -1)) == int(expected.task_index), "%s serializes the exact task checkpoint" % label)
	_expect(String(serialized.get("current_quest", "")) == String(expected.quest), "%s serializes the exact current quest" % label)
	_expect(serialized.get("oakleaf_defeated_bandits", {}) == expected.bandits, "%s serializes independent Bandit flags" % label)
	_expect(bool(serialized.get("oakleaf_boss_defeated", false)) == bool(expected.boss), "%s serializes Boss state" % label)
	_expect(bool(serialized.get("oakleaf_return_to_teacher", false)) == bool(expected.return_teacher), "%s serializes Teacher-return state" % label)
	_expect(bool(serialized.get("city_of_knowledge_unlocked", false)) == bool(expected.city), "%s serializes City unlock state" % label)
	_expect(int(serialized.get("total_quests_completed", -1)) == int(expected.completed_count), "%s serializes canonical completion count" % label)

	_corrupt_runtime_state_for_reload_probe(expected)
	var loaded := GameState.load_save(save_path, false)
	_expect(not loaded.is_empty(), "%s reloads through the public Load API" % label)
	_assert_snapshot_restored(label, expected)


func _snapshot_oakleaf_state() -> Dictionary:
	var save_data := GameState.build_save_data()
	return {
		"task_index": GameState.current_task_index,
		"quest": GameState.get_current_quest_text(),
		"scene": GameState.current_scene_path,
		"position": GameState.player_position,
		"bandits": GameState.oakleaf_defeated_bandits.duplicate(true),
		"boss": GameState.oakleaf_boss_defeated,
		"return_teacher": GameState.oakleaf_return_to_teacher,
		"city": GameState.city_of_knowledge_unlocked,
		"completed_count": GameState.total_quests_completed,
		"completion_ids": save_data.get("completed_player_facing_tasks", {}).duplicate(true),
	}


func _corrupt_runtime_state_for_reload_probe(expected: Dictionary) -> void:
	GameState.current_task_index = GameState.tasks.size()
	GameState.current_quest = "CORRUPTED QA STATE"
	GameState.current_scene_path = PLAYER_HOUSE_SCENE if String(expected.scene) != PLAYER_HOUSE_SCENE else OAKLEAF_SCENE
	GameState.player_position = Vector2(-9999.0, -9999.0)
	for encounter_id in GameState.OAKLEAF_BANDIT_IDS:
		GameState.oakleaf_defeated_bandits[encounter_id] = not bool(expected.bandits.get(encounter_id, false))
	GameState.oakleaf_boss_defeated = not bool(expected.boss)
	GameState.oakleaf_return_to_teacher = not bool(expected.return_teacher)
	GameState.city_of_knowledge_unlocked = not bool(expected.city)
	GameState.total_quests_completed = 999


func _assert_snapshot_restored(label: String, expected: Dictionary) -> void:
	_expect(GameState.current_task_index == int(expected.task_index), "%s reload restores the exact task index" % label)
	_expect(GameState.get_current_quest_text() == String(expected.quest), "%s reload restores the authoritative Current Quest" % label)
	_expect(GameState.current_quest == String(expected.quest), "%s reload reconciles the persisted quest presentation" % label)
	_expect(GameState.current_scene_path == String(expected.scene), "%s reload restores a valid scene" % label)
	_expect(ResourceLoader.exists(GameState.current_scene_path), "%s restored scene resource exists" % label)
	_expect(GameState.player_position.is_equal_approx(expected.position), "%s reload restores the saved player spawn" % label)
	_expect(GameState.oakleaf_defeated_bandits == expected.bandits, "%s reload preserves every independent Bandit flag" % label)
	_expect(GameState.oakleaf_boss_defeated == bool(expected.boss), "%s reload preserves Boss state" % label)
	_expect(GameState.oakleaf_return_to_teacher == bool(expected.return_teacher), "%s reload preserves Teacher-return state" % label)
	_expect(GameState.city_of_knowledge_unlocked == bool(expected.city), "%s reload preserves City unlock state" % label)
	_expect(GameState.total_quests_completed == int(expected.completed_count), "%s reload preserves canonical completion count" % label)
	var reloaded_completion_ids: Variant = GameState.build_save_data().get("completed_player_facing_tasks", {})
	_expect(reloaded_completion_ids == expected.completion_ids, "%s reload preserves idempotent canonical completion IDs" % label)
	for encounter_id in GameState.OAKLEAF_BANDIT_IDS:
		var defeated := bool(expected.bandits.get(encounter_id, false))
		var expected_available := not defeated and GameState.current_task_index == GameState.OAKLEAF_BANDIT_TASK_INDEX
		if encounter_id == GameState.OAKLEAF_BANDIT_IDS[0]:
			expected_available = not defeated and GameState.current_task_index == 2
		_expect(GameState.can_start_oakleaf_encounter(encounter_id) == expected_available, "%s reload keeps %s availability consistent with its own flag/prerequisite" % [label, encounter_id])
	var expected_boss_available := not bool(expected.boss) \
			and GameState.current_task_index == GameState.OAKLEAF_BOSS_TASK_INDEX \
			and GameState.are_all_oakleaf_bandits_defeated()
	_expect(GameState.can_start_oakleaf_encounter(GameState.OAKLEAF_BOSS_ID) == expected_boss_available, "%s reload preserves the five-of-five Boss prerequisite" % label)


func _verify_final_completion_identity() -> void:
	var ids: Variant = GameState.build_save_data().get("completed_player_facing_tasks", {})
	_expect(ids is Dictionary, "completion identity is persisted as a canonical ID set")
	if ids is Dictionary:
		_expect(ids.size() == 4, "exactly four player-facing Oakleaf tasks are complete")
		_expect(bool(ids.get("tutorial", false)), "completion set includes Tutorial")
		_expect(bool(ids.get("talk-to-the-teacher", false)), "completion set includes required Teacher interaction")
		_expect(bool(ids.get("oakleaf-bandits", false)), "completion set includes combined Bandits + Boss Task 3")
		_expect(bool(ids.get("oakleaf-return-to-teacher", false)), "completion set includes Teacher return / City unlock")
		for encounter_id in GameState.OAKLEAF_BANDIT_IDS:
			_expect(not ids.has(encounter_id), "%s stays an internal milestone instead of inflating quest count" % encounter_id)
	_expect(_checkpoint_labels == [
		"after Tutorial",
		"after Teacher interaction",
		"after Bandit 1",
		"after Bandit 2",
		"after Bandit 4",
		"after all five regular Bandits",
		"after Boss",
		"after Return Teacher / City unlock",
	], "all eight required Oakleaf Save/Load checkpoints ran in story order")


func _verify_notification_and_dialogue_placement() -> void:
	# Use a dedicated instance so notifications queued during the state walkthrough
	# cannot race this focused geometry probe.
	var manager := QuestNotificationManagerScript.new()
	manager.name = "QaNotificationGeometryProbe"
	add_child(manager)
	await get_tree().process_frame
	_expect(manager != null, "shared QuestNotificationManager script instantiates")
	if manager != null:
		manager.call("show_task_completed", "Task Complete", "QA layout", "qa:layout:complete")
		for _frame in range(8):
			await get_tree().process_frame
		var completion_panel := manager.get("_task_complete_panel") as Control
		_expect(completion_panel != null and completion_panel.visible, "completion notification renders through the shared compact panel")
		if completion_panel != null:
			_expect(completion_panel.position.y <= 16.0, "Task Complete notification is positioned at the top")
			_expect(completion_panel.size.x <= 460.0 and completion_panel.size.y <= 96.0, "Task Complete notification remains compact")

		manager.call("_on_progression_session_reset", "qa_layout_probe")
		manager.call("show_quest_updated", "New Quest", "Defeat All Bandits", "qa:layout:objective")
		for _frame in range(8):
			await get_tree().process_frame
		var objective_panel := manager.get("_task_complete_panel") as Control
		_expect(objective_panel != null and objective_panel.visible, "next-objective notification renders through the shared compact panel")
		if objective_panel != null:
			_expect(objective_panel.position.y <= 16.0, "New Quest / next-objective notification is positioned at the top")
			_expect(objective_panel.size.x <= 460.0 and objective_panel.size.y <= 104.0, "next-objective notification remains compact")
		manager.call("_on_progression_session_reset", "qa_layout_probe_complete")
		manager.queue_free()

	var quest_ui_source := FileAccess.get_file_as_string("res://world/QuestUI.gd")
	_expect(quest_ui_source.contains("dialogue_panel.anchor_top = 1.0") and quest_ui_source.contains("dialogue_panel.anchor_bottom = 1.0"), "shared Teacher/NPC dialogue panel is bottom-anchored")
	_expect(quest_ui_source.contains("dialogue_panel.offset_bottom = -40.0"), "shared story dialogue keeps a bottom screen margin")
	var notification_source := FileAccess.get_file_as_string("res://scripts/quest_notification_manager.gd")
	_expect(notification_source.contains('"bottom" if is_trigger else "top"'), "Teacher task/story trigger remains bottom-center while objective/completion toasts remain top")
	var encounter_source := FileAccess.get_file_as_string("res://scripts/oakleaf_battle_encounter.gd")
	_expect(encounter_source.contains("Boss Bandit") and encounter_source.contains("begin_dialogue"), "Boss victory uses actual shared bottom dialogue before disappearing")


func _on_task_state_changed(previous_index: int, current_index: int, event: Dictionary) -> void:
	var captured := event.duplicate(true)
	captured["observed_previous_index"] = previous_index
	captured["observed_current_index"] = current_index
	_task_events.append(captured)


func _on_canonical_activity_boundary(event: Dictionary) -> void:
	_activity_events.append(event.duplicate(true))


func _count_event_title(title: String) -> int:
	var count := 0
	for event in _task_events + _activity_events:
		if String(event.get("title", "")) == title:
			count += 1
	return count


func _current_save_paths() -> Dictionary:
	var paths: Dictionary = {}
	for entry in GameState.list_saves():
		var path := String(entry.get("save_path", ""))
		if not path.is_empty():
			paths[path] = true
	return paths


func _cleanup_disposable_saves() -> Dictionary:
	var deleted := 0
	var failed := 0
	for entry in GameState.list_saves():
		var path := String(entry.get("save_path", ""))
		if path.is_empty() or _baseline_save_paths.has(path):
			continue
		if GameState.delete_save(path):
			deleted += 1
		else:
			failed += 1
	return {"deleted": deleted, "failed": failed}


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var cleanup := _cleanup_disposable_saves()
	_expect(int(cleanup.failed) == 0, "all disposable QA-local save files are cleaned up")
	var failed := 0
	for check in _checks:
		if not bool(check.get("passed", false)):
			failed += 1
	var report := {
		"passed": _checks.size() - failed,
		"failed": failed,
		"checks": _checks,
		"checkpoint_count": _checkpoint_labels.size(),
		"qa_local_only": HttpApi != null and HttpApi.is_local_qa_mode(),
		"production_writes": 0,
		"cleanup": cleanup,
		"manual_gap": "Physical walking, ACT/E/Space proximity, live dialogue advancement, battle answering/animations, and visual spawn placement still require the owner F5 walkthrough.",
	}
	var report_file := FileAccess.open("user://oakleaf_story_runtime_test_result.json", FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report))
		report_file.close()
	print("OAKLEAF_STORY_RUNTIME_TEST " + JSON.stringify(report))
	# Keep the process alive briefly so Godot MCP can collect the full report.
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
