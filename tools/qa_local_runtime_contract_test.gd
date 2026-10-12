extends Node

var _checks: Array[Dictionary] = []

const QA_PROFILE_PATH := "res://Data/api_config.qa_local.json"
const ANDROID_QA_PROFILE_PATH := "res://Data/api_config.android_qa.json"
const ANDROID_QA_BASE_URL := "https://theresians-monitoring-system-qa-owner-testing.up.railway.app"
const TERMS_APP_ACCEPTANCE_PATH := "user://terms_app_acceptance.json"
const RESULT_PATH := "user://qa_local_runtime_contract_test_result.json"

var _had_original_terms_app_acceptance := false
var _original_terms_app_acceptance := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_terms_app_acceptance()
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	var game_state := get_node_or_null("/root/GameState")
	var http_source := FileAccess.get_file_as_string("res://scripts/http_api.gd")
	var remote_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	var state_source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var launcher_source := FileAccess.get_file_as_string("res://tools/human_qa_launcher.gd")
	var menu_source := FileAccess.get_file_as_string("res://scripts/main_menu_scene.gd")
	var save_delete_harness_source := FileAccess.get_file_as_string("res://tools/load_game_save_delete_test.gd")
	var export_presets_source := FileAccess.get_file_as_string("res://export_presets.cfg")
	var export_config := ConfigFile.new()
	var export_config_error := export_config.load("res://export_presets.cfg")
	var qa_profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(QA_PROFILE_PATH)) if FileAccess.file_exists(QA_PROFILE_PATH) else null
	var android_qa_profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(ANDROID_QA_PROFILE_PATH)) if FileAccess.file_exists(ANDROID_QA_PROFILE_PATH) else null
	_expect(http != null, "HttpApi autoload is available")
	_expect(remote != null, "RemoteSync autoload is available")
	_expect(game_state != null, "GameState autoload is available")
	_expect(http_source.contains("resolve_api_base_url"), "HttpApi owns the centralized API resolver")
	_expect(http_source.contains("QA_LOCAL_REMOTE_BLOCKED"), "HttpApi reports a blocked non-loopback QA target")
	_expect(remote_source.contains("LOCAL_QA_PENDING_FILE") and remote_source.contains("environment_scope"), "RemoteSync isolates and tags local QA outbox data")
	_expect(state_source.contains("LOCAL_QA_SAVE_DIRECTORY") and state_source.contains("enable_local_qa_mode"), "GameState exposes a QA-local save namespace")
	_expect(save_delete_harness_source.contains("GameState.get_save_directory()") and save_delete_harness_source.contains("test_runs/load_game_save_delete_"), "Save/delete fixtures are rooted in a unique run-specific QA directory")
	_expect(not save_delete_harness_source.contains("user://saves"), "Save/delete fixtures never address the ordinary player save directory")
	_expect(save_delete_harness_source.contains("remove_absolute(_absolute_path(_run_directory))"), "Save/delete cleanup removes only its exact isolated run directory")
	_expect(launcher_source.contains("enable_local_qa_mode") and launcher_source.contains("loading_screen.tscn"), "The QA launcher enables the boundary before the game flow")
	_expect(menu_source.contains("get_node_or_null(\"VBoxContainer/TermsPrivacyButton\")"), "Main Menu resolves the Terms and Privacy review button at its real scene path")
	_expect(qa_profile is Dictionary, "A dedicated QA-local profile exists before runtime startup")
	if qa_profile is Dictionary:
		_expect(String(qa_profile.get("api_base_url", "")) == "http://127.0.0.1:5000", "QA-local profile targets the loopback backend")
		_expect(qa_profile.get("production_qa_enabled", true) == false, "QA-local profile disables production QA mode")
		_expect(qa_profile.get("qa_local_only", false) == true, "QA-local profile declares loopback-only operation")
	_expect(http_source.contains("QA_LOCAL_PROFILE_PATH"), "HttpApi recognizes the dedicated QA-local profile before autoload requests")
	_expect(http_source.contains("OS.has_feature(\"android_qa\")"), "Android QA is selected from the exported custom feature at startup")
	_expect(export_presets_source.contains("name=\"Android QA\"") and export_presets_source.contains("custom_features=\"android_qa\""), "A dedicated Android QA export preset activates android_qa")
	_expect(export_config_error == OK, "Godot parses the configured export presets")
	if export_config_error == OK:
		_expect(String(export_config.get_value("preset.3", "name", "")) == "Android QA", "Preset 3 is the separate Android QA profile")
		_expect(String(export_config.get_value("preset.3", "custom_features", "")) == "android_qa", "Android QA preset embeds the android_qa feature")
		_expect(String(export_config.get_value("preset.3.options", "package/unique_name", "")) == "com.theresiansquest.game", "Android QA keeps the approved package ID")
		_expect(int(export_config.get_value("preset.3.options", "version/code", 0)) == 1, "Android QA uses version code 1")
		_expect(String(export_config.get_value("preset.3.options", "version/name", "")) == "0.0.0-qa", "Android QA uses version name 0.0.0-qa")
		_expect(bool(export_config.get_value("preset.3.options", "architectures/arm64-v8a", false)), "Android QA targets arm64-v8a")
		_expect(bool(export_config.get_value("preset.3.options", "permissions/internet", false)), "Android QA enables Internet permission")
		_expect(bool(export_config.get_value("preset.3.options", "package/signed", false)), "Android QA export signs the debug APK")
	_expect(http_source.contains("leaderboard_numeric_display_regression_test.tscn"), "The focused leaderboard runtime test selects the QA-local profile before autoload requests")
	_expect(http_source.contains("game_leaderboard_contract_test.tscn"), "The game leaderboard contract test selects the QA-local profile before autoload requests")
	_expect(http_source.contains("leaderboard_multi_row_regression_test.tscn"), "The leaderboard refresh test selects the QA-local profile before autoload requests")
	_expect(http_source.contains("load_game_identity_gate_test.tscn"), "The Load Game identity regression selects the QA-local profile before autoload requests")
	_expect(http_source.contains("telemetry_payload_resilience_test.tscn"), "The telemetry regression selects the QA-local profile before autoload requests")
	_expect(http_source.contains("original_flow_ingestion_test.tscn"), "The result-outbox and save-flush test selects the QA-local profile before autoload requests")
	_expect(http_source.contains("settings_ingame_regression_test.tscn"), "The Settings input regression test selects the QA-local profile before autoload requests")
	_expect(http_source.contains("deepest_forest_pinehill_flow_test.tscn"), "The Forest/Pinehill runtime test selects the QA-local profile before autoload requests")
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
	if http != null:
		_expect(FileAccess.file_exists(ANDROID_QA_PROFILE_PATH), "A dedicated Android QA API profile exists")
		_expect(android_qa_profile is Dictionary and String(android_qa_profile.get("api_base_url", "")) == ANDROID_QA_BASE_URL, "Android QA profile file contains only the approved Railway QA base URL")
		_expect(http.has_method("resolve_android_qa_profile"), "HttpApi exposes a fail-closed Android QA profile resolver")
		if http.has_method("resolve_android_qa_profile"):
			var qa_config := {"api_base_url": ANDROID_QA_BASE_URL, "production_qa_enabled": true, "production_url": "https://theresiansquest.com"}
			var valid_profile: Dictionary = http.call("resolve_android_qa_profile", qa_config)
			_expect(String(valid_profile.get("api_base_url", "")) == ANDROID_QA_BASE_URL, "android_qa selects the approved Railway QA URL")
			_expect(bool(valid_profile.get("config_valid", false)) and bool(valid_profile.get("remote_writes_enabled", false)), "The approved Android QA URL enables only its validated QA profile")
			var production_profile: Dictionary = http.call("resolve_android_qa_profile", {"api_base_url": "https://theresiansquest.com", "production_url": "https://theresiansquest.com"})
			_expect(not bool(production_profile.get("config_valid", true)) and not bool(production_profile.get("remote_writes_enabled", true)), "Production URL is rejected while resolving Android QA")
			_expect(String(production_profile.get("api_base_url", "")) == "", "Rejected Android QA config cannot fall through to production")
			var missing_profile: Dictionary = http.call("resolve_android_qa_profile", {})
			_expect(not bool(missing_profile.get("config_valid", true)) and not bool(missing_profile.get("remote_writes_enabled", true)), "Missing Android QA config disables remote writes")
			var invalid_profile: Dictionary = http.call("resolve_android_qa_profile", {"api_base_url": "http://127.0.0.1:5000"})
			_expect(not bool(invalid_profile.get("config_valid", true)) and not bool(invalid_profile.get("remote_writes_enabled", true)), "Invalid Android QA target disables remote writes instead of using localhost")
			_expect(bool(http.call("resolve_api_base_url", JSON.parse_string(FileAccess.get_file_as_string(QA_PROFILE_PATH)), true, false, true).begins_with("http://127.0.0.1")), "Local test mode continues to select localhost independently")
			_expect(String(valid_profile.get("api_base_url", "")) != String(production_profile.get("api_base_url", "")), "Android QA has no QA-to-production fallback")
		var api_probe = load("res://scripts/http_api.gd").new()
		var applied_qa_profile: Dictionary = api_probe.call("_apply_android_qa_profile", {"api_base_url": ANDROID_QA_BASE_URL, "production_qa_enabled": true, "production_url": "https://theresiansquest.com"})
		_expect(bool(applied_qa_profile.get("config_valid", false)) and bool(api_probe.get("android_qa_mode")) and String(api_probe.get("base_url")) == ANDROID_QA_BASE_URL, "Android QA profile overrides the production QA opt-in")
		_expect(bool(api_probe.call("_qa_request_allowed")), "Only the allowlisted QA base can issue Android QA requests")
		var rejected_profile: Dictionary = api_probe.call("_apply_android_qa_profile", {"api_base_url": "https://theresiansquest.com", "production_url": "https://theresiansquest.com"})
		_expect(not bool(rejected_profile.get("config_valid", true)) and String(api_probe.get("base_url")) == "", "Android QA refuses an active production base and leaves no fallback URL")
		_expect(not bool(api_probe.call("_qa_request_allowed")), "HTTP request guard blocks production while Android QA mode is active")
		var missing_applied: Dictionary = api_probe.call("_apply_android_qa_profile", {})
		_expect(not bool(missing_applied.get("remote_writes_enabled", true)) and String(api_probe.get("base_url")) == "", "Missing Android QA URL fails closed after startup profile application")
		api_probe.free()
	if remote != null and remote.has_method("enable_local_qa_mode"):
		remote.call("enable_local_qa_mode")
		_expect(bool(remote.get("local_qa_only")), "RemoteSync disables production writes in local QA")
		_expect(String(remote.get("_pending_file")).contains("local_qa"), "RemoteSync selects the local QA outbox")
	if remote != null:
		_expect(remote.has_method("configure_android_qa_mode"), "RemoteSync exposes an isolated Android QA outbox profile")
		if remote.has_method("configure_android_qa_mode"):
			remote.call("configure_android_qa_mode", true)
			_expect(bool(remote.get("android_qa_mode")) and bool(remote.get("android_qa_remote_writes_enabled")), "Validated Android QA enables QA-scoped remote sync")
			_expect(not bool(remote.call("_remote_writes_blocked")), "Validated Android QA allows writes only through its QA profile")
			_expect(String(remote.get("_pending_file")).contains("android_qa"), "Android QA uses a separate outbox from production and local QA")
			_expect(String(remote.call("_current_environment_scope")) == "android_qa", "Android QA outbox entries are scoped to the QA backend")
			remote.call("configure_android_qa_mode", false)
			_expect(bool(remote.get("android_qa_mode")) and not bool(remote.get("android_qa_remote_writes_enabled")), "Invalid Android QA profile keeps all remote writes disabled")
			_expect(bool(remote.call("_remote_writes_blocked")), "Invalid Android QA configuration blocks every RemoteSync write path")
			_expect(String(remote.get("_pending_file")).contains("android_qa"), "Invalid Android QA never opens the production outbox")
	if game_state != null and game_state.has_method("enable_local_qa_mode"):
		game_state.call("enable_local_qa_mode")
		_expect(String(game_state.call("get_save_directory")).contains("qa_local"), "GameState selects the local QA save namespace")
	await _run_terms_startup_checks()
	_restore_terms_app_acceptance()
	_expect(_terms_app_acceptance_is_restored(), "The QA harness restores the owner's pre-existing Terms acceptance record")
	_finish()


