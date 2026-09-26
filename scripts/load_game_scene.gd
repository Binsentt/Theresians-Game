extends Control

const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")
const LoadingScreenController := preload("res://scripts/loading_screen.gd")
const LOADING_SCENE_PATH := "res://scenes/loading_screen.tscn"
const TERMS_GATE_SCRIPT := preload("res://scripts/terms_gate.gd")

@onready var saves_container: VBoxContainer = $TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer
@onready var empty_label: Label = $TextureRect/SavePanel/MarginContainer/Content/EmptyLabel
@onready var identity_gate: Control = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate") as Control
@onready var identity_student_input: LineEdit = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate/IdentityFields/StudentIdInput") as LineEdit
@onready var identity_parent_input: LineEdit = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate/IdentityFields/ParentIdInput") as LineEdit
@onready var identity_status_label: Label = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate/IdentityStatusLabel") as Label
@onready var identity_verify_button: Button = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityGate/IdentityFields/VerifyButton") as Button
@onready var delete_confirmation: ConfirmationDialog = $DeleteSaveConfirmation
@onready var delete_all_button: Button = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/DeleteAllButton") as Button
@onready var delete_all_confirmation: ConfirmationDialog = get_node_or_null("DeleteAllSaveConfirmation") as ConfirmationDialog

var _save_transitioning: bool = false
var _pending_delete_path: String = ""
var _delete_all_pending: bool = false
var _student_terms_gate: Control
var _identity_verifying: bool = false

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)
	if not delete_confirmation.confirmed.is_connected(_on_delete_confirmed):
		delete_confirmation.confirmed.connect(_on_delete_confirmed)
	if not delete_confirmation.canceled.is_connected(_on_delete_canceled):
		delete_confirmation.canceled.connect(_on_delete_canceled)
	if delete_all_button != null and not delete_all_button.pressed.is_connected(_on_delete_all_requested):
		delete_all_button.pressed.connect(_on_delete_all_requested)
	if delete_all_confirmation != null and not delete_all_confirmation.confirmed.is_connected(_on_delete_all_confirmed):
		delete_all_confirmation.confirmed.connect(_on_delete_all_confirmed)
	if delete_all_confirmation != null and not delete_all_confirmation.canceled.is_connected(_on_delete_all_canceled):
		delete_all_confirmation.canceled.connect(_on_delete_all_canceled)
	if identity_verify_button != null and not identity_verify_button.pressed.is_connected(_on_verify_save_owner_pressed):
		identity_verify_button.pressed.connect(_on_verify_save_owner_pressed)
	_refresh_save_list()


func _refresh_save_list() -> void:
	for child in saves_container.get_children():
		child.queue_free()

	if not _has_valid_session_identity():
		if identity_gate != null:
			identity_gate.visible = true
		empty_label.text = "Verify your Student ID and Parent ID to view saves."
		empty_label.visible = true
		if delete_all_button != null:
			delete_all_button.disabled = true
		return

	if identity_gate != null:
		identity_gate.visible = false
	var saves: Array[Dictionary] = GameState.list_saves()
	empty_label.text = "No save data found"
	empty_label.visible = saves.is_empty()
	if delete_all_button != null:
		delete_all_button.disabled = _save_transitioning or saves.is_empty()

	for save_data: Dictionary in saves:
		var save_entry: Control = SAVE_ENTRY_SCENE.instantiate() as Control
		saves_container.add_child(save_entry)
		save_entry.setup(save_data)
		save_entry.save_selected.connect(_on_save_selected)
		save_entry.save_delete_requested.connect(_on_delete_requested)


func _on_delete_requested(save_path: String) -> void:
	if _save_transitioning or save_path.is_empty():
		return
	_pending_delete_path = save_path
	delete_confirmation.popup_centered()


func _on_delete_confirmed() -> void:
	var save_path := _pending_delete_path
	_pending_delete_path = ""
	if save_path.is_empty():
		return
	if GameState.delete_save(save_path):
		_refresh_save_list()
		return

	empty_label.text = "Unable to delete selected save."
	empty_label.visible = true


func _on_delete_canceled() -> void:
	_pending_delete_path = ""

func _on_delete_all_requested() -> void:
	if _save_transitioning or delete_all_confirmation == null:
		return
	_delete_all_pending = true
	delete_all_confirmation.popup_centered()

func _on_delete_all_confirmed() -> void:
	if not _delete_all_pending:
		return
	_delete_all_pending = false
	var deletion_result: Dictionary = GameState.delete_all_saves()
	var deletion_failed := int(deletion_result.get("failed_count", 0)) > 0

	_refresh_save_list()
	if deletion_failed:
		empty_label.text = "Unable to delete all saved games."
		empty_label.visible = true

func _on_delete_all_canceled() -> void:
	_delete_all_pending = false

