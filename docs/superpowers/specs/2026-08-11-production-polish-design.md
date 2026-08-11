# Production Polish Design

## Goal

Polish the current main Godot 4 project without redesigning or rewriting unrelated gameplay: remove the stale `res://assets/hearts.png` dependency, use the provided application logo for project and Android launcher icon fallback, reuse the existing loading scene for startup/new-game/load-game/connection-error presentation, and play the provided Game Over effect once per Game Over scene entry.

## Audited assets and existing behavior

- Application icon source: `res://Images/Application-Logo.png` (1536×1536).
- Loading background source: `res://Images/Loading Backgroud.png` (1536×1024). The existing filename is misspelled; it remains unchanged to preserve user-owned assets.
- Game Over effect: `res://bg-musics/game over sound effects.mp3`, already imported with looping disabled.
- The only runtime `res://assets/hearts.png` reference is `res://player/life.tscn`. Existing battle and HUD scenes instantiate this scene, and the project already contains `res://assets/hearth.png` as the working battle-safe texture.
- The existing loading scene uses animated dots and currently routes to `GameState.current_scene_path`. New Game already enters this scene; Load Game currently bypasses it.
- No networking/API runtime implementation exists, so connection failure support is presentation-only and callable by future integration code.
- The existing Game Over scene is `res://scenes/game_over_scene.tscn`; no second Game Over system is introduced.

## Architecture

### Heart cleanup

Keep the current life scene and battle/HUD node structure intact. Replace only its missing texture resource path with `res://assets/hearth.png`. This eliminates the obsolete dependency while preserving all life counts, damage logic, battle nodes, animations, and sizing code.

### Branding and startup

Set `application/config/icon` to the existing application logo. Set the Godot boot splash to the existing loading background with filtered aspect-preserving scaling, and make the reusable loading scene the run main scene. With no prepared request, the loading controller treats the entry as `STARTUP` and routes to the existing main menu.

Add an Android export preset beside the existing Windows preset. Set its classic launcher icon to `Application-Logo.png`. Leave separate adaptive background/foreground images empty so Godot's documented fallback uses the configured main/project icon rather than duplicating the complete logo into both adaptive layers. Preserve the existing Windows preset and do not invent keystores or signing secrets.

### Reusable loading controller

The existing `loading_screen.gd` owns a small static request object with four modes: `STARTUP`, `NEW_GAME`, `LOAD_GAME`, and `CONNECTION_RETRY`. Public preparation methods set the next mode and destination before changing to `res://scenes/loading_screen.tscn`.

The scene displays `Loading Backgroud.png` full-rect, then a subtle bottom-center panel containing animated `Loading`, `Loading.`, `Loading..`, `Loading...` text and an indeterminate fantasy-style progress bar. No numeric percentage is shown. The destination is changed only after the loading delay and after confirming the destination resource exists; an invalid destination produces a scene-loading error rather than a connection message.

New Game explicitly prepares `NEW_GAME` for `res://interiors/player_house.tscn` and retains its existing GameState reset/spawn behavior. Load Game applies the selected save exactly as before, then prepares `LOAD_GAME` using the normalized saved scene and passes through the same loading scene.

### Connection failure presentation

Because the project has no network/API code, no fake check is added. The loading controller exposes a public `show_connection_error(message, retry_callback)` method. It stops loading animation, shows the approved connection text, and enables Retry only when a valid callback exists. Return to Main Menu is always available. The normal destination-loading failure uses a separate loading-error message and cannot be mislabeled as a Wi-Fi failure.

### Game Over audio

Attach one `AudioStreamPlayer` to the existing Game Over scene, using the provided non-looping MP3 and the existing `SFX` bus. On scene readiness, stop the existing music through `MusicManager` and call a guarded method that plays the effect once. Repeated calls do not restart or overlap it. The player stops when leaving the scene, while all existing buttons, visual nodes, reset behavior, and navigation remain unchanged.

## Error handling

- Missing loading destinations display an explicit loading error and a Return to Main Menu action.
- Connection Retry is hidden/disabled until future networking code supplies a valid callable.
- No OS-level restart or process spawning is added.
- Android export signing remains a device/release-operations responsibility; no credentials are stored.

## Validation

Add a focused Godot regression scene that checks resource paths, project/export settings, loading scene nodes/modes/routes, connection presentation, and Game Over audio configuration. Run it red before implementation and green afterward through Godot MCP where the engine can initialize. Also run parser/resource scans, scene/resource existence checks, signal/node checks, a full `res://assets/hearts.png` scan, and `git diff --check`. Android launcher appearance, boot splash behavior on device, APK/AAB signing/export, and audio behavior on physical hardware remain device tests.

## Scope protection

Only the life resource, branding/export settings, reusable loading files and their two callers, existing Game Over scene/controller, focused tests, and the supplied assets/import metadata are in scope. Battle logic, quests, dialogue, save data semantics, registration, navigation managers, mobile controls, interactions, and database/API architecture remain unchanged.