func _run_terms_startup_checks() -> void:
	const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")
	var game_state := get_node_or_null("/root/GameState")
	if FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_APP_ACCEPTANCE_PATH))
	var fade_stub := ColorRect.new()
	fade_stub.name = "Fade"
	add_child(fade_stub)
	var menu_stub := VBoxContainer.new()
	menu_stub.name = "VBoxContainer"
	add_child(menu_stub)
	var menu := MAIN_MENU_SCENE.instantiate() as Control
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	await get_tree().process_frame
	var first_gate := menu.get_node_or_null("TermsGate") as Control
	var first_new_game := menu.get_node_or_null("VBoxContainer/NewGameBtn") as BaseButton
	var first_load_game := menu.get_node_or_null("VBoxContainer/LoadGameBtn") as BaseButton
	var first_options := menu.get_node_or_null("VBoxContainer/OptionBtn") as BaseButton
	var first_quit := menu.get_node_or_null("VBoxContainer/QuitBtn") as BaseButton
	var first_terms_privacy := menu.get_node_or_null("VBoxContainer/TermsPrivacyButton") as BaseButton
	var first_leaderboard := menu.get_node_or_null("LeaderboardButton") as BaseButton
	_expect(first_gate != null and first_gate.visible, "Terms gate blocks the first Main Menu startup")
	_expect(first_new_game != null and first_new_game.disabled, "New Game is disabled before first-launch acceptance")
	_expect(first_load_game != null and first_load_game.disabled, "Load Game is disabled before first-launch acceptance")
	_expect(first_options != null and first_options.disabled, "Options is disabled before first-launch acceptance")
	_expect(first_quit != null and first_quit.disabled, "Quit is disabled before first-launch acceptance")
	_expect(first_terms_privacy != null and not first_terms_privacy.disabled, "Terms and Privacy remains available so the agreement can be reviewed before acceptance")
	_expect(first_leaderboard != null and first_leaderboard.disabled, "Leaderboard is disabled before first-launch acceptance")
	var first_checkbox := first_gate.get_node_or_null("Panel/Margin/Content/AgreementRow/AgreementCheckBox") as CheckBox if first_gate != null else null
	var first_continue := first_gate.get_node_or_null("Panel/Margin/Content/Actions/ContinueButton") as Button if first_gate != null else null
	if first_checkbox != null and first_continue != null:
		first_checkbox.button_pressed = true
		await get_tree().process_frame
		first_continue.pressed.emit()
		await get_tree().process_frame
	_expect(first_terms_privacy != null and not first_terms_privacy.disabled, "Terms and Privacy review becomes available after acceptance")
	if first_terms_privacy != null:
		first_terms_privacy.pressed.emit()
		await get_tree().process_frame
		var review_gate := menu.get_node_or_null("TermsPrivacyReview") as Control
		var review_checkbox := review_gate.get_node_or_null("Panel/Margin/Content/AgreementRow/AgreementCheckBox") as CheckBox if review_gate != null else null
		var review_continue := review_gate.get_node_or_null("Panel/Margin/Content/Actions/ContinueButton") as Button if review_gate != null else null
		var review_close := review_gate.get_node_or_null("Panel/Margin/Content/Actions/CancelButton") as Button if review_gate != null else null
		_expect(review_gate != null and review_gate.visible, "Terms and Privacy opens in a readable review overlay")
		_expect(review_checkbox != null and not review_checkbox.visible and review_continue != null and not review_continue.visible, "Review mode does not request acceptance again")
		_expect(review_close != null and review_close.visible and review_close.text == "CLOSE", "Review mode provides a visible Close action")
		if review_close != null:
			review_close.pressed.emit()
			await get_tree().process_frame
	var second_menu := MAIN_MENU_SCENE.instantiate() as Control
	get_tree().root.add_child(second_menu)
	get_tree().current_scene = second_menu
	await get_tree().process_frame
	await get_tree().process_frame
	var second_gate := second_menu.get_node_or_null("TermsGate") as Control
	var second_new_game := second_menu.get_node_or_null("VBoxContainer/NewGameBtn") as BaseButton
	var second_options := second_menu.get_node_or_null("VBoxContainer/OptionBtn") as BaseButton
	var second_quit := second_menu.get_node_or_null("VBoxContainer/QuitBtn") as BaseButton
	_expect(second_gate == null or not second_gate.visible, "Accepted Terms do not reopen during the same game session")
	_expect(second_new_game != null and not second_new_game.disabled, "Same-session acceptance leaves New Game available")
	_expect(second_options != null and not second_options.disabled, "Same-session acceptance leaves Options available")
	_expect(second_quit != null and not second_quit.disabled, "Same-session acceptance leaves Quit available")
	if game_state != null and game_state.has_method("reset_terms_session_acceptance"):
		game_state.call("reset_terms_session_acceptance")
	var third_menu := MAIN_MENU_SCENE.instantiate() as Control
	get_tree().root.add_child(third_menu)
	get_tree().current_scene = third_menu
	await get_tree().process_frame
	await get_tree().process_frame
	var third_gate := third_menu.get_node_or_null("TermsGate") as Control
	var third_new_game := third_menu.get_node_or_null("VBoxContainer/NewGameBtn") as BaseButton
	_expect(third_gate == null or not third_gate.visible, "Persisted app Terms acceptance survives a fresh menu/session")
	_expect(third_new_game != null and not third_new_game.disabled, "Persisted app Terms acceptance keeps New Game available after restart")
	menu.queue_free()
	second_menu.queue_free()
	third_menu.queue_free()
	if FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_APP_ACCEPTANCE_PATH))


