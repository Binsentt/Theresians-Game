# Civilian NPC inventory and complete expansion plan

Implementation follow-up: all ten listed safe civilians were converted using the unchanged existing wanderer, bringing the tested civilian mover count to fifteen. Canonical MCP verification passed 331 checks, including all fifteen collision lanes, bounds/idle/speed, and all four Oakleaf greetings through ACT/E/Space. No dialogue was invented for the eleven silent City/Pinehill civilians. The tables below retain their explicitly pre-expansion source inventory. The later captured unapproved map drift was reversed after explicit user authorization; all three approved source hashes and the fresh 331-check canonical runtime suite pass. Archived copies remain intact behind docs/qa/.gdignore.

Canonical root: `C:\Users\vince\Documents\Capstone-Project\capstone-theresians-quest`. Starting HEAD: `3d846de475713d1f34a747d345f36217a453586f`. Original ZIP: `C:\Users\vince\Downloads\capstone-theresians-quest6.zip`; only `capstone-theresians-quest6/` was read, excluding worktree content.

31 unique outdoor actors. Pinehill entry wrapper expands scenes/2nd Village/Pinehill Village.tscn and is not counted twice. Visual child instances are not counted twice. Linked separate interiors inspected for protected teachers and School actors.

Static eligibility only; moving/keyboard/ACT flags describe configuration, not runtime or human acceptance. Parent must perform canonical Godot MCP tests.

## Counts before expansion

| Map | Actors | Civilians | Enemies/bosses | Civilian dialogue | Civilian movers configured | Additional safe civilians |
|---|---:|---:|---:|---:|---:|---:|
| Oakleaf | 10 | 4 | 6 | 4 | 2 | 2 |
| City of Knowledge | 10 | 5 | 5 | 0 | 1 | 4 |
| Pinehill | 11 | 6 | 5 | 0 | 2 | 4 |
| Total | 31 | 15 | 16 | 4 | 5 | 10 |

City also has five approved moving Bandits. Preserve all five; they do not count as civilian expansion. After all ten eligible conversions, all fifteen civilians would be configured to wander. Eleven remain without source-supported dialogue.

## Every outdoor NPC

YES in input/motion columns means source-configured eligibility, subject to the condition and runtime caveat above. Source positions are map-local; use `2026-09-07-civilian-expansion-runtime-baseline.json` for measured canonical world transforms through the Pinehill entry wrapper. The full JSON includes all expanded node properties and original/current script bindings.

### Oakleaf

| Node | Character / class | ZIP dialogue | Current dialogue | Safe civilian movement | Moving | Area | E/Space | ACT | Recommended action |
|---|---|---|---|---|---|---|---|---|---|
| `girl_npc` | Girl civilian (Female npc.png); civilian / dialogue | YES | YES | YES | YES | YES | YES | YES | Preserve existing bounded movement and source dialogue |
| `NPC` | Male civilian (Male npc.png); civilian / dialogue | YES | YES | YES | NO | YES | YES | YES | Expand using bounded wrapper; keep dialogue target, Area, geometry and connections under Visual |
| `villager-female` | Female villager (villager-female.png); civilian / dialogue | YES | YES | YES | YES | YES | YES | YES | Preserve existing bounded movement and source dialogue |
| `NPC1` | Older woman civilian (Female teacher.png; no Teacher quest role); civilian / dialogue | YES | YES | YES | NO | YES | YES | YES | Expand using bounded wrapper; keep dialogue target, Area, geometry and connections under Visual |
| `Bandits` | Normal Bandit; enemy / quest-critical / trigger-dependent | YES | YES | NO | NO | YES | YES | YES | Keep fixed; preserve encounter role |
| `Bandits2` | Normal Bandit; enemy | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |
| `Bandits3` | Normal Bandit; enemy | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |
| `Bandits4` | Normal Bandit; enemy | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |
| `Bandits5` | Normal Bandit; enemy | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |
| `Boss-Bandit` | Boss Bandit; boss / fixed | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |

