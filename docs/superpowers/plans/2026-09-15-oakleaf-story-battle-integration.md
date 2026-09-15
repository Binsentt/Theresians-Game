# Oakleaf Story and Battle Integration Plan

**Goal:** Align the canonical Oakleaf runtime with `Game Story.pdf` while preserving the original battle presentation, question source, save/load, telemetry, and released UI behavior.

## 1. Lock the baseline and write failing tests

- Record the canonical game and website release heads and protected dirty files.
- Add isolated Godot tests for same-scene encounter availability, current-grade Easy question scope, canonical enemy attribution, source-position autosave, all eight requested Oakleaf save/load states, Boss closure dialogue, Teacher proximity, and exact-scope question prefetch.
- Add a website component test proving visible per-quest duration wording is removed while backend timing evidence remains unchanged.
- Run each new focused test before implementation and retain its expected failure.

## 2. Repair only proven Oakleaf defects

- Keep encounter registrations structurally valid and evaluate quest prerequisites at interaction time.
- Remove the First Bandit's Grade 1 hardcode while retaining Oakleaf Easy difficulty.
- Populate `canonical_battle_id` from the active encounter context and preserve existing outbox event IDs.
- Apply the captured source scene/position before victory autosave clears encounter context.
- Add the source-compatible Boss defeat acknowledgement through the shared bottom dialogue system before completing Task 3.
- Expand only the Teacher interaction sensor at runtime; never change the Teacher's physical collision.
- Add an exact Grade/Difficulty question prefetch/cache and a compact non-blocking battle loading state without changing the original VS scenes or visual effects.

## 3. Preserve and prove existing behavior

- Re-run original Bandit/Boss male/female routing, four-choice mapping, HP/hearts, attacks, hit effects, victory/defeat, result idempotency, Terms, save isolation, and task-presentation tests.
- Verify Task 1, Task 2, all-five-plus-Boss Task 3 gating, Return-to-Teacher, and City unlock ordering.
- Verify all eight Oakleaf save/load checkpoints and six independent encounter IDs.
- Compare battle-scene structure before/after and confirm no scene resource changes.

## 4. Runtime and performance verification

- Start only the canonical Godot project through Godot MCP in localhost-only QA mode.
- Use disposable local backend fixtures for the full Oakleaf walkthrough; never send QA telemetry to production.
- Measure uncached and prefetched battle-trigger-to-question-visible time.
- Stop the QA runtime and clean disposable state after capture.

## 5. Minimal website presentation follow-up

- Sanitize only visible Per-Quest Evidence duration prose.
- Keep quest labels and graded evidence visible; preserve all backend timing, telemetry, fingerprint, AI grounding, and analytics calculations.
- Run focused/full frontend tests, production build, and diff checks without OpenAI calls.

## 6. Release gates

- Confirm zero script/parse/resource/runtime errors and `git diff --check` in both repositories.
- Request final scoped review, commit only the focused files, and verify clean committed diffs without protected dirty work.
- Fast-forward push the game release. If the website changed, fast-forward push it and deploy only the existing Railway production service through Railway MCP.
- Do not delete either Pinehill scene; report the canonical full scene, compatibility wrapper, Old Lady naming gap, and later-story inventory separately.
