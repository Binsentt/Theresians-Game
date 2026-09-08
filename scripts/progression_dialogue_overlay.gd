extends CanvasLayer

signal dialogue_closed

@onready var panel: Control = $DialoguePanel
@onready var label: Label = $DialoguePanel/DialogueLabel

var _lines: Array[String] = []
var _line_index := 0
var _await_release := true


func _ready() -> void:
	panel.visible = false


func _process(_delta: float) -> void:
	if not panel.visible:
		return
	if _await_release:
		if not InputManager.is_interact_pressed():
			_await_release = false
		return
	if not InputManager.consume_interact_just_pressed():
		return
	if _line_index + 1 < _lines.size():
		_line_index += 1
		label.text = _lines[_line_index]
		_await_release = true
		return
	panel.visible = false
	dialogue_closed.emit()


func show_lines(lines: Array) -> void:
	_lines.clear()
	for value in lines:
		var line := String(value).strip_edges()
		if not line.is_empty():
			_lines.append(line)
	if _lines.is_empty():
		dialogue_closed.emit()
		return
	_line_index = 0
	_await_release = true
	label.text = _lines[0]
	panel.visible = true
	await dialogue_closed
