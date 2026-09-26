extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_OVER_SCENE := "res://scenes/game_over_scene.tscn"
const SETTINGS_INGAME_SCENE := preload("res://scenes/Settings-Ingame/settings_ingame.tscn")
const TIME_PANEL_RECT := Rect2(Vector2(14.0, 12.0), Vector2(190.0, 74.0))
const QUEST_MAX_WIDTH := 460.0
const QUEST_EDGE_MARGIN := 14.0
const QUEST_TIME_GAP := 12.0
const QUEST_VERTICAL_GAP := 10.0
const QUEST_NARROW_BREAKPOINT := 784.0

@onready var time_panel: PanelContainer = $TimeMargin/TimePanel
@onready var time_header: Label = $TimeMargin/TimePanel/TimeContent/TimeHeader
@onready var time_label: Label = $TimeMargin/TimePanel/TimeContent/TimeLabel
@onready var time_progress: ProgressBar = $TimeMargin/TimePanel/TimeContent/TimeProgress
@onready var quest_guide: PanelContainer = $QuestGuide
@onready var quest_label: Label = $QuestGuide/QuestContent/QuestLabel
@onready var quest_heading: Label = $QuestGuide/QuestContent/HeadingRow/Heading
@onready var game_over_overlay: Control = $GameOverOverlay
@onready var return_button: Button = $GameOverOverlay/PanelContainer/VBoxContainer/ReturnButton

var _last_time_visual_state := ""
var _time_panel_styles: Dictionary = {}
var _time_fill_styles: Dictionary = {}
var _quest_normal_style: StyleBoxFlat
var _quest_achievement_style: StyleBoxFlat
var _last_quest_text := ""
var _last_achievement_state := false
var _quest_change_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_settings_overlay()
	_build_hud_styles()
	_update_quest_label()
	_update_playtime_label()
	game_over_overlay.visible = false
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)

	if not GameState.quest_changed.is_connected(_on_quest_changed):
		GameState.quest_changed.connect(_on_quest_changed)
	if not GameState.task_state_changed.is_connected(_on_task_state_changed):
		GameState.task_state_changed.connect(_on_task_state_changed)
	if not GameState.game_over.is_connected(_on_game_over):
		GameState.game_over.connect(_on_game_over)
	if not return_button.pressed.is_connected(_on_return_button_pressed):
		return_button.pressed.connect(_on_return_button_pressed)
	await RenderingServer.frame_post_draw
	_layout_hud()

func _process(_delta: float) -> void:
	_update_playtime_label()


func _update_playtime_label() -> void:
	if time_label == null or time_progress == null:
		return
	var limit_minutes := maxi(0, int(GameState.playtime_limit_minutes))
	var remaining_seconds := maxf(0.0, float(GameState.get_playtime_remaining_seconds()))
	var visual_state := _time_visual_state(limit_minutes, remaining_seconds)
	_apply_time_visual_state(visual_state)
	var display_text := "--:--" if visual_state == "DISABLED" else _format_remaining_time(remaining_seconds)
	if time_label.text != display_text:
		time_label.text = display_text
	if visual_state == "DISABLED":
		if not is_equal_approx(time_progress.value, 0.0):
			time_progress.value = 0.0
		return
	var configured_seconds := float(limit_minutes) * 60.0
	var progress_value := clampf((remaining_seconds / configured_seconds) * 100.0, 0.0, 100.0)
	if not is_equal_approx(time_progress.value, progress_value):
		time_progress.value = progress_value


func _format_remaining_time(remaining_seconds: float) -> String:
	var whole_seconds := maxi(0, int(floor(remaining_seconds)))
	var minutes := int(whole_seconds / 60.0)
	var seconds := whole_seconds % 60
	return "%02d:%02d" % [minutes, seconds]


func _time_visual_state(limit_minutes: int, remaining_seconds: float) -> String:
	if limit_minutes <= 0:
		return "DISABLED"
	if remaining_seconds <= 60.0:
		return "CRITICAL_1"
	if remaining_seconds <= 300.0:
		return "WARNING_5"
	if remaining_seconds <= 900.0:
		return "WARNING_15"
	return "NORMAL"


