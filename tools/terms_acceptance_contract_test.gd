extends Node

const GameStateScript = preload("res://scripts/game_state.gd")
const RESULT_PATH := "user://terms_acceptance_contract_test_result.json"
var _checks: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var state_source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var login_source := FileAccess.get_file_as_string("res://scenes/texture_rect_2.gd")
	var menu_source := FileAccess.get_file_as_string("res://scripts/main_menu_scene.gd")
	var gate_source := FileAccess.get_file_as_string("res://scripts/terms_gate.gd")
	_expect(state_source.contains("TERMS_VERSION"), "Terms acceptance has an explicit version")
	_expect(state_source.contains("terms_acceptance"), "Terms acceptance is stored in a local record")
	_expect(state_source.contains("terms_version") and state_source.contains("accepted_at"), "Terms record keeps version and acceptance time")
	_expect(login_source.contains("_ensure_terms_accepted"), "New Game checks Terms before gameplay")
	_expect(menu_source.contains("TERMS_GATE_SCRIPT") and menu_source.contains("_initialize_terms_gate"), "Main Menu owns the startup Terms gate")
	_expect(gate_source.contains("AgreementCheckBox") and gate_source.contains("ContinueButton"), "Terms gate uses a checkbox and Continue action")
	_expect(gate_source.contains("disabled = true") and gate_source.contains("_on_checkbox_toggled"), "Continue starts disabled and follows checkbox state")
	_expect(login_source.contains("bind_current_terms_acceptance_to_student"), "New Game binds app acceptance to the known Student ID")
	_expect(not login_source.contains("func() -> void: accepted = true"), "Student-specific Terms acceptance does not rely on a captured primitive flag")
	_expect(not login_source.contains("func() -> void: cancelled = true"), "Student-specific Terms cancellation does not rely on a captured primitive flag")
	_expect(login_source.contains("completion_state"), "Student-specific Terms gate shares completion state with its signal callbacks")
	_expect(login_source.contains("request_playtime_session") and login_source.find("_ensure_terms_accepted") < login_source.find("request_playtime_session"), "Terms gate runs before playtime/game start")
	var state := GameStateScript.new()
	add_child(state)
	_expect(state.has_method("has_current_terms_acceptance"), "GameState exposes current Terms validation")
	_expect(state.has_method("record_terms_acceptance"), "GameState exposes one Terms acceptance writer")
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
	var result := {"passed": _checks.size() - failed, "failed": failed, "checks": _checks}
	var result_file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(result))
	print("TERMS_ACCEPTANCE_CONTRACT_TEST " + JSON.stringify(result))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
