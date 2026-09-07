# Original Tutorial layout and controller lifecycle restoration

Canonical starting HEAD: `d6180f4028f5c9325ddd245c2cf620b564198791`.

The restored `interiors/player_house.tscn` matches the entire developer ZIP scene, initial commit `de77b5277161e8405c5026e3e8c38cac0e654656`, and starting HEAD (normalizing line endings). The only centering regression was an unstaged edit on `CanvasLayer/Panel`; no introducing commit exists in Git history.

| Panel property | Removed unstaged value | Restored ZIP value |
| --- | ---: | ---: |
| anchor_left | 0 | 0 |
| anchor_top | 0.3925 | 0.785 |
| anchor_right | 1 | 1 |
| anchor_bottom | 0.6075 | 1 |
| offset_left | 2 | 4 |
| offset_top | 0.0874939 | 0.1749878 |
| offset_right | -2 | 0 (implicit) |
| offset_bottom | -0.0874939 | 0 (implicit) |

`anchors_preset=-1`, both grow settings `2`, and horizontal size flags `3` remain original. At the existing logical 1215x545 viewport, position is `(4,428)` and size is `1211x117`. The original bottom margin is zero; no new margin or 680x210 layout was introduced. Shared world dialogue separately retains its existing 40px bottom margin.

`NPCImage`, `Image`, `TextLabel`, and `Button` serialized blocks are byte-identical to the ZIP. The Teacher image asset bytes also match. Portrait drawn size remains approximately 140x116; Next remains approximately 107.822x39.852 with its original signal to `NPCTeacher._on_button_pressed`. All original artwork, content, font, spacing and internal layout are preserved.

## Controller lifecycle

Only `scripts/mobile_controls.gd` changes relative to HEAD. In the canonical Player House, it observes the existing Tutorial panel's visibility and layout. A control group hides only when its margin rectangle physically overlaps the Teacher portrait or Next. The transparent margins are included because they also intercept input. Hidden buttons release their held input. A pending mobile ACT edge from immediately before opening is discarded without discarding held or just-pressed keyboard interaction. Closing the panel restores visibility through the existing exploration/dialogue/input-lock rules.

The resource `ui/mobile_controls.tscn` is byte-unchanged from this task's starting snapshot. It already contained separate, uncommitted position/size changes when this task began. Their approval is not established here; they are left untouched and excluded from the commit. With those current positions, only the D-pad obstructs the original panel, so ACT remains visible. A separate in-memory runtime fixture uses the committed controller geometry and verifies that both groups hide and both restore exactly. Another fixture isolates ACT-only obstruction. No fixture layout was saved into a product resource.

## Canonical runtime verification

Godot MCP ran `res://tools/tutorial_layout_lifecycle_test.tscn` from the canonical root. It freed live transports before opening gameplay and used isolated local fixture state. No production request or write, deployment, APK build, OpenAI call, or alternate project was used.

- **351 PASS, 0 FAIL** at client sizes 1215x545, 844x390 and 1280x800, using the existing logical viewport/stretch settings.
- Exact original Tutorial anchors, offsets, lower rectangle, portrait, instruction image, Next geometry and signal: PASS.
- Real viewport Next clicks, one press per line, final deliberate close, original Tutorial completion/HUD timing: PASS.
- Obstruction-specific hiding, held-input release, rapid released ACT, simultaneous keyboard hold/tap, visible D-pad preservation, delayed controller attachment and scene exit/reentry: PASS.
- All normal control geometry, style, visibility and enabled states restore after closing; all four directions work: PASS.
- Civilian, Teacher and Bandit world dialogue remains viewport-relative at its existing 40px bottom margin: PASS.
- SCRIPT ERROR = 0; resource/parse errors = 0; working and staged `git diff --check`: PASS.
- The existing ObjectDB exit warning remains; no unrelated cleanup was performed. Automated verification does not replace human visual acceptance.

## Scope and commit

Product files touched during this task:

1. `interiors/player_house.tscn`: removed only the unstaged centering hunk. It is now identical to HEAD and therefore has no new committed delta.
2. `scripts/mobile_controls.gd`: Tutorial-only obstruction/visibility lifecycle and pending mobile-edge handling.

Focused test files: `tools/tutorial_layout_lifecycle_test.gd` and `.tscn`.

Focused evidence files: this report, `2026-09-07-tutorial-lifecycle-preservation.json`, and `2026-09-07-tutorial-lifecycle-runtime.json`.

**Unrelated product delta count: 0.** All other 1,857 starting tracked paths retain their bytes, including maps, shared dialogue, Tutorial script/content, battle/VS, quests, HUD/timer, Teacher House, Task Trigger/Complete, Settings, loading, login, Save/Load, RemoteSync, QuestionProvider, and Grade/Difficulty. The pre-existing index is preserved outside these focused commit paths.

The commit is created with a temporary Git index so existing staged changes are not included. Its resulting SHA is recorded in the local post-commit evidence and final response.
