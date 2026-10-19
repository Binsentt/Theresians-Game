extends Node

const CITY := "res://scenes/city_of_knowledge.tscn"
const OAKLEAF := "res://scenes/oak_leaf_village.tscn"
const PINEHILL := "res://scenes/2nd Village/Pinehill Village.tscn"
const SCHOOL := "res://interiors/school.tscn"
const WIZARD_HOUSE_NODE := "display-kase yung wizard sa labas lang"
const PROGRESSION_ROUTER := preload("res://scripts/progression_battle_encounter.gd")

var _checks: Array[Dictionary] = []
var _observed: Dictionary = {}


class LocalQuestionProvider extends Node:
	signal questions_loaded(count: int)
	var _questions: Array[Dictionary] = [{
		"question": "Local QA fixture question",
		"choices": ["A", "B", "C", "D"],
		"correct": 0,
	}]

	func load_questions() -> Array[Dictionary]:
		questions_loaded.emit(_questions.size())
		return _questions.duplicate(true)

	func get_questions() -> Array[Dictionary]:
		return _questions.duplicate(true)


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, label: String) -> void:
	_checks.append({"label": label, "passed": condition})
	if not condition:
		push_error(label)


func _run() -> void:
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	var local_api := http != null \
			and http.has_method("is_local_qa_mode") \
			and bool(http.call("is_local_qa_mode")) \
			and String(http.call("get_resolved_api_base_url")).begins_with("http://127.0.0.1:")
	var local_sync := remote != null and bool(remote.get("local_qa_only"))
	_expect(local_api and local_sync, "Regression runner starts in loopback-only QA with remote writes disabled")
	if not local_api or not local_sync:
		print("MAP_AUDIO_TRANSITION_REGRESSION BLOCKED: local-only runtime guard not active")
		get_tree().quit(2)
		return
	GameState.enable_local_qa_mode()
	_test_wizard_objective_and_location()
	print("MAP_AUDIO_STAGE wizard")
	await _test_city_arrival_markers()
	print("MAP_AUDIO_STAGE city_transition")
	await _test_audio_routes_and_playback()
	print("MAP_AUDIO_STAGE static_and_scene_audio")
	await _test_battle_music_lifecycle()
	print("MAP_AUDIO_STAGE battle_audio_lifecycle")
	var failed := _checks.filter(func(row: Dictionary) -> bool: return not bool(row.get("passed", false))).size()
	var evidence := {
		"passed": _checks.size() - failed,
		"failed": failed,
		"live_network_calls": 0,
		"production_writes": 0,
		"checks": _checks,
		"observed": _observed,
	}
	var result_directory := ProjectSettings.globalize_path("user://qa_local_saves")
	DirAccess.make_dir_recursive_absolute(result_directory)
	var result_file := FileAccess.open("user://qa_local_saves/map_audio_transition_regression_test_result.json", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(evidence, "\t"))
		result_file.close()
	print("MAP_AUDIO_TRANSITION_REGRESSION " + JSON.stringify({
		"passed": evidence.passed,
		"failed": evidence.failed,
		"live_network_calls": evidence.live_network_calls,
		"production_writes": evidence.production_writes,
	}))
	get_tree().quit(1 if failed else 0)


