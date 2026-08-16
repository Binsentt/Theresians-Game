extends SceneTree

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const SETTINGS_SCRIPT_PATH := "res://scripts/settings.gd"
const MENU_BUTTON_SCRIPTS := [
	"res://scripts/new_game_btn.gd",
	"res://scripts/load_game_btn.gd",
	"res://scripts/option_btn.gd",
	"res://scripts/quit_btn.gd",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_assert_menu_button_contract()
	_assert_options_slider_contract()
	_finish()


func _assert_menu_button_contract() -> void:
	var scene_source := _read_source(MAIN_MENU_SCENE_PATH)
	if scene_source.is_empty():
		_fail("Main Menu scene source is unavailable")
		return
	for button_name in ["NewGameBtn", "LoadGameBtn", "OptionBtn", "QuitBtn"]:
		var node_start := scene_source.find("[node name=\"%s\"" % button_name)
		var node_end := scene_source.find("[node name=", node_start + 1)
		var node_block := scene_source.substr(node_start, node_end - node_start if node_end >= 0 else -1)
		if node_start < 0:
			_fail("Main Menu is missing %s" % button_name)
			continue
		if not node_block.contains("theme_override_styles/normal = SubResource(\"StyleBoxFlat_menu_button_normal\")"):
			_fail("%s must use the shared gold-bordered normal style" % button_name)
		if not node_block.contains("theme_override_styles/hover = SubResource(\"StyleBoxFlat_menu_button_hover\")"):
			_fail("%s must use the shared gold-bordered hover style" % button_name)
		if not node_block.contains("theme_override_styles/pressed = SubResource(\"StyleBoxFlat_menu_button_pressed\")"):
			_fail("%s must use the shared gold-bordered pressed style" % button_name)

	for script_path in MENU_BUTTON_SCRIPTS:
		var script_source := _read_source(script_path)
		if script_source.contains("flat = true"):
			_fail("%s disables the Main Menu button StyleBox with flat mode" % script_path)


func _assert_options_slider_contract() -> void:
	var scene_source := _read_source(MAIN_MENU_SCENE_PATH)
	var settings_source := _read_source(SETTINGS_SCRIPT_PATH)
	if not settings_source.contains("const COMPACT_GRABBER_SIZE := Vector2i(40, 38)"):
		_fail("Settings must define the compact 40x38 grabber size")
	if not settings_source.contains("Image.INTERPOLATE_NEAREST"):
		_fail("Settings must downsample the decorative grabber with nearest-neighbor filtering")
	if settings_source.count("add_theme_icon_override(") != 3:
		_fail("Settings must override normal, highlighted, and disabled slider grabbers")

	for slider_name in ["MusicVolume", "SfxVolume"]:
		var node_start := scene_source.find("[node name=\"%s\"" % slider_name)
		var node_end := scene_source.find("[node name=", node_start + 1)
		var node_block := scene_source.substr(node_start, node_end - node_start if node_end >= 0 else -1)
		if node_start < 0:
			_fail("Options popup is missing %s" % slider_name)
			continue
		if not node_block.contains("custom_minimum_size = Vector2(331, 38)"):
			_fail("%s must reserve enough height for its compact grabber" % slider_name)
		if not node_block.contains("theme_override_styles/slider = SubResource(\"StyleBoxTexture_lgwnu\")"):
			_fail("%s must retain the blue/gold decorative slider track" % slider_name)


func _read_source(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MAIN_MENU_UI_LAYOUT_TEST PASSED")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	print("MAIN_MENU_UI_LAYOUT_TEST FAILED")
	quit(1)
