extends SceneTree

func _initialize() -> void:
	var output_path := ProjectSettings.globalize_path("res://tools/godot_probe_output.txt")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string("probe_ok\n")
		file.close()
	quit()
