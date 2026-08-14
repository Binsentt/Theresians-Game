extends TextureRect

enum RegistrationStep { GENDER, IDS, NAME_GRADE }

@onready var gender_panel: TextureRect = $GenderSelect
@onready var ids_panel: TextureRect = $StudentParentId
@onready var name_grade_panel: TextureRect = $NameGradeSelect

@onready var male_btn: TextureButton = $GenderSelect/MaleBtn
@onready var female_btn: TextureButton = $GenderSelect/FemaleBtn
@onready var gender_continue_btn: TextureButton = $GenderSelect/GenderContinue

@onready var student_id_input: LineEdit = $StudentParentId/StudentIdInput
@onready var parent_id_input: LineEdit = $StudentParentId/ParentIdInput
@onready var ids_next_btn: TextureButton = $StudentParentId/NextBtn

@onready var name_input: LineEdit = $NameGradeSelect/NameInput
@onready var start_btn: TextureButton = $NameGradeSelect/Start
@onready var validation_panel: PanelContainer = $ValidationPanel
@onready var validation_label: Label = $ValidationPanel/MarginContainer/ValidationLabel

@onready var grade_buttons: Array[TextureButton] = [
	$NameGradeSelect/Grade1,
	$NameGradeSelect/Grade2,
	$NameGradeSelect/Grade3,
	$NameGradeSelect/Grade4,
	$NameGradeSelect/Grade5,
	$NameGradeSelect/Grade6
]

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const PLAYER_HOUSE_SCENE_PATH := "res://interiors/player_house.tscn"
const LOADING_SCENE_PATH := "res://scenes/loading_screen.tscn"
const LoadingScreenController := preload("res://scripts/loading_screen.gd")
const GRADE_LABELS := {
	"Grade1": "Grade 1",
	"Grade2": "Grade 2",
	"Grade3": "Grade 3",
	"Grade4": "Grade 4",
	"Grade5": "Grade 5",
	"Grade6": "Grade 6"
}

var current_step := RegistrationStep.GENDER
var selected_gender := ""
var selected_grade := ""
var selected_grade_btn: TextureButton = null
var _step_transitioning := false
var _sanitizing_id := false
var _play_transitioning := false

var male_tween: Tween
var female_tween: Tween
var start_tween: Tween
var grade_tweens := {}

@export var normal_scale: Vector2 = Vector2(1.0, 1.0)
@export var hover_scale: Vector2 = Vector2(1.08, 1.08)
@export var pressed_scale: Vector2 = Vector2(1.14, 1.14)

@export var hover_duration: float = 0.10
@export var press_duration: float = 0.05
@export var release_duration: float = 0.10

func _ready() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene != null and MusicManager != null:
		MusicManager.play_for_scene(current_scene.scene_file_path)

	_hydrate_registration()
	reset_buttons()

	await get_tree().process_frame

	male_btn.pivot_offset = male_btn.size / 2.0
	female_btn.pivot_offset = female_btn.size / 2.0
	gender_continue_btn.pivot_offset = gender_continue_btn.size / 2.0
	ids_next_btn.pivot_offset = ids_next_btn.size / 2.0
	start_btn.pivot_offset = start_btn.size / 2.0
	for btn in grade_buttons:
		btn.pivot_offset = btn.size / 2.0

	_connect_signals()
	_apply_gender_visuals()
	_apply_grade_visuals()
	_show_initial_gender()

