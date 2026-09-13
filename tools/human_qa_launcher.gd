extends Node

const LOCAL_BACKEND_URL := "http://127.0.0.1:5000"
const GAME_ENTRY_SCENE := "res://scenes/loading_screen.tscn"


func _ready() -> void:
	var http := get_node_or_null("/root/HttpApi")
	var remote := get_node_or_null("/root/RemoteSync")
	var game_state := get_node_or_null("/root/GameState")
	if http == null or remote == null or game_state == null:
		_block("QA_LOCAL_REMOTE_BLOCKED: required runtime singletons are unavailable")
		return

	var activated := bool(http.call("enable_local_qa_mode", LOCAL_BACKEND_URL))
	if not activated or not bool(http.get("local_qa_only")):
		_block("QA_LOCAL_REMOTE_BLOCKED: API resolver refused the loopback target")
		return
	remote.call("enable_local_qa_mode")
	game_state.call("enable_local_qa_mode")
	var resolved_base := String(http.call("get_resolved_api_base_url"))
	if not bool(http.call("is_loopback_url", resolved_base)) or not bool(remote.get("local_qa_only")) or not String(game_state.call("get_save_directory")).contains("qa_local"):
		_block("QA_LOCAL_REMOTE_BLOCKED: local-only runtime assertions failed")
		return

	print("QA_LOCAL_ONLY = true")
	print("API BASE = " + resolved_base)
	print("PRODUCTION SYNC = DISABLED")
	print("PRODUCTION TELEMETRY = IMPOSSIBLE")
	print("LOCAL BACKEND = " + ("CONNECTED" if _loopback_port_listening() else "OFFLINE-SAFE"))
	call_deferred("_enter_game")


func _enter_game() -> void:
	var result := get_tree().change_scene_to_file(GAME_ENTRY_SCENE)
	if result != OK:
		_block("QA_LOCAL_REMOTE_BLOCKED: game entry scene could not be loaded")


func _loopback_port_listening() -> bool:
	# The launcher never opens a socket. A failed local request remains offline-safe.
	return false


func _block(message: String) -> void:
	push_error(message)
	print("QA_LOCAL_REMOTE_BLOCKED")
	get_tree().quit(1)
