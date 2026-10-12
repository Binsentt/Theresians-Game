extends Control

const LEADERBOARD_SCENE_PATH := "res://leaderboard_scene.tscn"
const TERMS_GATE_SCRIPT := preload("res://scripts/terms_gate.gd")

@onready var leaderboard_button: Button = $LeaderboardButton
@onready var terms_privacy_button: Button = get_node_or_null("VBoxContainer/TermsPrivacyButton") as Button
@onready var fade: ColorRect = $Fade
@onready var menu: Control = $VBoxContainer

var _transitioning := false
var _terms_gate: Control
var _gated_controls: Array[BaseButton] = []
var _terms_required := false
var _editor_fresh_terms_button: Button

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)

	if not leaderboard_button.pressed.is_connected(_on_leaderboard_pressed):
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	if terms_privacy_button != null and not terms_privacy_button.pressed.is_connected(_on_terms_privacy_pressed):
		terms_privacy_button.pressed.connect(_on_terms_privacy_pressed)
	_install_editor_fresh_terms_button()
	call_deferred("_initialize_terms_gate")


func _install_editor_fresh_terms_button() -> void:
	if not _editor_terms_simulation_available():
		return
	_editor_fresh_terms_button = Button.new()
	_editor_fresh_terms_button.name = "EditorFreshTermsButton"
	_editor_fresh_terms_button.text = "QA: FRESH TERMS"
	_editor_fresh_terms_button.tooltip_text = "Open Terms with an isolated QA-only acceptance profile. Existing saves are not deleted or changed."
	_editor_fresh_terms_button.custom_minimum_size = Vector2(232.0, 42.0)
	_editor_fresh_terms_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_editor_fresh_terms_button.offset_left = -244.0
	_editor_fresh_terms_button.offset_top = -54.0
	_editor_fresh_terms_button.offset_right = -12.0
	_editor_fresh_terms_button.offset_bottom = -12.0
	_editor_fresh_terms_button.z_index = 10
	_editor_fresh_terms_button.focus_mode = Control.FOCUS_NONE
	_editor_fresh_terms_button.add_theme_font_override("font", load("res://Font/PressStart2P.ttf"))
	_editor_fresh_terms_button.add_theme_font_size_override("font_size", 8)
	_editor_fresh_terms_button.add_theme_color_override("font_color", Color(1.0, 0.88, 0.48, 1.0))
	_editor_fresh_terms_button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.72, 1.0))
	_editor_fresh_terms_button.add_theme_stylebox_override("normal", _fresh_terms_button_style(Color(0.85, 0.62, 0.18, 1.0)))
	_editor_fresh_terms_button.add_theme_stylebox_override("hover", _fresh_terms_button_style(Color(1.0, 0.84, 0.36, 1.0)))
	_editor_fresh_terms_button.disabled = not String(GameState.student_id).strip_edges().is_empty()
	_editor_fresh_terms_button.pressed.connect(simulate_fresh_install_terms_for_editor_qa)
	add_child(_editor_fresh_terms_button)


func _fresh_terms_button_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.024, 0.08, 0.22, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = border
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 5
	return style


func _editor_terms_simulation_available() -> bool:
	return OS.is_debug_build() and (OS.has_feature("editor") or HttpApi.is_local_qa_mode())


func simulate_fresh_install_terms_for_editor_qa() -> bool:
	if not _editor_terms_simulation_available() or not String(GameState.student_id).strip_edges().is_empty():
		return false
	var isolated_path := "user://qa_test_artifacts/terms_startup_flow_test_editor_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not GameState.set_terms_app_acceptance_path_for_qa(isolated_path) or GameState.has_current_terms_app_acceptance():
		return false
	_terms_required = true
	_set_gated_controls_enabled(false)
	_show_required_terms_gate()
	return true


func _initialize_terms_gate() -> void:
	_gated_controls = []
	for node in [
		get_node_or_null("VBoxContainer/NewGameBtn"),
		get_node_or_null("VBoxContainer/LoadGameBtn"),
		get_node_or_null("VBoxContainer/OptionBtn"),
		get_node_or_null("VBoxContainer/QuitBtn"),
		leaderboard_button,
	]:
		if node is BaseButton:
			_gated_controls.append(node)
	var persistent_app_acceptance := GameState.has_current_terms_app_acceptance()
	if persistent_app_acceptance:
		_terms_required = false
		_set_gated_controls_enabled(true)
		return
	_terms_required = true
	_set_gated_controls_enabled(false)
	_show_required_terms_gate()


func _show_required_terms_gate() -> void:
	if not is_instance_valid(_terms_gate):
		_terms_gate = TERMS_GATE_SCRIPT.new() as Control
		_terms_gate.name = "TermsGate"
		_terms_gate.accepted.connect(_on_terms_gate_accepted)
		_terms_gate.cancelled.connect(_on_terms_gate_cancelled)
		add_child(_terms_gate)
	_terms_gate.set_review_mode(false)
	_terms_gate.visible = true
	_terms_gate.mouse_filter = Control.MOUSE_FILTER_STOP


func _set_gated_controls_enabled(enabled: bool) -> void:
	for control in _gated_controls:
		if is_instance_valid(control):
			control.disabled = not enabled
			control.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _on_terms_gate_accepted() -> void:
	_terms_required = false
	_set_gated_controls_enabled(true)
	if is_instance_valid(_terms_gate):
		_terms_gate.visible = false
		_terms_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_terms_gate_cancelled() -> void:
	_terms_required = true
	_set_gated_controls_enabled(false)
	if is_instance_valid(_terms_gate):
		_terms_gate.visible = false
		_terms_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_terms_privacy_pressed() -> void:
	if terms_privacy_button == null or terms_privacy_button.disabled:
		return
	if _terms_required:
		_show_required_terms_gate()
		return
	var review_gate := TERMS_GATE_SCRIPT.new() as Control
	review_gate.name = "TermsPrivacyReview"
	add_child(review_gate)
	review_gate.set_review_mode(true)
	review_gate.cancelled.connect(_on_terms_review_closed.bind(review_gate))


func _on_terms_review_closed(review_gate: Control) -> void:
	if is_instance_valid(review_gate):
		review_gate.queue_free()

func _on_leaderboard_pressed() -> void:
	if _transitioning or leaderboard_button.disabled:
		return

	_transitioning = true
	leaderboard_button.disabled = true
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(menu, "modulate:a", 0.0, 0.15)
	tween.parallel().tween_property(fade, "modulate:a", 1.0, 0.25)

	await tween.finished
	get_tree().change_scene_to_file(LEADERBOARD_SCENE_PATH)
