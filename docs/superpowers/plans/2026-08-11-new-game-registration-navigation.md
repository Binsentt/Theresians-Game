# Main Menu and New Game Registration Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the existing leaderboard and New Game registration routes so both genders follow `Main Menu → Gender → IDs → Name/Grade 1–6 → Play → res://interiors/player_house.tscn`, with strict ID validation and temporary registration state.

**Architecture:** Keep the existing `scenes/new_game_scene.tscn` as a single in-scene wizard. Add a small temporary registration dictionary to the existing `GameState` autoload, keep permanent profile fields separate until Play, and use the existing fade/loading/tutorial path. Connect only buttons that are not already editor-connected, and use transition guards so a press is handled once.

**Tech Stack:** Godot 4.6.1, GDScript, text `.tscn` resources, headless Godot SceneTree probes, PowerShell/Python static checks.

---

## Scope and file map

Files to create or modify:

- Create: `tools/new_game_registration_test.gd` — headless state/validation test.
- Create: `tools/new_game_route_test.gd` — headless scene-route/back-navigation probe.
- Modify: `scripts/game_state.gd` — temporary registration, string ID helpers, finalized ID fields, and new-game reset integration.
- Modify: `scripts/main_menu_scene.gd` — existing Leaderboard button handler and guarded fade transition.
- Modify: `scripts/new_game_btn.gd` — touch-safe guarded New Game transition and fresh registration reset.
- Modify: `scripts/newgm_back.gd` — touch-safe Back handling and wizard delegation.
- Modify: `scenes/texture_rect_2.gd` — explicit Gender/IDs/Name-Grade wizard, validation, hydration, and Play finalization.
- Modify: `scenes/new_game_scene.tscn` — hide/show the existing panels correctly, add only the required Gender Continue control, configure ID inputs, move/reuse validation UI, and retain the six existing grade buttons.
- Modify: `leaderboard_scene.tscn` — remove the incorrect registration wizard script attachment while keeping its existing visual content and Back button.
- Modify: `tools/scene_smoke_test.gd` — include `res://leaderboard_scene.tscn` in the active scene list.

Files explicitly out of scope: battle scenes/scripts, quiz/question data, quest/task/dialogue scripts, mobile D-pad/interact/interaction systems, door/map scenes, tutorial content, and unrelated save fields. Existing dirty changes in those files must not be staged or reverted.

## Task 1: Write the failing registration-state tests

**Files:**

- Create: `tools/new_game_registration_test.gd`

- [ ] **Step 1: Add the red test before changing production code.**

Create a `SceneTree` test that calls the intended `GameState` registration API and exercises the required edge cases:

```gdscript
extends SceneTree

var failures: Array[String] = []
var save_created := false

func _initialize() -> void:
	GameState.save_created.connect(_on_save_created)
	call_deferred("_run")

func _run() -> void:
	_assert(GameState.is_valid_six_digit_id("123456"), "six ordinary digits are valid")
	_assert(GameState.is_valid_six_digit_id("000123"), "leading zeroes are valid")
	_assert(not GameState.is_valid_six_digit_id("12345"), "five digits are invalid")
	_assert(not GameState.is_valid_six_digit_id("1234567"), "seven digits are invalid")
	_assert(not GameState.is_valid_six_digit_id("12A456"), "letters are invalid")
	_assert(not GameState.is_valid_six_digit_id("12-456"), "symbols are invalid")
	_assert(not GameState.is_valid_six_digit_id("123 456"), "spaces are invalid")
	_assert(not GameState.is_valid_six_digit_id("123.45"), "decimal points are invalid")
	_assert(not GameState.is_valid_six_digit_id("+12345"), "signs are invalid")
	_assert(GameState.sanitize_six_digit_id("12A 3-4567") == "123456", "pasted text keeps only the first six digits")

	GameState.begin_new_game_registration()
	GameState.update_new_game_registration({
		"gender": "female",
		"student_id": "000123",
		"parent_id": "654321",
		"student_name": "  Ana Maria  ",
		"grade": "Grade 6"
	})
	var registration := GameState.get_new_game_registration()
	_assert(registration.get("student_id") == "000123", "temporary student ID preserves leading zeroes")
	_assert(registration.get("parent_id") == "654321", "temporary parent ID is preserved")
	_assert(registration.get("student_name") == "  Ana Maria  ", "temporary name is preserved before final trim")
	_assert(not save_created, "incomplete registration does not emit a save")

	GameState.current_scene_path = "res://scenes/city_of_knowledge.tscn"
	GameState.player_position = Vector2(999, 999)
	GameState.current_task_index = 2
	GameState.battle_active = true
	GameState.current_battle_enemy_path = NodePath("stale_enemy")
	_assert(GameState.finalize_new_game_registration(), "valid registration finalizes")
	_assert(GameState.gender == "female", "final gender is committed")
	_assert(GameState.student_id == "000123", "final student ID is committed as a string")
	_assert(GameState.parent_id == "654321", "final parent ID is committed as a string")
	_assert(GameState.player_name == "Ana Maria", "final name is trimmed")
	_assert(GameState.grade_level == "Grade 6", "exact grade value is committed")
	_assert(GameState.current_scene_path == GameState.START_SCENE_PATH, "new game starts at the canonical scene")
	_assert(GameState.current_task_index == 0, "new game resets task state")
	_assert(not GameState.battle_active, "new game clears stale battle state")
	_assert(GameState.current_battle_enemy_path.is_empty(), "new game clears stale battle enemy path")
	_assert(GameState.get_new_game_registration().is_empty(), "temporary registration clears after finalization")
	_assert(not save_created, "finalization itself does not create a save")

	if failures.is_empty():
		print("NEW_GAME_REGISTRATION_TEST PASSED")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("NEW_GAME_REGISTRATION_TEST FAILED")
	quit(1)

func _on_save_created(_save_data: Dictionary) -> void:
	save_created = true

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
```

