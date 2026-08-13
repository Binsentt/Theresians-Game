extends Node

const TRACK_MENU := "menu"
const TRACK_HOME := "school_or_house"
const TRACK_ADVENTURE := "adventure"
const FADE_DURATION := 0.2
const SILENT_VOLUME_DB := -60.0
const TARGET_VOLUME_DB := 0.0
const SCENE_TRACKS := {
	"res://scenes/main_menu.tscn": TRACK_MENU,
	"res://scenes/new_game_scene.tscn": TRACK_MENU,
	"res://scenes/loading_screen.tscn": TRACK_MENU,
	"res://interiors/player_house.tscn": TRACK_HOME,
	"res://interiors/hotel.tscn": TRACK_HOME,
	"res://interiors/npc_house.tscn": TRACK_HOME,
	"res://interiors/school.tscn": TRACK_HOME,
	"res://interiors/teacher_house.tscn": TRACK_HOME,
	"res://scenes/oak_leaf_village.tscn": TRACK_ADVENTURE,
	"res://world/player_house_outside_door.tscn": TRACK_ADVENTURE,
	"res://world/npc_house_outside_door.tscn": TRACK_ADVENTURE,
	"res://world/teacher_house_outside_door.tscn": TRACK_ADVENTURE,
	"res://scenes/city_of_knowledge.tscn": TRACK_ADVENTURE,
	"res://scenes/pinehill_village.tscn": TRACK_ADVENTURE,
	"res://scenes/2nd Village/Pinehill Village.tscn": TRACK_ADVENTURE
}

var _player: AudioStreamPlayer
var _fade_tween: Tween
var _transition_id: int = 0
var _current_track_key: String = ""
var _last_scene_path: String = ""

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BackgroundMusicPlayer"
	_player.bus = AudioSettingsManager.MUSIC_BUS_NAME
	_player.volume_db = TARGET_VOLUME_DB
	add_child(_player)
	set_process(true)

func _process(_delta: float) -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return

	var scene_path: String = current_scene.scene_file_path
	if scene_path == _last_scene_path:
		return

	_last_scene_path = scene_path
	play_for_scene(scene_path)

func play_for_scene(scene_path: String) -> void:
	var track_key: String = String(SCENE_TRACKS.get(scene_path, ""))
	if track_key.is_empty():
		stop_music()
		return
	play_track(track_key)

func play_track(track_key: String) -> void:
	if track_key.is_empty():
		stop_music()
		return
	if track_key == _current_track_key and _player.playing:
		return

	_transition_id += 1
	var transition_id: int = _transition_id
	_switch_to_track(track_key, transition_id)

func stop_music() -> void:
	_transition_id += 1
	var transition_id: int = _transition_id
	_fade_out_and_stop(transition_id)

func _switch_to_track(track_key: String, transition_id: int) -> void:
	if _fade_tween != null:
		_fade_tween.kill()

	if _player.playing:
		_fade_tween = create_tween()
		_fade_tween.tween_property(_player, "volume_db", SILENT_VOLUME_DB, FADE_DURATION)
		await _fade_tween.finished
		if transition_id != _transition_id:
			return
		_player.stop()

	var next_stream: AudioStream = _get_looping_stream(track_key)
	if next_stream == null:
		_current_track_key = ""
		return

	_player.stream = next_stream
	_player.volume_db = SILENT_VOLUME_DB
	_player.play()
	_current_track_key = track_key

	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", TARGET_VOLUME_DB, FADE_DURATION)

func _fade_out_and_stop(transition_id: int) -> void:
	if _fade_tween != null:
		_fade_tween.kill()

	if not _player.playing:
		_current_track_key = ""
		_player.stream = null
		_player.volume_db = TARGET_VOLUME_DB
		return

	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", SILENT_VOLUME_DB, FADE_DURATION)
	await _fade_tween.finished

	if transition_id != _transition_id:
		return

	_player.stop()
	_player.stream = null
	_player.volume_db = TARGET_VOLUME_DB
	_current_track_key = ""

func _get_looping_stream(track_key: String) -> AudioStream:
	var source_stream: AudioStream = _get_stream_for_track(track_key)
	if source_stream == null:
		return null

	var duplicated_stream: AudioStream = source_stream.duplicate(true) as AudioStream
	if duplicated_stream is AudioStreamMP3:
		var mp3_stream: AudioStreamMP3 = duplicated_stream as AudioStreamMP3
		mp3_stream.loop = true
	return duplicated_stream

func _get_stream_for_track(track_key: String) -> AudioStream:
	match track_key:
		TRACK_MENU:
			return load("res://bg-musics/menu.mp3") as AudioStream
		TRACK_HOME:
			return load("res://bg-musics/schoolorhouse.mp3") as AudioStream
		TRACK_ADVENTURE:
			return load("res://bg-musics/adventure3.mp3") as AudioStream
		_:
			return null
