extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_OVER_SCENE := "res://scenes/game_over_scene.tscn"
const SETTINGS_INGAME_SCENE := preload("res://scenes/Settings-Ingame/settings_ingame.tscn")

@onready var time_label: Label = $TimeMargin/TimePanel/TimeLabel
@onready var quest_guide: PanelContainer = $QuestGuide
@onready var quest_label: Label = $QuestGuide/QuestContent/QuestLabel
@onready var game_over_overlay: Control = $GameOverOverlay
@onready var return_button: Button = $GameOverOverlay/PanelContainer/VBoxContainer/ReturnButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_settings_overlay()
	_update_quest_label()
	_update_playtime_label()
	game_over_overlay.visible = false

	if not GameState.quest_changed.is_connected(_on_quest_changed):
		GameState.quest_changed.connect(_on_quest_changed)
	if not GameState.task_state_changed.is_connected(_on_task_state_changed):
		GameState.task_state_changed.connect(_on_task_state_changed)
	if not GameState.game_over.is_connected(_on_game_over):
		GameState.game_over.connect(_on_game_over)
	if not GameState.time_limit_reached.is_connected(_on_time_limit_reached):
		GameState.time_limit_reached.connect(_on_time_limit_reached)
	if not return_button.pressed.is_connected(_on_return_button_pressed):
		return_button.pressed.connect(_on_return_button_pressed)

func _process(_delta: float) -> void:
	_update_playtime_label()


func _update_playtime_label() -> void:
	if time_label == null:
		return
	if GameState.playtime_limit_minutes <= 0:
		time_label.text = "Time Left: --"
		return
	var remaining_seconds := maxf(0.0, GameState.get_playtime_remaining_seconds())
	var minutes := int(ceil(remaining_seconds / 60.0))
	time_label.text = "Time Left: %s min" % str(minutes)


func _on_game_over() -> void:
	if ResourceLoader.exists(GAME_OVER_SCENE):
		get_tree().change_scene_to_file(GAME_OVER_SCENE)
		return
	game_over_overlay.visible = true


func _on_time_limit_reached() -> void:
	var label := get_node_or_null("GameOverOverlay/PanelContainer/VBoxContainer/Label") as Label
	var description := get_node_or_null("GameOverOverlay/PanelContainer/VBoxContainer/Description") as Label
	if label != null:
		label.text = "TIME LIMIT REACHED"
		label.add_theme_font_size_override("font_size", 22)
	if description != null:
		description.text = "Daily playtime allowance is complete."
		description.add_theme_font_size_override("font_size", 11)
	if game_over_overlay != null:
		var panel := game_over_overlay.get_node("PanelContainer") as Control
		panel.offset_left = -210.0
		panel.offset_top = -114.0
		panel.offset_right = 210.0
		panel.offset_bottom = 114.0
		game_over_overlay.visible = true
	if return_button != null:
		return_button.add_theme_font_size_override("font_size", 13)
		return_button.disabled = false


func show_time_limit_reached() -> void:
	_on_time_limit_reached()


func _on_return_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _build_settings_overlay() -> void:
	if get_node_or_null("Settings-Ingame") != null:
		return

	var settings_ui: Control = SETTINGS_INGAME_SCENE.instantiate() as Control
	if settings_ui == null:
		push_error("Unable to load in-game settings scene.")
		return

	settings_ui.name = "Settings-Ingame"
	settings_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(settings_ui)


func _on_quest_changed(_current_quest: String) -> void:
	_update_quest_label()


func _on_task_state_changed(_previous_index: int, _current_index: int, _event: Dictionary) -> void:
	_update_quest_label()


func _update_quest_label() -> void:
	if quest_label == null or quest_guide == null:
		return

	var quest_text := _get_active_quest_text()
	quest_guide.visible = not quest_text.is_empty()
	quest_label.visible = not quest_text.is_empty()
	quest_label.text = quest_text


func _get_active_quest_text() -> String:
	if GameState.has_method("get_current_quest_text"):
		var authoritative_text := String(GameState.call("get_current_quest_text")).strip_edges()
		if not authoritative_text.is_empty() and authoritative_text != GameState.DEFAULT_QUEST:
			return authoritative_text
	if GameState.is_tutorial_active():
		return GameState.TUTORIAL_QUEST
	if GameState.current_task_index >= 0 and GameState.current_task_index < GameState.tasks.size():
		return String(GameState.tasks[GameState.current_task_index].get("quest_text", "")).strip_edges()

	var fallback_quest := GameState.current_quest.strip_edges()
	return "" if fallback_quest == GameState.DEFAULT_QUEST else fallback_quest