- [ ] **Step 2: Run the test and confirm the failure is caused by missing registration API.**

Run from the actual project root:

```powershell
& .\tools\Godot_v4.6.1-stable_win64.exe --headless --path . --script tools/new_game_registration_test.gd
```

Expected before implementation: non-zero exit with an undefined registration method or equivalent missing-API error. If the executable exits with signal 11 before SceneTree initialization instead, record that as an environment/runtime blocker while retaining the red test as the required test-first artifact.

## Task 2: Implement temporary registration and finalized profile state

**Files:**

- Modify: `scripts/game_state.gd`
- Test: `tools/new_game_registration_test.gd`

- [ ] **Step 1: Add the registration constants and separate temporary dictionary.**

Add the following near the existing player fields without changing the existing task/mode definitions:

```gdscript
const VALID_REGISTRATION_GRADES := [
	"Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"
]

var student_id := ""
var parent_id := ""
var _new_game_registration: Dictionary = {}
```

- [ ] **Step 2: Add exact string validation and temporary-session helpers.**

Implement these methods in `scripts/game_state.gd`. They must preserve leading zeroes, accept only ASCII digits, and never call `save_game()`:

```gdscript
func is_valid_six_digit_id(value: String) -> bool:
	if value.length() != 6:
		return false
	for character in value:
		var codepoint := character.unicode_at(0)
		if codepoint < 48 or codepoint > 57:
			return false
	return true

func sanitize_six_digit_id(value: String) -> String:
	var digits := ""
	for character in value:
		var codepoint := character.unicode_at(0)
		if codepoint >= 48 and codepoint <= 57:
			digits += character
			if digits.length() == 6:
				break
	return digits

func begin_new_game_registration() -> void:
	_new_game_registration = {
		"gender": "",
		"student_id": "",
		"parent_id": "",
		"student_name": "",
		"grade": ""
	}

func get_new_game_registration() -> Dictionary:
	return _new_game_registration.duplicate(true)

func update_new_game_registration(values: Dictionary) -> void:
	for key in ["gender", "student_id", "parent_id", "student_name", "grade"]:
		if values.has(key):
			_new_game_registration[key] = values[key]

func clear_new_game_registration() -> void:
	_new_game_registration.clear()

func is_valid_new_game_registration(values: Dictionary) -> bool:
	var gender_value := String(values.get("gender", "")).to_lower()
	var grade_value := String(values.get("grade", ""))
	return (
		gender_value in ["male", "female"]
		and is_valid_six_digit_id(String(values.get("student_id", "")))
		and is_valid_six_digit_id(String(values.get("parent_id", "")))
		and not String(values.get("student_name", "")).strip_edges().is_empty()
		and grade_value in VALID_REGISTRATION_GRADES
	)
```

- [ ] **Step 3: Extend `start_new_game()` with required IDs while preserving its existing reset body.**

Keep the existing `start_new_game(profile)` entry point and add only these commits beside the current name/gender/grade assignments:

