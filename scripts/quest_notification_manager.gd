extends Node

signal notification_started(event: Dictionary)
signal notification_finished(event: Dictionary)

const DEFAULT_DURATION := 2.4
const MAX_PANEL_WIDTH := 420.0
const SAFE_MARGIN_BOTTOM := 168.0

var _root_layer: CanvasLayer = null
var _panel: PanelContainer = null
var _headline_label: Label = null
var _body_label: Label = null
var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {}
var _active_key: String = ""
var _active_timer: SceneTreeTimer = null
var _is_showing: bool = false


func _ready() -> void:
	_build_ui()
	_connect_game_state()
	_update_layout()
	refresh()


func _exit_tree() -> void:
	if _active_timer != null:
		_active_timer = null


func show_quest_updated(title: String, objective: String) -> void:
	_enqueue_notification({
		"kind": "quest_updated",
		"key": "quest_updated:%s|%s" % [title.strip_edges(), objective.strip_edges()],
		"title": title.strip_edges(),
		"description": objective.strip_edges(),
		"accent": "blue",
		"duration": DEFAULT_DURATION
	})


func show_task_completed(title: String, description: String) -> void:
	_enqueue_notification({
		"kind": "task_completed",
		"key": "task_completed:%s|%s" % [title.strip_edges(), description.strip_edges()],
		"title": title.strip_edges(),
		"description": description.strip_edges(),
		"accent": "wood",
		"duration": DEFAULT_DURATION + 0.6
	})


func show_quest_completed(title: String, description: String) -> void:
	_enqueue_notification({
		"kind": "quest_completed",
		"key": "quest_completed:%s|%s" % [title.strip_edges(), description.strip_edges()],
		"title": title.strip_edges(),
		"description": description.strip_edges(),
		"accent": "gold",
		"duration": DEFAULT_DURATION + 1.0
	})


func refresh() -> void:
	if _is_showing:
		return
	if _is_mode_blocked():
		return
	if _queue.is_empty():
		_hide_panel()
		return
	var event: Dictionary = _queue.pop_front()
	var key: String = String(event.get("key", ""))
	if key.is_empty():
		return
	_queued_keys.erase(key)
	_show_event(event)


func _enqueue_notification(event: Dictionary) -> void:
	if _is_mode_blocked():
		return
	var key: String = String(event.get("key", ""))
	if key.is_empty():
		key = "%s:%s|%s" % [String(event.get("kind", "notification")), String(event.get("title", "")), String(event.get("description", ""))]
	if key == _active_key or _queued_keys.has(key):
		return
	_queued_keys[key] = true
	_queue.append(event)
	refresh()


func _show_event(event: Dictionary) -> void:
	_active_key = String(event.get("key", ""))
	_is_showing = true
	_apply_theme(event)
	_update_labels(event)
	_show_panel()
	notification_started.emit(event)
	var duration := float(event.get("duration", DEFAULT_DURATION))
	if _active_timer != null:
		_active_timer = null
	_active_timer = get_tree().create_timer(maxf(0.8, duration))
	await _active_timer.timeout
	_is_showing = false
	_active_key = ""
	_active_timer = null
	notification_finished.emit(event)
	_hide_panel()
	refresh()


func _build_ui() -> void:
	_root_layer = CanvasLayer.new()
	_root_layer.name = "QuestNotificationLayer"
	add_child(_root_layer)

	_panel = PanelContainer.new()
	_panel.name = "QuestNotificationPanel"
	_panel.visible = false
	# Start hidden and fully transparent so we can animate slide/fade in
	_panel.modulate = Color(1, 1, 1, 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size = Vector2(280, 86)
	_root_layer.add_child(_panel)

	var container := VBoxContainer.new()
	container.name = "NotificationContent"
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.size_flags_horizontal = Control.SIZE_FILL
	container.size_flags_vertical = Control.SIZE_FILL
	container.add_theme_constant_override("separation", 6)
	_panel.add_child(container)

	_headline_label = Label.new()
	_headline_label.name = "Headline"
	_headline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_headline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline_label.add_theme_font_size_override("font_size", 20)
	_headline_label.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(_headline_label)

	_body_label = Label.new()
	_body_label.name = "Body"
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(_body_label)


func _connect_game_state() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state == null or not game_state.has_signal("mode_changed"):
		return
	var callback := Callable(self, "_on_game_mode_changed")
	if not game_state.is_connected("mode_changed", callback):
		game_state.connect("mode_changed", callback)


func _on_game_mode_changed(_previous_mode: Variant, current_mode: Variant) -> void:
	if current_mode != GameState.GameMode.EXPLORATION:
		_hide_panel()
		return
	refresh()


func _apply_theme(event: Dictionary) -> void:
	var accent: String = String(event.get("accent", "wood")).to_lower()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.10, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.74, 0.48, 0.18, 1.0)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 10
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	if accent == "blue":
		style.border_color = Color(0.26, 0.50, 0.92, 1.0)
		style.bg_color = Color(0.10, 0.16, 0.28, 0.94)
	elif accent == "gold":
		style.border_color = Color(0.95, 0.76, 0.28, 1.0)
		style.bg_color = Color(0.25, 0.20, 0.05, 0.94)
	_panel.add_theme_stylebox_override("panel", style)


func _update_labels(event: Dictionary) -> void:
	if _headline_label != null:
		_headline_label.text = String(event.get("title", "Quest Update"))
	if _body_label != null:
		_body_label.text = String(event.get("description", ""))


func _show_panel() -> void:
	if _panel == null:
		return
	_update_layout()
	# Slide/fade in from slightly below
	var target_pos := _panel.position
	_panel.position = Vector2(target_pos.x, target_pos.y + 24.0)
	_panel.visible = true
	_panel.modulate = Color(1, 1, 1, 0.0)
	var tween := get_tree().create_tween()
	tween.tween_property(_panel, "position", target_pos, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.28)


func _hide_panel() -> void:
	if _panel == null:
		return
	# Animate slide/fade out and then hide
	if not _panel.visible:
		return
	var target_pos := Vector2(_panel.position.x, _panel.position.y + 24.0)
	var tween := get_tree().create_tween()
	tween.tween_property(_panel, "position", target_pos, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.24)
	await tween.finished
	_panel.visible = false


func _update_layout() -> void:
	if _panel == null or _root_layer == null:
		return
	var viewport_size: Vector2 = Vector2(0, 0)
	var viewport := get_viewport()
	if viewport != null:
		viewport_size = viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(420, 240)
	var width := minf(MAX_PANEL_WIDTH, viewport_size.x * 0.9)
	var height := 90.0
	var bottom_margin := SAFE_MARGIN_BOTTOM
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		bottom_margin = SAFE_MARGIN_BOTTOM + 24.0
	_panel.size = Vector2(width, height)
	_panel.position = Vector2((viewport_size.x - width) / 2.0, viewport_size.y - height - bottom_margin)


func _is_mode_blocked() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	if game_state == null or not game_state.has_method("get_mode"):
		return false
	return game_state.get_mode() != GameState.GameMode.EXPLORATION
