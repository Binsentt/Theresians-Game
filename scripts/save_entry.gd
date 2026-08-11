extends Button

signal save_selected(save_path: String)

@onready var time_label: Label = $MarginContainer/VBoxContainer/TimeLabel
@onready var date_label: Label = $MarginContainer/VBoxContainer/DateLabel
@onready var player_label: Label = $MarginContainer/VBoxContainer/PlayerLabel
@onready var grade_label: Label = $MarginContainer/VBoxContainer/GradeLabel
@onready var quest_label: Label = $MarginContainer/VBoxContainer/QuestLabel

var save_path: String = ""
var _pending_save_data: Dictionary = {}

func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

	if not _pending_save_data.is_empty():
		_apply_save_data(_pending_save_data)
		_pending_save_data.clear()

func setup(save_data: Dictionary) -> void:
	if not is_node_ready():
		_pending_save_data = save_data
		return

	_apply_save_data(save_data)

func _apply_save_data(save_data: Dictionary) -> void:
	save_path = String(save_data.get("save_path", ""))
	time_label.text = "Time: %s" % String(save_data.get("save_time", "--:--:--"))
	date_label.text = "Date: %s" % String(save_data.get("save_date", "----/--/--"))
	player_label.text = "Player: %s" % String(save_data.get("player_name", "Unknown"))
	grade_label.text = "Grade: %s" % String(save_data.get("grade_level", "-"))
	quest_label.text = "Quest: %s" % String(save_data.get("current_quest", GameState.DEFAULT_QUEST))

func _on_pressed() -> void:
	save_selected.emit(save_path)
