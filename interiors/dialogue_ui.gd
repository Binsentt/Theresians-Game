extends Panel

@onready var dialogue_text = $DialogueText

func _ready():
	self.visible = false # Nakatago muna sa simula

func start_dialogue(text_to_show: String, duration: float):
	self.visible = true
	dialogue_text.text = text_to_show
	
	await get_tree().create_timer(duration).timeout
	
	self.visible = false
