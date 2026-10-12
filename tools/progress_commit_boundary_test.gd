extends Node

const RemoteSyncScript := preload("res://scripts/remote_sync.gd")
const QA_DIRECTORY_ROOT := "user://qa_local_saves"
const VALID_SCENE := "res://scenes/oak_leaf_village.tscn"


class FakeHttpApi extends Node:
	var requests: Array[Dictionary] = []

	func request_post(path: String, payload: Dictionary) -> Dictionary:
		requests.append({"path": path, "payload": payload.duplicate(true)})
		if path == "/api/playtime/end":
			return {"ok": true, "status": 200, "body": {"ok": true}}
		if path == "/api/playtime/start":
			return {"ok": true, "status": 201, "body": {
				"session_id": 97002,
				"session_credential": "qa-only-next-lease",
				"can_play": true,
				"remaining_minutes": 60,
				"remaining_seconds": 3600,
			}}
		return {"ok": true, "status": 201, "body": {"ok": true, "can_play": true}}


var _checks: Array[Dictionary] = []
var _test_directory := ""
var _pending_file := ""
var _fake_http: FakeHttpApi
var _remote: Node
var _original_save_directory := ""
var _original_device_id := ""
var _test_device_id := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var real_http := get_node_or_null("/root/HttpApi")
	var local_profile_proven := real_http != null \
			and real_http.has_method("is_local_qa_profile_active") \
			and bool(real_http.call("is_local_qa_profile_active")) \
			and String(real_http.get("base_url")) == "http://127.0.0.1:5000"
	_expect(local_profile_proven, "The runner enters local-only QA before autoload initialization")
	if not local_profile_proven:
		print("Progress commit QA stopped before fixtures because local-only startup was not proven.")
		await _finish()
		return

	var autoload_remote := get_node_or_null("/root/RemoteSync")
	if autoload_remote != null and autoload_remote.has_method("enable_local_qa_mode"):
		autoload_remote.call("enable_local_qa_mode")
	GameState.enable_local_qa_mode()
	_original_save_directory = GameState.get_save_directory()
	_original_device_id = String(GameState.get("device_installation_id"))
	_test_device_id = "qa-commit-device-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_directory = "%s/progress_commit_%d_%d" % [QA_DIRECTORY_ROOT, OS.get_process_id(), Time.get_ticks_usec()]
	_pending_file = "%s/pending_commit_%d_%d.json" % [QA_DIRECTORY_ROOT, OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_directory := ProjectSettings.globalize_path(_test_directory)
	if DirAccess.dir_exists_absolute(absolute_directory):
		_expect(false, "The QA fixture uses a new unique save directory")
		await _finish()
		return
	_expect(DirAccess.make_dir_recursive_absolute(absolute_directory) == OK, "Creates an isolated disposable QA save directory")
	GameState.set("_save_directory", _test_directory)
	GameState.set("device_installation_id", _test_device_id)
	_set_student("88002001", "880021")

	if real_http != null:
		real_http.free()
	_fake_http = FakeHttpApi.new()
	_fake_http.name = "HttpApi"
	get_tree().root.add_child(_fake_http)
	_remote = RemoteSyncScript.new()
	_remote.name = "ProgressCommitRemoteSyncHarness"
	_remote.set("_pending_file", _pending_file)
	get_tree().root.add_child(_remote)
	_remote.set("_pending_file", _pending_file)
	_remote.set("_current_playtime_session_id", 97001)
	_remote.set("_current_playtime_session_credential", "qa-only-synthetic-lease")
	_remote.set("_current_playtime_student_id", GameState.student_id)
	_remote.set("_current_playtime_parent_id", GameState.parent_id)
	_remote.set("_current_playtime_learning_cycle_version", GameState.learning_cycle_version)
	GameState.set("playtime_authorized", true)

	_test_pending_results_and_activities_wait_for_save()
	await _test_checkpoint_does_not_commit_progress()
	await _test_manual_save_commits_pending_progress_once()
	_test_manual_save_survives_unsaved_exit()
	await _test_voluntary_exit_discards_unsaved_run()
	await _test_daily_limit_uses_one_forced_save()
	await _finish()


func _test_pending_results_and_activities_wait_for_save() -> void:
	_fake_http.requests.clear()
	_remote.call("record_question_attempt", {
		"question_id": "qa-question-1",
		"difficulty": "Easy",
		"question_presented_at": "2026-10-11T01:00:00Z",
		"answer_submitted_at": "2026-10-11T01:00:04Z",
		"response_time_seconds": 4,
	}, true)
	_remote.call("_submit_canonical_task_activity", 0, 1, {
		"type": "task_completed",
		"key": "qa:task:complete:1",
		"title": "QA task",
		"description": "Synthetic local regression.",
	})
	_expect(_fake_http.requests.is_empty(), "Quiz answers and quest activity do not reach the Website before manual Save")
	_expect(GameState.has_method("get_pending_academic_event_count") and int(GameState.call("get_pending_academic_event_count")) >= 2,
		"Quiz and quest events remain pending in the current Student-owned run")


func _test_checkpoint_does_not_commit_progress() -> void:
	_fake_http.requests.clear()
	GameState.current_scene_path = VALID_SCENE
	GameState.current_map = VALID_SCENE
	var checkpoint_path := GameState.save_checkpoint()
	await get_tree().process_frame
	_expect(not checkpoint_path.is_empty() and _visible_save_count() == 0,
		"Hidden checkpoint remains available without creating a Load Game slot")
	_expect(_fake_http.requests.is_empty(), "Internal checkpoint writes do not sync academic progress")


func _test_manual_save_commits_pending_progress_once() -> void:
	_fake_http.requests.clear()
	var save_path := GameState.save_manual_game()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not save_path.is_empty() and _visible_save_count() == 1,
		"Manual Save creates exactly one visible manual slot")
	_expect(_count_requests("/api/game/progress") == 1,
		"Manual Save queues exactly one committed progress snapshot")
	_expect(_count_requests("/api/game/result") == 1,
		"Manual Save commits each pending quiz result once")
	_expect(_count_requests("/api/game/activity") == 1,
		"Manual Save commits each pending canonical activity once")
	_expect(GameState.has_method("get_pending_academic_event_count") and int(GameState.call("get_pending_academic_event_count")) == 0,
		"Successfully enqueued commit clears the current run's pending event buffer")
	var slot := GameState.peek_save_data(save_path)
	_expect((slot.get("pending_academic_results", []) as Array).is_empty()
			and (slot.get("pending_academic_activities", []) as Array).is_empty(),
		"Committed manual save does not replay its already-enqueued academic events when loaded later")