func _test_wizard_objective_and_location() -> void:
	var old_task_index := int(GameState.current_task_index)
	var old_current_quest := String(GameState.current_quest)
	GameState.current_task_index = int(GameState.WIZARD_TASK_INDEX)
	var objective := GameState.get_current_quest_text()
	_expect(objective == "Talk to the Wizard", "Wizard task displays exactly Talk to the Wizard")
	_expect(not objective.to_lower().contains("outside"), "Wizard task display contains no outside wording")
	GameState.current_task_index = old_task_index
	GameState.current_quest = old_current_quest

	var pinehill_scene := load(PINEHILL) as PackedScene
	var pinehill := pinehill_scene.instantiate() as Node2D if pinehill_scene != null else null
	var wizard := pinehill.get_node_or_null("Boss-Wizard") as Node2D if pinehill != null else null
	var wizard_house := pinehill.get_node_or_null(WIZARD_HOUSE_NODE) as Node2D if pinehill != null else null
	_expect(wizard != null, "Canonical Pinehill contains the actual outdoor Wizard actor")
	_expect(wizard_house != null, "Canonical Pinehill contains the existing outdoor Wizard House landmark")
	if wizard != null and wizard_house != null and pinehill != null:
		_expect(wizard.get_parent() == pinehill, "Outdoor Wizard is a scene-level NPC, not a child/interior of the Wizard House")
		var house_offset := wizard.global_position - wizard_house.global_position
		_expect(absf(house_offset.x) <= 32.0 and house_offset.y > 0.0 and house_offset.y <= 64.0, "Outdoor Wizard remains in front of the existing Wizard House area within a position tolerance")
		var blocker := wizard_house.get_node_or_null("HouseCollision/BlockerShape") as CollisionShape2D
		var blocker_shape := blocker.shape as RectangleShape2D if blocker != null else null
		if blocker != null and blocker_shape != null:
			var half_size := blocker_shape.size * blocker.global_scale.abs() * 0.5
			var house_blocker_bounds := Rect2(blocker.global_position - half_size, half_size * 2.0)
			_expect(not house_blocker_bounds.has_point(wizard.global_position), "Outdoor Wizard stands outside the Wizard House blocker footprint")
		else:
			_expect(false, "Wizard House keeps its existing blocker footprint for outside-location verification")
		# The adapter is intentionally installed only when the canonical task
		# gate is open. Give this fixture the real pre-Wizard state instead of
		# bypassing or weakening that runtime authorization.
		var previous_task_index := int(GameState.current_task_index)
		var previous_old_lady_complete := bool(GameState.pinehill_old_man_completed)
		var previous_guard_defeats: Dictionary = GameState.pinehill_defeated_bandits.duplicate(true)
		GameState.current_task_index = GameState.WIZARD_TASK_INDEX
		GameState.pinehill_old_man_completed = true
		GameState.pinehill_defeated_bandits = {}
		for guard_id in GameState.PINEHILL_BANDIT_IDS:
			GameState.pinehill_defeated_bandits[guard_id] = true
		PROGRESSION_ROUTER.install_for_scene(pinehill, PROGRESSION_ROUTER)
		var encounter := wizard.get_node_or_null("ProgressionBattleEncounter")
		_expect(encounter != null, "The outdoor Wizard actor owns the encounter adapter")
		_expect(wizard_house.get_node_or_null("ProgressionBattleEncounter") == null, "Wizard House artwork is not an interaction/battle trigger")
		if encounter != null:
			var route: Dictionary = encounter.get("_route")
			_expect(String(route.get("encounter_id", "")) == "pinehill_wizard", "Outdoor Wizard owns exactly the canonical Wizard encounter")
			_expect(String(route.get("difficulty", "")) == "Difficult", "Outdoor Wizard keeps the pushed Difficult question scope")
		GameState.current_task_index = previous_task_index
		GameState.pinehill_old_man_completed = previous_old_lady_complete
		GameState.pinehill_defeated_bandits = previous_guard_defeats
		pinehill.free()


