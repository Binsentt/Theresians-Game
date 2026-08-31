extends Node

const OAKLEAF_SCENE := "res://scenes/oak_leaf_village.tscn"
const BANDIT_ADAPTER_PATH := "Bandits/BanditTaskTrigger/TaskDialogAdapter"
const BANDIT_TRIGGER_PATH := "Bandits/BanditTaskTrigger"

var _failures: Array[String] = []
var _battle_transition_count := 0


class QuestionProviderStub extends Node:
	signal questions_loaded(count: int)

	const QUESTION := {
		"question": "1 + 1 = ?",
		"choices": ["2", "1", "3", "4"],
		"correct": 0,
		"topic_id": "basic_addition",
	}

	func load_questions() -> void:
		questions_loaded.emit(1)

	func get_questions() -> Array[Dictionary]:
		return [QUESTION.duplicate(true)]

	func get_question() -> Dictionary:
		return QUESTION.duplicate(true)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_promote_to_root()
	_replace_question_provider_with_stub()
	GameState.current_task_index = 2
	GameState.playtime_authorized = true
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	InputManager.unlock_input("door_transition")

	_assert(await _load_scene(OAKLEAF_SCENE), "Oakleaf loads in project context")
	await _wait_frames(4)

	var oakleaf := get_tree().current_scene
	var trigger := oakleaf.get_node_or_null(BANDIT_TRIGGER_PATH) as Area2D if oakleaf != null else null
	var adapter := oakleaf.get_node_or_null(BANDIT_ADAPTER_PATH) if oakleaf != null else null
	var panel := oakleaf.get_node_or_null("CanvasLayer/Panel") if oakleaf != null else null
	var player := get_tree().get_first_node_in_group("player_character") as Node2D
	_assert(trigger != null, "Oakleaf exposes the First Bandit interaction area")
	_assert(adapter != null, "Oakleaf exposes the First Bandit TaskDialogAdapter")
	_assert(panel != null, "Oakleaf exposes the canonical CanvasLayer/Panel dialogue host")
	_assert(player != null, "Oakleaf project context creates the player")
	if trigger == null or adapter == null or panel == null or player == null:
		_finish()
		return

	player.global_position = trigger.global_position
	trigger.call("_on_body_entered", player)

	var resolved_panel := adapter.get_node_or_null(adapter.quest_ui_path)
	_assert(resolved_panel == panel, "First Bandit TaskDialogAdapter resolves the canonical CanvasLayer/Panel")
	_assert(adapter.can_interact(), "TaskDialogAdapter can interact at the active First Bandit task")
	_assert(trigger.can_interact(), "Player reaching the First Bandit interaction area enables Interact")
	if not _failures.is_empty():
		_finish()
		return

	GameState.battle_started.connect(_on_battle_started)
	var dialogue_label := panel.get_node_or_null("DialogueText") as CanvasItem
	_assert(trigger.interact(), "First Bandit interaction is accepted once")
	await _wait_frames(2)
	_assert(dialogue_label != null and dialogue_label.visible, "First Bandit dialogue opens through the existing dialogue panel")
	_assert(not trigger.interact(), "A duplicate interaction is rejected while First Bandit dialogue is active")
	_assert(await _wait_for_battle_transition(6.0), "The final First Bandit dialogue close starts its existing battle")
	_assert(_battle_transition_count == 1, "First Bandit dialogue creates exactly one battle transition")
	await _wait_frames(4)
	_assert(_battle_transition_count == 1, "Duplicate interaction cannot create a second battle transition")

	var scope := GameState.get_encounter_question_scope()
	_assert(String(scope.get("grade", "")) == "Grade 1", "First Bandit keeps Grade 1 scope")
	_assert(String(scope.get("difficulty", "")) == "Easy", "First Bandit keeps Easy scope")
	_assert(String(scope.get("topic_id", "")) == "basic_addition", "First Bandit keeps basic_addition scope")
	_finish()


func _promote_to_root() -> void:
	var tree := get_tree()
	var harness := get_parent()
	if tree != null and harness != null:
		harness.remove_child(self)
		tree.root.add_child(self)


func _replace_question_provider_with_stub() -> void:
	var provider := get_node_or_null("/root/QuestionProvider")
	if provider != null:
		get_tree().root.remove_child(provider)
		provider.queue_free()
	var stub := QuestionProviderStub.new()
	stub.name = "QuestionProvider"
	get_tree().root.add_child(stub)


func _load_scene(path: String) -> bool:
	if get_tree().change_scene_to_file(path) != OK:
		return false
	for _index in 240:
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _wait_for_battle_transition(timeout_seconds: float) -> bool:
	var timeout := get_tree().create_timer(timeout_seconds)
	while timeout.time_left > 0.0:
		if _battle_transition_count > 0:
			return true
		await get_tree().process_frame
	return _battle_transition_count > 0


func _wait_frames(frame_count: int) -> void:
	for _index in frame_count:
		await get_tree().process_frame


func _on_battle_started(_battle: Node) -> void:
	_battle_transition_count += 1


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FIRST_BANDIT_INTERACTION_PROJECT_CONTEXT_TEST PASSED")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FIRST_BANDIT_INTERACTION_PROJECT_CONTEXT_TEST FAILED")
	get_tree().quit(1)