func _test_voluntary_exit_discards_unsaved_run() -> void:
	_set_student("88002002", "880022")
	_fake_http.requests.clear()
	_remote.call("record_question_attempt", {"question_id": "abandoned-result"}, false)
	GameState.save_checkpoint()
	await get_tree().process_frame
	await _remote.call("request_end_playtime_session")
	_expect(GameState.has_method("discard_unsaved_run"),
		"GameState exposes a separate voluntary-exit discard operation")
	if GameState.has_method("discard_unsaved_run"):
		GameState.call("discard_unsaved_run")
	_expect(_visible_save_count() == 0 and not FileAccess.file_exists(_current_checkpoint_path(GameState.student_id)),
		"Voluntary Exit removes only the unsaved run checkpoint and creates no Load Game entry")
	_expect(GameState.student_id == "88002002" and GameState.parent_id == "880022",
		"Voluntary Exit retains the linked Student identity")
	_expect(_fake_http.requests.filter(func(item: Dictionary) -> bool:
		return String(item.get("path", "")).begins_with("/api/game/")).is_empty(),
		"Voluntary Exit does not submit abandoned academic records")
	_expect(_count_requests("/api/playtime/end") == 1,
		"Voluntary Exit finalizes Screen Time independently of unsaved academic progress")


func _test_manual_save_survives_unsaved_exit() -> void:
	_set_student("88002004", "880024")
	var save_path := GameState.save_manual_game()
	var saved_before := GameState.peek_save_data(save_path)
	GameState.current_task_index = 10
	GameState.current_quest = GameState.get_current_quest_text()
	_remote.call("record_question_attempt", {"question_id": "abandoned-after-save"}, false)
	GameState.save_checkpoint()
	var discarded: Dictionary = GameState.discard_unsaved_run()
	var saves: Array[Dictionary] = GameState.list_saves()
	var saved_after := GameState.peek_save_data(save_path)
	_expect(bool(discarded.get("ok", false)) and saves.size() == 1 and String(saves[0].get("save_path", "")) == save_path,
		"Discarding a later unsaved run preserves the existing manual save slot")
	_expect(String(saved_before.get("scene_path", "")) == String(saved_after.get("scene_path", ""))
			and int(saved_before.get("current_task_index", -1)) == int(saved_after.get("current_task_index", -2)),
		"Unsaved progression does not overwrite the exact state of a prior manual save")


