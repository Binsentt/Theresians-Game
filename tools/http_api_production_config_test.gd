extends SceneTree

const CONFIG_PATH := "res://Data/api_config.json"
const EXPECTED_PRODUCTION_URL := "https://theresiansquest.com"
const EXPECTED_DEVELOPMENT_URL := "http://localhost:5000"
const QA_LOCAL_CONFIG_PATH := "res://Data/api_config.qa_local.json"
const EXPECTED_QA_LOCAL_URL := "http://127.0.0.1:5000"
const HttpApiScript := preload("res://scripts/http_api.gd")

var failures: Array[String] = []


func _init() -> void:
	var config: Variant = _load_config()
	_expect(config is Dictionary, "API configuration must be a JSON object.")
	if config is Dictionary:
		_verify_config(config)
		_verify_environment_resolution(config)
		_verify_invalid_production_config_fails_closed(config)
	if failures.is_empty():
		print("PASS: production API configuration is safe and environment-specific.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _load_config() -> Variant:
	var config_file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if config_file == null:
		failures.append("Unable to open " + CONFIG_PATH + ".")
		return null
	var parsed: Variant = JSON.parse_string(config_file.get_as_text())
	config_file.close()
	return parsed


func _verify_config(config: Dictionary) -> void:
	var production_url := String(config.get("production_url", "")).strip_edges()
	var development_url := String(config.get("development_url", "")).strip_edges()
	_expect(production_url == EXPECTED_PRODUCTION_URL, "production_url must be " + EXPECTED_PRODUCTION_URL + ".")
	_expect(not production_url.to_lower().contains("example.com"), "production_url must not use example.com.")
	_expect(not production_url.to_lower().contains("localhost"), "production_url must not use localhost.")
	_expect(development_url == EXPECTED_DEVELOPMENT_URL, "development_url must retain the explicit local-development endpoint.")
	_expect(not config.has("production_qa_enabled"), "Production QA must not be enabled by a committed config flag.")
	var allowed_keys := ["development_url", "production_url", "timeout_ms"]
	for key in config.keys():
		_expect(allowed_keys.has(String(key)), "API config must not contain API keys or other secrets.")


func _verify_environment_resolution(config: Dictionary) -> void:
	# Exercise the committed default as-is; production smoke testing is opt-in.
	var api: Node = HttpApiScript.new()
	_expect(api.has_method("resolve_configured_base_url"), "HttpApi must expose environment-specific URL resolution.")
	_expect(api.has_method("resolve_configured_base_url_for_environment"), "HttpApi must expose explicit production-smoke URL resolution.")
	if not api.has_method("resolve_configured_base_url") or not api.has_method("resolve_configured_base_url_for_environment"):
		api.free()
		return
	_expect(not bool(api.call("is_production_qa_enabled", config, false)), "Debug default must not enable production QA.")
	var legacy_opt_in_config := config.duplicate(true)
	legacy_opt_in_config["production_qa_enabled"] = true
	_expect(
		not bool(api.call("is_production_qa_enabled", legacy_opt_in_config, false)),
		"A legacy config flag alone must not enable production QA."
	)
	_expect(
		api.call("resolve_configured_base_url_for_environment", legacy_opt_in_config, true, false) == EXPECTED_DEVELOPMENT_URL,
		"A legacy config flag alone must not route a debug build to production."
	)
	_expect(bool(api.call("is_production_qa_enabled", config, true)), "Explicit production smoke opt-in must enable production QA.")
	_expect(bool(api.call("should_use_local_only_mode", true, false, false)), "Ordinary debug mode must isolate sync writes and outbox data.")
	_expect(not bool(api.call("should_use_local_only_mode", true, true, false)), "Explicit authorized production QA may use production sync.")
	_expect(not bool(api.call("should_use_local_only_mode", false, false, false)), "Release builds must not enter local-only mode.")
	_expect(bool(api.call("should_use_local_only_mode", false, false, true)), "Explicit local QA must remain local-only in every build.")
	_expect(api.call("resolve_configured_base_url_for_environment", config, true, false) == EXPECTED_DEVELOPMENT_URL, "Debug builds must resolve the development URL by default.")
	_expect(api.call("resolve_configured_base_url_for_environment", config, true, true) == EXPECTED_PRODUCTION_URL, "Explicit debug production-smoke mode must resolve the deployed HTTPS production URL.")
	_expect(api.call("resolve_configured_base_url_for_environment", config, false, false) == EXPECTED_PRODUCTION_URL, "Release builds must resolve the deployed HTTPS production URL.")
	_expect(api.call("resolve_configured_base_url_for_environment", config, false, true) == EXPECTED_PRODUCTION_URL, "Release builds must keep the deployed HTTPS production URL regardless of the debug-only smoke flag.")
	var qa_config: Variant = _load_config(QA_LOCAL_CONFIG_PATH)
	_expect(qa_config is Dictionary, "Explicit local QA profile must be valid JSON.")
	if qa_config is Dictionary:
		_expect(
			api.call("resolve_api_base_url", qa_config, true, true, true) == EXPECTED_QA_LOCAL_URL,
			"Explicit local QA selection must prefer its loopback URL over production smoke mode."
		)
	api.free()


func _verify_invalid_production_config_fails_closed(config: Dictionary) -> void:
	config = config.duplicate(true)
	var api: Node = HttpApiScript.new()
	if not api.has_method("resolve_configured_base_url_for_environment"):
		api.free()
		return
	var missing_production_config := config.duplicate(true)
	missing_production_config.erase("production_url")
	_expect(api.call("resolve_configured_base_url_for_environment", missing_production_config, false, false) == "", "A release build with no production URL must not fall back to localhost.")
	_expect(api.call("resolve_configured_base_url_for_environment", missing_production_config, true, true) == "", "Debug production-smoke mode with no production URL must fail closed instead of falling back to localhost.")
	_expect(api.call("resolve_configured_base_url_for_environment", missing_production_config, true, false) == EXPECTED_DEVELOPMENT_URL, "Debug default must retain the local-development URL when production smoke mode is not explicitly enabled.")
	var missing_development_config := config.duplicate(true)
	missing_development_config.erase("development_url")
	_expect(api.call("resolve_configured_base_url_for_environment", missing_development_config, true, false) == "", "Debug builds with no development URL must fail closed instead of falling back to production.")
	api.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