func _test_city_arrival_markers() -> void:
	var oakleaf_scene := load(OAKLEAF) as PackedScene
	var city_scene := load(CITY) as PackedScene
	var oakleaf := oakleaf_scene.instantiate() as Node2D if oakleaf_scene != null else null
	var city := city_scene.instantiate() as Node2D if city_scene != null else null
	_expect(oakleaf != null and city != null, "Canonical Oakleaf and City scenes load for transition verification")
	if oakleaf == null or city == null:
		if oakleaf != null:
			oakleaf.free()
		if city != null:
			city.free()
		return
	var source_door := oakleaf.get_node_or_null("Go-to-City-of-Knowledge") as Node2D
	var arrival := city.get_node_or_null("spawn_from_oakleaf") as Marker2D
	var oakleaf_entry := city.get_node_or_null("Go-to-Oak-Leaf-Village") as Area2D
	_expect(source_door != null, "Oakleaf scene owns the City transition")
	_expect(arrival != null, "City has a dedicated Oakleaf arrival marker")
	if source_door != null and arrival != null and oakleaf_entry != null:
		_expect(String(source_door.get("destination_scene_path")) == CITY, "Oakleaf transition targets the canonical City scene")
		_expect(String(source_door.get("destination_spawn_marker_name")) == "spawn_from_oakleaf", "Oakleaf source selects the dedicated City arrival marker")
		_expect(String(source_door.get("destination_facing_direction")) == "left", "Oakleaf arrival faces into the City")
		_expect(Vector2(source_door.get("destination_spawn_position")) == arrival.position, "Transition fallback agrees with its dedicated marker")
		_expect(
			arrival.position.x < oakleaf_entry.position.x
			and arrival.position.x >= oakleaf_entry.position.x - 64.0
			and absf(arrival.position.y - oakleaf_entry.position.y) <= 32.0,
			"Oakleaf arrival is beside the right-side City entrance"
		)
	if oakleaf_entry != null and arrival != null:
		_expect(oakleaf_entry.position == Vector2(1213, 84), "Right-side Oakleaf entrance keeps its authored City location")
		var shape_node := oakleaf_entry.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var rectangle := shape_node.shape as RectangleShape2D if shape_node != null else null
		var trigger_center := oakleaf_entry.position + (shape_node.position if shape_node != null else Vector2.ZERO)
		var clear_of_trigger := rectangle != null and (
			absf(arrival.position.x - trigger_center.x) > rectangle.size.x * 0.5 + 16.0
			or absf(arrival.position.y - trigger_center.y) > rectangle.size.y * 0.5 + 16.0
		)
		_expect(clear_of_trigger, "Arrival is safely outside the right-side exit trigger bounds")
	var pinehill_return := (load("res://Door-Navigations-Scene2Scene/pinehill_to_city_of_knowledge.tscn") as PackedScene).instantiate()
	var forest_return := (load("res://Door-Navigations-Scene2Scene/deepest_forest_to_city.tscn") as PackedScene).instantiate()
	_expect(String(pinehill_return.get("destination_scene_path")) == CITY and String(pinehill_return.get("destination_spawn_marker_name")) == "spawn_from_pinehill", "Active Pinehill-to-City return loads the shared map at its forest-side marker")
	_expect(
		Vector2(pinehill_return.get("destination_spawn_position")) == (city.get_node("spawn_from_pinehill") as Marker2D).position,
		"Pinehill return fallback position matches the active spawn_from_pinehill marker"
	)
	_expect(String(forest_return.get("destination_spawn_marker_name")) == "spawn_from_deepest_forest", "Legacy Forest-wrapper return retains its City compatibility marker")
	_expect((city.get_node("spawn_from_pinehill") as Marker2D).position == Vector2(128, 508), "Pinehill return marker remains at its authored forest-side location")
	_expect((city.get_node("spawn_from_deepest_forest") as Marker2D).position == Vector2(128, 508), "Legacy Forest marker remains aligned for old saves")
	pinehill_return.free()
	forest_return.free()
	oakleaf.free()
	add_child(city)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var live_marker := city.get_node_or_null("spawn_from_oakleaf") as Marker2D
	var player := get_tree().get_first_node_in_group("player_character") as CharacterBody2D
	_expect(player != null and live_marker != null, "City scene creates its real player and Oakleaf spawn marker in the physics world")
	if player != null and live_marker != null:
		player.set_physics_process(false)
		player.global_position = live_marker.global_position
		await get_tree().physics_frame
		var stable_spawn_distance := player.global_position.distance_to(live_marker.global_position)
		_expect(stable_spawn_distance <= 2.0, "Oakleaf arrival is not displaced by a physical collision")
		var player_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if player_shape != null and player_shape.shape != null:
			var shape_query := PhysicsShapeQueryParameters2D.new()
			shape_query.shape = player_shape.shape
			shape_query.transform = player_shape.global_transform
			shape_query.collision_mask = player.collision_mask
			shape_query.collide_with_areas = false
			shape_query.exclude = [player.get_rid()]
			var overlaps := player.get_world_2d().direct_space_state.intersect_shape(shape_query, 16)
			_expect(overlaps.is_empty(), "Oakleaf arrival player footprint does not overlap a physical obstacle")
		else:
			_expect(false, "Oakleaf arrival has a player collision shape for physical overlap verification")
		var start_position := player.global_position
		for _step in 24:
			player.velocity = Vector2.LEFT * 120.0
			player.move_and_slide()
			await get_tree().physics_frame
		player.velocity = Vector2.ZERO
		var walked_into_city := start_position.x - player.global_position.x
		_observed["oakleaf_arrival_physics"] = {
			"start": str(start_position),
			"end": str(player.global_position),
			"distance_into_city": walked_into_city,
			"stable_spawn_distance": stable_spawn_distance,
		}
		_expect(walked_into_city >= 24.0, "Player can walk from the Oakleaf arrival into the City without an invisible blocker")
	city.queue_free()
	await get_tree().process_frame


