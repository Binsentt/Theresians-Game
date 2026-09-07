# Canonical original gameplay restoration verification

Starting canonical HEAD: `dee8b5cdb27311e75451a6042063bed8aa67800f`.
Canonical project: `C:/Users/vince/Documents/Capstone-Project/capstone-theresians-quest/project.godot`.
Baseline: supplied `capstone-theresians-quest6.zip`, read directly without extracting or launching another project.

**TECHNICALLY RESTORED — HUMAN RECHECK PENDING** for the implemented source-supported chain and preserved presentations. Later encounters and progression remain source-evidence gaps; this is not a claim of a complete end-to-end game or production acceptance.

Three previously uncommitted, user-authorized corrections are verified for focused commits. No product file was rewritten during this task: the runtime already contained those corrections. The HEAD comparison is **two product files, 11 insertions and 5 deletions**. All 1,869 pre-existing tracked files remained byte-identical to the task-start snapshot. Pre-existing staged analytics, configuration, map/UI work, document removals and other integrations are excluded from the focused commits and preserved.

## Product corrections and provenance

| File/function | Proven problem in earlier committed code | Focused correction being committed |
|---|---|---|
| `scripts/game_state.gd::apply_save_data` | Loader accepted an obsolete Teacher-House title alongside a completed checkpoint. Earlier progression writes were repaired at `bb65a3f9`, but existing stale saves remained possible. The HUD falls back to this title after the authored task list ends. | Derive current quest from the already-clamped saved checkpoint, retaining the existing active Tutorial marker. Five added lines; no schema, keys, quest order, HUD or RemoteSync change. |
| `world/QuestUI.gd::show_completed_with_dialogue` | Both genders followed the task's hardcoded male normal-Bandit scene. ZIP includes the original female scene but does not select it. | Only female + exact normal male-Bandit route selects `female_vs_bandit.tscn`. This implements the explicit gender requirement using original assets; it is not claimed to be exact ZIP routing. |
| Same QuestUI function, completion tail | ZIP's legacy final-task `queue_free()` survived after four civilian greetings were integrated with this shared host at `e409454`. Winning the final listed task removed their dialogue host until reload. | Keep the host and update its quest visibility. All four actual Oakleaf greetings remain usable after victory without replaying a battle or advancing a task. |

In-memory earlier-code replay reproduced all three defects while leaving product files untouched. The final runtime tested the corrected behavior. No additional battle adapter, NPC movement or dialogue-resource change was needed.

## Battle

Codex replacement battle UI identified: **NO**. Replacement still active: **NO**. Duplicate battle-question UI count: **0** in all tested scenes. No files were deleted.

All eight complete VS root scenes are byte-identical to the ZIP. Their recursive resource graph contains 150 files: 149 identical; only the existing `QuizManager.gd` integration differs. The original portraits, background, six battle-local hearts, effects and UI remain intact. The ninth `male_vs_boss_bandit.tscn` is incomplete and unbound; it is preserved, not selected.

All filenames below are in `Battle/Battle-Enemy/`:

| Encounter presentation | Male | Female | Actual world route |
|---|---|---|---|
| Normal Bandit | `male_vs_bandit.tscn` | `female_vs_bandit.tscn` | First Oakleaf Bandit only. Other Oakleaf, City and Pinehill Bandits have no source-proven binding. |
| Boss Bandit | `male_vs_boss.tscn` | `female_vs_boss_bandit.tscn` | Not supplied by ZIP/current source. |
| Wizard | `male_vs_wizard.tscn` | `female_vs_wizard1.tscn` | Not supplied by ZIP/current source. |
| Teacher | `male_vs_teacher.tscn` | `female_vs_teacher.tscn` | Not supplied by ZIP/current source. Teacher House is a quest conversation. |

**PASS:** real canonical QuestionProvider accepts backend-shaped isolated transport responses, retains exact Grade + Difficulty and optional Topic, and populates the original QuestionLabel and ChoiceA–D. Correct answer and question-set traceability are retained. No UI substitution exists. The existing lesson/question publication pipeline and backend were neither changed nor exercised.

