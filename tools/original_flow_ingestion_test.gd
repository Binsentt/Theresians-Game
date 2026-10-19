extends Node

var checks: Array[Dictionary] = []

class HttpStub extends Node:
	var requests: Array[Dictionary] = []
	var before_response: Callable = Callable()
	var responses: Array[Dictionary] = []
	func request_post(path: String, payload: Dictionary) -> Dictionary:
		# Match HttpApi's JSON encoding boundary without opening any connection.
		var encoded_payload := JSON.stringify(payload)
		var decoded_payload: Dictionary = JSON.parse_string(encoded_payload)
		requests.append({"path": path, "payload": decoded_payload})
		if before_response.is_valid():
			var callback := before_response
			before_response = Callable()
			callback.call(path, decoded_payload)
		if not responses.is_empty():
			return responses.pop_front()
		return {"ok": true, "status": 201, "body": {}}

func _ready() -> void:
	_run.call_deferred()

func _expect(passed: bool, label: String) -> void:
	checks.append({"name": label, "passed": passed})
	print(("PASS " if passed else "FAIL ") + label)

func _run() -> void:
	# The canonical project is used, with network observers replaced only in this
	# test process and the existing fixture subclass directing saves to one file.
	get_node("/root/RemoteSync").free()
	get_node("/root/HttpApi").free()
	var state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.start_new_game({"student_id": "12345678", "parent_id": "123456", "player_name": "Local flow fixture", "grade_level": "Grade 1"}, false)
	state.score = 4
	state.correct_answers = 4
	state.incorrect_answers = 2
	state.total_questions = 6
	state.progress_percentage = 25
	state.lesson_progress = 3
	state.total_play_time = 42
	state.difficulty_level = "Easy"
	state.start_new_game({"student_id": "87654321", "parent_id": "654321", "player_name": "Second local fixture", "grade_level": "Grade 2"}, false)
	_expect(
		state.score == 0 and state.correct_answers == 0 and state.incorrect_answers == 0 and state.total_questions == 0
		and state.progress_percentage == 0 and state.lesson_progress == 0 and state.total_play_time == 0 and state.difficulty_level == "Unknown",
		"Starting a new Student profile clears the previous Student's per-run analytics"
	)
	state.start_new_game({"student_id": "12345678", "parent_id": "123456", "player_name": "Local flow fixture", "grade_level": "Grade 1"}, false)
	_expect(state.tasks.size() == 18, "Retain the canonical 18-task campaign graph")
	_expect(state.get_task_activity_metadata(0).activity_id == "go-to-teachers-house", "Teacher House remains first tracked task")
	_expect(state.get_task_activity_metadata(1).activity_id == "talk-to-the-teacher", "Teacher conversation remains second tracked task")
	_expect(state.get_task_activity_metadata(2).activity_id == "first-bandit-math-challenge", "First Bandit remains third tracked task")
	var during: Dictionary = state.build_save_data()
	state.apply_save_data(during, false)
	_expect(state.is_tutorial_active() and state.current_quest == "Tutorial", "Save/Load during Tutorial retains authoritative Tutorial state")
	state.complete_tutorial_activity()
	var after_tutorial: Dictionary = state.build_save_data()
	state.apply_save_data(after_tutorial, false)
	_expect(not state.is_tutorial_active() and state.current_task_index == 0, "Save/Load after Tutorial retains completion without advancing arrival")
	_expect(state.current_quest == state.tasks[0].quest_text, "Teacher House objective follows Tutorial completion")
	state.advance_task_and_save({"type": "task_trigger", "activity_type": "task_completed", "key": "test-arrival"})
	_expect(state.current_task_index == 1 and state.current_quest == state.tasks[1].quest_text, "Arrival advances once to Teacher conversation")
	state.advance_task_and_save({"type": "quest_completed", "key": "test-teacher"})
	_expect(state.current_task_index == 2 and state.current_quest == state.tasks[2].quest_text, "Teacher completion advances to First Bandit")
	state.begin_encounter({"encounter_id": "first-bandit", "quest_checkpoint": 2})
	state.record_encounter_loss()
	_expect(state.current_task_index == 2, "Battle loss preserves First Bandit checkpoint")
	state.begin_encounter({"encounter_id": "first-bandit", "quest_checkpoint": 2})
	state.record_encounter_victory()
	state.advance_task_and_save({"type": "task_completed", "key": "test-bandit"})
	var after_battle: Dictionary = state.build_save_data()
	after_battle.current_quest = "Go to the Teacher's House"
	state.apply_save_data(after_battle, false)
	_expect(state.current_task_index == 3 and state.current_quest == state.tasks[3].quest_text, "Loading the completed First Bandit checkpoint advances to the partial all-Bandits objective without regressing to the stale Teacher House title")
	_expect(state.current_task_index == state.OAKLEAF_BANDIT_TASK_INDEX, "First Bandit completion remains partial progress and does not skip the remaining Oakleaf Bandits")

	var http := HttpStub.new()
	http.name = "HttpApi"
	get_tree().root.add_child(http)
	var sync = load("res://scripts/remote_sync.gd").new()
	var pending_path := "user://original_flow_ingestion_%d.json" % Time.get_ticks_usec()
	sync.set("_pending_file", pending_path)
	get_tree().root.add_child(sync)
	sync.set_process(false)
	state.learning_cycle_version = 7
	state.playtime_authorized = true
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "local-test-lease")
	sync.set("_current_playtime_student_id", state.student_id)
	sync.set("_current_playtime_parent_id", state.parent_id)
	sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	var teacher_event := {"type": "quest_completed", "key": "teacher:complete"}
	await sync._on_task_state_changed(1, 2, teacher_event)
	var staged_activities: Array = state.get_pending_academic_events().get("activities", [])
	_expect(http.requests.is_empty() and staged_activities.size() == 1, "Teacher completion stages one canonical activity locally before the Save boundary")
	if staged_activities.size() == 1:
		var teacher_activity: Dictionary = staged_activities[0]
		var payload: Dictionary = teacher_activity.get("payload", {})
		_expect(String(teacher_activity.get("path", "")) == "/api/game/activity", "Canonical activity retains its backend endpoint while staged")
		_expect(String(payload.get("task_id", "")) == "Talk to the Teacher", "Teacher completion labels the completed Teacher task, not the next Bandit task")
		_expect(String(payload.get("current_quest", "")) == state.current_quest, "Canonical completion carries the authoritative post-completion Current Quest")
		_expect(String(payload.get("event_type", "")) == "quest_completed", "Teacher completion preserves canonical event type")
		_expect(not payload.has("student_id") and not payload.has("parent_id"), "Canonical activity identity remains lease-owned")
	await sync._on_task_state_changed(1, 2, teacher_event)
	staged_activities = state.get_pending_academic_events().get("activities", [])
	_expect(http.requests.is_empty() and staged_activities.size() == 1, "Repeated completion is staged idempotently and cannot create a duplicate")
	await sync._on_task_state_changed(2, 3, {"type": "quest_completed", "key": "terminal:complete"})
	staged_activities = state.get_pending_academic_events().get("activities", [])
	_expect(http.requests.is_empty() and staged_activities.size() == 2, "Terminal completion is staged even when the next task does not exist")
	await sync._on_canonical_activity_boundary({"type": "task_completed", "key": "tutorial:complete", "previous_index": 0, "current_index": 0, "activity": {"activity_id": "tutorial", "activity_label": "Tutorial"}})
	staged_activities = state.get_pending_academic_events().get("activities", [])
	_expect(http.requests.is_empty() and staged_activities.size() == 3, "Explicit Tutorial activity is staged without an early network write")
	if staged_activities.size() == 3:
		var tutorial_payload: Dictionary = staged_activities[2].get("payload", {})
		_expect(String(tutorial_payload.get("task_id", "")) == "Tutorial", "Explicit Tutorial activity metadata is preserved")
		_expect(String(tutorial_payload.get("canonical_task_id", "")) == "tutorial" and String(tutorial_payload.get("canonical_milestone_id", "")) == "tutorial.complete", "Tutorial emits its own canonical weighted milestone instead of colliding with Teacher House")
	await _test_answer_and_progress_serialization(state, sync, http)
	await _test_playtime_transition_races(state, sync, http)
	var captured_requests: Array[Dictionary] = []
	for request in http.requests:
		var captured: Dictionary = request.duplicate(true)
		for credential_key in ["session_credential", "playtime_session_credential"]:
			if captured.payload.has(credential_key):
				captured.payload[credential_key] = "[isolated test lease]"
		captured_requests.append(captured)
	sync.free()
	http.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	var failed := 0
	for check in checks:
		if not check.passed:
			failed += 1
	var result := {
		"passed": checks.size() - failed,
		"failed": failed,
		"checks": checks,
		"transport": "in-memory HttpStub; requests never leave the test process",
		"live_network_calls": 0,
		"production_writes": 0,
		"captured_requests": captured_requests,
	}
	var file := FileAccess.open("res://docs/qa/2026-09-07-original-flow-ingestion-runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ORIGINAL_FLOW_INGESTION_TEST " + JSON.stringify({"passed": checks.size() - failed, "failed": failed}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)


func _test_answer_and_progress_serialization(state, sync, http: HttpStub) -> void:
	var completed_snapshot: Dictionary = state.build_save_data()
	state.current_task_index = 2
	state.current_quest = String(state.tasks[2].quest_text)
	state.current_scene_path = "res://scenes/oak_leaf_village.tscn"
	state.current_map = "Oakleaf"
	state.difficulty_level = "Easy"
	state.encounter_context = {
		"encounter_id": "oakleaf_bandits3",
		"source_scene_path": "res://scenes/oak_leaf_village.tscn",
		"source_position": {"x": 320.0, "y": 410.0},
		"quest_checkpoint": 3,
		"retry_count": 0,
		"question_scope": {"grade": state.grade_level, "difficulty": "Easy"},
	}
	var scope: Dictionary = state.get_encounter_question_scope()
	var question := {
		"id": "isolated-serialization-question",
		# A stale/question-level label must never collapse every Oakleaf result to
		# Bandit 1 when an authoritative encounter context is active.
		"battle_id": "oakleaf_bandits1",
		"question_id": 90101,
		"question_set_id": 901,
		"topic_id": "basic_addition",
		"grade": scope.grade,
		"difficulty": scope.difficulty,
		"question": "1 + 1 = ?",
		"choices": ["2", "1", "3", "4"],
		"correct": 0,
	}
	state.clear_pending_academic_events()
	var safe_diagnostic := String(sync.call("_format_outbox_failure_diagnostic", "/api/game/result", {
		"ok": false,
		"status": 400,
		"body": {
			"error": "topic_id does not match the canonical question metadata.",
			"code": "INVALID_TOPIC_METADATA",
			"debug": "raw database exception local-test-lease",
		},
	}))
	_expect(safe_diagnostic.contains("HTTP 400") and safe_diagnostic.contains("INVALID_TOPIC_METADATA") and safe_diagnostic.contains("topic_id does not match the canonical question metadata."), "Rejected result diagnostics include endpoint status and exact safe backend validation reason")
	_expect(not safe_diagnostic.contains("local-test-lease") and not safe_diagnostic.contains("raw database exception") and not safe_diagnostic.contains("debug="), "Rejected result diagnostics exclude credentials, raw exception/debug fields, and request payloads")
	var credential_diagnostic := String(sync.call("_format_outbox_failure_diagnostic", "/api/game/result", {
		"ok": false,
		"status": 400,
		"body": {"error": "credential local-test-lease password=private-pass", "code": "INVALID_RESULT"},
	}))
	_expect(not credential_diagnostic.contains("local-test-lease") and not credential_diagnostic.contains("private-pass"), "Rejected result diagnostics redact session credentials and password values embedded in backend text")
	var legacy_question := {
		"id": "question:local-only-hash",
		"question": "2 + 3 = ?",
		"difficulty": scope.difficulty,
	}
	var legacy_payload: Dictionary = sync._build_question_result_payload(legacy_question, true)
	_expect(not legacy_payload.has("question_id") and not legacy_payload.has("question_set_id") and not legacy_payload.has("topic_id"), "A legacy/local question without canonical IDs does not fabricate database traceability fields")
	_expect(not String(legacy_payload.get("result_event_id", "")).is_empty(), "A legacy question may still use a stable independent result event identity")
	var before_results := http.requests.size()
	await sync.record_question_attempt(question, true)
	await sync.record_question_attempt(question, false)
	_expect(http.requests.size() == before_results, "Answer stays locally staged and does not send academic result before Save")
	var staged_events: Dictionary = state.get_pending_academic_events()
	var staged_results: Array = staged_events.get("results", [])
	_expect(staged_results.size() == 2, "Both answer results remain in the durable local staging buffer before Save")
	var emitted_result_event_ids: Array[String] = []
	for answer_index in mini(2, staged_results.size()):
		var payload: Dictionary = staged_results[answer_index]
		var label := "Correct result" if answer_index == 0 else "Incorrect result"
		_expect(int(payload.get("score", -1)) == (1 if answer_index == 0 else 0) and int(payload.get("total_items", 0)) == 1, label + " preserves answered-item and correct/wrong values")
		_expect(String(payload.get("student_id", "")) == state.student_id and String(payload.get("parent_id", "")) == state.parent_id and String(payload.get("student_name", "")) == state.player_name, label + " preserves current profile trace references")
		_expect(String(payload.get("grade_level", "")) == "Grade 1" and String(payload.get("difficulty", "")) == "Easy", label + " carries the active Oakleaf encounter Grade and Difficulty")
		_expect(int(payload.get("question_set_id", 0)) == 901 and int(payload.get("question_id", 0)) == 90101 and String(payload.get("topic_id", "")) == "basic_addition", label + " retains canonical question, set, and topic traceability")
		_expect(String(payload.get("canonical_battle_id", "")) == "oakleaf_bandits3", label + " attributes a backend-shaped question to the active Bandit encounter")
		emitted_result_event_ids.append(String(payload.get("result_event_id", "")))
	_expect(emitted_result_event_ids.size() == 2 and not emitted_result_event_ids[0].is_empty() and emitted_result_event_ids[0] != emitted_result_event_ids[1], "Separate answers to the same question receive separate stable result event IDs")
	var staged_activity_key := "cycle:7:task:2:3:task_completed:qa-oakleaf-task"
	state.stage_pending_academic_activity({
		"event_key": staged_activity_key,
		"event_type": "task_completed",
		"canonical_task_id": "oakleaf-bandit-1",
		"task_id": "First Bandit",
		"current_quest": state.current_quest,
	}, "/api/game/activity")
	var manual_snapshot: Dictionary = state.build_save_data()
	manual_snapshot["save_kind"] = "manual"
	manual_snapshot["save_commit_id"] = "manual:qa:7:1"
	http.responses = [{"ok": false, "status": 400, "body": {"error": "topic_id does not match the canonical question metadata.", "code": "INVALID_TOPIC_METADATA"}}]
	await sync._on_save_created(manual_snapshot)
	var requests_after_rejection: Array = http.requests.slice(before_results)
	_expect(requests_after_rejection.size() == 1 and requests_after_rejection[0].path == "/api/game/result", "Manual Save queues the result first and preserves FIFO ordering when the backend rejects it")
	if not requests_after_rejection.is_empty():
		var sent_payload: Dictionary = requests_after_rejection[0].payload
		_expect(int(sent_payload.get("question_id", 0)) == 90101 and int(sent_payload.get("question_set_id", 0)) == 901 and String(sent_payload.get("topic_id", "")) == "basic_addition", "Saved result request matches the canonical database question contract")
		_expect(int(sent_payload.get("playtime_session_id", 0)) == 123 and String(sent_payload.get("playtime_session_credential", "")) == "local-test-lease" and int(sent_payload.get("learning_cycle_version", 0)) == 7, "Saved result attaches the current lease and Learning Cycle")
	var rejected_pending: Array = sync._load_pending()
	_expect(rejected_pending.size() == 4 and rejected_pending.any(func(item: Dictionary) -> bool: return String(item.get("kind", "")) == "activity" and String(item.get("path", "")) == "/api/game/activity"), "Failed Save commit keeps result, canonical activity, and progress items retryable")
	_expect(http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/activity").is_empty(), "Canonical task activity waits behind the failed result rather than being falsely acknowledged")
	http.responses = []
	await sync._flush_pending()
	var result_requests := http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result")
	_expect(result_requests.size() == 3, "Successful retry drains the original result plus the second staged answer")
	if result_requests.size() == 3:
		_expect(String(result_requests[0].payload.get("result_event_id", "")) == String(result_requests[1].payload.get("result_event_id", "")), "Rejected transport retry reuses the same idempotent result event ID")
		_expect(String(result_requests[2].payload.get("result_event_id", "")) == emitted_result_event_ids[1], "Second staged answer keeps its own stable result event ID")
	var canonical_activity_requests: Array = http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/activity")
	_expect(canonical_activity_requests.size() == 1 and String(canonical_activity_requests[0].payload.get("event_key", "")) == staged_activity_key, "Save sends the canonical task completion through /api/game/activity once")
	_expect(sync._load_pending().is_empty(), "Successful result, activity, and progress acknowledgements clear the committed outbox")
	sync.set("_current_playtime_session_id", 0)
	sync.set("_current_playtime_session_credential", "")
	state.playtime_authorized = false
	await sync.record_question_attempt(question, true)
	_expect(http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result").size() == 3, "A new answer still stays staged without a live playtime lease")
	var pending_results: Array = state.get_pending_academic_events().get("results", [])
	_expect(pending_results.size() == 1, "A graded answer remains durable in hidden local staging when no lease is available")
	var queued_result_event_id := ""
	if pending_results.size() == 1:
		queued_result_event_id = String((pending_results[0] as Dictionary).get("result_event_id", ""))
		_expect(not queued_result_event_id.is_empty(), "The staged result preserves a stable nonempty event ID")
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "local-test-lease")
	sync.set("_current_playtime_student_id", state.student_id)
	sync.set("_current_playtime_parent_id", state.parent_id)
	sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	state.playtime_authorized = true
	var lease_recovery_snapshot: Dictionary = state.build_save_data()
	lease_recovery_snapshot["save_kind"] = "manual"
	lease_recovery_snapshot["save_commit_id"] = "manual:qa:7:2"
	await sync._on_save_created(lease_recovery_snapshot)
	await sync._flush_pending()
	result_requests = http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result")
	_expect(result_requests.size() == 4, "Save/lease recovery flushes the pending graded answer exactly once")
	if result_requests.size() == 4:
		_expect(String(result_requests[3].payload.get("result_event_id", "")) == queued_result_event_id, "Outbox retry reuses the original result event ID")

	var flushing_payload: Dictionary = sync._build_question_result_payload(question, true)
	var concurrent_payload: Dictionary = sync._build_question_result_payload(question, false)
	sync._enqueue_pending_result(flushing_payload)
	http.before_response = func(path: String, _payload: Dictionary) -> void:
		if path == "/api/game/result":
			sync._enqueue_pending_result(concurrent_payload)
	await sync._flush_pending()
	var after_concurrent_enqueue: Array = sync._load_pending()
	var queued_after_flush := after_concurrent_enqueue.filter(func(item: Dictionary) -> bool:
		return String(item.get("kind", "")) == "result"
	)
	_expect(queued_after_flush.size() == 1, "A result enqueued while a flush awaits the server is not overwritten by the older queue snapshot")
	if queued_after_flush.size() == 1:
		var retained_payload: Dictionary = queued_after_flush[0].get("payload", {})
		_expect(String(retained_payload.get("result_event_id", "")) == String(concurrent_payload.get("result_event_id", "")), "Concurrent outbox reconciliation retains the newly queued answer event")
	await sync._flush_pending()
	_expect(sync._load_pending().is_empty(), "A later serialized flush acknowledges the retained concurrent answer without duplication")

	var result_requests_before_stale := http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result").size()
	http.responses = [{"ok": false, "status": 409, "body": {"code": "PLAYTIME_HEARTBEAT_STALE"}}]
	await sync.record_question_attempt(question, true)
	var stale_save: Dictionary = state.build_save_data()
	stale_save["save_kind"] = "manual"
	stale_save["commit_trigger"] = "manual_save"
	stale_save["save_commit_id"] = "manual:qa:7:stale-lease"
	http.responses.append({"ok": false, "status": 0, "body": {}, "error": "isolated offline retry"})
	await sync._on_save_created(stale_save)
	await get_tree().process_frame
	var stale_pending: Array = sync._load_pending()
	var stale_event_id := ""
	for pending_item: Variant in stale_pending:
		if pending_item is Dictionary and String(pending_item.get("kind", "")) == "result":
			stale_event_id = String(pending_item.get("payload", {}).get("result_event_id", ""))
	_expect(not stale_event_id.is_empty(), "A result rejected by a stale server lease remains queued with its original event ID")
	_expect(int(sync.get("_current_playtime_session_id")) == 0 and String(sync.get("_current_playtime_session_credential")).is_empty(), "A stale server lease is invalidated before retry")
	http.responses = [{
		"ok": true,
		"status": 201,
		"body": {
			"can_play": true,
			"session_id": 456,
			"session_credential": "renewed-local-test-lease",
			"remaining_minutes": 60,
			"remaining_seconds": 3600,
			"daily_limit_minutes": 60,
			"total_playtime_today": 0,
			"learning_cycle": {"version": 7, "started_at": ""},
		},
	}]
	await sync._flush_pending()
	var stale_result_requests := http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result")
	_expect(stale_result_requests.size() == result_requests_before_stale + 2, "A later outbox flush reacquires a lease and retries the rejected result exactly once")
	if stale_result_requests.size() == result_requests_before_stale + 2:
		var retried_payload: Dictionary = stale_result_requests.back().payload
		_expect(String(retried_payload.get("result_event_id", "")) == stale_event_id, "Lease recovery preserves the original result event ID")
		_expect(int(retried_payload.get("playtime_session_id", 0)) == 456 and String(retried_payload.get("playtime_session_credential", "")) == "renewed-local-test-lease", "Lease recovery retries with the renewed server lease")
	_expect(sync._load_pending().is_empty(), "A server-accepted stale-lease retry leaves no pending duplicate")

	var student_a_id := String(state.student_id)
	var student_a_parent_id := String(state.parent_id)
	var student_a_payload: Dictionary = sync._build_question_result_payload(question, false)
	sync._enqueue_pending_result(student_a_payload)
	state.student_id = "87654321"
	state.parent_id = "654321"
	sync.set("_current_playtime_session_id", 789)
	sync.set("_current_playtime_session_credential", "student-b-test-lease")
	var before_cross_student_flush := http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result").size()
	await sync._flush_pending()
	var after_cross_student_flush := http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result").size()
	_expect(after_cross_student_flush == before_cross_student_flush, "Student B cannot submit a queued Student A result with Student B's lease")
	var cross_student_pending: Array = sync._load_pending()
	_expect(cross_student_pending.any(func(item: Dictionary) -> bool:
		return String(item.get("kind", "")) == "result" and String(item.get("payload", {}).get("result_event_id", "")) == String(student_a_payload.get("result_event_id", ""))
	), "Student A's queued result remains available until Student A has an active lease")
	state.student_id = student_a_id
	state.parent_id = student_a_parent_id
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "local-test-lease")
	sync.set("_current_playtime_student_id", state.student_id)
	sync.set("_current_playtime_parent_id", state.parent_id)
	sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	state.playtime_authorized = true
	await sync._flush_pending()
	_expect(sync._load_pending().is_empty(), "Student A can flush its own retained result after returning to its account")

	var in_flight_student_a_payload: Dictionary = sync._build_question_result_payload(question, true)
	sync._enqueue_pending_result(in_flight_student_a_payload)
	http.responses = [{"ok": false, "status": 403, "body": {"error": "The active playtime session is invalid."}}]
	http.before_response = func(path: String, _payload: Dictionary) -> void:
		if path == "/api/game/result":
			state.student_id = "87654321"
			state.parent_id = "654321"
			sync.set("_current_playtime_session_id", 789)
			sync.set("_current_playtime_session_credential", "student-b-test-lease")
			sync.set("_current_playtime_student_id", state.student_id)
			sync.set("_current_playtime_parent_id", state.parent_id)
			sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	await sync._flush_pending()
	_expect(
		int(sync.get("_current_playtime_session_id")) == 789 and String(sync.get("_current_playtime_session_credential")) == "student-b-test-lease",
		"A rejected in-flight Student A request cannot invalidate Student B's newly issued lease"
	)
	_expect(sync._load_pending().any(func(item: Dictionary) -> bool:
		return String(item.get("kind", "")) == "result" and String(item.get("payload", {}).get("result_event_id", "")) == String(in_flight_student_a_payload.get("result_event_id", ""))
	), "An in-flight account switch preserves Student A's rejected result for Student A")
	state.student_id = student_a_id
	state.parent_id = student_a_parent_id
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "local-test-lease")
	sync.set("_current_playtime_student_id", state.student_id)
	sync.set("_current_playtime_parent_id", state.parent_id)
	sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	state.playtime_authorized = true
	http.responses = []
	await sync._flush_pending()
	_expect(sync._load_pending().is_empty(), "Student A's rejected in-flight result remains retryable after returning")

	# Representative local counters exercise projection only. Overall progress
	# semantics remain the backend's responsibility; no client percentage is made
	# from these three correct and one incorrect answers.
	state.correct_answers = 3
	state.incorrect_answers = 1
	state.total_questions = 4
	state.score = 3
	state.total_play_time = 42
	await _test_saved_progress_projection(state, sync, http, "Active First Bandit")
	state.apply_save_data(completed_snapshot, false)
	await _test_saved_progress_projection(state, sync, http, "Completed ZIP task list")