func _build_hud_styles() -> void:
	var base_panel := time_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var base_fill := time_progress.get_theme_stylebox("fill") as StyleBoxFlat
	if base_panel != null and base_fill != null:
		var palette := {
			"NORMAL": Color(0.94902, 0.823529, 0.443137, 1.0),
			"WARNING_15": Color(1.0, 0.901961, 0.34902, 1.0),
			"WARNING_5": Color(1.0, 0.619608, 0.270588, 1.0),
			"CRITICAL_1": Color(0.913725, 0.333333, 0.321569, 1.0),
			"DISABLED": Color(0.478431, 0.498039, 0.552941, 1.0),
		}
		for state in palette:
			var panel_style := base_panel.duplicate() as StyleBoxFlat
			var fill_style := base_fill.duplicate() as StyleBoxFlat
			panel_style.border_color = palette[state]
			fill_style.bg_color = palette[state]
			if state == "DISABLED":
				panel_style.bg_color = Color(0.066667, 0.07451, 0.113725, 0.94)
			_time_panel_styles[state] = panel_style
			_time_fill_styles[state] = fill_style

	var base_quest := quest_guide.get_theme_stylebox("panel") as StyleBoxFlat
	if base_quest != null:
		_quest_normal_style = base_quest.duplicate() as StyleBoxFlat
		_quest_achievement_style = base_quest.duplicate() as StyleBoxFlat
		_quest_achievement_style.border_color = Color(1.0, 0.878431, 0.407843, 1.0)
		quest_guide.add_theme_stylebox_override("panel", _quest_normal_style)


func _apply_time_visual_state(state: String) -> void:
	if state == _last_time_visual_state:
		return
	_last_time_visual_state = state
	if _time_panel_styles.has(state):
		time_panel.add_theme_stylebox_override("panel", _time_panel_styles[state])
	if _time_fill_styles.has(state):
		time_progress.add_theme_stylebox_override("fill", _time_fill_styles[state])
	var bar_height := 6.0
	if state == "WARNING_15":
		bar_height = 7.0
	elif state in ["WARNING_5", "CRITICAL_1"]:
		bar_height = 8.0
	time_progress.custom_minimum_size.y = bar_height


func _on_game_over() -> void:
	if ResourceLoader.exists(GAME_OVER_SCENE):
		get_tree().change_scene_to_file(GAME_OVER_SCENE)
		return
	game_over_overlay.visible = true


func _on_time_limit_reached() -> void:
	InputManager.lock_input("daily_time_limit")
	var label := get_node_or_null("GameOverOverlay/PanelContainer/VBoxContainer/Label") as Label
	var description := get_node_or_null("GameOverOverlay/PanelContainer/VBoxContainer/Description") as Label
	if label != null:
		label.text = "DAILY PLAYTIME COMPLETE"
		label.add_theme_font_size_override("font_size", 16)
	if description != null:
		description.text = "You have reached today's playtime limit.\nYour progress has been saved."
		description.add_theme_font_size_override("font_size", 11)
	if game_over_overlay != null:
		var panel := game_over_overlay.get_node("PanelContainer") as Control
		panel.offset_left = -220.0
		panel.offset_top = -114.0
		panel.offset_right = 220.0
		panel.offset_bottom = 114.0
		game_over_overlay.visible = true
	if return_button != null:
		return_button.add_theme_font_size_override("font_size", 13)
		return_button.disabled = false


func show_time_limit_reached() -> void:
	_on_time_limit_reached()


func _on_return_button_pressed() -> void:
	get_tree().paused = false
	InputManager.unlock_input("daily_time_limit")
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
	_set_quest_text(_get_active_quest_text())


