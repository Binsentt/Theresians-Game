extends Control

const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")
const LoadingScreenController := preload("res://scripts/loading_screen.gd")
const LOADING_SCENE_PATH := "res://scenes/loading_screen.tscn"

@onready var saves_container: VBoxContainer = $TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer
@onready var empty_label: Label = $TextureRect/SavePanel/MarginContainer/Content/EmptyLabel
@onready var delete_confirmation: ConfirmationDialog = $DeleteSaveConfirmation

var _save_transitioning: bool = false
var _pending_delete_path: String = ""
var _save_entries_by_path: Dictionary = {}
var _save_list_revision: int = 0

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)
	if not delete_confirmation.confirmed.is_connected(_on_delete_confirmed):
		delete_confirmation.confirmed.connect(_on_delete_confirmed)
	if not delete_confirmation.canceled.is_connected(_on_delete_canceled):
		delete_confirmation.canceled.connect(_on_delete_canceled)
	_refresh_save_list()

func _refresh_save_list() -> void:
	_save_list_revision += 1
	_save_entries_by_path.clear()
	for child in saves_container.get_children():
		child.queue_free()

	var saves: Array[Dictionary] = GameState.list_saves()
	empty_label.text = "No save data found"
	empty_label.visible = saves.is_empty()

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
