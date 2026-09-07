extends Node

## The one shared, nonblocking quest-presentation queue. GameState remains the
## only quest-progression owner; the existing interaction adapters remain the
## only DIALOGUE-mode owners.

signal notification_started(event: Dictionary)
signal notification_finished(event: Dictionary)

const TASK_TRIGGER_DURATION := 2.5
const TASK_COMPLETE_DURATION := 3.0
const DEFAULT_DURATION := 2.4
const MAX_PANEL_WIDTH := 460.0
const TASK_TRIGGER_HEIGHT := 96.0
const TASK_COMPLETE_HEIGHT := 88.0
const TASK_TRIGGER_PORTRAIT_SIZE := 72.0
const TASK_TRIGGER_CONTENT_SEPARATION := 10.0
const PANEL_HORIZONTAL_INSET := 32.0

var _root_layer: CanvasLayer
var _task_trigger_panel: PanelContainer
var _task_trigger_portrait: TextureRect
var _task_trigger_labels: VBoxContainer
var _task_trigger_headline: Label
var _task_trigger_body: Label
var _task_complete_panel: PanelContainer
var _task_complete_headline: Label
var _task_complete_body: Label
var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {}
var _active_key := ""
var _is_showing := false
var _presentation_generation := 0


func _ready() -> void:
	_build_ui()
	_connect_game_state()
	refresh()


func show_task_trigger(title: String, objective: String, key: String, portrait_path: String = "") -> void:
	_enqueue_notification({
		"kind": "task_trigger",
		"key": _resolved_key(key, "task_trigger", title, objective),
		"title": title.strip_edges(),
		"description": objective.strip_edges(),
		"portrait_path": portrait_path.strip_edges(),
		"accent": "blue",
		"duration": TASK_TRIGGER_DURATION,
	})


func show_quest_updated(title: String, objective: String, key: String = "") -> void:
	_enqueue_notification({
		"kind": "quest_updated",
		"key": _resolved_key(key, "quest_updated", title, objective),
		"title": title.strip_edges(),
		"description": objective.strip_edges(),
		"accent": "blue",
		"duration": DEFAULT_DURATION,
	})


func show_task_completed(title: String, description: String, key: String = "") -> void:
	_enqueue_notification({
		"kind": "task_completed",
		"key": _resolved_key(key, "task_completed", title, description),
		"title": title.strip_edges(),
		"description": description.strip_edges(),
		"accent": "wood",
		"duration": TASK_COMPLETE_DURATION,
	})


func show_quest_completed(title: String, description: String, key: String = "") -> void:
	_enqueue_notification({
		"kind": "quest_completed",
		"key": _resolved_key(key, "quest_completed", title, description),
		"title": title.strip_edges(),
		"description": description.strip_edges(),
		"accent": "gold",
		"duration": TASK_COMPLETE_DURATION,
	})


func show_system_notification(title: String, description: String, key: String = "") -> void:
	_enqueue_notification({
		"kind": "system",
		"key": _resolved_key(key, "system", title, description),
		"title": title.strip_edges(),
		"description": description.strip_edges(),
		"accent": "gold",
		"duration": DEFAULT_DURATION,
		"allow_when_blocked": true,
	})


func get_active_notification_key() -> String:
	return _active_key


func get_pending_notification_count() -> int:
	return _queue.size()


func refresh() -> void:
	if _is_showing:
		return
	if _queue.is_empty():
		_hide_all_panels_immediately()
		return
	if _is_mode_blocked() and not bool(_queue.front().get("allow_when_blocked", false)):
		return

	var event: Dictionary = _queue.pop_front()
	var key := String(event.get("key", ""))
	if key.is_empty():
		return
	_queued_keys.erase(key)
	_show_event(event, _presentation_generation)


func _enqueue_notification(event: Dictionary) -> void:
	var key := String(event.get("key", ""))
	if key.is_empty() or key == _active_key or _queued_keys.has(key):
		return
	_queued_keys[key] = true
	_queue.append(event)
	# Task completion must remain queued during real dialogue/battle dialogue.
	# It is presentation-only and will be shown once EXPLORATION resumes.
	refresh()


func _show_event(event: Dictionary, generation: int) -> void:
	if generation != _presentation_generation:
		return
	_active_key = String(event.get("key", ""))
	_is_showing = true
	await _show_event_panel(event)
	if generation != _presentation_generation:
		return
	notification_started.emit(event)

	await get_tree().create_timer(maxf(0.8, float(event.get("duration", DEFAULT_DURATION)))).timeout
	if generation != _presentation_generation:
		return

	_is_showing = false
	_active_key = ""
	notification_finished.emit(event)
	_hide_all_panels_immediately()
	refresh()