func _on_save_selected(save_path: String) -> void:
	if _save_transitioning:
		return

	_save_transitioning = true
	var save_data: Dictionary = GameState.peek_save_data(save_path)
	if save_data.is_empty():
		empty_label.text = "Unable to load selected save."
		empty_label.visible = true
		_save_transitioning = false
		return
	if not bool(save_data.get("loadable", false)):
		empty_label.text = String(save_data.get("save_error", "This save is unavailable. Delete it or create a new save."))
		empty_label.visible = true
		_save_transitioning = false
		return
	var selected_student_id := String(save_data.get("student_id", "")).strip_edges()
	if not await _ensure_terms_accepted_for_student(selected_student_id):
		empty_label.text = "Please accept the Terms & Conditions before loading this save."
		empty_label.visible = true
		_save_transitioning = false
		return

	var cycle_result: Dictionary = await RemoteSync.request_learning_cycle(
		String(save_data.get("student_id", "")),
		String(save_data.get("parent_id", ""))
	)
	var cycle_descriptor: Dictionary = cycle_result.get("learning_cycle", {}) if bool(cycle_result.get("ok", false)) else {}
	save_data = GameState.annotate_save_learning_cycle(save_data, cycle_descriptor)
	if not bool(save_data.get("loadable", false)):
		empty_label.text = String(save_data.get("save_error", cycle_result.get("error", "Unable to verify Learning Cycle. Connect to continue.")))
		empty_label.visible = true
		_save_transitioning = false
		return

	var scene_path: String = String(save_data.get("scene_path", ""))
	if scene_path.is_empty():
		_save_transitioning = false
		return

	var playtime_result: Dictionary = await RemoteSync.request_playtime_session({
		"_force_refresh": true,
		"student_id": String(save_data.get("student_id", "")),
		"parent_id": String(save_data.get("parent_id", "")),
		"student_name": String(save_data.get("player_name", "")),
		"grade_level": String(save_data.get("grade_level", "")),
		"section": ""
	})
	if not playtime_result.ok or playtime_result.get("can_play", true) == false or playtime_result.get("should_block", false) == true:
		var error_message := String(playtime_result.get("error", "Unable to connect to playtime service."))
		if playtime_result.get("status", 0) == 403 or playtime_result.get("should_block", false) == true:
			error_message = String(playtime_result.get("error", "Daily playtime limit reached."))
		empty_label.text = error_message
		empty_label.visible = true
		_save_transitioning = false
		return
	var authoritative_start_cycle: Variant = playtime_result.get("learning_cycle", {})
	if GameState.set_learning_cycle_descriptor_is_valid(authoritative_start_cycle):
		save_data = GameState.annotate_save_learning_cycle(save_data, authoritative_start_cycle)
		if not bool(save_data.get("loadable", false)):
			await RemoteSync.request_end_playtime_session()
			empty_label.text = String(save_data.get("save_error", "Previous Learning Cycle"))
			empty_label.visible = true
			_save_transitioning = false
			return

	var applied_save: Dictionary = GameState.load_save(save_path, false)
	if applied_save.is_empty():
		empty_label.text = "Unable to load selected save."
		empty_label.visible = true
		_save_transitioning = false
		return
	if GameState.set_learning_cycle_descriptor_is_valid(authoritative_start_cycle):
		GameState.set_learning_cycle(authoritative_start_cycle)

	LoadingScreenController.prepare_load_game(scene_path)
	var result: int = get_tree().change_scene_to_file(LOADING_SCENE_PATH)
	if result != OK:
		LoadingScreenController.cancel_pending_request()
		_save_transitioning = false


func _has_valid_session_identity() -> bool:
	return GameState.is_valid_existing_student_id(String(GameState.student_id).strip_edges()) \
			and GameState.is_valid_six_digit_id(String(GameState.parent_id).strip_edges())


func _on_verify_save_owner_pressed() -> void:
	if _identity_verifying:
		return
	_identity_verifying = true
	if identity_verify_button != null:
		identity_verify_button.disabled = true
	if identity_status_label != null:
		identity_status_label.text = "Verifying Student and Parent ID..."
	var result: Dictionary = await _verify_save_owner()
	_identity_verifying = false
	if identity_verify_button != null:
		identity_verify_button.disabled = false
	if not bool(result.get("ok", false)):
		if identity_status_label != null:
			identity_status_label.text = String(result.get("error", "Unable to verify Student and Parent ID."))
		GameState.student_id = ""
		GameState.parent_id = ""
		_refresh_save_list()
		return
	if identity_status_label != null:
		identity_status_label.text = "Student verified. Showing your saves."
	_refresh_save_list()