```gdscript
student_id = String(profile.get("student_id", ""))
parent_id = String(profile.get("parent_id", ""))
```

Do not remove or reorder its existing reset operations for quest, lives, scene path, spawn, city unlock, task index, pending spawn, return context, battle state, resume state, mode, and progression signals.

- [ ] **Step 4: Add the finalization method with validate → commit/reset → clear ordering.**

Add:

```gdscript
func finalize_new_game_registration() -> bool:
	var values := get_new_game_registration()
	if not is_valid_new_game_registration(values):
		return false

	start_new_game({
		"player_name": String(values.get("student_name", "")).strip_edges(),
		"gender": String(values.get("gender", "")).to_lower(),
		"student_id": String(values.get("student_id", "")),
		"parent_id": String(values.get("parent_id", "")),
		"grade_level": String(values.get("grade", ""))
	})
	clear_new_game_registration()
	return true
```

- [ ] **Step 5: Add finalized IDs to permanent save/load data only.**

Add `student_id` and `parent_id` beside the existing profile fields in `build_save_data()` and read them in `apply_save_data()`. Do not add temporary dictionary contents to save data, and do not change any unrelated save fields.

- [ ] **Step 6: Run the focused test and verify GREEN.**

Run the same Godot command from Task 1. Expected: `NEW_GAME_REGISTRATION_TEST PASSED` and exit code 0. If runtime initialization still signal-11 crashes, run the parser/static validation separately and record runtime as unexecuted; do not silently mark the test passed.

- [ ] **Step 7: Commit only the state/test changes.**

```powershell
git add -- scripts/game_state.gd tools/new_game_registration_test.gd
git commit -m "feat: add temporary new-game registration state"
```

## Task 3: Write the failing route and signal-audit probe

**Files:**

- Create: `tools/new_game_route_test.gd`
- Test: `scenes/main_menu.tscn`, `leaderboard_scene.tscn`, `scenes/new_game_scene.tscn`

- [ ] **Step 1: Add a route probe that treats each transition as a single action.**

The probe must load the actual scenes and use only existing/new UI nodes and `pressed.emit()` calls. Create it with this executable body:

```gdscript
const MAIN_MENU := "res://scenes/main_menu.tscn"
const LEADERBOARD := "res://leaderboard_scene.tscn"
const NEW_GAME := "res://scenes/new_game_scene.tscn"
const LOADING := "res://scenes/loading_screen.tscn"
const PLAYER_HOUSE := "res://interiors/player_house.tscn"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _load_scene(MAIN_MENU)
	await _press(current_scene.get_node("LeaderboardButton") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(LEADERBOARD)
	await _press(current_scene.get_node("TextureRect2/BackgroundMenu/Back-Button") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(MAIN_MENU)

	await _press(current_scene.get_node("VBoxContainer/NewGameBtn") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(NEW_GAME)
	_assert(current_scene.get_node("TextureRect2/GenderSelect").visible, "New Game opens Gender")
	_assert(not current_scene.get_node("TextureRect2/StudentParentId").visible, "New Game hides IDs until Continue")
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(MAIN_MENU)
	_assert(GameState.get_new_game_registration().is_empty(), "Gender Back cancels temporary registration")

	await _run_back_preservation_case()
	await _run_gender_case("male", "Grade 1")
	await _run_gender_case("female", "Grade 6")

	if failures.is_empty():
		print("NEW_GAME_ROUTE_TEST PASSED")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NEW_GAME_ROUTE_TEST FAILED")
	quit(1)

func _run_back_preservation_case() -> void:
	await _load_scene(MAIN_MENU)
	await _press(current_scene.get_node("VBoxContainer/NewGameBtn") as BaseButton)
	await _wait_seconds(0.5)
	var wizard := current_scene.get_node("TextureRect2")
	await _press(wizard.get_node("GenderSelect/MaleBtn") as BaseButton)
	_assert(wizard.get_node("GenderSelect").visible, "gender selection does not auto-advance")
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.3)
	_assert(wizard.get_node("StudentParentId").visible, "Gender Continue opens IDs")
	wizard.get_node("StudentParentId/StudentIdInput").text = "000123"
	wizard.get_node("StudentParentId/ParentIdInput").text = "654321"
	await process_frame
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.3)
	_assert(wizard.get_node("GenderSelect").visible, "ID Back returns to Gender")
	_assert(GameState.get_new_game_registration().get("student_id") == "000123", "ID Back preserves Student ID")
	_assert(GameState.get_new_game_registration().get("parent_id") == "654321", "ID Back preserves Parent ID")
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.3)
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.3)
	wizard.get_node("NameGradeSelect/NameInput").text = " Student "
	await process_frame
	await _press(wizard.get_node("NameGradeSelect/Grade2") as BaseButton)
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.3)
	_assert(wizard.get_node("StudentParentId").visible, "Name/Grade Back returns to IDs")
	_assert(GameState.get_new_game_registration().get("student_name") == " Student ", "Name/Grade Back preserves name")
	_assert(GameState.get_new_game_registration().get("grade") == "Grade 2", "Name/Grade Back preserves grade")
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.3)
	await _press(current_scene.get_node("Button") as BaseButton)
	await _wait_seconds(0.5)
	_assert_scene(MAIN_MENU)
	_assert(GameState.get_new_game_registration().is_empty(), "cancelled registration is cleared")

func _run_gender_case(gender_value: String, final_grade: String) -> void:
	await _load_scene(MAIN_MENU)
	await _press(current_scene.get_node("VBoxContainer/NewGameBtn") as BaseButton)
	await _wait_seconds(0.5)
	var wizard := current_scene.get_node("TextureRect2")
	var gender_button_path := "GenderSelect/MaleBtn" if gender_value == "male" else "GenderSelect/FemaleBtn"
	await _press(wizard.get_node(gender_button_path) as BaseButton)
	_assert(wizard.get_node("GenderSelect").visible, "gender selection waits for Continue")
	await _press(wizard.get_node("GenderSelect/GenderContinue") as BaseButton)
	await _wait_seconds(0.3)
	wizard.get_node("StudentParentId/StudentIdInput").text = "12A456"
	await process_frame
	_assert(wizard.get_node("StudentParentId/StudentIdInput").text == "12456", "invalid Student ID characters are sanitized")
	wizard.get_node("StudentParentId/ParentIdInput").text = "12345"
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	_assert(wizard.get_node("ValidationPanel").visible, "invalid ID shows validation")
	_assert(String(wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel").text).contains("Parent ID"), "invalid Parent ID is named")
	wizard.get_node("StudentParentId/StudentIdInput").text = "000123"
	wizard.get_node("StudentParentId/ParentIdInput").text = "654321"
	await _press(wizard.get_node("StudentParentId/NextBtn") as BaseButton)
	await _wait_seconds(0.3)
	wizard.get_node("NameGradeSelect/NameInput").text = "   "
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	_assert(wizard.get_node("ValidationPanel").visible, "empty name is rejected")
	_assert(String(wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel").text).contains("name"), "empty name is named")
	wizard.get_node("NameGradeSelect/NameInput").text = " Student "
	await process_frame
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	_assert(wizard.get_node("ValidationPanel").visible, "missing grade is rejected")
	_assert(String(wizard.get_node("ValidationPanel/MarginContainer/ValidationLabel").text).contains("grade"), "missing grade is named")
	for grade_number in range(1, 7):
		await _press(wizard.get_node("NameGradeSelect/Grade%d" % grade_number) as BaseButton)
		_assert(GameState.get_new_game_registration().get("grade") == "Grade %d" % grade_number, "grade %d stores its exact value" % grade_number)
	_assert(GameState.get_new_game_registration().get("grade") == final_grade, "selected final grade is preserved")
	GameState.current_scene_path = "res://scenes/city_of_knowledge.tscn"
	GameState.current_task_index = 2
	GameState.battle_active = true
	GameState.current_battle_enemy_path = NodePath("stale_enemy")
	await _press(wizard.get_node("NameGradeSelect/Start") as BaseButton)
	await _wait_seconds(0.2)
	_assert_scene(LOADING)
	await _wait_seconds(1.0)
	_assert_scene(PLAYER_HOUSE)
	_assert(GameState.gender == gender_value, "%s gender is finalized" % gender_value)
	_assert(GameState.get_player_scene_path().ends_with("player_%s.tscn" % gender_value), "%s player scene is selected" % gender_value)
	_assert(GameState.student_id == "000123", "%s Student ID is finalized" % gender_value)
	_assert(GameState.parent_id == "654321", "%s Parent ID is finalized" % gender_value)
	_assert(GameState.player_name == "Student", "%s name is finalized" % gender_value)
	_assert(GameState.current_task_index == 0, "%s task state resets" % gender_value)
	_assert(not GameState.battle_active, "%s battle state resets" % gender_value)

func _load_scene(path: String) -> void:
	var result := change_scene_to_file(path)
	_assert(result == OK, "scene change accepted: %s" % path)
	await process_frame
	await process_frame

func _assert_scene(path: String) -> void:
	var current := current_scene.scene_file_path
	_assert(current == path, "expected %s, got %s" % [path, current])

func _press(button: BaseButton) -> void:
	button.emit_signal("pressed")
	await process_frame

func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
```