func _build_ui() -> void:
	_root_layer = CanvasLayer.new()
	_root_layer.name = "QuestNotificationLayer"
	add_child(_root_layer)

	_task_trigger_panel = PanelContainer.new()
	_task_trigger_panel.name = "TaskTriggerPanel"
	_task_trigger_panel.visible = false
	_task_trigger_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_layer.add_child(_task_trigger_panel)
	var trigger_content := HBoxContainer.new()
	trigger_content.name = "TaskTriggerContent"
	trigger_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trigger_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trigger_content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trigger_content.add_theme_constant_override("separation", int(TASK_TRIGGER_CONTENT_SEPARATION))
	_task_trigger_panel.add_child(trigger_content)

	# Keep the native image size from participating in HBox minimum-size
	# propagation. The portrait is rendered inside this fixed compact slot.
	var portrait_slot := Control.new()
	portrait_slot.name = "PortraitSlot"
	portrait_slot.custom_minimum_size = Vector2(TASK_TRIGGER_PORTRAIT_SIZE, TASK_TRIGGER_PORTRAIT_SIZE)
	portrait_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_slot.clip_contents = true
	portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trigger_content.add_child(portrait_slot)

	_task_trigger_portrait = TextureRect.new()
	_task_trigger_portrait.name = "Portrait"
	_task_trigger_portrait.visible = false
	_task_trigger_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_task_trigger_portrait.custom_minimum_size = Vector2(TASK_TRIGGER_PORTRAIT_SIZE, TASK_TRIGGER_PORTRAIT_SIZE)
	_task_trigger_portrait.size = Vector2(TASK_TRIGGER_PORTRAIT_SIZE, TASK_TRIGGER_PORTRAIT_SIZE)
	_task_trigger_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_task_trigger_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_slot.add_child(_task_trigger_portrait)

	var trigger_labels := _build_label_column("TaskTriggerLabels")
	trigger_content.add_child(trigger_labels)
	_task_trigger_labels = trigger_labels
	_task_trigger_headline = trigger_labels.get_node("Headline") as Label
	_task_trigger_body = trigger_labels.get_node("Body") as Label

	_task_complete_panel = PanelContainer.new()
	_task_complete_panel.name = "TaskCompletePanel"
	_task_complete_panel.visible = false
	_task_complete_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_layer.add_child(_task_complete_panel)
	var complete_labels := _build_label_column("TaskCompleteContent")
	_task_complete_panel.add_child(complete_labels)
	_task_complete_headline = complete_labels.get_node("Headline") as Label
	_task_complete_body = complete_labels.get_node("Body") as Label


func _build_label_column(node_name: String) -> VBoxContainer:
	var labels := VBoxContainer.new()
	labels.name = node_name
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.add_theme_constant_override("separation", 4)

	var headline := Label.new()
	headline.name = "Headline"
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.add_theme_font_size_override("font_size", 20)
	headline.add_theme_color_override("font_color", Color.WHITE)
	labels.add_child(headline)

	var body := Label.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color.WHITE)
	labels.add_child(body)
	return labels


func _connect_game_state() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state == null:
		return
	var mode_callback := Callable(self, "_on_game_mode_changed")
	if game_state.has_signal("mode_changed") and not game_state.is_connected("mode_changed", mode_callback):
		game_state.connect("mode_changed", mode_callback)
	var reset_callback := Callable(self, "_on_progression_session_reset")
	if game_state.has_signal("progression_session_reset") and not game_state.is_connected("progression_session_reset", reset_callback):
		game_state.connect("progression_session_reset", reset_callback)


func _on_game_mode_changed(_previous_mode: Variant, current_mode: Variant) -> void:
	if current_mode != GameState.GameMode.EXPLORATION:
		_hide_all_panels_immediately()
		return
	refresh()


func _on_progression_session_reset(_source: String) -> void:
	_presentation_generation += 1
	_queue.clear()
	_queued_keys.clear()
	_active_key = ""
	_is_showing = false
	_hide_all_panels_immediately()