**PASS:** all eight scenes, both outcomes, original pointer-clicked controls, correct/wrong heart damage and effects, 60-frame/60-fps non-looping terminal effect before one result, and no duplicate answer/result. Specialized scenes are explicitly fixture-only; no later world routing is invented. Actual male/female first-Bandit victories and male defeat additionally verify original world/controller return, Settings access and timeout Return to Main Menu.

**PASS:** actual VS answers produce 3 correct + 1 incorrect = 75% Accuracy and current difficulty Easy. Total Progress and lesson progress fields remain unchanged. No quest denominator or percentage was invented. Admin/Teacher/Parent role parity and web rendering were not rerun; those systems remain untouched.

Full routing/resources evidence: [VS source audit](C:/Users/vince/Documents/Capstone-Project/capstone-theresians-quest/docs/qa/2026-09-07-final-vs-source-audit.md).

## Quest

The source-supported/current intended chain is:

1. Original eight-step Tutorial; current approved persistent Tutorial state remains active through its final line until deliberate close.
2. `Go to the Teacher's House` at checkpoint 0 after Tutorial completion.
3. Existing Teacher House arrival trigger advances once to checkpoint 1, `Talk to the Teacher`.
4. Final deliberate Teacher conversation close advances once to checkpoint 2, first Bandit math challenge.
5. First Bandit victory advances once to checkpoint 3, exhausting the three authored tasks. Current state is `No active quest`; HUD has no stale earlier objective. Defeat retains checkpoint 2 and the existing retry behavior.

**Post-battle Teacher-House fallback eliminated: YES for the reproduced stale-title/valid-checkpoint path.** Both genders retain checkpoint 3 after victory, scene reload and real serializer/file/load operations. Stale titles at checkpoints 1, 2 and 3 reconcile to their authoritative checkpoint. Active and completed Tutorial saves preserve their respective states. All four Oakleaf greetings still work after winning, and do not replay quests or battles.

The actual RemoteSync observer was tested separately with isolated success, failure, queued retry, activity and result responses carrying stale earlier quest fields. Its state remained completed. The test asserts an actual isolated `/api/game/activity` request, not merely a call that returns before transport. This does not establish production/backend handling of reordered writes.

Source-proven sequence, history, exact trigger bindings, gate and legacy limitations: [quest source audit](C:/Users/vince/Documents/Capstone-Project/capstone-theresians-quest/docs/qa/2026-09-07-final-quest-source-audit.md).

## Complete outdoor actor inventory

The following source table covers all **31** actors. Current movement was verified by the fresh canonical 331-check suite. E/Space/ACT applies only to actors with source-supported interactions and their normal proximity/mode/task gates. No new civilian movement was needed: all **15** safe civilians already wander. All **five** City Bandits preserve approved bounded movement. Newly restored civilian bindings: **0**; all four Oakleaf bindings already existed and were preserved. The shared-host lifetime correction keeps them alive after battle.

## Oakleaf

| Node | Classification | ZIP dialogue | Current dialogue | Safe civilian wander | Wandering | Binding | E | Space | ACT |
|---|---|---|---|---|---|---|---|---|---|
| `girl_npc` | civilian / dialogue | YES | YES | YES | YES | YES | YES | YES | YES |
| `NPC` | civilian / dialogue | YES | YES | YES | YES | YES | YES | YES | YES |
| `villager-female` | civilian / dialogue | YES | YES | YES | YES | YES | YES | YES | YES |
| `NPC1` | civilian / dialogue | YES | YES | YES | YES | YES | YES | YES | YES |
| `Bandits` | enemy / quest-critical / trigger-dependent | YES | YES | NO | NO | YES | YES | YES | YES |
| `Bandits2` | enemy | NO | NO | NO | NO | NO | NO | NO | NO |
| `Bandits3` | enemy | NO | NO | NO | NO | NO | NO | NO | NO |
| `Bandits4` | enemy | NO | NO | NO | NO | NO | NO | NO | NO |
| `Bandits5` | enemy | NO | NO | NO | NO | NO | NO | NO | NO |
| `Boss-Bandit` | boss / fixed | NO | NO | NO | NO | NO | NO | NO | NO |

