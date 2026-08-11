extends CharacterBody2D

@export var speed = 20
@export var move_time = 3.0

var timer = 0.0
var triggered = false
var step = 0

@onready var panel = get_tree().get_first_node_in_group("dialogue_ui")
@onready var label = panel.get_node("TextLabel")
@onready var image = panel.get_node("Image")
@onready var audio = $AudioStreamPlayer2D

func _ready():
	panel.visible = false

func _physics_process(delta):
	if timer < move_time:
		velocity = Vector2.UP * speed
		timer += delta
	else:
		velocity = Vector2.ZERO

		if not triggered:
			triggered = true
			start_tutorial()

	move_and_slide()


# 👉 START
func start_tutorial():
	panel.visible = true
	step = 0
	show_step()


# 👉 SHOW CURRENT STEP
func show_step():
	if step == 0:
		label.text = "Welcome, student. I will teach you how to play and prepare you for your journey."

		audio.stream = preload("res://audio/teacher1.mp3")
	if step == 1:
		label.text = "Use T pad buttons to move."
		image.texture = preload("res://Images/move.png")
		audio.stream = preload("res://audio/move.mp3")

	elif step == 2:
		label.text = "Press interact button to interact."
		image.texture = preload("res://Images/interact.png")
		audio.stream = preload("res://audio/interact.mp3")

	elif step == 3:
		label.text = "Answer math questions to progress."
		image.texture = preload("res://Images/quiz.png")
		audio.stream = preload("res://audio/quiz.mp3")

	elif step == 4:
		label.text = "You only have three chances to answer incorrectly.If you fail, you must repeat the challenge."
		audio.stream = preload("res://audio/last.mp3")

	elif step == 5:
		label.text = "Well done! You have completed the Quest."
		image.texture = preload("res://Images/completed.png")
		audio.stream = preload("res://audio/completed.mp3")

	elif step == 6:
		label.text = "You have unlocked your first quest.Oakleaf Village is now open for exploration."
		audio.stream = preload("res://audio/quest.mp3")

	elif step == 7:
		label.text = "AFTER TUTORIAL. Come to my house and talk to me"
		audio.stream = preload("res://audio/come.mp3")

		image.texture = null

	audio.play()


# 👉 NEXT BUTTON
func next_step():
	step += 1

	if step > 7:
		panel.visible = false
		hide_npc()
	else:
		show_step()

func hide_npc():
	print("Hiding full NPCTeacher")

	# stop logic
	set_physics_process(false)
	set_process(false)

	# disable collision
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.disabled = true

	# hide ALL children visually
	for child in get_children():
		if child is CanvasItem:
			child.hide()

	# hide root last
	hide()

func _on_button_pressed() -> void:
	next_step() # Replace with function body.
