# Shared normal NPC dialogue visual refinement

Canonical starting HEAD: `dbb3c2abc42d8e11ca140acfb3d26ae5325d6cc2`.

Only the normal world dialogue layout initialization in `world/QuestUI.gd` changed. The existing container is 20px wider on each side and approximately 10% shorter, rounded to even pixels. Longer text uses Godot's existing minimum-size behavior and grows upward from the bottom margin. Content, font family/style/22px size, artwork, border, colors, corner radius, 18px horizontal/12px vertical padding, interaction bindings and continuation code are unchanged.

| Existing shared presentation | Before width x height | After width x height | Before L/T/R/B offsets | After L/T/R/B offsets |
| --- | --- | --- | --- | --- |
| Oakleaf civilian / shared world dialogue | 480x88 | 520x80 | -240 / -128 / 240 / -40 | -260 / -120 / 260 / -40 |
| Teacher House (same QuestUI host) | 420x140 | 460x126 | -210 / -180 / 210 / -40 | -230 / -166 / 230 / -40 |

Both retain runtime anchors L/T/R/B `0.5 / 1 / 0.5 / 1`, horizontal centering and **40px bottom margin** in the existing 1215x545 logical viewport. Width increases are 8.3% and 9.5%; normal height reductions are 9.1% and 10%. Long text can temporarily require more height, then returns to the normal size for short text. No scene file, map node or controller geometry was edited.

## Canonical Godot MCP verification

`tools/normal_dialogue_size_test.tscn` ran in the canonical project, using isolated local fixture state with live transports removed before gameplay. Client sizes: 1215x545, 844x390, 1280x800. The unchanged project stretch configuration supplies the logical viewport.

- **317 PASS, 0 FAIL**. SCRIPT ERROR = **0**; resource/parse errors = **0**. Working, staged and focused diff whitespace checks pass.
- All four Oakleaf speakers: real sensor entry, exact original greeting, one held opening press, deliberate final close, unchanged quest state, movement pause and normal controller restoration PASS.
- Teacher House: actual shared dialogue and original long Teacher line, one-press continuation and existing deliberate task completion PASS. Teacher scene/trigger source remains unchanged.
- World Bandit shared dialogue: new normal height, original bottom margin and control lifecycle PASS; no VS battle was entered or modified.
- Long runtime-only text: every wrapped line visible, original padding retained, no clipping or ACT overlap, upward expansion maintains the margin, and the next short line restores compact height PASS. No dialogue resource was edited.
- Tutorial: existing exact ZIP rectangle, portrait, Next, instruction, clicks, deliberate completion and controller lifecycle PASS. Entire `player_house.tscn` and `TutorialNPC.gd` remain byte/layout-equivalent to `dbb3c2a` (line endings normalized for HEAD comparison).
- City and Pinehill civilian dialogue: **N/A**. Their existing maps have no civilian dialogue bindings or shared dialogue container. Source inventory and canonical runtime confirm this. Their existing silent NPCs and map content remain unchanged; no dialogue was invented.

Screenshots inspected for desktop, phone-like and tablet views show the intended small proportional change. Automated verification does not establish final human acceptance. Existing warnings about resource UID fallbacks and ObjectDB exit cleanup remain outside this visual task; final runtime has no script/resource/parse errors.

## Preservation and focused commit

All other 1,862 starting tracked paths retain their bytes. Tutorial, maps/backgrounds, quest logic, battle/VS UI/effects/hearts, mobile controls, Teacher Task Trigger, Task Complete, HUD/timer/timeout notice, Settings, login, loading, Save/Load, RemoteSync, QuestionProvider, Grade/Difficulty and backend/web were not changed. **Unrelated product delta count: 0.**

`world/QuestUI.gd` already had separate uncommitted female battle-routing and post-quest host-preservation hunks. They remain untouched in the working file and are excluded from this commit. All pre-existing staged work is preserved using a temporary Git index.

Exact focused files:

- `world/QuestUI.gd`: only `_ready()` normal dialogue geometry.
- `tools/map_ui_presentation_test.gd`: update the existing normal dialogue height expectations; Tutorial expectations untouched.
- `tools/normal_dialogue_size_test.gd` and `.tscn`: focused canonical runtime harness.
- `docs/qa/2026-09-07-normal-dialogue-report.md`: this report.
- `docs/qa/2026-09-07-normal-dialogue-preservation.json`: before/after geometry and file preservation proof.
- `docs/qa/2026-09-07-normal-dialogue-runtime.json`: final check results.

No deployment, production write, APK build, OpenAI call or alternate-worktree implementation occurred. Resulting commit SHA is recorded in the local post-commit evidence and final response.
