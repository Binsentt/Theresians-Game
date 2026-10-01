extends Control

const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")
const LoadingScreenController := preload("res://scripts/loading_screen.gd")
const LOADING_SCENE_PATH := "res://scenes/loading_screen.tscn"
const TERMS_GATE_SCRIPT := preload("res://scripts/terms_gate.gd")
const CONFIRMATION_FONT: Font = preload("res://Font/PressStart2P.ttf")
const SLOW_ONLINE_VERIFICATION_FEEDBACK_DELAY_SECONDS := 0.75

@onready var saves_container: VBoxContainer = $TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer
@onready var empty_label: Label = $TextureRect/SavePanel/MarginContainer/Content/EmptyLabel
@onready var delete_confirmation: ConfirmationDialog = $DeleteSaveConfirmation
@onready var delete_all_button: Button = get_node_or_null("TextureRect/SavePanel/MarginContainer/Content/Footer/DeleteAllButton") as Button
@onready var delete_all_confirmation: ConfirmationDialog = get_node_or_null("DeleteAllSaveConfirmation") as ConfirmationDialog

var _save_transitioning: bool = false
var _pending_delete_path: String = ""
var _delete_all_pending: bool = false
var _student_terms_gate: Control
var _online_verification_pending: bool = false

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)
	_configure_confirmation_dialog(delete_confirmation, true)
	if delete_all_confirmation != null:
		_configure_confirmation_dialog(delete_all_confirmation, true)
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
	_refresh_save_list()


func _configure_confirmation_dialog(dialog: ConfirmationDialog, destructive_action: bool) -> void:
	if dialog == null:
		return
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.exclusive = true
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.055, 0.16, 1.0)
	panel_style.border_color = Color(0.94902, 0.823529, 0.443137, 1.0)
	panel_style.set_border_width_all(4)
	panel_style.content_margin_left = 20.0
	panel_style.content_margin_right = 20.0
	panel_style.content_margin_top = 18.0
	panel_style.content_margin_bottom = 18.0
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	panel_style.shadow_size = 6
	panel_style.shadow_offset = Vector2(3.0, 3.0)
	dialog.add_theme_stylebox_override("panel", panel_style)
	dialog.add_theme_color_override("font_color", Color(0.96, 0.91, 0.77, 1.0))
	dialog.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.78, 1.0))
	dialog.add_theme_font_override("font", CONFIRMATION_FONT)
	dialog.add_theme_font_size_override("font_size", 10)
	for button: Button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
		button.custom_minimum_size = Vector2(142.0, 42.0)
		button.add_theme_font_override("font", CONFIRMATION_FONT)
		button.add_theme_font_size_override("font_size", 8)
		button.add_theme_color_override("font_color", Color(0.98, 0.86, 0.5, 1.0))
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.82, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(0.93, 0.75, 0.32, 1.0))
		var destructive: bool = destructive_action and button == dialog.get_ok_button()
		button.add_theme_stylebox_override("normal", _make_confirmation_button_style(false, destructive))
		button.add_theme_stylebox_override("hover", _make_confirmation_button_style(true, destructive))
		button.add_theme_stylebox_override("pressed", _make_confirmation_button_style(false, destructive, true))


func _make_confirmation_button_style(hovered: bool, destructive: bool, pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if destructive:
		style.bg_color = Color(0.40, 0.075, 0.11, 1.0) if not pressed else Color(0.28, 0.045, 0.07, 1.0)
		if hovered:
			style.bg_color = Color(0.58, 0.12, 0.15, 1.0)
	else:
		style.bg_color = Color(0.035, 0.16, 0.43, 1.0) if not pressed else Color(0.02, 0.095, 0.29, 1.0)
		if hovered:
			style.bg_color = Color(0.08, 0.27, 0.58, 1.0)
	style.border_color = Color(1.0, 0.78, 0.24, 1.0)
	style.set_border_width_all(3)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _refresh_save_list() -> void:
	for child in saves_container.get_children():
		child.queue_free()

	if not _has_valid_session_identity():
		empty_label.text = "Sign in from New Game to view your saved games."
		empty_label.visible = true
		if delete_all_button != null:
			delete_all_button.disabled = true
		return

	var saves: Array[Dictionary] = GameState.list_saves()
	empty_label.text = "No saved games for this Student yet."
	empty_label.visible = saves.is_empty()
	if delete_all_button != null:
		delete_all_button.disabled = _save_transitioning or saves.is_empty()

	for index in range(saves.size()):
		var save_data: Dictionary = saves[index]
		var save_entry: Control = SAVE_ENTRY_SCENE.instantiate() as Control
		saves_container.add_child(save_entry)
		save_entry.setup(save_data)
		save_entry.set_slot_number(int(save_data.get("slot_number", index + 1)))
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

	empty_label.hide()
	_online_verification_pending = true
	call_deferred("_show_slow_online_verification_status_after_delay")
	var cycle_result: Dictionary = await RemoteSync.request_learning_cycle(
		String(save_data.get("student_id", "")),
		String(save_data.get("parent_id", ""))
	)
	var cycle_descriptor: Dictionary = cycle_result.get("learning_cycle", {}) if bool(cycle_result.get("ok", false)) else {}
	save_data = GameState.annotate_save_learning_cycle(save_data, cycle_descriptor)
	if not bool(save_data.get("loadable", false)):
		_online_verification_pending = false
		empty_label.text = String(save_data.get("save_error", cycle_result.get("error", "Unable to verify Learning Cycle. Connect to continue.")))
		empty_label.visible = true
		_save_transitioning = false
		return

	var scene_path: String = String(save_data.get("scene_path", ""))
	if scene_path.is_empty():
		_online_verification_pending = false
		empty_label.hide()
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
	_online_verification_pending = false
	if not playtime_result.ok or playtime_result.get("can_play", true) == false or playtime_result.get("should_block", false) == true:
		var error_message := String(playtime_result.get("error", "Unable to connect to playtime service."))
		if playtime_result.get("status", 0) == 403 or playtime_result.get("should_block", false) == true:
			error_message = String(playtime_result.get("error", "Daily playtime limit reached."))
		empty_label.text = error_message
		empty_label.visible = true
		_save_transitioning = false
		return
	empty_label.hide()
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


func _show_slow_online_verification_status_after_delay() -> void:
	await get_tree().create_timer(SLOW_ONLINE_VERIFICATION_FEEDBACK_DELAY_SECONDS).timeout
	if _online_verification_pending and is_inside_tree():
		empty_label.text = "Connecting..."
		empty_label.visible = true


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
