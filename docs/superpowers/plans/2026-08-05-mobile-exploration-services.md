# Mobile Exploration Services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a touch-only exploration layer with intentional interactions, immediate persistent Teacher House Task 1 progress, carved-wood quest notifications, battle-only health UI, and a JSON question-provider boundary.

**Architecture:** `GameState` owns controlled gameplay-mode transitions and task persistence. `InputManager`, `InteractionManager`, and `QuestNotificationManager` respectively own touch state, nearest-target selection, and queued feedback. Existing NPC, quest, battle, and door scripts are adapted only at their boundaries; battle scenes and automatic doors retain their behavior.

**Tech Stack:** Godot 4.6, typed GDScript, `.tscn` Control scenes, ProjectSettings AutoLoads, existing JSON data, and the bundled Godot executable.

---

## Guardrails

- The project has extensive user-owned uncommitted changes. Stage only files named by the active task, inspect the staged diff, and never reset, clean, or stage unrelated paths.
- The recovery branch is `backup/pre-mobile-exploration-services-20260805`.
- Each phase must finish with a parseable project, its named test passing, and a focused commit before the next phase starts.
- The current and only runtime `res://assets/hearts.png` reference is `player/life.tscn`; `ui/battle_life_display.tscn` instantiates it. The existing `res://assets/hearth.png` is therefore the battle-safe replacement.

## File map

| Unit | Files |
| --- | --- |
| Flow and saves | `scripts/game_state.gd`, `project.godot`, `tools/mobile_exploration_services_test.gd` |
| Touch controls | `scripts/touch_hold_button.gd`, `scripts/input_manager.gd`, `scripts/mobile_controls.gd`, `ui/mobile_controls.tscn`, `project.godot` |
| Interaction | `scripts/interactable_area.gd`, `scripts/interaction_manager.gd`, `project.godot` |
| Teacher task | `world/task_progress_trigger.gd`, `scripts/teacher_task_interaction.gd`, `world/QuestUI.gd`, `scenes/oak_leaf_village.tscn`, `interiors/teacher_house.tscn` |
| Quest UI | `scripts/quest_notification_manager.gd`, `ui/quest_notification_manager.tscn`, `project.godot` |
| Health UI | `scripts/gameplay_scene.gd`, `scripts/game_hud.gd`, `ui/game_hud.tscn`, `player/life.tscn` |
| Question source | `scripts/question_provider.gd`, `Battle/Battle-Enemy/QuizManager.gd`, `project.godot` |
| Regression | `NPC/Npc/old_adult_women_Dialog.gd`, `tools/scene_smoke_test.gd`, `tools/validate_theresian_scene_integrity.ps1` |

## Shared verification commands

```powershell
& '.\tools\Godot_v4.6.1-stable_win64.exe' --headless --path . --editor --quit
& '.\tools\Godot_v4.6.1-stable_win64.exe' --headless --path . --script res://tools/mobile_exploration_services_test.gd
& '.\tools\Godot_v4.6.1-stable_win64.exe' --headless --path . --script res://tools/scene_smoke_test.gd
& '.\tools\validate_theresian_scene_integrity.ps1'
```

Headless outcomes are reported as **Headless validated**. Desktop calls or programmatic `InputManager` calls are reported as **Desktop logic validated using simulated touch/input**. Multi-touch on real hardware, Android safe areas, and a complete mobile playthrough remain **Android device testing required** until a device or emulator is connected.

### Task 1: Add controlled game modes and backward-compatible task persistence

**Files:**
- Create: `tools/mobile_exploration_services_test.gd`
- Modify: `scripts/game_state.gd`

- [ ] **Step 1: Write a failing foundation test.**

Create a `SceneTree` test that instantiates `res://scripts/game_state.gd`, calls `set_mode(EXPLORATION)`, `push_mode(DIALOGUE)`, `push_mode(CUTSCENE)`, then two `pop_mode()` calls. Assert the exact restored sequence `CUTSCENE → DIALOGUE → EXPLORATION`. Call `apply_save_data({"save_version": 5, "current_quest": ""})` and assert `current_task_index == 0`.

