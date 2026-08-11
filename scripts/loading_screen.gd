extends Control

enum LoadingMode { STARTUP, NEW_GAME, LOAD_GAME, CONNECTION_RETRY }

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const DEFAULT_NEW_GAME_SCENE_PATH := "res://interiors/player_house.tscn"
const START_SCENE_DELAY := 0.75
const DOT_UPDATE_DELAY := 0.25
const PROGRESS_UPDATE_DELAY := 0.04
const PROGRESS_STEP := 2.5
const MAX_DOTS := 3
const CONNECTION_ERROR_MESSAGE := "Unable to connect. Please try again."

static var _pending_mode: int = LoadingMode.STARTUP
static var _pending_destination_scene: String = MAIN_MENU_SCENE_PATH
static var _pending_connection_message: String = CONNECTION_ERROR_MESSAGE

var current_mode: int
var destination_scene: String

@onready var loading_content: Control = $LoadingContent
@onready var loading_label: Label = $LoadingContent/Panel/MarginContainer/Content/LoadingLabel
@onready var subtitle: Label = $LoadingContent/Panel/MarginContainer/Content/Subtitle
@onready var progress_bar: ProgressBar = $LoadingContent/Panel/MarginContainer/Content/ProgressBar
@onready var error_panel: PanelContainer = $ErrorPanel
@onready var error_title: Label = $ErrorPanel/MarginContainer/Content/ErrorTitle
@onready var error_message: Label = $ErrorPanel/MarginContainer/Content/ErrorMessage
@onready var retry_button: Button = $ErrorPanel/MarginContainer/Content/Actions/RetryButton
@onready var return_button: Button = $ErrorPanel/MarginContainer/Content/Actions/ReturnButton
@onready var dots_timer: Timer = $DotsTimer
@onready var progress_timer: Timer = $ProgressTimer
@onready var start_timer: Timer = $StartTimer

var _dot_count: int = 0
var _connection_error_message: String = CONNECTION_ERROR_MESSAGE
var _retry_callback: Callable = Callable()
var _retry_in_progress: bool = false
var _return_in_progress: bool = false
var _transition_in_progress: bool = false

static func prepare_new_game(destination: String = DEFAULT_NEW_GAME_SCENE_PATH) -> void:
	_pending_mode = LoadingMode.NEW_GAME
	_pending_destination_scene = destination
	_pending_connection_message = CONNECTION_ERROR_MESSAGE

static func prepare_load_game(destination: String) -> void:
	_pending_mode = LoadingMode.LOAD_GAME
	_pending_destination_scene = destination
	_pending_connection_message = CONNECTION_ERROR_MESSAGE

# Cross-scene requests carry presentation only; callbacks belong to the active screen.
static func prepare_connection_retry(message: String = CONNECTION_ERROR_MESSAGE) -> void:
	_pending_mode = LoadingMode.CONNECTION_RETRY
	_pending_destination_scene = MAIN_MENU_SCENE_PATH
	_pending_connection_message = message

static func cancel_pending_request() -> void:
	_pending_mode = LoadingMode.STARTUP
	_pending_destination_scene = MAIN_MENU_SCENE_PATH
	_pending_connection_message = CONNECTION_ERROR_MESSAGE

func _ready() -> void:
	_consume_pending_request()
	MusicManager.play_for_scene(scene_file_path)
	_connect_signals_once()
	_apply_mode_copy()

	if current_mode == LoadingMode.CONNECTION_RETRY:
		show_connection_error(_connection_error_message)
		return

	_start_loading_timers()

func _consume_pending_request() -> void:
	current_mode = _pending_mode
	destination_scene = _pending_destination_scene
	_connection_error_message = _pending_connection_message
	cancel_pending_request()

func _connect_signals_once() -> void:
	if not dots_timer.timeout.is_connected(_on_dots_timer_timeout):
		dots_timer.timeout.connect(_on_dots_timer_timeout)
	if not progress_timer.timeout.is_connected(_on_progress_timer_timeout):
		progress_timer.timeout.connect(_on_progress_timer_timeout)
	if not start_timer.timeout.is_connected(_on_start_timer_timeout):
		start_timer.timeout.connect(_on_start_timer_timeout)
	if not retry_button.pressed.is_connected(_on_retry_button_pressed):
		retry_button.pressed.connect(_on_retry_button_pressed)
	if not return_button.pressed.is_connected(_on_return_button_pressed):
		return_button.pressed.connect(_on_return_button_pressed)

