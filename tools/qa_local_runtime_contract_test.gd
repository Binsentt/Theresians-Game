extends Node

var _checks: Array[Dictionary] = []

const QA_PROFILE_PATH := "res://Data/api_config.qa_local.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	var game_state := get_node_or_null("/root/GameState")
	var http_source := FileAccess.get_file_as_string("res://scripts/http_api.gd")
	var remote_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	var state_source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var launcher_source := FileAccess.get_file_as_string("res://tools/human_qa_launcher.gd")
	var qa_profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(QA_PROFILE_PATH)) if FileAccess.file_exists(QA_PROFILE_PATH) else null
	_expect(http != null, "HttpApi autoload is available")
	_expect(remote != null, "RemoteSync autoload is available")
	_expect(game_state != null, "GameState autoload is available")
	_expect(http_source.contains("resolve_api_base_url"), "HttpApi owns the centralized API resolver")
	_expect(http_source.contains("QA_LOCAL_REMOTE_BLOCKED"), "HttpApi reports a blocked non-loopback QA target")
	_expect(remote_source.contains("LOCAL_QA_PENDING_FILE") and remote_source.contains("environment_scope"), "RemoteSync isolates and tags local QA outbox data")
	_expect(state_source.contains("LOCAL_QA_SAVE_DIRECTORY") and state_source.contains("enable_local_qa_mode"), "GameState exposes a QA-local save namespace")
	_expect(launcher_source.contains("enable_local_qa_mode") and launcher_source.contains("loading_screen.tscn"), "The QA launcher enables the boundary before the game flow")
	_expect(qa_profile is Dictionary, "A dedicated QA-local profile exists before runtime startup")
	if qa_profile is Dictionary:
		_expect(String(qa_profile.get("api_base_url", "")) == "http://127.0.0.1:5000", "QA-local profile targets the loopback backend")
		_expect(qa_profile.get("production_qa_enabled", true) == false, "QA-local profile disables production QA mode")
		_expect(qa_profile.get("qa_local_only", false) == true, "QA-local profile declares loopback-only operation")
	_expect(http_source.contains("QA_LOCAL_PROFILE_PATH"), "HttpApi recognizes the dedicated QA-local profile before autoload requests")
	if http != null and http.has_method("resolve_api_base_url"):
		var config := JSON.parse_string(FileAccess.get_file_as_string("res://Data/api_config.json")) as Dictionary
		_expect(String(http.call("resolve_api_base_url", config, true, false, false)) == String(config.get("production_url", "")), "Normal production-QA resolution remains unchanged")
		var local_candidate := String(http.call("resolve_api_base_url", config, true, false, true))
		_expect(local_candidate.begins_with("http://localhost") or local_candidate.begins_with("http://127.0.0.1"), "Local QA resolution returns loopback only")
		_expect(not bool(http.call("is_loopback_url", "http://127.0.0.1.evil")), "QA loopback validation rejects a lookalike host")
		_expect(not bool(http.call("is_loopback_url", "http://localhost.evil")), "QA loopback validation rejects a localhost lookalike host")
		_expect(not bool(http.call("enable_local_qa_mode", "https://theresiansquest.com")), "Production URL is rejected by the QA boundary")
		_expect(bool(http.call("enable_local_qa_mode", "http://127.0.0.1:5000")), "Loopback URL is accepted by the QA boundary")
		_expect(not bool(http.call("is_loopback_url", "http://theresiansquest.com")), "Public hosts remain blocked by the QA resolver")
		_expect(bool(http.get("local_qa_only")) and not bool(http.get("production_qa_mode")), "HttpApi enters local-only mode")
	if remote != null and remote.has_method("enable_local_qa_mode"):
		remote.call("enable_local_qa_mode")
		_expect(bool(remote.get("local_qa_only")), "RemoteSync disables production writes in local QA")
		_expect(String(remote.get("_pending_file")).contains("local_qa"), "RemoteSync selects the local QA outbox")
	if game_state != null and game_state.has_method("enable_local_qa_mode"):
		game_state.call("enable_local_qa_mode")
		_expect(String(game_state.call("get_save_directory")).contains("qa_local"), "GameState selects the local QA save namespace")
	_finish()


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if not bool(check.get("passed", false)):
			failed += 1
	print("QA_LOCAL_RUNTIME_CONTRACT_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