func _connect_signals() -> void:
	if not male_btn.pressed.is_connected(_on_male_btn_pressed):
		male_btn.pressed.connect(_on_male_btn_pressed)
	if not male_btn.mouse_entered.is_connected(_on_male_btn_mouse_entered):
		male_btn.mouse_entered.connect(_on_male_btn_mouse_entered)
	if not male_btn.mouse_exited.is_connected(_on_male_btn_mouse_exited):
		male_btn.mouse_exited.connect(_on_male_btn_mouse_exited)

	if not female_btn.pressed.is_connected(_on_female_btn_pressed):
		female_btn.pressed.connect(_on_female_btn_pressed)
	if not female_btn.mouse_entered.is_connected(_on_female_btn_mouse_entered):
		female_btn.mouse_entered.connect(_on_female_btn_mouse_entered)
	if not female_btn.mouse_exited.is_connected(_on_female_btn_mouse_exited):
		female_btn.mouse_exited.connect(_on_female_btn_mouse_exited)

	if not gender_continue_btn.pressed.is_connected(_on_gender_continue_pressed):
		gender_continue_btn.pressed.connect(_on_gender_continue_pressed)
	if not ids_next_btn.pressed.is_connected(_on_ids_next_pressed):
		ids_next_btn.pressed.connect(_on_ids_next_pressed)
	if not start_btn.pressed.is_connected(_on_start_pressed):
		start_btn.pressed.connect(_on_start_pressed)

	if not student_id_input.text_changed.is_connected(_on_student_id_changed):
		student_id_input.text_changed.connect(_on_student_id_changed)
	if not parent_id_input.text_changed.is_connected(_on_parent_id_changed):
		parent_id_input.text_changed.connect(_on_parent_id_changed)
	if not name_input.text_changed.is_connected(_on_name_input_changed):
		name_input.text_changed.connect(_on_name_input_changed)

	if not start_btn.mouse_entered.is_connected(_on_start_hover):
		start_btn.mouse_entered.connect(_on_start_hover)
	if not start_btn.mouse_exited.is_connected(_on_start_exit):
		start_btn.mouse_exited.connect(_on_start_exit)

	for btn in grade_buttons:
		var hover_callable := Callable(self, "_on_grade_hover").bind(btn)
		var exit_callable := Callable(self, "_on_grade_exit").bind(btn)
		var pressed_callable := Callable(self, "_on_grade_pressed").bind(btn)
		if not btn.mouse_entered.is_connected(hover_callable):
			btn.mouse_entered.connect(hover_callable)
		if not btn.mouse_exited.is_connected(exit_callable):
			btn.mouse_exited.connect(exit_callable)
		if not btn.pressed.is_connected(pressed_callable):
			btn.pressed.connect(pressed_callable)

func _hydrate_registration() -> void:
	var registration := GameState.get_new_game_registration()
	if registration.is_empty():
		GameState.begin_new_game_registration()
		registration = GameState.get_new_game_registration()

	selected_gender = String(registration.get("gender", "")).to_lower()
	selected_grade = String(registration.get("grade", ""))
	student_id_input.text = String(registration.get("student_id", ""))
	parent_id_input.text = String(registration.get("parent_id", ""))
	name_input.text = String(registration.get("student_name", ""))
	selected_grade_btn = _grade_button_for_value(selected_grade)
	if not student_id_input.text.is_empty():
		student_id_input.caret_column = student_id_input.text.length()
	if not parent_id_input.text.is_empty():
		parent_id_input.caret_column = parent_id_input.text.length()

func _show_initial_gender() -> void:
	current_step = RegistrationStep.GENDER
	gender_panel.visible = true
	ids_panel.visible = false
	name_grade_panel.visible = false
	gender_panel.modulate.a = 1.0
	ids_panel.modulate.a = 1.0
	name_grade_panel.modulate.a = 1.0
	validation_panel.visible = false

func reset_buttons() -> void:
	male_btn.texture_normal = preload("res://Images/male_normal.png")
	female_btn.texture_normal = preload("res://Images/female_normal.png")

	male_btn.scale = normal_scale
	female_btn.scale = normal_scale

	for btn in grade_buttons:
		btn.scale = normal_scale

func _apply_gender_visuals() -> void:
	if selected_gender == "male":
		_apply_male_selected_visuals()
	elif selected_gender == "female":
		_apply_female_selected_visuals()
	else:
		male_btn.texture_normal = preload("res://Images/male_normal.png")
		female_btn.texture_normal = preload("res://Images/female_normal.png")

func _apply_male_selected_visuals() -> void:
	male_btn.texture_normal = preload("res://Images/male_selected.png")
	female_btn.texture_normal = preload("res://Images/female_normal.png")
	_animate_button(male_btn, pressed_scale, press_duration)
	_animate_button(female_btn, normal_scale, release_duration)

func _apply_female_selected_visuals() -> void:
	male_btn.texture_normal = preload("res://Images/male_normal.png")
	female_btn.texture_normal = preload("res://Images/female_selected.png")
	_animate_button(female_btn, pressed_scale, press_duration)
	_animate_button(male_btn, normal_scale, release_duration)

func _apply_grade_visuals() -> void:
	for btn in grade_buttons:
		if btn == selected_grade_btn:
			_animate_grade(btn, pressed_scale, press_duration)
		else:
			_animate_grade(btn, normal_scale, release_duration)

func _grade_button_for_value(value: String) -> TextureButton:
	for btn in grade_buttons:
		if String(GRADE_LABELS.get(btn.name, "")) == value:
			return btn
	return null