func _apply_mode_copy() -> void:
	loading_content.show()
	error_panel.hide()
	loading_label.text = "Loading"
	progress_bar.value = progress_bar.min_value

	match current_mode:
		LoadingMode.NEW_GAME:
			subtitle.text = "Beginning a new adventure"
		LoadingMode.LOAD_GAME:
			subtitle.text = "Restoring your saved adventure"
		LoadingMode.CONNECTION_RETRY:
			subtitle.text = "Waiting to reconnect"
		_:
			subtitle.text = "Preparing Theresian's Quest"

func _start_loading_timers() -> void:
	dots_timer.wait_time = DOT_UPDATE_DELAY
	progress_timer.wait_time = PROGRESS_UPDATE_DELAY
	start_timer.wait_time = START_SCENE_DELAY
	dots_timer.start()
	progress_timer.start()
	start_timer.start()

func _stop_loading_timers() -> void:
	dots_timer.stop()
	progress_timer.stop()
	start_timer.stop()

func _on_dots_timer_timeout() -> void:
	_dot_count = (_dot_count + 1) % (MAX_DOTS + 1)
	loading_label.text = "Loading%s" % ".".repeat(_dot_count)

func _on_progress_timer_timeout() -> void:
	var next_value := progress_bar.value + PROGRESS_STEP
	if next_value > progress_bar.max_value:
		next_value = progress_bar.min_value
	progress_bar.value = next_value

func _on_start_timer_timeout() -> void:
	if _transition_in_progress:
		return

	_transition_in_progress = true
	_stop_loading_timers()
	if destination_scene.is_empty() or not ResourceLoader.exists(destination_scene):
		_transition_in_progress = false
		_show_loading_error("The requested scene could not be loaded. Return to the main menu and try again.")
		return

	var result := get_tree().change_scene_to_file(destination_scene)
	if result != OK:
		_transition_in_progress = false
		_show_loading_error("The requested scene could not be opened. Return to the main menu and try again.")

func show_connection_error(
	message: String = CONNECTION_ERROR_MESSAGE,
	retry_callback: Callable = Callable()
) -> void:
	_stop_loading_timers()
	current_mode = LoadingMode.CONNECTION_RETRY
	loading_content.hide()
	error_title.text = "Connection Error"
	error_message.text = message
	error_panel.show()

	_retry_callback = retry_callback if retry_callback.is_valid() else Callable()
	_retry_in_progress = false
	retry_button.visible = _retry_callback.is_valid()
	retry_button.disabled = not _retry_callback.is_valid()
	return_button.disabled = false

func _show_loading_error(message: String) -> void:
	_stop_loading_timers()
	loading_content.hide()
	error_title.text = "Loading Error"
	error_message.text = message
	error_panel.show()

	_retry_callback = Callable()
	_retry_in_progress = false
	retry_button.hide()
	retry_button.disabled = true
	return_button.disabled = false

func _on_retry_button_pressed() -> void:
	if _retry_in_progress or not _retry_callback.is_valid():
		return

	_retry_in_progress = true
	retry_button.disabled = true
	var callback := _retry_callback
	callback.call()
	call_deferred("_rearm_retry_button")

func _rearm_retry_button() -> void:
	if not is_inside_tree() or not is_instance_valid(error_panel) or not error_panel.visible:
		return

	_retry_in_progress = false
	# Retain only the callback supplied directly to this active loading screen.
	retry_button.visible = _retry_callback.is_valid()
	retry_button.disabled = not _retry_callback.is_valid()

func _on_return_button_pressed() -> void:
	if _return_in_progress:
		return

	_return_in_progress = true
	_stop_loading_timers()
	retry_button.disabled = true
	return_button.disabled = true
	var result := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if result != OK:
		_return_in_progress = false
		return_button.disabled = false
		_rearm_retry_button()
