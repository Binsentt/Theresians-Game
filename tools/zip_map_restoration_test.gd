extends "res://tools/preservation_restoration_test.gd"

const ORIGINAL_TEXTURE := "res://Grass n Dirt/free-fields-tileset-pixel-art-for-tower-defense/TileSet_V2.png"
const MAPS := [OAK, CITY, "res://scenes/2nd Village/Pinehill Village.tscn"]
var observations: Dictionary = {}

func _run() -> void:
	# Test-only isolation: no account/backend/production or normal save writes.
	get_node("/root/RemoteSync").free()
	get_node("/root/HttpApi").free()
	state = get_node("/root/GameState")
	state.set_script(load("res://tools/preservation_regression_state.gd"))
	inputs = get_node("/root/InputManager")
	interactions = get_node("/root/InteractionManager")
	get_tree().current_scene = null
	state.start_new_game(PROFILE, false)
	state.complete_tutorial_activity()
	state.current_task_index = 1
	for map_path in MAPS:
		await _map(map_path)
	await _doors()
	await _presentation()
	var failed := 0
	for check in checks:
		if not check.passed:
			failed += 1
	var output := FileAccess.open("user://hud_runtime_map_qa_20260926_verified.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": checks.size() - failed, "failed": failed, "checks": checks, "observations": observations}, "\t"))
	output.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.fixture_path))
	print("ZIP_MAP_RESTORATION_TEST " + JSON.stringify({"passed": checks.size() - failed, "failed": failed}))
	get_tree().quit(0 if failed == 0 else 1)

func _map(path: String) -> void:
	var scene := await _load(path)
	state.set_mode(state.GameMode.MENU)
	var layers := scene.find_children("*", "TileMapLayer", true, false)
	var expected_count := 5 if path == OAK else (11 if path == CITY else 6)
	_expect(layers.size() == expected_count, path + " all original map layers load")
	var map_details: Array[Dictionary] = []
	var replacement_found := false
	for layer in layers:
		var affected_sources: Array[int] = []
		for index in layer.tile_set.get_source_count():
			var source_id: int = layer.tile_set.get_source_id(index)
			var source = layer.tile_set.get_source(source_id)
			if source is TileSetAtlasSource and source.texture != null and "TileSet_V2" in source.texture.resource_path:
				affected_sources.append(source_id)
				var matches: bool = source.texture.resource_path == ORIGINAL_TEXTURE and source.texture.get_size() == Vector2(256, 640)
				replacement_found = replacement_found or not matches
				_expect(matches, path + ":" + str(scene.get_path_to(layer)) + " uses ZIP original texture")
		var invalid_used := 0
		for cell in layer.get_used_cells():
			if layer.get_cell_source_id(cell) in affected_sources:
				var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
				if atlas.x < 0 or atlas.y < 0 or atlas.x >= 8 or atlas.y >= 20:
					invalid_used += 1
		_expect(invalid_used == 0, path + ":" + str(scene.get_path_to(layer)) + " all used original texture cells fit")
		map_details.append({"node": str(scene.get_path_to(layer)), "cells": layer.get_used_cells().size(), "original_sources": affected_sources.size(), "invalid_used": invalid_used})
	observations[path] = map_details
	var expected_npcs := ["girl_npc", "NPC", "villager-female", "NPC1", "Bandits", "Boss-Bandit"] if path == OAK else (["city_npc", "Bandits", "Bandits2", "Bandits3", "Bandits4", "Bandits5"] if path == CITY else ["old_npc", "villager-male", "Boss-Wizard"])
	for npc_name in expected_npcs:
		_expect(scene.get_node_or_null(npc_name) != null, path + " existing NPC spawns: " + npc_name)
	var camera := Camera2D.new()
	camera.position = Vector2(640, 304)
	camera.zoom = Vector2(0.8, 0.8)
	scene.add_child(camera)
	camera.make_current()
	# Background comparison photographs only; normal HUD/controller remains in scene.
	for layer in scene.get_children():
		if layer is CanvasLayer:
			layer.visible = false
	await _frames(4)
	var map_name := "oakleaf" if path == OAK else ("city" if path == CITY else "pinehill")
	await _capture(map_name + ("-before" if replacement_found else "-after"))
	# Preview the exact proposed texture rebind in memory, preserving every cell.
	# No scene/resource is saved by this preview and no other project is used.
	for layer in layers:
		layer.tile_set = layer.tile_set.duplicate(true)
		for index in layer.tile_set.get_source_count():
			var source = layer.tile_set.get_source(layer.tile_set.get_source_id(index))
			if source is TileSetAtlasSource and source.texture != null and "TileSet_V2" in source.texture.resource_path:
				source.texture = load(ORIGINAL_TEXTURE)
	await _frames(4)
	await _capture(map_name + "-zip-preview")

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://hud_runtime_map_qa_20260926_verified_" + label + ".png")

