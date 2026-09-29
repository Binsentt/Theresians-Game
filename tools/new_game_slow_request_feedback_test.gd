extends Node

const NEW_GAME_SCENE := preload("res://scenes/new_game_scene.tscn")
const LOAD_GAME_SCENE := preload("res://scenes/load_game_scene.tscn")

var _failures: Array[String] = []
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var http_api := get_node_or_null("/root/HttpApi")
	var remote_sync := get_node_or_null("/root/RemoteSync")
	_assert(http_api != null, "New Game loading feedback test has HttpApi")
	_assert(remote_sync != null, "New Game loading feedback test has RemoteSync")
	if http_api == null or remote_sync == null:
		await _finish()
		return
	var local_qa_active := bool(http_api.call("is_local_qa_profile_active"))
	_assert(local_qa_active, "New Game loading feedback test starts with loopback-only QA configuration")
	if not local_qa_active:
		await _finish()
		return
	remote_sync.call("enable_local_qa_mode")
	var new_game := NEW_GAME_SCENE.instantiate()
	get_tree().root.add_child(new_game)
	await get_tree().process_frame
	var controller := new_game.get_node_or_null("TextureRect2")
	_assert(controller != null, "New Game scene exposes its existing registration controller")
	if controller == null:
		await _finish()
		return
	var panel := controller.get_node("ValidationPanel") as PanelContainer
	var label := controller.get_node("ValidationPanel/MarginContainer/ValidationLabel") as Label
	_assert(controller.has_method("_show_playtime_connecting_status_after_delay"), "controller exposes the slow-request feedback helper")
	if not controller.has_method("_show_playtime_connecting_status_after_delay"):
		await _finish()
		return

	controller.set("_playtime_request_pending", true)
	controller.call_deferred("_show_playtime_connecting_status_after_delay")
	await get_tree().create_timer(0.25).timeout
	_assert(panel != null and not panel.visible, "a fast request does not flash a loading message before the slow threshold")
	controller.set("_playtime_request_pending", false)
	await get_tree().create_timer(0.55).timeout
	_assert(panel != null and not panel.visible, "a request completed before the threshold keeps the loading panel hidden")

	controller.set("_playtime_request_pending", true)
	controller.call_deferred("_show_playtime_connecting_status_after_delay")
	await get_tree().create_timer(0.9).timeout
	_assert(panel != null and panel.visible, "a genuinely slow playtime request displays in-place feedback")
	_assert(label != null and label.text == "Connecting...", "slow request feedback uses the approved concise message")
	_assert(get_tree().current_scene.scene_file_path == "res://tools/new_game_slow_request_feedback_test.tscn", "loading feedback does not navigate away or restart New Game")
	controller.set("_playtime_request_pending", false)
	controller.call("_hide_validation")
	_assert(panel == null or not panel.visible, "the connection status clears when the request completes")
	new_game.queue_free()
	await get_tree().process_frame
	await _verify_load_game_verification_feedback()
	await _finish()


func _verify_load_game_verification_feedback() -> void:
	var load_game := LOAD_GAME_SCENE.instantiate()
	get_tree().root.add_child(load_game)
	await get_tree().process_frame
	var label := load_game.get_node("TextureRect/SavePanel/MarginContainer/Content/EmptyLabel") as Label
	_assert(load_game.has_method("_show_slow_online_verification_status_after_delay"), "Load Game exposes slow online-verification feedback")
	if not load_game.has_method("_show_slow_online_verification_status_after_delay"):
		load_game.queue_free()
		return
	label.hide()
	load_game.set("_online_verification_pending", true)
	load_game.call_deferred("_show_slow_online_verification_status_after_delay")
	await get_tree().create_timer(0.25).timeout
	_assert(label != null and not label.visible, "fast saved-game checks do not flash the status label")
	await get_tree().create_timer(0.55).timeout
	_assert(label != null and label.visible and label.text == "Connecting...", "slow saved-game checks display truthful in-place connection feedback")
	load_game.set("_online_verification_pending", false)
	label.hide()
	_assert(label == null or not label.visible, "Load Game feedback clears after authorization completes")
	load_game.queue_free()


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("NEW_GAME_SLOW_REQUEST_FEEDBACK_TEST {\"passed\":%d,\"failed\":0}" % _passed)
		await get_tree().create_timer(15.0).timeout
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("NEW_GAME_SLOW_REQUEST_FEEDBACK_TEST {\"passed\":%d,\"failed\":%d}" % [_passed, _failures.size()])
	await get_tree().create_timer(15.0).timeout
	get_tree().quit(1)
