extends Node

const CONFIG_PATH := "user://settings.cfg"
const MUSIC_SECTION := "audio"
const MUSIC_KEY := "music_volume"
const SFX_KEY := "sfx_volume"
const MUSIC_BUS_NAME := "Music"
const SFX_BUS_NAME := "SFX"
const DEFAULT_MUSIC_VOLUME := 0.8
const DEFAULT_SFX_VOLUME := 0.8
const MIN_LINEAR_VOLUME := 0.001
const SILENT_DB := -80.0

var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME

func _ready() -> void:
	_ensure_bus(MUSIC_BUS_NAME)
	_ensure_bus(SFX_BUS_NAME)
	load_settings()
	apply_all()

func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(CONFIG_PATH)
	if error != OK:
		music_volume = DEFAULT_MUSIC_VOLUME
		sfx_volume = DEFAULT_SFX_VOLUME
		return

	music_volume = clampf(float(config.get_value(MUSIC_SECTION, MUSIC_KEY, DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value(MUSIC_SECTION, SFX_KEY, DEFAULT_SFX_VOLUME)), 0.0, 1.0)

func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(MUSIC_SECTION, MUSIC_KEY, music_volume)
	config.set_value(MUSIC_SECTION, SFX_KEY, sfx_volume)
	config.save(CONFIG_PATH)

func apply_all() -> void:
	_apply_bus_volume(MUSIC_BUS_NAME, music_volume)
	_apply_bus_volume(SFX_BUS_NAME, sfx_volume)

func set_music_volume(value: float, should_save: bool = true) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(MUSIC_BUS_NAME, music_volume)
	if should_save:
		save_settings()

func set_sfx_volume(value: float, should_save: bool = true) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(SFX_BUS_NAME, sfx_volume)
	if should_save:
		save_settings()

func get_music_volume() -> float:
	return music_volume

func get_sfx_volume() -> float:
	return sfx_volume

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return

	AudioServer.add_bus(AudioServer.bus_count)
	var new_bus_index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(new_bus_index, bus_name)

func _apply_bus_volume(bus_name: String, linear_value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return

	var clamped_value: float = clampf(linear_value, 0.0, 1.0)
	var target_db: float = SILENT_DB if clamped_value < MIN_LINEAR_VOLUME else linear_to_db(clamped_value)
	AudioServer.set_bus_volume_db(bus_index, target_db)