The complete probe will cover:

- Main Menu Leaderboard press → `leaderboard_scene.tscn`.
- Leaderboard Back press → `scenes/main_menu.tscn`.
- New Game press → `new_game_scene.tscn` with only Gender visible.
- Gender Back → Main Menu.
- Male and Female selection → Gender remains visible until Continue.
- Continue → IDs; ID Back → Gender with values preserved.
- Valid IDs → Name/Grade; Name/Grade Back → IDs with IDs preserved.
- Empty name/missing grade rejected.
- Each Grade 1–Grade 6 button sets exactly one selected grade.
- Valid Male and Female Play routes finalize the correct `GameState.gender`, `get_player_scene_path()`, IDs, name, grade, reset task/battle/scene state, and enter `LOADING` then `PLAYER_HOUSE`.

- [ ] **Step 2: Add static signal-connection assertions before changing connections.**

The probe or a companion PowerShell assertion must count the existing editor connections in `scenes/new_game_scene.tscn` and enforce this implementation rule:

- Male/Female selection and Play already have editor connections and must not receive duplicate programmatic `pressed` connections.
- Gender Continue, ID Next, and Grade 1–6 have no editor `pressed` connections and may receive exactly one guarded programmatic connection.
- Leaderboard has no editor connection and receives exactly one guarded programmatic connection.
- Back has no editor connection and receives exactly one guarded script connection.

- [ ] **Step 2a: Run a read-only signal audit before adding connections.**

```powershell
$sceneText = Get-Content -Raw .\scenes\new_game_scene.tscn
([regex]::Matches($sceneText, '\[connection signal="pressed" from="TextureRect2/GenderSelect/MaleBtn"')).Count
([regex]::Matches($sceneText, '\[connection signal="pressed" from="TextureRect2/GenderSelect/FemaleBtn"')).Count
([regex]::Matches($sceneText, '\[connection signal="pressed" from="TextureRect2/NameGradeSelect/Start"')).Count
([regex]::Matches($sceneText, '\[connection signal="pressed" from="TextureRect2/StudentParentId/NextBtn"')).Count
```

Expected counts before implementation: Male=1, Female=1, Start=1, ID Next=0. Preserve those counts and add exactly one guarded connection for each newly handled button.

- [ ] **Step 3: Run the probe and confirm it fails for the current route.**

```powershell
& .\tools\Godot_v4.6.1-stable_win64.exe --headless --path . --script tools/new_game_route_test.gd
```

Expected before implementation: non-zero failure because Leaderboard has no handler, the Leaderboard scene attaches the registration script, and Gender currently skips the ID panel. A signal-11 exit before SceneTree initialization must be recorded separately.

## Task 4: Repair Main Menu, Leaderboard, and touch-safe transition guards

**Files:**

- Modify: `scripts/main_menu_scene.gd`
- Modify: `scripts/new_game_btn.gd`
- Modify: `scripts/newgm_back.gd`
- Modify: `leaderboard_scene.tscn`
- Test: `tools/new_game_route_test.gd`

- [ ] **Step 1: Add the guarded Leaderboard handler to the existing Main Menu controller.**

Use the existing `Fade` and `VBoxContainer` nodes. Connect the existing `LeaderboardButton` once in `_ready()` and guard `_on_leaderboard_pressed()` with `_transitioning` and `button.disabled` before fading and calling the actual path:

```gdscript
const LEADERBOARD_SCENE_PATH := "res://leaderboard_scene.tscn"

@onready var leaderboard_button: Button = $LeaderboardButton
@onready var fade: CanvasItem = $Fade
@onready var menu: Control = $VBoxContainer

var _transitioning := false

func _ready() -> void:
	MusicManager.play_for_scene(scene_file_path)
	if not leaderboard_button.pressed.is_connected(_on_leaderboard_pressed):
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)

func _on_leaderboard_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	leaderboard_button.disabled = true
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(menu, "modulate:a", 0.0, 0.15)
	tween.parallel().tween_property(fade, "modulate:a", 1.0, 0.25)
	await tween.finished
	get_tree().change_scene_to_file(LEADERBOARD_SCENE_PATH)
```

