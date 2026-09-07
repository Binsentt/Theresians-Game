# Original gameplay: focused canonical repair evidence

Starting Godot HEAD: `843b0b7f8d38d4417cfce9f566863505aa9e2042`.
Authoritative ZIP: `C:\Users\vince\Downloads\capstone-theresians-quest6.zip`.
SHA-256: `CC982451B3D25876082E9F71203CF6232B6D5BD8BF449845DEE0D502EE1C9173`.

The ZIP's exact three-task flow and missing later quest chain are documented in `2026-09-07-original-quest-flow-audit.md`. This repair does not invent or reorder quests. All Godot engine operations used Godot MCP and the canonical project. Runtime fixtures disconnect production observers, substitute an in-memory HTTP/QuestionProvider stub, and remove only their unique test saves. Normal user saves, accounts, production, APKs and other projects are untouched.

## Proven repairs

| Product file / location | Before | Focused repair |
|---|---|---|
| `scripts/remote_sync.gd::_activity_metadata_for_event` | `quest_completed` selected the next task. Teacher completion acquired the Bandit label, and terminal completion disappeared when the next index had no task. | Select the previous index for both completion event types; explicit Tutorial metadata, route, stable event keys and lease identity stay intact. |
| `Battle/Battle-Enemy/QuizManager.gd::_finish_battle` | Immediate `battle_finished` caused the existing quest owner to free the original VS scene while its final hit effect was still playing. The early-emission integration appears at `0f739b90f46429eebf8386d94835d6cc1dd53aab`. | Keep the existing one-shot guard and disabled choices, then await the active original terminal animation before emitting. No effect duration, resource, heart, portrait, question UI or battle scene was replaced. |
| `scenes/oak_leaf_village.tscn`: `girl_npc/Visual`, `villager-female/Visual`, `NPC1/Area2D` | The current working scene had lost the two greeting scripts. Both interaction components still targeted their Visual child. NPC1 also lacked the body-exit connection, so ACT could reopen its greeting after leaving the region. | Restore only the existing greeting script and shared host paths; serialize proper editable-instance metadata for both wrappers; reconnect NPC1 exit to its existing handler. No transforms, animation properties, sensors, colliders, spawns, map data, dialogue content, HUD or trigger coordinates changed. |

The two Visual overrides were already present in HEAD but used `editable_children = true` rather than `[editable path=...]`; the starting editor-saved scene had dropped them. The working-file restoration reinstates these bindings. The commit corrects the serialization metadata rather than absorbing unrelated editor-save differences. Packing, saving and reloading a temporary scene proves both bindings survive serialization.

## Runtime verification

| Canonical MCP scene | Red gate | Final gate |
|---|---|---|
| `tools/original_flow_ingestion_test.tscn` | 18 pass / 2 fail: wrong Teacher label, dropped terminal event | 64 pass / 0 fail, including expanded actual result/progress serialization |
| `tools/original_battle_presentation_test.tscn` | 530 pass / 64 fail: terminal effect/signaling order across 16 win/loss cases | 594 pass / 0 fail |
| `tools/original_interaction_regression_test.tscn` | 153 pass / 11 fail: two missing scripts and stale NPC1 proximity | 190 pass / 0 fail, including 18 pack/save/reload assertions |
| Existing `tools/zip_map_restoration_test.tscn` | Prior map restoration baseline | 99 pass / 0 fail in this task |

Final total: **947 passed assertions, 0 failed**. Final logs contain **0 SCRIPT ERROR and 0 resource/parse errors**. Existing UID warnings are not represented as errors or silently cleaned up.

Battle verification loads all eight original male/female Bandit, Boss, Teacher and Wizard VS scenes; uses an offline QuestionProvider to fill the original question label and four choices; verifies correct/wrong feedback, three original local hearts, original one-second terminal effects, duplicate-answer guard and one completion signal. These resources match the developer ZIP; the missing later quest routes remain a separate blocker.

Interaction verification uses real proximity shapes and actual touch press/hold/release: Tutorial, Teacher, four Oakleaf NPCs, and both First Bandit gender routes. Keyboard continuation and final deliberate close retain their existing behavior. Actual answers complete the original First Bandit once and do not redisplay the Teacher House objective. No full Boss/return-Teacher/City progression is claimed.

Ingestion verification invokes actual RemoteSync code and JSON serialization into a stub: task event labels/duplicate acknowledgment; correct/wrong result scores, Grade 1/Easy, profile trace references, active lease, learning cycle and question_set_id; actual saved progress fields and timestamps. The corresponding backend identity/relationship/lease, ingestion and aggregation tests use mocked databases. This is local boundary verification, not a production database end-to-end test.

The map gate reloads Oakleaf, City and Pinehill, checks original texture bindings and all 22 TileMap layers, NPC spawns, actual door transitions, frozen quest checkpoint, lower-middle dialogue at desktop/mobile viewport sizes, ACT availability, and three-second top-center Task Complete without moving the top HUD/timer.

## Preservation and source control

`tools/original_flow_scope.py verify` reverses only the allowed changes and matches the starting byte hashes. **1,829 other tracked Godot files remain byte-identical** to the captured task-start working state. Oakleaf's entire remaining source matches its saved pre-edit bytes. Unrelated product delta count: **0**.

Existing staged QuizManager answer-statistics lines, Question deletions, export/project settings, UID edits, pending GameState load reconciliation, QuestUI gender routing and other dirty work remain outside this commit. Tests run against that explicitly preserved canonical working tree. The resulting commit alone is therefore not a clean-tree reproduction of all pre-existing pending integrations. The temporary-index commit helper retains the original staged content instead of overwriting it.

No notification slide/fade behavior was changed. The previously restored map appearance, dialogue placement and Task Complete placement remain frozen.

## Controller baseline distinction (resolved by the user)

The ZIP contains blue/gold direction buttons labeled UP/LT/RT/DN, sized 68x56, and a rectangular 132x88 ACT button. The preserved canonical scene uses brown/gold 76x76 arrow buttons and a round 112x112 ACT button, with its already-working touch-hold integration. The canonical controller scene is traced to the repository's initial upload `de77b52`; current Git history does not identify a later visual-edit commit establishing why it differs from the ZIP.

The user previously explicitly froze the approved current controller design, while the latest task names the ZIP baseline. This conflict was reported and the user explicitly answered: **Keep the current approved brown controller.** No controller visual, asset, layout, action or lifecycle source was changed. Current-controller interaction is verified; exact ZIP visual equivalence is not claimed or requested after this clarification.

## Remaining boundaries

- The supplied ZIP implements neither the remembered required-Bandit count/Boss/Teacher-return/City-unlock chain nor City/Pinehill continuation. The authoritative finite milestone list, triggers and saved/backend completion evidence are still needed before implementing those routes or calculating overall progress.
- The exact production record responsible for the observed 75% was not accessed. Local audit proves an unverified saved percentage was displayed as Total Progress; it does not prove production reused accuracy as its formula.
- Human acceptance of gameplay, touch layout, login/loading, portal visuals and real-account ingestion remains pending. No production writes, deployment, OpenAI calls or APK build were performed.
