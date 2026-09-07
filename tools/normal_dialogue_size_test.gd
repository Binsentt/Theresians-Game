extends "res://tools/tutorial_layout_lifecycle_test.gd"

const NORMAL_RESULT := "res://docs/qa/2026-09-07-normal-dialogue-runtime.json"
const LONG_FIXTURE := "This longer dialogue checks that every word stays readable inside the original padded box. The shared container must wrap the text and keep its bottom margin without covering the action button."
var normal_observed: Array[Dictionary] = []

func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		get_node("/root/" + autoload_name).free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	state.fixture_path = "user://saves/normal_dialogue_%d.json" % Time.get_ticks_usec()
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	for scene_path in [OAK, TEACHER]:
		await _normal_scene(scene_path)
	await _silent_maps()
	await _world_dialogue("Bandit")
	await _tutorial_layout_at(Vector2i(844, 390))
	var failed := checks.filter(func(check: Dictionary) -> bool: return not check.passed).size()
	var result := {"passed":checks.size() - failed, "failed":failed, "checks":checks,
		"normal":normal_observed, "shared_world":observed, "tutorial":tutorial_observations, "pointer_events":pointer_events,
		"canonical_root":ProjectSettings.globalize_path("res://"), "live_network_calls":0}
	var output := FileAccess.open(NORMAL_RESULT, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	print("NORMAL_DIALOGUE_SIZE_TEST " + JSON.stringify({"passed":checks.size() - failed, "failed":failed}))
	get_tree().quit(1 if failed else 0)

func _normal_scene(scene_path: String) -> void:
	state.start_new_game(PROFILE, false)
	state.complete_tutorial_activity()
	state.current_task_index = 1
	var scene := await _load(scene_path)
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	for actor in scene.find_children("*", "CharacterBody2D", true, false):
		actor.set_physics_process(false)
	var panel := scene.get_node("CanvasLayer/DialoguePanel") as Control
	var ui := scene.get_node("CanvasLayer/Panel")
	var label := panel.get_node("DialogueLabel") as Label
	var style := panel.get_theme_stylebox("panel")
	var font := label.get_theme_font("font")
	var expected_width := 460.0 if scene_path == TEACHER else 520.0
	var expected_height := 126.0 if scene_path == TEACHER else 80.0
	var actors := ["Teacher"] if scene_path == TEACHER else ["girl_npc", "NPC", "villager-female", "NPC1"]
	for actor_name in actors:
		player.global_position = Vector2(-4000, -4000)
		await _physics(4)
		var actor := scene.get_node(actor_name)
		var area := actor.find_child("Area2D2" if scene_path == TEACHER else "Area2D", true, false)
		var sensor := area.get_node_or_null("CollisionShape2D") as Node2D if area != null else null
		_expect(sensor != null, actor_name + " existing interaction sensor found")
		if sensor == null:
			continue
		player.global_position = sensor.global_position
		await _physics(5)
		_touch(scene, true)
		await _frames(12)
		_expect(ui.is_dialogue_active() and ui.get_dialogue_line_index() == 0, scene_path + "/" + actor_name + " held opening press leaves first line intact")
		_touch(scene, false)
		await _frames(3)
		for dimensions in VIEWPORTS:
			await _resize_window(dimensions)
			_measure(scene, actor_name, "original-content", expected_width, expected_height)
			await _capture_ui(actor_name + "-" + str(dimensions.x))
		_expect(panel.get_theme_stylebox("panel") == style and label.get_theme_font("font") == font and label.get_theme_font_size("font_size") == 22, actor_name + " original style and font retained")
		if scene_path == OAK:
			_expect(label.text == "Hello traveler! Welcome to our town.", actor_name + " exact greeting unchanged")
			actor.set_physics_process(true)
			var position_before: Vector2 = actor.global_position
			await _physics(10)
			_expect(actor.global_position.is_equal_approx(position_before), actor_name + " dialogue still pauses wandering")
			actor.set_physics_process(false)
			await _tap(scene)
			_expect(not ui.is_dialogue_active() and state.current_task_index == 1 and state.get_mode() == state.GameMode.EXPLORATION, actor_name + " deliberate close preserves quest and resumes exploration")
		else:
			await _tap(scene)
			_expect(ui.get_dialogue_line_index() == 1 and ui.is_dialogue_active() and state.current_task_index == 1, "Teacher one press advances exactly one line without completing early")
			await _tap(scene)
			_expect(not ui.is_dialogue_active() and state.current_task_index == 2, "Teacher existing final deliberate close completes its task once")
		_expect(not panel.visible and _button(scene, "up").is_visible_in_tree() and _button(scene).is_visible_in_tree(), actor_name + " existing control lifecycle restored")
	# Stress wrapping with runtime-only text; no NPC dialogue resource is edited.
	for dimensions in VIEWPORTS:
		await _resize_window(dimensions)
		state.push_mode(state.GameMode.DIALOGUE)
		ui.begin_dialogue([LONG_FIXTURE, "Short line."])
		await _frames(5)
		_measure(scene, "long-fixture", "long", expected_width, expected_height, true)
		await _capture_ui(("teacher" if scene_path == TEACHER else "oakleaf") + "-long-" + str(dimensions.x))
		_expect(label.text == LONG_FIXTURE and label.get_line_count() >= 3, "Long fixture retains all text and wraps into multiple lines")
		await _tap(scene)
		_expect(label.text == "Short line." and ui.get_dialogue_line_index() == 1, "Long fixture continuation advances once")
		_measure(scene, "short-after-long", "short", expected_width, expected_height)
		await _tap(scene)
		state.pop_mode()
		_expect(not panel.visible, "Long fixture final deliberate close still works")

func _measure(scene: Node, actor_name: String, stage: String, expected_width: float, expected_height: float, long_text: bool = false) -> void:
	var panel := scene.get_node("CanvasLayer/DialoguePanel") as Control
	var label := panel.get_node("DialogueLabel") as Label
	var rect := panel.get_global_rect()
	var viewport := panel.get_viewport_rect().size
	var inner := label.get_global_rect()
	var prefix := actor_name + " " + stage + " " + str(get_window().size) + ": "
	var geometry := {"scene":scene.scene_file_path, "actor":actor_name, "stage":stage, "window":str(get_window().size), "viewport":str(viewport), "width":rect.size.x, "height":rect.size.y, "rect":str(rect), "label_rect":str(inner), "line_count":label.get_line_count(), "visible_lines":label.get_visible_line_count(), "label_minimum":str(label.get_minimum_size())}
	for property in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom"]:
		geometry[property] = panel.get(property)
	normal_observed.append(geometry)
	print("NORMAL_DIALOGUE_GEOMETRY " + JSON.stringify(geometry))
	_expect(absf(rect.size.x - expected_width) < 1.5, prefix + "width slightly increased")
	_expect(rect.size.y >= expected_height - 1.5 if long_text else absf(rect.size.y - expected_height) < 1.5, prefix + "compact normal height; long text can fit naturally")
	_expect(absf(rect.get_center().x - viewport.x * 0.5) < 1.5 and absf(viewport.y - rect.end.y - 40.0) < 1.5, prefix + "bottom-center with preserved 40px margin")
	_expect(inner.position.x - rect.position.x >= 17.5 and rect.end.x - inner.end.x >= 17.5 and inner.position.y - rect.position.y >= 11.5 and rect.end.y - inner.end.y >= 11.5, prefix + "original 18px horizontal and 12px vertical padding")
	_expect(label.get_visible_line_count() == label.get_line_count() and label.size.y + 1.0 >= label.get_minimum_size().y, prefix + "all wrapped lines fit without clipping")
	_expect(not rect.intersects(_button(scene).get_global_rect()) and not _button(scene, "up").is_visible_in_tree(), prefix + "clear of ACT with normal dialogue D-pad lifecycle")

func _silent_maps() -> void:
	for scene_path in [CITY, "res://scenes/pinehill_village.tscn"]:
		var scene := await _load(scene_path)
		var speakers := 0
		for node in scene.find_children("*", "", true, false):
			if node.has_method("begin_dialogue") or node.has_method("show_dialogue_timed"):
				speakers += 1
		_expect(speakers == 0 and scene.find_children("DialoguePanel", "", true, false).is_empty(), scene_path + " unchanged: no existing shared civilian dialogue component (N/A)")

func _physics(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame

func _capture_ui(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/2026-09-07-normal-dialogue-" + label + ".png")
