extends CanvasLayer

signal closed

const PANEL_MAX_SIZE := Vector2(760.0, 460.0)
const VIEWPORT_MARGIN := Vector2(32.0, 24.0)
const PIXEL_FONT := preload("res://Font/PressStart2P.ttf")
const COMPLETION_STING := preload("res://audio/completed.mp3")

var selected_action := ""
var _action_selected := false
var _screen_root: Control
var _backdrop: ColorRect
var _panel: PanelContainer
var _summary_rows: GridContainer
var _completion_sound: AudioStreamPlayer


func _ready() -> void:
	layer = 20
	build_screen()
	_apply_layout(get_viewport().get_visible_rect().size)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_play_presentation()


func build_screen() -> void:
	_screen_root = Control.new()
	_screen_root.name = "ScreenRoot"
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_screen_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "DimBackdrop"
	_backdrop.color = Color(0.012, 0.025, 0.067, 0.92)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen_root.add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.name = "CompletionPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = PANEL_MAX_SIZE
	_panel.add_theme_stylebox_override("panel", _build_panel_style())
	_screen_root.add_child(_panel)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 9)
	_panel.add_child(content)

	var title := _make_label("THERESIAN'S QUEST\nCOMPLETE", 18, Color(1.0, 0.81, 0.35))
	title.name = "TitleLabel"
	content.add_child(title)

	var champion := _make_label("MATH CHAMPION", 14, Color(1.0, 0.9, 0.61))
	champion.name = "ChampionLabel"
	content.add_child(champion)

	var player_name := String(GameState.player_name).strip_edges()
	if player_name.is_empty():
		player_name = "Student"
	var congratulations := _make_label("Congratulations,\n%s" % player_name, 11, Color(0.94, 0.95, 1.0))
	congratulations.name = "CongratulationsLabel"
	content.add_child(congratulations)

	var adventure_complete := _make_label("You completed your\nMathematics Adventure!", 9, Color(0.78, 0.83, 0.94))
	adventure_complete.name = "AdventureCompleteLabel"
	content.add_child(adventure_complete)

	var divider := HSeparator.new()
	divider.name = "SummaryDivider"
	content.add_child(divider)

	_summary_rows = GridContainer.new()
	_summary_rows.name = "SummaryRows"
	_summary_rows.columns = 2
	_summary_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_rows.add_theme_constant_override("h_separation", 22)
	_summary_rows.add_theme_constant_override("v_separation", 8)
	content.add_child(_summary_rows)
	_populate_summary_rows()

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	content.add_child(actions)

	var continue_button := _make_button("Continue", "ContinueButton")
	continue_button.pressed.connect(_select_action.bind("continue"))
	actions.add_child(continue_button)
	var main_menu_button := _make_button("Main Menu", "MainMenuButton")
	main_menu_button.pressed.connect(_select_action.bind("main_menu"))
	actions.add_child(main_menu_button)

	_completion_sound = AudioStreamPlayer.new()
	_completion_sound.name = "CompletionSound"
	_completion_sound.stream = COMPLETION_STING
	_completion_sound.bus = AudioSettingsManager.SFX_BUS_NAME
	_completion_sound.max_polyphony = 1
	add_child(_completion_sound)


func build_summary_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var player_name_value := String(GameState.player_name).strip_edges()
	if not player_name_value.is_empty():
		rows.append({"label": "Student", "value": player_name_value})
	var grade := String(GameState.grade_level).strip_edges()
	if not grade.is_empty():
		rows.append({"label": "Grade", "value": grade})
	var answered := int(GameState.total_questions)
	if answered > 0:
		rows.append({"label": "Correct Answers", "value": str(int(GameState.correct_answers))})
		rows.append({"label": "Questions Answered", "value": str(answered)})
	var progress := int(GameState.progress_percentage)
	if progress > 0:
		rows.append({"label": "Progress", "value": "%d%%" % progress})
	return rows


func get_panel_rect_for_viewport(viewport_size: Vector2) -> Rect2:
	var panel_size := Vector2(
		minf(PANEL_MAX_SIZE.x, maxf(0.0, viewport_size.x - VIEWPORT_MARGIN.x)),
		minf(PANEL_MAX_SIZE.y, maxf(0.0, viewport_size.y - VIEWPORT_MARGIN.y))
	)
	return Rect2((viewport_size - panel_size) * 0.5, panel_size)


func _populate_summary_rows() -> void:
	for child in _summary_rows.get_children():
		child.queue_free()
	for row in build_summary_rows():
		var label := _make_label(String(row["label"]), 8, Color(0.77, 0.82, 0.93))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.name = "SummaryLabel_%s" % String(row["label"]).replace(" ", "")
		_summary_rows.add_child(label)
		var value := _make_label(String(row["value"]), 8, Color(1.0, 0.92, 0.7))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.name = "SummaryValue_%s" % String(row["label"]).replace(" ", "")
		_summary_rows.add_child(value)


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _make_button(text_value: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value.to_upper()
	button.custom_minimum_size = Vector2(190.0, 48.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", PIXEL_FONT)
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.91))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	button.add_theme_stylebox_override("normal", _build_button_style(Color(0.08, 0.17, 0.32), Color(0.78, 0.55, 0.19)))
	button.add_theme_stylebox_override("hover", _build_button_style(Color(0.15, 0.28, 0.43), Color(1.0, 0.78, 0.32)))
	button.add_theme_stylebox_override("pressed", _build_button_style(Color(0.04, 0.1, 0.2), Color(0.94, 0.71, 0.25)))
	button.add_theme_stylebox_override("focus", _build_button_style(Color(0.08, 0.17, 0.32, 0.75), Color(1.0, 0.91, 0.55)))
	return button


func _build_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.075, 0.16, 0.98)
	style.border_color = Color(0.85, 0.63, 0.24, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(2)
	style.content_margin_left = 28.0
	style.content_margin_top = 22.0
	style.content_margin_right = 28.0
	style.content_margin_bottom = 22.0
	return style


func _build_button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(1)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _apply_layout(viewport_size: Vector2) -> void:
	if _panel == null:
		return
	var panel_rect := get_panel_rect_for_viewport(viewport_size)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -panel_rect.size.x * 0.5
	_panel.offset_right = panel_rect.size.x * 0.5
	_panel.offset_top = -panel_rect.size.y * 0.5
	_panel.offset_bottom = panel_rect.size.y * 0.5
	_panel.custom_minimum_size = panel_rect.size


func _on_viewport_size_changed() -> void:
	_apply_layout(get_viewport().get_visible_rect().size)


func _play_presentation() -> void:
	_panel.modulate.a = 0.0
	_backdrop.color.a = 0.0
	var shade := create_tween()
	shade.tween_property(_backdrop, "color:a", 0.92, 0.35)
	await shade.finished
	if not is_inside_tree():
		return
	if _completion_sound != null and not _completion_sound.playing:
		_completion_sound.play()
	var reveal := create_tween()
	reveal.tween_property(_panel, "modulate:a", 1.0, 0.2)


func _select_action(action: String) -> void:
	if _action_selected:
		return
	if action not in ["continue", "main_menu"]:
		return
	_action_selected = true
	selected_action = action
	closed.emit()
