# Final quest source audit

Canonical starting HEAD: `dee8b5cdb27311e75451a6042063bed8aa67800f`. Report HEAD: `dee8b5cdb27311e75451a6042063bed8aa67800f`. Developer ZIP read directly under its canonical prefix, excluding archival worktrees. No product edit or Godot run.

The ZIP proves three task entries, preceded by a separate Tutorial narrative. Current canonical retains that task order and its approved persistent Tutorial state. No later milestone chain is proved. The three focused working hunks are coherent; their runtime acceptance belongs to the parent verification.

## Exact sequence and evidence classification

| State | Proven/current transition | Classification |
|---|---|---|
| 0, Tutorial incomplete | Tutorial | ZIP narrative source-proven; authoritative Tutorial state/persistence is existing approved canonical behavior |
| 0 -> 1 | Go to the Teacher's House -> Talk to the Teacher | source-proven task order; existing canonical trigger/persistence behavior |
| 1 -> 2 | Talk to the Teacher -> Challenge the player with math questions | source-proven task order and narrative; existing canonical deliberate input |
| 2 -> 3 | First Bandit math challenge -> authored task list exhausted | source-proven final listed task; current victory/defeat behavior preserved |
| No authored entry beyond index 2 | City/Pinehill/Boss/Wizard/Teacher battle milestones | not proven by provided baseline |

`Tutorial`: ZIP: TutorialNPC performs upward movement for 3 seconds then eight steps 0..7, ending with instruction to come to Teacher house. At step >7 it hides itself; no GameState Tutorial completion field/call exists. Current: start_new_game sets Tutorial; is_tutorial_active is index 0 and incomplete flag; Tutorial next_step >7 calls complete_tutorial_activity, leaving index 0 and changing current_quest to task 0.

`Go to the Teacher's House -> Talk to the Teacher`: ZIP: Oakleaf TeacherHouseTaskTrigger uses world/Task1.gd default task index 0; dialogue and QuestUI completion increment to 1. Current: Same fixed trigger uses task_progress_trigger; valid player at required index 0 invokes advance_task_and_save once. Completed triggers ignore index >0.

`Talk to the Teacher -> Challenge the player with math questions`: ZIP: Teacher/Area2D2 binds Task1 with trigger_for_task_index 1; QuestUI presents the two original Teacher lines, then completes. Current: TeacherTaskInteraction gates exact index 1 and shared QuestUI advances/saves at conversation completion. The line Reward: Forest Path unlocked is narrative; no City flag writer is proven.

`First Bandit math challenge -> authored task list exhausted`: ZIP: Oakleaf first Bandit trigger_for_task_index 2; task next_scene male_vs_bandit; QuestUI awaits battle_finished, increments, and destroys its host after final task. It does not branch on signal win/loss result. Current: Exact index 2 ACT/E/Space adapter; original male/female normal VS; advances/saves only on battle_won. Retry/defeat leaves checkpoint; terminal current_quest is No active quest.

`City/Pinehill/Boss/Wizard/Teacher battle milestones`: ZIP: Map/battle assets exist; no later tasks array entries or source-backed authoritative quest denominator. Current: Still three tasks. Do not invent later objectives, completion order, or Total Progress percentage.

The original task 0 text has an encoding replacement character in the possessive; current approved text is Go to the Teacher's House. No need to restore that encoding defect. The two Teacher narrative lines and first Bandit challenge line retain source content.

## Review of focused working hunks

### scripts/game_state.gd apply_save_data checkpoint-to-title reconciliation

Focused and coherent for a valid saved checkpoint; fresh runtime test required.

State had separate checkpoint and title representations. Before bb65a3f, advance_task_and_save incremented checkpoint without updating current_quest. bb65a3f repaired future progression writes, but apply_save_data still accepted obsolete saved current_quest beside a newer checkpoint. HUD uses current_quest as fallback once tasks are exhausted.

Load index 1 -> Talk to the Teacher; index 2 -> first Bandit objective; index 3 -> No active quest even if stale title says Go to Teacher House. Index 0 plus Tutorial marker remains Tutorial. Index 0 unmarked legacy title follows existing compatibility behavior and is treated as post-Tutorial.

Does not reconstruct absent historical checkpoint, add milestones, protect against intentional loading of an older valid save, or prove the exact human-observed causal trace without runtime evidence. No save schema keys/version are changed.

Provenance: Advance title write added bb65a3f9; saved title/checkpoint fields predate that; current hunk is pre-existing uncommitted work at audit start.

### world/QuestUI.gd female first-Bandit scene substitution

Focused user-authorized gender correction using original source asset.

ZIP and canonical task entry hardcode male_vs_bandit.tscn; first-Bandit QuestUI previously loaded this for either gender. The ZIP contains female_vs_bandit.tscn, but its quest routing does not select it.

Only female encounters whose next_scene is exactly male_vs_bandit.tscn select female_vs_bandit.tscn. Male path and specialized scene paths are untouched.

Do not claim this selector is restored exact ZIP routing. The source-backed asset plus explicit user requirement justify it. It does not create world encounter bindings or a new milestone chain.

Provenance: Hardcoded route is in ZIP; Git blame attributes task route to 54467ef1.

### world/QuestUI.gd retain shared host after final task

Focused preservation fix for existing civilian dialogue dependency.

The legacy quest-only host queued itself for deletion after the last task. Civilian greetings now call begin_dialogue on the same host. Finishing the first Bandit removed all four civilian targets shared dialogue host until scene reload.

Calls update_task_ui at terminal index, which hides quest bridge UI while keeping the node and its process alive for sibling DialoguePanel greetings. No task increment or quest text logic changes.

