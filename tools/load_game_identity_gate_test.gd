extends Node

const STUDENT_A := "88000011"
const STUDENT_B := "88000012"
const PARENT_A := "880011"
const PARENT_B := "880012"
const SAVE_A := "user://saves/save_identity_gate_a.json"
const SAVE_B := "user://saves/save_identity_gate_b.json"
const LOAD_SCENE := preload("res://load_game_scene.tscn")

var _failures: Array[String] = []


class ProfileHttpStub extends Node:
	func request_get(path: String, params: Dictionary = {}) -> Dictionary:
		var student_code := path.get_file()
		var parent_code := String(params.get("parent_id", ""))
		var valid := (student_code == STUDENT_A and parent_code == PARENT_A) \
				or (student_code == STUDENT_B and parent_code == PARENT_B)
		if not valid:
			return {"ok": false, "status": 403, "body": {"error": "Student and Parent IDs are not linked."}}
		return {
			"ok": true,
			"status": 200,
			"body": {
				"ok": true,
				"can_play": true,
				"canonical_profile": {
					"student_id": student_code,
					"parent_id": parent_code,
					"name": "Identity Gate Fixture",
					"grade_level": "Grade 3",
				},
			},
		}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	_configure_stubs()
	_cleanup()
	_write_save(SAVE_A, STUDENT_A, PARENT_A)
	_write_save(SAVE_B, STUDENT_B, PARENT_B)
	GameState.student_id = ""
	GameState.parent_id = ""

	var scene := LOAD_SCENE.instantiate() as Control
	get_tree().current_scene = self
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame
	var student_input := scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityFields/StudentIdInput") as LineEdit
	var parent_input := scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityFields/ParentIdInput") as LineEdit
	var verify_button := scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityFields/VerifyButton") as Button
	var status_label := scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityStatusLabel") as Label
	_assert(student_input != null and parent_input != null and verify_button != null and status_label != null, "Load Game renders the Student/Parent ownership gate")
	_assert(_rendered_paths(scene).is_empty(), "Cold Load Game exposes no saves before Student ownership is verified")

	if scene.has_method("_verify_save_owner") and student_input != null and parent_input != null:
		student_input.text = STUDENT_A
		parent_input.text = PARENT_A
		await scene.call("_verify_save_owner")
		await get_tree().process_frame
		_assert(GameState.student_id == STUDENT_A and GameState.parent_id == PARENT_A, "Correct Student A relationship establishes the canonical owner")
		_assert(_rendered_paths(scene) == [SAVE_A], "Verified Student A sees only Student A saves")

		student_input.text = STUDENT_B
		parent_input.text = PARENT_A
		await scene.call("_verify_save_owner")
		await get_tree().process_frame
		_assert(GameState.student_id == STUDENT_A and _rendered_paths(scene) == [SAVE_A], "Wrong Parent cannot switch or expose another Student")
		_assert(status_label.visible and not status_label.text.is_empty(), "Rejected ownership verification shows a clear validation message")

		student_input.text = STUDENT_B
		parent_input.text = PARENT_B
		await scene.call("_verify_save_owner")
		await get_tree().process_frame
		_assert(GameState.student_id == STUDENT_B and GameState.parent_id == PARENT_B, "Correct Student B relationship switches the canonical owner")
		_assert(_rendered_paths(scene) == [SAVE_B], "Verified Student B sees only Student B saves")
	else:
		_assert(false, "Load Game exposes read-only Student/Parent verification")

	scene.queue_free()
	await get_tree().process_frame
	_cleanup()
	_finish()


func _configure_stubs() -> void:
	var remote := get_node_or_null("/root/RemoteSync")
	if remote != null:
		remote.set_script(load("res://tools/load_game_ux_remote_stub.gd"))
	var live_http := get_node_or_null("/root/HttpApi")
	if live_http != null:
		get_tree().root.remove_child(live_http)
		live_http.free()
	var stub := ProfileHttpStub.new()
	stub.name = "HttpApi"
	get_tree().root.add_child(stub)


func _write_save(path: String, owner_id: String, relationship_id: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create %s" % path)
		return
	file.store_string(JSON.stringify({
		"save_version": GameState.SAVE_VERSION,
		"student_id": owner_id,
		"parent_id": relationship_id,
		"player_name": "Identity Gate Fixture",
		"grade_level": "Grade 3",
		"gender": "female",
		"scene_path": "res://interiors/player_house.tscn",
		"save_timestamp": 100,
	}))
	file.close()


func _rendered_paths(scene: Control) -> Array[String]:
	var paths: Array[String] = []
	var container := scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer")
	if container == null:
		return paths
	for entry in container.get_children():
		paths.append(String(entry.get("save_path")))
	return paths


func _cleanup() -> void:
	for path in [SAVE_A, SAVE_B]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var report := {"passed": 9 - _failures.size(), "failed": _failures.size(), "failures": _failures}
	var file := FileAccess.open("res://tools/load_game_identity_gate_test_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if _failures.is_empty():
		print("LOAD_GAME_IDENTITY_GATE_TEST PASSED")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOAD_GAME_IDENTITY_GATE_TEST FAILED")
	get_tree().quit(1)