func _animate_button(btn: TextureButton, target_scale: Vector2, duration: float) -> void:
	if btn == male_btn:
		if male_tween:
			male_tween.kill()
		male_tween = create_tween()
		male_tween.set_trans(Tween.TRANS_SINE)
		male_tween.set_ease(Tween.EASE_OUT)
		male_tween.tween_property(btn, "scale", target_scale, duration)
	elif btn == female_btn:
		if female_tween:
			female_tween.kill()
		female_tween = create_tween()
		female_tween.set_trans(Tween.TRANS_SINE)
		female_tween.set_ease(Tween.EASE_OUT)
		female_tween.tween_property(btn, "scale", target_scale, duration)
	elif btn == start_btn:
		if start_tween:
			start_tween.kill()
		start_tween = create_tween()
		start_tween.set_trans(Tween.TRANS_SINE)
		start_tween.set_ease(Tween.EASE_OUT)
		start_tween.tween_property(btn, "scale", target_scale, duration)

func _animate_grade(btn: TextureButton, target_scale: Vector2, duration: float) -> void:
	if grade_tweens.has(btn) and grade_tweens[btn]:
		grade_tweens[btn].kill()

	var t = create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(btn, "scale", target_scale, duration)

	grade_tweens[btn] = t

func _on_male_btn_pressed() -> void:
	selected_gender = "male"
	GameState.update_new_game_registration({"gender": selected_gender})
	_hide_validation()
	_apply_male_selected_visuals()

func _on_female_btn_pressed() -> void:
	selected_gender = "female"
	GameState.update_new_game_registration({"gender": selected_gender})
	_hide_validation()
	_apply_female_selected_visuals()

func _on_gender_continue_pressed() -> void:
	if _step_transitioning or _play_transitioning:
		return
	if selected_gender not in ["male", "female"]:
		_show_validation("Please select your gender.")
		return

	GameState.update_new_game_registration({"gender": selected_gender})
	await _show_step(RegistrationStep.IDS)

func _on_student_id_changed(new_text: String) -> void:
	_sanitize_id_field(student_id_input, new_text)
	GameState.update_new_game_registration({"student_id": student_id_input.text})
	if GameState.is_valid_six_digit_id(student_id_input.text):
		_hide_validation()

func _on_parent_id_changed(new_text: String) -> void:
	_sanitize_id_field(parent_id_input, new_text)
	GameState.update_new_game_registration({"parent_id": parent_id_input.text})
	if GameState.is_valid_six_digit_id(parent_id_input.text):
		_hide_validation()

func _sanitize_id_field(field: LineEdit, value: String) -> void:
	if _sanitizing_id:
		return

	var sanitized := GameState.sanitize_six_digit_id(value)
	if sanitized == value:
		return

	_sanitizing_id = true
	field.text = sanitized
	field.caret_column = sanitized.length()
	_sanitizing_id = false

func _on_ids_next_pressed() -> void:
	if _step_transitioning or _play_transitioning:
		return

	GameState.update_new_game_registration({
		"student_id": student_id_input.text,
		"parent_id": parent_id_input.text
	})
	if not GameState.is_valid_six_digit_id(student_id_input.text):
		_show_validation("Student ID must contain exactly 6 digits.")
		student_id_input.grab_focus()
		return
	if not GameState.is_valid_six_digit_id(parent_id_input.text):
		_show_validation("Parent ID must contain exactly 6 digits.")
		parent_id_input.grab_focus()
		return

	_step_transitioning = true
	var validation_result := await _validate_ids_with_backend()
	_step_transitioning = false
	if not validation_result.get("ok", false):
		_show_validation(String(validation_result.get("error", "Unable to validate registration.")))
		return

	if validation_result.get("offline", false):
		_show_validation(String(validation_result.get("warning", "Offline test mode: Parent ID could not be verified.")))
		await _show_step(RegistrationStep.NAME_GRADE)
		return

	_hide_validation()
	await _show_step(RegistrationStep.NAME_GRADE)

