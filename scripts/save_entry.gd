extends PanelContainer

signal save_selected(save_path: String)
signal save_delete_requested(save_path: String)

const DEFAULT_THUMBNAIL: Texture2D = preload("res://Images/Background-Menu.png")
const LOCATION_PRESENTATION := {
	"res://scenes/oak_leaf_village.tscn": {
		"label": "Oak Leaf Village",
		"thumbnail": preload("res://Images/LoadGame/oak_leaf.png"),
	},
	"res://scenes/2nd Village/Pinehill Village.tscn": {
		"label": "Pinehill Village",
		"thumbnail": preload("res://Images/LoadGame/pinehill.png"),
	},
	"res://scenes/city_of_knowledge.tscn": {
		"label": "City of Knowledge",
		"thumbnail": preload("res://Images/LoadGame/city_of_knowledge.png"),
	},
	"res://interiors/player_house.tscn": {
		"label": "Player House",
		"thumbnail": preload("res://Images/LoadGame/house.png"),
	},
	"res://interiors/teacher_house.tscn": {
		"label": "Teacher House",
		"thumbnail": preload("res://Images/LoadGame/house.png"),
	},
	"res://interiors/npc_house.tscn": {
		"label": "NPC House",
		"thumbnail": preload("res://Images/LoadGame/house.png"),
	},
	"res://interiors/school.tscn": {
		"label": "School",
		"thumbnail": preload("res://Images/LoadGame/school.png"),
	},
}

@onready var slot_number_label: Label = $MarginContainer/Content/SlotBadge/BadgeContent/SlotNumber
@onready var slot_caption_label: Label = $MarginContainer/Content/SlotBadge/BadgeContent/SlotCaption
@onready var thumbnail: TextureRect = $MarginContainer/Content/ThumbnailPanel/Thumbnail
@onready var location_label: Label = $MarginContainer/Content/Details/LocationLabel
@onready var player_label: Label = $MarginContainer/Content/Details/PlayerLabel
@onready var grade_label: Label = $MarginContainer/Content/Details/GradeLabel
@onready var quest_label: Label = $MarginContainer/Content/Details/QuestLabel
@onready var saved_label: Label = $MarginContainer/Content/Details/SavedLabel
@onready var playtime_label: Label = $MarginContainer/Content/Details/PlaytimeLabel
@onready var availability_label: Label = $MarginContainer/Content/Details/AvailabilityLabel
@onready var load_button: Button = $MarginContainer/Content/Actions/LoadButton
@onready var delete_button: Button = $MarginContainer/Content/Actions/DeleteButton

var save_path: String = ""
var _pending_save_data: Dictionary = {}
var _loadable: bool = true
var _slot_number := 0
var _save_kind := "manual"


func _ready() -> void:
	if not load_button.pressed.is_connected(_on_load_pressed):
		load_button.pressed.connect(_on_load_pressed)
	if not delete_button.pressed.is_connected(_on_delete_pressed):
		delete_button.pressed.connect(_on_delete_pressed)
	_update_slot_number_label()
	if not _pending_save_data.is_empty():
		_apply_save_data(_pending_save_data)
		_pending_save_data.clear()


func setup(save_data: Dictionary) -> void:
	if not is_node_ready():
		_pending_save_data = save_data
		return
	_apply_save_data(save_data)


func set_slot_number(slot_number: int) -> void:
	_slot_number = maxi(0, slot_number)
	_update_slot_number_label()


func _update_slot_number_label() -> void:
	if is_instance_valid(slot_number_label):
		slot_number_label.text = str(_slot_number) if _save_kind == "manual" and _slot_number > 0 else ""
	if is_instance_valid(slot_caption_label):
		slot_caption_label.text = "TIME LIMIT" if _save_kind == "daily_time_limit" else "SAVE"


func _apply_save_data(save_data: Dictionary) -> void:
	save_path = String(save_data.get("save_path", ""))
	_save_kind = String(save_data.get("save_kind", "manual"))
	_update_slot_number_label()
	var location := LOCATION_PRESENTATION.get(String(save_data.get("scene_path", "")), {}) as Dictionary
	location_label.text = String(location.get("label", "Unknown Location"))
	thumbnail.texture = location.get("thumbnail", DEFAULT_THUMBNAIL) as Texture2D
	player_label.text = "Player: %s" % _display_value(save_data.get("player_name", ""), "Unknown")
	grade_label.text = "Grade: %s" % _display_value(save_data.get("grade_level", ""), "Not recorded")
	quest_label.text = "Progress: %s" % _display_value(save_data.get("current_quest", ""), "No quest recorded")
	var save_date := _display_value(save_data.get("save_date", ""), "Date not recorded")
	var save_time := _display_value(save_data.get("save_time", ""), "Time not recorded")
	saved_label.text = "Last Saved: %s  %s" % [save_date, save_time]
	playtime_label.text = "Playtime: %s" % _format_playtime(int(save_data.get("total_play_time", 0)))
	_loadable = bool(save_data.get("loadable", true))
	var historical_replay := bool(save_data.get("historical_replay_mode", false))
	availability_label.visible = not _loadable or historical_replay
	if historical_replay:
		availability_label.text = "Historical replay: no current-cycle academic credit."
		availability_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28, 1.0))
	else:
		availability_label.remove_theme_color_override("font_color")
		availability_label.text = String(save_data.get("save_error", "This save is unavailable. Delete it or create a new save."))
	load_button.disabled = not _loadable
	delete_button.disabled = _save_kind != "manual"


func _display_value(value: Variant, fallback: String) -> String:
	var text := String(value).strip_edges()
	return fallback if text.is_empty() else text


func _format_playtime(total_seconds: int) -> String:
	var safe_seconds := maxi(0, total_seconds)
	var hours := int(float(safe_seconds) / 3600.0)
	var minutes := int(float(safe_seconds % 3600) / 60.0)
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	if minutes > 0:
		return "%dm" % minutes
	return "%ds" % safe_seconds


func _on_load_pressed() -> void:
	if not _loadable:
		return
	save_selected.emit(save_path)


func _on_delete_pressed() -> void:
	save_delete_requested.emit(save_path)
