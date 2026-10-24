extends Node

const QA_STUDENT_ID := "88003001"
const QA_PARENT_ID := "880301"
const OTHER_STUDENT_ID := "88003002"
const OTHER_PARENT_ID := "880302"

var _failures: Array[String] = []
var _checks := 0
var _qa_directory := ""
var _previous_save_directory := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(HttpApi.is_local_qa_profile_active(), "snapshot/replay test starts in local-only mode before autoload initialization")
	if not HttpApi.is_local_qa_profile_active():
		await _finish()
		return
	HttpApi.enable_local_qa_mode("http://127.0.0.1:5000")
	RemoteSync.enable_local_qa_mode()
	GameState.enable_local_qa_mode()
	_previous_save_directory = GameState.get_save_directory()
	_qa_directory = "%s/manual_snapshot_replay_%d_%d" % [
		GameState.LOCAL_QA_SAVE_DIRECTORY, OS.get_process_id(), Time.get_ticks_usec()
	]
	var absolute_directory := ProjectSettings.globalize_path(_qa_directory)
	_expect(not DirAccess.dir_exists_absolute(absolute_directory), "fixture refuses to reuse an existing save directory")
	if DirAccess.dir_exists_absolute(absolute_directory):
		await _finish()
		return
	_expect(DirAccess.make_dir_recursive_absolute(absolute_directory) == OK, "creates only its unique QA save directory")
	GameState.set("_save_directory", _qa_directory)
	RemoteSync.set("_pending_file", _qa_directory + "/pending.json")
	GameState.start_new_game({
		"player_name": "Snapshot QA Student",
		"gender": "female",
		"grade_level": "Grade 4",
		"student_id": QA_STUDENT_ID,
		"parent_id": QA_PARENT_ID,
		"learning_cycle": {"version": 8, "started_at": "2026-09-01T00:00:00Z"},
	}, false)
	GameState.device_installation_id = "manual-snapshot-qa-device"
	GameState.current_scene_path = GameState.DEEPEST_FOREST_PATH
	GameState.current_map = "Deepest Forest"
	GameState.player_position = Vector2(113, 227)
	GameState.current_task_index = GameState.DEEP_FOREST_BANDIT_TASK_INDEX
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.city_of_knowledge_unlocked = true
	GameState.city_first_arrival_seen = true
	GameState.city_school_stage_complete = true
	GameState.city_next_path_unlocked = true
	GameState.city_school_stage = 2
	GameState.current_lives = 2
	GameState.score = 41
	GameState.correct_answers = 5
	GameState.incorrect_answers = 3
	GameState.total_questions = 8
	GameState.lesson_progress = 6
	GameState.progress_percentage = 37
	GameState.total_play_time = 765
	GameState._completed_player_facing_tasks = {"city_school": true}
	var first_slot := GameState.save_manual_game()
	_expect(first_slot.begins_with(_qa_directory + "/"), "first explicit manual save creates an owned visible slot")
	var first_bytes := _read_text(first_slot)
	var first_snapshot: Dictionary = GameState.peek_save_data(first_slot)

	for encounter_id in GameState.DEEP_FOREST_BANDIT_IDS:
		var victory: Dictionary = GameState.record_progression_encounter_victory(String(encounter_id), false)
		_expect(bool(victory.get("changed", false)), "later progression can advance encounter %s" % String(encounter_id))
	GameState.current_scene_path = "res://scenes/2nd Village/Pinehill Village.tscn"
	GameState.current_map = "Pinehill Village"
	GameState.player_position = Vector2(337, 449)
	GameState.current_task_index = GameState.PINEHILL_OLD_MAN_TASK_INDEX
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.current_lives = 1
	GameState.score = 83
	GameState.correct_answers = 9
	GameState.incorrect_answers = 5
	GameState.total_questions = 14
	GameState.pinehill_old_man_completed = false
	var second_slot := GameState.save_manual_game()
	_expect(second_slot.begins_with(_qa_directory + "/") and second_slot != first_slot, "later manual save creates a separate slot")
	var second_bytes := _read_text(second_slot)
	var hidden_path := String(GameState.call("_get_current_student_save_path", QA_STUDENT_ID))
	var hidden_bytes := _read_text(hidden_path)
	_expect(int(GameState.peek_save_data(second_slot).get("current_task_index", -1)) == GameState.PINEHILL_OLD_MAN_TASK_INDEX, "newest manual slot contains later Pinehill state")
	_expect(GameState.list_saves().size() == 2, "only the two explicit manual saves are visible")
	GameState.pinehill_old_man_completed = true
	GameState.current_task_index = GameState.PINEHILL_BANDIT_TASK_INDEX
	GameState.current_quest = GameState.get_current_quest_text()
	for encounter_id in GameState.PINEHILL_BANDIT_IDS:
		var guard_victory: Dictionary = GameState.record_progression_encounter_victory(String(encounter_id), false)
		_expect(bool(guard_victory.get("changed", false)), "later Pinehill progression can advance guard %s" % String(encounter_id))
	_expect(GameState.current_task_index == GameState.WIZARD_TASK_INDEX, "four later Guard victories unlock the Wizard stage")
	var wizard_victory: Dictionary = GameState.record_progression_encounter_victory("pinehill_wizard", false)
	_expect(bool(wizard_victory.get("changed", false)), "later Wizard victory advances the return stage")
	var pinehill_selected: Dictionary = GameState.load_save(second_slot, false)
	_expect(not pinehill_selected.is_empty(), "older Pinehill manual slot remains independently loadable")
	_expect(GameState.current_task_index == GameState.PINEHILL_OLD_MAN_TASK_INDEX and not GameState.pinehill_old_man_completed, "older Pinehill slot restores its pre-Old-Lady checkpoint")
	_expect(not GameState.are_all_progression_bandits_defeated("pinehill") and not GameState.wizard_defeated, "older Pinehill slot clears only later Guard/Wizard progression from runtime state")
	_expect(_read_text(second_slot) == second_bytes and _read_text(hidden_path) == hidden_bytes, "restoring the older Pinehill slot never mutates it or the newer hidden checkpoint")

	GameState.current_task_index = GameState.tasks.size()
	GameState.journey_complete = true
	GameState.player_position = Vector2(999, 999)
	var selected: Dictionary = GameState.load_save(first_slot, false)
	_expect(not selected.is_empty(), "selected older manual slot loads successfully")
	_expect(GameState.current_scene_path == "res://scenes/city_of_knowledge.tscn" and GameState.current_map == "Deepest Forest", "selected legacy Forest slot restores into the shared City scene while preserving its semantic map label")
	_expect(GameState.player_position.is_equal_approx(Vector2(113, 227)), "selected slot restores its exact saved position")
	_expect(GameState.current_task_index == GameState.DEEP_FOREST_BANDIT_TASK_INDEX and GameState.current_quest == String(first_snapshot.get("current_quest", "")), "selected slot restores its exact task and quest")
	_expect(GameState.current_lives == 2 and GameState.score == 41 and GameState.correct_answers == 5 and GameState.incorrect_answers == 3 and GameState.total_questions == 8, "selected slot restores its saved lives and answer/score counters")
	_expect(not GameState.pinehill_unlocked and not GameState.are_all_progression_bandits_defeated("deep_forest"), "loading pre-victory slot restores its locked Pinehill/undefeated Forest state")
	_expect(GameState._completed_player_facing_tasks == first_snapshot.get("completed_player_facing_tasks", {}), "selected slot restores completed player-facing tasks")
	_expect(_read_text(first_slot) == first_bytes and _read_text(second_slot) == second_bytes, "loading never mutates either manual slot")
	_expect(_read_text(hidden_path) == hidden_bytes, "newer hidden checkpoint does not override or mutate the selected slot")

	GameState.student_id = OTHER_STUDENT_ID
	GameState.parent_id = OTHER_PARENT_ID
	_expect(GameState.peek_save_data(first_slot).is_empty(), "another Student cannot inspect the selected Student's manual slot")
	_expect(GameState.load_save(first_slot, false).is_empty(), "another Student cannot load the selected Student's manual slot")
	_expect(GameState.load_save(hidden_path, false).is_empty(), "another Student cannot load the selected Student's hidden checkpoint")
	GameState.student_id = QA_STUDENT_ID
	GameState.parent_id = QA_PARENT_ID

	GameState.set_learning_cycle({"version": 7, "started_at": "2026-08-01T00:00:00Z"})
	GameState.current_task_index = GameState.PINEHILL_BANDIT_TASK_INDEX
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.current_scene_path = "res://scenes/2nd Village/Pinehill Village.tscn"
	GameState.current_map = "Pinehill Village"
	GameState.player_position = Vector2(202, 366)
	GameState.deep_forest_defeated_bandits.clear()
	GameState.pinehill_unlocked = true
	GameState.pinehill_old_man_completed = true
	GameState.pinehill_defeated_bandits = {"pinehill_bandits1": true}
	var old_result := {
		"student_id": QA_STUDENT_ID,
		"parent_id": QA_PARENT_ID,
		"learning_cycle_version": 7,
		"result_event_id": "prior-cycle-answer",
		"score": 0,
	}
	var old_activity := {
		"student_id": QA_STUDENT_ID,
		"parent_id": QA_PARENT_ID,
		"learning_cycle_version": 7,
		"event_key": "prior-cycle-task",
		"payload": {"event_type": "task_completed"},
	}
	_expect(GameState.stage_pending_academic_result(old_result), "pre-replay academic fixture stages in its original cycle")
	_expect(GameState.stage_pending_academic_activity(old_activity), "pre-replay activity fixture stages in its original cycle")
	var prior_cycle_slot := GameState.save_manual_game()
	var prior_cycle_bytes := _read_text(prior_cycle_slot)
	var authoritative_cycle := {"version": 8, "started_at": "2026-09-01T00:00:00Z"}
	var load_save_accepts_cycle := false
	for method_info: Dictionary in GameState.get_method_list():
		if String(method_info.get("name", "")) == "load_save":
			load_save_accepts_cycle = (method_info.get("args", []) as Array).size() >= 3
	_expect(load_save_accepts_cycle, "selected-save load accepts the verified authoritative Learning Cycle descriptor")
	var replay_load: Variant = {}
	if load_save_accepts_cycle:
		replay_load = GameState.call("load_save", prior_cycle_slot, false, authoritative_cycle)
	_expect(replay_load is Dictionary and not (replay_load as Dictionary).is_empty(), "valid prior-cycle manual slot loads with a server-authoritative current cycle")
	_expect(GameState.learning_cycle_version == 8 and GameState.learning_cycle_started_at == String(authoritative_cycle.started_at), "historical gameplay never rewinds the authenticated current cycle")
	_expect(GameState.get("historical_replay_mode") == true and int(GameState.get("replay_origin_learning_cycle_version")) == 7, "runtime marks replay and retains its origin cycle")
	_expect(GameState.current_task_index == GameState.PINEHILL_BANDIT_TASK_INDEX and GameState.current_scene_path == "res://scenes/2nd Village/Pinehill Village.tscn" and GameState.player_position.is_equal_approx(Vector2(202, 366)), "historical replay restores its own exact later-quest gameplay snapshot")
	_expect(GameState.get_pending_academic_event_count() == 0, "prior-cycle pending answer/activity data is discarded")
	_expect(_read_text(prior_cycle_slot) == prior_cycle_bytes, "loading a prior-cycle slot leaves its source file unchanged")
	_expect(not GameState.stage_pending_academic_result({"student_id": QA_STUDENT_ID, "parent_id": QA_PARENT_ID, "learning_cycle_version": 8, "result_event_id": "replay-answer"}), "historical replay cannot stage a current-cycle answer")
	_expect(not GameState.stage_pending_academic_activity({"student_id": QA_STUDENT_ID, "parent_id": QA_PARENT_ID, "learning_cycle_version": 8, "event_key": "replay-task"}), "historical replay cannot stage a current-cycle task event")
	_expect(GameState.get_pending_academic_event_count() == 0, "replay event staging leaves no current-cycle academic payload")
	_expect(RemoteSync.call("_build_playtime_start_payload", {}).get("student_id", "") == QA_STUDENT_ID, "playtime/Screen Time session identity remains available during replay")
	var replay_data := GameState.build_save_data()
	_expect(bool(replay_data.get("historical_replay_mode", false)) and int(replay_data.get("replay_origin_learning_cycle_version", -1)) == 7, "replay-created snapshots keep the persistent historical marker")
	var pending_file := String(RemoteSync.get("_pending_file"))
	var pending_sentinel := "[{\"qa_sentinel\":\"historical-replay-must-not-commit\"}]"
	var pending_handle := FileAccess.open(pending_file, FileAccess.WRITE)
	_expect(pending_handle != null, "creates a sentinel only inside this isolated QA outbox")
	if pending_handle != null:
		pending_handle.store_string(pending_sentinel)
		pending_handle.close()
	var original_remote_qa_mode := bool(RemoteSync.get("local_qa_only"))
	RemoteSync.set("local_qa_only", false)
	_expect(not bool(RemoteSync.call("_remote_writes_blocked")), "historical replay itself does not disable independent Screen Time writes")
	var replay_commit_fixture := replay_data.duplicate(true)
	replay_commit_fixture["save_kind"] = "manual"
	_expect(not bool(RemoteSync.call("_commit_academic_save_data", replay_commit_fixture)), "historical replay cannot queue a progress commit even when remote-write gates are otherwise open")
	RemoteSync.call("_on_save_created", replay_commit_fixture)
	_expect(_read_text(pending_file) == pending_sentinel, "historical replay save-created signal leaves the academic outbox unchanged")
	RemoteSync.set("local_qa_only", original_remote_qa_mode)
	var next_replay_slot := GameState.save_manual_game()
	var next_replay_snapshot: Dictionary = GameState.peek_save_data(next_replay_slot)
	_expect(bool(next_replay_snapshot.get("historical_replay_mode", false)) and int(next_replay_snapshot.get("replay_origin_learning_cycle_version", -1)) == 7, "a new manual slot created during replay remains marked after persistence")
	_expect(_read_text(pending_file) == pending_sentinel, "explicit manual save during replay still does not enqueue an academic commit")
	_expect(GameState.list_saves().size() == 4, "only explicit manual save calls create visible slots during replay")
	var replay_lives := int((replay_load as Dictionary).get("current_lives", -1)) if replay_load is Dictionary else -1
	_expect(GameState.current_lives == replay_lives, "historical replay retains the selected slot's saved lives")
	_expect(bool(GameState.call("set_learning_cycle", authoritative_cycle)), "current cycle can be retained after replay operations")
	_expect(_read_text(prior_cycle_slot) == prior_cycle_bytes, "later replay saves do not change the old-cycle source slot")

	await _finish()


func _read_text(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if not _qa_directory.is_empty():
		_remove_directory_tree(ProjectSettings.globalize_path(_qa_directory))
	if not _previous_save_directory.is_empty():
		GameState.set("_save_directory", _previous_save_directory)
	if _failures.is_empty():
		print("MANUAL_SAVE_SNAPSHOT_REPLAY_TEST: PASS checks=%d" % _checks)
		await get_tree().create_timer(30.0).timeout
		get_tree().quit(0)
		return
	print("MANUAL_SAVE_SNAPSHOT_REPLAY_TEST: FAIL checks=%d failures=%d" % [_checks, _failures.size()])
	await get_tree().create_timer(30.0).timeout
	get_tree().quit(1)


func _remove_directory_tree(absolute_path: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if entry_name != "." and entry_name != "..":
			var child := absolute_path.path_join(entry_name)
			if directory.current_is_dir():
				_remove_directory_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry_name = directory.get_next()
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(absolute_path)
