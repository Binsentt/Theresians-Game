xtends CanvasLayer

const LIFE_SCENE := preload("res://player/life.tscn")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_OVER_SCENE := "res://scenes/game_over_scene.tscn"
const BATTLE_PLAYER_HEART_SIZE := Vector2(28, 32)
const EXPLORATION_PLAYER_HEART_SIZE := Vector2(28, 32)
const BATTLE_PLAYER_HEART_SCALE := Vector2(0.66, 0.68)
const EXPLORATION_PLAYER_HEART_SCALE := Vector2(0.66, 0.68)
const PLAYER_HEART_BATTLE_SPACING := 6
const PLAYER_HEART_EXPLORATION_SPACING := 6
const SETTINGS_INGAME_SCENE := preload("res://scenes/Settings-Ingame/settings_ingame.tscn")

@onready var player_label: Label = $MarginContainer/PlayerPanel/VBoxContainer/PlayerLabel
@onready var lives_container: HBoxContainer = $MarginContainer/PlayerPanel/VBoxContainer/LivesRow
@onready var save_button: Button = $MarginContainer/PlayerPanel/VBoxContainer/ActionsRow/SaveButton
@onready var save_status_label: Label = $MarginContainer/PlayerPanel/VBoxContainer/SaveStatusLabel
@onready var quest_label: Label = $MarginContainer/PlayerPanel/VBoxContainer/QuestLabel
@onready var game_over_overlay: Control = $GameOverOverlay
@onready var return_button: Button = $GameOverOverlay/PanelContainer/VBoxContainer/ReturnButton

var _life_icons: Array[Control] = []
var _playtime_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_life_icons()
	_build_settings_overlay()
	player_label.text = "HP"
	refresh_lives(GameState.current_lives, GameState.max_lives)
	save_status_label.text = ""
	_update_quest_label()
	_ensure_playtime_label()
	_update_playtime_label()
	game_over_overlay.visible = false

	if not GameState.lives_changed.is_connected(refresh_lives):
		GameState.lives_changed.connect(refresh_lives)
	if not GameState.quest_changed.is_connected(_on_quest_changed):
		GameState.quest_changed.connect(_on_quest_changed)
	if not GameState.save_created.is_connected(_on_save_created):
		GameState.save_created.connect(_on_save_created)
	if not GameState.game_over.is_connected(_on_game_over):
		GameState.game_over.connect(_on_game_over)
	if not GameState.time_limit_reached.is_connected(_on_time_limit_reached):
		GameState.time_limit_reached.connect(_on_time_limit_reached)

	if not save_button.pressed.is_connected(_on_save_button_pressed):
		save_button.pressed.connect(_on_save_button_pressed)
	if not return_button.pressed.is_connected(_on_return_button_pressed):
		return_button.pressed.connect(_on_return_button_pressed)

func _ensure_playtime_label() -> void:
	if _playtime_label != null and is_instance_valid(_playtime_label):
		return
	_playtime_label = Label.new()
	_playtime_label.name = "PlaytimeLabel"
	_playtime_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_playtime_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_playtime_label.theme_override_fonts/font = quest_label.get_theme_font_override("font") if quest_label != null else null
	_playtime_label.theme_override_font_sizes/font_size = 9
	_playtime_label.visible = true
	_playtime_label.text = ""
	$MarginContainer/PlayerPanel/VBoxContainer.add_child(_playtime_label)

func _update_playtime_label() -> void:
	if _playtime_label == null or not is_instance_valid(_playtime_label):
		return
	if GameState.playtime_limit_minutes <= 0:
		_playtime_label.text = "Time Left: --"
		return
	var remaining_seconds := maxf(0.0, GameState.get_playtime_remaining_seconds())
	var minutes := int(ceil(remaining_seconds / 60.0))
	_playtime_label.text = "Time Left: %s min" % String(minutes)

func refresh_lives(current_lives: int, total_lives: int) -> void:
	if _life_icons.size() != total_lives:
		_rebuild_life_icons(total_lives)

	_apply_player_heart_style()

	for index in range(_life_icons.size()):
		_life_icons[index].visible = index < current_lives