- [ ] **Step 2: Remove the incorrect registration script from the Leaderboard background.**

Delete the `texture_rect_2.gd` external resource entry and the `script =` property from `leaderboard_scene.tscn`. Keep the existing background, leaderboard artwork, labels, and `Back-Button` node. Do not add gender/ID/grade dependencies.

- [ ] **Step 3: Make New Game and Back respond once to mouse or touch.**

Replace the mouse-only scene-change trigger in `scripts/new_game_btn.gd` and `scripts/newgm_back.gd` with guarded `button_down` and `button_up` handling so the same code path responds to touch and mouse. Preserve the current scale animations and fade tween. The New Game handler must call `GameState.begin_new_game_registration()` before changing scenes. The Back handler must first call `TextureRect2.handle_back()` when that method exists; otherwise it must use its exported `target_scene` and existing fade path.

Each script must connect only if `is_connected()` is false, set an `_transitioning` guard before awaiting any tween, and ignore later taps until the scene changes.

- [ ] **Step 4: Run the route probe and confirm only the registration panels remain failing.**

The Leaderboard route must now pass. The probe may still fail at Gender Continue/ID routing until Task 5 is implemented. Do not advance by weakening assertions.

- [ ] **Step 5: Commit the navigation changes.**

```powershell
git add -- scripts/main_menu_scene.gd scripts/new_game_btn.gd scripts/newgm_back.gd leaderboard_scene.tscn
git commit -m "fix: route leaderboard and guard menu transitions"
```

## Task 5: Implement the explicit registration wizard and touch-safe validation

**Files:**

- Modify: `scenes/texture_rect_2.gd`
- Modify: `scenes/new_game_scene.tscn`
- Test: `tools/new_game_route_test.gd`

- [ ] **Step 1: Update the scene resource without replacing existing grade assets.**

In `scenes/new_game_scene.tscn`:

- Keep `GenderSelect`, `StudentParentId`, `NameGradeSelect`, `Grade1`, `Grade2`, `Grade3`, `Grade4`, `Grade5`, and `Grade6` nodes and their current textures/layouts.
- Set `StudentParentId` initially hidden; the script will show it only at the IDs step.
- Add `GenderContinue` under `GenderSelect` using the existing `start.png` texture and the same `TextureButton`/Label styling as `NextBtn`, with label `NEXT` and a touch-friendly rectangle.
- Configure both ID fields with `max_length = 6` and the Godot numeric virtual keyboard enum value supported by the project’s Godot version.
- Move the existing validation panel one level under `TextureRect2` so it can display on both ID and Name/Grade steps without duplicating the panel style.
- Change only the final button label from `START` to `PLAY`; keep its texture, font, animation script, and layout.
- Leave the existing editor connections for Male/Female and Start intact.

- [ ] **Step 2: Replace the wizard controller with explicit step state, preserving existing animation helpers.**

Use an enum and one guarded transition path:

```gdscript
enum RegistrationStep { GENDER, IDS, NAME_GRADE }

var current_step := RegistrationStep.GENDER
var selected_gender := ""
var selected_grade := ""
var _step_transitioning := false
var _sanitizing_id := false
var _play_transitioning := false
```

On `_ready()`:

- play the existing menu music;
- read `GameState.get_new_game_registration()`;
- restore selected gender, ID text, name text, and selected grade when present;
- hide ID/Name panels and show Gender initially;
- connect only signals not already connected in the scene file;
- keep the current hover/press/grade scale animations;
- do not connect Male/Female/Start `pressed` again because the scene file already connects them.

- [ ] **Step 3: Make Gender selection store state without auto-advancing.**

The existing `_on_male_btn_pressed()` and `_on_female_btn_pressed()` handlers must:

```gdscript
func _on_male_btn_pressed() -> void:
	selected_gender = "male"
	GameState.update_new_game_registration({"gender": selected_gender})
	_apply_male_selected_visuals()

func _on_female_btn_pressed() -> void:
	selected_gender = "female"
	GameState.update_new_game_registration({"gender": selected_gender})
	_apply_female_selected_visuals()
```

`_on_gender_continue_pressed()` must reject an empty selection with a clear message, then call the guarded step transition to IDs. It must not call Play or the tutorial.

- [ ] **Step 4: Implement actual ID sanitization and exact validation.**