func _test_audio_routes_and_playback() -> void:
	var music := get_node_or_null("/root/MusicManager")
	_expect(music != null, "Existing central MusicManager owns background tracks")
	if music == null:
		return
	music.call("stop_music")
	await get_tree().create_timer(0.25).timeout
	var house_routes := [
		"res://interiors/player_house.tscn",
		"res://interiors/npc_house.tscn",
		"res://interiors/teacher_house.tscn",
		SCHOOL,
	]
	for scene_path in house_routes:
		_expect(String(MusicManager.SCENE_TRACKS.get(scene_path, "")) == "school_or_house", "House and School route to schoolorhouse.mp3: " + scene_path)
	_expect(_track_source_path(music, "school_or_house") == "res://bg-musics/schoolorhouse.mp3", "House/School track resolves to the existing schoolorhouse.mp3 asset")
	var battle_dir := DirAccess.open("res://Battle/Battle-Enemy")
	var vs_count := 0
	if battle_dir != null:
		battle_dir.list_dir_begin()
		var file_name := battle_dir.get_next()
		while not file_name.is_empty():
			if file_name.match("*_vs_*.tscn"):
				vs_count += 1
				var scene_path := "res://Battle/Battle-Enemy/" + file_name
				var expected_track := "teacher_battle" if file_name.ends_with("_vs_teacher.tscn") else "battle"
				_expect(String(MusicManager.SCENE_TRACKS.get(scene_path, "")) == expected_track, "VS scene selects the correct battle track: " + file_name)
			file_name = battle_dir.get_next()
		battle_dir.list_dir_end()
	_expect(vs_count == 9, "All nine canonical VS battle scenes are covered")
	_expect(_track_source_path(music, "teacher_battle") == "res://bg-musics/Teacher-Battle.mp3", "Teacher battle track resolves to Teacher-Battle.mp3")
	_expect(_track_source_path(music, "battle") == "res://bg-musics/battle-mus.mp3", "Other VS battle track resolves to battle-mus.mp3")
	var music_bus_index := AudioServer.get_bus_index(AudioSettingsManager.MUSIC_BUS_NAME)
	var sfx_bus_index := AudioServer.get_bus_index(AudioSettingsManager.SFX_BUS_NAME)
	var user_music_volume := AudioSettingsManager.get_music_volume()
	var user_sfx_volume := AudioSettingsManager.get_sfx_volume()
	var music_bus_db := AudioServer.get_bus_volume_db(music_bus_index) if music_bus_index >= 0 else NAN
	var sfx_bus_db := AudioServer.get_bus_volume_db(sfx_bus_index) if sfx_bus_index >= 0 else NAN
	_expect(music_bus_index >= 0 and sfx_bus_index >= 0, "Existing Music and SFX buses are available for per-track attenuation checks")
	await _play_and_check_track(music, OAKLEAF, "adventure", "res://bg-musics/adventure3.mp3", 0.0)
	await _play_and_check_track(music, "res://interiors/player_house.tscn", "school_or_house", "res://bg-musics/schoolorhouse.mp3", 0.0)
	await _play_and_check_track(music, "res://Battle/Battle-Enemy/male_vs_teacher.tscn", "teacher_battle", "res://bg-musics/Teacher-Battle.mp3", -6.0)
	await _play_and_check_track(music, "res://Battle/Battle-Enemy/male_vs_bandit.tscn", "battle", "res://bg-musics/battle-mus.mp3", -6.0)
	await _play_and_check_track(music, "res://Battle/Battle-Enemy/male_vs_wizard.tscn", "battle", "res://bg-musics/battle-mus.mp3", -6.0)
	await _play_and_check_track(music, SCHOOL, "school_or_house", "res://bg-musics/schoolorhouse.mp3", 0.0)
	_expect(is_equal_approx(AudioSettingsManager.get_music_volume(), user_music_volume), "Per-track battle attenuation leaves the saved Music Volume setting unchanged")
	_expect(is_equal_approx(AudioSettingsManager.get_sfx_volume(), user_sfx_volume), "Per-track battle attenuation leaves the saved SFX Volume setting unchanged")
	_expect(music_bus_index >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(music_bus_index), music_bus_db), "Per-track battle attenuation leaves the Music bus gain unchanged")
	_expect(sfx_bus_index >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus_index), sfx_bus_db), "Per-track battle attenuation does not change the SFX bus gain")
	await _test_preserved_special_audio(music)