func _show_event_panel(event: Dictionary) -> void:
	_hide_all_panels_immediately()
	var is_trigger := String(event.get("kind", "")) in ["task_trigger", "quest_updated"]
	var is_completion := String(event.get("kind", "")) in ["task_completed", "quest_completed"]
	_root_layer.layer = 2 if is_completion else 1
	var target_panel: PanelContainer
	var target_height: float
	if is_trigger:
		_apply_panel_theme(_task_trigger_panel, String(event.get("accent", "blue")))
		_task_trigger_headline.text = String(event.get("title", "New Objective"))
		_task_trigger_body.text = String(event.get("description", ""))
		_update_trigger_portrait(String(event.get("portrait_path", "")))
		_reserve_trigger_label_width()
		target_panel = _task_trigger_panel
		target_height = TASK_TRIGGER_HEIGHT
	else:
		_apply_panel_theme(_task_complete_panel, String(event.get("accent", "wood")))
		_task_complete_headline.text = String(event.get("title", "Task Complete"))
		_task_complete_body.text = String(event.get("description", ""))
		target_panel = _task_complete_panel
		target_height = TASK_COMPLETE_HEIGHT

	# Texture and text changes notify containers on the next layout frame. Center
	# only after that update so a source image's native dimensions cannot clamp
	# the notification to an oversized height.
	await get_tree().process_frame
	var layout_frames := 0
	while target_panel.get_combined_minimum_size().y > target_height and layout_frames < 4:
		await get_tree().process_frame
		layout_frames += 1
	_center_panel(target_panel, target_height, is_completion)
	target_panel.visible = true
	# The first visible layout applies Container child rects. Recenter once those
	# rects have settled so the resolved compact minimum size controls the panel.
	await get_tree().process_frame
	_center_panel(target_panel, target_height, is_completion)


func _reserve_trigger_label_width() -> void:
	if _task_trigger_labels == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0:
		viewport_size.x = MAX_PANEL_WIDTH
	var panel_width := minf(MAX_PANEL_WIDTH, viewport_size.x * 0.84)
	var portrait_width := 0.0
	if _task_trigger_portrait != null and _task_trigger_portrait.visible:
		portrait_width = TASK_TRIGGER_PORTRAIT_SIZE + TASK_TRIGGER_CONTENT_SEPARATION
	var label_width := maxf(1.0, panel_width - PANEL_HORIZONTAL_INSET - portrait_width)
	_task_trigger_labels.custom_minimum_size = Vector2(label_width, 0.0)
	_task_trigger_headline.custom_minimum_size = Vector2(label_width, 0.0)
	_task_trigger_body.custom_minimum_size = Vector2(label_width, 0.0)


func _update_trigger_portrait(portrait_path: String) -> void:
	var normalized_path := portrait_path.strip_edges()
	if normalized_path.is_empty():
		_task_trigger_portrait.texture = null
		_task_trigger_portrait.visible = false
		return
	# Isolated/headless worktrees can legitimately lack generated import data.
	# Only load when Godot reports the portrait resource is ready.
	var portrait_texture: Texture2D = null
	if ResourceLoader.exists(normalized_path, "Texture2D"):
		portrait_texture = load(normalized_path) as Texture2D
	_task_trigger_portrait.texture = portrait_texture
	_task_trigger_portrait.visible = portrait_texture != null
	_task_trigger_portrait.position = Vector2.ZERO
	_task_trigger_portrait.size = Vector2(TASK_TRIGGER_PORTRAIT_SIZE, TASK_TRIGGER_PORTRAIT_SIZE)


func _apply_panel_theme(panel: PanelContainer, accent: String) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.10, 0.94)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.74, 0.48, 0.18, 1.0)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	match accent.to_lower():
		"blue":
			style.border_color = Color(0.26, 0.50, 0.92, 1.0)
			style.bg_color = Color(0.10, 0.16, 0.28, 0.94)
		"gold":
			style.border_color = Color(0.95, 0.76, 0.28, 1.0)
			style.bg_color = Color(0.25, 0.20, 0.05, 0.94)
	panel.add_theme_stylebox_override("panel", style)


func _center_panel(panel: Control, height: float, top_center: bool = false) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(460.0, 300.0)
	var width := minf(MAX_PANEL_WIDTH, viewport_size.x * 0.84)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP if top_center else Control.PRESET_TOP_LEFT)
	panel.size = Vector2(width, height)
	panel.position = Vector2((viewport_size.x - width) * 0.5, 12.0 if top_center else (viewport_size.y - height) * 0.5)


func _hide_all_panels_immediately() -> void:
	for panel in [_task_trigger_panel, _task_complete_panel]:
		if panel != null:
			panel.visible = false


func _is_mode_blocked() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state != null and game_state.has_method("get_mode") and game_state.get_mode() != GameState.GameMode.EXPLORATION


func _resolved_key(key: String, kind: String, title: String, description: String) -> String:
	var trimmed := key.strip_edges()
	if not trimmed.is_empty():
		return trimmed
	return "%s:%s|%s" % [kind, title.strip_edges(), description.strip_edges()]
