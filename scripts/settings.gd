extends Control

@onready var music_slider: HSlider = $TextureRect/MusicVolume
@onready var sfx_slider: HSlider = $TextureRect/SfxVolume

func _ready() -> void:
	visible = false
	_sync_controls()

	if not music_slider.value_changed.is_connected(_on_music_volume_changed):
		music_slider.value_changed.connect(_on_music_volume_changed)
	if not sfx_slider.value_changed.is_connected(_on_sfx_volume_changed):
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)

func _sync_controls() -> void:
	music_slider.set_value_no_signal(AudioSettingsManager.get_music_volume())
	sfx_slider.set_value_no_signal(AudioSettingsManager.get_sfx_volume())

func _on_music_volume_changed(value: float) -> void:
	AudioSettingsManager.set_music_volume(value, false)

func _on_sfx_volume_changed(value: float) -> void:
	AudioSettingsManager.set_sfx_volume(value, false)