func _test_preserved_special_audio(music: Node) -> void:
	_expect(_track_source_path(music, "ending") == "res://bg-musics/ending the game.mp3", "Ending keeps the existing ending the game.mp3 track")
	music.call("play_track", "ending")
	var player := music.get_node_or_null("BackgroundMusicPlayer") as AudioStreamPlayer
	var deadline := Time.get_ticks_msec() + 3000
	while (String(music.get("_current_track_key")) != "ending" or player == null or not player.playing or player.volume_db < -0.5) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(player != null and player.playing and String(music.get("_current_track_key")) == "ending", "Ending track starts through the existing MusicManager player")
	var game_over_scene := load("res://scenes/game_over_scene.tscn") as PackedScene
	var game_over := game_over_scene.instantiate() if game_over_scene != null else null
	var game_over_sound := game_over.get_node_or_null("GameOverSound") as AudioStreamPlayer if game_over != null else null
	_expect(game_over_sound != null and game_over_sound.stream != null and game_over_sound.stream.resource_path == "res://bg-musics/game over sound effects.mp3", "Final-loss Game Over retains its existing sound effect")
	_expect(game_over_sound != null and game_over_sound.bus == &"SFX" and not game_over_sound.autoplay, "Game Over sound remains an explicit SFX trigger")
	var game_over_source := FileAccess.get_file_as_string("res://scripts/game_over_scene.gd")
	_expect(game_over_source.contains("_play_game_over_sound_once()") and game_over_source.contains("if _game_over_sound_played"), "Game Over sound keeps its one-shot guard")
	if game_over != null:
		game_over.free()


func _track_source_path(music: Node, track_key: String) -> String:
	var stream := music.call("_get_stream_for_track", track_key) as AudioStream
	return stream.resource_path if stream != null else ""


