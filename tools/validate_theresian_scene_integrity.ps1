$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

function Read-ProjectFile([string] $relativePath) {
    $path = Join-Path $root $relativePath
    if (-not (Test-Path $path)) {
        $failures.Add("${relativePath}: file is missing")
        return ""
    }
    return Get-Content -Path $path -Raw
}

function Require-Contains([string] $relativePath, [string] $needle, [string] $message) {
    $content = Read-ProjectFile $relativePath
    if (-not $content.Contains($needle)) {
        $failures.Add("${relativePath}: $message")
    }
}

function Require-NotContains([string] $relativePath, [string] $needle, [string] $message) {
    $content = Read-ProjectFile $relativePath
    if ($content.Contains($needle)) {
        $failures.Add("${relativePath}: $message")
    }
}

function Require-Regex([string] $relativePath, [string] $pattern, [string] $message) {
    $content = Read-ProjectFile $relativePath
    if ($content -notmatch $pattern) {
        $failures.Add("${relativePath}: $message")
    }
}

Require-Contains 'interiors\player_house.tscn' 'destination_scene_path = "res://scenes/oak_leaf_village.tscn"' 'Player House exit must load the real Oak Leaf Village scene.'
Require-Contains 'interiors\player_house.tscn' 'destination_spawn_marker_name = "PlayerHouseExitSpawn"' 'Player House exit must target its outside marker.'
Require-Contains 'interiors\teacher_house.tscn' 'destination_scene_path = "res://scenes/oak_leaf_village.tscn"' 'Teacher House exit must load the real Oak Leaf Village scene.'
Require-Contains 'interiors\teacher_house.tscn' 'destination_spawn_marker_name = "TeacherHouseExitSpawn"' 'Teacher House exit must target its outside marker.'
Require-Contains 'interiors\npc_house.tscn' 'destination_scene_path = "res://scenes/oak_leaf_village.tscn"' 'NPC House exit must load the real Oak Leaf Village scene.'
Require-Contains 'interiors\npc_house.tscn' 'destination_spawn_marker_name = "NpcHouseExitSpawn"' 'NPC House exit must target its outside marker.'

Require-Contains 'scenes\oak_leaf_village.tscn' '[node name="PlayerHouseExitSpawn" type="Marker2D"' 'Village needs the Player House outside spawn marker.'
Require-Contains 'scenes\oak_leaf_village.tscn' '[node name="TeacherHouseExitSpawn" type="Marker2D"' 'Village needs the Teacher House outside spawn marker.'
Require-Contains 'scenes\oak_leaf_village.tscn' '[node name="NpcHouseExitSpawn" type="Marker2D"' 'Village needs the NPC House outside spawn marker.'
Require-Contains 'scenes\oak_leaf_village.tscn' 'groups=["quest_ui"]' 'Village must preserve the tutorial quest UI panel.'
Require-Contains 'scenes\oak_leaf_village.tscn' 'path="res://world/task_progress_trigger.gd"' 'Village must preserve the canonical task progress trigger script.'
Require-Contains 'scenes\oak_leaf_village.tscn' 'path="res://world/QuestUI.gd"' 'Village must preserve the tutorial quest UI script.'
Require-NotContains 'scenes\oak_leaf_village.tscn' 'instance=ExtResource("24_h6312")' 'Village must not instantiate the Boss Bandit scene as the map substitute.'

Require-Contains 'scripts\game_state.gd' '"res://world/player_house_outside_door.tscn": "res://scenes/oak_leaf_village.tscn"' 'Legacy Player House outside map path must normalize to Oak Leaf Village.'
Require-Contains 'scripts\game_state.gd' '"res://world/teacher_house_outside_door.tscn": "res://scenes/oak_leaf_village.tscn"' 'Legacy Teacher House outside map path must normalize to Oak Leaf Village.'
Require-Contains 'scripts\game_state.gd' '"res://world/npc_house_outside_door.tscn": "res://scenes/oak_leaf_village.tscn"' 'Legacy NPC House outside map path must normalize to Oak Leaf Village.'

Require-Contains 'scripts\npc_collision_manager.gd' '"res://NPC/Enemy/"' 'Enemy humanoid NPC scenes must get generated foot collisions.'
Require-Contains 'scripts\npc_collision_manager.gd' '"res://NPC/Teacher.tscn"' 'Teacher scene must get generated foot collision.'
Require-Contains 'scripts\npc_collision_manager.gd' 'NPC_COLLISION_LAYER := 2' 'Generated NPC blockers must use a dedicated layer so Area2D triggers do not see them.'
Require-Contains 'player\player_male.tscn' 'collision_mask = 3' 'Male player must collide with world and NPC foot blockers.'
Require-Contains 'player\player_female.tscn' 'collision_mask = 3' 'Female player must collide with world and NPC foot blockers.'
Require-Contains 'scripts\top_down_player.gd' 'add_to_group("player")' 'All player variants must trigger existing tutorial Area2D task systems.'

