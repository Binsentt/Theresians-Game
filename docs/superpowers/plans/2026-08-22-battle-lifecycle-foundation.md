# Battle Lifecycle Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide centralized encounter retry, safe battle outcome handling, and shared question scope without inventing absent story progression.

**Architecture:** `GameState` holds the serializable encounter context and exposes lifecycle methods. `QuizManager` emits one terminal result, while a reusable encounter adapter enters the existing battle overlay and reports the result back to `GameState`. Existing quest UI remains the only owner that advances an existing task.

**Tech Stack:** Godot 4.6, GDScript, existing `GameState`, `QuestionProvider`, `QuizManager`, `QuestNotificationManager`.

---

### Task 1: Establish the encounter-state contract

**Files:**
- Modify: `scripts/game_state.gd`
- Test: `tools/battle_lifecycle_test.gd`
- Test scene: `tools/battle_lifecycle_test.tscn`

- [x] Add a failing test for a new encounter capturing ID, source scene, exact position, task index, and optional scope.
- [x] Run the test and confirm it fails because the lifecycle API is absent.
- [x] Add `begin_encounter`, `record_encounter_loss`, `record_encounter_victory`, `get_encounter_question_scope`, and additive save/load serialization in `GameState`.
- [x] Run the test and confirm capture, loss one/two, and loss three checkpoint reset pass.

### Task 2: Make QuizManager report a single terminal outcome

**Files:**
- Modify: `Battle/Battle-Enemy/QuizManager.gd`
- Test: `tools/battle_lifecycle_test.gd`

- [x] Add a focused test that expects `battle_finished(success)` exactly once when either side reaches zero hearts.
- [x] Add the signal and a guarded terminal-outcome path after existing heart damage, preserving answer scoring and per-question RemoteSync.
- [x] Run the test and confirm three player/enemy hearts and a single victory signal remain correct.

### Task 3: Integrate the existing overlay owner

**Files:**
- Modify: `world/QuestUI.gd`
- Test: `tools/battle_lifecycle_test.gd`

- [x] Update `QuestUI` only at its existing battle task to capture context, wait for `battle_finished`, and delegate outcomes to `GameState` before advancing.
- [x] Preserve loss-without-advancement and victory-only advancement without creating new quest order.

### Task 4: Restore the broken Teacher contract

**Files:**
- Modify: `NPC/Teacher.tscn`
- Test: `tools/battle_lifecycle_test.gd`

- [x] Inspect the unreferenced male boss-bandit scene and leave it visual-only because it lacks the required question/health contract.
- [x] Replace Teacher's missing script reference with the existing interaction adapter only; do not add final-boss sequencing.
- [x] Run the contract tests and semantic diagnostics.

### Task 5: Apply scope and retry notifications safely

**Files:**
- Modify: `scripts/question_provider.gd`
- Modify: `scripts/quest_notification_manager.gd`
- Test: `tools/battle_lifecycle_test.gd`

- [x] Add focused tests for map-derived canonical difficulty and one-per-threshold playtime warnings.
- [x] Implement scope resolution from the active encounter/current map without topic inference.
- [x] Add one generic notification entry point rather than NPC-specific UI systems; allow the server playtime warnings during an active battle.
- [ ] Run all focused tests, including the known pre-existing question-provider normalization test.

### Task 6: Verify and checkpoint

**Files:**
- Test: `tools/battle_lifecycle_test.gd`
- Test: `tools/question_set_traceability_test.tscn`

- [ ] Run Godot focused tests and project parsing.
- [ ] Run production-question smoke and local-fallback contract tests without production writes.
- [ ] Run semantic diagnostics for each changed script and `git diff --check`.
- [ ] Commit only the battle-lifecycle branch after all tests pass.