- [ ] **Step 2: Run the test before implementation.**

Run the second shared verification command. Expected: parser failure because the mode API and `apply_save_data()` are not yet defined.

- [ ] **Step 3: Implement the foundation API.**

Add this public contract in `scripts/game_state.gd`:

```gdscript
enum GameMode { EXPLORATION, DIALOGUE, CUTSCENE, BATTLE, MENU }
signal mode_changed(previous_mode: GameMode, current_mode: GameMode)
signal task_state_changed(previous_index: int, current_index: int, event: Dictionary)
signal progression_session_reset(source: String)
var _mode_stack: Array[GameMode] = [GameMode.MENU]

func get_mode() -> GameMode:
	return _mode_stack.back()

func set_mode(mode: GameMode) -> void:
	var previous := get_mode()
	_mode_stack = [mode]
	if previous != mode:
		mode_changed.emit(previous, mode)

func push_mode(mode: GameMode) -> void:
	var previous := get_mode()
	if previous != mode:
		_mode_stack.append(mode)
		mode_changed.emit(previous, mode)

func pop_mode() -> GameMode:
	if _mode_stack.size() > 1:
		var previous := _mode_stack.pop_back()
		mode_changed.emit(previous, get_mode())
	return get_mode()
```

Set `SAVE_VERSION` to `6`. Extract the save dictionary into `build_save_data()`, adding `"current_task_index": current_task_index`. Make `load_save()` parse then call `apply_save_data(data)`, where `current_task_index = clampi(int(data.get("current_task_index", 0)), 0, tasks.size())`; emit `progression_session_reset("load")` after applying it. Add `advance_task_and_save(event: Dictionary) -> Dictionary`: validate remaining tasks, increment the index, call `save_game()`, then emit `task_state_changed(previous, current_task_index, event)`. Reset the task index and mode stack in `start_new_game()`, then emit `progression_session_reset("new_game")`.

- [ ] **Step 4: Verify foundation behavior.**

Run the first and second shared verification commands. Expected: `MOBILE_EXPLORATION_SERVICES_TEST PASSED: foundation` and no new `game_state.gd` parser error.

- [ ] **Step 5: Commit the phase.**

```powershell
git add -- scripts/game_state.gd tools/mobile_exploration_services_test.gd
git diff --cached --check
git commit -m "feat: add game flow and task persistence"
```

### Task 2: Convert exploration controls to multi-touch-safe touch input

**Files:**
- Create: `scripts/touch_hold_button.gd`
- Modify: `project.godot`, `scripts/input_manager.gd`, `scripts/mobile_controls.gd`, `ui/mobile_controls.tscn`, `tools/mobile_exploration_services_test.gd`

- [ ] **Step 1: Add a failing simulated-touch test.**

Extend the shared test with `set_mobile_direction("right", true)` and `set_mobile_direction("up", true)`, wait one process frame, assert a non-zero movement vector, then call `clear_mobile_state()` and assert `Vector2.ZERO`. Also assert `InputManager.has_method("consume_interact_just_pressed")`. Do not use `Input.action_press()`.

- [ ] **Step 2: Confirm the test fails against the keyboard-dependent implementation.**

Run the second shared verification command. Expected: the new test exposes `InputManager._process()` still reading `Input.get_vector()` and keyboard interaction actions.

- [ ] **Step 3: Implement touch holds and mobile-only routing.**

Create `scripts/touch_hold_button.gd`:

