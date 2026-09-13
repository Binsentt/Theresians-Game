extends Node

const GameStateScript = preload("res://scripts/game_state.gd")
var _checks: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var state_source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var login_source := FileAccess.get_file_as_string("res://scenes/texture_rect_2.gd")
	_expect(state_source.contains("TERMS_VERSION"), "Terms acceptance has an explicit version")
	_expect(state_source.contains("terms_acceptance"), "Terms acceptance is stored in a local record")
	_expect(state_source.contains("terms_version") and state_source.contains("accepted_at"), "Terms record keeps version and acceptance time")
	_expect(login_source.contains("_ensure_terms_accepted"), "New Game checks Terms before gameplay")
	_expect(login_source.contains("CheckBox") and login_source.contains("get_ok_button"), "Terms gate uses a checkbox and disabled Continue action")
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
	print("TERMS_ACCEPTANCE_CONTRACT_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
