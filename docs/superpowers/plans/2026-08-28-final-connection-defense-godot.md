# Final Connection and Defense Godot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Godot-side canonical quest activity, scoped question exhaustion, lease-authenticated leaderboard consumption, and battle-life regression coverage without changing quests, battle rules, identities, release URL behavior, or local fallback semantics.

**Architecture:** Reuse the existing `GameState` task-transition signal, `RemoteSync` request/lease queue, `QuestionProvider`, `LeaderboardSceneController`, and save/lifecycle design. The server remains the only authority for activity logs, lifecycle, questions, and rankings.

**Tech Stack:** Godot 4.6, GDScript, existing headless tool-harness regressions, release worktree configuration.

---

## Scope and branch boundary

Implement only from a clean isolated worktree based on canonical
`codex/android-release-gate`. Do not edit its dirty release settings/scenes,
signing credentials, `export_presets.cfg`, or `project.godot`. Do not build an
APK, push, deploy backend, call OpenAI, create gameplay data, or change backend
schema in this Godot branch.

## Exact files and responsibilities

| Area | Files to modify or add |
| --- | --- |
| Scoped remote question consumption | `scripts/question_provider.gd`, `tools/question_provider_normalization_test.gd`, `tools/question_pool_exhaustion_test.gd` (new) |
| Canonical quest activity | `scripts/remote_sync.gd`, `tools/remote_sync_pending_queue_test.gd`, `tools/quest_activity_event_test.gd` (new) |
| In-game leaderboard | `scripts/remote_sync.gd`, `scripts/leaderboard_scene_controller.gd`, `tools/game_leaderboard_contract_test.gd` (new) |
| Battle-life preservation | existing battle lifecycle test plus `tools/battle_life_persistence_test.gd` (new if its assertions are not already present) |
| Final regression harness | existing `tools/production_question_api_smoke_test.gd`, `tools/http_api_production_config_test.gd`, QuizManager/traceability/lease tests and scene smoke scripts |

Before editing, locate the actual existing test filenames with `rg --files
tools | rg 'battle|quiz|trace|lease|provider|remote'`; use them rather than
creating an overlapping harness. No second HUD, dialogue system, notification
manager, lifecycle manager, or game leaderboard calculation is permitted.

## Task 1: exact-scope question-pool exhaustion

**Files:** `scripts/question_provider.gd`; existing provider normalization test; `tools/question_pool_exhaustion_test.gd`.

- [ ] Write the failing regression first. With a remote Grade 1/Easy/Basic Addition Set A scope containing valid four-choice questions, select every unique question and then request one more. Assert no question repeats before exhaustion, one `question_pool_exhausted` signal is emitted, only this scope's history is cleared, and the next request begins a new round inside the same scope.
- [ ] Add cases for two simultaneous scopes (different `learning_file_id`, grade, normalized difficulty, or topic); exhausting one must not change the other. Add malformed/three-choice candidates and assert they are excluded. Add no-candidate handling and assert a truthful unavailable/error result rather than a guessed question or fallback to an unrelated scope.
- [ ] Run the test to prove the current global `_history` and `candidates[0]` fallback permit a silent repeat.
- [ ] Replace the single history with a dictionary keyed by `question_set_id + grade + canonical difficulty + controlled topic`. Build the key only from the validated resolved remote scope. Retain existing Easy/Normal/Difficult legacy normalization and first-Bandit Grade 1/Easy/Basic Addition scope.
- [ ] When all valid candidates in that exact scope were used, emit a structured `question_pool_exhausted(scope_descriptor)` signal once per exhaustion, clear only that key's round history, and start a new round. Do not route it to another remote scope. Preserve local fallback only under the existing failed/empty remote-load contract; do not make exhaustion appear as transport failure.
- [ ] Re-run normalization, QuizManager provider, production question, traceability, and new exhaustion tests. Confirm question-set propagation is unchanged.

## Task 2: canonical idempotent quest event emission

**Files:** `scripts/remote_sync.gd`; `tools/remote_sync_pending_queue_test.gd`; `tools/quest_activity_event_test.gd`.

- [ ] Add failing tests using a stubbed active lease and `GameState.task_state_changed(previous_index, current_index, event)` signal. Assert one successful transition produces one lease-authenticated request to `/api/game/activity` with session ID, session credential, learning-cycle version, allowed event type, and a stable key. Assert canonical name/grade/section/Student ID are absent from the payload.
- [ ] Test that scene re-entry, notification timeout, dialogue rendering, a held Interact press, and an identical signal retry do not create a fresh event key. A retry after a transient request failure must reuse the exact same key and retain the event until acknowledged.
- [ ] Connect `RemoteSync` once to the existing `GameState.task_state_changed` signal after its normal initialization. Do not emit events from `QuestNotificationManager`, scene nodes, rendering callbacks, or dialogue timers.
- [ ] Build the deterministic key exactly as `cycle:<version>:task:<previous>:<current>:<event-type>:<event-key>`, where `event-key` comes from the authoritative task transition event. Queue the small canonical event through existing RemoteSync pending-request behavior only when a valid active lease/current-cycle descriptor is available.
- [ ] Treat server `{ duplicate: true }` as acknowledged success. On forbidden/expired/cycle-mismatched lease errors, do not fabricate a local Activity Log; use existing session/error handling and retain no unbounded retry loop.
- [ ] Re-run pending queue, lease payload, task/quest state, canonical profile, and new idempotency tests. Confirm quest order and notification behavior remain untouched.