```gdscript
extends Button
class_name TouchHoldButton

signal hold_changed(is_held: bool)
var _touch_ids: Dictionary[int, bool] = {}
var _mouse_held := false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_ids[event.index] = true
		else:
			_touch_ids.erase(event.index)
		_emit_hold()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_held = event.pressed
		_emit_hold()
		accept_event()

func force_release() -> void:
	_touch_ids.clear()
	_mouse_held = false
	_emit_hold()

func _emit_hold() -> void:
	hold_changed.emit(_mouse_held or not _touch_ids.is_empty())
```

In `InputManager`, compute movement only from `_get_mobile_vector()`, retain the existing input-lock branch, and add `consume_interact_just_pressed()` that returns and clears the edge flag. Clear all held states when `GameState.mode_changed` leaves `EXPLORATION`. In `mobile_controls.gd`, connect every `TouchHoldButton.hold_changed` to the existing direction/interact setters; show the root only in exploration, keep the action control hidden and force-released until the manager phase adds target availability, and force-release all buttons before hiding.

In `ui/mobile_controls.tscn`, attach `TouchHoldButton` to the four arrows and Interact control; use `▲`, `◀`, `▶`, and `▼`; use brown wood StyleBoxes; set directional targets to at least `76 x 76`; make Interact circular at `112 x 112`; preserve lower-corner anchors; reserve at least `190` bottom pixels at center for notifications. Remove only custom gameplay actions `up`, `down`, `left`, `right`, and `interact` from `project.godot`; retain engine UI actions and text/menu behavior.

- [ ] **Step 4: Verify input and exploration scene loading.**

Run the second and third shared verification commands. Expected: the touch test passes and exploration scenes load without a missing script error.

- [ ] **Step 5: Commit the touch phase.**

```powershell
git add -- project.godot scripts/touch_hold_button.gd scripts/input_manager.gd scripts/mobile_controls.gd ui/mobile_controls.tscn tools/mobile_exploration_services_test.gd
git diff --cached --check
git commit -m "feat: make exploration controls touch only"
```

### Task 3: Add deterministic intentional interaction services

**Files:**
- Create: `scripts/interactable_area.gd`, `scripts/interaction_manager.gd`
- Modify: `project.godot`, `scripts/mobile_controls.gd`, `tools/mobile_exploration_services_test.gd`

- [ ] **Step 1: Add failing selection and single-activation tests.**

Create two fake interactables: a farther target with priority `10`, and a nearer target with priority `0`. Assert priority wins. Create two priority-`0` targets at different distances and assert the nearer wins. For equal distance/priority assert the smaller registration ordinal wins. Assert `request_interaction()` calls the selected fake exactly once until `InputManager` receives a release.

- [ ] **Step 2: Run the suite before the manager exists.**

Run the second shared verification command. Expected: missing `InteractableArea` and `InteractionManager` symbols.

- [ ] **Step 3: Create the component and central manager.**

`InteractableArea` extends `Area2D`, exports `interaction_target_path`, `interaction_method = &"interact"`, `availability_method = &"can_interact"`, `interaction_priority`, and `interaction_enabled`. Its public methods are `can_interact() -> bool`, `interact() -> bool`, `get_interaction_position() -> Vector2`, and `get_interaction_priority() -> int`.

`can_interact()` must reject disabled components, absent player, blocked game mode, locked input, invalid/freed targets, missing required target methods, and a false availability method. `interact()` must call only a valid target with `has_method(interaction_method)`. Register on player group entry once, unregister on exit and `_exit_tree()`, and unregister/re-register around blocked/exploration mode changes so scene changes and disabled components cannot remain candidates.

`InteractionManager` is an AutoLoad `Node` with `register(component)`, `unregister(component)`, `has_active_interactable()`, `get_active_interactable()`, and `request_interaction()`. It rejects duplicate registration, stores a monotonically increasing registration ordinal, and ranks valid candidates by `-priority`, squared player distance, then ordinal. It signals `active_interactable_changed(component)`, clears its active target while blocked, and does not process an interaction until `InputManager.consume_interact_just_pressed()` returns true. Lock the request until the touch release is observed.

