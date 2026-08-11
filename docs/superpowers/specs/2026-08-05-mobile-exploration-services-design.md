# Mobile Exploration Services Design

## Goal

Convert exploration gameplay to touch-only Android controls without rebuilding the completed RPG. Keep automatic door and map transitions, require an explicit on-screen interaction for NPCs and intentional objects, make Task 1 advance immediately at the Teacher House, and provide polished quest notifications. Existing JSON quiz content must remain the current question source behind a provider boundary for a future API/PostgreSQL migration.

## Existing Project Constraints

- `InputManager` is the movement and interaction source used by both player scenes. The existing mobile control scene already writes into it.
- `gameplay_scene.gd` creates the player, game HUD, and mobile controls for exploration scenes.
- `door.gd` already supports automatic touch triggers and must retain that behavior for doors and map exits.
- The outdoor `TeacherHouseTaskTrigger` uses `Task1.gd`. Its current UI routine contains long dialogue waits, so task progression is visually delayed after entry and the task index is not persisted by saves.
- NPC dialogue and task triggers are currently implemented by several scene-local scripts. New shared behavior must adapt these scripts rather than replace battle or question content.
- Battle scenes already instantiate `BattleLifeDisplay`; the exploration HUD separately shows player hearts and must no longer do so.

## Architecture

### Game flow state

Extend the central game state with typed gameplay modes: `EXPLORATION`, `DIALOGUE`, `CUTSCENE`, `BATTLE`, and `MENU`. A mode-changed signal is the visibility contract for exploration UI. Mode changes are controlled through public transition methods such as `set_mode(mode)`, `push_mode(mode)`, and `pop_mode()`; unrelated scene scripts do not assign the current mode directly. A mode stack restores nested flows correctly, for example `EXPLORATION → DIALOGUE → CUTSCENE → DIALOGUE → EXPLORATION`, and battle/menu exits restore the actual prior valid mode.

- Mobile movement controls show only in `EXPLORATION`.
- The Interact button is enabled only in `EXPLORATION` when the interaction manager has a valid target.
- Queued quest notifications do not begin while the mode is not `EXPLORATION`. A notification already visible when gameplay becomes blocked immediately exits or pauses hidden, then remains queued for resumption when exploration returns.
- Battle entry sets `BATTLE` before effects or questions appear; battle and menu exits restore the prior valid mode through the stack.
- Scene menus and loading screens use `MENU`/blocked input so exploration UI cannot flash during transitions.
- Leaving `EXPLORATION` clears every held touch direction and held interaction press.

### Touch controls

Keep `ui/mobile_controls.tscn` as the control host and retain its connection to `InputManager`. Replace the temporary rectangular presentation with a wooden framed D-pad in the lower-left safe area. Direction targets use a child-friendly touch size and clean arrows. The lower-right button is a large circular `INTERACT` control.

The input layer becomes touch-only: movement and interaction actions are driven by the on-screen controls, with state cleared when a press is released, cancelled, hidden, or input becomes blocked. Keyboard movement, interaction, and other exploration gameplay mappings are removed from `project.godot`, and `InputManager` no longer reads keyboard actions. Editor/debug controls, text-entry behavior, and menu navigation are retained unless already replaced by complete touch controls. The UI uses full-rect anchors, lower-corner margin containers, and minimum sizes derived from the viewport so it remains clear of the bottom-center notification area.

### Intentional interaction

Create a reusable `InteractableArea` component and a central `InteractionManager` autoload.

- An interactable registers once while the shared `player`/`player_character` group is inside its `Area2D`.
- The manager ranks candidates deterministically by highest exported priority, shortest distance to the player, then registration order or instance ID as a stable tie-breaker.
- Invalid candidates are removed when they leave range, are freed, become disabled, the player changes scenes, or the gameplay mode becomes blocked.
- Pressing the on-screen Interact button consumes one edge-triggered request, calls the selected component once, and blocks further activation until a release and valid new request.
- The component validates its target, checks `has_method()`, never calls freed/disabled nodes, and can query an optional quest-aware availability method before dispatching to an existing node method.
- The reusable component exposes `can_interact()`, `interact()`, `get_interaction_position()`, and `get_interaction_priority()` or equivalent safe methods. Existing scripts are wrapped or adapted rather than rewritten.
- Interactions are disabled and requests remain locked during dialogue, cutscenes, battle, menus, transitions, and any active interaction.

Doors remain outside this component. Their `Area2D` behavior stays automatic for houses, exits, and scene changes.

### Teacher House Task 1 and progression semantics

Separate the two meanings currently bundled into `Task1.gd`.

- The current task array is zero-based and existing semantics are preserved:

| `current_task_index` | Active objective | Teacher House meaning |
| --- | --- | --- |
| `0` | Go to the Teacher's House | The outside Task 1 objective is active and has not yet been completed. |
| `1` | Talk to the Teacher | The house arrival was completed and saved; the Teacher conversation is now the active intentional interaction. |
| `2` | Challenge the player with math questions | The Teacher conversation has completed; the next battle objective is active. |
| `>= 3` | No remaining entry in the current task array | The current task sequence is complete. |

