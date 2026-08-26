extends Node

const QUEST_UI_SCRIPT := preload("res://world/QuestUI.gd")
const TEACHER_INTERACTION_SCRIPT := preload("res://scripts/teacher_task_interaction.gd")
const BANDIT_ADAPTER_SCRIPT := preload("res://scripts/task_dialogue_adapter.gd")

var _failures: Array[String] = []


class BanditDialogueStub extends Node:
    signal release_requested

    var calls := 0

    func show_completed_with_dialogue() -> void:
        calls += 1
        await release_requested


class TeacherDialogueStub extends Node:
    signal release_requested

    var calls := 0

    func play_teacher_dialogue() -> void:
        calls += 1
        GameState.current_task_index += 1
        await release_requested


func _ready() -> void:
    call_deferred("_run")


func _run() -> void:
    var original_mode := GameState.get_mode()
    var original_task_index := GameState.current_task_index
    var manager := get_tree().root.get_node_or_null("QuestNotificationManager")
    _expect(manager != null, "QuestNotificationManager autoload must be available.")

    if manager != null:
        _exercise_notification_contract(manager)

    await _exercise_dialogue_contract()
    _exercise_scene_contracts(manager)

    GameState.set_mode(original_mode)
    GameState.current_task_index = original_task_index

    if _failures.is_empty():
        print("quest_presentation_dialogue_regression_test: PASS")
        get_tree().quit(0)
        return

    for failure in _failures:
        push_error(failure)
    get_tree().quit(1)


func _exercise_notification_contract(manager: Node) -> void:
    _expect(
        manager.has_method("show_task_trigger"),
        "Task Trigger API must exist for the approved New Objective presentation."
    )
    _expect(
        manager.has_method("get_active_notification_key"),
        "Notification manager must expose the active stable key for regression coverage."
    )
    _expect(
        manager.has_method("get_pending_notification_count"),
        "Notification manager must expose the queued count for regression coverage."
    )

    if not (
        manager.has_method("show_task_trigger")
        and manager.has_method("get_active_notification_key")
        and manager.has_method("get_pending_notification_count")
    ):
        return

    var notification_layer := manager.get_node_or_null("QuestNotificationLayer")
    var trigger_panel := manager.get_node_or_null("QuestNotificationLayer/TaskTriggerPanel") as Control
    var complete_panel := manager.get_node_or_null("QuestNotificationLayer/TaskCompletePanel") as Control
    _expect(notification_layer != null, "The existing manager owns the only notification CanvasLayer.")
    _expect(trigger_panel != null and complete_panel != null, "Task Trigger and Task Complete use separate panel instances.")
    _expect(
        trigger_panel != null and complete_panel != null
            and trigger_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE
            and complete_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
        "Nonblocking notification panels must ignore pointer input."
    )

    GameState.set_mode(GameState.GameMode.EXPLORATION)
    var task_before := GameState.current_task_index
    manager.call(
        "show_task_trigger",
        "Task 1",
        "Talk to the Teacher",
        "quest:main:task:0:arrival",
        "res://Images/NPC.jpg"
    )
    _expect(
        GameState.get_mode() == GameState.GameMode.EXPLORATION,
        "Task Trigger notification must not enter DIALOGUE mode."
    )
    _expect(
        GameState.current_task_index == task_before,
        "Task Trigger notification must not advance quest state."
    )
    _expect(
        String(manager.call("get_active_notification_key")) == "quest:main:task:0:arrival",
        "Task Trigger must become the active stable-key notification."
    )

    manager.call(
        "show_task_trigger",
        "Task 1",
        "Talk to the Teacher",
        "quest:main:task:0:arrival",
        "res://Images/NPC.jpg"
    )
    _expect(
        int(manager.call("get_pending_notification_count")) == 0,
        "An active Task Trigger duplicate must not be queued."
    )

    GameState.progression_session_reset.emit("quest_presentation_test_before_queue")
    await get_tree().process_frame
    _expect(
        String(manager.call("get_active_notification_key")) == "",
        "A progression reset must clear an active quest notification."
    )

    GameState.set_mode(GameState.GameMode.DIALOGUE)
    manager.call(
        "show_task_completed",
        "Task 3 Complete",
        "Battle completed",
        "quest:main:task:2:complete"
    )
    _expect(
        GameState.get_mode() == GameState.GameMode.DIALOGUE,
        "Task Complete notification must not change the active dialogue mode."
    )
    _expect(
        int(manager.call("get_pending_notification_count")) == 1,
        "Task Complete must queue while dialogue is active."
    )

    manager.call(
        "show_task_completed",
        "Task 3 Complete",
        "Battle completed",
        "quest:main:task:2:complete"
    )
    _expect(
        int(manager.call("get_pending_notification_count")) == 1,
        "A queued Task Complete duplicate must not be queued twice."
    )

    GameState.set_mode(GameState.GameMode.EXPLORATION)
    await get_tree().process_frame
    _expect(
        String(manager.call("get_active_notification_key")) == "quest:main:task:2:complete",
        "Queued Task Complete must appear after EXPLORATION resumes."
    )

    GameState.set_mode(GameState.GameMode.DIALOGUE)
    manager.call(
        "show_task_completed",
        "Task 3 Complete",
        "Battle completed",
        "quest:main:task:2:stale"
    )
    GameState.progression_session_reset.emit("quest_presentation_test")
    GameState.set_mode(GameState.GameMode.EXPLORATION)
    await get_tree().process_frame
    _expect(
        int(manager.call("get_pending_notification_count")) == 0,
        "A progression reset must discard stale queued notifications."
    )