Require-Contains 'scripts\door.gd' '@export_range(0.05, 3.0, 0.05) var fade_duration: float = 0.25' 'Door fade duration export range must allow 2-second scene transitions.'
Require-Contains 'scripts\door.gd' 'body.is_in_group("player") or body.is_in_group("player_character")' 'Door triggers must detect the player group while preserving existing player_character support.'
Require-Contains 'scripts\game_state.gd' '"res://scenes/2nd Village/Pinehill Village.tscn": Vector2' 'Pinehill needs a fallback spawn.'
Require-Contains 'scripts\game_state.gd' '"res://scenes/pinehill_village.tscn": "res://scenes/2nd Village/Pinehill Village.tscn"' 'Legacy Pinehill saves must normalize to the canonical map after wrapper retirement.'
Require-Contains 'Door-Navigations-Scene2Scene\city_of_knowledge_to_pine_hill.tscn' 'destination_scene_path = "res://scenes/2nd Village/Pinehill Village.tscn"' 'Unlocked City forest passage must load canonical Pinehill directly.'
Require-Contains 'Door-Navigations-Scene2Scene\city_of_knowledge_to_pine_hill.tscn' 'destination_spawn_marker_name = "spawn_from_deepest_forest"' 'City-to-Pinehill passage must target the established Pinehill arrival marker.'
Require-Contains 'Door-Navigations-Scene2Scene\city_of_knowledge_to_pine_hill.tscn' 'play_fade_transition = true' 'City-to-Pinehill passage must use its established fade transition.'
Require-Contains 'Door-Navigations-Scene2Scene\city_of_knowledge_to_pine_hill.tscn' 'fade_duration = 2.0' 'City-to-Pinehill passage must retain its 2-second fade.'
Require-Contains 'Door-Navigations-Scene2Scene\pinehill_to_city_of_knowledge.tscn' 'destination_scene_path = "res://scenes/city_of_knowledge.tscn"' 'Active Pinehill return loads the shared City/Forest map directly.'
Require-Contains 'Door-Navigations-Scene2Scene\pinehill_to_city_of_knowledge.tscn' 'destination_spawn_marker_name = "spawn_from_pinehill"' 'Active Pinehill return uses the forest-side City marker.'
if ((Test-Path (Join-Path $root 'scenes\deepest_forest_path.tscn')) -or
    (Test-Path (Join-Path $root 'scripts\deepest_forest_path.gd')) -or
    (Test-Path (Join-Path $root 'Door-Navigations-Scene2Scene\deepest_forest_to_pinehill.tscn')) -or
    (Test-Path (Join-Path $root 'Door-Navigations-Scene2Scene\deepest_forest_to_city.tscn')) -or
    (Test-Path (Join-Path $root 'Door-Navigations-Scene2Scene\pinehill_to_deepest_forest.tscn'))) {
    $failures.Add('Dedicated Deepest Forest wrapper resources must remain removed.')
}
Require-Contains 'scripts\game_state.gd' 'DEEPEST_FOREST_PATH: "res://scenes/city_of_knowledge.tscn"' 'Legacy Forest saves normalize to the canonical City scene.'
Require-Contains 'scripts\gameplay_scene.gd' '_sync_city_deep_forest_actors(active_scene_path)' 'City Forest actor visibility is progression-aware within the shared map.'
Require-Contains 'scripts\progression_battle_encounter.gd' 'CITY_PATH: {' 'Shared City/Forest map owns the active Forest encounter routes.'
Require-Contains 'scenes\city_of_knowledge.tscn' 'path="res://Door-Navigations-Scene2Scene/city_of_knowledge_to_pine_hill.tscn"' 'City scene must instance the correctly named City-to-Pinehill trigger.'
Require-Contains 'scenes\city_of_knowledge.tscn' '[node name="spawn_from_pinehill" type="Marker2D"' 'City scene must have a Pinehill return spawn marker.'
Require-Contains 'scenes\2nd Village\Pinehill Village.tscn' '[node name="spawn_from_deepest_forest" type="Marker2D"' 'Pinehill must retain the established arrival marker used by the City forest-side passage.'
Require-Contains 'scenes\city_of_knowledge.tscn' '[node name="spawn_from_deepest_forest" type="Marker2D"' 'City must retain its legacy wrapper compatibility marker.'
Require-Contains 'scenes\2nd Village\Pinehill Village.tscn' 'path="res://Door-Navigations-Scene2Scene/pinehill_to_city_of_knowledge.tscn"' 'Pinehill active scene instances the City-return door resource.'
Require-Contains 'scenes\2nd Village\Pinehill Village.tscn' '[node name="Pinehill-to-City-of-Knowledge"' 'Pinehill active route returns directly to the shared City/Forest map.'
Require-NotContains 'scenes\2nd Village\Pinehill Village.tscn' '[node name="Pinehill-to-Deepest-Forest"' 'Pinehill does not expose a separate Forest-wrapper return trigger.'

foreach ($legacyDoorScene in @('world\player_house_outside_door.tscn', 'world\teacher_house_outside_door.tscn', 'world\npc_house_outside_door.tscn')) {
    Require-Regex $legacyDoorScene '\[node name=.* type="Area2D"' 'Legacy outside door scene must be only an Area2D trigger, not a village map duplicate.'
    Require-NotContains $legacyDoorScene 'uid="uid://dr13hnfgvwx31"' 'Legacy outside door scene must not share the Oak Leaf Village UID.'
}

if ($failures.Count -gt 0) {
    Write-Host "Theresian scene integrity check failed:"
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    exit 1
}

Write-Host "Theresian scene integrity check passed."
