extends Control

const LEADERBOARD_SCENE_PATH := "res://leaderboard_scene.tscn"
const TERMS_GATE_SCRIPT := preload("res://scripts/terms_gate.gd")

@onready var leaderboard_button: Button = $LeaderboardButton
@onready var fade: ColorRect = $Fade
@onready var menu: Control = $VBoxContainer

var _transitioning := false
var _terms_gate: Control
var _gated_controls: Array[BaseButton] = []

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)

	if not leaderboard_button.pressed.is_connected(_on_leaderboard_pressed):
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)
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
	_terms_gate = TERMS_GATE_SCRIPT.new() as Control
	_terms_gate.name = "TermsGate"
	_terms_gate.accepted.connect(_on_terms_gate_accepted)
	_terms_gate.cancelled.connect(_on_terms_gate_cancelled)
	add_child(_terms_gate)
	_set_gated_controls_enabled(false)


func _set_gated_controls_enabled(enabled: bool) -> void:
	for control in _gated_controls:
		if is_instance_valid(control):
			control.disabled = not enabled
			control.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _on_terms_gate_accepted() -> void:
	_set_gated_controls_enabled(true)
	if is_instance_valid(_terms_gate):
		_terms_gate.visible = false
		_terms_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_terms_gate_cancelled() -> void:
	_set_gated_controls_enabled(false)

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
