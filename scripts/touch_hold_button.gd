extends Button

class_name TouchHoldButton

signal hold_changed(is_held: bool)

var _touch_ids: Dictionary = {}
var _mouse_held: bool = false
var _is_held: bool = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			_touch_ids[event.index] = true
		else:
			_touch_ids.erase(event.index)
		_refresh_held_state()
		accept_event()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_held = event.pressed
		_refresh_held_state()
		accept_event()


func force_release() -> void:
	_touch_ids.clear()
	_mouse_held = false
	_is_held = false
	hold_changed.emit(false)


func _refresh_held_state() -> void:
	var next_held: bool = _mouse_held or not _touch_ids.is_empty()
	if _is_held == next_held:
		return

	_is_held = next_held
	hold_changed.emit(_is_held)
