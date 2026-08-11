extends TextureRect

@onready var male_btn: TextureButton = $GenderSelect/MaleBtn
@onready var female_btn: TextureButton = $GenderSelect/FemaleBtn



var selected_gender := ""

var male_tween: Tween
var female_tween: Tween

@export var normal_scale: Vector2 = Vector2(1.0, 1.0)
@export var hover_scale: Vector2 = Vector2(1.08, 1.08)
@export var pressed_scale: Vector2 = Vector2(1.14, 1.14)

@export var hover_duration: float = 0.10
@export var press_duration: float = 0.05
@export var release_duration: float = 0.10

func _ready() -> void:
	reset_buttons()

	await get_tree().process_frame
	male_btn.pivot_offset = male_btn.size / 2.0
	female_btn.pivot_offset = female_btn.size / 2.0

	male_btn.mouse_entered.connect(_on_male_btn_mouse_entered)
	male_btn.mouse_exited.connect(_on_male_btn_mouse_exited)
	female_btn.mouse_entered.connect(_on_female_btn_mouse_entered)
	female_btn.mouse_exited.connect(_on_female_btn_mouse_exited)

func reset_buttons() -> void:
	male_btn.texture_normal = preload("res://Images/male_normal.png")
	female_btn.texture_normal = preload("res://Images/female_normal.png")

func select_male() -> void:
	selected_gender = "male"

	male_btn.texture_normal = preload("res://Images/male_selected.png")
	female_btn.texture_normal = preload("res://Images/female_normal.png")

	_animate_button(male_btn, pressed_scale, press_duration)
	_animate_button(female_btn, normal_scale, release_duration)

func select_female() -> void:
	selected_gender = "female"

	male_btn.texture_normal = preload("res://Images/male_normal.png")
	female_btn.texture_normal = preload("res://Images/female_selected.png")

	_animate_button(female_btn, pressed_scale, press_duration)
	_animate_button(male_btn, normal_scale, release_duration)

func _animate_button(btn: TextureButton, target_scale: Vector2, duration: float) -> void:
	if btn == male_btn:
		if male_tween:
			male_tween.kill()
		male_tween = create_tween()
		male_tween.set_trans(Tween.TRANS_SINE)
		male_tween.set_ease(Tween.EASE_OUT)
		male_tween.tween_property(btn, "scale", target_scale, duration)
	else:
		if female_tween:
			female_tween.kill()
		female_tween = create_tween()
		female_tween.set_trans(Tween.TRANS_SINE)
		female_tween.set_ease(Tween.EASE_OUT)
		female_tween.tween_property(btn, "scale", target_scale, duration)

func _on_male_btn_pressed() -> void:
	select_male()

func _on_female_btn_pressed() -> void:
	select_female()

func _on_male_btn_mouse_entered() -> void:
	if selected_gender == "male":
		_animate_button(male_btn, Vector2(1.18, 1.18), hover_duration)
	else:
		_animate_button(male_btn, hover_scale, hover_duration)

func _on_male_btn_mouse_exited() -> void:
	if selected_gender == "male":
		_animate_button(male_btn, pressed_scale, release_duration)
	else:
		_animate_button(male_btn, normal_scale, release_duration)

func _on_female_btn_mouse_entered() -> void:
	if selected_gender == "female":
		_animate_button(female_btn, Vector2(1.18, 1.18), hover_duration)
	else:
		_animate_button(female_btn, hover_scale, hover_duration)

func _on_female_btn_mouse_exited() -> void:
	if selected_gender == "female":
		_animate_button(female_btn, pressed_scale, release_duration)
	else:
		_animate_button(female_btn, normal_scale, release_duration)