func _validate_ids_with_backend() -> Dictionary:
	var http := get_node_or_null("/root/HttpApi")
	if http == null:
		if GameState.ALLOW_OFFLINE_NEW_GAME_TESTING and GameState.is_valid_six_digit_id(student_id_input.text) and GameState.is_valid_six_digit_id(parent_id_input.text):
			return {"ok": true, "offline": true, "warning": "Offline test mode: Parent ID could not be verified."}
		return {"ok": false, "error": "Unable to connect to the server. Please try again."}

	var parent_result: Dictionary = await http.request_post("/api/game/parent/validate", {
		"parent_id": parent_id_input.text
	})
	var parent_body: Dictionary = parent_result.get("body", {})
	var parent_ok := bool(parent_result.get("ok", false)) or bool(parent_result.get("success", false)) or bool(parent_body.get("ok", false)) or bool(parent_body.get("success", false))
	var parent_status: int = int(parent_result.get("status", 0))
	if not parent_ok or parent_status < 200 or parent_status >= 300:
		if GameState.ALLOW_OFFLINE_NEW_GAME_TESTING and GameState.is_valid_six_digit_id(student_id_input.text) and GameState.is_valid_six_digit_id(parent_id_input.text):
			return {"ok": true, "offline": true, "warning": "Offline test mode: Parent ID could not be verified."}
		return {"ok": false, "error": _registration_api_error(parent_result, "Parent ID does not exist.")}

	var profile_result: Dictionary = await http.request_get("/api/game/profile/check/" + student_id_input.text, {
		"parent_id": parent_id_input.text
	})
	var profile_body: Dictionary = profile_result.get("body", {})
	var profile_ok := bool(profile_result.get("ok", false)) or bool(profile_body.get("ok", false))
	var profile_status: int = int(profile_result.get("status", 0))
	if not profile_ok or profile_status < 200 or profile_status >= 300:
		if GameState.ALLOW_OFFLINE_NEW_GAME_TESTING and GameState.is_valid_six_digit_id(student_id_input.text) and GameState.is_valid_six_digit_id(parent_id_input.text):
			return {"ok": true, "offline": true, "warning": "Offline test mode: Parent ID could not be verified."}
		return {"ok": false, "error": _registration_api_error(profile_result, "Unable to connect to the server. Please try again.")}
	if profile_body.get("should_block", false):
		return {"ok": false, "error": String(profile_body.get("error", "Student ID already has an existing game profile. Please use Load Game."))}

	return {"ok": true}

func _registration_api_error(result: Dictionary, fallback: String) -> String:
	var body: Variant = result.get("body", {})
	if body is Dictionary:
		var message: String = String(body.get("error", body.get("message", ""))).strip_edges()
		if not message.is_empty():
			if message.to_lower() == "parent id not found." or message.to_lower() == "parent id does not exist.":
				return "Parent ID does not exist."
			if message.to_lower() == "parent account is no longer active.":
				return "Parent account is no longer active."
			return message
	return fallback

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

func _on_grade_hover(btn: TextureButton) -> void:
	if btn == selected_grade_btn:
		_animate_grade(btn, Vector2(1.18, 1.18), hover_duration)
	else:
		_animate_grade(btn, hover_scale, hover_duration)

func _on_grade_exit(btn: TextureButton) -> void:
	if btn == selected_grade_btn:
		_animate_grade(btn, pressed_scale, release_duration)
	else:
		_animate_grade(btn, normal_scale, release_duration)

func _on_grade_pressed(btn: TextureButton) -> void:
	selected_grade_btn = btn
	selected_grade = String(GRADE_LABELS.get(btn.name, ""))
	GameState.update_new_game_registration({"grade": selected_grade})
	_hide_validation()

	for other_btn in grade_buttons:
		if other_btn != btn:
			_animate_grade(other_btn, normal_scale, release_duration)

	_animate_grade(btn, pressed_scale, press_duration)

func _on_start_hover() -> void:
	_animate_button(start_btn, hover_scale, hover_duration)

func _on_start_exit() -> void:
	_animate_button(start_btn, normal_scale, release_duration)

func _on_start_pressed() -> void:
	if _play_transitioning or _step_transitioning:
		return

	_play_transitioning = true
	_animate_button(start_btn, pressed_scale, press_duration)
	_sync_form_to_registration()

	var validation_error := _first_registration_error()
	if not validation_error.is_empty():
		_show_validation(validation_error)
		_focus_first_invalid_field(validation_error)
		_animate_button(start_btn, normal_scale, release_duration)
		_play_transitioning = false
		return

	_hide_validation()
	var registration := GameState.get_new_game_registration()
	var playtimeResult := await RemoteSync.request_playtime_session({
		"student_id": String(registration.get("student_id", "")),
		"parent_id": String(registration.get("parent_id", "")),
		"student_name": String(registration.get("student_name", "")),
		"grade_level": String(registration.get("grade", "")),
		"section": ""
	})
	if not playtimeResult.ok or playtimeResult.get("can_play", true) == false or playtimeResult.get("should_block", false) == true:
		var errorText := String(playtimeResult.get("error", "Unable to connect to playtime service."))
		if playtimeResult.get("status", 0) == 403 or playtimeResult.get("should_block", false) == true:
			errorText = String(playtimeResult.get("error", "Daily playtime limit reached."))
		_show_validation(errorText)
		_play_transitioning = false
		return

	if not GameState.finalize_new_game_registration():
		_show_validation(_first_registration_error())
		_play_transitioning = false
		return

	GameState.queue_scene_spawn(
		GameState.START_SCENE_PATH,
		GameState.get_scene_fallback_spawn(GameState.START_SCENE_PATH),
		"down"
	)

	var next_scene_path := LOADING_SCENE_PATH if ResourceLoader.exists(LOADING_SCENE_PATH) else PLAYER_HOUSE_SCENE_PATH
	if next_scene_path == LOADING_SCENE_PATH:
		LoadingScreenController.prepare_new_game(PLAYER_HOUSE_SCENE_PATH)
	else:
		LoadingScreenController.cancel_pending_request()
	var result := get_tree().change_scene_to_file(next_scene_path)
	if result != OK:
		LoadingScreenController.cancel_pending_request()
		_play_transitioning = false
		_show_validation("Unable to start the new game.")