### City of Knowledge

| Node | Character / class | ZIP dialogue | Current dialogue | Safe civilian movement | Moving | Area | E/Space | ACT | Recommended action |
|---|---|---|---|---|---|---|---|---|---|
| `adult-male_npc` | Adult male civilian (civilian male.png); civilian / decorative | NO | NO | YES | NO | NO | NO | NO | Expand using bounded wrapper; NO SOURCE-SUPPORTED DIALOGUE |
| `city_npc` | City/shopkeeper civilian (Shopkeeper (1).png); civilian / decorative | NO | NO | YES | YES | NO | NO | NO | Preserve existing bounded movement; NO SOURCE-SUPPORTED DIALOGUE |
| `old_adult_women` | Older woman civilian (Female teacher.png; no Teacher quest role); civilian / decorative | NO | NO | YES | NO | NO | NO | NO | Expand using bounded wrapper; NO SOURCE-SUPPORTED DIALOGUE |
| `old_npc` | Senior civilian (civilian senior .png); civilian / decorative | NO | NO | YES | NO | NO | NO | NO | Expand using bounded wrapper; NO SOURCE-SUPPORTED DIALOGUE |
| `girl_npc` | Girl civilian (Female npc.png); civilian / decorative | NO | NO | YES | NO | NO | NO | NO | Expand using bounded wrapper; NO SOURCE-SUPPORTED DIALOGUE |
| `Bandits` | Normal Bandit; enemy | NO | NO | NO | YES | NO | NO | NO | Preserve approved City Bandit movement; no civilian dialogue |
| `Bandits2` | Normal Bandit; enemy | NO | NO | NO | YES | NO | NO | NO | Preserve approved City Bandit movement; no civilian dialogue |
| `Bandits3` | Normal Bandit; enemy | NO | NO | NO | YES | NO | NO | NO | Preserve approved City Bandit movement; no civilian dialogue |
| `Bandits4` | Normal Bandit; enemy | NO | NO | NO | YES | NO | NO | NO | Preserve approved City Bandit movement; no civilian dialogue |
| `Bandits5` | Normal Bandit; enemy | NO | NO | NO | YES | NO | NO | NO | Preserve approved City Bandit movement; no civilian dialogue |

### Pinehill

| Node | Character / class | ZIP dialogue | Current dialogue | Safe civilian movement | Moving | Area | E/Space | ACT | Recommended action |
|---|---|---|---|---|---|---|---|---|---|
| `old_adult_women` | Older woman civilian (Female teacher.png; no Teacher quest role); civilian / decorative | NO | NO | YES | NO | NO | NO | NO | Expand using bounded wrapper; NO SOURCE-SUPPORTED DIALOGUE |
| `old_npc` | Senior civilian (civilian senior .png); civilian / decorative | NO | NO | YES | YES | NO | NO | NO | Preserve existing bounded movement; NO SOURCE-SUPPORTED DIALOGUE |
| `male-npc` | Male civilian (Male npc.png); civilian / decorative | NO | NO | YES | NO | NO | NO | NO | Expand using bounded wrapper; NO SOURCE-SUPPORTED DIALOGUE |
| `girl_npc` | Girl civilian (Female npc.png); civilian / decorative | NO | NO | YES | NO | NO | NO | NO | Expand using bounded wrapper; NO SOURCE-SUPPORTED DIALOGUE |
| `villager-male` | Male villager (male-villager.png); civilian / decorative | NO | NO | YES | YES | NO | NO | NO | Preserve existing bounded movement; NO SOURCE-SUPPORTED DIALOGUE |
| `villager-female` | Female villager (villager-female.png); civilian / decorative | NO | NO | YES | NO | NO | NO | NO | Expand using bounded wrapper; NO SOURCE-SUPPORTED DIALOGUE |
| `Bandits` | Normal Bandit; enemy | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |
| `Bandits2` | Normal Bandit; enemy | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |
| `Bandits3` | Normal Bandit; enemy | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |
| `Bandits4` | Normal Bandit; enemy | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |
| `Boss-Wizard` | Boss Wizard; boss / fixed | NO | NO | NO | NO | NO | NO | NO | Keep fixed; preserve encounter role |

