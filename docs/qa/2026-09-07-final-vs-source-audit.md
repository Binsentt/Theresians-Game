# Final VS source audit — 2026-09-07

Canonical source: `C:\Users\vince\Documents\Capstone-Project\capstone-theresians-quest`, HEAD `dee8b5cdb27311e75451a6042063bed8aa67800f`. Authoritative archive: `C:\Users\vince\Downloads\capstone-theresians-quest6.zip`, top-level `capstone-theresians-quest6/` only. ZIP entries were inspected directly; no copy was extracted or launched. The JSON companion records fresh hashes, node declarations, exact connections, route-search hits and pre-existing dirty diffs.

This source audit made no product edit, Godot invocation, network call, staging operation, commit or deletion. It does not claim runtime or human acceptance. Parent owns canonical MCP runtime verification. Existing QuestUI female routing and shared-host lifetime changes, staged QuizManager analytics, GameState work and other dirty files were preserved.

## Findings before implementation

- **Codex replacement battle UI identified: NO.** Searches of 177 ZIP and 201 current product `.gd`, `.tscn`, `.tres`, `.json`, and `.godot` files found no `QuestionContainer`, `Question Container`, `MultipleChoice`, `BattleScene`, or `battle_scene.tscn` presentation or caller. Dot directories, tools and QA documents were excluded. A fresh all-ref history change search for the replacement names returned no entries. This does not describe unavailable external history.
- **Replacement still active: no source evidence.** Current source instantiates one original VS scene. Source extra-question-presentation count is 0; the fresh runtime duplicate count belongs to the parent MCP tree test.
- **All eight full VS scenes are byte-identical to ZIP.** Their recursive `ext_resource` graph contains 150 files including the eight roots: 149 identical and one intentional integration difference, `QuizManager.gd`. No resource is missing. Portraits, background, heart scripts/assets, effects, animation frames and layout are preserved.
- **No new battle-source regression is proven.** The world-camera canvas correction is already in HEAD (`a6140e3`); final-effect completion ordering is already in HEAD (`3d846de`). Preserve these corrections. No battle product edit or replacement-file removal is recommended.
- **Later gameplay routes remain source-evidence gaps.** Complete presentation assets do not supply encounter identities, prerequisites, Grade/Difficulty scopes, milestone transitions or a quest denominator.

## Exact scene mapping

All paths below are under `res://Battle/Battle-Enemy/`.

| Enemy | Male full scene | Female full scene | Original enemy portrait |
| --- | --- | --- | --- |
| Normal Bandit | `male_vs_bandit.tscn` | `female_vs_bandit.tscn` | `res://Battle/Bandit-Battle.tscn` |
| Boss Bandit | `male_vs_boss.tscn` | `female_vs_boss_bandit.tscn` | `res://Battle/boss_bandit_battle.tscn` |
| Wizard | `male_vs_wizard.tscn` | `female_vs_wizard1.tscn` | `res://Battle/Wizard-Battle.tscn` |
| Teacher | `male_vs_teacher.tscn` | `female_vs_teacher.tscn` | `res://Battle/Teacher_Battle.tscn` |

`male_vs_boss_bandit.tscn` is a ninth, incomplete, unbound static scene: background, Boss portrait, male portrait and BattleLifeDisplay. It has no QuizManager, question/four-choice controls or slash effects. Its more specific filename is not evidence that it should replace the complete `male_vs_boss.tscn`. Preserve it without routing to it or deleting it. The complete female Wizard filename includes `1`, although its root node name does not.

Every complete scene binds the same `QuizManager.gd` on the root and contains the original `CanvasLayer/Panel/QuestionLabel`, `ChoiceA` through `ChoiceD`, four pressed-signal connections, `PlayerHealth/Hearts/Heart1..3`, `EnemyHealth/Hearts/Heart1..3`, `player/SlashEffect`, and `Bandit/SlashEffect`. `Bandit` is the original shared enemy node name even for specialized portraits. The male/female player portraits are `Battle/Player-male-battle.tscn` and `Battle/player_female_battle.tscn` respectively.

## Gameplay routing, separate from presentation availability

| Area / actor class | Male presentation | Female presentation | ZIP caller | Current caller |
| --- | --- | --- | --- | --- |
| Oakleaf normal Bandit | `male_vs_bandit.tscn` | `female_vs_bandit.tscn` | First Bandit only, both genders to male scene | First Bandit only, matching gender |
| Oakleaf Boss Bandit | `male_vs_boss.tscn` | `female_vs_boss_bandit.tscn` | None proven | None proven |
| City normal Bandit | `male_vs_bandit.tscn` | `female_vs_bandit.tscn` | None proven | None proven |
| Pinehill normal Bandit | `male_vs_bandit.tscn` | `female_vs_bandit.tscn` | None proven | None proven |
| Pinehill Wizard | `male_vs_wizard.tscn` | `female_vs_wizard1.tscn` | None proven | None proven |
| Final Teacher; location/milestone unproven | `male_vs_teacher.tscn` | `female_vs_teacher.tscn` | None proven | None proven |

The JSON expands these to twelve area/class/gender rows. The mappings in unbound rows specify the existing full presentation, not an implemented gameplay route.

The fresh ZIP/current task lists contain exactly three entries: go to Teacher House, talk to Teacher, first Bandit math challenge. Only the last entry has `next_scene`. Current first-Bandit scope is the approved Grade 1 / Easy; no later scope is invented. The post-Bandit index is the end of this implemented list. Current `DEFAULT_QUEST` is `No active quest`; this is not proof that the whole game is complete.

