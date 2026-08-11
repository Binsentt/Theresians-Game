extends Panel

@onready var quest_text = get_node_or_null("QuestText")
@onready var feedback_text = get_node_or_null("FeedbackText")
@onready var dialogue_text = get_node_or_null("DialogueText")
@onready var npc_image = get_node_or_null("NPCImage")

func _ready():
	update_task_ui()


func update_task_ui():
	if GameState.current_task_index >= GameState.tasks.size():
		visible = false
		return

	var current_task_data = GameState.tasks[GameState.current_task_index]

	if quest_text:
		quest_text.text = current_task_data["quest_text"]
		quest_text.visible = true

	if npc_image:
		npc_image.visible = false

	if feedback_text:
		feedback_text.visible = false

	if dialogue_text:
		dialogue_text.visible = false

	visible = true


func show_completed_with_dialogue():
	if GameState.current_task_index >= GameState.tasks.size():
		return

	var current_task_data = GameState.tasks[GameState.current_task_index]


	if quest_text:
		quest_text.visible = false


	if dialogue_text:
		dialogue_text.visible = true


	var sprite_path = current_task_data.get("NPC", "res://Images/NPC.jpg")

	if npc_image:
		npc_image.texture = load(sprite_path)
		npc_image.visible = true


	var lines = current_task_data.get("dialogue", [])

	for line in lines:
		if dialogue_text:
			dialogue_text.text = line

		await get_tree().create_timer(4.0).timeout


	if current_task_data.has("next_scene"):

		await get_tree().create_timer(1.0).timeout

		var battle_scene = load(current_task_data["next_scene"]).instantiate()

		# Add battle as overlay
		get_tree().current_scene.add_child(battle_scene)


		visible = false


		await battle_scene.battle_finished


		battle_scene.queue_free()


		visible = true

	# Hide dialogue
	if npc_image:
		npc_image.visible = false

	if dialogue_text:
		dialogue_text.visible = false

	# Show completed message
	if feedback_text:
		feedback_text.text = "Task %d Completed!" % (GameState.current_task_index + 1)
		feedback_text.visible = true

	GameState.complete_task()

	await get_tree().create_timer(3.0).timeout

	if GameState.current_task_index < GameState.tasks.size():
		update_task_ui()
	else:
		queue_free()


func play_teacher_dialogue():
	# Keep the existing dialogue, battle, cutscene/animation, and completion
	# behavior in one implementation; TeacherTaskInteraction only awaits it.
	var previous_task_index := GameState.current_task_index
	await show_completed_with_dialogue()
	if GameState.current_task_index > previous_task_index:
		# The legacy completion routine advances the in-memory index but does not
		# persist or broadcast it. The Teacher adapter owns that narrow bridge so
		# existing dialogue and battle content remains unchanged.
		GameState.save_game()
		GameState.task_state_changed.emit(
			previous_task_index,
			GameState.current_task_index,
			{
				"type": "quest_completed",
				"key": "quest:main:task:%d:complete" % previous_task_index,
				"title": "Task %d Complete" % (previous_task_index + 1),
				"description": "Teacher conversation completed",
				"source": "teacher_interaction",
				"reason": "teacher_task_completed",
			}
		)
