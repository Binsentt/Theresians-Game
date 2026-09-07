# Battle routing re-audit — 2026-09-07

## Runtime follow-up supersedes the preliminary source-only presentation conclusion

Canonical Godot MCP rendering found that the original VS scene was attached directly below the world Camera2D: its question CanvasLayer appeared, while the original background, portraits and hearts were outside the viewport. The original resources were present and unchanged; their caller's canvas context was wrong. No separate Codex question UI was found. This runtime evidence supersedes the preliminary “no new presentation regression” statement below. The exact introducing historical commit is not established.

The focused `world/QuestUI.gd` correction hosts the existing VS scene in a viewport CanvasLayer at -1, places its existing question layer at 0, and leaves the existing GameHUD at 1. It captures and temporarily hides the world's CanvasItem visibility during battle, then restores it on victory or defeat. No original battle scene, art, effect, choice control or HUD property is edited. Initial alternatives that covered the HUD or questions were rejected by screenshot and pointer checks before commit.

Fresh actual-encounter testing records 107 passing checks and zero failures: male/female original routes, real QuestionProvider with isolated backend-shaped transport, four choices, correct answers, actual viewport pointer clicks on Settings/close/answers/timeout Return, victory and defeat return visibility, one terminal result, checkpoint and save behavior. Eight original VS variants also pass 594 checks across 16 win/loss cases. These remain automated evidence, not human acceptance. See `2026-09-07-gameplay-battle-tree.json` and the original male/female screenshots. The later routing gaps below remain unchanged.

Final preservation checking separately detected concurrent changes to three map scenes outside the approved NPC transformations; these were captured in `2026-09-07-gameplay-concurrent-map-drift/`. The human explicitly rejected that drift. All 29 reverse hunks were applied without a scene overwrite; fresh canonical map hashes and the 331-check civilian/runtime snapshot suite pass. Archived copies remain intact behind docs/qa/.gdignore to prevent duplicate UID discovery.

## Preliminary source audit (captured before the runtime correction)

Canonical HEAD: `3d846de475713d1f34a747d345f36217a453586f`. Canonical root: `C:\Users\vince\Documents\Capstone-Project\capstone-theresians-quest`. Archive: `C:\Users\vince\Downloads\capstone-theresians-quest6.zip`, top-level `capstone-theresians-quest6/` only. Dot directories, embedded worktrees, tools and QA documents were excluded from product-source searches. ZIP entries were read directly; no project copy was extracted or launched.

This is a fresh source audit, not a runtime acceptance report. No Godot action, gameplay request, production mutation, product edit, deletion, staging or commit was performed. Existing staged QuizManager analytics and dirty GameState/QuestUI/map/config work were inspected and preserved. Only this report and its JSON companion were written. Parent task owns canonical Godot MCP verification and human rechecks.

## Findings

The only source-proven active encounter is the first Oakleaf Bandit. Current code opens the original male/female Bandit VS scene. This conclusion follows the map trigger, interaction adapter, task data, instantiation caller and scene-node bindings independently; it does not rely on scene byte identity alone.

No current product `BattleScene`, `battle_scene.tscn`, `QuestionContainer`, `Question Container` or separate multiple-choice presentation was identified. The broad search covered 198 canonical and 177 archive product source/resource files (`.gd`, `.tscn`, `.tres`, `.json`, `.godot`). Neither baseline contains a matching replacement resource/caller. Git searches across available refs for `QuestionContainer`, `BattleScene`, and matching battle-scene filenames also returned no matches. This does not establish what may have appeared in unavailable historical or external copies. The current runtime tree still needs its own MCP check; this report does not assign a runtime duplicate-UI count.

The original `CanvasLayer/Panel/QuestionLabel` and `ChoiceA..D` are present in the ZIP and current full VS scenes. Calling these controls a Codex-created replacement would be incorrect. No presentation path was retired or deleted because no active displacement was proven.

## Twelve-row area / enemy / gender routing matrix

