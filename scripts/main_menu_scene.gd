extends Control

const LEADERBOARD_SCENE_PATH := "res://leaderboard_scene.tscn"

@onready var leaderboard_button: Button = $LeaderboardButton
@onready var fade: ColorRect = $Fade
@onready var menu: Control = $VBoxContainer

var _transitioning := false

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)

	if not leaderboard_button.pressed.is_connected(_on_leaderboard_pressed):
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)

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
