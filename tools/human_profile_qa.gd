extends Node
## Manual, read-only QA entry point. Never used by the product main scene.
## The normal New Game controller performs the actual profile request.

var registration: Node
var status_label: Label
var request_in_flight := false
const LOCAL_BACKEND_URL := "http://127.0.0.1:5000"
@onready var http_api: Node = get_node("/root/HttpApi")
@onready var game_state: Node = get_node("/root/GameState")

func _ready() -> void:
	if http_api == null or not bool(http_api.call("enable_local_qa_mode", LOCAL_BACKEND_URL)):
		push_error("QA_LOCAL_REMOTE_BLOCKED: profile QA requires loopback API")
		get_tree().quit(1)
		return
	game_state.begin_new_game_registration()
	var scene := load("res://scenes/new_game_scene.tscn") as PackedScene
	var instance := scene.instantiate()
	add_child(instance)
	registration = instance.get_node("TextureRect2")
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	layer.add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	status_label = Label.new()
	status_label.text = "LOCAL QA only. Enter linked IDs through New Game. Start is disabled."
	status_label.add_theme_font_size_override("font_size", 14)
	rows.add_child(status_label)
	http_api.child_entered_tree.connect(_observe_request)
	await get_tree().process_frame
	await get_tree().process_frame
	# The original Next action is unchanged. Start cannot create a lease/save/activity.
	for connection in registration.start_btn.pressed.get_connections():
		registration.start_btn.pressed.disconnect(connection.callable)
	registration.start_btn.disabled = true
	print("PROFILE QA: project=" + ProjectSettings.globalize_path("res://"))
	print("PROFILE QA: debug=" + str(OS.is_debug_build()) + " pid=" + str(OS.get_process_id()))
	print("PROFILE QA: executable=" + OS.get_executable_path())
	print("PROFILE QA: base_url=" + String(http_api.call("get_resolved_api_base_url")) + "; production writes disabled at Start boundary")

func _process(_delta: float) -> void:
	if is_instance_valid(registration) and is_instance_valid(registration.start_btn):
		registration.start_btn.disabled = true
func _observe_request(child: Node) -> void:
	if child is HTTPRequest:
		request_in_flight = true
		print("PROFILE QA: GET " + http_api.base_url + "/api/game/profile/check/[STUDENT]?parent_id=[PARENT]")
		child.request_completed.connect(_record_response)

func _record_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	request_in_flight = false
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else {}
	var response: Dictionary = parsed if parsed is Dictionary else {}
	var labels := {
		HTTPRequest.RESULT_SUCCESS: "RESULT_SUCCESS",
		HTTPRequest.RESULT_CANT_CONNECT: "RESULT_CANT_CONNECT",
		HTTPRequest.RESULT_CANT_RESOLVE: "RESULT_CANT_RESOLVE",
		HTTPRequest.RESULT_CONNECTION_ERROR: "RESULT_CONNECTION_ERROR",
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "RESULT_TLS_HANDSHAKE_ERROR",
		HTTPRequest.RESULT_TIMEOUT: "RESULT_TIMEOUT"
	}
	var error_text := String(response.get("error", response.get("message", "")))
	for identifier in [registration.student_id_input.text, registration.parent_id_input.text]:
		if not String(identifier).is_empty():
			error_text = error_text.replace(String(identifier), "[REDACTED]")
	var summary := {
		"result": result,
		"result_name": labels.get(result, "OTHER_HTTPREQUEST_RESULT"),
		"http_status": response_code,
		"canonical_profile_present": response.get("canonical_profile") is Dictionary,
		"can_play": response.get("can_play", null),
		"should_block": response.get("should_block", null),
		"error": error_text,
		"production_writes": 0
	}
	print("PROFILE QA RESPONSE: " + JSON.stringify(summary))
	status_label.text = "HTTP " + str(response_code) + " / " + String(labels.get(result, str(result))) + " — Start disabled; human recheck pending."