func _exercise_dialogue_contract() -> void:
    var canvas_layer := CanvasLayer.new()
    canvas_layer.name = "DialogueTestCanvas"

    var dialogue_panel := PanelContainer.new()
    dialogue_panel.name = "DialoguePanel"
    dialogue_panel.visible = false
    var dialogue_label := Label.new()
    dialogue_label.name = "DialogueLabel"
    dialogue_panel.add_child(dialogue_label)
    canvas_layer.add_child(dialogue_panel)

    var quest_ui := QUEST_UI_SCRIPT.new() as Panel
    quest_ui.name = "Panel"
    canvas_layer.add_child(quest_ui)
    get_tree().root.add_child(canvas_layer)
    await get_tree().process_frame

    _expect(
        quest_ui.has_method("begin_dialogue"),
        "QuestUI must expose one deliberate dialogue session API."
    )
    _expect(
        quest_ui.has_method("get_dialogue_line_index"),
        "QuestUI must expose dialogue line state for regression coverage."
    )

    if quest_ui.has_method("begin_dialogue") and quest_ui.has_method("get_dialogue_line_index"):
        # Reproduce the real interaction ordering: the opening press begins an
        # interaction, entering DIALOGUE clears that held mobile state, then
        # line one is rendered. The original press cannot consume line one.
        GameState.set_mode(GameState.GameMode.EXPLORATION)
        InputManager.set_mobile_interact_pressed(true)
        GameState.set_mode(GameState.GameMode.DIALOGUE)
        quest_ui.call("begin_dialogue", ["Line 1", "Line 2"])
        await get_tree().process_frame
        _expect(dialogue_panel.visible, "Opening dialogue must show the one shared DialoguePanel.")
        _expect(
            String(dialogue_label.text) == "Line 1",
            "The opening Interact action must render line 1."
        )
        _expect(
            int(quest_ui.call("get_dialogue_line_index")) == 0,
            "The opening Interact action must not consume line 1."
        )

        await get_tree().process_frame
        await get_tree().process_frame
        _expect(
            int(quest_ui.call("get_dialogue_line_index")) == 0,
            "Held Interact must not skip the opening dialogue line."
        )

        InputManager.set_mobile_interact_pressed(false)
        await get_tree().process_frame
        InputManager.set_mobile_interact_pressed(true)
        await get_tree().process_frame
        _expect(
            int(quest_ui.call("get_dialogue_line_index")) == 1,
            "One deliberate Interact edge must advance exactly one dialogue line."
        )

        await get_tree().process_frame
        _expect(
            int(quest_ui.call("get_dialogue_line_index")) == 1,
            "A held advancing press must not skip a second dialogue line."
        )

        InputManager.set_mobile_interact_pressed(false)
        await get_tree().process_frame
        InputManager.set_mobile_interact_pressed(true)
        await get_tree().process_frame
        _expect(
            not dialogue_panel.visible,
            "The final deliberate Interact press must close DialoguePanel once."
        )
        InputManager.set_mobile_interact_pressed(false)

        await _exercise_adapter_guards(canvas_layer)

    canvas_layer.queue_free()
    await get_tree().process_frame
    InputManager.clear_mobile_state()


