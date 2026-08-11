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
	# create a single HTTPRequest child used for all calls
	var http := HTTPRequest.new()
	http.name = "__HttpApiRequest"
	add_child(http)

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
	var http := get_node_or_null("__HttpApiRequest")
	if http == null:
		push_error("HttpApi: missing HTTPRequest node")
		return {"ok": false, "error": "no_http_request"}
	var url := _build_url(path, params)
	var t := timeout_ms > 0 ? timeout_ms : default_timeout_ms
	var err := http.request(url, [], false, HTTPClient.METHOD_GET, null, t)
	if err != OK:
		return {"ok": false, "error": str(err)}
	# wait for completion
	var res = await_signal(http, "request_completed")
	if res and res.size() >= 3:
		var code = int(res[0])
		var body = res[2]
		var parsed = {}
		if typeof(body) == TYPE_STRING and body != "":
			var j = JSON.parse_string(body)
			if j.error == OK:
				parsed = j.result
		return {"ok": true, "status": code, "body": parsed}
	return {"ok": false, "error": "no_response"}

func post(path: String, payload: Dictionary, timeout_ms: int = -1) -> Dictionary:
	var http := get_node_or_null("__HttpApiRequest")
	if http == null:
		push_error("HttpApi: missing HTTPRequest node")
		return {"ok": false, "error": "no_http_request"}
	var url := _build_url(path, {})
	var t := timeout_ms > 0 ? timeout_ms : default_timeout_ms
	var body := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]
	var err := http.request(url, headers, false, HTTPClient.METHOD_POST, body, t)
	if err != OK:
		return {"ok": false, "error": str(err)}
	var res = await_signal(http, "request_completed")
	if res and res.size() >= 3:
		var code = int(res[0])
		var bodyText = res[2]
		var parsed = {}
		if typeof(bodyText) == TYPE_STRING and bodyText != "":
			var j = JSON.parse_string(bodyText)
			if j.error == OK:
				parsed = j.result
		return {"ok": true, "status": code, "body": parsed}
	return {"ok": false, "error": "no_response"}

# compatibility helper for await signal
func await_signal(node: Node, signal_name: String) -> Array:
	var completed := false
	var result := []
	var conn = null
	func _on_signal(a, b, c, d, e):
		result = [a, b, c, d, e]
		completed = true
		if conn:
			node.disconnect(signal_name, self, "_on_signal")
	conn = node.connect(signal_name, self, "_on_signal")
	while not completed:
		OS.delay_msec(10)
	return result