In `mobile_controls.gd`, connect `InteractionManager.active_interactable_changed` and the game mode signal; set the action margin visible/enabled only when the mode is exploration and `InteractionManager.has_active_interactable()` returns true. The Interact `TouchHoldButton` continues to feed `InputManager`; no gameplay keyboard path is restored.

Add this AutoLoad entry:

```ini
InteractionManager="*res://scripts/interaction_manager.gd"
```

- [ ] **Step 4: Verify deterministic behavior.**

Run the first three shared verification commands. Expected: candidate ordering and one-press behavior pass; no exploration scene loses its automatic Door behavior.

- [ ] **Step 5: Commit interaction services.**

```powershell
git add -- scripts/interactable_area.gd scripts/interaction_manager.gd scripts/mobile_controls.gd project.godot tools/mobile_exploration_services_test.gd
git diff --cached --check
git commit -m "feat: add reusable exploration interactions"
```

### Task 4: Separate automatic Teacher House arrival from Teacher conversation

**Files:**
- Create: `world/task_progress_trigger.gd`, `scripts/teacher_task_interaction.gd`
- Modify: `world/QuestUI.gd`, `scenes/oak_leaf_village.tscn`, `interiors/teacher_house.tscn`, `tools/mobile_exploration_services_test.gd`

- [ ] **Step 1: Add failing Task 1 tests.**

Assert that an automatic trigger with `required_task_index = 0` changes the index to `1` on first valid player entry, calls `advance_task_and_save()` before emitting notification data, and ignores another entry. Assert the Teacher component returns false from `can_interact()` at index `0`, then true at index `1`; a second press while its dialogue is active must return false.

- [ ] **Step 2: Run the tests against the legacy adapter.**

Run the second shared verification command. Expected: `Task1.gd` awaits dialogue work and cannot demonstrate immediate persisted arrival state.

- [ ] **Step 3: Implement focused Teacher adapters.**

Create `TaskProgressTrigger` as an `Area2D` with exported `required_task_index := 0`, `event_key := "quest:main:task:0:arrival"`, `notification_title := "Task 1"`, and `notification_objective := "Talk to the Teacher"`. On a `player` group body entry, it must reject a consumed or mismatched state, set its consumed flag, call:

```gdscript
GameState.advance_task_and_save({
	"type": "quest_updated",
	"key": event_key,
	"title": notification_title,
	"description": notification_objective,
})
```

Only free the trigger when `advanced` is true; otherwise clear its consumed flag. This establishes the required order: validate, advance, save, emit, then later visual feedback.

Create `teacher_task_interaction.gd` with `can_interact()` checking index `1` and a private active-dialogue flag. Its `interact()` pushes `DIALOGUE`, delegates to `QuestUI.play_teacher_dialogue()`, and pops only the mode it pushed when the dialogue finishes. Refactor `QuestUI` so the Teacher's existing dialogue text and battle destination survive, while the outside-arrival timer no longer controls task advancement.

In `scenes/oak_leaf_village.tscn`, replace the `TeacherHouseTaskTrigger` script only, retaining its position and collision shape. In `interiors/teacher_house.tscn`, remove the `Teacher/Area2D2` automatic `Task1.gd` signal, attach `teacher_task_interaction.gd` to `Teacher`, and attach `InteractableArea` to its existing range `Area2D` with target `..`, method `interact`, availability `can_interact`, and priority `100`.

- [ ] **Step 4: Validate exact scenes and node paths.**

Run the second, third, and fourth shared verification commands. Expected: Task 1 unit checks pass; Oak Leaf Village and Teacher House load without invalid node-path or signal errors.

- [ ] **Step 5: Commit the Teacher House phase.**

```powershell
git add -- world/task_progress_trigger.gd scripts/teacher_task_interaction.gd world/QuestUI.gd scenes/oak_leaf_village.tscn interiors/teacher_house.tscn tools/mobile_exploration_services_test.gd
git diff --cached --check
git commit -m "fix: advance Teacher House task immediately"
```