func _doors() -> void:
	state.current_task_index = 1
	var pairs := [
		[OAK, TEACHER], [TEACHER, OAK],
		[CITY, "res://scenes/pinehill_village.tscn"],
		["res://scenes/2nd Village/Pinehill Village.tscn", CITY],
	]
	for pair in pairs:
		var scene := await _load(pair[0])
		var candidate: Node = null
		for area in scene.find_children("*", "Area2D", true, false):
			if area.has_method("_resolve_destination_scene_path"):
				var target: String = area._resolve_destination_scene_path()
				if target.begins_with("uid://"):
					target = ResourceUID.get_id_path(ResourceUID.text_to_id(target))
				if target == pair[1]:
					candidate = area
					break
		_expect(candidate != null, pair[0] + " retains door to " + pair[1])
		if candidate == null:
			continue
		var player := get_tree().get_first_node_in_group("player_character") as Node2D
		# Exercise the existing door animation/fade/spawn/scene-change implementation.
		candidate._begin_transition(player)
		var deadline := Time.get_ticks_msec() + 5000
		while get_tree().current_scene == scene and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		await _frames(8)
		_expect(get_tree().current_scene.scene_file_path == pair[1], pair[0] + " actual door transition arrives at " + pair[1])
		_expect(not inputs.is_input_locked(), "Door arrival releases its existing input lock")
		_expect(state.current_task_index == 1, "Door transition preserves frozen quest checkpoint")

