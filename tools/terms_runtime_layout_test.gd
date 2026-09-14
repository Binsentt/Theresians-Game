extends Node

const TERMS_GATE_SCRIPT := preload("res://scripts/terms_gate.gd")
const VIEWPORTS := [Vector2i(1134, 509), Vector2i(1215, 545), Vector2i(1280, 720), Vector2i(1920, 1080)]
const RESULT_PATH := "res://tools/terms_runtime_layout_test_result.json"

var _results: Array[Dictionary] = []
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for requested_size: Vector2i in VIEWPORTS:
		var test_viewport := SubViewport.new()
		test_viewport.size = requested_size
		test_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_tree().root.add_child(test_viewport)
		await _settle_window()
		_clear_acceptance()
		var gate := TERMS_GATE_SCRIPT.new() as Control
		test_viewport.add_child(gate)
		await get_tree().process_frame
		await get_tree().process_frame
		await _check_gate(requested_size, test_viewport.size, gate)
		gate.queue_free()
		test_viewport.queue_free()
		await get_tree().process_frame

	var output := {
		"pass": _failures.is_empty(),
		"failures": _failures,
		"results": _results,
	}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(output))
		file.close()
	print("TERMS_RUNTIME_LAYOUT " + JSON.stringify(output))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _settle_window() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _check_gate(requested_size: Vector2i, actual_size: Vector2, gate: Control) -> void:
	var panel := gate.get_node_or_null("Panel") as Control
	var scroll := gate.get_node_or_null("Panel/Margin/Content/TermsScroll") as ScrollContainer
	var body := gate.get_node_or_null("Panel/Margin/Content/TermsScroll/TermsBody") as RichTextLabel
	var checkbox := gate.get_node_or_null("Panel/Margin/Content/AgreementRow/AgreementCheckBox") as CheckBox
	var row := gate.get_node_or_null("Panel/Margin/Content/AgreementRow") as Control
	var actions := gate.get_node_or_null("Panel/Margin/Content/Actions") as Control
	var continue_button := gate.get_node_or_null("Panel/Margin/Content/Actions/ContinueButton") as Button
	var cancel_button := gate.get_node_or_null("Panel/Margin/Content/Actions/CancelButton") as Button
	var panel_rect := panel.get_global_rect() if panel != null else Rect2()
	var scroll_rect := scroll.get_global_rect() if scroll != null else Rect2()
	var row_rect := row.get_global_rect() if row != null else Rect2()
	var actions_rect := actions.get_global_rect() if actions != null else Rect2()
	var viewport_rect := Rect2(Vector2.ZERO, actual_size)
	var scrollbar := scroll.get_v_scroll_bar() if scroll != null else null
	var content_height := body.get_content_height() if body != null else 0
	var needs_scroll := content_height > scroll_rect.size.y + 1.0
	var scrollable := not needs_scroll or (scrollbar != null and scrollbar.max_value > 0.0)
	var entry := {
		"requested_viewport": _rect_dict(Rect2(Vector2.ZERO, requested_size)),
		"actual_viewport": _rect_dict(viewport_rect),
		"panel": _rect_dict(panel_rect),
		"scroll": _rect_dict(scroll_rect),
		"agreement_row": _rect_dict(row_rect),
		"actions": _rect_dict(actions_rect),
		"checkbox": _rect_dict(checkbox.get_global_rect()) if checkbox != null else {},
		"continue": _rect_dict(continue_button.get_global_rect()) if continue_button != null else {},
		"cancel": _rect_dict(cancel_button.get_global_rect()) if cancel_button != null else {},
		"content_height": content_height,
		"needs_scroll": needs_scroll,
		"scroll_max": scrollbar.max_value if scrollbar != null else -1.0,
		"scrollable": scrollable,
	}
	_results.append(entry)

	_require(panel != null, "panel exists", requested_size)
	_require(scroll != null and body != null, "scroll body exists", requested_size)
	_require(checkbox != null and continue_button != null and cancel_button != null, "footer controls exist", requested_size)
	if panel == null or scroll == null or checkbox == null or row == null or actions == null or continue_button == null or cancel_button == null:
		return
	_require(panel_rect.position.x >= -1.0 and panel_rect.position.y >= -1.0, "panel starts inside viewport", requested_size)
	_require(panel_rect.end.x <= viewport_rect.end.x + 1.0 and panel_rect.end.y <= viewport_rect.end.y + 1.0, "panel ends inside viewport", requested_size)
	_require(panel_rect.size.y <= actual_size.y * 0.88 + 1.0, "panel height is bounded", requested_size)
	_require(scroll_rect.end.y <= row_rect.position.y + 1.0, "scroll does not overlap footer", requested_size)
	_require(row_rect.end.y <= viewport_rect.end.y + 1.0, "checkbox row is visible", requested_size)
	_require(actions_rect.end.y <= viewport_rect.end.y + 1.0, "actions are visible", requested_size)
	_require(checkbox.get_global_rect().size.x > 0.0 and checkbox.get_global_rect().size.y > 0.0, "checkbox is laid out", requested_size)
	_require(continue_button.get_global_rect().end.y <= viewport_rect.end.y + 1.0, "continue button is visible", requested_size)
	_require(cancel_button.get_global_rect().end.y <= viewport_rect.end.y + 1.0, "cancel button is visible", requested_size)
	_require(scrollable, "terms body is scrollable", requested_size)
	if needs_scroll and scrollbar != null:
		var initial_scroll := scroll.scroll_vertical
		scroll.scroll_vertical = int(scrollbar.max_value)
		await get_tree().process_frame
		_require(scroll.scroll_vertical > initial_scroll, "terms scroll responds", requested_size)
		scroll.scroll_vertical = 0
	_require(not checkbox.button_pressed, "checkbox starts unchecked", requested_size)
	_require(continue_button.disabled, "continue starts disabled", requested_size)
	checkbox.button_pressed = true
	await get_tree().process_frame
	_require(not continue_button.disabled, "checking enables continue", requested_size)
	checkbox.button_pressed = false
	await get_tree().process_frame
	_require(continue_button.disabled, "unchecking disables continue", requested_size)


func _require(condition: bool, label: String, requested_size: Vector2i) -> void:
	if not condition:
		_failures.append("%s @ %sx%s" % [label, requested_size.x, requested_size.y])


func _clear_acceptance() -> void:
	var path := ProjectSettings.globalize_path("user://terms_app_acceptance.json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _rect_dict(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y, "end_x": rect.end.x, "end_y": rect.end.y}