## Dialogue evidence and actual cause

No current missing source-supported civilian binding: all four explicit ZIP Oakleaf bindings are present. Prior movement wrapper risk was loss of script compatibility (AnimatedSprite2D script on CharacterBody2D) and one extra nesting level for quest_ui_path; current girl/villager-female bind old_adult_women_Dialog.gd to Visual and target ../Visual with host ../../CanvasLayer/Panel. Other eleven civilians were unbound decorative sprites in the ZIP; no proven lost binding or actor-specific text found.

The exact preserved line is `Hello traveler! Welcome to our town.` ZIP `NPC/Npc/old_adult_women_Dialog.gd:10` supplies it; the current script retains it at line 8. ZIP Oakleaf explicitly binds this script at nodes `girl_npc` (line 863), `NPC` (877), `villager-female` (892), and `NPC1` (913), plus their Area signals. The base sprite scenes are byte-equivalent as normalized text between ZIP and current and do not contain dialogue scripts. City/Pinehill map instances have no dialogue script, text override, sensor, or component. Sharing the same artwork with an Oakleaf speaker does not prove a lost binding in another map.

`NO SOURCE-SUPPORTED DIALOGUE`: City `adult-male_npc`, `city_npc`, `old_adult_women`, `old_npc`, `girl_npc`; Pinehill `old_adult_women`, `old_npc`, `male-npc`, `girl_npc`, `villager-male`, `villager-female`. Do not fabricate text or attach Oakleaf lore based only on shared assets.

Oakleaf first Bandit has its original task dialogue, currently connected through `Bandits/BanditTaskTrigger/TaskDialogAdapter` at required task index 2. Other Bandits/bosses have no world-dialogue interaction binding in these map sources. Their separate battle presentation/routing audit must not be confused with civilian dialogue restoration.

## Complete ten-actor minimal expansion plan

Reuse `scripts/decorative_npc_wanderer.gd` unchanged: CharacterBody2D, group `decorative_wanderer`, collision layer 2/mask 1, 30 px/s, home-relative radius 42, idle 1.5 seconds, `move_and_slide`, and GameState mode pause. No new movement algorithm. Preserve root map position/z-index and the exact visible AnimatedSprite transform, resource, frame, animation, child nodes, and existing signal connections.

- `NPC/Npc/wandering_male_npc.tscn` (new wrapper of `NPC/Npc/male_npc.tscn`): `Oakleaf/NPC`, `Pinehill/male-npc`. Oakleaf Visual scale 0.1; Pinehill Visual 0.095. Preserve Oakleaf children under Visual and dialogue host path ../../CanvasLayer/Panel.
- `NPC/Npc/wandering_old_adult_women.tscn` (new wrapper of `NPC/Npc/old_adult_women.tscn`): `Oakleaf/NPC1`, `City of Knowledge/old_adult_women`, `Pinehill/old_adult_women`. Pinehill Visual animation walk_right; others walk_left. Preserve Oakleaf children and uppercase Player group under Visual. Dialogue host ../../CanvasLayer/Panel.
- `NPC/Npc/wandering_adult_male_npc.tscn` (new wrapper of `NPC/Npc/adult_male_npc.tscn`): `City of Knowledge/adult-male_npc`. Preserve walk_up and z_index 1.
- `NPC/Npc/wandering_old_npc.tscn` (reuse): `City of Knowledge/old_npc`. Move walk_down animation override to Visual; keep current visual scale.
- `NPC/Npc/wandering_girl_npc.tscn` (reuse): `City of Knowledge/girl_npc`, `Pinehill/girl_npc`. City Visual walk_right. Pinehill preserve default. No dialogue or interactive Area exists for either actor.
- `NPC/Npc/wandering_villager_female.tscn` (reuse): `Pinehill/villager-female`. Preserve Visual scale 0.085 and walk_up.

