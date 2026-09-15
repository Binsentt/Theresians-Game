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

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)

	if not leaderboard_button.pressed.is_connected(_on_leaderboard_pressed):
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	if terms_privacy_button != null and not terms_privacy_button.pressed.is_connected(_on_terms_privacy_pressed):
		terms_privacy_button.pressed.connect(_on_terms_privacy_pressed)
	call_deferred("_initialize_terms_gate")


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
	var debug_session_accepted := GameState.has_method("has_terms_session_acceptance") and bool(GameState.call("has_terms_session_acceptance"))
	var production_acceptance := not GameState.is_debug_terms_run() and GameState.has_current_terms_app_acceptance()
	if debug_session_accepted or production_acceptance:
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
