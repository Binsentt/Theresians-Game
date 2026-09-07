extends "res://tools/normal_dialogue_size_test.gd"
## Reuses the approved UI checks without overwriting earlier evidence.

func _ready() -> void:
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is HTTPRequest:
			node.free()
			push_error("UI fixture rejected a live HTTPRequest node")
			get_tree().quit(2)
	)
	_run.call_deferred()

func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		get_node("/root/" + autoload_name).free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.fixture_path = "user://saves/final_ui_%d.json" % Time.get_ticks_usec()
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
	var output := FileAccess.open("res://docs/qa/2026-09-07-final-ui-runtime.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	print("FINAL_UI_PRESERVATION_TEST " + JSON.stringify({"passed":checks.size() - failed, "failed":failed}))
	get_tree().quit(1 if failed else 0)

func _capture_ui(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/2026-09-07-final-ui-" + label + ".png")
