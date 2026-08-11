extends Node2D

@onready var anim = $AnimatedSprite2D

func _ready():
	visible = false

func play_effect():

	print("Playing Effect:", get_parent().name)

	visible = true

	anim.stop()
	anim.frame = 0

	anim.play("explode")  


func _on_animated_sprite_2d_animation_finished():

	visible = false
