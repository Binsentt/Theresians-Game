# Production Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved heart cleanup, Android branding, reusable loading presentation, connection-error UI, and Game Over sound to the current main Godot project without changing unrelated gameplay.

**Architecture:** Preserve the existing life, loading, save-selection, New Game, and Game Over entry points. Make narrow resource/configuration changes, expand the single loading scene into a mode-aware reusable controller, and attach one guarded SFX player to the existing Game Over scene.

**Tech Stack:** Godot 4.6.1, GDScript, `.tscn` resources, `project.godot`, `export_presets.cfg`, PowerShell static validation, Godot MCP runtime validation.

---

### Task 1: Add production-polish regression checks

**Files:**
- Create: `tools/validate_production_polish.ps1`
- Create: `tools/production_polish_test.gd`
- Create: `tools/production_polish_test.tscn`

- [ ] **Step 1: Write the failing static validator**

The validator must read the actual project files and fail until all of these are true: the obsolete heart path is absent from runtime resources; project icon, boot splash, and main scene reference the supplied assets/loading scene; the Android preset uses the application logo; the loading scene contains one background, one progress bar, animated-dot/progress timers, and one initially hidden error panel; New Game and Load Game prepare their modes; and the Game Over scene contains one non-looping SFX player.

- [ ] **Step 2: Write the failing Godot scene test**

The test scene instantiates `res://scenes/loading_screen.tscn`, verifies the background resource path, exercises dot and indeterminate-bar updates, prepares `NEW_GAME` and `LOAD_GAME` requests, calls `show_connection_error`, and verifies the existing Game Over scene's `AudioStreamPlayer` stream and SFX bus.

- [ ] **Step 3: Run both checks and verify RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tools/validate_production_polish.ps1
```

Expected: nonzero with missing production-polish requirements.

Run the test scene using Godot MCP. Expected: test failures caused by the missing background/mode/error/audio implementation, or an explicitly reported pre-SceneTree engine crash.

### Task 2: Remove the obsolete heart dependency

**Files:**
- Modify: `player/life.tscn:3`

- [ ] **Step 1: Replace only the stale texture path**

Use the existing battle-safe resource while preserving the scene nodes and UID:

```ini
[ext_resource type="Texture2D" uid="uid://b6hhnyruov6t5" path="res://assets/hearth.png" id="1_ck4jm"]
```

- [ ] **Step 2: Verify the focused heart checks turn green**

Run a runtime-resource scan excluding documentation/import caches. Expected: no `res://assets/hearts.png`; `player/life.tscn` and `ui/battle_life_display.tscn` still load and retain their existing life nodes.

### Task 3: Configure project startup and Android branding

**Files:**
- Modify: `project.godot:12-17`
- Modify: `export_presets.cfg`
- Add existing user assets to the scoped commit: `Images/Application-Logo.png`, `Images/Application-Logo.png.import`, `Images/Loading Backgroud.png`, `Images/Loading Backgroud.png.import`

- [ ] **Step 1: Preserve existing project settings and update branding/startup**

Keep the current application name and autoloads, then set:

```ini
run/main_scene="res://scenes/loading_screen.tscn"
config/icon="res://Images/Application-Logo.png"
boot_splash/image="res://Images/Loading Backgroud.png"
boot_splash/show_image=true
boot_splash/stretch_mode=1
boot_splash/use_filter=true
```

- [ ] **Step 2: Preserve the Windows preset and add an Android preset**

Append a standard Android preset with `export_filter="all_resources"` and:

```ini
launcher_icons/main_192x192="res://Images/Application-Logo.png"
launcher_icons/adaptive_foreground_432x432=""
launcher_icons/adaptive_background_432x432=""
launcher_icons/adaptive_monochrome_432x432=""
```

The empty adaptive layers intentionally use Godot's documented main/project-icon fallback and avoid inventing new branding artwork. Do not add keystore paths or credentials.

- [ ] **Step 3: Verify configuration paths resolve**

Run the static validator and Godot MCP project info/resource inspection. Expected: existing image resources resolve and no Windows preset value is removed.

### Task 4: Implement the reusable loading scene

**Files:**
- Modify: `scripts/loading_screen.gd`
- Modify: `scenes/loading_screen.tscn`
- Modify: `scenes/texture_rect_2.gd:31-33,374-384`
- Modify: `scripts/load_game_scene.gd:1-35`

- [ ] **Step 1: Implement request modes in the existing controller**

