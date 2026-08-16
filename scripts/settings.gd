extends Control

const GRABBER_TEXTURE: Texture2D = preload("res://Images/grabber.png")
const COMPACT_GRABBER_SIZE := Vector2i(40, 38)

@onready var music_slider: HSlider = $TextureRect/MusicVolume
@onready var sfx_slider: HSlider = $TextureRect/SfxVolume

func _ready() -> void:
	visible = false
	_configure_compact_slider_visuals()
	_sync_controls()

	if not music_slider.value_changed.is_connected(_on_music_volume_changed):
		music_slider.value_changed.connect(_on_music_volume_changed)
	if not sfx_slider.value_changed.is_connected(_on_sfx_volume_changed):
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)

func _configure_compact_slider_visuals() -> void:
	var compact_grabber := _create_compact_grabber()
	for slider in [music_slider, sfx_slider]:
		slider.add_theme_icon_override(&"grabber", compact_grabber)
		slider.add_theme_icon_override(&"grabber_highlight", compact_grabber)
		slider.add_theme_icon_override(&"grabber_disabled", compact_grabber)

func _create_compact_grabber() -> ImageTexture:
	var image := GRABBER_TEXTURE.get_image()
	image.resize(COMPACT_GRABBER_SIZE.x, COMPACT_GRABBER_SIZE.y, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)

func _sync_controls() -> void:
	music_slider.set_value_no_signal(AudioSettingsManager.get_music_volume())
	sfx_slider.set_value_no_signal(AudioSettingsManager.get_sfx_volume())

func _on_music_volume_changed(value: float) -> void:
	AudioSettingsManager.set_music_volume(value, false)

func _on_sfx_volume_changed(value: float) -> void:
	AudioSettingsManager.set_sfx_volume(value, false)
