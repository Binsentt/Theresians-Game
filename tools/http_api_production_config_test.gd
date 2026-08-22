extends SceneTree

const CONFIG_PATH := "res://Data/api_config.json"
const EXPECTED_PRODUCTION_URL := "https://theresiansquest.com"
const EXPECTED_DEVELOPMENT_URL := "http://localhost:5000"
const HttpApiScript := preload("res://scripts/http_api.gd")

var failures: Array[String] = []


func _init() -> void:
	var config: Variant = _load_config()
	_expect(config is Dictionary, "API configuration must be a JSON object.")
	if config is Dictionary:
		_verify_config(config)
		_verify_environment_resolution(config)
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
	var allowed_keys := ["development_url", "production_url", "timeout_ms"]
	for key in config.keys():
		_expect(allowed_keys.has(String(key)), "API config must not contain API keys or other secrets.")


func _verify_environment_resolution(config: Dictionary) -> void:
	var api: Node = HttpApiScript.new()
	_expect(api.has_method("resolve_configured_base_url"), "HttpApi must expose environment-specific URL resolution.")
	if not api.has_method("resolve_configured_base_url"):
		api.free()
		return
	_expect(api.call("resolve_configured_base_url", config, false) == EXPECTED_PRODUCTION_URL, "Release builds must resolve the deployed HTTPS production URL.")
	_expect(api.call("resolve_configured_base_url", config, true) == EXPECTED_DEVELOPMENT_URL, "Debug builds must resolve only the explicit local-development URL.")
	api.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
