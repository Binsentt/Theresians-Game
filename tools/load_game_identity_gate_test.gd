extends Node

const STUDENT_A := "88000011"
const STUDENT_B := "88000012"
const PARENT_A := "880011"
const PARENT_B := "880012"
const SAVE_A := "user://saves/save_identity_gate_a.json"
const SAVE_B := "user://saves/save_identity_gate_b.json"
const LEGACY_SAVE := "user://saves/save_identity_gate_legacy.json"
const LOAD_SCENE := preload("res://load_game_scene.tscn")

var _failures: Array[String] = []


class ProfileHttpStub extends Node:
	var request_count := 0

	func request_get(path: String, params: Dictionary = {}) -> Dictionary:
		request_count += 1
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
	GameState.set_script(load("res://tools/load_game_ux_test_state.gd"))
	var fixture_paths: Array[String] = [SAVE_A, SAVE_B, LEGACY_SAVE]
	GameState.fixture_paths = fixture_paths
	_cleanup()
	_write_save(SAVE_A, STUDENT_A, PARENT_A, 100, "Device Student A")
	_write_save(SAVE_B, STUDENT_B, PARENT_B, 200, "Device Student B")
	_write_legacy_save()
	GameState.student_id = STUDENT_A
	GameState.parent_id = PARENT_A

	var scene := LOAD_SCENE.instantiate() as Control
	get_tree().current_scene = self
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityPromptLabel") == null, "Load Game has no Verify Student prompt")
	_assert(scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityFields") == null, "Load Game has no Student ID, Parent ID, or Verify controls")
	_assert(scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityStatusLabel") == null, "Load Game has no verification instruction/status label")
	_assert(not scene.has_method("_verify_save_owner"), "Load Game has no backend owner-verification handler")
	_assert(_rendered_paths(scene) == [SAVE_A], "Load Game lists only saves owned by the current Student")
	var http_stub := get_node_or_null("/root/HttpApi")
	var remote_stub := get_node_or_null("/root/RemoteSync")
	_assert(http_stub != null and int(http_stub.get("request_count")) == 0, "Listing local saves emits no profile-check request")
	_assert(remote_stub != null and int(remote_stub.get("learning_cycle_request_count")) == 0, "Listing local saves emits no RemoteSync request")

	_assert(GameState.peek_save_data(SAVE_B).is_empty(), "Student A cannot inspect Student B save by direct path")
	_assert(GameState.load_save(SAVE_B, false).is_empty(), "Student A cannot load Student B save by direct path")
	_assert(GameState.student_id == STUDENT_A and GameState.parent_id == PARENT_A, "Rejected cross-Student load preserves the current identity")
	_assert(FileAccess.file_exists(LEGACY_SAVE), "An ownerless legacy file is preserved rather than deleted by listing")

	GameState.student_id = STUDENT_B
	GameState.parent_id = PARENT_B
	scene.call("_refresh_save_list")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_rendered_paths(scene) == [SAVE_B], "Switching the established session to Student B shows only Student B saves")

	GameState.student_id = ""
	GameState.parent_id = ""
	scene.call("_refresh_save_list")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_rendered_paths(scene).is_empty(), "No established Student identity exposes no local saves")
	var game_state_source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var remote_sync_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	_assert(game_state_source.contains('const SAVE_DIRECTORY := "user://saves"'), "Save files remain in Godot's application-local user storage")
	_assert(remote_sync_source.contains('game_state.connect("save_created"') and remote_sync_source.contains('request_post("/api/game/progress"'), "RemoteSync still uploads approved monitoring/progress projections")
	_assert(not remote_sync_source.contains("GameState.list_saves") and not remote_sync_source.contains("GameState.load_save") and not remote_sync_source.contains("user://saves"), "RemoteSync has zero code paths that download, enumerate, or reconstruct local save files")

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


func _write_save(path: String, owner_id: String, relationship_id: String, timestamp: int, player_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create %s" % path)
		return
	file.store_string(JSON.stringify({
		"save_version": GameState.SAVE_VERSION,
		"student_id": owner_id,
		"parent_id": relationship_id,
		"player_name": player_name,
		"grade_level": "Grade 3",
		"gender": "female",
		"scene_path": "res://interiors/player_house.tscn",
		"current_task_index": 3,
		"save_timestamp": timestamp,
	}))
	file.close()


func _write_legacy_save() -> void:
	var file := FileAccess.open(LEGACY_SAVE, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create %s" % LEGACY_SAVE)
		return
	file.store_string(JSON.stringify({
		"player_name": "Legacy Device Save",
		"scene_path": "res://interiors/player_house.tscn",
		"save_timestamp": 50,
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
	for path in [SAVE_A, SAVE_B, LEGACY_SAVE]:
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
	var report := {"passed": 16 - _failures.size(), "failed": _failures.size(), "failures": _failures}
	var file := FileAccess.open("res://tools/load_game_identity_gate_test_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if _failures.is_empty():
		print("LOAD_GAME_IDENTITY_GATE_TEST PASSED checks=16 failures=0")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOAD_GAME_IDENTITY_GATE_TEST FAILED checks=16 failures=%d" % _failures.size())
	get_tree().quit(1)
