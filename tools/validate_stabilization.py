from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent.parent

ACTIVE_SCENES = [
    "scenes/main_menu.tscn",
    "scenes/new_game_scene.tscn",
    "scenes/loading_screen.tscn",
    "scenes/oak_leaf_village.tscn",
    "world/player_house_outside_door.tscn",
    "world/npc_house_outside_door.tscn",
    "world/teacher_house_outside_door.tscn",
    "scenes/city_of_knowledge.tscn",
    "scenes/2nd Village/Pinehill Village.tscn",
    "interiors/player_house.tscn",
    "interiors/npc_house.tscn",
    "interiors/teacher_house.tscn",
    "interiors/school.tscn",
    "interiors/hotel.tscn",
]

ACTIVE_SCRIPTS = [
    "scripts/door.gd",
    "scripts/gameplay_scene.gd",
    "scripts/game_state.gd",
    "scripts/load_game_btn.gd",
    "scripts/music_manager.gd",
    "scripts/npc_collision_manager.gd",
    "scripts/scene_hud_host.gd",
    "scripts/game_hud.gd",
    "scenes/Settings-Ingame/settings_ingame_controller.gd",
]

FORBIDDEN_RUNTIME_TOKENS = [
    "res://NPC/Enemy/",
    "res://scripts/battle_enemy.gd",
    "battle_name = ",
    "begin_overworld_battle",
]

FORBIDDEN_ACTIVE_SCRIPT_TOKENS = [
    "res://NPC/Enemy/",
    "res://scripts/battle_enemy.gd",
]

LEGACY_FILES_THAT_MUST_BE_REMOVED = [
    "scenes/load_game_scene.tscn",
    "scripts/load_game_scene.gd",
    "ui/save_entry.tscn",
    "scripts/save_entry.gd",
    "interiors/players_house.tscn",
    "interiors/npc_house_1.tscn",
    "interiors/hotel_interior.tscn",
    "interiors/school-inside.tscn",
    "scripts/battle_enemy.gd",
]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def main() -> int:
    failures: list[str] = []

    for relative_path in ACTIVE_SCENES + ACTIVE_SCRIPTS:
        full_path = ROOT / relative_path
        if not full_path.exists():
            failures.append(f"Missing required active file: {relative_path}")

    for relative_path in ACTIVE_SCENES:
        scene_text = read_text(relative_path)
        for token in FORBIDDEN_RUNTIME_TOKENS:
            if token in scene_text:
                failures.append(f"Forbidden token {token!r} found in active scene {relative_path}")

    for relative_path in ACTIVE_SCRIPTS:
        script_text = read_text(relative_path)
        for token in FORBIDDEN_ACTIVE_SCRIPT_TOKENS:
            if token in script_text:
                failures.append(f"Forbidden token {token!r} found in active script {relative_path}")

    for relative_path in LEGACY_FILES_THAT_MUST_BE_REMOVED:
        if (ROOT / relative_path).exists():
            failures.append(f"Legacy file still present: {relative_path}")

    tmp_matches = sorted(ROOT.glob("scenes/oak_leaf_village.tscn*.tmp"))
    for path in tmp_matches:
        failures.append(f"Temporary scene file still present: {path.relative_to(ROOT).as_posix()}")

    if failures:
        print("Stabilization validation failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Stabilization validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