func _play_and_check_track(music: Node, scene_path: String, track_key: String, asset_path: String, target_volume_db: float) -> void:
	music.call("play_for_scene", scene_path)
	var deadline := Time.get_ticks_msec() + 3000
	var player := music.get_node_or_null("BackgroundMusicPlayer") as AudioStreamPlayer
	while (String(music.get("_current_track_key")) != track_key
			or player == null
			or not player.playing
			or _music_fade_is_running(music)
			or not is_equal_approx(player.volume_db, target_volume_db)) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var playback_started := player != null and String(music.get("_current_track_key")) == track_key and player.playing
	_expect(playback_started, "Scene starts its intended BGM without a restart: " + scene_path)
	if player != null:
		_expect(player.bus == AudioSettingsManager.MUSIC_BUS_NAME, "BGM uses the Music volume bus: " + scene_path)
		_expect(player.stream != null, "BGM stream is loaded: " + scene_path)
		_expect(is_equal_approx(player.volume_db, target_volume_db), "BGM reaches its per-track target of %.1f dB: %s" % [target_volume_db, scene_path])
	_expect(_track_source_path(music, track_key) == asset_path, "BGM source asset is correct: " + scene_path)
	var players := music.find_children("*", "AudioStreamPlayer", true, false)
	_expect(players.size() == 1, "Exactly one background player is active after the scene switch: " + scene_path)


func _music_fade_is_running(music: Node) -> bool:
	var fade := music.get("_fade_tween") as Tween
	return fade != null and fade.is_running()


func _test_battle_music_lifecycle() -> void:
	var provider := get_node_or_null("/root/QuestionProvider")
	if provider != null:
		provider.free()
	var local_provider := LocalQuestionProvider.new()
	local_provider.name = "QuestionProvider"
	get_tree().root.add_child(local_provider)
	await _run_battle_music_lifecycle("res://Battle/Battle-Enemy/male_vs_teacher.tscn", "teacher_battle")
	await _run_battle_music_lifecycle("res://Battle/Battle-Enemy/male_vs_bandit.tscn", "battle")
	local_provider.free()


func _run_battle_music_lifecycle(scene_path: String, battle_track: String) -> void:
	var prior_context: Dictionary = GameState.encounter_context.duplicate(true)
	GameState.encounter_context = {"source_scene_path": SCHOOL}
	var packed := load(scene_path) as PackedScene
	var battle := packed.instantiate() if packed != null else null
	_expect(battle != null, "Canonical battle scene instantiates for music lifecycle: " + scene_path)
	if battle == null:
		GameState.encounter_context = prior_context
		return
	MusicManager.call("stop_music")
	await get_tree().create_timer(0.25).timeout
	add_child(battle)
	var question_deadline := Time.get_ticks_msec() + 2500
	while Dictionary(battle.get("_current_question_data")).is_empty() and Time.get_ticks_msec() < question_deadline:
		await get_tree().process_frame
	_expect(not Dictionary(battle.get("_current_question_data")).is_empty(), "Local question fixture loads without provider/network traffic: " + scene_path)
	await _playback_track_started(battle_track, scene_path, -6.0)
	var results: Array[bool] = []
	battle.battle_finished.connect(func(won: bool) -> void: results.append(won), CONNECT_ONE_SHOT)
	battle.call("_finish_battle", false)
	var finish_deadline := Time.get_ticks_msec() + 1800
	while results.is_empty() and Time.get_ticks_msec() < finish_deadline:
		await get_tree().process_frame
	if is_instance_valid(battle):
		battle.queue_free()
		await get_tree().process_frame
	_expect(results == [false], "Battle emits one result while restoring world music: " + scene_path)
	await _playback_track_started("school_or_house", scene_path + " return", 0.0)
	GameState.encounter_context = prior_context


func _playback_track_started(track_key: String, label: String, target_volume_db: float) -> void:
	var music := get_node("/root/MusicManager")
	var player := music.get_node("BackgroundMusicPlayer") as AudioStreamPlayer
	var deadline := Time.get_ticks_msec() + 1800
	while (String(music.get("_current_track_key")) != track_key
			or not player.playing
			or _music_fade_is_running(music)
			or not is_equal_approx(player.volume_db, target_volume_db)) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(String(music.get("_current_track_key")) == track_key and player.playing, "Battle lifecycle selects " + track_key + " for " + label)
	_expect(is_equal_approx(player.volume_db, target_volume_db), "Battle lifecycle reaches %.1f dB for %s" % [target_volume_db, label])