func _exercise_adapter_guards(canvas_layer: CanvasLayer) -> void:
    var teacher_ui := TeacherDialogueStub.new()
    teacher_ui.name = "TeacherQuestUI"
    canvas_layer.add_child(teacher_ui)

    var teacher := TEACHER_INTERACTION_SCRIPT.new()
    teacher.quest_ui_path = NodePath("../TeacherQuestUI")
    canvas_layer.add_child(teacher)
    GameState.current_task_index = 1
    GameState.set_mode(GameState.GameMode.EXPLORATION)
    await get_tree().process_frame

    _expect(teacher.interact(), "Teacher interaction must start once while exploring.")
    _expect(
        not teacher.interact(),
        "Teacher interaction must reject a second input while dialogue is active."
    )
    teacher_ui.release_requested.emit()
    await get_tree().process_frame
    _expect(
        GameState.current_task_index == 2,
        "Teacher dialogue completion must advance the quest exactly once."
    )
    _expect(
        teacher_ui.calls == 1,
        "Teacher adapter must invoke its existing continuation exactly once."
    )

    var bandit_ui := BanditDialogueStub.new()
    bandit_ui.name = "BanditQuestUI"
    canvas_layer.add_child(bandit_ui)

    var bandit := BANDIT_ADAPTER_SCRIPT.new()
    bandit.quest_ui_path = NodePath("../BanditQuestUI")
    bandit.require_task_index = 2
    canvas_layer.add_child(bandit)
    GameState.current_task_index = 2
    GameState.set_mode(GameState.GameMode.EXPLORATION)
    await get_tree().process_frame

    _expect(bandit.interact(), "Bandit dialogue must start once while exploring.")
    _expect(
        not bandit.interact(),
        "Bandit dialogue must reject a second activation while its session is active."
    )
    bandit_ui.release_requested.emit()
    await get_tree().process_frame
    _expect(
        bandit_ui.calls == 1,
        "Bandit dialogue adapter must invoke the existing battle continuation once."
    )

    teacher.queue_free()
    teacher_ui.queue_free()
    bandit.queue_free()
    bandit_ui.queue_free()


func _exercise_scene_contracts(_manager: Node) -> void:
    var oak_leaf_source := _read_source("res://scenes/oak_leaf_village.tscn")
    var greeting_source := _read_source("res://NPC/Npc/old_adult_women_Dialog.gd")
    _expect(
        oak_leaf_source.count("[node name=\"DialoguePanel\" type=\"PanelContainer\" parent=\"CanvasLayer\"]") == 1,
        "Oak Leaf must contain exactly one shared DialoguePanel."
    )
    _expect(
        not oak_leaf_source.contains("TeacherTriggerPortrait"),
        "The old top-right Teacher portrait path must be removed from Oak Leaf."
    )
    _expect(
        oak_leaf_source.contains("[node name=\"QuestText\" type=\"Label\" parent=\"CanvasLayer/Panel\"")
            and oak_leaf_source.contains("[node name=\"DialoguePanel\" type=\"PanelContainer\" parent=\"CanvasLayer\"]"),
        "The legacy QuestUI bridge and one DialoguePanel must remain separate."
    )

    var hud_source := _read_source("res://ui/game_hud.tscn")
    _expect(
        hud_source.contains("CurrentQuest") or hud_source.contains("Quest"),
        "The existing GameHUD Current Quest presentation remains the persistent objective owner."
    )
    var mobile_source := _read_source("res://ui/mobile_controls.tscn")
    _expect(
        mobile_source.contains("ActionButton") and mobile_source.contains("MovementPanel"),
        "The existing D-pad and Interact control nodes remain present."
    )
    _expect(
        greeting_source.contains("func show_dialogue_timed()")
            and greeting_source.contains("await quest_ui.begin_dialogue([greeting_message])"),
        "Existing NPC greeting wiring must retain its public entry point and use the shared deliberate-input dialogue flow."
    )


func _read_source(path: String) -> String:
    return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)