## Task 3: lease-authenticated in-game leaderboard

**Files:** `scripts/remote_sync.gd`; `scripts/leaderboard_scene_controller.gd`; `tools/game_leaderboard_contract_test.gd`.

- [ ] First add controller tests proving it does not call the portal-only `/api/leaderboard/top-achievers` route directly. It must request data through RemoteSync and render a truthful loading, empty, or unavailable state without mock rows.
- [ ] Add RemoteSync request tests asserting `POST /api/game/leaderboard` carries only the active session ID, session credential, and current cycle context. Assert a response object accepts only `rank`, `display_name`, `grade`, `progress`, and `accuracy`; reject/ignore unexpected email, ID, parent, account, or management fields.
- [ ] Implement one `RemoteSync` leaderboard method that requires an active lease and calls the game endpoint. Use the normal configured production URL resolution; do not introduce arbitrary URL input or a portal JWT.
- [ ] Refactor `LeaderboardSceneController` to call that method, clear old rows before each request, and apply the newest response only. On empty/current-cycle no-data response, show a truthful no-ranking-yet state; on denied lease, show unavailable/error state without cached previous Student data.
- [ ] Add a two-request race test: an older response cannot overwrite a newer empty or successful response. Add a reset-cycle response test showing previous-cycle rows are not retained.
- [ ] Re-run production API config and release URL tests to prove DEBUG default, explicit production smoke, and release behavior remain unchanged.

## Task 4: preserve canonical battle lives across normal gameplay

**Files:** existing battle lifecycle harness; `tools/battle_life_persistence_test.gd` only if needed.

- [ ] Add regression coverage for the existing state contract: new game begins with `current_lives = max_lives = 3`; a loss decrements once; retry and victory do not restore player lives; scene/notification changes do not restore them; save/load persists the current value; only the existing Game Over/new-game reset path restores lives.
- [ ] Run the test against the current code. Do not change `GameState.current_lives`, enemy HP, battle damage, retries, quest triggers, or Game Over unless the new regression finds a verified direct defect.
- [ ] If a direct source fix becomes necessary, add the smallest assertion-backed change to `scripts/game_state.gd` or the current battle owner only; do not introduce a second life model. Otherwise commit test coverage only.

## Task 5: release-compatible regression gate

- [ ] Run the modified tests plus: QuestionProvider normalization, QuizManager provider, question-set/lease traceability, RemoteSync pending queue, canonical profile/New Game, lifecycle current/previous save tests, production API config, HUD runtime, battle lifecycle, mobile controls, Teacher House trigger, and project parse/main-menu smoke.
- [ ] Use the existing Godot 4.6 executable or Godot MCP project runner for a real parse/load. A process exit code is insufficient: inspect output and fail on `SCRIPT ERROR`, parse error, RemoteSync initialization error, or debugger break. Report unrelated existing UID/TileSet warnings separately only if non-blocking.
- [ ] Run `git diff --check`, review `git diff --name-only`, and confirm no signing credential, generated export artifact, `export_presets.cfg`, or `project.godot` local configuration entered the commit.

## Interaction and data-safety assertions

- [ ] First Bandit remains Grade 1 / Easy / Basic Addition; no question/quest/battle scope is changed.
- [ ] The current top-center Current Quest, D-pad, Interact, Settings, dialogue, mobile controls, Parent/Student login, canonical profile, online validation, timeout, and loading flows are outside this plan and must stay byte-for-byte untouched unless a focused test proves an unavoidable dependency.
- [ ] A Reset Top Achievers request made from the portal begins a new server learning cycle. Godot reads its normal lifecycle descriptor; existing old local saves remain labelled `Previous Learning Cycle`, blocked from Load, and available for manual Delete. Godot adds no new reset control or client lifecycle mutation.

## Commit strategy

1. Commit scoped QuestionProvider behavior/tests separately from RemoteSync activity/leaderboard behavior where possible.
2. Commit battle-life regression coverage independently if it changes no production source.
3. Never include generated `.godot` content, Android signing secrets, user-owned scene/resource edits, APKs, or export configuration in these commits.
4. Do not push, merge, export, or deploy. A later exact-commit approval is required after website/backend deployment and production health verification.

## Rollback strategy

Before integration, discard/revert only the focused commits from the isolated branch. After a future production deployment, backend idempotency is the protection against retry duplicates; a Godot rollback simply stops sending new canonical quest events and/or uses the prior controller. Do not use real game sessions, learning-cycle resets, local-save deletion, question publication, or production data as a rollback mechanism.
