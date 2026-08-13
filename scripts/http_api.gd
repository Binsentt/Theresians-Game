xtends Node

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
		var parsed_config = JSON.parse_string(text)
		if typeof(parsed_config) == TYPE_DICTIONARY:
			var cfg: Dictionary = parsed_config
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
	if not params.is_empty():
		var query := ""
		var keys := params.keys()
		for index in range(keys.size()):
			var key_text := String(keys[index])
			var value_text := String(params[keys[index]])
			if index > 0:
				query += "&"
			query += key_text.uri_encode() + "=" + value_text.uri_encode()
		full += "?" + query
	return full

func request_get(path: String, params: Dictionary = {}, timeout_ms: int = -1) -> Dictionary:
	var url := _build_url(path, params)
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, [], HTTPClient.METHOD_GET, "")
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": str(err)}
	var args = await http.request_completed
	# args: result, response_code, headers, body
	var response_code: int = int(args[1]) if args.size() > 1 else 0
	var raw_body = args[3] if args.size() > 3 else null
	var body_text := ""
	if raw_body != null:
		if typeof(raw_body) == TYPE_PACKED_BYTE_ARRAY:
			body_text = raw_body.get_string_from_utf8()
		elif typeof(raw_body) == TYPE_STRING:
			body_text = raw_body
	var parsed: Dictionary = {}
	if body_text != "":
		var parsed_body = JSON.parse_string(body_text)
		if typeof(parsed_body) == TYPE_DICTIONARY:
			parsed = parsed_body
	http.queue_free()
	return {"ok": true, "status": response_code, "body": parsed}

func request_post(path: String, payload: Dictionary, timeout_ms: int = -1) -> Dictionary:
	var url := _build_url(path, {})
	var body := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": str(err)}
	var args = await http.request_completed
	var response_code: int = int(args[1]) if args.size() > 1 else 0
	var raw_body = args[3] if args.size() > 3 else null
	var body_text := ""
	if raw_body != null:
		if typeof(raw_body) == TYPE_PACKED_BYTE_ARRAY:
			body_text = raw_body.get_string_from_utf8()
		elif typeof(raw_body) == TYPE_STRING:
			body_text = raw_body
	var parsed: Dictionary = {}
	if body_text != "":
		var parsed_body = JSON.parse_string(body_text)
		if typeof(parsed_body) == TYPE_DICTIONARY:
			parsed = parsed_body
	http.queue_free()
	return {"ok": true, "status": response_code, "body": parsed}

