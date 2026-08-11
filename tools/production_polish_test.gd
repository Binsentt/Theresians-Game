extends Node

const BACKGROUND_PATH := "res://Images/Loading Backgroud.png"
const GAME_OVER_MP3_PATH := "res://bg-musics/game over sound effects.mp3"

var failures: Array[String] = []
var retry_request_count: int = 0

func _ready() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	failures.append(message)

func _on_retry_requested() -> void:
	retry_request_count += 1

func _find_named(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find_named(child, node_name)
		if found != null:
			return found
	return null

func _collect_game_over_sounds(node: Node, sounds: Array[AudioStreamPlayer]) -> void:
	if node.name == "GameOverSound" and node is AudioStreamPlayer:
		sounds.append(node)
	for child in node.get_children():
		_collect_game_over_sounds(child, sounds)

func _property_value(instance: Object, candidates: Array[String]) -> Variant:
	for item in instance.get_property_list():
		if item.name in candidates:
			return instance.get(item.name)
	return null

func _stop_loading_timers(loading: Node) -> void:
	for timer_name in ["DotsTimer", "ProgressTimer", "StartTimer"]:
		var timer := _find_named(loading, timer_name) as Timer
		if timer != null:
			timer.stop()

func _controller_state(loading: Node) -> Dictionary:
	return {
		"mode": _property_value(loading, ["current_mode"]),
		"destination": _property_value(loading, ["destination_scene"]),
	}

func _run() -> void:
	var loading_resource := ResourceLoader.load("res://scenes/loading_screen.tscn") as PackedScene
	if loading_resource == null:
		_fail("Loading scene is unavailable")
	else:
		var loading := loading_resource.instantiate()
		add_child(loading)
		_stop_loading_timers(loading)
		var background := _find_named(loading, "Background") as TextureRect
		if background == null or background.texture == null or background.texture.resource_path != BACKGROUND_PATH:
			_fail("Loading Background does not use the expected texture")
		var progress := _find_named(loading, "ProgressBar") as ProgressBar
		if progress == null or progress.show_percentage:
			_fail("Loading ProgressBar is missing or shows its percentage")
		if _find_named(loading, "DotsTimer") == null:
			_fail("Loading scene has no DotsTimer")
		if _find_named(loading, "ProgressTimer") == null:
			_fail("Loading scene has no ProgressTimer")
		var loading_label := _find_named(loading, "LoadingLabel") as Label
		if loading_label == null or not loading.has_method("_on_dots_timer_timeout"):
			_fail("Loading scene lacks a usable dots timeout handler")
		else:
			var dots_before := loading_label.text
			loading.call("_on_dots_timer_timeout")
			if loading_label.text == dots_before:
				_fail("Dots timeout handler did not change LoadingLabel text")
		if progress == null or not loading.has_method("_on_progress_timer_timeout"):
			_fail("Loading scene lacks a usable progress timeout handler")
		else:
			var progress_before := progress.value
			loading.call("_on_progress_timer_timeout")
			if progress.value == progress_before:
				_fail("Progress timeout handler did not change ProgressBar value")
		if loading.has_method("show_connection_error") and loading.has_method("_on_retry_button_pressed"):
			retry_request_count = 0
			loading.call("show_connection_error", "Unable to connect.", Callable(self, "_on_retry_requested"))
			var error_panel := _find_named(loading, "ErrorPanel") as Control
			if error_panel == null or not error_panel.visible:
				_fail("Connection error does not show ErrorPanel")
			loading.call("_on_retry_button_pressed")
			await get_tree().process_frame
			loading.call("_on_retry_button_pressed")
			await get_tree().process_frame
			var retry_button := _find_named(loading, "RetryButton") as Button
			if retry_request_count != 2:
				_fail("Retry callback must run once per attempt and allow a later attempt")
			if retry_button == null or not retry_button.visible or retry_button.disabled:
				_fail("Retry must remain available after an attempt completes")
		else:
			_fail("Loading scene has no usable connection retry handlers")
		loading.queue_free()

	var controller_script = ResourceLoader.load("res://scripts/loading_screen.gd")
	if controller_script == null or loading_resource == null:
		_fail("Loading controller script or scene is unavailable")
	else:
		if not controller_script.has_method("prepare_new_game") or not controller_script.has_method("prepare_load_game"):
			_fail("Loading controller lacks mode preparation methods")
		else:
			var new_game_state: Dictionary = {}
			var new_game_result = controller_script.call("prepare_new_game", "res://interiors/player_house.tscn")
			if new_game_result is int and new_game_result != OK:
				_fail("prepare_new_game returned an error")
			else:
				var new_game_loading := loading_resource.instantiate()
				add_child(new_game_loading)
				_stop_loading_timers(new_game_loading)
				new_game_state = _controller_state(new_game_loading)
				if new_game_state.mode == null or new_game_state.destination != "res://interiors/player_house.tscn":
					_fail("prepare_new_game was not consumed by a fresh loading scene")
				new_game_loading.queue_free()
			var load_game_result = controller_script.call("prepare_load_game", "res://scenes/main_menu.tscn")
			if load_game_result is int and load_game_result != OK:
				_fail("prepare_load_game returned an error")
			else:
				var load_game_loading := loading_resource.instantiate()
				add_child(load_game_loading)
				_stop_loading_timers(load_game_loading)
				var load_game_state := _controller_state(load_game_loading)
				if load_game_state.mode == null or load_game_state.destination != "res://scenes/main_menu.tscn":
					_fail("prepare_load_game was not consumed by a fresh loading scene")
				elif new_game_state.mode == load_game_state.mode:
					_fail("prepare_new_game and prepare_load_game did not produce distinct modes")
				load_game_loading.queue_free()

		if not controller_script.has_method("prepare_connection_retry"):
			_fail("Loading controller lacks prepare_connection_retry")
		else:
			var connection_message := "The service is temporarily unavailable."
			controller_script.call("prepare_connection_retry", connection_message)
			var connection_loading := loading_resource.instantiate()
			add_child(connection_loading)
			_stop_loading_timers(connection_loading)
			var connection_modes: Dictionary = controller_script.get_script_constant_map().get("LoadingMode", {})
			var connection_state := _controller_state(connection_loading)
			var connection_panel := _find_named(connection_loading, "ErrorPanel") as Control
			var connection_message_label := _find_named(connection_loading, "ErrorMessage") as Label
			var connection_retry_button := _find_named(connection_loading, "RetryButton") as Button
			var connection_return_button := _find_named(connection_loading, "ReturnButton") as Button
			if connection_state.mode != connection_modes.get("CONNECTION_RETRY"):
				_fail("prepare_connection_retry was not consumed as CONNECTION_RETRY")
			if connection_panel == null or not connection_panel.visible or connection_message_label == null or connection_message_label.text != connection_message:
				_fail("Prepared connection retry does not show its error message")
			if connection_return_button == null or not connection_return_button.visible or connection_return_button.disabled:
				_fail("Prepared connection retry must provide Return Main Menu")
			if connection_retry_button == null or connection_retry_button.visible or not connection_retry_button.disabled:
				_fail("Prepared connection retry must hide Retry until an active-screen callback is supplied")
			connection_loading.queue_free()

	var game_over_resource := ResourceLoader.load("res://scenes/game_over_scene.tscn") as PackedScene
	if game_over_resource == null:
		_fail("Game Over scene is unavailable")
	else:
		var game_over := game_over_resource.instantiate()
		add_child(game_over)
		var sounds: Array[AudioStreamPlayer] = []
		_collect_game_over_sounds(game_over, sounds)
		if sounds.size() != 1:
			_fail("Game Over scene must contain exactly one GameOverSound AudioStreamPlayer")
		else:
			var game_over_sound := sounds[0]
			var mp3_stream := game_over_sound.stream as AudioStreamMP3
			if game_over_sound.autoplay or mp3_stream == null or mp3_stream.resource_path != GAME_OVER_MP3_PATH or mp3_stream.loop or game_over_sound.bus != &"SFX":
				_fail("GameOverSound stream or bus is incorrect")
		game_over.queue_free()

	if failures.is_empty():
		print("PRODUCTION_POLISH_GODOT_TEST PASSED")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PRODUCTION_POLISH_GODOT_TEST FAILED")
		get_tree().quit(1)
