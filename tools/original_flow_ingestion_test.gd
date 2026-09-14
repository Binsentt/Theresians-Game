extends Node

var checks: Array[Dictionary] = []

class HttpStub extends Node:
	var requests: Array[Dictionary] = []
	func request_post(path: String, payload: Dictionary) -> Dictionary:
		# Match HttpApi's JSON encoding boundary without opening any connection.
		var encoded_payload := JSON.stringify(payload)
		var decoded_payload: Dictionary = JSON.parse_string(encoded_payload)
		requests.append({"path": path, "payload": decoded_payload})
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
	_expect(state.tasks.size() == 3, "Retain exactly the three task entries implemented by the ZIP")
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
	_expect(state.current_task_index == 3 and state.current_quest == state.DEFAULT_QUEST, "Loading completed checkpoint does not regress to stale Teacher House title")
	_expect(not state.advance_task_and_save({}).advanced, "Completed ZIP task list cannot advance twice")

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
	var teacher_event := {"type": "quest_completed", "key": "teacher:complete"}
	await sync._on_task_state_changed(1, 2, teacher_event)
	_expect(http.requests.size() == 1, "Teacher completion sends one canonical activity")
	if http.requests.size() == 1:
		var payload: Dictionary = http.requests[0].payload
		_expect(payload.task_id == "Talk to the Teacher", "Teacher completion labels the completed Teacher task, not the next Bandit task")
		_expect(payload.event_type == "quest_completed", "Teacher completion preserves canonical event type")
		_expect(not payload.has("student_id") and not payload.has("parent_id"), "Canonical activity identity remains lease-owned")
		_expect(http.requests[0].path == "/api/game/activity", "Canonical activity route remains unchanged")
	await sync._on_task_state_changed(1, 2, teacher_event)
	_expect(http.requests.size() == 1, "Acknowledged completion cannot be sent twice")
	await sync._on_task_state_changed(2, 3, {"type": "quest_completed", "key": "terminal:complete"})
	_expect(http.requests.size() == 2, "Terminal completion is not dropped when next task does not exist")
	await sync._on_canonical_activity_boundary({"type": "task_completed", "key": "tutorial:complete", "previous_index": 0, "current_index": 0, "activity": {"activity_id": "tutorial", "activity_label": "Tutorial"}})
	_expect(http.requests.back().payload.task_id == "Tutorial", "Explicit Tutorial activity metadata is preserved")
	await _test_answer_and_progress_serialization(state, sync, http)
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
	var result := {"passed": checks.size() - failed, "failed": failed, "checks": checks, "captured_requests": captured_requests}
	var file := FileAccess.open("res://docs/qa/2026-09-07-original-flow-ingestion-runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ORIGINAL_FLOW_INGESTION_TEST " + JSON.stringify({"passed": checks.size() - failed, "failed": failed}))
	get_tree().quit(0 if failed == 0 else 1)