func _process(_delta: float) -> void:
	_update_playtime_label()

func _build_life_icons() -> void:
	_rebuild_life_icons(GameState.max_lives)

func _rebuild_life_icons(total_lives: int) -> void:
	for child in lives_container.get_children():
		child.queue_free()

	_life_icons.clear()

	for _index in range(total_lives):
		var life_icon: Control = LIFE_SCENE.instantiate() as Control
		lives_container.add_child(life_icon)
		_life_icons.append(life_icon)

	_apply_player_heart_style()

func _on_save_button_pressed() -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player_character") as Node2D
	if player == null:
		save_status_label.text = "Player not found."
		return

	var current_scene: Node = get_tree().current_scene
	GameState.capture_runtime(current_scene.scene_file_path, player.global_position)
	var save_path: String = GameState.save_game()

	if save_path.is_empty():
		save_status_label.text = "Save failed."

func _on_save_created(save_data: Dictionary) -> void:
	save_status_label.text = "Saved %s %s" % [
		String(save_data.get("save_date", "")),
		String(save_data.get("save_time", ""))
	]

func _on_game_over() -> void:
	save_button.disabled = true

	if ResourceLoader.exists(GAME_OVER_SCENE):
		get_tree().change_scene_to_file(GAME_OVER_SCENE)
		return

	game_over_overlay.visible = true

func _on_time_limit_reached() -> void:
	var label := get_node_or_null("GameOverOverlay/PanelContainer/VBoxContainer/Label") as Label
	var description := get_node_or_null("GameOverOverlay/PanelContainer/VBoxContainer/Description") as Label
	if label != null:
		label.text = "TIME LIMIT REACHED"
	if description != null:
		description.text = "Daily playtime allowance is complete."
	if game_over_overlay != null:
		game_over_overlay.visible = true
	if save_button != null:
		save_button.disabled = true
	if return_button != null:
		return_button.disabled = false

func show_time_limit_reached() -> void:
	_on_time_limit_reached()

func _on_return_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _apply_player_heart_style() -> void:
	var current_scene: Node = get_tree().current_scene
	var scene_path: String = ""
	if current_scene != null:
		scene_path = current_scene.scene_file_path

	var use_large_hearts: bool = GameState.should_use_large_player_hearts(scene_path)
	var heart_size: Vector2 = EXPLORATION_PLAYER_HEART_SIZE if use_large_hearts else BATTLE_PLAYER_HEART_SIZE
	var heart_scale: Vector2 = EXPLORATION_PLAYER_HEART_SCALE if use_large_hearts else BATTLE_PLAYER_HEART_SCALE
	lives_container.add_theme_constant_override(
		"separation",
		PLAYER_HEART_EXPLORATION_SPACING if use_large_hearts else PLAYER_HEART_BATTLE_SPACING
	)

	for life_icon: Control in _life_icons:
		_apply_heart_style_to_icon(life_icon, heart_size, heart_scale)

func _apply_heart_style_to_icon(icon: Control, heart_size: Vector2, heart_scale: Vector2) -> void:
	if icon == null:
		return

	icon.custom_minimum_size = heart_size
	icon.size = heart_size

	var sprite: Sprite2D = icon.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return

	sprite.scale = heart_scale
	sprite.position = heart_size / 2.0

func _build_settings_overlay() -> void:
	if get_node_or_null("Settings-Ingame") != null:
		return

	var settings_ui: Control = SETTINGS_INGAME_SCENE.instantiate() as Control
	if settings_ui == null:
		push_error("Unable to load in-game settings scene.")
		return

	settings_ui.name = "Settings-Ingame"
	settings_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(settings_ui)

func _on_quest_changed(_current_quest: String) -> void:
	_update_quest_label()

func _update_quest_label() -> void:
	if quest_label == null:
		return

	var current_quest := GameState.current_quest.strip_edges()
	if current_quest.is_empty() or current_quest == GameState.DEFAULT_QUEST:
		quest_label.text = ""
		quest_label.visible = false
		return

	quest_label.visible = true
	quest_label.text = "Quest: %s" % current_quest
