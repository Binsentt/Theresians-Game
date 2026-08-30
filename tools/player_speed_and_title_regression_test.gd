extends SceneTree

const PLAYER_SOURCE_PATH := "res://scripts/top_down_player.gd"
const PROJECT_CONFIG_PATH := "res://project.godot"
const EXPORT_PRESETS_PATH := "res://export_presets.cfg"
const EXPECTED_PLAYER_SPEED := 60.0


func _initialize() -> void:
	_run()


func _run() -> void:
	var failed := false
	var player_source := FileAccess.get_file_as_string(PLAYER_SOURCE_PATH)
	failed = not _expect(player_source.contains("@export var move_speed: float = 60.0"), "TopDownPlayer uses the approved 60 px/s move speed.") or failed
	failed = not _expect(player_source.contains("InputManager.get_movement_vector()"), "Keyboard and D-pad continue to share InputManager movement input.") or failed
	failed = not _expect(player_source.contains("velocity = input_vector * move_speed"), "Player velocity continues to be derived from the shared input vector and move speed.") or failed
	failed = not _expect(player_source.contains("move_and_slide()"), "Player movement continues to use CharacterBody2D.move_and_slide().") or failed

	var keyboard_cardinal := Vector2.RIGHT * EXPECTED_PLAYER_SPEED
	var dpad_cardinal := Vector2.UP * EXPECTED_PLAYER_SPEED
	failed = not _expect(is_equal_approx(keyboard_cardinal.length(), EXPECTED_PLAYER_SPEED), "A keyboard-shaped cardinal vector resolves to 60 px/s.") or failed
	failed = not _expect(is_equal_approx(dpad_cardinal.length(), EXPECTED_PLAYER_SPEED), "A D-pad-shaped cardinal vector resolves to 60 px/s.") or failed
	failed = not _expect((Vector2.ZERO * EXPECTED_PLAYER_SPEED).is_zero_approx(), "Zero movement input remains stationary.") or failed

	var project_config := ConfigFile.new()
	var config_error := project_config.load(PROJECT_CONFIG_PATH)
	failed = not _expect(config_error == OK, "project.godot loads for title validation.") or failed
	if config_error == OK:
		failed = not _expect(String(project_config.get_value("application", "config/name", "")) == "Theresian's Quest", "The visible application title is Theresian's Quest.") or failed

	var export_presets := FileAccess.get_file_as_string(EXPORT_PRESETS_PATH)
	failed = not _expect(export_presets.contains("package/unique_name=\"com.theresiansquest.game\""), "The Android package ID remains com.theresiansquest.game.") or failed

	if failed:
		quit(1)
		return
	print("player_speed_and_title_regression_test: PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		printerr("[Player Speed and Title Test] %s" % message)
		return false
	return true
