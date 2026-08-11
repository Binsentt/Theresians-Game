extends Node

const GAME_HUD_SCENE := preload("res://ui/game_hud.tscn")

func _ready() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return

	if current_scene.get_node_or_null("GameHUD") != null:
		return

	var hud: CanvasLayer = GAME_HUD_SCENE.instantiate() as CanvasLayer
	if hud == null:
		return

	hud.name = "GameHUD"
	current_scene.add_child.call_deferred(hud)