func _test_playtime_transition_races(state, sync, http: HttpStub) -> void:
	state.student_id = "12345678"
	state.parent_id = "123456"
	state.learning_cycle_version = 7
	state.playtime_authorized = true
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "student-a-lease")
	sync.set("_current_playtime_student_id", state.student_id)
	sync.set("_current_playtime_parent_id", state.parent_id)
	sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)

	http.responses = [{"ok": false, "status": 409, "body": {"code": "PLAYTIME_HEARTBEAT_STALE"}}]
	http.before_response = func(path: String, _payload: Dictionary) -> void:
		if path == "/api/playtime/heartbeat":
			state.student_id = "87654321"
			state.parent_id = "654321"
			sync.set("_current_playtime_session_id", 789)
			sync.set("_current_playtime_session_credential", "student-b-lease")
			sync.set("_current_playtime_student_id", state.student_id)
			sync.set("_current_playtime_parent_id", state.parent_id)
			sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	await sync._refresh_playtime_lease()
	_expect(int(sync.get("_current_playtime_session_id")) == 789 and String(sync.get("_current_playtime_session_credential")) == "student-b-lease", "A late Student A heartbeat response cannot invalidate Student B's replacement lease")

	state.student_id = "12345678"
	state.parent_id = "123456"
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "student-a-lease")
	sync.set("_current_playtime_student_id", state.student_id)
	sync.set("_current_playtime_parent_id", state.parent_id)
	sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	http.responses = [{"ok": true, "status": 200, "body": {}}]
	http.before_response = func(path: String, _payload: Dictionary) -> void:
		if path == "/api/playtime/end":
			state.student_id = "87654321"
			state.parent_id = "654321"
			sync.set("_current_playtime_session_id", 789)
			sync.set("_current_playtime_session_credential", "student-b-lease")
			sync.set("_current_playtime_student_id", state.student_id)
			sync.set("_current_playtime_parent_id", state.parent_id)
			sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	await sync._end_playtime_session()
	_expect(int(sync.get("_current_playtime_session_id")) == 789 and String(sync.get("_current_playtime_session_credential")) == "student-b-lease", "A late Student A end response cannot clear Student B's replacement lease")

	state.student_id = "12345678"
	state.parent_id = "123456"
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "student-a-lease")
	sync.set("_current_playtime_student_id", state.student_id)
	sync.set("_current_playtime_parent_id", state.parent_id)
	sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	http.responses = [{"ok": false, "status": 0, "body": {}, "error": "offline"}]
	var request_count_before_failed_transition := http.requests.size()
	var failed_transition: Dictionary = await sync._start_playtime_session({
		"_force_refresh": true,
		"student_id": state.student_id,
		"parent_id": state.parent_id,
	})
	var failed_transition_requests: Array = http.requests.slice(request_count_before_failed_transition)
	_expect(not bool(failed_transition.get("ok", false)) and int(sync.get("_current_playtime_session_id")) == 123, "A failed prior-session end preserves its lease instead of orphaning it")
	_expect(failed_transition_requests.size() == 1 and failed_transition_requests[0].path == "/api/playtime/end", "A new playtime session is not opened when the previous lease could not be closed safely")

	var earlier_progress: Dictionary = state.build_save_data()
	earlier_progress["current_quest"] = "Earlier queued objective"
	var later_progress: Dictionary = state.build_save_data()
	later_progress["current_quest"] = "Later queued objective"
	sync._enqueue_pending(earlier_progress)
	sync._enqueue_pending(later_progress)
	http.responses = [{"ok": false, "status": 500, "body": {"error": "synthetic failure"}}]
	var before_fifo_failure := http.requests.size()
	await sync._flush_pending()
	var failed_fifo_requests: Array = http.requests.slice(before_fifo_failure)
	_expect(failed_fifo_requests.size() == 1 and String(failed_fifo_requests[0].payload.get("current_quest", "")) == "Earlier queued objective", "A failed earliest progress write prevents a later Current Quest from overtaking it")
	_expect(sync._load_pending().size() == 2, "FIFO failure retains both chronological progress writes for retry")
	http.responses = []
	var before_fifo_retry := http.requests.size()
	await sync._flush_pending()
	var retried_fifo_requests: Array = http.requests.slice(before_fifo_retry)
	_expect(retried_fifo_requests.size() == 2 and String(retried_fifo_requests[0].payload.get("current_quest", "")) == "Earlier queued objective" and String(retried_fifo_requests[1].payload.get("current_quest", "")) == "Later queued objective", "Recovered outbox drain preserves Current Quest chronology")
	_expect(sync._load_pending().is_empty(), "Successful FIFO retry clears both acknowledged progress writes")

	http.responses = [
		{"ok": false, "status": 401, "body": {"error": "expired lease"}},
		{"ok": true, "status": 201, "body": {
			"can_play": true,
			"session_id": 456,
			"session_credential": "replacement-lease",
			"remaining_minutes": 60,
			"remaining_seconds": 3600,
			"daily_limit_minutes": 60,
			"total_playtime_today": 0,
			"learning_cycle": {"version": 7, "started_at": ""},
		}},
	]
	var replacement: Dictionary = await sync._start_playtime_session({
		"_force_refresh": true,
		"student_id": state.student_id,
		"parent_id": state.parent_id,
	})
	_expect(bool(replacement.get("ok", false)) and int(sync.get("_current_playtime_session_id")) == 456, "A server-rejected prior lease can be replaced without retaining a permanently dead credential")

	sync.set("_session_start_in_progress", true)
	state.playtime_authorized = false
	sync.set("_playtime_timeout_handled", false)
	sync.set("_playtime_timeout_pending", false)
	sync._on_time_limit_reached()
	_expect(bool(sync.get("_playtime_timeout_pending")) and not bool(sync.get("_playtime_timeout_handled")), "A playtime denial during session start is deferred instead of consuming the only timeout signal")
	sync.set("_session_start_in_progress", false)
	sync.set("_playtime_timeout_pending", false)
	state.playtime_authorized = true
	http.responses = []


