extends SceneTree

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const LOAD_GAME_BUTTON_SCRIPT_PATH := "res://scripts/load_game_btn.gd"
const LOAD_GAME_SCENE_PATHS := [
	"res://load_game_scene.tscn",
	"res://scenes/load_game_scene.tscn",
]

var _failures: Array[String] = []


func _init() -> void:
	_assert_main_menu_route()
	for scene_path in LOAD_GAME_SCENE_PATHS:
		_assert_load_game_scene_contract(scene_path)
	if _failures.is_empty():
		print("LOAD_GAME_SCENE_CONTRACT_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOAD_GAME_SCENE_CONTRACT_TEST: FAIL")
	quit(1)


func _assert_main_menu_route() -> void:
	var main_menu_source := FileAccess.get_file_as_string(MAIN_MENU_SCENE_PATH)
	var load_button_source := FileAccess.get_file_as_string(LOAD_GAME_BUTTON_SCRIPT_PATH)
	_assert(main_menu_source.contains('[node name="LoadGameBtn" type="Button" parent="VBoxContainer"'), "Main Menu serializes its Load Game button")
	_assert(main_menu_source.contains('path="res://scripts/load_game_btn.gd"'), "Main Menu uses the Load Game button script")
	_assert(load_button_source.contains('target_scene: String = "res://load_game_scene.tscn"'), "Load Game button resolves to the canonical root scene")


func _assert_load_game_scene_contract(scene_path: String) -> void:
	var source := FileAccess.get_file_as_string(scene_path)
	var saves_container_matcher := RegEx.new()
	var saves_container_pattern_valid := saves_container_matcher.compile('\\[node name="SavesContainer" type="VBoxContainer" parent="TextureRect/SavePanel/MarginContainer/Content/ScrollContainer"') == OK
	_assert(not source.is_empty(), "%s source is readable" % scene_path)
	_assert(
		source.contains('[node name="DeleteSaveConfirmation" type="ConfirmationDialog" parent="."]'),
		"%s provides the DeleteSaveConfirmation required by load_game_scene.gd" % scene_path
	)
	_assert(
		saves_container_pattern_valid and saves_container_matcher.search(source) != null,
		"%s provides the save-list container required by load_game_scene.gd" % scene_path
	)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
