# Theresian's Quest Main Menu and New Game Registration Navigation Design

**Date:** 2026-08-11  
**Status:** Approved for implementation

## Goal

Repair the existing Main Menu leaderboard route and the existing embedded New Game registration wizard without changing battle, quest, dialogue, animation, save, navigation, or mobile-control systems outside the registration path.

## Existing project context

The repository's actual relevant scenes and scripts are:

- Main Menu: `res://scenes/main_menu.tscn`
- Main Menu controller: `res://scripts/main_menu_scene.gd`
- Leaderboard: `res://leaderboard_scene.tscn`
- New Game: `res://scenes/new_game_scene.tscn`
- New Game wizard controller: `res://scenes/texture_rect_2.gd`
- New Game Back button: `res://scripts/newgm_back.gd`
- New Game button: `res://scripts/new_game_btn.gd`
- Existing tutorial/player entry scene: `res://interiors/player_house.tscn`
- Existing loading route: `res://scenes/loading_screen.tscn`
- Central autoload state: `res://scripts/game_state.gd`

The New Game scene already contains the registration panels `GenderSelect`, `StudentParentId`, and `NameGradeSelect`. It also already contains the six individual grade buttons `Grade1` through `Grade6`, their existing textures, and the existing grade label mapping. The current controller advances directly from gender selection to the name/grade panel, leaving the ID panel out of the route. The leaderboard scene currently reuses the New Game wizard script even though it does not contain the wizard nodes that script expects.

## Chosen approach

Keep the existing scene structure and repair it as an explicit in-scene wizard. Do not create duplicate Main Menu, Leaderboard, Gender, ID, Name/Grade, or Tutorial scenes.

The wizard will have these states:

1. Gender selection
2. Student ID and Parent ID
3. Student Name and Grade 1–6

The gender panel will receive a Continue/Next control using the existing button visual style. Selecting Male or Female will only update selection state; Continue advances to the ID panel. The existing ID Next control advances to Name/Grade only after both IDs pass validation. The existing Start button becomes the final Play action.

## Navigation and transition behavior

### Main Menu and Leaderboard

`scripts/main_menu_scene.gd` will connect the existing `LeaderboardButton` exactly once. Its handler will:

- guard against repeated presses;
- disable further Main Menu input while transitioning;
- preserve the existing fade behavior using `Fade`;
- call `change_scene_to_file("res://leaderboard_scene.tscn")`.

The existing `leaderboard_scene.tscn` will no longer attach `res://scenes/texture_rect_2.gd` to its background control. Its existing Back button will remain the route back to `res://scenes/main_menu.tscn`, using the existing Back/fade script. A small leaderboard-only controller may be attached if needed for existing music behavior; it will not introduce a second navigation manager.

### Registration Back behavior

The existing New Game Back button will delegate to the wizard controller when the current scene exposes its registration Back handler:

- Gender → Main Menu and cancel the incomplete registration session;
- Student/Parent IDs → Gender, preserving selected gender and entered IDs;
- Name/Grade → Student/Parent IDs, preserving all entered values.

The Back script will otherwise retain its existing scene-target behavior for the leaderboard route. Back and forward transitions will be guarded so a repeated tap cannot trigger duplicate scene changes or duplicate state transitions.

## Temporary registration state

`GameState` will own a small temporary registration dictionary separate from permanent player/save fields. Its fields are:

- `selected_gender`
- `student_id`
- `parent_id`
- `student_name`
- `grade_level`

Main Menu → New Game calls a reset method to start a fresh session. The wizard updates this state as the user types or selects values. Going backward within the wizard rehydrates the controls from this state where appropriate. Returning from Gender to Main Menu clears the incomplete session.

The temporary dictionary is never written by `save_game()` or `build_save_data()`. Only a validated Play action calls `GameState.start_new_game()` with the complete profile. The permanent new-game state will store the finalized gender, student ID, parent ID, name, and grade along with the existing save fields. `start_new_game()` will continue to reset the existing quest/task, scene/spawn, lives, battle, resume, and progression state before entering the existing tutorial/player-house route.

## Validation and mobile input

Both ID `LineEdit` controls will use:

- `max_length = 6`;
- the Godot numeric virtual-keyboard hint where supported;
- actual text sanitization on every text change;
- an exact six-ASCII-digit check before progression.

Sanitization removes pasted letters, symbols, spaces, decimal points, signs, and any extra digits while preserving valid digits and leading zeroes. Validation messages identify the field and say that it must contain exactly six digits. Invalid input will not clear the other valid field.

Name validation trims leading/trailing whitespace and rejects only an empty result. Grade validation requires exactly one of the six existing buttons. The existing grade labels and mapping remain unchanged so grade-specific quiz/question behavior continues to receive the same values.

Controls will use Godot `pressed` signal handling, which works for touch and mouse. Existing visual hover/press animations will be retained. No keyboard-dependent gameplay behavior will be introduced.

## Final Play and tutorial route

Play is allowed only when gender, Student ID, Parent ID, non-empty trimmed name, and one valid grade are present. On Play:

1. Finalize the profile in `GameState`.
2. Clear temporary registration state.
3. Run the existing `start_new_game()` reset behavior.
4. Queue the existing player-house spawn/loading route.
5. Enter the existing tutorial content through `res://scenes/loading_screen.tscn` and `res://interiors/player_house.tscn`.

The tutorial content, teacher introduction, dialogue, movement/interaction tutorial, sample quiz/battle, quest setup, scene progression, and Male/Female player scene selection remain unchanged.

## Scope boundaries

Changes are limited to the Main Menu leaderboard handler, leaderboard scene script attachment, New Game wizard navigation/validation, registration-session state, relevant Back/New Game button touch guards, and focused tests/probes. Battle logic, quiz/question data, quest ordering/dialogue, NPC interaction architecture, animations, doors/maps, D-pad/interact controls, notifications, and unrelated save fields will not be refactored.

## Verification plan

The implementation will be verified in layers:

1. Parser/static checks for every changed GDScript and scene reference.
2. Focused headless tests for six-digit validation, sanitization, temporary-state preservation, finalization, and no-save-before-Play behavior.
3. Scene/resource smoke tests covering Main Menu, Leaderboard, New Game, loading, and existing tutorial/player-house scenes.
4. A headless route probe for Main Menu → Leaderboard → Main Menu and both Male/Female New Game flows, including Back transitions and final tutorial entry where the runtime permits.
5. A requirements checklist covering invalid ID input, empty name, missing grade, preservation of valid fields, old-save isolation, duplicate-press guards, and unchanged systems.

The final report will explicitly distinguish parser/static validation, scene/resource validation, actual runtime validation, and Android/device testing. Runtime or Android success will not be claimed if Godot exits before SceneTree test initialization or if touch is not exercised on a device/emulator.
