extends Node

signal request_completed(status_code: int, result: Dictionary)
signal request_failed(error: String)

const DEFAULT_CONFIG_PATH := "res://Data/api_config.json"
const QA_LOCAL_PROFILE_PATH := "res://Data/api_config.qa_local.json"
const PRODUCTION_SMOKE_TEST_ENVIRONMENT := "THERESIANS_PRODUCTION_SMOKE_TEST"
const QA_LOCAL_ENVIRONMENT_VARIABLE := "THERESIANS_QA_LOCAL"
const DEFAULT_LOCAL_QA_URL := "http://127.0.0.1:5000"
var base_url: String = ""
var default_timeout_ms: int = 10000
var production_qa_mode := false
var local_qa_only := false
var qa_local_profile_active := false
var config_source_path := DEFAULT_CONFIG_PATH

func _ready() -> void:
	var cfg: Dictionary = {}
	qa_local_profile_active = is_local_qa_profile_requested()
	config_source_path = QA_LOCAL_PROFILE_PATH if qa_local_profile_active else DEFAULT_CONFIG_PATH
	var config_file := FileAccess.open(config_source_path, FileAccess.READ)
	if config_file:
		var text := config_file.get_as_text()
		config_file.close()
		var parsed_config = JSON.parse_string(text)
		if typeof(parsed_config) == TYPE_DICTIONARY:
			cfg = parsed_config
			var debug_build := OS.is_debug_build()
			var production_smoke_test_enabled := is_production_qa_enabled(cfg, is_production_smoke_test_enabled())
			var local_qa_requested := qa_local_profile_active or is_local_qa_requested()
			production_qa_mode = debug_build and production_smoke_test_enabled and not local_qa_requested
			var configured_url := resolve_api_base_url(cfg, debug_build, production_smoke_test_enabled, local_qa_requested)
			var requires_production_url := (not debug_build and not local_qa_requested) or (production_smoke_test_enabled and not local_qa_requested)
			if local_qa_requested and not is_loopback_url(configured_url):
				base_url = ""
				local_qa_only = true
				push_error("QA_LOCAL_REMOTE_BLOCKED")
			elif _is_usable_base_url(configured_url, requires_production_url):
				base_url = configured_url.rstrip("/")
				if local_qa_requested:
					local_qa_only = true
			else:
				base_url = ""
				if local_qa_requested:
					push_error("QA_LOCAL_REMOTE_BLOCKED")
				else:
					push_warning("HttpApi: no usable API URL is configured for this build; remote API requests are disabled.")
			if debug_build:
				var mode_label := "LOCAL QA ONLY" if local_qa_only else ("PRODUCTION QA" if production_qa_mode else "LOCAL DEVELOPMENT")
				print("API MODE: " + mode_label + " — " + (base_url if base_url != "" else "disabled (invalid API URL)"))
				print("API CONFIG SOURCE: " + config_source_path)
				print("CANONICAL RUNTIME: pid=" + str(OS.get_process_id()) + " project=" + ProjectSettings.globalize_path("res://"))
			if cfg.has("timeout_ms"):
				default_timeout_ms = int(cfg.get("timeout_ms"))
	# no persistent HTTPRequest node: create per-request nodes to avoid blocking and allow concurrency


func enable_local_qa_mode(local_url: String = DEFAULT_LOCAL_QA_URL) -> bool:
	var candidate := local_url.strip_edges().rstrip("/")
	if candidate.is_empty():
		candidate = DEFAULT_LOCAL_QA_URL
	if not is_loopback_url(candidate):
		push_error("QA_LOCAL_REMOTE_BLOCKED")
		return false
	local_qa_only = true
	production_qa_mode = false
	base_url = candidate
	print("API MODE: LOCAL QA ONLY — " + base_url)
	return true


func is_local_qa_mode() -> bool:
	return local_qa_only


func is_local_qa_profile_active() -> bool:
	return qa_local_profile_active and local_qa_only and not production_qa_mode


func is_local_qa_requested() -> bool:
	return OS.get_environment(QA_LOCAL_ENVIRONMENT_VARIABLE).strip_edges() == "1"


func is_local_qa_profile_requested() -> bool:
	if is_local_qa_requested():
		return true
	for argument in OS.get_cmdline_args():
		var normalized := String(argument).replace("\\", "/").to_lower()
		if (
			normalized.ends_with("/human_qa_launcher.tscn")
			or normalized.ends_with("/qa_local_runtime_contract_test.tscn")
			or normalized.ends_with("/leaderboard_numeric_display_regression_test.tscn")
			or normalized.ends_with("/game_leaderboard_contract_test.tscn")
			or normalized.ends_with("/leaderboard_multi_row_regression_test.tscn")
			or normalized.ends_with("/original_flow_ingestion_test.tscn")
			or normalized.ends_with("/quest_telemetry_contract_test.tscn")
			or normalized.ends_with("/final_game_flow_state_test.tscn")
			or normalized.ends_with("/remote_sync_pending_queue_test.tscn")
			or normalized.ends_with("/quest_presentation_dialogue_regression_test.tscn")
			or normalized.ends_with("/map_ui_presentation_test.tscn")
			or normalized.ends_with("/live_defect_contract_test.tscn")
			or normalized.ends_with("/session_ux_layout_test.tscn")
		):
			return true
	return false


func get_resolved_api_base_url() -> String:
	return base_url


