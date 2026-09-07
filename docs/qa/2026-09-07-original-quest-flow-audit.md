# Developer ZIP quest-flow audit before product edits

Canonical Godot starting HEAD: `843b0b7f8d38d4417cfce9f566863505aa9e2042`.
Canonical web starting HEAD: `ed83226bc5adaf577c05f11e3978283714cfd7b4`.

Source: `C:\Users\vince\Downloads\capstone-theresians-quest6.zip`, root `capstone-theresians-quest6/` only. Embedded worktrees were excluded. The full root `.gd` and `.json` source was searched; relevant scene script bindings were inspected.

## Exact implemented baseline

The separate `interiors/TutorialNPC.gd` runs eight instruction steps (0–7) and hides itself after the final Next press. It does not advance a persistent tutorial quest ID. Its last line instructs the player to visit Teacher House.

`scripts/game_state.gd` has exactly three ordered `tasks` entries, identified only by numeric indices in the ZIP:

| Index | ZIP quest text | Completion / routing |
|---|---|---|
| 0 | Go to the Teacher’s house (the source contains a damaged apostrophe character) | `world/Task1.gd` checks its exported index, invokes the assigned QuestUI, then removes the trigger. QuestUI shows the two arrival dialogue lines and calls `GameState.complete_task()`. |
| 1 | Talk to the Teacher | Two dialogue lines: travel through the forest to City of Knowledge; Forest Path unlocked. QuestUI then increments the index. |
| 2 | Challenge the player with math questions | `next_scene = res://Battle/Battle-Enemy/male_vs_bandit.tscn`; `complete_after_battle = true`. QuestUI instantiates that overlay, awaits `battle_finished`, then increments the index. |

After index 2, there is no further task entry. The ZIP QuizManager does not declare the signal its QuestUI awaits; preserving newer lifecycle integration is necessary rather than copying the old files wholesale.

`city_of_knowledge_unlocked` is initialized/reset false, serialized and loaded, and read by the door prerequisite. No gameplay writer sets it true. City and Pinehill scenes contain map/NPC assets and doors but no additional quest-state chain. The archive has complete Boss Bandit, Teacher and Wizard VS presentation scenes, but no task routing to them. Legacy `Task2/Task3/Quest2/Quest3` scripts refer to undefined `task_2_done/task_3_done`; they do not establish a functioning later chain.

The ZIP therefore does **not** implement the remembered repeated-Bandit → Boss Bandit → Teacher return → City unlock sequence. This discrepancy was reported before editing progression. A clarification is pending for the authoritative missing Bandit count and City/Pinehill milestones, or a baseline containing them. No missing gameplay or percentage denominator will be invented from the remembered outline.

## Current comparison

The canonical active task list retains those three entries in the same order. It adds backend-safe activity IDs: `go-to-teachers-house`, `talk-to-the-teacher`, `first-bandit-math-challenge`; Tutorial has separate `tutorial` activity metadata. Version-8 persistence, victory-only encounter completion, deliberate dialogue continuation and gender routing are integration/preservation behavior, not evidence of deleted later quests.

No removed, reordered Boss/Teacher-return/City/Pinehill chain can be proven from this ZIP. A three-task or four-activity denominator would falsely describe the first Bandit as the end of the whole intended game and is not authorized as Total Progress.

One concrete ingestion defect is in `scripts/remote_sync.gd::_activity_metadata_for_event`: `task_completed` uses the previous task index, but `quest_completed` incorrectly uses the new index. Teacher conversation completion can consequently be labeled as the following Bandit activity. Correcting that lookup does not change quest order, triggers or current quest state.

Current post-load reconciliation already exists as dirty work in `scripts/game_state.gd`: an obsolete saved quest title is reconciled to its saved checkpoint. It must be preserved and verified, not overwritten with ZIP version-5 save code. The current backend receives a saved `progress_percentage` field whose Godot variable is never computed beyond initialization/load; this is not an authoritative whole-game completion formula.

Maps/backgrounds and all dialogue/notification/HUD placement remain frozen at the task-start working baseline. Separate battle and Student Progress audits record other proven findings.