func _test_saved_progress_projection(state, sync, http: HttpStub, label: String) -> void:
	# The existing test subclass writes only its unique fixture. Read its real
	# serialized gameplay state, then attach the metadata an approved manual Save
	# supplies before emitting the production signal consumed by RemoteSync. This
	# avoids invoking the production save destination or user save files.
	# Clear older staged activity/result fixtures so this assertion isolates the
	# one progress projection represented by this save snapshot.
	state.clear_pending_academic_events()
	var fixture_path: String = state.save_game()
	var serialized: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	_expect(serialized is Dictionary, label + " fixture uses the actual GameState save serializer")
	if not (serialized is Dictionary):
		return
	var save_data: Dictionary = serialized
	save_data["save_kind"] = "manual"
	save_data["commit_trigger"] = "manual_save"
	save_data["save_commit_id"] = "manual:qa:projection:%s:%d:%d" % [String(save_data.get("student_id", "")), int(save_data.get("learning_cycle_version", 0)), Time.get_ticks_usec()]
	state.playtime_authorized = true
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "local-test-lease")
	sync.set("_current_playtime_student_id", state.student_id)
	sync.set("_current_playtime_parent_id", state.parent_id)
	sync.set("_current_playtime_learning_cycle_version", state.learning_cycle_version)
	var before_save := http.requests.size()
	state.save_created.emit(save_data)
	await get_tree().process_frame
	_expect(http.requests.size() == before_save + 1, label + " save_created signal reaches actual RemoteSync progress projection once")
	if http.requests.size() <= before_save:
		return
	var request: Dictionary = http.requests[before_save]
	var payload: Dictionary = request.payload
	_expect(request.path == "/api/game/progress", label + " uses the original progress endpoint")
	_expect(String(payload.get("student_id", "")) == String(save_data.student_id) and String(payload.get("parent_id", "")) == String(save_data.parent_id) and String(payload.get("student_name", "")) == String(save_data.player_name), label + " progress retains serialized profile trace references")
	_expect(String(payload.get("grade_level", "")) == String(save_data.grade_level) and String(payload.get("gender", "")) == String(save_data.gender), label + " progress retains saved grade and gender")
	_expect(String(payload.get("current_quest", "")).strip_edges() == String(save_data.current_quest).strip_edges() and int(payload.get("quest_progress", -1)) == int(save_data.current_task_index), label + " progress agrees with authoritative saved quest and checkpoint")
	_expect(String(payload.get("current_scene", "")) == String(save_data.scene_path) and String(payload.get("current_map", "")) == String(save_data.current_map), label + " progress retains canonical scene and map")
	_expect(String(payload.get("difficulty_level", "")) == String(save_data.difficulty_level), label + " progress preserves saved current difficulty")
	_expect(int(payload.get("correct_answers", -1)) == int(save_data.correct_answers) and int(payload.get("incorrect_answers", -1)) == int(save_data.incorrect_answers) and int(payload.get("total_questions", -1)) == int(save_data.total_questions), label + " progress preserves separate correct wrong and answered counters")
	_expect(int(payload.get("progress_percentage", -1)) == int(save_data.progress_percentage) and int(payload.get("lesson_progress", -1)) == int(save_data.lesson_progress), label + " progress forwards saved fields without replacing them with answer accuracy")
	_expect(int(payload.get("total_quests_completed", -1)) == int(save_data.total_quests_completed) and int(payload.get("score", -1)) == int(save_data.score) and int(payload.get("total_play_time", -1)) == int(save_data.total_play_time), label + " progress preserves remaining numeric save fields")
	_expect(int(payload.get("save_timestamp", 0)) == int(save_data.save_timestamp) and int(payload.get("save_timestamp", 0)) > 0 and String(payload.get("save_time", "")) == String(save_data.save_time) and String(payload.get("save_date", "")) == String(save_data.save_date), label + " progress retains actual save timestamp date and time")
	_expect(int(payload.get("playtime_session_id", 0)) == 123 and String(payload.get("playtime_session_credential", "")) == "local-test-lease" and int(payload.get("learning_cycle_version", 0)) == int(save_data.learning_cycle_version), label + " progress carries active lease and saved learning cycle")
	_expect(String(payload.get("save_status", "")) == "saved", label + " progress preserves Save Game activity status")
