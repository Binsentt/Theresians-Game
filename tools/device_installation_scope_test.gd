extends Node

const GameStateScript = preload("res://scripts/game_state.gd")
var _checks: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	_expect(source.contains("device_installation_id"), "GameState persists the stable device installation identity")
	_expect(source.contains("get_device_installation_id"), "GameState exposes one stable device identity accessor")
	_expect(source.contains('"device_installation_id"'), "Save metadata includes the device installation identity")
	var state := GameStateScript.new()
	add_child(state)
	var first_id := String(state.call("get_device_installation_id"))
	var second_id := String(state.call("get_device_installation_id"))
	_expect(not first_id.is_empty(), "A device installation identity is always available")
	_expect(first_id == second_id, "The device installation identity is stable within a session")
	var owned := {"student_id": "87654321", "device_installation_id": first_id}
	state.student_id = "87654321"
	_expect(bool(state.call("_is_save_owned_by_current_student", owned)), "Current Student plus current device owns a save")
	_expect(not bool(state.call("_is_save_owned_by_current_student", {"student_id": "87654321", "device_installation_id": "other-device"})), "A different device cannot load the Student save")
	_expect(bool(state.call("_is_save_owned_by_current_student", {"student_id": "87654321"})), "Legacy Student-owned saves remain readable without changing the saved schema")
	_expect(not bool(state.call("_is_save_owned_by_current_student", {"player_name": "Legacy Device Save"})), "Ownerless legacy data remains hidden from the loader")
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
	print("DEVICE_INSTALLATION_SCOPE_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
