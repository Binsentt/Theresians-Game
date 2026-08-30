# Final Testing Defects: Godot Implementation Plan

This plan implements only the Godot portion of the reviewed Final Testing Defect Patch Specification at the website/backend planning worktree:

C:/Users/vince/Documents/Capstone-Project/Theresian's Quest- Web/.worktrees/final-testing-defects-web-spec-plan/capstone/docs/defense/final-testing-defect-patch-spec.md

## Baseline and isolation

- Worktree branch: codex/final-testing-defects-godot-spec-plan.
- Frozen base: f7811c688876dc52f316a9322603275b323d8102.
- The already signed f7811c6 APK remains unchanged and is not rebuilt in this work.
- No online request, production identity, backend change, Railway action, APK build, or push is allowed.

## Verified audit facts

- The canonical exploration mover is scripts/top_down_player.gd, inherited by player_male.gd and player_female.gd.
- It is a CharacterBody2D, sets velocity to InputManager.get_movement_vector() times move_speed, then uses move_and_slide().
- move_speed is currently 100.0 pixels per second. Keyboard and D-pad share the exact same InputManager vector and therefore the same speed owner.
- The visible project title is Capstone Theresians Quest_v6 in project.godot application/config/name.
- The Android package ID remains com.theresiansquest.game and must not be edited.
- Existing decorative NPC scene roots are AnimatedSprite2D. The city_npc instance in scenes/city_of_knowledge.tscn at its existing placement has no quest, dialogue, Teacher, Bandit, or tutorial script.
- scripts/npc_collision_manager.gd dynamically gives matching NPC sprites a foot collision, so an opt-in moving wrapper must be proven against the existing collision arrangement before any broader reuse.

## Exact source scope

Expected implementation files:

- scripts/top_down_player.gd
- project.godot
- scripts/decorative_npc_wanderer.gd (new)
- NPC/Npc/decorative_wandering_city_npc.tscn (new)
- scenes/city_of_knowledge.tscn
- a focused player-speed test under tools/
- a focused decorative-NPC wander test under tools/

No existing NPC asset, Teacher, tutorial NPC, Bandit, boss, quest script, dialogue script, InputManager, QuestNotificationManager, GameState quest logic, RemoteSync, QuestionProvider, QuizManager, Settings scene, Save/Load code, export preset, or Android signing file is in scope.

## Step 1: player-speed test before code

Add a focused regression that proves:

1. the canonical move_speed baseline is 100.0 before the patch and then 60.0 after the patch;
2. a keyboard-shaped and a D-pad-shaped cardinal InputManager vector both yield velocity magnitude 60.0;
3. zero input remains zero;
4. movement continues to call CharacterBody2D move_and_slide();
5. no diagonal policy is changed by this patch.

The implementation change is one value only: move_speed changes from 100.0 to 60.0. No animation rate, timer, collision, trigger, or InputManager behavior changes.

## Step 2: visible title test before code

Add a focused project-settings assertion that application/config/name equals Theresian's Quest and that the Android export package/application identifier remains com.theresiansquest.game.

Change only project.godot application/config/name to Theresian's Quest. Audit export_preset values before implementation; do not edit export_presets.cfg unless a verified release-label override prevents project.godot from controlling the visible title. Signing values and ETC2/ASTC settings are not touched.

## Step 3: opt-in decorative wanderer test before code

The first and only roaming candidate is City of Knowledge's existing city_npc. It is classified SAFE DECORATIVE after the audit found no attached interaction/quest script.

Create a small, reusable CharacterBody2D wrapper scene rather than mutating the shared city_npc asset or converting all AnimatedSprite2D scenes. The wrapper owns:

- an instance of the unchanged city_npc sprite;
- one foot CollisionShape2D configured to use the existing NPC collision layer/mask contract after a focused fixture confirms its dimensions;
- origin/home position;
- exported wander radius;
- exported walk speed below the player speed;
- a DecorativeNpcWanderer child script.

The script uses timer/state transitions, not pathfinding every frame:

Idle -> choose one of Up, Down, Left, Right -> walk a bounded short leg with velocity and move_and_slide -> idle.

It never selects a diagonal. Before it starts a leg it validates that the target remains within the origin radius. If collision blocks progress or the candidate leaves the radius, it stops and enters idle before selecting again. It uses only existing walk_up, walk_down, walk_left, and walk_right animations. On idle it pauses the latest directional animation/frame instead of inventing missing idle art.

The component treats GameState DIALOGUE as a global pause condition. It sets velocity to zero and pauses its timer while dialogue is active, then waits one normal idle interval after exploration resumes. This does not alter DialoguePanel or interaction code; it only makes the one decorative actor stationary during an existing dialogue.

Tests must prove in a local scene fixture:

1. idle produces zero velocity;
2. each selected leg is cardinal;
3. velocity magnitude equals the exported NPC speed and is below 60;
4. a configured radius is never exceeded;
5. a collision fixture blocks the CharacterBody2D;
6. DIALOGUE stops motion and EXPLORATION resumes only after idle;
7. no duplicated wrapper/NPC instance is created;
8. Teacher, Bandit, tutorial, and existing dialogue NPC scene paths are not changed.

## Step 4: scene integration

In scenes/city_of_knowledge.tscn, replace only the existing city_npc instance with the wrapper at the identical current position. Preserve the city scene's other NPCs, TileMaps, collision, doors, quest nodes, enemies, resource ordering unless Godot requires one directly related resource reference, and all scene transitions.

Before finalizing the scene hunk, run a fixture with the existing NpcCollisionManager. If its dynamic StaticBody2D is duplicated inside the new wrapper or conflicts with the CharacterBody2D collision, add the narrowest opt-in skip marker recognized only by the wrapper; do not change collision behavior for every existing NPC.

## Frozen-system regression gate

Run the existing deterministic regressions after the focused tests:

- project parse and Main Menu;
- Player House and Oakleaf entry;
- Tutorial, Teacher House, Task Trigger/Complete, DialoguePanel, quest order, and Bandit trigger;
- first-Bandit Grade 1 / Easy / Basic Addition scope, QuestionProvider, QuizManager, four-choice, exhaustion, traceability, battle lifecycle, and player-life persistence;
- Save, Load, previous-cycle protection, life persistence, and manual save delete;
- Settings Resume, Save, Load Game, Exit, hitbox isolation, volume sliders, and pause behavior;
- D-pad, Interact, keyboard/D-pad parity, and no-diagonal behavior;
- profile validation, production API configuration, lease, heartbeat, activity, leaderboard, result, and progress tests.

Treat ordinary existing TileSet/UID diagnostics as non-blocking only if graphical smoke has no visible breakage and no SCRIPT ERROR. Any new SCRIPT ERROR, trigger failure, collision failure, or scene parse failure blocks the patch.

## Commit and rollback

Commit only the title, player speed, opt-in wrapper, city scene hunk, and focused tests after all gates pass. Preserve all dirty main-worktree files and existing release configuration.

If a frozen regression fails, remove or revert only the focused change in this isolated worktree. Do not build an APK, push, or integrate the Godot patch until reviewed.
