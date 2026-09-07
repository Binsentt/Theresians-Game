# Original battle audit — 2026-09-07

Read-only product audit. Starting canonical HEAD: `843b0b7f8d38d4417cfce9f566863505aa9e2042`. Existing staged `Battle/Battle-Enemy/QuizManager.gd` analytics and unstaged `world/QuestUI.gd` female routing changes were present before this audit and were not edited. No runtime was launched by this audit; the parent task owns Godot MCP verification. No network, production, OpenAI, APK, staging, or commit action was performed.

Authoritative comparison source: `C:\Users\vince\Downloads\capstone-theresians-quest6.zip`, only entries under the top-level `capstone-theresians-quest6/`. Embedded dot directories/worktrees were excluded from source searches. ZIP files were read directly without extracting or launching a project.

## Exact full VS scene inventory

All paths below are under `Battle/Battle-Enemy/`. All eight complete scenes are byte-for-byte identical between ZIP and canonical working tree.

| Variant | Exact full scene filename | Portrait scene |
| --- | --- | --- |
| Male / Bandit | `male_vs_bandit.tscn` | `Battle/Bandit-Battle.tscn` |
| Female / Bandit | `female_vs_bandit.tscn` | `Battle/Bandit-Battle.tscn` |
| Male / Boss Bandit | `male_vs_boss.tscn` | `Battle/boss_bandit_battle.tscn` |
| Female / Boss Bandit | `female_vs_boss_bandit.tscn` | `Battle/boss_bandit_battle.tscn` |
| Male / Teacher | `male_vs_teacher.tscn` | `Battle/Teacher_Battle.tscn` |
| Female / Teacher | `female_vs_teacher.tscn` | `Battle/Teacher_Battle.tscn` |
| Male / Wizard | `male_vs_wizard.tscn` | `Battle/Wizard-Battle.tscn` |
| Female / Wizard | `female_vs_wizard1.tscn` | `Battle/Wizard-Battle.tscn` |

Male portraits use `Battle/Player-male-battle.tscn`; female portraits use `Battle/player_female_battle.tscn`. All use `Battle/Bg-battle.tscn`.

The ZIP also contains a ninth `male_vs_boss_bandit.tscn`. It is an incomplete static presentation with `Sprite2D`, `Boss_Bandit_Battle`, `player-male`, and `BattleLifeDisplay`; it has no `QuizManager`, question/choices, or hit-effect children. It is not the full male Boss quiz scene. The canonical file differs only in its scene UID (`uid://b0t1odtilgyao` -> `uid://cbfuk25bb15sp`). Its referenced `ui/battle_life_display.tscn` also differs from ZIP only in the scene UID. Neither difference proves a visual regression. Do not substitute this incomplete scene for `male_vs_boss.tscn` or restore a UID blindly.

## Routing evidence and baseline limitation

ZIP `scripts/game_state.gd:63-79` defines only three array tasks: Teacher House, Teacher conversation, and first Bandit questions. Only the last task has `next_scene`, pointing to `res://Battle/Battle-Enemy/male_vs_bandit.tscn` (ZIP line 76). ZIP `world/QuestUI.gd:66-79` directly instantiates that path as an overlay and awaits `battle_finished`. It performs no gender substitution. No root source references were found that route to the female, Teacher, Boss, or Wizard full VS scenes.

`scripts/game_over.gd:19` also contains a hardcoded male Bandit retry in both ZIP and canonical; the current actual `scenes/game_over_scene.tscn:3` binds `scripts/game_over_scene.gd`, so this legacy retry reference alone does not establish a reachable retry path.

Current `scripts/game_state.gd:112` retains the same Bandit scene target, with explicit Grade 1 / Easy question scope. Current `world/QuestUI.gd:86-91` substitutes `female_vs_bandit.tscn` for a female player, then instantiates the existing VS scene. This substitution is pre-existing unstaged work, not a change in this audit. Current code still has no canonical encounter routes to the other six full scenes.

Therefore: original VS presentation retained **yes**; Codex replacement battle/quiz UI displacing it found **no**. All eight encounters' gameplay routing restored/verified **no**: the required encounter triggers and progression connecting the other variants are not present in the inspected ZIP routing. Do not invent new quest milestones or claim this ZIP proves the remembered multi-Bandit/Boss/Teacher-return sequence. Parent quest audit should resolve/report that source gap.

## Original nodes, effects, and health

The eight full scenes have the same required contract: root `QuizManager.gd`, `player`, enemy node named `Bandit` (including Boss/Teacher/Wizard), `player/SlashEffect`, `Bandit/SlashEffect`, `CanvasLayer/Panel/QuestionLabel`, `ChoiceA` through `ChoiceD`, `PlayerHealth/Hearts/Heart1..3`, and `EnemyHealth/Hearts/Heart1..3`. Four pressed connections target `_on_choice_a_pressed` through `_on_choice_d_pressed`.

A direct recursive ZIP/current byte comparison followed all resource dependencies of the eight scenes: 142 distinct dependency files checked; 141 identical, only shared `QuizManager.gd` different. This includes portrait/background PNGs and scenes, heart textures/scripts, `assets/Effects/SlashEffect.tscn`, `assets/Effects/hit_effect.gd`, and referenced effect image frames. No missing dependency was found by that comparison. No visual resource change is justified by this audit.

