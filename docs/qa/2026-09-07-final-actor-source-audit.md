# Final actor source audit

Canonical HEAD: `dee8b5cdb27311e75451a6042063bed8aa67800f`. Developer ZIP: `C:\Users\vince\Downloads\capstone-theresians-quest6.zip`; only the canonical ZIP prefix was read. No product edit or Godot execution was performed.

Fresh source inspection confirms all 15 safe civilians already use the approved wanderer. No additional safe unmoving civilian and no missing source-supported civilian dialogue binding were found. Preserve current movement and dialogue code. Five City Bandits remain approved movers.

The tables cover 31 unique outdoor NPC/enemy/boss actors. Visual children are not extra actors. YES for wandering/E/Space/ACT means configured in current source, subject to game mode and proximity/task gating; it is not a fresh runtime pass or human acceptance.

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

## Source dialogue and children

All four Oakleaf speakers retain the exact ZIP greeting: `Hello traveler! Welcome to our town.`. All underlying original NPC/enemy sprite scenes match the ZIP after newline normalization. Each greeting remains on its AnimatedSprite2D Visual; its relative host resolves to CanvasLayer/Panel. Each sensor has both body-entered and body-exited connections to the interaction component.

- `girl_npc`: `girl_npc/InteractableArea`, target `NodePath("../Visual")`; children: `girl_npc`, `girl_npc/Visual`, `girl_npc/FootCollision`, `girl_npc/Area2D`, `girl_npc/Area2D/CollisionShape2D`, `girl_npc/InteractableArea`.
- `NPC`: `NPC/Visual/InteractableArea`, target `NodePath("..")`; children: `NPC`, `NPC/Visual`, `NPC/FootCollision`, `NPC/Visual/Area2D`, `NPC/Visual/Area2D/CollisionShape2D`, `NPC/Visual/InteractableArea`.
- `villager-female`: `villager-female/InteractableArea`, target `NodePath("../Visual")`; children: `villager-female`, `villager-female/Visual`, `villager-female/FootCollision`, `villager-female/Area2D`, `villager-female/Area2D/CollisionShape2D`, `villager-female/InteractableArea`.
- `NPC1`: `NPC1/Visual/InteractableArea`, target `NodePath("..")`; children: `NPC1`, `NPC1/Visual`, `NPC1/FootCollision`, `NPC1/Visual/Area2D`, `NPC1/Visual/Area2D/CollisionShape2D`, `NPC1/Visual/InteractableArea`.

No Oakleaf greeting requires a new binding. First Oakleaf Bandits retains the source line `You want to pass? Solve this first!` through BanditTaskTrigger/TaskDialogAdapter, requiring task index 2. Actor position, sensor, and static collision remain fixed.

NO SOURCE-SUPPORTED DIALOGUE:

- City of Knowledge / `adult-male_npc`.
- City of Knowledge / `city_npc`.
- City of Knowledge / `old_adult_women`.
- City of Knowledge / `old_npc`.
- City of Knowledge / `girl_npc`.
- Pinehill / `old_adult_women`.
- Pinehill / `old_npc`.
- Pinehill / `male-npc`.
- Pinehill / `girl_npc`.
- Pinehill / `villager-male`.
- Pinehill / `villager-female`.

Sharing artwork with an Oakleaf speaker is not evidence of dialogue in another map. No new text is justified.

## Motion and input contracts

All 15 civilians and the five City Bandits resolve to scripts/decorative_npc_wanderer.gd: 30 px/s, radius 42 from a captured home position, idle 1.5 seconds, velocity capped to remaining distance, collision-aware move_and_slide(), collision idle, mode pause, and a new idle phase on resuming exploration. Every wrapper has an explicit foot collider and uses collision layer 2/mask 1. Player collision mask 3 permits map and NPC collision. The preserved mask does not enable NPC-to-NPC collision; this report makes no such claim.

E and Space are installed by InputManager when the interact action is absent. Mobile ACT feeds the same press edge. InteractionManager consumes that edge once and locks until release. QuestUI separately waits for the opening press to be released before advancing. All four greeting components and the first Bandit adapter use this chain. Mobile controls retain exploration/DIALOGUE visibility rules and are hidden in BATTLE; lifecycle signals restore visibility when returning.

Fresh MCP motion/collision/dialogue/input tests remain the parent task. The prior 331 checks were read only as a reference and are not presented as new evidence.

## Supplemental actors and protected nodes

- interiors/player_house.tscn/NPCTeacher: source/current Tutorial dialogue present; retain only its original scripted movement. No ambient wandering.
- interiors/teacher_house.tscn/Teacher: source/current quest dialogue present; fixed, with current Teacher interaction binding. No ambient wandering.
- Each outdoor map has one runtime player selected by gender: Player-male or CharacterBody2D, spawned by gameplay_scene.gd. These are player actors, not omitted NPCs.
- School and NPC-house interiors contain no NPC actor instances. Teacher tables and the Pinehill wizard-house are props.
- Boss-Bandit and Boss-Wizard are fixed. There is no separate outdoor ordinary Wizard actor in these three source maps.

## Concrete gaps and minimal change decision

No civilian movement or dialogue product change is required. Newly eligible civilian list: empty. Newly restored dialogue-binding list: empty. All 15 currently approved civilian movers must remain.

The remaining 15 enemy/boss map actors have no serialized world encounter interaction binding in either the ZIP or current actor sources. This is a source-evidence gap for battle encounter reachability, not proof of lost civilian dialogue. Preserve map geometry and City Bandit movement while the battle audit resolves it.

The original source cannot authorize dialogue for the 11 silent civilians. This remains a SOURCE-EVIDENCE GAP awaiting separately supplied/authorized text. NPC collision, idle/bounds, E/Space and ACT behavior are HUMAN RECHECK ITEMS after fresh MCP verification.

## Preservation boundary

This audit changed only its two report files and the parent-requested test-only wrapper tools/final_civilian_preservation_test.gd. The wrapper only redirects _write_json result output; it inherits all original test bodies and baseline comparisons. No product source was edited. Source hashes are recorded in the companion JSON.

Frozen normal dialogue source calculation remains Oakleaf 480x88 serialized -> 520x80 runtime and Teacher 420x140 serialized -> 460x126 runtime through the existing QuestUI adjustment, with 40px bottom margin. Do not add another adjustment. Tutorial original layout and all controller visuals remain frozen.

The current dirty work was inspected before reporting; it was neither reverted nor committed. Runtime ownership and .worktrees runtime count are held by the parent task.