func _verify_save_owner(student_code: String = "", parent_code: String = "") -> Dictionary:
	var requested_student_id := student_code.strip_edges() if not student_code.strip_edges().is_empty() else String(identity_student_input.text).strip_edges() if identity_student_input != null else ""
	var requested_parent_id := parent_code.strip_edges() if not parent_code.strip_edges().is_empty() else String(identity_parent_input.text).strip_edges() if identity_parent_input != null else ""
	requested_student_id = GameState.sanitize_student_id(requested_student_id)
	requested_parent_id = requested_parent_id.replace("-", "").strip_edges()
	if not GameState.is_valid_existing_student_id(requested_student_id):
		return {"ok": false, "error": "Enter a valid Student ID."}
	if not GameState.is_valid_six_digit_id(requested_parent_id):
		return {"ok": false, "error": "Enter a valid 6-digit Parent ID."}
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		return {"ok": false, "error": "Unable to connect to the server. Please try again."}
	var profile_result: Dictionary = await http.request_get("/api/game/profile/check/" + requested_student_id, {"parent_id": requested_parent_id})
	var body: Variant = profile_result.get("body", {})
	var status := int(profile_result.get("status", 0))
	var profile_ok := bool(profile_result.get("ok", false)) or (body is Dictionary and bool(body.get("ok", false)))
	if not profile_ok or status < 200 or status >= 300:
		return {"ok": false, "error": _identity_api_error(profile_result)}
	if not (body is Dictionary) or body.get("can_play", true) == false:
		return {"ok": false, "error": String(body.get("error", "This Student and Parent account cannot play.")) if body is Dictionary else "Unable to verify Student and Parent ID."}
	var canonical_profile: Variant = body.get("canonical_profile", null)
	if not (canonical_profile is Dictionary):
		return {"ok": false, "error": "Unable to verify the linked Student profile."}
	var canonical_student_id := GameState.sanitize_student_id(String(canonical_profile.get("student_id", requested_student_id)))
	var canonical_parent_id := String(canonical_profile.get("parent_id", requested_parent_id)).strip_edges()
	var canonical_name := String(canonical_profile.get("name", "")).strip_edges()
	var canonical_grade := String(canonical_profile.get("grade_level", "")).strip_edges()
	if canonical_student_id != requested_student_id or not GameState.is_valid_six_digit_id(canonical_parent_id) \
			or canonical_name.is_empty() or canonical_grade not in GameState.VALID_REGISTRATION_GRADES:
		return {"ok": false, "error": "Unable to verify the linked Student profile."}
	GameState.student_id = canonical_student_id
	GameState.parent_id = canonical_parent_id
	GameState.player_name = canonical_name
	GameState.grade_level = canonical_grade
	var canonical_gender := String(canonical_profile.get("gender", "")).to_lower().strip_edges()
	if canonical_gender in ["male", "female"]:
		GameState.gender = canonical_gender
	var learning_cycle: Variant = body.get("learning_cycle", {})
	if learning_cycle is Dictionary:
		GameState.set_learning_cycle(learning_cycle)
	return {"ok": true, "canonical_profile": canonical_profile, "learning_cycle": learning_cycle}


func _identity_api_error(result: Dictionary) -> String:
	var body: Variant = result.get("body", {})
	if body is Dictionary:
		var message := String(body.get("error", body.get("message", ""))).strip_edges()
		if not message.is_empty():
			return message
	return "Unable to verify Student and Parent ID."


func _ensure_terms_accepted_for_student(for_student_id: String) -> bool:
	if for_student_id.is_empty():
		return false
	if GameState.has_current_terms_acceptance(for_student_id):
		return true
	var app_acceptance := GameState.has_current_terms_app_acceptance()
	var app_student_id := GameState.get_terms_app_acceptance_student_id()
	if app_acceptance and (app_student_id.is_empty() or app_student_id == for_student_id):
		return GameState.bind_current_terms_acceptance_to_student(for_student_id)
	if is_instance_valid(_student_terms_gate):
		return false
	_student_terms_gate = TERMS_GATE_SCRIPT.new() as Control
	_student_terms_gate.name = "LoadStudentTermsGate"
	add_child(_student_terms_gate)
	_student_terms_gate.set_student_context(for_student_id)
	var completion_state := {"accepted": false, "cancelled": false}
	_student_terms_gate.accepted.connect(func() -> void: completion_state["accepted"] = true)
	_student_terms_gate.cancelled.connect(func() -> void: completion_state["cancelled"] = true)
	while is_instance_valid(_student_terms_gate) and not bool(completion_state["accepted"]) and not bool(completion_state["cancelled"]):
		await get_tree().process_frame
	if is_instance_valid(_student_terms_gate):
		_student_terms_gate.queue_free()
	_student_terms_gate = null
	return bool(completion_state["accepted"]) and GameState.has_current_terms_acceptance(for_student_id)