Connect `text_changed` for both fields exactly once. Keep the fields as strings and use the `GameState` helpers:

```gdscript
func _on_student_id_changed(new_text: String) -> void:
	_sanitize_id_field(student_id_input, new_text)
	GameState.update_new_game_registration({"student_id": student_id_input.text})

func _on_parent_id_changed(new_text: String) -> void:
	_sanitize_id_field(parent_id_input, new_text)
	GameState.update_new_game_registration({"parent_id": parent_id_input.text})

func _sanitize_id_field(field: LineEdit, value: String) -> void:
	if _sanitizing_id:
		return
	var sanitized := GameState.sanitize_six_digit_id(value)
	if sanitized == value:
		return
	_sanitizing_id = true
	field.text = sanitized
	field.caret_column = sanitized.length()
	_sanitizing_id = false
```

`_on_ids_next_pressed()` must validate Student ID first and Parent ID second using `is_valid_six_digit_id()`. It must show `Student ID must contain exactly 6 digits.` or `Parent ID must contain exactly 6 digits.` and return without clearing either field when invalid. Only both valid strings may advance to Name/Grade.

- [ ] **Step 5: Preserve name and exact Grade 1–6 selection.**

On name text change, update temporary `student_name` without trimming away the user’s in-progress spaces. On Play, trim leading/trailing spaces and reject an empty result. Each existing grade button must update exactly one `selected_grade`, deselect the other five using the existing visual scale/texture behavior, and store the exact existing values `Grade 1` through `Grade 6`. Do not change grade mapping or add group buttons.

- [ ] **Step 6: Implement Back transitions inside the wizard.**

Implement `handle_back()` in `scenes/texture_rect_2.gd`:

```gdscript
func handle_back() -> void:
	if _step_transitioning or _play_transitioning:
		return
	match current_step:
		RegistrationStep.GENDER:
			GameState.clear_new_game_registration()
			await _fade_and_change_scene_to_main_menu()
		RegistrationStep.IDS:
			await _show_step(RegistrationStep.GENDER)
		RegistrationStep.NAME_GRADE:
			await _show_step(RegistrationStep.IDS)
```

The `_show_step()` function must fade/hide only the existing panels, preserve the current `Fade`/menu behavior, update `current_step`, and restore controls from `GameState` when moving backward. It must set `_step_transitioning` before awaiting and clear it afterward. `_fade_and_change_scene_to_main_menu()` must use the existing `TextureRect2`/`Fade` tween before changing to `res://scenes/main_menu.tscn`.

- [ ] **Step 7: Implement Play validation and canonical tutorial entry.**

The existing editor-connected `_on_start_pressed()` must validate the full temporary dictionary again, then call `GameState.finalize_new_game_registration()`. On failure it must show the first precise validation error and leave all valid fields intact. On success it must queue the existing spawn and follow the existing loading route:

```gdscript
if not GameState.finalize_new_game_registration():
	_show_validation(_first_registration_error())
	return

GameState.queue_scene_spawn(
	GameState.START_SCENE_PATH,
	GameState.get_scene_fallback_spawn(GameState.START_SCENE_PATH),
	"down"
)

if ResourceLoader.exists(LOADING_SCENE_PATH):
	get_tree().change_scene_to_file(LOADING_SCENE_PATH)
else:
	get_tree().change_scene_to_file(GameState.START_SCENE_PATH)
```

Implement `_first_registration_error()` with this exact precedence so invalid input is reported without clearing valid fields:

```gdscript
func _first_registration_error() -> String:
	var values := GameState.get_new_game_registration()
	if String(values.get("gender", "")).to_lower() not in ["male", "female"]:
		return "Please select your gender."
	if not GameState.is_valid_six_digit_id(String(values.get("student_id", ""))):
		return "Student ID must contain exactly 6 digits."
	if not GameState.is_valid_six_digit_id(String(values.get("parent_id", ""))):
		return "Parent ID must contain exactly 6 digits."
	if String(values.get("student_name", "")).strip_edges().is_empty():
		return "Please enter your name."
	if String(values.get("grade", "")) not in GameState.VALID_REGISTRATION_GRADES:
		return "Please select your grade."
	return ""
```

Keep `LOADING_SCENE_PATH` and `GameState.START_SCENE_PATH` as the existing paths. Do not replace `interiors/player_house.tscn`, bypass loading when it exists, alter `TutorialNPC.gd`, or add a tutorial scene.