## City of Knowledge

| Node | Classification | ZIP dialogue | Current dialogue | Safe civilian wander | Wandering | Binding | E | Space | ACT |
|---|---|---|---|---|---|---|---|---|---|
| `adult-male_npc` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `city_npc` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `old_adult_women` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `old_npc` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `girl_npc` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `Bandits` | enemy | NO | NO | NO | YES | NO | NO | NO | NO |
| `Bandits2` | enemy | NO | NO | NO | YES | NO | NO | NO | NO |
| `Bandits3` | enemy | NO | NO | NO | YES | NO | NO | NO | NO |
| `Bandits4` | enemy | NO | NO | NO | YES | NO | NO | NO | NO |
| `Bandits5` | enemy | NO | NO | NO | YES | NO | NO | NO | NO |

## Pinehill

| Node | Classification | ZIP dialogue | Current dialogue | Safe civilian wander | Wandering | Binding | E | Space | ACT |
|---|---|---|---|---|---|---|---|---|---|
| `old_adult_women` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `old_npc` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `male-npc` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `girl_npc` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `villager-male` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `villager-female` | civilian / decorative | NO | NO | YES | YES | NO | NO | NO | NO |
| `Bandits` | enemy | NO | NO | NO | NO | NO | NO | NO | NO |
| `Bandits2` | enemy | NO | NO | NO | NO | NO | NO | NO | NO |
| `Bandits3` | enemy | NO | NO | NO | NO | NO | NO | NO | NO |
| `Bandits4` | enemy | NO | NO | NO | NO | NO | NO | NO | NO |
| `Boss-Wizard` | boss / fixed | NO | NO | NO | NO | NO | NO | NO | NO |


All four Oakleaf greetings retain `Hello traveler! Welcome to our town.`. The First Bandit retains its source challenge. No dialogue text was invented.

**NO SOURCE-SUPPORTED DIALOGUE:** City `adult-male_npc`, `city_npc`, `old_adult_women`, `old_npc`, `girl_npc`; Pinehill `old_adult_women`, `old_npc`, `male-npc`, `girl_npc`, `villager-male`, `villager-female`.

Fresh motion checks confirm 30 px/s, home radius 42px, idle phases, bounded collision-aware movement, player collision/no pass-through, and dialogue pause/resume. The existing collision masks do not enable NPC-to-NPC collision; no such new behavior is claimed. Teacher, Tutorial scripted movement, bosses and trigger-dependent actors were not given ambient wandering.

Complete bindings, nested children and source hashes: [actor source audit](C:/Users/vince/Documents/Capstone-Project/capstone-theresians-quest/docs/qa/2026-09-07-final-actor-source-audit.md).

## Preservation

| Protected feature | Delta during this task |
|---|---:|
| Oakleaf / City / Pinehill maps, props, spawns, TileMaps/TileSets | 0 |
| Tutorial dialogue | 0; entire player_house.tscn byte-identical to ZIP |
| Shared normal dialogue layout | 0; Oakleaf 520×80, Teacher House 460×126, bottom margin 40px |
| Brown controller visual geometry/assets | 0 |
| Controller lifecycle and keyboard actions | 0 |
| Task Complete / Task Trigger / Current Quest / timer | 0 |
| Settings / Teacher House | 0 |
| Original battle scenes/resources, animations/effects/hearts | 0 |
| Login, loading, provider, Save schema, RemoteSync, Grade+Difficulty, backend/web | 0 |
| Unrelated product delta count | **0** |

Tutorial portrait, instruction image, Next binding, original anchors/offsets and controller obstruction/restoration were checked at 1215×545, 844×390 and 1280×800 windows. Normal dialogue wrapping, padding, long-text expansion and return to approved size passed. No layout was redesigned. Production QA remains enabled as requested.

