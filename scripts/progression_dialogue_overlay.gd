extends CanvasLayer

signal dialogue_closed

@onready var panel: Control = $DialoguePanel
@onready var label: Label = $DialoguePanel/DialogueContent/DialogueLabel

var _lines: Array[String] = []
var _line_index := 0
var _await_release := true
var _pointer_held := false
var _last_advance_frame := -1
var _closed := false
var _completed_normally := false


func _ready() -> void:
	panel.visible = false
	panel.gui_input.connect(_on_panel_gui_input)


func _exit_tree() -> void:
	if not _closed:
		_finish_dialogue(false)


func _process(_delta: float) -> void:
	if not panel.visible:
		return
	if _await_release:
		if not InputManager.is_interact_pressed() and not Input.is_action_pressed("ui_accept"):
			_await_release = false
		return
	if not (InputManager.consume_interact_just_pressed() or Input.is_action_just_pressed("ui_accept")):
		return
	_advance_once()


func _on_panel_gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed = (event as InputEventMouseButton).pressed
	else:
		return
	if not pressed:
		_pointer_held = false
		return
	if _pointer_held:
		return
	_pointer_held = true
	_advance_once()
	panel.accept_event()


func _advance_once() -> void:
	if not panel.visible or _last_advance_frame == Engine.get_process_frames():
		return
	_last_advance_frame = Engine.get_process_frames()
	if _line_index + 1 < _lines.size():
		_line_index += 1
		label.text = _lines[_line_index]
		_await_release = true
		return
	_finish_dialogue(true)


func _finish_dialogue(completed: bool) -> void:
	if _closed:
		return
	_closed = true
	_completed_normally = completed
	panel.visible = false
	dialogue_closed.emit()


func show_lines(lines: Array) -> bool:
	_lines.clear()
	for value in lines:
		var line := String(value).strip_edges()
		if not line.is_empty():
			_lines.append(line)
	if _lines.is_empty():
		_finish_dialogue(false)
		return false
	_line_index = 0
	_await_release = true
	_pointer_held = false
	_last_advance_frame = -1
	_closed = false
	_completed_normally = false
	label.text = _lines[0]
	panel.visible = true
	await dialogue_closed
	return _completed_normally