- The outside `TeacherHouseTaskTrigger` stays an automatic area trigger, checks the shared player group and requires index `0`, advances atomically to index `1`, saves the updated state, emits its task-state signal, queues feedback, and removes/guards itself after success.
- The Teacher inside the house becomes an intentional interactable. It requires Task 1 to be active, starts the existing dialogue only after an Interact press, and cannot start duplicate dialogue while a conversation is active.
- No long timer is allowed before the outside task state advances. The required order is validate state, advance, persist, emit state, queue notification, then start optional narrative feedback. A notification or dialogue failure cannot prevent the saved progression.

### Quest notifications

Create a reusable quest notification scene plus `QuestNotificationManager` API:

```gdscript
show_quest_updated(title, objective)
show_task_completed(title, description)
show_quest_completed(title, description)
```

The manager owns a FIFO queue and stable duplicate-event cache. Each event accepts an optional stable key composed from quest identity, task index, notification type, and progression state rather than only displayed text. The cache prevents repeated emission of one transition, permits legitimate later messages with a new state key, and resets or rehydrates safely when starting or loading a game. It displays one item at a time using short slide/fade tweens, then releases the next entry. The normal style is carved wood:

- blue headline/accent for `QUEST UPDATED`;
- gold headline/accent, glow, and the existing completion sound where available for `QUEST COMPLETE`;
- bottom-center placement above the reserved touch-control safe zone;
- responsive width and text wrapping for Android resolutions.

Rune-stone styling is not used for ordinary updates; its theme hook remains available for future wizard, boss, and magical events.

### Quest persistence

Persist `current_task_index` with the existing save data and restore it through a defensive lookup. The project already has `SAVE_VERSION`; the save schema version advances only as needed for this additive field. Saves made before the field existed stay valid, defaulting to index `0`, which is the current initial `Go to the Teacher's House` objective. The value is clamped to the valid task range without rejecting or corrupting the old save. Emit a quest/task state signal after load and after each safe task transition so the notification manager and scene UI remain synchronized. New-game initialization resets task state and notification deduplication state. Existing quest text, dialogue arrays, and battle destinations remain intact.

### Exploration and battle HUD

Exploration no longer creates or displays player-heart UI. Existing `BattleLifeDisplay` instances remain in battle scenes and continue to use current life and damage logic. The new game mode controls any globally-instanced HUD root so it cannot flash while a scene or battle overlay changes. Every reference to `res://assets/hearts.png` is traced before modification: the reference is removed if it belongs only to retired exploration UI, or redirected to the existing battle-heart resource if battle scenes require it. No placeholder image is created.

### Question provider boundary

Create a JSON-backed question provider with the interface:

```gdscript
get_random_question(filters := {})
get_questions_by_grade(grade)
get_questions_by_topic(topic)
get_questions_by_difficulty(difficulty)
```

The provider exposes `get_random_question(filters := {}) -> Dictionary` and the listed collection methods returning `Array[Dictionary]`. A valid battle question must retain the current dictionary shape: non-empty `question` text, an answer `choices` array compatible with the four battle buttons, and an integer `correct` index inside that array. Optional filters can include grade, topic, difficulty, enemy, or map without changing callers. Missing, malformed, empty, or invalid JSON entries are reported safely and excluded; collection filtering returns an empty array and random selection returns an empty dictionary when no valid matching question exists. `QuizManager` handles that result without a null error and continues to receive the same battle-facing dictionary. A future API provider can implement the same calls without changing battle scenes. No API URL or placeholder database code is added.

## Files Expected to Change

- Project setup and exploration input: `project.godot`, `scripts/input_manager.gd`, `scripts/game_state.gd`, `scripts/gameplay_scene.gd`, `scripts/mobile_controls.gd`, `ui/mobile_controls.tscn`.
- New shared services/components: interaction manager/component, notification manager/scene, JSON question provider.
- Existing adapters: Teacher/NPC, Task 1, selected quest scenes, `QuizManager`, and exploration HUD.
- Scene wiring: Oak Leaf Village, Teacher House, and any shared NPC/interactable scenes required by the component.

## Validation Strategy

1. Run Godot headless parse/import validation and targeted scene-load smoke checks for every modified scene.
2. Run static checks for autoload names, signal connections, node paths, resource paths, and JSON provider output.
3. Run desktop logic checks with the bundled Godot executable using simulated touch/input, programmatic `InputManager` calls, or input-event injection; production keyboard gameplay controls are never restored to test the game.
4. Report validation with the labels `Headless validated`, `Desktop logic validated using simulated touch/input`, and `Android device testing required`. Multi-touch, touch hit targets, Android safe areas, and a full device playthrough remain Android-device testing until an actual device/emulator is connected.

## Rollback-Friendly Implementation Phases

1. Game mode and save-state foundation.
2. Touch-input cleanup.
3. Interaction manager and reusable component.
4. Teacher House Task 1 adaptation.
5. Quest notification system.
6. Exploration HUD cleanup and heart-reference fix.
7. Question-provider boundary.
8. Scene adapters and regression validation.

Each phase keeps the project parseable and runnable before the next begins. The pre-change backup branch and the committed design document provide a recovery point; no phase replaces existing battle, door, or dialogue content wholesale.

## Scope Boundaries

- Do not rewrite battle scenes, dialogue content, quest narrative, animations, save format fields unrelated to task state, or existing door transition logic.
- Preserve the current quest and battle content while routing it through new shared interfaces.
- Do not create database or network code; preserve migration compatibility through the provider interface only.
