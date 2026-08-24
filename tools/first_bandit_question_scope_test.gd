extends SceneTree

const QuestionProviderScript = preload("res://scripts/question_provider.gd")


class HttpApiStub extends Node:
	var requests: Array[Dictionary] = []

	func request_get(path: String, params: Dictionary) -> Dictionary:
		requests.append({
			"path": path,
			"params": params.duplicate(true),
		})
		return {
			"ok": true,
			"status": 200,
			"body": {
				"questions": [{
					"id": 13,
					"question": "Remote question",
					"options": ["1", "2", "3", "4"],
					"correct_answer": "2",
					"learning_file_id": 13,
				}],
			},
		}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var root_window: Window = root
	var game_state: Node = root_window.get_node_or_null("GameState")
	if game_state == null:
		printerr("[First Bandit Scope Test] GameState autoload must be available.")
		quit(1)
		return

	var original_grade: Variant = game_state.get("grade_level")
	var original_scene: Variant = game_state.get("current_scene_path")
	var original_context: Variant = game_state.get("encounter_context")
	var original_task_index: Variant = game_state.get("current_task_index")

	game_state.set("grade_level", "Grade 1")
	game_state.set("current_scene_path", "res://scenes/oak_leaf_village.tscn")
	game_state.set("current_task_index", 2)
	var tasks: Array = game_state.get("tasks")
	var first_bandit_task: Dictionary = tasks[2]
	var declared_scope: Variant = first_bandit_task.get("question_scope", {})
	failed = not _assert(declared_scope is Dictionary, "The first Bandit task must declare a controlled question scope.") or failed
	if declared_scope is Dictionary:
		failed = not _assert_equal(String(declared_scope.get("topic", "")), "Basic Addition", "The first Bandit topic must be Basic Addition.") or failed

	var encounter: Dictionary = game_state.call("begin_encounter", {
		"encounter_id": "oakleaf_first_bandit",
		"question_scope": declared_scope if declared_scope is Dictionary else {},
	})
	var resolved_scope: Dictionary = encounter.get("question_scope", {})
	failed = not _assert_equal(String(resolved_scope.get("grade", "")), "Grade 1", "The first Bandit must use the canonical student grade.") or failed
	failed = not _assert_equal(String(resolved_scope.get("difficulty", "")), "Easy", "Oakleaf must retain the Easy difficulty mapping.") or failed
	failed = not _assert_equal(String(resolved_scope.get("topic", "")), "Basic Addition", "The encounter must retain the explicit Basic Addition topic.") or failed

	var provider := QuestionProviderScript.new()
	provider.name = "FirstBanditQuestionProvider"
	root_window.add_child(provider)
	var params: Dictionary = provider.call("_get_encounter_question_params")
	failed = not _assert_equal(params, {
		"grade": "Grade 1",
		"difficulty": "Easy",
		"topic": "Basic Addition",
	}, "QuestionProvider must construct the fully scoped first Bandit request.") or failed

	var active_http: Node = root_window.get_node_or_null("HttpApi")
	var original_http_name := ""
	if active_http != null:
		original_http_name = active_http.name
		active_http.name = "_first_bandit_original_http"
	var http_stub := HttpApiStub.new()
	http_stub.name = "HttpApi"
	root_window.add_child(http_stub)
	var remote_questions: Array[Dictionary] = await provider.load_questions()
	failed = not _assert_equal(http_stub.requests.size(), 1, "QuestionProvider must make one remote request before considering fallback questions.") or failed
	if http_stub.requests.size() == 1:
		failed = not _assert_equal(http_stub.requests[0].get("path"), "/api/game/questions", "The first Bandit must use the production question endpoint.") or failed
		failed = not _assert_equal(http_stub.requests[0].get("params"), params, "The remote request must keep the complete first Bandit scope.") or failed
	failed = not _assert_equal(remote_questions.size(), 1, "A usable remote question response must be used without local fallback.") or failed
	if remote_questions.size() == 1:
		failed = not _assert_equal(remote_questions[0].get("question_set_id"), 13, "Remote question-set traceability must survive the first Bandit fetch.") or failed
	http_stub.queue_free()
	if active_http != null:
		active_http.name = original_http_name
	provider.queue_free()

	game_state.set("grade_level", original_grade)
	game_state.set("current_scene_path", original_scene)
	game_state.set("encounter_context", original_context)
	game_state.set("current_task_index", original_task_index)
	if failed:
		quit(1)
		return
	print("first_bandit_question_scope_test: PASS")
	quit(0)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[First Bandit Scope Test] %s" % message)
		return false
	return true


func _assert_equal(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		printerr("[First Bandit Scope Test] %s. Expected %s, got %s" % [message, str(expected), str(actual)])
		return false
	return true
