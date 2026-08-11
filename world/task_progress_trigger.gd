extends Area2D

## One-shot progression trigger for an exploration milestone.
##
## The GameState method owns the increment/save/signal ordering. This adapter
## emits `task_triggered` only after that method reports a successful advance so
## a later notification queue can consume the same event without duplicating
## progression or dialogue behavior.
signal task_triggered(event: Dictionary)

@export var required_task_index: int = 0
@export var event_key: String = "quest:main:task:0:arrival"
@export var notification_title: String = "Task 1"
@export var notification_objective: String = "Talk to the Teacher"

const PLAYER_GROUPS: Array[StringName] = [&"player_character", &"player"]

var _consumed: bool = false


func _ready() -> void:
	if GameState.current_task_index > required_task_index:
		monitoring = false
		set_deferred("monitorable", false)
		return
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _consumed or not _is_valid_player(body):
		return
	if GameState.current_task_index != required_task_index:
		return

	var result: Variant = GameState.advance_task_and_save({
		"type": "quest_updated",
		"key": event_key,
		"title": notification_title,
		"description": notification_objective
	})
	if not (result is Dictionary) or not bool(result.get("advanced", false)):
		return

	_consumed = true
	monitoring = false
	set_deferred("monitorable", false)
	task_triggered.emit({
		"type": "quest_updated",
		"key": event_key,
		"title": notification_title,
		"description": notification_objective,
		"previous_index": result.get("previous_index", required_task_index),
		"current_index": result.get("current_index", GameState.current_task_index)
	})


func _is_valid_player(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	for player_group in PLAYER_GROUPS:
		if body.is_in_group(player_group):
			return true
	return false
