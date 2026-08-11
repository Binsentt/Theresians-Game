extends Area2D

@export var trigger_for_task_index: int = 0
@export var ui_panel: Panel

func _ready():
	# Kung tapos na ang task na ito, burahin agad ang trigger
	if GameState.current_task_index > trigger_for_task_index:
		queue_free()
	else:

		body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("player"):
		# Sinisiguro nito na hindi mo ma-ti-trigger ang Task 2 kung hindi pa tapos ang Task 1
		if GameState.current_task_index == trigger_for_task_index:
			if ui_panel != null:
				ui_panel.show_completed_with_dialogue()

			queue_free()
