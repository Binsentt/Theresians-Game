extends "res://scripts/game_state.gd"

var fixture_paths: Array[String] = []

func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	for save_path in fixture_paths:
		if not FileAccess.file_exists(ProjectSettings.globalize_path(save_path)):
			continue
		var save_data := _read_save_file(save_path)
		if save_data.is_empty():
			saves.append(_build_unavailable_save_entry(save_path, "This save file is malformed or unavailable."))
		else:
			saves.append(_prepare_save_entry(save_data, save_path))
	saves.sort_custom(Callable(self, "_sort_saves_desc"))
	return saves
