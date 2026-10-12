# Exact Manual Save Snapshot and Historical Replay Design

## Goal

Make the manually selected save slot authoritative for gameplay restoration, including older progression snapshots, while isolating previous Learning Cycle gameplay replay from current academic records.

## Current context

- The canonical GameState builds manual save snapshots and restores them through `apply_save_data`; that path currently applies forward-only progression reconciliation to loaded state.
- Load Game selects and passes an exact manual-save path, but the reconciliation can still advance the selected snapshot.
- Learning-cycle annotation currently rejects valid prior-cycle saves. Website academic events are staged locally and RemoteSync handles separate academic commits and Screen Time sessions.
- Manual slots, hidden quest checkpoints, identity ownership, and current server cycle must remain separate and authoritative in their existing domains.

## Design

### Exact selected snapshot

Keep selected-path and Student/device ownership checks unchanged. Treat a snapshot as authoritative only when it is a manual save at the current `SAVE_VERSION`, has a positive manual slot sequence, and contains the current snapshot's core scene/location, position, task index, completion set, and progression-state fields. Restore that snapshot's scene/location, position, task/quest index, progression flags, lives, score, answer state, playtime snapshot, and player-facing task state without importing later in-memory, newer-slot, or hidden-checkpoint progression. Keep the legacy forward migration only for incomplete/older formats that require it. Loading must be read-only with respect to every manual slot; a later explicit manual save creates a distinct slot.

### Prior-cycle replay isolation

Allow an otherwise valid prior-cycle manual save to load as historical gameplay replay. Establish the server-authenticated current Learning Cycle before applying the gameplay snapshot and never temporarily assign the save's old cycle to the runtime session. Discard pending academic payloads embedded in the older save and do not stage replay answers/task events or enqueue academic progress commits into the current cycle. Persist a replay marker and the save's origin-cycle metadata on any later manual snapshot created during replay, so relaunch cannot accidentally turn replay into an ordinary current-cycle session. Keep Screen Time and session playtime on the normal current-session path. Same-cycle saves continue through normal academic behavior. If the current cycle cannot be established, fail closed for prior-cycle replay rather than replacing it with the save's old cycle. Existing identity, daily-time, manual-save commit-boundary, exit-discard, Game Over, and idempotency behavior remain unchanged.

### Hidden checkpoint precedence

An explicit Load action applies only the selected manual path. Hidden Game Over/quest recovery data remains a separate recovery source and must not merge forward into that load. Existing saves are neither rewritten nor migrated during load.

## Regression coverage

- Save an older and a newer snapshot and verify the older selection restores exact prior task/scene/position/flags while the newer slot bytes remain unchanged.
- Restore a pre-Forest-victory snapshot after later victories and verify all five bandits are undefeated and Pinehill is locked; restore a pre-Guard Pinehill snapshot after the later Wizard stage and verify Guards/Wizard state rewinds to that snapshot.
- Load a previous-cycle save without changing the current cycle or replaying its pending academic payload; verify the session still records Screen Time.
- Verify same-cycle continuation, separate new manual slot creation, selected-slot immutability, hidden-checkpoint non-precedence, Student/device isolation, and existing compatibility tests.

## Scope boundary

Expected product files are `scripts/game_state.gd`, `scripts/load_game_scene.gd`, and `scripts/remote_sync.gd` only where needed to enforce the historical-replay academic boundary, plus focused save/load/Learning Cycle/RemoteSync regression scenes and scripts. Do not change Website code, database schema, story content, manual-save ownership, other students' data, production configuration, or unrelated dirty files. No provider or production network calls are part of the tests.