func resolve_api_base_url(
	config: Dictionary,
	is_debug_build: bool,
	production_smoke_test_enabled: bool,
	local_qa_requested: bool = false
) -> String:
	if local_qa_requested:
		return String(config.get("api_base_url", config.get("development_url", DEFAULT_LOCAL_QA_URL))).strip_edges()
	return resolve_configured_base_url_for_environment(config, is_debug_build, production_smoke_test_enabled)


func resolve_configured_base_url(config: Dictionary, is_debug_build: bool) -> String:
	return resolve_configured_base_url_for_environment(config, is_debug_build, is_production_smoke_test_enabled())


func resolve_configured_base_url_for_environment(config: Dictionary, is_debug_build: bool, production_smoke_test_enabled: bool) -> String:
	var config_key := "production_url" if not is_debug_build or is_production_qa_enabled(config, production_smoke_test_enabled) else "development_url"
	return String(config.get(config_key, "")).strip_edges()


func is_production_qa_enabled(config: Dictionary, environment_override: bool) -> bool:
	var configured_opt_in: Variant = config.get("production_qa_enabled", false)
	return environment_override or (configured_opt_in is bool and configured_opt_in)


func is_production_smoke_test_enabled() -> bool:
	return OS.get_environment(PRODUCTION_SMOKE_TEST_ENVIRONMENT).strip_edges() == "1"


func _is_usable_base_url(value: String, requires_production_url: bool = false) -> bool:
	var url := value.strip_edges().to_lower()
	if not (url.begins_with("https://") or url.begins_with("http://")) or url.contains("example.com"):
		return false
	if requires_production_url:
		return url.begins_with("https://") and not url.contains("localhost") and not url.contains("127.0.0.1")
	return true


func is_loopback_url(value: String) -> bool:
	var parsed := value.strip_edges().to_lower()
	const SCHEME := "http://"
	if not parsed.begins_with(SCHEME):
		return false
	var authority := parsed.substr(SCHEME.length())
	var path_start := authority.find("/")
	if path_start >= 0:
		authority = authority.substr(0, path_start)
	var query_start := authority.find("?")
	if query_start >= 0:
		authority = authority.substr(0, query_start)
	if authority.is_empty() or authority.contains("@"): # no user-info in a QA endpoint
		return false
	var host := authority
	if host.begins_with("["):
		var closing_bracket := host.find("]")
		if closing_bracket < 0:
			return false
		host = host.substr(1, closing_bracket - 1)
	else:
		var port_separator := host.find(":")
		if port_separator >= 0:
			host = host.substr(0, port_separator)
	return host == "localhost" or host == "127.0.0.1" or host == "::1"

func _build_url(path: String, params: Dictionary = {}) -> String:
	var url := path.strip_edges()
	if url.begins_with("/"):
		url = url.substr(1, url.length())
	var full := get_resolved_api_base_url().rstrip("/") + "/" + url
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


func _qa_request_allowed() -> bool:
	if local_qa_only and not is_loopback_url(base_url):
		push_error("QA_LOCAL_REMOTE_BLOCKED")
		return false
	return true


func _create_request(timeout_ms: int = -1) -> HTTPRequest:
	var http := HTTPRequest.new()
	var resolved_timeout_ms := timeout_ms if timeout_ms > 0 else default_timeout_ms
	http.timeout = maxf(1.0, float(resolved_timeout_ms) / 1000.0)
	add_child(http)
	return http

func request_get(path: String, params: Dictionary = {}, timeout_ms: int = -1) -> Dictionary:
	if not _qa_request_allowed():
		return {"ok": false, "error": "Local QA boundary rejected a non-loopback API base."}
	var url := _build_url(path, params)
	var http := _create_request(timeout_ms)
	var trace_profile := production_qa_mode and path.trim_prefix("/").begins_with("api/game/profile/check/")
	if trace_profile:
		print("PROFILE CHECK REQUEST: pid=" + str(OS.get_process_id()) + " GET " + base_url + "/api/game/profile/check/[STUDENT]?parent_id=[PARENT]")
	var err := http.request(url, [], HTTPClient.METHOD_GET, "")
	if err != OK:
		if trace_profile:
			print("PROFILE CHECK START ERROR: pid=" + str(OS.get_process_id()) + " error_code=" + str(err))
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
	if trace_profile:
		var request_result := int(args[0]) if not args.is_empty() else -1
		print("PROFILE CHECK RESPONSE: pid=" + str(OS.get_process_id()) + " " + JSON.stringify(profile_check_diagnostic(request_result, response_code, parsed)))
	http.queue_free()
	return {"ok": true, "status": response_code, "body": parsed}


func profile_check_diagnostic(result_code: int, response_code: int, response: Dictionary) -> Dictionary:
	# Deliberately exclude identifiers, canonical profile contents and free-form messages.
	return {
		"result": result_code,
		"http_status": response_code,
		"canonical_profile_present": response.get("canonical_profile") is Dictionary,
		"can_play": response.get("can_play", null),
		"should_block": response.get("should_block", null)
	}

func request_post(path: String, payload: Dictionary, timeout_ms: int = -1) -> Dictionary:
	if not _qa_request_allowed():
		return {"ok": false, "error": "Local QA boundary rejected a non-loopback API base."}
	var url := _build_url(path, {})
	var body := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]
	var http := _create_request(timeout_ms)
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
