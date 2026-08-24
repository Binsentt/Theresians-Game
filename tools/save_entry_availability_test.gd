extends Node

const SAVE_ENTRY_SCENE := preload("res://ui/save_entry.tscn")

var _failures: Array[String] = []
var _load_requested := false
var _delete_requested := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var entry := SAVE_ENTRY_SCENE.instantiate() as Control
	add_child(entry)
	entry.save_selected.connect(func(_path: String) -> void: _load_requested = true)
	entry.save_delete_requested.connect(func(_path: String) -> void: _delete_requested = true)
	entry.setup({
		"save_path": "user://saves/invalid-local-save.json",
		"loadable": false,
		"save_error": "This save file is malformed or unavailable.",
	})
	await get_tree().process_frame

	var load_button := entry.get_node("MarginContainer/Content/Actions/LoadButton") as Button
	var delete_button := entry.get_node("MarginContainer/Content/Actions/DeleteButton") as Button
	var availability_label := entry.get_node("MarginContainer/Content/Details/AvailabilityLabel") as Label
	_assert(load_button.disabled, "unavailable saves disable Load")
	_assert(not delete_button.disabled, "unavailable saves retain Delete")
	_assert(availability_label.visible and availability_label.text.contains("malformed"), "unavailable saves show a truthful message")
	load_button.pressed.emit()
	delete_button.pressed.emit()
	_assert(not _load_requested, "disabled Load never emits a request")
	_assert(_delete_requested, "Delete still targets the selected unavailable local save")
	entry.queue_free()

	if _failures.is_empty():
		print("SAVE_ENTRY_AVAILABILITY_TEST: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SAVE_ENTRY_AVAILABILITY_TEST: FAIL")
	get_tree().quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
