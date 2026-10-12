extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var yes_button: Button = $CenterContainer/PanelContainer/VBoxContainer/ButtonsRow/YesButton
@onready var no_button: Button = $CenterContainer/PanelContainer/VBoxContainer/ButtonsRow/NoButton
@onready var game_over_sound: AudioStreamPlayer = $GameOverSound

var _game_over_sound_played: bool = false
var _retry_in_progress := false

func _ready() -> void:
	yes_button.disabled = false
	if not yes_button.pressed.is_connected(_on_yes_button_pressed):
		yes_button.pressed.connect(_on_yes_button_pressed)
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
	if RemoteSync != null and RemoteSync.has_method("request_end_playtime_session"):
		await RemoteSync.request_end_playtime_session()
	var discard_result: Dictionary = GameState.discard_unsaved_run()
	if not bool(discard_result.get("ok", false)):
		GameState.reset_lives()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_yes_button_pressed() -> void:
	if _retry_in_progress:
		return
	_retry_in_progress = true
	yes_button.disabled = true
	if game_over_sound != null:
		game_over_sound.stop()
	var recovery: Dictionary = GameState.restore_game_over_checkpoint()
	if not bool(recovery.get("ok", false)):
		_retry_in_progress = false
		yes_button.disabled = false
		push_warning("Game Over retry could not restore the active Student checkpoint; the Student identity was retained.")
		return
	var scene_path := String(recovery.get("scene_path", ""))
	if scene_path.is_empty():
		scene_path = GameState.START_SCENE_PATH
	var change_result := get_tree().change_scene_to_file(scene_path)
	if change_result != OK:
		_retry_in_progress = false
		yes_button.disabled = false
		_play_game_over_sound_once()
		push_error("Game Over retry could not open the restored gameplay scene: %s" % scene_path)