func _test_daily_limit_uses_one_forced_save() -> void:
	_set_student("88002003", "880023")
	_fake_http.requests.clear()
	const PINEHILL_SCENE := "res://scenes/2nd Village/Pinehill Village.tscn"
	GameState.current_scene_path = PINEHILL_SCENE
	GameState.current_map = PINEHILL_SCENE
	GameState.player_position = Vector2(321, 456)
	GameState.current_task_index = GameState.PINEHILL_BANDIT_TASK_INDEX
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.pinehill_unlocked = true
	GameState.pinehill_old_man_completed = true
	GameState.pinehill_defeated_bandits = {
		"pinehill_bandits1": false,
		"pinehill_bandits2": false,
		"pinehill_bandits3": false,
		"pinehill_bandits4": false,
	}
	GameState.current_lives = 2
	GameState.save_checkpoint()
	_remote.call("record_question_attempt", {"question_id": "daily-limit-result"}, true)
	GameState.battle_active = true
	GameState.set_mode(GameState.GameMode.BATTLE)
	GameState.current_scene_path = "res://scenes/male_vs_bandit.tscn"
	GameState.encounter_context = {
		"encounter_id": "pinehill_bandits1",
		"source_scene_path": PINEHILL_SCENE,
		"source_position": {"x": 321.0, "y": 456.0},
		"quest_checkpoint": GameState.PINEHILL_BANDIT_TASK_INDEX,
		"retry_count": 0,
	}
	GameState.set("playtime_authorized", false)
	_remote.set("_playtime_timeout_handled", false)
	await _remote.call("_on_time_limit_reached")
	await _remote.call("_on_time_limit_reached")
	await get_tree().process_frame
	var daily_entries: Array[Dictionary] = GameState.list_saves()
	var daily_count := 0
	var manual_count := 0
	for entry in daily_entries:
		if String(entry.get("save_kind", "")) == "daily_time_limit":
			daily_count += 1
		elif String(entry.get("save_kind", "")) == "manual":
			manual_count += 1
	_expect(daily_count == 1, "Daily time exhaustion creates one deterministic, loadable recovery entry")
	_expect(manual_count == 0, "Daily forced recovery does not masquerade as a manual save")
	var queued: Array = _remote.call("_load_pending")
	_expect(_count_queued_kind(queued, "progress_commit") == 1 and _count_queued_kind(queued, "result") == 1,
		"Daily expiry durably queues exactly one progress and result commit while time authorization is exhausted")
	var forced_data: Dictionary = {}
	for entry in daily_entries:
		if String(entry.get("save_kind", "")) == "daily_time_limit":
			forced_data = GameState.peek_save_data(String(entry.get("save_path", "")))
	_expect(not forced_data.is_empty() and bool(forced_data.get("loadable", false)),
		"Time-limit recovery remains loadable after the session ends")
	_expect(String(forced_data.get("commit_trigger", "")) == "daily_time_limit",
		"Forced commit is internally distinguished from manual Save")
	_expect(String(forced_data.get("scene_path", "")) == PINEHILL_SCENE
			and forced_data.get("encounter_context", {}).is_empty()
			and int(forced_data.get("current_lives", 0)) == 3,
		"Daily timeout during battle saves a safe Pinehill quest checkpoint, not transient battle state")
	_expect(not bool(forced_data.get("pinehill_defeated_bandits", {}).get("pinehill_bandits1", true))
			and int(forced_data.get("current_task_index", -1)) == GameState.PINEHILL_BANDIT_TASK_INDEX,
		"Daily timeout does not mark the failed Pinehill encounter complete or advance its objective")
	var forced_path := String(forced_data.get("save_path", ""))
	var deletion_result: Dictionary = GameState.delete_all_saves()
	_expect(not GameState.delete_save(forced_path) and int(deletion_result.get("deleted_count", 0)) == 0
			and GameState.list_saves().size() == 1,
		"Manual Delete/Delete All cannot remove the protected daily recovery slot")
	_expect(_fake_http.requests.any(func(item: Dictionary) -> bool:
		return String(item.get("path", "")) == "/api/playtime/end"),
		"Daily limit finalizes the independent Screen Time session")
	_remote.set("_current_playtime_session_id", 97003)
	_remote.set("_current_playtime_session_credential", "qa-only-reconnected-lease")
	_remote.set("_current_playtime_student_id", GameState.student_id)
	_remote.set("_current_playtime_parent_id", GameState.parent_id)
	_remote.set("_current_playtime_learning_cycle_version", GameState.learning_cycle_version)
	GameState.playtime_authorized = true
	await _remote.call("_flush_pending")
	await get_tree().process_frame
	_expect(_count_requests("/api/game/progress") == 1 and _count_requests("/api/game/result") == 1,
		"The daily forced commit flushes once after a later authorized session resumes")


