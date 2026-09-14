extends Node

const TERMS_APP_ACCEPTANCE_PATH := "user://terms_app_acceptance.json"
const TERMS_ACCEPTANCE_PATH := "user://terms_acceptance.json"
const TERMS_GATE_SCRIPT := preload("res://scripts/terms_gate.gd")
const RESULT_PATH := "user://terms_policy_contract_test_result.json"

var _checks: Array[Dictionary] = []
var _original_app := ""
var _had_original_app := false
var _original_student := ""
var _had_original_student := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_original_app = FileAccess.get_file_as_string(TERMS_APP_ACCEPTANCE_PATH)
	_had_original_app = FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH)
	_original_student = FileAccess.get_file_as_string(TERMS_ACCEPTANCE_PATH)
	_had_original_student = FileAccess.file_exists(TERMS_ACCEPTANCE_PATH)
	_clear_fixture_files()

	var state := get_node_or_null("/root/GameState")
	_expect(state != null, "GameState autoload is available")
	_expect(state != null and state.has_method("reset_terms_session_acceptance"), "Terms session state can be reset for a fresh debug run")
	_expect(state != null and state.has_method("has_terms_session_acceptance"), "Terms acceptance exposes session-only state")
	_expect(state != null and state.has_method("get_terms_app_acceptance_student_id"), "Device acceptance exposes its bound Student identity")
	_expect(state != null and state.has_method("is_debug_terms_run"), "Terms policy distinguishes debug/editor runs")
	_expect(state != null and state.has_method("record_terms_acceptance"), "Student-specific acceptance writer remains available")

	if state != null:
		state.call("reset_terms_session_acceptance")

	if state != null:
		_expect(bool(state.call("record_terms_app_acceptance")), "Terms acceptance unlocks the current debug session")
		_expect(bool(state.call("has_terms_session_acceptance")), "Acceptance is session-scoped during a debug run")
		_expect(bool(state.call("bind_current_terms_acceptance_to_student", "17000087")), "First Student binds the device acceptance")
		_expect(String(state.call("get_terms_app_acceptance_student_id")) == "17000087", "Device acceptance records the first Student identity")
		_expect(bool(state.call("has_current_terms_acceptance", "17000087")), "First Student remains accepted")
		_expect(not bool(state.call("has_current_terms_acceptance", "17000088")), "A different Student does not inherit acceptance")
		_expect(bool(state.call("record_terms_acceptance", "17000088")), "Second Student can accept independently")
		_expect(bool(state.call("has_current_terms_acceptance", "17000088")), "Second Student acceptance is persisted")
		_expect(bool(state.call("has_current_terms_acceptance", "17000087")), "First Student acceptance is preserved after a second Student accepts")
		var original_device_id := String(state.call("get_device_installation_id"))
		state.set("device_installation_id", "qa-fresh-installation-simulation")
		_expect(not bool(state.call("has_current_terms_app_acceptance")), "A fresh installation does not inherit device-level acceptance")
		_expect(not bool(state.call("has_current_terms_acceptance", "17000087")), "A fresh installation requires Student acceptance again")
		state.set("device_installation_id", original_device_id)
		_expect(bool(state.call("has_current_terms_acceptance", "17000087")), "Returning to the accepted installation restores the first Student acceptance")

	var review := TERMS_GATE_SCRIPT.new() as Control
	get_tree().root.add_child(review)
	review.call("set_review_mode", true)
	await get_tree().process_frame
	var review_checkbox := review.get_node_or_null("Panel/Margin/Content/AgreementRow/AgreementCheckBox") as CheckBox
	var review_continue := review.get_node_or_null("Panel/Margin/Content/Actions/ContinueButton") as Button
	var review_cancel := review.get_node_or_null("Panel/Margin/Content/Actions/CancelButton") as Button
	_expect(review_checkbox != null and not review_checkbox.visible, "Terms review mode hides the acceptance checkbox")
	_expect(review_continue != null and not review_continue.visible, "Terms review mode hides the Continue action")
	_expect(review_cancel != null and review_cancel.visible, "Terms review mode keeps a visible close action")

	_cleanup()
	_finish()


func _clear_fixture_files() -> void:
	if FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_APP_ACCEPTANCE_PATH))
	if FileAccess.file_exists(TERMS_ACCEPTANCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_ACCEPTANCE_PATH))


func _cleanup() -> void:
	if FileAccess.file_exists(TERMS_APP_ACCEPTANCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_APP_ACCEPTANCE_PATH))
	if FileAccess.file_exists(TERMS_ACCEPTANCE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERMS_ACCEPTANCE_PATH))
	if _had_original_app:
		var app_file := FileAccess.open(TERMS_APP_ACCEPTANCE_PATH, FileAccess.WRITE)
		if app_file != null:
			app_file.store_string(_original_app)
			app_file.close()
	if _had_original_student:
		var student_file := FileAccess.open(TERMS_ACCEPTANCE_PATH, FileAccess.WRITE)
		if student_file != null:
			student_file.store_string(_original_student)
			student_file.close()


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
	print("TERMS_POLICY_CONTRACT_TEST " + JSON.stringify(result))
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if failed == 0 else 1)
