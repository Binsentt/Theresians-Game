extends Control

const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")
const LoadingScreenController := preload("res://scripts/loading_screen.gd")
const LOADING_SCENE_PATH := "res://scenes/loading_screen.tscn"

@onready var saves_container: VBoxContainer = $TextureRect/SavePanel/MarginContainer/Content/ScrollContainer/SavesContainer
@onready var empty_label: Label = $TextureRect/SavePanel/MarginContainer/Content/EmptyLabel

var _save_transitioning: bool = false

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)
	_refresh_save_list()

func _refresh_save_list() -> void:
	for child in saves_container.get_children():
		child.queue_free()

	var saves: Array[Dictionary] = GameState.list_saves()
	empty_label.visible = saves.is_empty()

	for save_data: Dictionary in saves:
		var save_entry: Control = SAVE_ENTRY_SCENE.instantiate() as Control
		saves_container.add_child(save_entry)
		save_entry.setup(save_data)
		save_entry.save_selected.connect(_on_save_selected)

func _on_save_selected(save_path: String) -> void:
	if _save_transitioning:
		return

	_save_transitioning = true
	var save_data: Dictionary = GameState.load_save(save_path)
	if save_data.is_empty():
		_save_transitioning = false
		return

	var scene_path: String = String(save_data.get("scene_path", ""))
	if scene_path.is_empty():
		_save_transitioning = false
		return

	LoadingScreenController.prepare_load_game(scene_path)
	var result := (
		get_tree().change_scene_to_file(LOADING_SCENE_PATH)
	)
	if result != OK:
		LoadingScreenController.cancel_pending_request()
		_save_transitioning = false