Add `STARTUP`, `NEW_GAME`, `LOAD_GAME`, and `CONNECTION_RETRY` enum values plus static preparation methods. Default startup routes to `res://scenes/main_menu.tscn`; New Game receives `res://interiors/player_house.tscn`; Load Game receives the normalized saved scene. Consume and reset each request when the loading scene starts.

- [ ] **Step 2: Implement safe destination handling**

After the existing short delay, use `ResourceLoader.exists(destination)` before changing scene. Missing destinations display a loading error with Return to Main Menu and are not labeled as connection failures.

- [ ] **Step 3: Add the approved loading presentation**

Replace the plain color background with one full-rect `TextureRect` using `res://Images/Loading Backgroud.png`. Place one subtle bottom-center panel above it with `Loading` animated dots and one `ProgressBar` configured with `show_percentage = false`. Drive the bar from a short repeating timer and wrap its value smoothly without displaying fake numeric progress.

- [ ] **Step 4: Add callable connection-error presentation**

Add one initially hidden error panel with title, message, Retry, and Return to Main Menu buttons. `show_connection_error(message, retry_callback)` exposes it; Retry is visible only for a valid callable. No networking, URL, restart process, or fake connectivity check is added.

- [ ] **Step 5: Route New Game through the mode API**

Immediately before the existing transition to `res://scenes/loading_screen.tscn`, call:

```gdscript
LoadingScreenController.prepare_new_game(PLAYER_HOUSE_SCENE_PATH)
```

Preserve registration finalization, GameState resets, spawn queueing, and the Player House destination.

- [ ] **Step 6: Route Load Game through the mode API**

After `GameState.load_save()` succeeds and returns its normalized scene path, call:

```gdscript
LoadingScreenController.prepare_load_game(scene_path)
get_tree().change_scene_to_file(LOADING_SCENE_PATH)
```

Keep the existing load/apply/spawn behavior unchanged and add a transition guard for repeated save-entry taps.

- [ ] **Step 7: Run focused tests GREEN**

Run the static validator and Godot MCP test scene. Expected: loading resource/mode/animation/route/error checks pass, or runtime is explicitly unexecuted if Godot crashes before SceneTree initialization.

### Task 5: Integrate Game Over audio once

**Files:**
- Modify: `scenes/game_over_scene.tscn`
- Modify: `scripts/game_over_scene.gd`
- Add existing user asset to the scoped commit: `bg-musics/game over sound effects.mp3`, `bg-musics/game over sound effects.mp3.import`

- [ ] **Step 1: Add one SFX player to the existing scene**

Add one external `AudioStreamMP3` resource for the supplied MP3 and one `AudioStreamPlayer` named `GameOverSound`, with `bus = &"SFX"` and no autoplay/loop override.

- [ ] **Step 2: Guard playback in the existing controller**

Keep the existing button/reset/navigation behavior. In `_ready()`, call `MusicManager.stop_music()` and a guarded `_play_game_over_sound_once()` method. The boolean guard is set before `play()` so repeated calls never restart or stack the effect. Stop the player from `_exit_tree()` if it is still playing.

- [ ] **Step 3: Run the Game Over regression checks GREEN**

Expected: exactly one GameOverSound node, the correct MP3 path, SFX bus, looping disabled by import configuration, and one guarded playback call per scene entry.

### Task 6: Full verification, review, and scoped commit

**Files:**
- Verify every file listed above and no unrelated gameplay file.

- [ ] **Step 1: Run complete verification**

Run the focused PowerShell validator, Godot MCP project/scene/resource validation, parser probes, missing-resource scan, node/signal count checks, obsolete-heart scan, and `git diff --check`.

- [ ] **Step 2: Review the scoped diff**

Confirm no battle damage/effects, quest, dialogue, registration, navigation manager, mobile control, interaction, or save-data semantics changed. Request an independent code review and resolve all Critical/Important findings.

- [ ] **Step 3: Stage only the scoped paths**

Explicitly stage the configuration, supplied assets/imports, loading/life/Game Over files, tests, spec, and this plan. Verify the staged whitelist before committing.

- [ ] **Step 4: Commit**

```powershell
git commit -m "feat: polish loading branding and game over audio"
```

- [ ] **Step 5: Record device limitations**

Report Android SDK/export/signing availability, APK/AAB and launcher-icon device testing, boot splash appearance, physical-device audio, and any pre-SceneTree Godot crash without claiming unexecuted tests passed.
