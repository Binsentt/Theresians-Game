extends Node

var max_health := 3
var health := 3
var _game_state: Node

@onready var hearts = [
	$Hearts/Heart1,
	$Hearts/Heart2,
	$Hearts/Heart3
]

func _ready():
	_game_state = get_node_or_null("/root/GameState")
	if _game_state != null:
		if _game_state.has_signal("lives_changed"):
			var lives_changed_callback := Callable(self, "_on_lives_changed")
			if not _game_state.is_connected("lives_changed", lives_changed_callback):
				_game_state.connect("lives_changed", lives_changed_callback)
			_sync_from_game_state()
	else:
		update_hearts()


func _exit_tree() -> void:
	if _game_state != null and is_instance_valid(_game_state):
		var lives_changed_callback := Callable(self, "_on_lives_changed")
		if _game_state.has_signal("lives_changed") and _game_state.is_connected("lives_changed", lives_changed_callback):
			_game_state.disconnect("lives_changed", lives_changed_callback)

func take_damage():
	if _game_state != null:
		if health > 0 and _game_state.has_method("lose_life"):
			_game_state.call("lose_life")
			_sync_from_game_state()
		return
	if health > 0:
		health -= 1
		update_hearts()


func _sync_from_game_state() -> void:
	max_health = maxi(1, int(_game_state.get("max_lives")))
	health = clampi(int(_game_state.get("current_lives")), 0, max_health)
	update_hearts()


func _on_lives_changed(current_lives: int, maximum_lives: int) -> void:
	max_health = maxi(1, maximum_lives)
	health = clampi(current_lives, 0, max_health)
	update_hearts()

func update_hearts():
	for i in range(max_health):
		hearts[i].visible = i < health
