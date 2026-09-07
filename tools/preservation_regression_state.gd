extends "res://scripts/game_state.gd"
## Only the test process uses this subclass. The real serializer/loader remain in use.
var fixture_path := "user://saves/preservation_regression_%d.json" % Time.get_ticks_usec()
var fixture_save_count := 0

func save_game() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(build_save_data()))
	file.close()
	fixture_save_count += 1
	return fixture_path
