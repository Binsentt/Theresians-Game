# Canonical preservation restoration

Implemented in `C:\Users\vince\Documents\Capstone-Project\capstone-theresians-quest` from canonical HEAD `2241f9efa6377161afc49c26809f35a39a1c4e71`, following the human's explicit post-audit authorization. Resulting commit is recorded in `2026-09-07-restoration-verification.json` and the final task response.

## Product changes

| Exact canonical-relative file | Focused restoration |
| --- | --- |
| `scripts/game_state.gd` | Persist active Tutorial through the existing `current_quest` string; restore completion on load; keep task checkpoint unchanged; update the saved objective during existing task advancement and clear it at terminal completion. Save version 8, keys, task order and IDs remain unchanged. |
| `scripts/game_hud.gd` | Show Tutorial while its authoritative state is active; display the existing task objective only afterward. |
| `interiors/TutorialNPC.gd` | Connect existing Next progression to the shared InteractionManager; retain all eight instructions and the final completion boundary; avoid replay after completed loads. E/Space use canonical Interact rather than duplicating a focused Next-button activation. Existing mouse/touch Next, position, movement speed and timing remain. |
| `scripts/input_manager.gd` | Restore preserved E/Space `interact` defaults only if that action is absent; merge keyboard and mobile into one consumed edge, including quick taps; prevent echo, overlapping holds, and held keys across input unlock from becoming duplicate presses. Existing movement calculation remains. |
| `scripts/mobile_controls.gd` | Show the original controller in canonical debug gameplay without an environment override. Retain Interact during dialogue, hide movement there, and preserve full hiding for battle/menu/input lock. No controller scene, assets, sizes, anchors, placement, or press scale changed. |
| `world/QuestUI.gd` | Consume the single shared Interact edge; remove the second raw-keyboard fallback that could bypass consumption. Retain dialogue text/order, release gate, final-close guard, encounter routing and victory-only progression. |
| `scenes/oak_leaf_village.tscn` | Remove the incorrect serialized `node_paths` annotation from only `girl_npc/Visual` and `villager-female/Visual`, allowing their existing `../../CanvasLayer/Panel` NodePath values to load correctly. All positions, wanderers, detectors and terrain remain. |
| `scenes/city_of_knowledge.tscn` | Apply the four existing starting directions to the correct `Visual` children: right, left, right, up. The fifth remains down. No positions, terrain, wrappers, collision, speed or home radius changed. |

## Verification

All engine runs used Godot MCP and the canonical project. The focused runtime fixture disables RemoteSync observers and HTTP access in its own process, supplies the existing local question-provider stub, and uses uniquely named disposable local save files. It exercises the canonical serializer and loader, real gameplay scenes, original touch handlers, keyboard events, NPC adapters, dialogue, and battle continuation. No production account/session, API request, deployment or APK build was used.

The initial regression test produced **32 failures / 63 passes**. After corrections and additional review cases, the final run produced **102 passes / 0 failures**. The existing mobile-controls project-context test also passed after updating its dialogue-visibility expectation to the explicitly authorized lifecycle.

| Required check | Result |
| --- | --- |
| Tutorial HUD before completion | PASS — Tutorial |
| Tutorial HUD after completion | PASS — Go to the Teacher's House |
| Save during Tutorial / Load | PASS — remains unfinished; existing instruction sequence can restart |
| Save after Tutorial / Load | PASS — remains completed, correct objective, no tutorial replay |
| Save schema and task checkpoint | PASS — version 8 and existing keys retained; no task skipped |
| Dialogue one press / one line | PASS — held press, echo, quick taps and simultaneous keyboard/touch covered |
| Final deliberate close | PASS — Teacher advances/saves once; First Bandit enters one battle |
| Oakleaf NPC bindings | PASS — both existing greetings open/close through their corrected bindings |
| City starting facing | PASS — right/left/right/up/down |
| City wandering/collision/home bounds | PASS — speed 30, radius 42, walking animation, collision stop and home radius retained |
| Mobile D-pad | PASS — four existing directions through InputManager in six canonical scenes |
| Mobile Interact | PASS — visible in debug exploration and dialogue; hidden in battle/menu/input lock |
| Tutorial Teacher | PASS — held touch advances one instruction, final completion once |
| Teacher House Teacher | PASS — deliberate lines, final close, one saved advancement |
| First Bandit | PASS — opening press does not skip dialogue; final close starts one battle; victory completes the existing sequence |
| Keyboard interaction | PASS — preserved E/Space bindings, shared consumption, echo/quick-tap/unlock cases |
| No duplicate trigger/advancement | PASS — Teacher, greetings, tutorial and Bandit cases |
| Final task HUD | PASS — completed sequence does not redisplay the obsolete Teacher House objective |
| SCRIPT ERROR | 0 |
| Resource/parse errors | 0 |
| `git diff --check`, staged and unstaged | PASS |

The 102-check run logged **295 warnings**, mostly repeated UID-to-path fallbacks while reloading scenes, plus script warnings and an ObjectDB exit-leak warning. This is not a warning-free certification. Automated runtime results do not substitute for physical-device hit testing or the human's visual acceptance.

The six scenes are Player House, Oakleaf, Teacher House, City, Pinehill and School. Player House was reloaded during and after Tutorial. First Bandit Grade 1/Easy and optional Topic behavior were checked with the existing local provider stub; the provider and battle UI product files were not changed.

## Notification effects and compatibility

The notification slide/fade removal is traced to `e409454`, the presentation rewrite. Canonical history shows the implementation change, but no explicit approval of removing those transitions was established. **Notification effects remain unchanged**, as requested. No old manager or panel design was restored.

Earlier unmarked saves never stored enough information to distinguish a completed tutorial from an unfinished one at task index 0. Loading such a save preserves its already-recorded quest checkpoint rather than rolling it back into a newly assumed tutorial. Newly saved Tutorial/completed states are distinguishable using the existing string field. No save schema extension or migration file was introduced.

## Scope and evidence

**Unrelated product delta count: 0.** Comparing the 199-file before-audit source/resource hash manifest found exactly the eight authorized product paths above. Controller scene/assets, movement/wandering resources, maps/TileSets, Teacher House layout, Grade/Difficulty routing, optional Topic, RemoteSync, login, loading and website/backend received no additional changes. Pre-existing staged/unstaged work is excluded from the focused commit.

Focused test files: `tools/preservation_restoration_test.gd`, `tools/preservation_restoration_test.tscn`, `tools/preservation_regression_state.gd`, and the one approved expectation change in `tools/mobile_controls_project_context_test.gd`.

Local evidence: `2026-09-07-restoration-tests-before.json`, `2026-09-07-restoration-tests.json`, `2026-09-07-restoration-before-log.txt`, `2026-09-07-restoration-after-log.txt`, and `2026-09-07-restoration-mobile-context-log.txt`. Independent code review identified quick-keyboard and terminal-HUD cases; both were reproduced, corrected and passed before commit.

No proven regression remains in the authorized restoration scope. Notification transition disposition remains deferred as instructed.