func _test_answer_and_progress_serialization(state, sync, http: HttpStub) -> void:
	var completed_snapshot: Dictionary = state.build_save_data()
	state.current_task_index = 2
	state.current_quest = String(state.tasks[2].quest_text)
	state.current_scene_path = "res://scenes/oak_leaf_village.tscn"
	state.current_map = "Oakleaf"
	state.difficulty_level = "Easy"
	var scope: Dictionary = state.tasks[2].question_scope
	var question := {
		"id": "isolated-serialization-question",
		"question_set_id": 901,
		"grade": scope.grade,
		"difficulty": scope.difficulty,
		"question": "1 + 1 = ?",
		"choices": ["2", "1", "3", "4"],
		"correct": 0,
	}
	var before_results := http.requests.size()
	await sync.record_question_attempt(question, true)
	await sync.record_question_attempt(question, false)
	_expect(http.requests.size() == before_results + 2, "Actual RemoteSync serializes one correct and one incorrect answer request")
	for answer_index in 2:
		if http.requests.size() <= before_results + answer_index:
			continue
		var request: Dictionary = http.requests[before_results + answer_index]
		var payload: Dictionary = request.payload
		var label := "Correct result" if answer_index == 0 else "Incorrect result"
		_expect(request.path == "/api/game/result", label + " uses the original result endpoint")
		_expect(int(payload.get("score", -1)) == (1 if answer_index == 0 else 0) and int(payload.get("total_items", 0)) == 1, label + " preserves answered-item and correct/wrong values")
		_expect(String(payload.get("student_id", "")) == state.student_id and String(payload.get("parent_id", "")) == state.parent_id and String(payload.get("student_name", "")) == state.player_name, label + " preserves current profile trace references")
		_expect(String(payload.get("grade_level", "")) == "Grade 1" and String(payload.get("difficulty", "")) == "Easy", label + " carries the actual First Bandit Grade and Difficulty")
		_expect(int(payload.get("playtime_session_id", 0)) == 123 and String(payload.get("playtime_session_credential", "")) == "local-test-lease" and int(payload.get("learning_cycle_version", 0)) == 7, label + " carries active server lease and learning cycle")
		_expect(int(payload.get("question_set_id", 0)) == 901, label + " retains question_set_id through JSON encoding")
		_expect(not payload.has("topic_id") and not payload.has("math_topic"), label + " does not require optional Topic metadata")
	sync.set("_current_playtime_session_id", 0)
	var before_unleased := http.requests.size()
	await sync.record_question_attempt(question, true)
	_expect(http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result").size() == 2, "A graded answer is not sent before a playtime lease is available")
	var pending_results: Array = []
	for pending_item in sync._load_pending():
		if pending_item is Dictionary and String(pending_item.get("kind", "")) == "result":
			pending_results.append(pending_item)
	_expect(pending_results.size() == 1, "A graded answer remains in the durable result outbox when the lease is unavailable")
	sync.set("_current_playtime_session_id", 123)
	sync.set("_current_playtime_session_credential", "local-test-lease")
	state.playtime_authorized = true
	await sync._flush_pending()
	_expect(http.requests.filter(func(request: Dictionary) -> bool: return request.path == "/api/game/result").size() == 3, "Save/lease recovery flushes the pending graded answer exactly once")

	# Representative local counters exercise projection only. Overall progress
	# semantics remain the backend's responsibility; no client percentage is made
	# from these three correct and one incorrect answers.
	state.correct_answers = 3
	state.incorrect_answers = 1
	state.total_questions = 4
	state.score = 3
	state.total_play_time = 42
	await _test_saved_progress_projection(state, http, "Active First Bandit")
	state.apply_save_data(completed_snapshot, false)
	await _test_saved_progress_projection(state, http, "Completed ZIP task list")


func _test_saved_progress_projection(state, http: HttpStub, label: String) -> void:
	# The existing test subclass writes only its unique fixture. Read its real
	# serialized save, then emit the production signal consumed by RemoteSync.
	# This avoids invoking the production save destination or user save files.
	var fixture_path: String = state.save_game()
	var serialized: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	_expect(serialized is Dictionary, label + " fixture uses the actual GameState save serializer")
	if not (serialized is Dictionary):
		return
	var save_data: Dictionary = serialized
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
	_expect(String(payload.get("current_quest", "")) == String(save_data.current_quest) and int(payload.get("quest_progress", -1)) == int(save_data.current_task_index), label + " progress agrees with authoritative saved quest and checkpoint")
	_expect(String(payload.get("current_scene", "")) == String(save_data.scene_path) and String(payload.get("current_map", "")) == String(save_data.current_map), label + " progress retains canonical scene and map")
	_expect(String(payload.get("difficulty_level", "")) == String(save_data.difficulty_level), label + " progress preserves saved current difficulty")
	_expect(int(payload.get("correct_answers", -1)) == int(save_data.correct_answers) and int(payload.get("incorrect_answers", -1)) == int(save_data.incorrect_answers) and int(payload.get("total_questions", -1)) == int(save_data.total_questions), label + " progress preserves separate correct wrong and answered counters")
	_expect(int(payload.get("progress_percentage", -1)) == int(save_data.progress_percentage) and int(payload.get("lesson_progress", -1)) == int(save_data.lesson_progress), label + " progress forwards saved fields without replacing them with answer accuracy")
	_expect(int(payload.get("total_quests_completed", -1)) == int(save_data.total_quests_completed) and int(payload.get("score", -1)) == int(save_data.score) and int(payload.get("total_play_time", -1)) == int(save_data.total_play_time), label + " progress preserves remaining numeric save fields")
	_expect(int(payload.get("save_timestamp", 0)) == int(save_data.save_timestamp) and int(payload.get("save_timestamp", 0)) > 0 and String(payload.get("save_time", "")) == String(save_data.save_time) and String(payload.get("save_date", "")) == String(save_data.save_date), label + " progress retains actual save timestamp date and time")
	_expect(int(payload.get("playtime_session_id", 0)) == 123 and String(payload.get("playtime_session_credential", "")) == "local-test-lease" and int(payload.get("learning_cycle_version", 0)) == int(save_data.learning_cycle_version), label + " progress carries active lease and saved learning cycle")
	_expect(String(payload.get("save_status", "")) == "saved", label + " progress preserves Save Game activity status")