Every presentation path in the table is under `res://Battle/Battle-Enemy/`. “Available” means the scene's bound portrait, health, controls and effects prove its class/gender; it does not mean a quest route exists. The ZIP routes both genders to the male scene for its one first-Bandit task; the existing canonical female substitution is retained.

| Area | Enemy class | Gender | Source-supported full presentation | ZIP gameplay route | Current gameplay route / result |
| --- | --- | --- | --- | --- | --- |
| Oakleaf | Normal Bandit | male | `male_vs_bandit.tscn` | `male_vs_bandit.tscn`, first actor only | `male_vs_bandit.tscn`, first actor only; remaining four unbound |
| Oakleaf | Normal Bandit | female | `female_vs_bandit.tscn` | `male_vs_bandit.tscn`, first actor only | `female_vs_bandit.tscn`, first actor only; remaining four unbound |
| Oakleaf | Boss Bandit | male | `male_vs_boss.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| Oakleaf | Boss Bandit | female | `female_vs_boss_bandit.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| City of Knowledge | Normal Bandit | male | `male_vs_bandit.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| City of Knowledge | Normal Bandit | female | `female_vs_bandit.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| Pinehill | Normal Bandit | male | `male_vs_bandit.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| Pinehill | Normal Bandit | female | `female_vs_bandit.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| Pinehill | Wizard | male | `male_vs_wizard.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| Pinehill | Wizard | female | `female_vs_wizard1.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| Final Teacher (location/milestone unproven) | Teacher | male | `male_vs_teacher.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |
| Final Teacher (location/milestone unproven) | Teacher | female | `female_vs_teacher.tscn` | No caller/milestone | No caller/milestone — NOT PROVEN BY SOURCE |

First-Bandit male/female route: source PASS. Normal Bandit reuse throughout all three areas: incomplete/source gap. Boss/Wizard/Teacher encounter routing: NOT PROVEN BY SOURCE. Opening their scenes in an isolated test establishes presentation compatibility, not implemented gameplay progression. No absent later milestone, actor count required for completion, encounter scope or Total Progress denominator is invented.

## Exact active caller chain

1. ZIP Oakleaf `Bandits/BanditTaskTrigger` is at `scenes/oak_leaf_village.tscn:1021`. It binds `world/Task1.gd`, index 2, and `../../CanvasLayer/Panel`. `Task1.gd:19` invokes QuestUI after the indexed proximity trigger. ZIP GameState's three-entry task array supplies `male_vs_bandit.tscn` at line 76. ZIP `world/QuestUI.gd:70` loads/instantiates that value and line 73 adds it to the current scene. There is no gender branch.
2. Current Oakleaf `scenes/oak_leaf_village.tscn:677` binds `scripts/interactable_area.gd`; its target is `TaskDialogAdapter`. At line 695 that adapter binds `scripts/task_dialogue_adapter.gd`, `require_task_index = 2`, and `../../../CanvasLayer/Panel`. `InteractionManager.request_interaction()` consumes the shared interaction action and calls the component; the component calls the adapter. The adapter's `_active`, exploration-mode and task-index gates prevent another active interaction, then `scripts/task_dialogue_adapter.gd:49-50` awaits `QuestUI.show_completed_with_dialogue()`.
3. Current `scripts/game_state.gd:112` still supplies the male Bandit scene and the approved Grade 1 / Easy scope. After deliberate dialogue, `world/QuestUI.gd:71-91` checks playtime authorization, records the encounter source position/checkpoint/scope, substitutes `female_vs_bandit.tscn` for female, instantiates that scene and adds it directly to the current scene. `GameState.begin_battle()` records the already-instantiated overlay and sets battle mode; it creates no question UI.
4. `world/QuestUI.gd:94-115` waits for that scene's outcome, queues the overlay for deletion, records defeat without advancement or victory followed by one `advance_task_and_save` event. The world scene remains the overlay's parent, so there is no fabricated victory destination or normal-encounter scene switch. Actual event multiplicity/transport behavior is a parent runtime check.

The current task list still has exactly Teacher House, Teacher conversation and first Bandit, in that order. The task index after the first Bandit is the end of this implemented array, not proof of whole-game completion. Current Teacher House binds `scripts/teacher_task_interaction.gd` at `interiors/teacher_house.tscn:869`; its `can_interact` accepts only index 1, which has dialogue and no battle target. It is not a final Teacher battle caller.

## Map actors do not create missing encounters

| Map | ZIP and current enemy actors | Source-supported encounter bindings |
| --- | --- | --- |
| Oakleaf | `Bandits`, `Bandits2..5`, `Boss-Bandit` | Only first `Bandits` owns the indexed battle interaction. Other four and boss have no such binding in either source. |
| City of Knowledge | `Bandits`, `Bandits2..5` | None. Current `NPC/Enemy/wandering_bandit.tscn` wraps the preserved Bandit visual with approved bounded movement; it has no encounter/quiz interaction. Preserve that movement. |
| Pinehill | `Bandits`, `Bandits2..4`, `Boss-Wizard` | None. The actors are visual resources without battle callers in both sources. |

The source scene instances are backed by `NPC/Enemy/bandits.tscn`, `boss_bandit.tscn`, and `boss_wizard.tscn`. Their original base resources contain animation/visual nodes, not hidden encounter routing. The ZIP and canonical do not set `city_of_knowledge_unlocked` true through gameplay; save loading can restore its persisted value. This is a baseline progression gap, not evidence that this audit has discovered a removed later chain.

## Full scene and node bindings

Eight full scenes are byte-identical to ZIP. The male Boss full quiz is **`male_vs_boss.tscn`**, proven by its Boss portrait and complete controls. The female Wizard full quiz is **`female_vs_wizard1.tscn`**; the root node is named `female_vs_wizard` but the exact resource filename includes `1`.

| Enemy class | Male scene | Female scene | Bound enemy portrait |
| --- | --- | --- | --- |
| Bandit | `male_vs_bandit.tscn` | `female_vs_bandit.tscn` | `Battle/Bandit-Battle.tscn` |
| Boss Bandit | `male_vs_boss.tscn` | `female_vs_boss_bandit.tscn` | `Battle/boss_bandit_battle.tscn` |
| Wizard | `male_vs_wizard.tscn` | `female_vs_wizard1.tscn` | `Battle/Wizard-Battle.tscn` |
| Teacher | `male_vs_teacher.tscn` | `female_vs_teacher.tscn` | `Battle/Teacher_Battle.tscn` |

Each complete scene binds `QuizManager.gd` on its root and preserves this contract:

- `player` uses `Battle/Player-male-battle.tscn` or `Battle/player_female_battle.tscn` according to gender.
- `Bandit` is the shared enemy node name even for Boss, Wizard and Teacher; its PackedScene determines the actual enemy portrait.
- `CanvasLayer/Panel/QuestionLabel` is the original Label. `ChoiceA..D` are the four original Buttons; their four pressed connections call `_on_choice_a_pressed` through `_on_choice_d_pressed`, which pass answer indices 0..3.
- `PlayerHealth/Hearts/Heart1..3` and `EnemyHealth/Hearts/Heart1..3` are the original six TextureRects. Both original health scripts start at 3 and subtract 1 per damage. Battle-local health is distinct from persistent `GameState.current_lives` and encounter retry count.
- `player/SlashEffect` and `Bandit/SlashEffect` instance `assets/Effects/SlashEffect.tscn`; the common `hit_effect.gd` selects the original non-looping `explode` animation, 60 frames at 60 fps. ZIP does not prove separate enemy-specific attack code or extra victory animations.

The JSON records all required node paths, exact scene line declarations, four signal bindings, portrait paths and SHA-256 comparisons. Fresh recursive `ext_resource` comparison found **142 distinct dependencies excluding the eight VS roots: 141 identical, only QuizManager different**. Including the eight roots gives 150 files, 149 identical. No resource is missing. The eight scene files, portraits/backgrounds, heart assets/scripts and effect resources are preserved. This dependency graph intentionally covers presentation resources; newer QuestionProvider/backend adapter code is audited separately rather than reverted as an art dependency.

The ninth `male_vs_boss_bandit.tscn` remains incomplete: a static background, Boss portrait, male portrait and `BattleLifeDisplay`, with no QuizManager, question/four choices or effects. It has no product caller. Its UID difference from ZIP and the referenced life-display UID difference are not a demonstrated visual regression. Do not route to this incomplete file because its filename sounds more specific, and do not delete it.

## Question injection and current lifecycle

`QuizManager.gd:20-27` binds the original label/buttons. `_ready` gets the autoload QuestionProvider, connects its completion signal, loads the pool and waits for asynchronous completion. `load_question` writes the returned question and choices into those existing nodes; it does not instantiate another Panel or Buttons. `answer_selected` uses the backend-normalized zero-based `correct` index, records the attempt, plays the original effect and damages only the intended side.

`scripts/question_provider.gd` remains the Grade + Difficulty API/normalization/randomization provider. The first encounter retains Grade 1 / Easy. Topic is optional. `_record_question_attempt` retains the existing staged Save Game counters and deferred RemoteSync forwarding; this audit does not revert it or exercise production results. question_set_id and backend provenance verification belong to parent isolated tests.

The earlier report's terminal-hit truncation is **historical, already repaired in current HEAD `3d846de`**. Current `QuizManager._finish_battle` sets its one-shot guard, disables controls and awaits the existing animated effect's `animation_finished` before emitting `battle_finished`. This preserves the existing effect duration and result label while allowing QuestUI's established continuation. The older ZIP lacked this completion signal although ZIP QuestUI awaited it, so copying the ZIP manager wholesale would break newer integration/lifecycle. This fresh source audit found no new current battle-presentation regression to fix.

## Inactive or legacy presentation paths

| Resource/path | ZIP/current caller evidence | Action |
| --- | --- | --- |
| `scripts/game_over.gd` | Contains hardcoded male-Bandit retry at line 19 in both baselines, but neither baseline binds this script in a product scene. | Leave preserved. Do not treat it as active retry or female-routing regression. |
| `scenes/game_over_scene.tscn` | Actually binds `scripts/game_over_scene.gd:3`; current Yes is disabled, No returns to main menu. | Active game-over presentation, not a replacement quiz. Preserve. |
| `world/Task1.gd` | ZIP task trigger caller; current canonical maps no longer bind it. | Preserved inactive legacy source. |
| `world/Task3.gd`, `world/Quest3.gd`, `interiors/Task2.gd`, `interiors/Quest2.gd` | No resource bindings in either source search. Refer to undefined legacy task flags and do not establish a later quest chain. | Preserve; no cleanup authorization. |
| `male_vs_boss_bandit.tscn` | No product caller; incomplete static scene described above. | Preserve; no substitute routing. |
| Oakleaf `BattleLayer` | Empty CanvasLayer in ZIP and canonical. Actual QuestUI attaches VS overlay to current scene. | Not a duplicate question panel. Preserve. |
| Alleged `BattleScene` / `QuestionContainer` / separate Multiple Choice UI | No current product resource or instantiation caller identified. | No safe removal candidate is established. |

## Required runtime and human boundaries

Parent canonical MCP checks must independently observe the real first-Bandit male/female route, one original question UI with four backend-shaped choices, health/effects and single outcome/quest/result handling. Instantiate other six full variants with isolated question/transport stubs for presentation tests, while continuing to report their gameplay milestones as NOT PROVEN BY SOURCE. Do not count isolated scene tests as implemented boss/City/Pinehill/final-Teacher gameplay or human visual acceptance.

No deletion or new route is recommended from this source audit. The high-level future presentation mapping is unambiguous from preserved portraits and controls; the missing encounter identity, prerequisite, milestone and progression source is not supplied. Human battle appearance, question-in-battle, timing, defeat/victory and later progression acceptance remain pending.
