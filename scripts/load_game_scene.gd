extends Control

const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")
const LoadingScreenController := preload("res://scripts/loading_screen.gd")
const LOADING_SCENE_PATH := "res://scenes/loading_screen.tscn"

@onready var saves_container: VBoxContainer = $TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer
@onready var empty_label: Label = $TextureRect/SavePanel/MarginContainer/Content/EmptyLabel
@onready var delete_confirmation: ConfirmationDialog = $DeleteSaveConfirmation
@onready var delete_all_button: Button = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/DeleteAllButton") as Button
@onready var delete_all_confirmation: ConfirmationDialog = get_node_or_null("DeleteAllSaveConfirmation") as ConfirmationDialog
@onready var student_id_input: LineEdit = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityFields/StudentIdInput") as LineEdit
@onready var parent_id_input: LineEdit = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityFields/ParentIdInput") as LineEdit
@onready var verify_owner_button: Button = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityFields/VerifyButton") as Button
@onready var identity_status_label: Label = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/IdentityStatusLabel") as Label

var _save_transitioning: bool = false
var _pending_delete_path: String = ""
var _delete_all_pending: bool = false
var _save_entries_by_path: Dictionary = {}
var _save_list_revision: int = 0
var _owner_verification_pending := false

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
	if verify_owner_button != null and not verify_owner_button.pressed.is_connected(_verify_save_owner):
		verify_owner_button.pressed.connect(_verify_save_owner)
	_hydrate_save_owner()
	_refresh_save_list()


func _hydrate_save_owner() -> void:
	if student_id_input != null:
		student_id_input.text = GameState.student_id
	if parent_id_input != null:
		parent_id_input.text = GameState.parent_id
	if identity_status_label == null:
		return
	if GameState.is_valid_existing_student_id(GameState.student_id) \
			and GameState.is_valid_six_digit_id(GameState.parent_id):
		identity_status_label.text = "Showing saves for Student %s" % GameState.student_id
		identity_status_label.visible = true
	else:
		identity_status_label.text = "Verify the linked Student and Parent IDs to view saves."
		identity_status_label.visible = true


func _verify_save_owner() -> void:
	if _owner_verification_pending or student_id_input == null or parent_id_input == null:
		return
	var student_code := GameState.sanitize_student_id(student_id_input.text)
	var parent_code := GameState.sanitize_six_digit_id(parent_id_input.text)
	student_id_input.text = student_code
	parent_id_input.text = parent_code
	if not GameState.is_valid_existing_student_id(student_code):
		_show_owner_error("Student ID must contain 8 digits, or 6 digits for an existing legacy Student.")
		return
	if not GameState.is_valid_six_digit_id(parent_code):
		_show_owner_error("Parent ID must contain exactly 6 digits.")
		return

	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		_show_owner_error("Unable to connect to the server. Please try again.")
		return
	_owner_verification_pending = true
	verify_owner_button.disabled = true
	var profile_result: Dictionary = await http.request_get(
		"/api/game/profile/check/" + student_code,
		{"parent_id": parent_code}
	)
	_owner_verification_pending = false
	verify_owner_button.disabled = false
	var body: Dictionary = profile_result.get("body", {}) if profile_result.get("body", {}) is Dictionary else {}
	var status := int(profile_result.get("status", 0))
	var request_ok: bool = (bool(profile_result.get("ok", false)) or bool(body.get("ok", false))) \
			and status >= 200 and status < 300 \
			and bool(body.get("can_play", true))
	if not request_ok:
		var message := String(body.get("error", body.get("message", "Unable to verify the linked Student profile."))).strip_edges()
		_show_owner_error(message if not message.is_empty() else "Unable to verify the linked Student profile.")
		return
	var canonical_profile: Variant = body.get("canonical_profile", {})
	if not (canonical_profile is Dictionary):
		_show_owner_error("Unable to verify the linked Student profile.")
		return
	var canonical_student_id := String(canonical_profile.get("student_id", student_code)).strip_edges()
	if canonical_student_id != student_code:
		_show_owner_error("The verified Student profile does not match the requested Student ID.")
		return

	GameState.student_id = student_code
	GameState.parent_id = parent_code
	var canonical_name := String(canonical_profile.get("name", "")).strip_edges()
	var canonical_grade := String(canonical_profile.get("grade_level", "")).strip_edges()
	if not canonical_name.is_empty():
		GameState.player_name = canonical_name
	if not canonical_grade.is_empty():
		GameState.grade_level = canonical_grade
	identity_status_label.text = "Showing saves for Student %s" % student_code
	identity_status_label.visible = true
	_refresh_save_list()


func _show_owner_error(message: String) -> void:
	if identity_status_label != null:
		identity_status_label.text = message
		identity_status_label.visible = true

func _refresh_save_list() -> void:
	_save_list_revision += 1
	_save_entries_by_path.clear()
	for child in saves_container.get_children():
		child.queue_free()

	var saves: Array[Dictionary] = GameState.list_saves()
	empty_label.text = "No save data found"
	empty_label.visible = saves.is_empty()
	if delete_all_button != null:
		delete_all_button.disabled = _save_transitioning or saves.is_empty()

	for save_data: Dictionary in saves:
		var save_entry: Control = SAVE_ENTRY_SCENE.instantiate() as Control
		saves_container.add_child(save_entry)
		save_entry.setup(save_data)
		_save_entries_by_path[String(save_data.get("save_path", ""))] = save_entry
		save_entry.save_selected.connect(_on_save_selected)
		save_entry.save_delete_requested.connect(_on_delete_requested)

	if not saves.is_empty():
		_verify_save_learning_cycles.call_deferred(saves, _save_list_revision)


func _verify_save_learning_cycles(saves: Array[Dictionary], revision: int) -> void:
	var grouped_saves: Dictionary = {}
	for save_data in saves:
		if not bool(save_data.get("loadable", false)):
			continue
		var student_code := String(save_data.get("student_id", ""))
		var parent_code := String(save_data.get("parent_id", ""))
		var key := "%s:%s" % [student_code, parent_code]
		if not grouped_saves.has(key):
			grouped_saves[key] = []
		grouped_saves[key].append(save_data)

	for key in grouped_saves:
		if revision != _save_list_revision:
			return
		var group: Array = grouped_saves[key]
		if group.is_empty():
			continue
		var representative: Dictionary = group[0]
		var cycle_result: Dictionary = await RemoteSync.request_learning_cycle(
			String(representative.get("student_id", "")),
			String(representative.get("parent_id", ""))
		)
		if revision != _save_list_revision:
			return
		var descriptor: Dictionary = cycle_result.get("learning_cycle", {}) if bool(cycle_result.get("ok", false)) else {}
		for original_save in group:
			var annotated_save := GameState.annotate_save_learning_cycle(original_save, descriptor)
			var entry: Control = _save_entries_by_path.get(String(annotated_save.get("save_path", ""))) as Control
			if entry != null:
				entry.setup(annotated_save)


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

	var applied_save: Dictionary = GameState.load_save(save_path, false)
	if applied_save.is_empty():
		empty_label.text = "Unable to load selected save."
		empty_label.visible = true
		_save_transitioning = false
		return

	LoadingScreenController.prepare_load_game(scene_path)
	var result: int = get_tree().change_scene_to_file(LOADING_SCENE_PATH)
	if result != OK:
		LoadingScreenController.cancel_pending_request()
		_save_transitioning = false