## Fresh canonical verification

| Suite | Passed | Failed |
|---|---:|---:|
| Actual world route, checkpoint/save/load/RemoteSync and all four post-battle greetings | 236 | 0 |
| All eight VS scenes × victory/defeat through real QuestionProvider and isolated transport | 972 | 0 |
| Full civilian and City Bandit preservation, collision, ACT/E/Space | 331 | 0 |
| Frozen normal/Tutorial UI and controller lifecycle across viewport sizes | 433 | 0 |
| **Total** | **1,972** | **0** |

Final runs: **SCRIPT ERROR = 0; resource-load errors = 0; parse errors = 0**. `git diff --check` and existing staged `git diff --cached --check`: **PASS**. Existing UID fallback warnings remain; resources loaded successfully using their preserved paths. These warnings were not repaired by changing frozen resources.

New harness development initially found assertion/typing mistakes (JSON key order, stripped task text, checking a replaced world instance, queued payload shape, inferred type, and a missing activity event key). These were fixed only in new test files; the initial failed harness log is preserved locally. The counts above are final complete reruns, not a claim that every development attempt passed.

All Godot engine actions used Godot MCP and the canonical root. The only remaining Godot process is canonical editor PID 4852. Active worktree runtime count: **0**. Every production transport was removed or replaced before fixture gameplay. Test saves/queues were uniquely named and isolated; no human save was modified. No deployment, production write, question publication/removal, live OpenAI call, APK/signing or worktree implementation occurred.

Verification hashes/counts: [preservation proof](C:/Users/vince/Documents/Capstone-Project/capstone-theresians-quest/docs/qa/2026-09-07-final-preservation-proof.json). Transport isolation: [isolation proof](C:/Users/vince/Documents/Capstone-Project/capstone-theresians-quest/docs/qa/2026-09-07-final-runtime-isolation.json).

## Delivery and remaining items

Focused commit groups:

1. `world/QuestUI.gd`: female first-Bandit route and preserved post-battle greeting host.
2. `scripts/game_state.gd`: saved-checkpoint/title reconciliation.
3. Four new `tools/final_*` harness `.gd/.tscn` pairs and the new source audits, runtime results, isolation/preservation proof and this report. Supporting generated UID sidecars are included only if present. Prior test bodies and evidence are not overwritten.

Exact commit IDs and complete path lists are recorded after committing in `docs/qa/2026-09-07-final-commit-result.json` and the final user-facing response. The final delivered HEAD is the evidence commit containing this report. Existing unrelated dirty/staged work remains separate; this is verified canonical working-tree delivery, not a clean-checkout release claim.

- **PRODUCT/RUNTIME BLOCKERS:** none found in the tested source-supported chain after the three corrections. Full later-game traversal cannot be claimed because the City flag is never set true by the supplied gameplay source and later encounters lack bindings; see source gaps. No gate or trigger was changed to conceal that limitation.
- **SOURCE-EVIDENCE GAPS:** no later City/Pinehill/Boss/Wizard/Teacher milestone chain, world encounter bindings, City unlock writer or complete quest denominator. ZIP-era saves omit quest checkpoint and Tutorial metadata, so absent progress cannot safely be reconstructed. Deliberately loading an older valid save restores that save, not a global maximum. Early Tutorial exit has no explicit source guard; its actual physical traversal before completion remains unverified, documented in the quest audit, and unchanged under the frozen trigger scope.
- **HUMAN RECHECK ITEMS:** battle appearance and original timing, click/touch usability, all four post-battle greetings, Tutorial completion and save/load behavior in the human session; long real backend question readability; actual map traversal/early Tutorial exit. Automated checks do not establish human approval.
- **RELEASE/INFRASTRUCTURE BLOCKERS:** release/deployment/signing/production validation were not attempted or authorized. Existing approved-signing and later release gates remain outside this task. Website metrics/role parity and the full publishing pipeline were preserved, not revalidated through production.

**TECHNICALLY RESTORED — HUMAN RECHECK PENDING.**