### Task 5: Add queued carved-wood quest notifications

**Files:**
- Create: `ui/quest_notification_manager.tscn`, `scripts/quest_notification_manager.gd`
- Modify: `project.godot`, `tools/mobile_exploration_services_test.gd`

- [ ] **Step 1: Add failing queue tests.**

Queue two different event keys and assert FIFO delivery. Queue the same stable key twice and assert one delivery. Change the game mode to `DIALOGUE` while a panel is visible and assert it hides without discarding the item; restore `EXPLORATION` and assert it resumes. Start a new game and assert the duplicate cache resets.

- [ ] **Step 2: Run the suite before the notification manager exists.**

Run the second shared verification command. Expected: missing `QuestNotificationManager` failure.

- [ ] **Step 3: Build the scene and manager API.**

Create a `CanvasLayer` scene with a full-rect `Root` Control, bottom-center `MarginContainer`, wood-styled `PanelContainer`, and `TypeLabel`, `TitleLabel`, and `DescriptionLabel`. Use the project font; blue type/border accents for `QUEST UPDATED`; gold type/border/glow for completed entries. The script positions the panel above `maxi(190, int(get_viewport().get_visible_rect().size.y * 0.28))` bottom pixels so it clears both touch clusters on different Android resolutions.

Expose exactly:

```gdscript
func show_quest_updated(title: String, objective: String, event_key: String = "") -> void
func show_task_completed(title: String, description: String, event_key: String = "") -> void
func show_quest_completed(title: String, description: String, event_key: String = "") -> void
```

Internally enqueue `{type, title, description, key}` dictionaries. A supplied stable key is recorded after enqueue; a generated key is unique only for that call. Begin tweened slide/fade display only in exploration. When a mode leaves exploration, kill the active tween, hide the panel, and place its incomplete item back at queue front. Resume when exploration returns. Connect `GameState.task_state_changed` to select the public method using its event dictionary, and clear the duplicate cache on `GameState.progression_session_reset`. Use `audio/completed.mp3` only for gold completion items when `ResourceLoader.exists()` confirms it.

Add this AutoLoad entry:

```ini
QuestNotificationManager="*res://ui/quest_notification_manager.tscn"
```

- [ ] **Step 4: Verify queue behavior and responsive layout.**

Run the second and third shared verification commands, then launch a desktop logic test with `720 x 1600` and `1080 x 2400` viewport overrides. Expected: queue tests pass; panels are hidden in blocked modes and appear above the safe zone only in exploration.

- [ ] **Step 5: Commit notifications.**

```powershell
git add -- ui/quest_notification_manager.tscn scripts/quest_notification_manager.gd project.godot tools/mobile_exploration_services_test.gd
git diff --cached --check
git commit -m "feat: add queued quest notifications"
```

### Task 6: Retire exploration hearts and repair the battle-heart resource

**Files:**
- Modify: `scripts/gameplay_scene.gd`, `scripts/game_hud.gd`, `ui/game_hud.tscn`, `player/life.tscn`, `tools/mobile_exploration_services_test.gd`

- [ ] **Step 1: Add failing HUD and resource tests.**

Assert that exploration scene setup does not instantiate `GameHUD`/life icons, a battle `BattleLifeDisplay` still instantiates `player/life.tscn`, and `player/life.tscn` contains `res://assets/hearth.png` with `region_enabled = false`.

- [ ] **Step 2: Record the baseline missing resource.**

Run the first shared verification command. Expected: the current baseline reports missing `res://assets/hearts.png` from `player/life.tscn`.

- [ ] **Step 3: Remove only exploration health UI.**

Remove `GAME_HUD_SCENE` and `_ensure_hud()` only from `gameplay_scene.gd`; retain player spawning, mobile controls, NPC collisions, and door input unlocking. Keep any legacy `GameHUD` life panel hidden outside `BATTLE` while preserving its game-over overlay. In `player/life.tscn`, change the texture to `res://assets/hearth.png`, remove the invalid UID, and disable the obsolete region rectangle. Do not modify any `BattleLifeDisplay` scene or create an image asset.

