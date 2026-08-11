extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var yes_button: Button = $CenterContainer/PanelContainer/VBoxContainer/ButtonsRow/YesButton
@onready var no_button: Button = $CenterContainer/PanelContainer/VBoxContainer/ButtonsRow/NoButton
@onready var game_over_sound: AudioStreamPlayer = $GameOverSound

var _game_over_sound_played: bool = false

func _ready() -> void:
	yes_button.disabled = true
	if not no_button.pressed.is_connected(_on_no_button_pressed):
		no_button.pressed.connect(_on_no_button_pressed)
	MusicManager.stop_music()
	_play_game_over_sound_once()

func _play_game_over_sound_once() -> void:
	if _game_over_sound_played:
		return
	_game_over_sound_played = true
	game_over_sound.play()

func _exit_tree() -> void:
	if game_over_sound != null and game_over_sound.playing:
		game_over_sound.stop()

func _on_no_button_pressed() -> void:
	GameState.reset_lives()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