func _set_student(student_id: String, parent_id: String) -> void:
	GameState.student_id = student_id
	GameState.parent_id = parent_id
	GameState.player_name = "QA Student"
	GameState.grade_level = "Grade 3"
	GameState.gender = "female"
	GameState.learning_cycle_version = 1
	GameState.current_scene_path = VALID_SCENE
	GameState.current_map = VALID_SCENE
	GameState.player_position = Vector2(40, 80)
	GameState.current_task_index = 3
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.correct_answers = 0
	GameState.incorrect_answers = 0
	GameState.total_questions = 0
	GameState.playtime_authorized = true
	if GameState.has_method("clear_pending_academic_events"):
		GameState.call("clear_pending_academic_events")
	if is_instance_valid(_remote):
		_remote.set("_current_playtime_session_id", 97001)
		_remote.set("_current_playtime_session_credential", "qa-only-synthetic-lease")
		_remote.set("_current_playtime_student_id", student_id)
		_remote.set("_current_playtime_parent_id", parent_id)
		_remote.set("_current_playtime_learning_cycle_version", GameState.learning_cycle_version)


func _current_checkpoint_path(student_id: String) -> String:
	return "%s/save_%s_current.json" % [_test_directory, student_id]


func _visible_save_count() -> int:
	return GameState.list_saves().size()


func _count_requests(path: String) -> int:
	return _fake_http.requests.filter(func(item: Dictionary) -> bool:
		return String(item.get("path", "")) == path).size()


func _count_queued_kind(queue: Array, kind: String) -> int:
	return queue.filter(func(item: Variant) -> bool:
		return item is Dictionary and String(item.get("kind", "")) == kind).size()


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		print("FAIL: " + label)


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	var report := {
		"passed": _checks.size() - failed,
		"failed": failed,
		"checks": _checks,
		"local_qa_only": true,
		"production_requests": 0,
		"production_writes": 0,
	}
	print("PROGRESS_COMMIT_BOUNDARY_TEST " + JSON.stringify(report))
	GameState.set("_save_directory", _original_save_directory)
	GameState.set("device_installation_id", _original_device_id)
	if is_instance_valid(_remote):
		_remote.queue_free()
	if is_instance_valid(_fake_http):
		_fake_http.queue_free()
	if not _pending_file.is_empty() and FileAccess.file_exists(_pending_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_pending_file))
	var absolute_directory := ProjectSettings.globalize_path(_test_directory)
	if not _test_directory.is_empty() and DirAccess.dir_exists_absolute(absolute_directory):
		var dir := DirAccess.open(_test_directory)
		if dir != null:
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while not file_name.is_empty():
				if not dir.current_is_dir():
					DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_directory + "/" + file_name))
				file_name = dir.get_next()
			dir.list_dir_end()
		DirAccess.remove_absolute(absolute_directory)
	await get_tree().create_timer(5.0).timeout
	if failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)