func _set_quest_text(quest_text: String) -> void:
	if quest_label == null or quest_guide == null:
		return
	var normalized_text := quest_text.strip_edges()
	var text_changed := normalized_text != _last_quest_text
	var had_previous_text := not _last_quest_text.is_empty()
	_last_quest_text = normalized_text
	var has_text := not normalized_text.is_empty()
	var is_achievement := has_text and bool(GameState.journey_complete) and normalized_text.to_lower() == "math champion"
	quest_guide.visible = has_text
	quest_label.visible = has_text
	quest_label.text = normalized_text
	if quest_heading != null:
		quest_heading.text = "ACHIEVEMENT" if is_achievement else "CURRENT QUEST"
	if is_achievement != _last_achievement_state:
		_last_achievement_state = is_achievement
		if _quest_achievement_style != null and is_achievement:
			quest_guide.add_theme_stylebox_override("panel", _quest_achievement_style)
		elif _quest_normal_style != null:
			quest_guide.add_theme_stylebox_override("panel", _quest_normal_style)
	_layout_hud()
	if text_changed and had_previous_text and has_text:
		_animate_quest_change()


func _animate_quest_change() -> void:
	if _quest_change_tween != null and _quest_change_tween.is_running():
		_quest_change_tween.kill()
	quest_guide.modulate = Color(1.0, 1.0, 1.0, 0.74)
	_quest_change_tween = create_tween()
	_quest_change_tween.tween_property(quest_guide, "modulate:a", 1.0, 0.2)


func _on_viewport_size_changed() -> void:
	_layout_hud()


func _layout_hud() -> void:
	if quest_guide == null or quest_label == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var geometry := _quest_layout_for_viewport(viewport_size, quest_label.text)
	quest_guide.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	quest_guide.position = geometry.position
	quest_guide.size = geometry.size


func _quest_layout_for_viewport(viewport_size: Vector2, objective: String) -> Dictionary:
	var available_width := viewport_size.x - 2.0 * (QUEST_EDGE_MARGIN + TIME_PANEL_RECT.size.x + QUEST_TIME_GAP)
	var panel_width := minf(QUEST_MAX_WIDTH, available_width)
	var top := QUEST_EDGE_MARGIN - 2.0
	if viewport_size.x < QUEST_NARROW_BREAKPOINT or panel_width < 340.0:
		panel_width = minf(QUEST_MAX_WIDTH, maxf(0.0, viewport_size.x - 32.0))
		top = TIME_PANEL_RECT.end.y + QUEST_VERTICAL_GAP
	var line_count := _estimate_quest_lines(objective, maxf(1.0, panel_width - 28.0))
	var panel_height := 48.0 + float(line_count) * 15.0
	panel_height = minf(panel_height, maxf(1.0, viewport_size.y - 24.0))
	var left := maxf(12.0, (viewport_size.x - panel_width) * 0.5)
	return {
		"position": Vector2(left, top),
		"size": Vector2(panel_width, panel_height),
		"line_count": line_count,
	}


func _estimate_quest_lines(objective: String, available_width: float) -> int:
	if objective.is_empty():
		return 1
	var font := quest_label.get_theme_font("font")
	var font_size := quest_label.get_theme_font_size("font_size")
	var line_width := 0.0
	var lines := 1
	for word in objective.split(" ", false):
		var word_width := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		var space_width := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x if line_width > 0.0 else 0.0
		if line_width > 0.0 and line_width + space_width + word_width > available_width:
			lines += 1
			line_width = word_width
		else:
			line_width += space_width + word_width
	return lines


func _get_active_quest_text() -> String:
	if GameState.has_method("get_current_quest_text"):
		var authoritative_text := String(GameState.call("get_current_quest_text")).strip_edges()
		if not authoritative_text.is_empty() and authoritative_text != GameState.DEFAULT_QUEST:
			return authoritative_text
	if bool(GameState.journey_complete):
		return "Math Champion"
	if GameState.is_tutorial_active():
		return GameState.TUTORIAL_QUEST
	if GameState.current_task_index >= 0 and GameState.current_task_index < GameState.tasks.size():
		return String(GameState.tasks[GameState.current_task_index].get("quest_text", "")).strip_edges()

	var fallback_quest := GameState.current_quest.strip_edges()
	return "" if fallback_quest == GameState.DEFAULT_QUEST else fallback_quest
