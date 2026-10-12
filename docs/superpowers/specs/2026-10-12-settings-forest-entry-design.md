# Settings Runtime and Deepest Forest Entry Design

## Goal

Make the in-game Settings panel render as the authored composition at all target viewports and make the first legitimate City-to-Forest arrival safe and playable, without changing the approved City/backdrop architecture or story route.

## Current context

- Canonical project: `C:\Users\vince\Documents\Capstone-Project\capstone-theresians-quest`.
- Branch and starting commit: `codex/deep-forest-pinehill-continuation` at `c64a765a474fa7f7e36e77ddef48832b27ff66b0`.
- `settings_ingame.tscn` is the authored visual source. Runtime code currently has compact/reflow helpers that alter child controls and volume grabbers.
- City-to-Forest is intentionally the existing City map route; no new Forest map or art is in scope. The route continues from City to `deepest_forest_path.tscn`, then Pinehill remains behind its five-victory gate.
- The worktree contains many unrelated pre-existing dirty/untracked paths; only inspected, task-owned files may be staged.

## Design

### Settings composition

Keep the authored child positions, dimensions, texture proportions, slider/grabber artwork, button bounds, and click routing intact. Compute the authored panel's visual bounds, derive one uniform scale no larger than the available viewport bounds, and apply that scale and centered placement to the popup composition as a whole. Do not individually resize or reposition the sliders or grabbers. At the 1215×545 reference viewport, report actual runtime global rectangles and compare the scaled composition with the authored geometry. Also verify the 640×360, 844×390, 915×412, and 360×640 target sizes. Action buttons must remain mutually disjoint and slider interactions must not activate an action.

### Forest arrival and gate

Retain the real route Teacher/School → City → Deepest Forest. Do not add encounters to the City hub and do not alter the reused backdrop. Inspect canonical scene collision and transition geometry before selecting a new `spawn_from_city` coordinate. Change only that spawn value if a walkable, non-overlapping point can be established. Pinehill entry stays blocked until five victories; a blocked transition leaves the player, scene, quest, and encounter state unchanged. Return-from-Pinehill spawning remains unchanged. The five required encounters must be verified through the actual route and first legitimate Forest entry, not by directly starting the Forest scene or injecting quest flags.

## Failure and safety behavior

If collision geometry cannot prove a safe arrival, stop rather than guess. Keep Settings functional if the viewport cannot fit the authored composition by applying the largest uniform scale that stays within safe margins; never distort the artwork. Automated runtime tests must begin in the pre-autoload local QA profile and route transports to local stubs. Preserve `Data/api_config.json` and prove production requests/writes remain zero.

## Regression coverage

- Settings runtime visual capture and rectangles at the reference viewport and phone aspect ratios.
- Disjoint action/slider rectangles, action isolation, disabled Load bounds, and existing modal/input behavior.
- True School → City → Forest route, first-entry active/reachable bandits 1–5, Pinehill blocked before 5/5 without side effects, and unlocked after 5/5.
- Existing focused route and Settings regressions remain green.

## Scope boundary

Expected product files are `scenes/Settings-Ingame/settings_ingame_controller.gd`, `tools/settings_ingame_regression_test.gd`, `scripts/deepest_forest_path.gd` or its scene only if runtime evidence identifies the spawn there, and `tools/deepest_forest_pinehill_flow_test.gd`. Do not change story text, map art, encounter design, save behavior, mobile controls, production configuration, or unrelated dirty work.