- [ ] **Step 8: Run the route probe for both genders and all Back paths.**

Expected: the probe reaches `res://interiors/player_house.tscn` for Male and Female, `GameState.get_player_scene_path()` returns `res://player/player_male.tscn` or `res://player/player_female.tscn`, and all invalid input/back assertions pass.

- [ ] **Step 9: Commit the wizard changes.**

```powershell
git add -- scenes/texture_rect_2.gd scenes/new_game_scene.tscn tools/new_game_route_test.gd
git commit -m "fix: restore validated new-game registration flow"
```

## Task 6: Add scene smoke coverage and run project-level validation

**Files:**

- Modify: `tools/scene_smoke_test.gd`
- Test: `tools/new_game_registration_test.gd`, `tools/new_game_route_test.gd`, existing `tools/validate_stabilization.py`, existing `tools/validate_theresian_scene_integrity.ps1`

- [ ] **Step 1: Include the actual Leaderboard scene in smoke coverage.**

Add exactly one entry to `ACTIVE_SCENES`:

```gdscript
	"res://leaderboard_scene.tscn",
```

Do not remove or reorder the existing exploration/tutorial scene coverage.

- [ ] **Step 2: Run parser/static validation.**

Run:

```powershell
& .\tools\Godot_v4.6.1-stable_win64.exe --headless --path . --editor --quit
python .\tools\validate_stabilization.py
powershell -ExecutionPolicy Bypass -File .\tools\validate_theresian_scene_integrity.ps1
```

Record each command’s exit code and complete output. Check changed scripts/scenes for missing node paths, invalid external resources, duplicate connections, and references to removed wizard nodes.

- [ ] **Step 3: Run scene/resource smoke validation.**

```powershell
& .\tools\Godot_v4.6.1-stable_win64.exe --headless --path . --script tools/scene_smoke_test.gd
```

Expected if the executable initializes: `SMOKE_TEST PASSED`. If the process crashes before `_initialize()`/SceneTree setup, report scene parser/static results separately and mark executable runtime unexecuted.

- [ ] **Step 4: Run focused registration tests again.**

```powershell
& .\tools\Godot_v4.6.1-stable_win64.exe --headless --path . --script tools/new_game_registration_test.gd
& .\tools\Godot_v4.6.1-stable_win64.exe --headless --path . --script tools/new_game_route_test.gd
```

Check the full requested matrix: Leaderboard route, Male/Female route, six-digit valid/invalid IDs, pasted invalid input, leading zeroes, empty name, no grade, single grade selection, Back preservation, cancel reset, no save before Play, final profile values, old scene/task/battle/resume reset, and canonical tutorial scene.

- [ ] **Step 5: Verify unrelated systems are unchanged in the final diff.**

```powershell
git diff --stat HEAD~3..HEAD
git status --short
git diff --name-only
git diff -- scripts/game_state.gd scenes/texture_rect_2.gd scenes/new_game_scene.tscn scripts/main_menu_scene.gd scripts/new_game_btn.gd scripts/newgm_back.gd leaderboard_scene.tscn tools/new_game_registration_test.gd tools/new_game_route_test.gd tools/scene_smoke_test.gd
```

Confirm no battle, quest, dialogue, mobile exploration, D-pad, interact, door/map, tutorial-content, or unrelated save files were staged or modified by this work. Preserve pre-existing dirty changes and do not use reset/checkout to clean them.

- [ ] **Step 6: Commit the smoke-test coverage only after verification.**

```powershell
git add -- tools/scene_smoke_test.gd
git commit -m "test: cover leaderboard and registration routes"
```

## Final handoff checklist

- [ ] Report exact modified files and actual scene paths.
- [ ] Report Main Menu → `res://leaderboard_scene.tscn` and Leaderboard Back → `res://scenes/main_menu.tscn`.
- [ ] Report the exact New Game sequence and both gender results.
- [ ] Report Student ID and Parent ID string validation/sanitization, including leading zeroes and pasted invalid text.
- [ ] Report temporary registration fields, cancellation behavior, and no-save-before-Play result.
- [ ] Report final Play ordering, new-game reset behavior, loading route, and `res://interiors/player_house.tscn` entry.
- [ ] Report Back behavior at every registration step.
- [ ] Report static/parser/resource/runtime/device status separately; explicitly state if Godot still signal-11 crashes before SceneTree initialization.
- [ ] List any remaining issues without claiming runtime or Android success unless the corresponding test actually executed.