- [ ] **Step 4: Verify the repair.**

Run:

```powershell
rg -n 'res://assets/hearts\.png' . -g '!docs/**'
& '.\tools\Godot_v4.6.1-stable_win64.exe' --headless --path . --script res://tools/mobile_exploration_services_test.gd
& '.\tools\Godot_v4.6.1-stable_win64.exe' --headless --path . --script res://tools/scene_smoke_test.gd
```

Expected: no runtime match for the invalid path, battle scenes resolve life icons, and exploration scenes have no player-heart panel.

- [ ] **Step 5: Commit HUD cleanup.**

```powershell
git add -- scripts/gameplay_scene.gd scripts/game_hud.gd ui/game_hud.tscn player/life.tscn tools/mobile_exploration_services_test.gd
git diff --cached --check
git commit -m "fix: keep health UI in battles only"
```

### Task 7: Route battle questions through a defensive JSON provider

**Files:**
- Create: `scripts/question_provider.gd`
- Modify: `Battle/Battle-Enemy/QuizManager.gd`, `project.godot`, `tools/mobile_exploration_services_test.gd`, `tools/scene_smoke_test.gd`

- [ ] **Step 1: Add failing provider tests.**

Test the existing `Data/questions.json`, a no-match filter, and an invalid record. A valid result must contain non-empty `question`, an array `choices` usable by four buttons, and integer `correct` within that array. Assert no-match returns `{}` and collection filtering returns `[]`.

- [ ] **Step 2: Run the suite before adding the provider.**

Run the second shared verification command. Expected: missing `QuestionProvider` failure.

- [ ] **Step 3: Implement provider and minimal battle adapter.**

Create `question_provider.gd` as an AutoLoad. Load `res://Data/questions.json` once, reject malformed/empty/invalid entries, and expose:

```gdscript
func get_random_question(filters: Dictionary = {}) -> Dictionary
func get_questions(filters: Dictionary = {}) -> Array[Dictionary]
func get_questions_by_grade(grade: String) -> Array[Dictionary]
func get_questions_by_topic(topic: String) -> Array[Dictionary]
func get_questions_by_difficulty(difficulty: String) -> Array[Dictionary]
```

Filters may use grade, topic, difficulty, enemy, or map. `get_random_question()` returns `{}` for no valid match; it never returns null. Add `QuestionProvider="*res://scripts/question_provider.gd"` to AutoLoads.

In `QuizManager`, replace direct `FileAccess`/`JSON` reads with `QuestionProvider.get_random_question()`. An empty dictionary sets `question_label.text = "No questions found!"` and disables buttons. Keep the existing answer buttons, correct/wrong effects, enemy/player health, and character scenes. Push `BATTLE` in `_ready()` and pop only if this instance pushed it in `_exit_tree()`.

- [ ] **Step 4: Verify JSON and battle loading.**

Extend `scene_smoke_test.gd` with every battle scene referencing `QuizManager.gd`, then run the first three shared verification commands. Expected: each scene loads and valid JSON still provides four answer choices.

- [ ] **Step 5: Commit provider boundary.**

```powershell
git add -- scripts/question_provider.gd Battle/Battle-Enemy/QuizManager.gd project.godot tools/mobile_exploration_services_test.gd tools/scene_smoke_test.gd
git diff --cached --check
git commit -m "refactor: route battles through question provider"
```

### Task 8: Adapt existing villagers and finish regression validation

**Files:**
- Create: `scripts/quest_task_interaction.gd`
- Modify: `NPC/Npc/old_adult_women_Dialog.gd`, `world/Task3.gd`, `interiors/Task2.gd`, `scenes/oak_leaf_village.tscn`, `tools/scene_smoke_test.gd`, `tools/validate_theresian_scene_integrity.ps1`, `tools/mobile_exploration_services_test.gd`

