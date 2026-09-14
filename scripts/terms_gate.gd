extends Control

signal accepted
signal cancelled

const TERMS_FONT_PATH := "res://Font/PressStart2P.ttf"
const NAVY := Color("#071737")
const DEEP_NAVY := Color("#020817")
const GOLD := Color("#f2c14e")
const MUTED_GOLD := Color("#8c7442")
const BODY := Color("#e8edf7")

var _panel: Panel
var _checkbox: CheckBox
var _continue_button: Button
var _cancel_button: Button
var _error_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_checkbox.grab_focus.call_deferred()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.08, 0.84)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2.ZERO
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.custom_minimum_size = Vector2.ZERO
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := Label.new()
	title.name = "Title"
	title.text = "TERMS & CONDITIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 22)
	_apply_font(title)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "Please review these terms before beginning your adventure."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", BODY)
	subtitle.add_theme_font_size_override("font_size", 13)
	_apply_font(subtitle)
	content.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.name = "TermsScroll"
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var body := RichTextLabel.new()
	body.name = "TermsBody"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.custom_minimum_size = Vector2.ZERO
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("default_color", BODY)
	body.add_theme_font_size_override("normal_font_size", 14)
	_apply_font(body)
	body.text = "[font_size=16][color=#f2c14e]Terms of Use[/color][/font_size]\n\nUse Theresian's Quest only for authorized educational or school activities and only with your assigned Student ID. Keep your account and ID private; do not share, cheat, tamper with, or exploit the game.\n\nGameplay progress, quiz and battle answers, quest completion, screen time, and activity timing may be recorded. Online features depend on network and service availability. Local save files are scoped to the logged-in Student and device.\n\n[color=#f2c14e]Privacy Notice[/color]\n\nThe connected school system may use this information for learning support. Authorized teachers, administrators, and a linked parent or guardian may view relevant educational progress. AI-supported questions and insights may be used by the connected system. Information is handled according to the school's applicable privacy policy and is not sold.\n\nYour acceptance is recorded on this device for the current terms version. After you identify your Student account, that acceptance is also associated with that Student ID."
	scroll.add_child(body)

	var agreement_row := HBoxContainer.new()
	agreement_row.name = "AgreementRow"
	agreement_row.add_theme_constant_override("separation", 10)
	content.add_child(agreement_row)

	_checkbox = CheckBox.new()
	_checkbox.name = "AgreementCheckBox"
	_checkbox.focus_mode = Control.FOCUS_ALL
	_checkbox.toggled.connect(_on_checkbox_toggled)
	agreement_row.add_child(_checkbox)

	var agreement_label := Label.new()
	agreement_label.name = "AgreementLabel"
	agreement_label.text = "I have read and agree to the Terms & Conditions and Privacy Notice."
	agreement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	agreement_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agreement_label.add_theme_color_override("font_color", BODY)
	agreement_label.add_theme_font_size_override("font_size", 12)
	_apply_font(agreement_label)
	agreement_row.add_child(agreement_label)

	_error_label = Label.new()
	_error_label.name = "ErrorLabel"
	_error_label.visible = false
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_color_override("font_color", Color("#ff9c9c"))
	_error_label.add_theme_font_size_override("font_size", 11)
	_apply_font(_error_label)
	content.add_child(_error_label)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	content.add_child(actions)

	_cancel_button = Button.new()
	_cancel_button.name = "CancelButton"
	_cancel_button.text = "CANCEL"
	_cancel_button.custom_minimum_size = Vector2(150, 44)
	_cancel_button.focus_mode = Control.FOCUS_ALL
	_cancel_button.add_theme_font_size_override("font_size", 14)
	_cancel_button.add_theme_color_override("font_color", BODY)
	_cancel_button.add_theme_stylebox_override("normal", _button_style(DEEP_NAVY, MUTED_GOLD))
	_cancel_button.add_theme_stylebox_override("hover", _button_style(NAVY, GOLD))
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_apply_font(_cancel_button)
	actions.add_child(_cancel_button)

	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = "CONTINUE"
	_continue_button.custom_minimum_size = Vector2(180, 44)
	_continue_button.focus_mode = Control.FOCUS_ALL
	_continue_button.disabled = true
	_continue_button.add_theme_font_size_override("font_size", 14)
	_continue_button.add_theme_color_override("font_color", Color("#071737"))
	_continue_button.add_theme_stylebox_override("normal", _button_style(GOLD, GOLD))
	_continue_button.add_theme_stylebox_override("hover", _button_style(Color("#ffe28a"), Color("#ffe28a")))
	_continue_button.add_theme_stylebox_override("disabled", _button_style(Color("#5f5a4b"), Color("#77705f")))
	_continue_button.pressed.connect(_on_continue_pressed)
	_apply_font(_continue_button)
	actions.add_child(_continue_button)

func _on_viewport_size_changed() -> void:
	if not is_instance_valid(_panel):
		return
	var viewport_size := get_viewport_rect().size
	var panel_size := Vector2(
		clampf(viewport_size.x * 0.86, 280.0, 920.0),
		clampf(viewport_size.y * 0.82, 280.0, 620.0)
	)
	_panel.size = panel_size
	_panel.position = (viewport_size - panel_size) * 0.5

func _on_checkbox_toggled(checked: bool) -> void:
	if is_instance_valid(_continue_button):
		_continue_button.disabled = not checked
		if checked:
			_error_label.visible = false

func _on_continue_pressed() -> void:
	if not _checkbox.button_pressed:
		return
	if not GameState.record_terms_app_acceptance():
		_error_label.text = "Unable to save acceptance on this device. Please try again."
		_error_label.visible = true
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	accepted.emit()

func _on_cancel_pressed() -> void:
	_checkbox.button_pressed = false
	_continue_button.disabled = true
	cancelled.emit()

func _apply_font(control: Control) -> void:
	var font := load(TERMS_FONT_PATH) as Font
	if font != null:
		control.add_theme_font_override("font", font)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#071737")
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 14
	return style

func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style