`PlayerHealth.gd` and `EnemyHealth.gd` are exactly the ZIP versions: `max_health = 3`, `health = 3`, one health removed per `take_damage()`, and each heart visible iff its index is below health. Battle health is local to each instantiated scene in the ZIP and current implementation. Separate `GameState.current_lives` and current encounter retry count are not these battle health nodes. Existing `tools/battle_life_persistence_test.gd` directly calls `GameState.lose_life()`; it does not test a real VS wrong answer. Do not use that test as proof that battle-local hearts persist across encounters, and do not rewrite original battle heart semantics based solely on its name.

ZIP `QuizManager.gd:80-100` and current `QuizManager.gd:106-124` preserve correct answer -> enemy effect/damage, wrong answer -> player effect/damage, enemy zero -> `YOU WIN!`, player zero -> `GAME OVER!`.

All enemy variants share the same effect, rather than distinct enemy attack code: `hit_effect.gd:8-17` sets visible, stops/resets the animated sprite, then plays `explode`; line 22 hides on animation completion. `SlashEffect.tscn` defines `explode` as 60 frames at 60 fps (1 second), `hit` as 60 frames at 60 fps, and `slash` as nine frames at 15 fps. All are non-looping. The original `play_effect()` selects `explode` for every variant. No per-enemy attack or extra victory animation is proven by the ZIP.

## Proven lifecycle delta needing focused runtime confirmation

Canonical `QuizManager.gd:117-124` sets the result label then calls `_finish_battle`; `_finish_battle` (154-159) disables controls and emits `battle_finished(success)` synchronously. `QuestUI.gd:94-95` immediately queues the entire battle overlay for deletion. The final effect just started at line 110 or 114 therefore cannot complete its original one-second animation, and the result label has no guaranteed rendered frame before teardown.

Proven source provenance: commit `0f739b90f46429eebf8386d94835d6cc1dd53aab` (`feat: add battle lifecycle foundation`, 2026-08-22) added the completion signal/guard, replaced both terminal `disable_buttons()` calls with `_finish_battle`, and made `QuestUI` consume the success boolean. The ZIP `QuizManager` has no `battle_finished` signal, although ZIP `QuestUI` already awaited it. Thus the ZIP has a broken continuation boundary, and removing the new signal is not a valid restoration.

Smallest candidate fix after canonical MCP confirmation: keep the existing result labels, health, assets, hit effect, and success/failure continuation; prevent duplicate answers immediately; wait for the terminal existing `AnimatedSprite2D.animation_finished` before emitting the completion signal/allowing overlay removal. No invented transition duration, new UI, or replacement effect is required. Retain an immediate fallback for a non-animated test stub only if needed. Test the real scenes to establish animation completion and single continuation on both win and defeat. Final human timing/presentation acceptance remains pending.

## Backend question integration preserved

Current `project.godot:25` autoloads `QuestionProvider`. `QuizManager._ready` connects `questions_loaded`, asks the provider to load, waits for completion, reads the pool, then writes the question and four choices into the original scene nodes. `load_question()` uses `get_question()`; no runtime quiz controls are manufactured.

`scripts/question_provider.gd:44-108` requests `/api/game/questions` using exact encounter Grade/Difficulty, normalizes/matches returned questions, fails closed on remote failure/scope mismatch, and uses local JSON only without `HttpApi`. Scope acquisition is in `_get_encounter_question_params` (118+). Existing four-choice normalization, scope history, randomization, and exhaustion behavior should remain intact.

Current `QuizManager._record_question_attempt` (130-145) updates pre-existing staged Save Game counters/difficulty and defers to `RemoteSync.record_question_attempt`. `scripts/remote_sync.gd` sends `/api/game/result` for the active server playtime lease, including student/parent reference, score 1 or 0, total_items 1, difficulty, learning-cycle version, and positive question_set_id when present. The parent backend audit owns identity and aggregation correctness; no network request was made here.

Relevant Git provenance: `de77b52` initially committed the VS assets and already-integrated QuestionProvider code; its message is not proof of original developer behavior. `ff9f4a7` repaired provider loading; `05fb803` added question-set result traceability; `0f739b9` added lifecycle; later `1b63903`, `7a52b93`, and `2241f9e` cover scope and loading behavior. Preserve the loading fix and current staged analytics; do not restore the raw ZIP QuizManager wholesale.

## Focused verification recommendations

1. Through Godot MCP in canonical root with isolated provider/transport and no real production gameplay, instantiate all eight exact full VS paths and assert existing portrait resources, panel/four controls, both three-heart systems, and both original effect children.
2. Inject a delayed backend-shaped Grade 1 / Easy question into the original controls; correct answer damages only enemy; wrong answer damages only player; question_set_id is forwarded once; no UI replacement is created.
3. Final correct and final wrong answer: existing effect remains alive until its real animation finishes; original result label is visible; duplicate input cannot cause another damage/result/outcome; battle exits exactly once afterward.
4. Exercise actual male/female first Bandit routing and save/return lifecycle. Do not label Teacher/Boss/Wizard gameplay routing PASS until authoritative quest connections exist.
5. Existing useful tests to run/extend: `first_bandit_question_scope_test.gd`, `first_bandit_interaction_project_context_test.gd`, `human_qa_followup_test.gd`, `question_set_traceability_test.gd`, `question_pool_randomization_test.gd`, `question_pool_exhaustion_test.gd`, and `battle_lifecycle_test.gd`. `quiz_manager_async_provider_test.gd` currently expects a synchronous outcome and uses fake effects, so it cannot detect terminal-effect truncation; update that expectation if completion is deferred.

No runtime PASS, visual acceptance, parse-error count, or all-encounter completeness is claimed by this read-only report.
