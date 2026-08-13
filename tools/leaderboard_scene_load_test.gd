extends SceneTree


func _init() -> void:
	var scene := load("res://leaderboard_scene.tscn") as PackedScene
	if scene == null:
		printerr("[Leaderboard Scene Test] The leaderboard scene must load.")
		quit(1)
		return
	var instance := scene.instantiate()
	if instance.get_script() == null:
		printerr("[Leaderboard Scene Test] The API-backed leaderboard controller must remain attached.")
		instance.free()
		quit(1)
		return
	instance.free()
	quit()
