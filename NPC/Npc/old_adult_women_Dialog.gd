extends AnimatedSprite2D

# I-drag dito ang 'Panel' (HINDI ang buong CanvasLayer)
@export var dialogue_panel: Control

# I-drag dito ang 'DialogueText'
@export var dialogue_label: Label

# Default greeting in English
@export_multiline var greeting_message: String = "Hello traveler! Welcome to our town."

var _dialogue_active: bool = false


func _ready():
	# Isiguradong tago ang Panel sa simula para kita lang ang Quest text
	if dialogue_panel:
		dialogue_panel.hide()


func can_interact() -> bool:
	if _dialogue_active:
		return false
	if GameState.get_mode() != GameState.GameMode.EXPLORATION:
		return false
	var input_manager := get_node_or_null("/root/InputManager")
	if input_manager != null and input_manager.has_method("is_input_locked") and bool(input_manager.call("is_input_locked")):
		return false
	return true


func interact() -> bool:
	if not can_interact():
		return false
	show_dialogue_timed()
	return true


func show_dialogue_timed():
	if _dialogue_active:
		return
	_dialogue_active = true
	GameState.push_mode(GameState.GameMode.DIALOGUE)
	if dialogue_label:
		dialogue_label.text = greeting_message

	if dialogue_panel:
		dialogue_panel.show() # Ito lang ang lalabas, mananatili ang Quest text

		# Wait for 5 seconds
		await get_tree().create_timer(3.0).timeout

		# Pagkatapos ng 5 seconds, itatago lang ang dialogue panel
		hide_dialogue()
	else:
		await get_tree().create_timer(0.2).timeout
		hide_dialogue()


func hide_dialogue():
	# Gagamit tayo ng 'if' check para iwas error kung sakaling naka-hide na
	if dialogue_panel and dialogue_panel.visible:
		dialogue_panel.hide()
	if GameState.get_mode() == GameState.GameMode.DIALOGUE:
		GameState.pop_mode()
	_dialogue_active = false