func _sync_form_to_registration() -> void:
	GameState.update_new_game_registration({
		"gender": selected_gender,
		"student_id": student_id_input.text,
		"parent_id": parent_id_input.text,
		"student_name": name_input.text,
		"grade": selected_grade
	})

func _first_registration_error() -> String:
	var values := GameState.get_new_game_registration()
	if String(values.get("gender", "")).to_lower() not in ["male", "female"]:
		return "Please select your gender."
	if not GameState.is_valid_six_digit_id(String(values.get("student_id", ""))):
		return "Student ID must contain exactly 6 digits."
	if not GameState.is_valid_six_digit_id(String(values.get("parent_id", ""))):
		return "Parent ID must contain exactly 6 digits."
	if String(values.get("student_name", "")).strip_edges().is_empty():
		return "Please enter your name."
	if String(values.get("grade", "")) not in GameState.VALID_REGISTRATION_GRADES:
		return "Please select your grade."
	return ""

func _focus_first_invalid_field(validation_error: String) -> void:
	if validation_error.begins_with("Student ID"):
		student_id_input.grab_focus()
	elif validation_error.begins_with("Parent ID"):
		parent_id_input.grab_focus()
	elif validation_error.begins_with("Please enter"):
		name_input.grab_focus()

func handle_back() -> void:
	if _step_transitioning or _play_transitioning:
		return

	_sync_form_to_registration()
	match current_step:
		RegistrationStep.GENDER:
			GameState.clear_new_game_registration()
			_step_transitioning = true
			await _fade_and_change_scene_to_main_menu()
		RegistrationStep.IDS:
			await _show_step(RegistrationStep.GENDER)
		RegistrationStep.NAME_GRADE:
			await _show_step(RegistrationStep.IDS)

func _show_step(next_step: int) -> void:
	if _step_transitioning or _play_transitioning:
		return

	_step_transitioning = true
	_hide_validation()
	_hydrate_registration()

	var current_panel := _panel_for_step(current_step)
	var next_panel := _panel_for_step(next_step)
	if current_panel != next_panel and current_panel.visible:
		var fade_out := create_tween()
		fade_out.set_trans(Tween.TRANS_SINE)
		fade_out.set_ease(Tween.EASE_OUT)
		fade_out.tween_property(current_panel, "modulate:a", 0.0, 0.15)
		await fade_out.finished
		current_panel.visible = false

	current_step = next_step as RegistrationStep
	next_panel.visible = true
	next_panel.modulate.a = 0.0
	var fade_in := create_tween()
	fade_in.set_trans(Tween.TRANS_SINE)
	fade_in.set_ease(Tween.EASE_OUT)
	fade_in.tween_property(next_panel, "modulate:a", 1.0, 0.2)
	await fade_in.finished

	_apply_gender_visuals()
	_apply_grade_visuals()
	if current_step == RegistrationStep.IDS:
		student_id_input.grab_focus()
	elif current_step == RegistrationStep.NAME_GRADE:
		name_input.grab_focus()
	_step_transitioning = false

func _panel_for_step(step: int) -> TextureRect:
	match step:
		RegistrationStep.GENDER:
			return gender_panel
		RegistrationStep.IDS:
			return ids_panel
		RegistrationStep.NAME_GRADE:
			return name_grade_panel
	return gender_panel

func _fade_and_change_scene_to_main_menu() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := get_tree().current_scene.get_node_or_null("Fade") as CanvasItem
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	if fade != null:
		tween.parallel().tween_property(fade, "modulate:a", 1.0, 0.25)
	await tween.finished
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func _show_validation(message: String) -> void:
	validation_label.text = message
	validation_panel.visible = true

func _hide_validation() -> void:
	validation_label.text = ""
	validation_panel.visible = false

func _on_name_input_changed(new_text: String) -> void:
	GameState.update_new_game_registration({"student_name": new_text})
	if not new_text.strip_edges().is_empty():
		_hide_validation()
