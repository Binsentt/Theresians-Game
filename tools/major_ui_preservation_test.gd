extends "res://tools/final_ui_preservation_test.gd"
## Fresh evidence wrapper; inherited UI checks and gameplay helpers are unchanged.

var _major_run_stamp := "%d-%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()]
var _major_output_path := ""
var _major_capture_index := 0
var _major_captures: Array[String] = []

func _ready() -> void:
	# Root siblings cannot be removed while the fixture enters the tree.
	# Disable live transport now; deferred _run removes it before fixture work.
	var live_http := get_node_or_null("/root/HttpApi")
	if live_http != null:
		live_http.set("base_url", "")
		live_http.process_mode = Node.PROCESS_MODE_DISABLED
	var live_sync := get_node_or_null("/root/RemoteSync")
	if live_sync != null:
		live_sync.process_mode = Node.PROCESS_MODE_DISABLED
	super._ready()

func _run() -> void:
	_major_output_path = _major_unique_path("res://docs/qa/2026-09-07-major-ui-runtime-" + _major_run_stamp, "json")
	print("MAJOR_UI_OUTPUT " + _major_output_path)
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		get_node("/root/" + autoload_name).free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.fixture_path = _major_unique_path("user://saves/major_ui_" + _major_run_stamp, "json")
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	for scene_path in [OAK, TEACHER]:
		await _normal_scene(scene_path)
	await _silent_maps()
	await _world_dialogue("Bandit")
	for dimensions in VIEWPORTS:
		await _tutorial_layout_at(dimensions)
	var failed := checks.filter(func(check: Dictionary) -> bool: return not check.passed).size()
	var result := {"passed":checks.size() - failed, "failed":failed, "checks":checks,
		"normal":normal_observed, "shared_world":observed, "tutorial":tutorial_observations, "pointer_events":pointer_events,
		"canonical_root":ProjectSettings.globalize_path("res://"), "live_network_calls":0}
	result["run_stamp"] = _major_run_stamp
	result["output"] = _major_output_path
	result["fixture_path"] = state.fixture_path
	result["captures"] = _major_captures.duplicate()
	var output := FileAccess.open(_major_output_path, FileAccess.WRITE)
	if output == null:
		push_error("Cannot create fresh major UI evidence")
		get_tree().quit(1)
		return
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	print("MAJOR_UI_PRESERVATION_TEST " + JSON.stringify({"passed":checks.size() - failed, "failed":failed}))
	get_tree().quit(1 if failed else 0)

func _capture_ui(label: String) -> void:
	await RenderingServer.frame_post_draw
	_major_capture_index += 1
	var stem := "res://docs/qa/2026-09-07-major-ui-" + _major_run_stamp + "-%03d-" % _major_capture_index + label
	var path := _major_unique_path(stem, "png")
	var saved := get_viewport().get_texture().get_image().save_png(path) == OK
	_expect(saved, "Fresh major UI capture saved: " + label)
	if saved:
		_major_captures.append(path)

func _major_unique_path(stem: String, extension: String) -> String:
	var path := stem + "." + extension
	var suffix := 1
	while FileAccess.file_exists(path):
		path = stem + "-%d." % suffix + extension
		suffix += 1
	return path