func _presentation() -> void:
	var original_window_size := get_window().size
	var manager := get_node("/root/QuestNotificationManager")
	for path in [OAK, TEACHER]:
		var scene := await _load(path)
		var player := get_tree().get_first_node_in_group("player_character") as Node2D
		player.global_position = Vector2(980, 300) if path == OAK else scene.get_node("Teacher").position + Vector2(0, 28)
		var ui := scene.get_node("CanvasLayer/Panel")
		var panel := scene.get_node("CanvasLayer/DialoguePanel") as Control
		state.push_mode(state.GameMode.DIALOGUE)
		ui.begin_dialogue(["You are ready. Travel through the forest and reach the City of Knowledge.", "Reward: Forest Path unlocked"])
		for window_size in [Vector2i(1215, 545), Vector2i(960, 540), Vector2i(844, 390)]:
			get_window().size = window_size
			await _frames(6)
			var rect := panel.get_global_rect()
			var viewport := panel.get_viewport_rect().size
			_expect(absf(rect.get_center().x - viewport.x * 0.5) < 1.0 and absf(viewport.y - rect.end.y - 40.0) < 1.5, path + " shared dialogue bottom-center at " + str(window_size))
			_expect(not rect.intersects(_button(scene).get_global_rect()), path + " dialogue does not overlap ACT at " + str(window_size))
			_expect(_button(scene).is_visible_in_tree() and not _button(scene, "up").is_visible_in_tree(), path + " existing dialogue control lifecycle unchanged")
			observations[path + str(window_size)] = {"dialogue": str(rect), "viewport": str(viewport), "act": str(_button(scene).get_global_rect())}
			await _capture(("oakleaf" if path == OAK else "teacher") + "-dialogue-" + str(window_size.x))
		await _tap(scene)
		_expect(ui.is_dialogue_active() and ui.get_dialogue_line_index() == 1, "One touch remains one dialogue line")
		await _tap(scene)
		_expect(not ui.is_dialogue_active(), "Final deliberate dialogue close unchanged")
		state.pop_mode()
		get_window().size = original_window_size
		await _frames(4)
		var hud := scene.get_node("GameHUD")
		var quest_rect: Rect2 = hud.quest_guide.get_global_rect()
		var time_rect: Rect2 = hud.get_node("TimeMargin").get_global_rect()
		manager._on_progression_session_reset("map_test")
		var timing := {"started": 0, "finished": 0}
		manager.notification_started.connect(func(_event: Dictionary): timing.started = Time.get_ticks_msec(), CONNECT_ONE_SHOT)
		manager.notification_finished.connect(func(_event: Dictionary): timing.finished = Time.get_ticks_msec(), CONNECT_ONE_SHOT)
		manager.show_task_completed("Task Complete", "Battle completed", "map-test-" + path)
		await manager.notification_started
		var complete: Control = manager._task_complete_panel
		var complete_rect := complete.get_global_rect()
		var expected_completion_y := quest_rect.end.y + 12.0 if hud.quest_guide.visible else 12.0
		_expect(absf(complete_rect.get_center().x - complete.get_viewport_rect().size.x * 0.5) < 1.0 and complete_rect.position.y >= expected_completion_y, "Task Complete is viewport-relative and separated below the persistent Current Quest when visible")
		_expect(manager._root_layer.layer > hud.layer, "Temporary Task Complete draws above unchanged top HUD")
		_expect(hud.quest_guide.get_global_rect() == quest_rect and hud.get_node("TimeMargin").get_global_rect() == time_rect, "Current Quest and timer geometry unchanged by notification")
		_expect(complete.size == Vector2(460, 88), "Task Complete existing dimensions unchanged")
		await _capture("task-complete-" + ("oakleaf" if path == OAK else "teacher"))
		while timing.finished == 0 and Time.get_ticks_msec() - timing.started < 5000:
			await get_tree().process_frame
		await _frames(2)
		var duration: int = timing.finished - timing.started
		observations[path + ":completion_duration_ms"] = duration
		_expect(not complete.visible and duration >= 2950 and duration < 3250, "Task Complete retains three-second automatic disappearance")
		manager.show_task_trigger("Task Trigger", "Existing trigger placement", "trigger-test-" + path)
		await manager.notification_started
		var trigger: Control = manager._task_trigger_panel
		var viewport_size := get_viewport().get_visible_rect().size
		var trigger_rect := trigger.get_global_rect()
		var trigger_bottom_margin := viewport_size.y - trigger_rect.end.y
		var trigger_overlaps_controls := false
		for direction in ["up", "down", "left", "right", "interact"]:
			trigger_overlaps_controls = trigger_overlaps_controls or trigger_rect.intersects(_button(scene, direction).get_global_rect())
		observations[path + ":trigger_rect"] = str(trigger_rect)
		_expect(manager._root_layer.layer == 1 and absf(trigger_bottom_margin - 28.0) < 1.5 and not trigger_overlaps_controls, "Task Trigger keeps its existing safe lower-screen placement without covering mobile controls")
		manager._on_progression_session_reset("map_test")
		manager.show_system_notification("System", "Existing system placement", "system-test-" + path)
		await manager.notification_started
		var system_rect := complete.get_global_rect()
		var system_position := Vector2((viewport_size.x - system_rect.size.x) * 0.5, 12.0)
		_expect(manager._root_layer.layer == 1 and system_rect.position.is_equal_approx(system_position), "Other shared system notifications keep their existing top-center placement and layer")
		manager._on_progression_session_reset("map_test")
	get_window().size = original_window_size
