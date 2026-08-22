extends SceneTree

const CONFIG_PATH := "res://Data/api_config.json"
const EXPECTED_PRODUCTION_URL := "https://theresiansquest.com"
const EXPECTED_TOPIC := "Problem Solving (Addition and Subtraction)"
const HttpApiScript := preload("res://scripts/http_api.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var config: Variant = _load_config()
	if not config is Dictionary:
		failures.append("API configuration must be a JSON object.")
		_finish()
		return
	var api: Node = HttpApiScript.new()
	var production_url := String(api.call("resolve_configured_base_url", config, false))
	_expect(production_url == EXPECTED_PRODUCTION_URL, "Release URL must resolve to the deployed HTTPS backend.")
	get_root().add_child(api)
	api.set("base_url", production_url)
	var result: Variant = await api.call("request_get", "/api/game/questions", {
		"grade": "Grade 1",
		"difficulty": "Hard",
		"topic": EXPECTED_TOPIC,
	}, 15000)
	api.queue_free()
	await process_frame
	_verify_response(result)
	_finish()


func _load_config() -> Variant:
	var config_file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if config_file == null:
		return null
	var parsed: Variant = JSON.parse_string(config_file.get_as_text())
	config_file.close()
	return parsed


func _verify_response(result: Variant) -> void:
	_expect(result is Dictionary, "Godot must receive a structured response from the production question API.")
	if not result is Dictionary:
		return
	var response: Dictionary = result
	_expect(bool(response.get("ok", false)), "Godot production question request must complete successfully.")
	_expect(int(response.get("status", 0)) == 200, "Production question endpoint must return HTTP 200.")
	var body: Variant = response.get("body", null)
	_expect(body is Dictionary, "Production question response body must be an object.")
	if not body is Dictionary:
		return
	var questions: Array = body.get("questions", [])
	_expect(questions.size() == 5, "Active Grade 1 / Hard scope must return exactly five questions.")
	if questions.is_empty():
		return
	var first: Variant = questions[0]
	_expect(first is Dictionary, "Each production question must be structured data.")
	if not first is Dictionary:
		return
	var question: Dictionary = first
	_expect(int(question.get("learning_file_id", 0)) == 8, "Remote question metadata must retain learning_file_id 8.")
	_expect(String(question.get("grade_level", "")) == "Grade 1", "Remote question grade must remain Grade 1.")
	_expect(String(question.get("difficulty", "")) == "Hard", "Remote question difficulty must remain Hard.")
	_expect(String(question.get("math_topic", "")) == EXPECTED_TOPIC, "Remote question topic must match the active set scope.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: Godot reached the active production question set remotely.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
