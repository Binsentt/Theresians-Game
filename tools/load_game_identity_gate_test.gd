extends Node

const STUDENT_A := "88000011"
const STUDENT_B := "88000012"
const PARENT_A := "880011"
const PARENT_B := "880012"
const LOAD_SCENE := preload("res://load_game_scene.tscn")
const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")
const LOAD_GAME_SCENES := [
	"res://load_game_scene.tscn",
	"res://scenes/load_game_scene.tscn",
]

var _failures: Array[String] = []
var _check_count := 0
var _qa_save_directory := ""
var _created_qa_save_directory := false
var _previous_save_directory := ""
var _save_a := ""
var _save_b := ""
var _legacy_save := ""


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
	# This runner must never touch the normal save namespace or use a live API
	# configuration. Switch the real autoloads to local-only before installing
	# the deterministic stubs used by this test.
	var live_http := get_node_or_null("/root/HttpApi")
	if live_http != null and live_http.has_method("enable_local_qa_mode"):
		live_http.call("enable_local_qa_mode", "http://127.0.0.1:5000")
	var live_remote := get_node_or_null("/root/RemoteSync")
	if live_remote != null and live_remote.has_method("enable_local_qa_mode"):
		live_remote.call("enable_local_qa_mode")
	GameState.set_script(load("res://tools/load_game_ux_test_state.gd"))
	if GameState.has_method("enable_local_qa_mode"):
		GameState.call("enable_local_qa_mode")
	_previous_save_directory = String(GameState.get_save_directory())
	_qa_save_directory = "%s/identity_gate_%d_%d" % [
		GameState.LOCAL_QA_SAVE_DIRECTORY,
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	var absolute_qa_directory := ProjectSettings.globalize_path(_qa_save_directory)
	if DirAccess.dir_exists_absolute(absolute_qa_directory):
		_failures.append("Refusing to reuse an existing identity-gate QA directory")
		await _finish()
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_qa_directory)
	if directory_error != OK:
		_failures.append("Could not create the isolated identity-gate QA directory")
		await _finish()
		return
	_created_qa_save_directory = true
	GameState.set("_save_directory", _qa_save_directory)
	_save_a = _qa_save_directory + "/save_identity_gate_a.json"
	_save_b = _qa_save_directory + "/save_identity_gate_b.json"
	_legacy_save = _qa_save_directory + "/save_identity_gate_legacy.json"
	_assert(_qa_save_directory.begins_with(GameState.LOCAL_QA_SAVE_DIRECTORY + "/") and not _qa_save_directory.begins_with(GameState.SAVE_DIRECTORY + "/"), "Identity-gate fixtures use a unique local QA directory, never user://saves")
	_configure_stubs()
	var fixture_paths: Array[String] = [_save_a, _save_b, _legacy_save]
	GameState.fixture_paths = fixture_paths
	_write_save(_save_a, STUDENT_A, PARENT_A, 100, "Device Student A")
	_write_save(_save_b, STUDENT_B, PARENT_B, 200, "Device Student B")
	_write_legacy_save()
	GameState.student_id = ""
	GameState.parent_id = ""

	var scene := LOAD_SCENE.instantiate() as Control
	get_tree().current_scene = self
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate") == null, "Load Game has no identity-entry gate")
	_assert(scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate/IdentityFields/StudentIdInput") == null, "Load Game has no Student ID input")
	_assert(scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate/IdentityFields/ParentIdInput") == null, "Load Game has no Parent ID input")
	_assert(scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate/IdentityFields/VerifyButton") == null, "Load Game has no Verify button")
	_assert(not scene.has_method("_verify_save_owner"), "Load Game does not retain a manual verification handler")
	_assert(_rendered_paths(scene).is_empty(), "A missing current Student session exposes no saved games")
	var empty_message := scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/EmptyLabel") as Label
	_assert(empty_message != null and empty_message.visible and empty_message.text.contains("New Game"), "Unauthenticated empty state directs the player to the existing sign-in flow")
	_assert(_scenes_have_no_search_or_verification_controls(), "Both Load Game scenes contain no search or verification-style UI")
	var compatibility_scene := (load("res://scenes/load_game_scene.tscn") as PackedScene).instantiate() as Control
	get_tree().root.add_child(compatibility_scene)
	await get_tree().process_frame
	_assert(compatibility_scene.get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer") != null, "Compatibility Load Game path instantiates the canonical themed save list")
	compatibility_scene.queue_free()
	await get_tree().process_frame
	var http_stub := get_node_or_null("/root/HttpApi")
	var remote_stub := get_node_or_null("/root/RemoteSync")
	_assert(http_stub != null and int(http_stub.get("request_count")) == 0, "Fresh Load Game does not emit a profile-check request automatically")
	_assert(remote_stub != null and int(remote_stub.get("learning_cycle_request_count")) == 0, "Listing local saves emits no RemoteSync request")

	GameState.student_id = STUDENT_A
	GameState.parent_id = PARENT_A
	scene.call("_refresh_save_list")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_rendered_paths(scene) == [_save_a], "Load Game lists only saves owned by the authenticated Student A session")

	_assert(GameState.peek_save_data(_save_b).is_empty(), "Student A cannot inspect Student B save by direct path")
	_assert(GameState.load_save(_save_b, false).is_empty(), "Student A cannot load Student B save by direct path")
	_assert(GameState.student_id == STUDENT_A and GameState.parent_id == PARENT_A, "Rejected cross-Student load preserves the current identity")
	_assert(FileAccess.file_exists(_legacy_save), "An ownerless legacy file is preserved rather than deleted by listing")

	GameState.student_id = ""
	GameState.parent_id = ""
	scene.call("_refresh_save_list")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_rendered_paths(scene).is_empty(), "Clearing the session identity hides all saves")
	GameState.student_id = STUDENT_B
	GameState.parent_id = PARENT_B
	scene.call("_refresh_save_list")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_rendered_paths(scene) == [_save_b], "After Student B is authenticated only Student B saves appear")

	GameState.student_id = ""
	GameState.parent_id = ""
	scene.call("_refresh_save_list")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_rendered_paths(scene).is_empty(), "No established Student identity exposes no local saves")
	await _assert_save_entry_location_presentation()
	var game_state_source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var remote_sync_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	var leaderboard_source := FileAccess.get_file_as_string("res://scripts/leaderboard_scene_controller.gd")
	_assert(game_state_source.contains('const SAVE_DIRECTORY := "user://saves"'), "Save files remain in Godot's application-local user storage")
	_assert(remote_sync_source.contains('game_state.connect("save_created"') and remote_sync_source.contains('request_post("/api/game/progress"'), "RemoteSync still uploads approved monitoring/progress projections")
	_assert(not remote_sync_source.contains("GameState.list_saves") and not remote_sync_source.contains("GameState.load_save") and not remote_sync_source.contains("user://saves"), "RemoteSync has zero code paths that download, enumerate, or reconstruct local save files")
	_assert(leaderboard_source.contains("GameState.list_saves().is_empty()") and leaderboard_source.contains("No rankings yet"), "Leaderboard stays empty without a current Student-owned save instead of using stale identity")

	scene.queue_free()
	await get_tree().process_frame
	_cleanup()
	await _finish()


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_qa_save_directory))
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
	var file := FileAccess.open(_legacy_save, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create %s" % _legacy_save)
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


func _scenes_have_no_search_or_verification_controls() -> bool:
	for scene_path in LOAD_GAME_SCENES:
		var source := FileAccess.get_file_as_string(scene_path)
		if source.is_empty() or source.contains("StudentIdInput") or source.contains("ParentIdInput") \
				or source.contains("VerifyButton") or source.contains("IdentityGate") \
				or source.contains("Search") or source.contains("Verify"):
			return false
	return true


func _assert_save_entry_location_presentation() -> void:
	var entry := SAVE_ENTRY_SCENE.instantiate() as Control
	entry.set_slot_number(7)
	get_tree().root.add_child(entry)
	await get_tree().process_frame
	var thumbnail := entry.get_node_or_null("MarginContainer/Content/ThumbnailPanel/Thumbnail") as TextureRect
	var slot_number := entry.get_node_or_null("MarginContainer/Content/SlotBadge/BadgeContent/SlotNumber") as Label
	var slot_caption := entry.get_node_or_null("MarginContainer/Content/SlotBadge/BadgeContent/SlotCaption") as Label
	_assert(slot_caption != null and slot_caption.text == "SAVE", "Save card uses a simple current-save badge")
	_assert(slot_number != null and slot_number.text == "7", "Save card shows the supplied per-Student manual-save order number")
	var cases := [
		{"scene": "res://scenes/oak_leaf_village.tscn", "location": "Oak Leaf", "texture": "res://Images/LoadGame/oak_leaf.png"},
		{"scene": "res://scenes/2nd Village/Pinehill Village.tscn", "location": "Pinehill", "texture": "res://Images/LoadGame/pinehill.png"},
		{"scene": "res://scenes/city_of_knowledge.tscn", "location": "City of Knowledge", "texture": "res://Images/LoadGame/city_of_knowledge.png"},
		{"scene": "res://interiors/player_house.tscn", "location": "House", "texture": "res://Images/LoadGame/house.png"},
		{"scene": "res://interiors/teacher_house.tscn", "location": "House", "texture": "res://Images/LoadGame/house.png"},
		{"scene": "res://interiors/npc_house.tscn", "location": "House", "texture": "res://Images/LoadGame/house.png"},
		{"scene": "res://interiors/school.tscn", "location": "School", "texture": "res://Images/LoadGame/school.png"},
	]
	_assert(thumbnail != null, "Save slot provides a location thumbnail")
	for case_data: Dictionary in cases:
		entry.setup({
			"save_path": "user://fixture.json",
			"player_name": "Synthetic Student",
			"grade_level": "Grade 3",
			"scene_path": case_data.scene,
			"current_quest": "Test quest",
			"save_date": "2026-09-29",
			"save_time": "10:20:30",
			"total_play_time": 3661,
			"loadable": true,
		})
		var location_label := entry.get_node_or_null("MarginContainer/Content/Details/LocationLabel") as Label
		_assert(location_label != null and location_label.text.contains(String(case_data.location)), "Scene location displays its mapped label: %s" % case_data.scene)
		_assert(thumbnail != null and thumbnail.texture != null and thumbnail.texture.resource_path == String(case_data.texture), "Scene location displays its mapped thumbnail: %s" % case_data.scene)
	var saved_label := entry.get_node_or_null("MarginContainer/Content/Details/SavedLabel") as Label
	var playtime_label := entry.get_node_or_null("MarginContainer/Content/Details/PlaytimeLabel") as Label
	_assert(saved_label != null and saved_label.text.contains("2026-09-29") and saved_label.text.contains("10:20:30"), "Save card shows the existing saved date and time fields")
	_assert(playtime_label != null and playtime_label.text.contains("1h 1m"), "Save card formats the existing accumulated playtime field")
	entry.setup({"scene_path": "res://scenes/unknown_location.tscn", "player_name": "Unknown", "current_quest": "Quest"})
	_assert(thumbnail != null and thumbnail.texture != null and thumbnail.texture.resource_path == "res://Images/Background-Menu.png", "Unknown scene paths use the safe themed fallback thumbnail")
	entry.queue_free()


func _cleanup() -> void:
	if not _created_qa_save_directory or _qa_save_directory.is_empty():
		return
	var safe_prefix := _qa_save_directory.rstrip("/") + "/"
	for path in [_save_a, _save_b, _legacy_save]:
		if not String(path).begins_with(safe_prefix):
			push_error("Refusing identity-gate cleanup outside its unique QA directory")
			continue
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_qa_save_directory))
	GameState.set("_save_directory", _previous_save_directory)
	_created_qa_save_directory = false


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _assert(condition: bool, message: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var report := {"passed": _check_count - _failures.size(), "failed": _failures.size(), "failures": _failures}
	var file := FileAccess.open("user://load_game_identity_gate_test_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if _failures.is_empty():
		print("LOAD_GAME_IDENTITY_GATE_TEST PASSED checks=%d failures=0" % _check_count)
	else:
		for failure in _failures:
			push_error(failure)
		print("LOAD_GAME_IDENTITY_GATE_TEST FAILED checks=%d failures=%d" % [_check_count, _failures.size()])
	await get_tree().create_timer(45.0).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
