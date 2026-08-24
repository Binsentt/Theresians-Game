extends SceneTree

const HttpApiScript := preload("res://scripts/http_api.gd")

var failures: Array[String] = []


func _init() -> void:
	var api: Node = HttpApiScript.new()
	api.set("default_timeout_ms", 15000)
	_assert(api.has_method("_create_request"), "HttpApi must create requests with the configured timeout")
	if api.has_method("_create_request"):
		var default_request := api.call("_create_request", -1) as HTTPRequest
		_assert(default_request != null and is_equal_approx(default_request.timeout, 15.0), "the configured 15000ms timeout is applied to HTTPRequest")
		if default_request != null:
			default_request.queue_free()
		var explicit_request := api.call("_create_request", 1200) as HTTPRequest
		_assert(explicit_request != null and is_equal_approx(explicit_request.timeout, 1.2), "an explicit request timeout overrides the configured default")
		if explicit_request != null:
			explicit_request.queue_free()
	api.free()
	if failures.is_empty():
		print("HTTP_API_TIMEOUT_TEST: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("HTTP_API_TIMEOUT_TEST: FAIL")
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