Fresh runtime must confirm all four greetings after victory; static source cannot establish human interaction acceptance.

Provenance: Original ZIP QuestUI ends with queue_free; root Git history retains it since de77b52. Shared civilian begin_dialogue usage was introduced by e409454.

## What the save fix proves

A valid saved checkpoint is authoritative. At checkpoint 1 or 2, loading an obsolete Teacher-House title now reconciles it to the current task. At checkpoint 3, it becomes No active quest, so the HUD terminal fallback cannot display the earlier objective. A marked unfinished Tutorial remains Tutorial. No save schema version or key is added.

The audit establishes a plausible code path for stale saved titles, not the exact causal trace of the human observation. Fresh canonical tests must confirm the corrected path. The existing bb65a3f progression write already derives the title before saving; these hunks do not add another live progression advance.

## Actual trigger and legacy callers

- ZIP: Oakleaf TeacherHouseTaskTrigger binds Task1 at default index 0; Teacher/Area2D2 binds Task1 at index 1; first Bandit/BanditTaskTrigger binds Task1 at index 2.
- Current: TeacherHouseTaskTrigger uses the approved one-shot task_progress_trigger; Teacher uses TeacherTaskInteraction at index 1; first Bandit uses InteractableArea and TaskDialogAdapter at index 2.
- Current live completion routes call advance_task_and_save. Legacy complete_task remains defined but has no product caller.
- Task2/Task3 and Quest2/Quest3 are unbound fragments in ZIP/current and use task_2_done/task_3_done, which GameState does not define. Quest3 even writes task_2_done and labels Task 2. Their filenames are not proof of later working stages.

## City gate and later source gaps

- SOURCE-EVIDENCE GAP / current gate blockage from default state: City gate requires city_of_knowledge_unlocked=true; no product source in ZIP/current writes true. Default/reset false, save/load preserves value. No full-history literal true assignment found. Cannot claim new-game City unlock or complete downstream quest progression from source. An existing save with true may pass. No gate change is justified solely by the later-map assets.
- SOURCE-EVIDENCE GAP: ZIP save_game/load_save omit current_task_index and Tutorial state entirely. There is no reliable checkpoint to restore for an old ZIP save that lacks these fields. Do not guess completed milestones from location, dialogue artwork, or absent metadata.
- SOURCE-EVIDENCE GAP: Task2/Task3/Quest2/Quest3 reference undefined task_2_done/task_3_done properties; no canonical or ZIP scene imports them. Only ZIP Task1 is bound to actual task triggers. Quest3 also writes task_2_done and labels Task 2. Treat these as unbound legacy fragments; do not splice them into a new chain.
- SOURCE-EVIDENCE GAP: No later quest entries, boss sequence, City/Pinehill encounter-trigger chain, or complete quest denominator exists in the provided sources. Terminal authored state is list exhaustion, not proof all game content is completed.
- VERIFICATION LIMIT: RemoteSync client observes local state and projects checkpoint/title into progress/activity payloads. It does not assign current_task_index/current_quest from API replies. Supports no client response-driven quest downgrade. Production/backend handling of reordered old saves was not audited or mutated here.

## Early arrival: source-only concern

SOURCE-ONLY CONCERN; no runtime reproduction or new regression claim. No new runtime regression is claimed. The conditional path is:

1. Player leaves Tutorial before next_step >7 through interiors/player_house.tscn node Interior-House Door at (175,159).
2. The node inherits Door-Navigations-Scene2Scene/interior_house_door.tscn, scripted by scripts/door.gd; default trigger_mode is touch.
3. Door body_entered -> _begin_transition: player/transition and optional City unlock checks exist; no Tutorial completion condition.
4. Destination is scenes/oak_leaf_village.tscn with PlayerHouseExitSpawn marker.
5. Player reaches fixed TeacherHouseTaskTrigger at (1143,182) before completing Tutorial.
6. Current task_progress_trigger sees current_task_index 0 and invokes GameState.advance_task_and_save; advancing to 1 makes is_tutorial_active false.

Unproven prerequisite: Whether the human can actually traverse those collisions/controls before Tutorial completion in the canonical runtime.

ZIP behavior: Same interior exit node/scene/script and destination are present in ZIP; neither exit nor Task1 checks Tutorial completion. ZIP had no authoritative Tutorial state to guard.

Report dependency if human/runtime confirms. Tutorial, doors and Teacher Task Trigger remain frozen; this audit does not authorize or invent a guard.

A new guard is not source-proven. This report only identifies the missing condition for a later human/runtime recheck and reports the frozen-trigger dependency; it does not authorize changing the trigger, Tutorial, door or map.

## RemoteSync and acceptance limits

The client sends authoritative save checkpoint/title and does not apply quest/index from response data. Scene entry updates scene identity, not task index. Teacher and Bandit adapters check exact indices; completed triggers do not replay. Save reload receives a clamped persisted checkpoint. None of this recovers an absent old checkpoint, validates backend stale-write ordering, or establishes human acceptance.

No quest denominator or later chain is inferred. Total Progress = Not available remains preferable to an invented percentage. NPC/map/controller/dialogue layout/Teacher Task Trigger/Task Complete/Settings/timer source is unchanged by this audit.

PRODUCT/RUNTIME BLOCKERS must be determined by parent runtime evidence; City gate from default false is a known source-level downstream blockage with missing authorized completion semantics. SOURCE-EVIDENCE GAPS are listed above. HUMAN RECHECK ITEMS include natural Tutorial completion/early exit, post-battle quest, Save/Load and interaction. No release/infrastructure operation was performed.