Exact first-Bandit chain:

1. ZIP `scenes/oak_leaf_village.tscn:1021` binds `Bandits/BanditTaskTrigger` to `world/Task1.gd`, `trigger_for_task_index = 2`, and `../../CanvasLayer/Panel`. ZIP `scripts/game_state.gd:76` supplies the male scene. ZIP QuestUI instantiates it without a gender branch.
2. Current `scenes/oak_leaf_village.tscn:691` binds the same first actor's trigger through `scripts/interactable_area.gd`; `TaskDialogAdapter` at line 709 binds `scripts/task_dialogue_adapter.gd`, the shared QuestUI path and `require_task_index = 2`. InteractionManager dispatches one accepted action through that adapter. The adapter gates exploration mode, input lock, task index and its own active state, then awaits QuestUI.
3. Current `world/QuestUI.gd:96` selects the task scene and lines 97–98 perform the pre-existing female substitution. It captures encounter source/checkpoint/scope, hides the world's CanvasItem, and attaches the original VS to `OriginalBattlePresentation` CanvasLayer at -1. The original question CanvasLayer is 0 and preserved GameHUD remains above it. `GameState.begin_battle` tracks this instance and battle mode; it creates no question UI.
4. On `battle_finished`, QuestUI frees the overlay layer, restores the same world visibility, records defeat/retry without task advancement or records victory and advances once through the existing canonical state boundary. No invented destination or normal-battle scene switch is introduced.

Oakleaf contains five normal Bandits and one Boss Bandit; only the first normal Bandit has a battle interaction in either source. City contains five normal Bandits with no encounter binding in either source. Its current `wandering_bandit.tscn` adds the approved bounded movement wrapper without creating a quiz route. Pinehill contains four normal Bandits and Boss-Wizard with no encounter binding in either source. Base `bandits.tscn`, `boss_bandit.tscn`, and `boss_wizard.tscn` are visual/animation resources without hidden quiz dispatch. The current Teacher House interaction gates task index 1, whose dialogue has no `next_scene`; it is not a final Teacher battle caller.

## Provider boundary, hearts and effects

Current QuizManager gets the canonical QuestionProvider, waits for its `questions_loaded` signal, reads normalized questions, and fills the existing label and four buttons. It never instantiates a second Panel or choice set. QuestionProvider requests `/api/game/questions` using exact Grade + Difficulty, accepts backend `options`/`correct_answer` data, rejects other than four choices and ambiguous/missing correct answers, and preserves the backend `learning_file_id` as `question_set_id`. Topic remains optional. Pool randomization and exhaustion stay in QuestionProvider. No provider/backend rollback is justified by restoring presentation.

Correct/wrong handling retains the ZIP player/enemy effect and health calls. Both original battle-local health scripts initialize three hearts and remove one per hit; these are separate from persistent GameState lives and retry count. `hit_effect.gd` plays the preserved non-looping `explode` animation with 60 frames at 60 fps. No extra enemy-specific effect code is proven by the ZIP: each specialized VS scene binds the same preserved effect resource with its original transform.

The current one-shot terminal guard disables answers immediately, keeps `YOU WIN!` / `GAME OVER!`, waits for the selected original effect's `animation_finished`, then emits one `battle_finished`. The ZIP QuestUI awaited a completion signal absent from its QuizManager; reverting the current manager wholesale would break established completion and backend integration. Pre-existing staged answer analytics and deferred RemoteSync delivery are preserved.

## Inactive paths and test limitations

- `scripts/game_over.gd` contains a hardcoded male-Bandit retry in ZIP/current but has no product scene binding. The active game-over scene binds `scripts/game_over_scene.gd`. The legacy file is not an active female-route defect.
- Current product resources no longer bind `world/Task1.gd`. `world/Task3.gd`, `world/Quest3.gd`, `interiors/Task2.gd`, and `interiors/Quest2.gd` have no resource bindings in either source. They do not prove a later chain. Preserve them.
- Oakleaf's original empty `BattleLayer` is not a duplicate question panel. Original `Panel`, `QuestionLabel` and `ChoiceA..D` in the VS files are developer controls, not Codex replacement controls.
- `original_battle_presentation_test.gd` covers all eight original scenes and both outcomes using a fake QuestionProvider. It verifies original controls, portraits, hearts, effect timing and parent teardown, but does not by itself prove the real QuestionProvider path for every variant or any later world route.
- `gameplay_battle_tree_audit.gd` uses the real QuestionProvider with isolated backend-shaped transport for actual first-Oakleaf male/female victories and male defeat. It covers pointer clicks, one original question presentation, exact scope, canvas placement, Settings/timeout return, world/controller restoration and task/save continuation. Its old evidence paths should not be silently overwritten in this task.
- `battle_life_persistence_test.gd` directly mutates GameState lives and tests saves; it does not establish that original VS-local health is the same system. Provider normalization/randomization/exhaustion tests are similarly component evidence, not full encounter evidence.

A new fixture-only all-eight real-QuestionProvider/isolated-HttpApi test can close the presentation integration coverage gap without adding product routes. Fresh actual-world, quest/reload/save/RemoteSync checks and all runtime error counts remain the parent task's responsibility. Battle appearance, long-question readability, original timing, input and victory/defeat acceptance remain **HUMAN RECHECK ITEMS**. Missing later milestones remain **SOURCE-EVIDENCE GAPS**, not silently repaired gameplay.
