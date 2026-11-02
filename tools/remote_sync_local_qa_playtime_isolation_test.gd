extends SceneTree

const EXPECTED_LOCAL_API_URL := "http://127.0.0.1:5000"
const QA_LOCAL_ENV := "THERESIANS_QA_LOCAL"
const PRODUCTION_SMOKE_ENV := "THERESIANS_PRODUCTION_SMOKE_TEST"

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment(QA_LOCAL_ENV).strip_edges() != "1" \
			or OS.get_environment(PRODUCTION_SMOKE_ENV).strip_edges() == "1":
		printerr("REMOTE_SYNC_LOCAL_QA_PLAYTIME_TEST: REFUSED unsafe test environment.")
		quit(2)
		return

	var http := get_root().get_node_or_null("HttpApi")
	var remote := get_root().get_node_or_null("RemoteSync")
	_expect(http != null, "HttpApi autoload is present.")
	_expect(remote != null, "RemoteSync autoload is present.")
	if http == null or remote == null:
		_finish()
		return

	_expect(String(http.call("get_resolved_api_base_url")) == EXPECTED_LOCAL_API_URL, "Explicit local QA resolves only to loopback.")
	_expect(bool(remote.get("local_qa_only")), "RemoteSync starts in local-only mode.")
	_expect(bool(remote.call("_remote_writes_blocked")), "Local QA blocks RemoteSync writes.")
	var result: Dictionary = await remote.call("request_playtime_session", {})
	_expect(not bool(result.get("ok", false)), "A local-only playtime request is denied.")
	_expect(String(result.get("error", "")).contains("Local QA mode disables playtime writes"), "The block returns a clear local-only error without requiring a response body.")
	_expect(int(remote.get("_current_playtime_session_id")) == 0, "A blocked request cannot create a session identity.")
	_expect(String(remote.get("_current_playtime_session_credential")).is_empty(), "A blocked request cannot create a session credential.")
	_finish()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
	printerr("FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("REMOTE_SYNC_LOCAL_QA_PLAYTIME_TEST: PASS checks=%d" % _checks)
		quit(0)
		return
	printerr("REMOTE_SYNC_LOCAL_QA_PLAYTIME_TEST: FAIL checks=%d failures=%d" % [_checks, _failures.size()])
	quit(1)
