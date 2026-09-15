extends Node

const QuestionProviderScript := preload("res://scripts/question_provider.gd")
const OAKLEAF_SCENE := "res://scenes/oak_leaf_village.tscn"


class DelayedHttpApi extends Node:
	var requests: Array[Dictionary] = []
	var generation := 0
	var fail_next_request := false

	func request_get(path: String, params: Dictionary = {}) -> Dictionary:
		requests.append({"path": path, "params": params.duplicate(true)})
		await get_tree().create_timer(0.25).timeout
		if fail_next_request:
			fail_next_request = false
			return {"ok": false, "status": 503, "body": {}}
		generation += 1
		var grade := String(params.get("grade", ""))
		var difficulty := String(params.get("difficulty", ""))
		return {
			"ok": true,
			"status": 200,
			"body": {"questions": [{
				"id": 7000 + generation,
				"question": "%s %s cached generation %d" % [grade, difficulty, generation],
				"options": ["1", "2", "3", "4"],
				"correct_answer": "3",
				"grade_level": grade,
				"difficulty": difficulty,
				"learning_file_id": 70,
			}]},
		}


var _checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	var http := DelayedHttpApi.new()
	http.name = "HttpApi"
	get_tree().root.add_child(http)
	GameState.grade_level = "Grade 1"
	GameState.current_scene_path = OAKLEAF_SCENE
	GameState.encounter_context.clear()
	var provider := QuestionProviderScript.new()
	provider.name = "PrefetchProvider"
	get_tree().root.add_child(provider)
	await get_tree().process_frame

	var supports_prefetch := provider.has_method("prefetch_questions")
	_expect(supports_prefetch, "QuestionProvider exposes exact-scope prefetch")
	if supports_prefetch:
		var scope := {"grade": "Grade 1", "difficulty": "Easy"}
		var prefetch_started := Time.get_ticks_msec()
		var prepared: Dictionary = await provider.call("prefetch_questions", scope)
		var uncached_ms := Time.get_ticks_msec() - prefetch_started
		_expect(bool(prepared.get("successful", false)) and int(prepared.get("count", 0)) == 1, "exact Grade 1 Easy prefetch returns one validated remote question")
		_expect(http.requests.size() == 1 and http.requests[0].get("params") == scope, "prefetch makes one exact-scope backend request")
		_expect(provider.get_questions().is_empty(), "background prefetch never mutates the active battle pool")

		GameState.encounter_context = {
			"encounter_id": "oakleaf_bandits2",
			"source_scene_path": OAKLEAF_SCENE,
			"question_scope": scope,
		}
		var cached_started := Time.get_ticks_msec()
		await provider.load_questions()
		var cached_ms := Time.get_ticks_msec() - cached_started
		_expect(http.requests.size() == 1, "battle consumes the prepared pool without a second request")
		_expect(provider.get_questions().size() == 1, "prepared question becomes the active battle pool")
		_expect(cached_ms < uncached_ms and cached_ms < 80, "prepared question becomes available without network delay")

		await provider.load_questions()
		_expect(http.requests.size() == 2, "prepared pool is one-shot so a later battle refreshes the active set")
		GameState.grade_level = "Grade 2"
		GameState.encounter_context["question_scope"] = {"grade": "Grade 2", "difficulty": "Easy"}
		await provider.load_questions()
		_expect(http.requests.size() == 3 and http.requests.back().get("params") == {"grade": "Grade 2", "difficulty": "Easy"}, "Grade 1 cache cannot satisfy a Grade 2 encounter")

		GameState.grade_level = "Grade 3"
		GameState.encounter_context["question_scope"] = {"grade": "Grade 3", "difficulty": "Easy"}
		http.fail_next_request = true
		var failed_prefetch: Dictionary = await provider.call("prefetch_questions", GameState.encounter_context["question_scope"])
		_expect(not bool(failed_prefetch.get("successful", true)), "a transient failed prefetch is reported without activating questions")
		var requests_before_recovery := http.requests.size()
		await provider.load_questions()
		_expect(http.requests.size() == requests_before_recovery + 1, "battle retries exact-scope loading after a failed speculative prefetch")
		_expect(provider.get_questions().size() == 1 and String(provider.get_questions()[0].get("grade_level", "")) == "Grade 3", "foreground recovery activates the valid exact-scope question")
		print("QUESTION_PREFETCH_TIMING " + JSON.stringify({"uncached_ms": uncached_ms, "cached_ms": cached_ms, "requests": http.requests.size()}))

	provider.queue_free()
	http.queue_free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	print("QUESTION_PROVIDER_PREFETCH_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
