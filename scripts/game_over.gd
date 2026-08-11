extends Node2D

@onready var result_label    = $CanvasLayer/ResultLabel
@onready var score_label     = $CanvasLayer/ScoreLabel
@onready var play_again_btn  = $CanvasLayer/PlayAgainBtn

func _ready():
	if GameState.player_won:
		result_label.text     = "You Win!"
		result_label.modulate = Color.YELLOW
	else:
		result_label.text     = " You Lose!"
		result_label.modulate = Color.RED

	score_label.text = "Final Score: " + str(GameState.score)
	play_again_btn.pressed.connect(_on_play_again)

func _on_play_again():
	get_tree().change_scene_to_file("res://Battle/Battle-Enemy/male_vs_bandit.tscn")
