extends SceneTree

const API_CONFIG_PATH := "res://Data/api_config.json"
const PRODUCTION_SMOKE_ENV := "THERESIANS_PRODUCTION_SMOKE_TEST"
const QA_LOCAL_ENV := "THERESIANS_QA_LOCAL"
const PRODUCTION_PENDING_FILE := "user://pending_syncs.json"
const LOCAL_QA_PENDING_FILE := "user://pending_syncs_local_qa.json"

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment(PRODUCTION_SMOKE_ENV).strip_edges() == "1":
		printerr("DEBUG_API_STARTUP_ISOLATION_TEST: REFUSED production smoke environment is set.")
		quit(2)
		return
	if OS.get_environment(QA_LOCAL_ENV).strip_edges() == "1":
		printerr("DEBUG_API_STARTUP_ISOLATION_TEST: REFUSED explicit local-QA override masks the default startup path.")
		quit(2)
		return

	var http := get_root().get_node_or_null("HttpApi")
	var remote := get_root().get_node_or_null("RemoteSync")
	_expect(http != null, "HttpApi autoload is present.")
	_expect(remote != null, "RemoteSync autoload is present.")
	if http == null or remote == null:
		_finish()
		return

	var parsed_config: Variant = JSON.parse_string(FileAccess.get_file_as_string(API_CONFIG_PATH))
	_expect(parsed_config is Dictionary, "The committed API configuration loads.")
	if not (parsed_config is Dictionary):
		_finish()
		return

	var debug_build := OS.is_debug_build()
	var expected_url := String(parsed_config.get("development_url", "")) if debug_build else String(parsed_config.get("production_url", ""))
	_expect(not expected_url.is_empty(), "The selected environment URL is configured.")
	_expect(String(http.call("get_resolved_api_base_url")) == expected_url, "The actual autoload resolves to the URL for this engine build mode.")
	_expect(not bool(http.get("production_qa_mode")), "Ordinary startup never enables production QA.")
	_expect(bool(http.get("local_qa_only")) == debug_build, "Only debug startup is local-only by default.")
	_expect(bool(remote.get("local_qa_only")) == debug_build, "RemoteSync receives the safe startup mode from HttpApi.")
	_expect(
		String(remote.get("_pending_file")) == (LOCAL_QA_PENDING_FILE if debug_build else PRODUCTION_PENDING_FILE),
		"Debug and Release startup select their separate existing pending-sync files."
	)
	_expect(bool(remote.call("_remote_writes_blocked")) == debug_build, "Debug sync writes are blocked while Release sync behavior remains enabled.")
	_expect(
		String(remote.call("_current_environment_scope")) == ("local_qa" if debug_build else "production"),
		"The outbox environment scope follows the actual build mode."
	)

	_finish()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
	printerr("FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("DEBUG_API_STARTUP_ISOLATION_TEST: PASS checks=%d" % _checks)
		quit(0)
		return
	printerr("DEBUG_API_STARTUP_ISOLATION_TEST: FAIL checks=%d failures=%d" % [_checks, _failures.size()])
	quit(1)
