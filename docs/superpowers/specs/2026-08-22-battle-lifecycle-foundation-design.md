# Battle Lifecycle Foundation Design

## Goal

Add one reusable battle lifecycle without changing the implemented quest order or creating absent City, Deep Forest, Old Man, Wizard, or final Teacher story progression.

## Boundaries

`GameState` owns a serializable encounter context: stable encounter ID, source scene, exact player position, task checkpoint, retry count, optional grade/difficulty/topic scope, enemy type, and an overlay/scene return mode. `QuizManager` remains responsible only for three-versus-three question combat and emits one terminal result. It does not mutate quest retries or world state.

The lifecycle returns losses one and two to the saved context. The third full battle loss presents the existing Game Over presentation, restores only the saved task checkpoint, and clears the encounter retry state. A victory clears the retry count and notifies the caller that already owns quest advancement.

## Question flow

Every supported battle continues through `QuestionProvider` and the deployed backend. The encounter context supplies only explicit scope. When no explicit scope is configured, `QuestionProvider` derives canonical difficulty from the current location: Oakleaf/Easy, City/Medium, Pinehill/Hard. Topic stays unset rather than inferred. Local fallback and `question_set_id` propagation stay unchanged.

## Existing content rules

The only existing active task flow is preserved. The missing historical `battle_enemy.gd` copies are not reused. `male_vs_boss_bandit.tscn` is an unreferenced visual-only scene without the required question/health nodes, so it is deliberately not given an incompatible `QuizManager` attachment. `NPC/Teacher.tscn` is repaired to use the existing `teacher_task_interaction.gd` adapter; it does not create final-Teacher progression.

## Persistence and safety

Encounter context is additive to save data. Legacy saves deserialize with an empty encounter context and continue normally. A timeout does not count as a battle loss. Battle entry is refused when `GameState` says gameplay is time-blocked.

## Verification

Godot contract tests cover heart outcomes, one/two/three-loss state transitions, checkpoint return, victory reset, serialized context, question scope normalization, and Teacher reference validity. Runtime/manual verification remains necessary for the unreferenced visual-only boss scene and later story assets that are absent from this repository.
