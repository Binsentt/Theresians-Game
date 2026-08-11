extends Panel

@onready var quest_text = $QuestText
@onready var feedback_text = $FeedbackText
@onready var dialogue_text = $DialogueText

func _ready():
	# DITO MO ILALAGAY ANG CHECK:
	if GameState.task_2_done:
		# Kung tapos na ang task, itatago na natin ang lahat agad
		self.visible = false
		quest_text.visible = false
	else:
		# Ito ang dati mong code sa loob ng _ready
		quest_text.text = "Talk to the Teacher"
		quest_text.visible = true
		feedback_text.visible = false
		dialogue_text.visible = false
		self.visible = true

func show_completed_with_dialogue():
	# 1. Itago ang quest text. 
	quest_text.visible = false
	
	# 2. Ipakita ang Dialogue
	dialogue_text.visible = true
	
	var lines = [
		"Teacher: You are ready. Travel through the forest and reach the City of Knowledge",
		"Reward: Forest Path unlocked"
	]
	
	for line in lines:
		dialogue_text.text = line
		await get_tree().create_timer(4.0).timeout
	
	# 3. Itago ang Dialogue
	dialogue_text.visible = false
	
	# 4. Ipakita ang Feedback (Task Completed)
	feedback_text.text = "Task 2 Completed!"
	feedback_text.visible = true
	
	# DITO MO RIN DAPAT I-SET NA TRUE ANG GAMESTATE
	GameState.task_2_done = true
	
	await get_tree().create_timer(3.0).timeout
	
	# 5. Ngayon pwedeng itago ang buong panel (self)
	feedback_text.visible = false
	self.visible = false
	
	queue_free()