- [ ] **Step 1: Add failing scene-adapter assertions.**

Assert that `girl_npc`, `NPC`, `villager-female`, and `NPC1` retain their Area2D collision shapes but use `InteractableArea`; assert their automatic dialogue `body_entered`/`body_exited` signals are absent; assert quest NPC/bandit triggers require a valid interaction request rather than body entry; assert Door scenes still have `trigger_mode = "touch"`.

- [ ] **Step 2: Run pre-adapter integrity validation.**

Run the second and fourth shared verification commands. Expected: the new adapter assertions fail because village dialogue remains proximity-triggered.

- [ ] **Step 3: Adapt dialogue without changing narrative content.**

Replace automatic body callbacks in `old_adult_women_Dialog.gd` with `can_interact()` and `interact()`. `interact()` must set the existing greeting label, push `DIALOGUE`, start the existing timed presentation, then pop only the mode it pushed when presentation ends. Preserve `greeting_message`, dialogue panel paths, label paths, and existing art/audio.

For the four named village NPCs, retain existing Area2D nodes and collision shapes, attach `interactable_area.gd`, target their parent, use `interact`/`can_interact`, and assign stable priorities. Remove only their automatic dialogue signal connections.

Create `quest_task_interaction.gd` as the adapter for existing quest NPCs, bandits, wizard encounters, signs, and chests: it exposes `can_interact()` for the required task state, `interact()` with a one-active-interaction guard, and exported target/method paths for the existing narrative or battle hand-off. Update `world/Task3.gd` and `interiors/Task2.gd` to call this adapter from an `InteractableArea` request instead of `body_entered`; preserve their existing task text, dialogue, battle destination, and completion condition. Apply the same component to currently automatic bandit/wizard quest range areas when their scene instances are found by the smoke-test inventory. Do not alter house doors, exits, or map-transition Area2Ds.

Update the integrity script to require `task_progress_trigger.gd` on `TeacherHouseTaskTrigger`, its preserved node name, and the Teacher House interaction node path. Remove its old requirement that this trigger still references `Task1.gd`.

- [ ] **Step 4: Run final checks and collect evidence.**

Run all shared verification commands, then run the game with the bundled executable and simulate touch through the new controls or programmatic input. Check: Task 1 first entry and repeat-entry guard; Teacher interact availability; automatic house/map doors; dialogue blocks controls/notifications; battle entry/exit modes; JSON question display; notification FIFO/deduplication; and corrected battle life icons. Do not reintroduce keyboard mappings for this check.

- [ ] **Step 5: Commit final adapters and validation tools.**

```powershell
git add -- scripts/quest_task_interaction.gd NPC/Npc/old_adult_women_Dialog.gd world/Task3.gd interiors/Task2.gd scenes/oak_leaf_village.tscn tools/scene_smoke_test.gd tools/validate_theresian_scene_integrity.ps1 tools/mobile_exploration_services_test.gd
git diff --cached --check
git commit -m "feat: adapt exploration interactions and validate flows"
```

## Final handoff checklist

- List all modified and newly created scripts/scenes.
- Explain the zero-based task state table: `0` arrival objective, `1` Teacher conversation, `2` battle objective, and `>= 3` complete current task sequence.
- Explain old-save fallback to index `0`, mode-stack restoration, touch clearing, selection sorting, one-press locking, notification event keys, and JSON provider failure behavior.
- Report the exact `player/life.tscn` correction from `res://assets/hearts.png` to `res://assets/hearth.png` and the reason it was retained for battle UI.
- Clearly separate Headless validated, Desktop logic validated using simulated touch/input, and Android device testing required results.
- If a phase regresses, revert that phase's focused commit or compare it to `backup/pre-mobile-exploration-services-20260805`; never discard unrelated user changes.
