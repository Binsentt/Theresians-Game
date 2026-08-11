extends Node

var max_health := 3
var health := 3

@onready var hearts = [
	$Hearts/Heart1,
	$Hearts/Heart2,
	$Hearts/Heart3
]

func _ready():
	update_hearts()

func take_damage():
	if health > 0:
		health -= 1
		update_hearts()

func update_hearts():
	for i in range(max_health):
		hearts[i].visible = i < health
