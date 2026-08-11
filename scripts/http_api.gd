extends Node

signal request_completed(status_code: int, result: Dictionary)
signal request_failed(error: String)

const DEFAULT_CONFIG_PATH := "res://Data/api_config.json"
var base_url: String = "http://localhost:5000"
var default_timeout_ms: int = 10000

func _ready() -> void:
	var config_file := FileAccess.open(DEFAULT_CONFIG_PATH, FileAccess.READ)
	if config_file:
		var text := config_file.get_as_text()
		config_file.close()
		var json := JSON.parse_string(text)
		if json.error == OK and typeof(json.result) == TYPE_DICTIONARY:
			var cfg := json.result
			if cfg.has("development_url"):
				base_url = String(cfg.get("development_url"))
			if cfg.has("timeout_ms"):
				default_timeout_ms = int(cfg.get("timeout_ms"))
	# no persistent HTTPRequest node: create per-request nodes to avoid blocking and allow concurrency

func _build_url(path: String, params: Dictionary = {}) -> String:
	var url := path.strip_edges()
	if url.begins_with("/"):
		url = url.substr(1, url.length())
	var full := base_url.rstrip("/") + "/" + url
	if params and params.size() > 0:
		var pairs := []
		for k in params.keys():
			var v = str(params[k])
			pairs.append(URI.encode_component(str(k)) + "=" + URI.encode_component(v))
		full += "?" + String(pairs.join("&"))
	return full

func get(path: String, params: Dictionary = {}, timeout_ms: int = -1) -> Dictionary:
	var url := _build_url(path, params)
	var t := timeout_ms > 0 ? timeout_ms : default_timeout_ms
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, [], false, HTTPClient.METHOD_GET, null, t)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": str(err)}
	var args = await http.request_completed
	# args: result, response_code, headers, body
	var response_code = args.size() > 1 ? int(args[1]) : 0
	var raw_body = args.size() > 3 ? args[3] : null
	var body_text = ""
	if raw_body != null:
		if typeof(raw_body) == TYPE_PACKED_BYTE_ARRAY:
			body_text = raw_body.get_string_from_utf8()
		elif typeof(raw_body) == TYPE_STRING:
			body_text = raw_body
	var parsed = {}
	if body_text != "":
		var j = JSON.parse_string(body_text)
		if j.error == OK:
			parsed = j.result
	http.queue_free()
	return {"ok": true, "status": response_code, "body": parsed}

func post(path: String, payload: Dictionary, timeout_ms: int = -1) -> Dictionary:
	var url := _build_url(path, {})
	var t := timeout_ms > 0 ? timeout_ms : default_timeout_ms
	var body := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, false, HTTPClient.METHOD_POST, body, t)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": str(err)}
	var args = await http.request_completed
	var response_code = args.size() > 1 ? int(args[1]) : 0
	var raw_body = args.size() > 3 ? args[3] : null
	var body_text = ""
	if raw_body != null:
		if typeof(raw_body) == TYPE_PACKED_BYTE_ARRAY:
			body_text = raw_body.get_string_from_utf8()
		elif typeof(raw_body) == TYPE_STRING:
			body_text = raw_body
	var parsed = {}
	if body_text != "":
		var j = JSON.parse_string(body_text)
		if j.error == OK:
			parsed = j.result
	http.queue_free()
	return {"ok": true, "status": response_code, "body": parsed}