func _capture_terms_app_acceptance() -> void:
	_had_original_terms_app_acceptance = FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH)
	_original_terms_app_acceptance = FileAccess.get_file_as_string(TERMS_APP_ACCEPTANCE_PATH) if _had_original_terms_app_acceptance else ""


func _restore_terms_app_acceptance() -> void:
	if FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_APP_ACCEPTANCE_PATH))
	if not _had_original_terms_app_acceptance:
		return
	var acceptance_file := FileAccess.open(TERMS_APP_ACCEPTANCE_PATH, FileAccess.WRITE)
	if acceptance_file != null:
		acceptance_file.store_string(_original_terms_app_acceptance)
		acceptance_file.close()


func _terms_app_acceptance_is_restored() -> bool:
	if FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH) != _had_original_terms_app_acceptance:
		return false
	if not _had_original_terms_app_acceptance:
		return true
	return FileAccess.get_file_as_string(TERMS_APP_ACCEPTANCE_PATH) == _original_terms_app_acceptance


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := 0
	for check in _checks:
		if not bool(check.get("passed", false)):
			failed += 1
	var result := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks}
	var result_file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(result))
		result_file.close()
	print("QA_LOCAL_RUNTIME_CONTRACT_TEST " + JSON.stringify(result))
	await get_tree().create_timer(45.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