New visual source details: male frame 106x177/default scale 0.095, older-woman frame 160x177/scale 0.065, adult-male frame 125x173/scale 0.077. All three provide `default`, `walk_down`, `walk_left`, `walk_right`, `walk_up`; no animation remapping is required.

For the two Oakleaf talkers, keep the preserved AnimatedSprite scene at `NPC/Visual` or `NPC1/Visual`, move their current `Area2D` and `InteractableArea` under that Visual, and keep all local sensor properties unchanged. Their `interaction_target_path = NodePath("..")` still resolves to the greeting target. The greeting target must use `quest_ui_path = NodePath("../../CanvasLayer/Panel")`. Retarget the existing body_entered/body_exited signals to the new paths. Preserve priorities 35 and 25 and add editable instance declarations where map-level child overrides require them.

| Actor | Map position | Visual scale | Sensor local size | Sensor local center | Resulting world size | Resulting world center |
|---|---|---|---|---|---|---|
| NPC | (906, 276) | 0.1 | (50, 100) | (5, 0) | (5, 10) | (906.5, 276) |
| NPC1 | (964, 173) | 0.065 | (92.30762, 138.46143) | (0, 23.076904) | approx (6, 9) | approx (964, 174.5) |

The existing runtime foot collision generated by `NpcCollisionManager` is distinct from the interaction sensor. For NPC it is world size `(4.77, 2.832)` at `(906, 283.788)`; for NPC1 `(4.68, 1.8408)` at `(964, 178.0622)`. If retaining the exact collider footprint, copy those physical dimensions into each wrapper foot collider rather than accidentally scaling a generic foot collider twice. New wrapper sprites are skipped by NpcCollisionManager because their direct parent is a CharacterBody2D in `decorative_wanderer`; the explicit foot collider must therefore exist.

NPC1 has an existing uppercase `Player` group on the old AnimatedSprite. Preserve it on Visual. Do not add lowercase `player`/`player_character` to the wrapper. Live doors (`scripts/door.gd:168`), interaction areas (`scripts/interactable_area.gd:162`), task progress triggers (`world/task_progress_trigger.gd:17,64`), and the legacy task trigger (`world/Task1.gd:15`) only accept lowercase player groups, so a bounded civilian cannot trigger quest/door progression merely because of this preserved uppercase group.

## Protected actors and validation gates

Keep Oakleaf `Bandits` and its trigger fixed; keep other Oakleaf Bandits, Boss-Bandit, all Pinehill Bandits and Boss-Wizard fixed. Preserve all five City Bandits and their approved movement unchanged. The Teacher in `interiors/teacher_house.tscn` and tutorial NPCTeacher in `interiors/player_house.tscn` are supplementary quest-critical actors with source dialogue; neither is eligible for civilian wandering. School and NPC-house interiors contain no NPC actor instances. The wizard-house node in Pinehill is a building prop, not an extra Wizard actor.

Before implementation, parent should capture the current dirty map resource/transform blocks and assert they do not change. Verify all ten new civilians instantiate with the same sprite size/position and actual explicit foot collision. Check collision with player and map, no home drift or teleport, idle periods, and mode pause/resume. For Oakleaf NPC/NPC1 physically enter and leave the original sensor, test keyboard E and Space and mobile ACT, one opening line and one deliberate close, mode restoration, pause/resume, and no quest/activity changes. Verify existing Oakleaf moving speakers still retain their dialogue and all City Bandits retain their current motion. Use canonical Godot MCP only.

Status: source inventory complete; product implementation and canonical runtime/human verification are owned by the parent task. No product files were modified by this subtask.
