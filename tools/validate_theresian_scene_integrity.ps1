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
Require-Contains 'scenes\oak_leaf_village.tscn' 'path="res://world/Task1.gd"' 'Village must preserve the tutorial task trigger script.'
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
Require-Contains 'scripts\game_state.gd' '"res://scenes/2nd Village/Pinehill Village.tscn": "res://scenes/pinehill_village.tscn"' 'Legacy Pinehill scene path must normalize to the clean Pinehill scene path.'
Require-Contains 'scripts\game_state.gd' '"res://scenes/pinehill_village.tscn": Vector2' 'Pinehill needs a fallback spawn.'
Require-Contains 'scenes\pinehill_village.tscn' 'path="res://scenes/2nd Village/Pinehill Village.tscn"' 'Clean Pinehill scene path must load the existing Pinehill map.'
Require-Contains 'Door-Navigations-Scene2Scene\city_of_knowledge_to_pine_hill.tscn' 'destination_scene_path = "res://scenes/pinehill_village.tscn"' 'City-to-Pinehill Area2D must load the clean Pinehill scene.'
Require-Contains 'Door-Navigations-Scene2Scene\city_of_knowledge_to_pine_hill.tscn' 'destination_spawn_marker_name = "spawn_from_city"' 'City-to-Pinehill Area2D must target the Pinehill entrance marker.'
Require-Contains 'Door-Navigations-Scene2Scene\city_of_knowledge_to_pine_hill.tscn' 'play_fade_transition = true' 'City-to-Pinehill Area2D must use fade transition.'
Require-Contains 'Door-Navigations-Scene2Scene\city_of_knowledge_to_pine_hill.tscn' 'fade_duration = 2.0' 'City-to-Pinehill Area2D must use a 2-second fade.'
Require-Contains 'Door-Navigations-Scene2Scene\pinehill_to_city_of_knowledge.tscn' 'destination_scene_path = "res://scenes/city_of_knowledge.tscn"' 'Pinehill-to-City Area2D must load City of Knowledge.'
Require-Contains 'Door-Navigations-Scene2Scene\pinehill_to_city_of_knowledge.tscn' 'destination_spawn_marker_name = "spawn_from_pinehill"' 'Pinehill-to-City Area2D must target the City entrance marker.'
Require-Contains 'Door-Navigations-Scene2Scene\pinehill_to_city_of_knowledge.tscn' 'play_fade_transition = true' 'Pinehill-to-City Area2D must use fade transition.'
Require-Contains 'Door-Navigations-Scene2Scene\pinehill_to_city_of_knowledge.tscn' 'fade_duration = 2.0' 'Pinehill-to-City Area2D must use a 2-second fade.'
Require-Contains 'scenes\city_of_knowledge.tscn' 'path="res://Door-Navigations-Scene2Scene/city_of_knowledge_to_pine_hill.tscn"' 'City scene must instance the correctly named City-to-Pinehill trigger.'
Require-Contains 'scenes\city_of_knowledge.tscn' '[node name="spawn_from_pinehill" type="Marker2D"' 'City scene must have a Pinehill return spawn marker.'
Require-Contains 'scenes\2nd Village\Pinehill Village.tscn' '[node name="spawn_from_city" type="Marker2D"' 'Pinehill scene must have a City entrance spawn marker.'

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
