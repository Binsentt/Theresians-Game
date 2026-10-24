$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$city = Get-Content -Raw (Join-Path $projectRoot 'scenes/city_of_knowledge.tscn')
$cityToPinehill = Get-Content -Raw (Join-Path $projectRoot 'Door-Navigations-Scene2Scene/city_of_knowledge_to_pine_hill.tscn')
$pinehillReturn = Get-Content -Raw (Join-Path $projectRoot 'Door-Navigations-Scene2Scene/pinehill_to_city_of_knowledge.tscn')
$pinehill = Get-Content -Raw (Join-Path $projectRoot 'scenes/2nd Village/Pinehill Village.tscn')
$gameplay = Get-Content -Raw (Join-Path $projectRoot 'scripts/gameplay_scene.gd')
$encounters = Get-Content -Raw (Join-Path $projectRoot 'scripts/progression_battle_encounter.gd')
$door = Get-Content -Raw (Join-Path $projectRoot 'scripts/door.gd')
$state = Get-Content -Raw (Join-Path $projectRoot 'scripts/game_state.gd')

$checks = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$condition, [string]$message) {
    if (-not $condition) { throw "FAIL: $message" }
    $checks.Add($message)
}

function Get-SceneNodeBlock([string]$source, [string]$nodeName) {
    $escapedName = [regex]::Escape($nodeName)
    $pattern = '(?ms)^\[node name="' + $escapedName + '"[^\]]*\](.*?)(?=^\[node name=|\z)'
    $match = [regex]::Match($source, $pattern)
    return $match.Value
}

# City and Deepest Forest are one physical map. No separate Forest wrapper is
# part of the active design; old saves are normalized by GameState instead.
Assert-Contract ($cityToPinehill -match 'destination_scene_path = "res://scenes/2nd Village/Pinehill Village\.tscn"' -and $cityToPinehill -match 'destination_spawn_marker_name = "spawn_from_deepest_forest"') 'The City forest-side passage leads directly to Pinehill using its Forest arrival marker.'
Assert-Contract ($pinehill -match 'path="res://Door-Navigations-Scene2Scene/pinehill_to_city_of_knowledge\.tscn"' -and $pinehill -match '\[node name="Pinehill-to-City-of-Knowledge"') 'The active Pinehill return uses the City-named passage, not a Forest route wrapper.'
Assert-Contract ($pinehillReturn -match 'destination_scene_path = "res://scenes/city_of_knowledge\.tscn"' -and $pinehillReturn -match 'destination_spawn_marker_name = "spawn_from_pinehill"') 'Pinehill returns directly to the shared City/Forest map at spawn_from_pinehill.'
Assert-Contract ($city -notmatch 'deepest_forest_path\.tscn' -and $pinehill -notmatch 'pinehill_to_deepest_forest\.tscn') 'Active City/Pinehill scenes do not reference the separate Forest wrapper architecture.'
Assert-Contract (-not (Test-Path (Join-Path $projectRoot 'scenes/deepest_forest_path.tscn')) -and -not (Test-Path (Join-Path $projectRoot 'scripts/deepest_forest_path.gd'))) 'Dedicated Forest wrapper scene and script are removed.'

# The five Forest actors stay at their approved authored positions in the left
# side of the continuous City map. This route correction must not relocate them.
$banditPositions = @{
    'Bandits' = 'Vector2\(114, 487\)'
    'Bandits2' = 'Vector2\(171, 463\)'
    'Bandits3' = 'Vector2\(84, 425\)'
    'Bandits4' = 'Vector2\(265, 325\)'
    'Bandits5' = 'Vector2\(327, 237\)'
}
foreach ($actorName in $banditPositions.Keys) {
    $actorBlock = Get-SceneNodeBlock $city $actorName
    Assert-Contract ($actorBlock -match 'parent="\."' -and $actorBlock -match ('position = ' + $banditPositions[$actorName])) "$actorName remains authored directly in City at its pre-pass position."
}
Assert-Contract ($city -match '\[node name="spawn_from_pinehill"[^\]]*\]\s*position = Vector2\(128, 508\)') 'The established City forest-side Pinehill return marker remains at its authored location.'
Assert-Contract ($city -match '\[node name="City-of-knowlwedge-to-PineHill"[^\]]*\]\s*position = Vector2\(128, 534\)') 'The City-to-Pinehill trigger remains on the authored forest passage, away from the background collision cell.'

# The City scene activates the five actors only when the canonical progression
# gate says each encounter can start, before installing the encounter adapter.
Assert-Contract ($gameplay -match 'GameState\.handle_scene_entered\(active_scene_path\)[\s\S]*?_sync_city_deep_forest_actors\(active_scene_path\)[\s\S]*?PROGRESSION_BATTLE_ENCOUNTER\.install_for_scene') 'City task state is reconciled before bandit activation and adapter installation.'
Assert-Contract ($gameplay -match 'func _sync_city_deep_forest_actors\(active_scene_path: String\)[\s\S]*?can_start_progression_encounter[\s\S]*?actor\.visible = true[\s\S]*?collision_layer", FOREST_BANDIT_COLLISION_LAYER[\s\S]*?collision_mask", FOREST_BANDIT_COLLISION_MASK') 'Active Forest quest state makes undefeated City-authored Bandits visible and collidable.'
Assert-Contract ($gameplay -match 'if not can_start[\s\S]*?actor\.visible = false[\s\S]*?collision_layer", 0[\s\S]*?collision_mask", 0') 'Inactive or defeated Bandits stay hidden and non-collidable.'
Assert-Contract ($encounters -match 'CITY_PATH: \{[\s\S]*?"Bandits"[\s\S]*?"Bandits5"' -and $encounters -notmatch 'if scene_path == CITY_PATH:\s*# The City is only the authored backdrop[\s\S]*?return') 'The City scene owns the five Normal encounter adapters when their progression gate allows them.'
Assert-Contract ($encounters -match 'is_progression_encounter_defeated", encounter_id' -and $encounters -match 'can_start_progression_encounter", encounter_id' -and $encounters -match 'if not GameState\.has_method\("can_start_progression_encounter"\)[\s\S]*?continue') 'Encounter adapters are gated by the canonical active-task and undefeated state.'
Assert-Contract ($state -match 'current_scene_path == "res://scenes/city_of_knowledge\.tscn"[\s\S]*?city_school_stage_complete and current_task_index == CITY_NEXT_PATH_TASK_INDEX[\s\S]*?current_task_index = DEEP_FOREST_BANDIT_TASK_INDEX') 'The real School exit into City advances the active task before the player walks into the Forest area.'

# The single City passage remains blocked before all five wins and opens only
# when GameState records the full canonical Forest victory set.
Assert-Contract ($door -match 'destination_lower\.contains\("pinehill"\)[\s\S]*?not GameState\.is_pinehill_unlocked\(\)[\s\S]*?return[\s\S]*?change_scene_to_file') 'A locked Pinehill passage returns without changing scenes or moving the player.'
Assert-Contract ($state -match 'group == "deep_forest" and are_all_progression_bandits_defeated\(group\)[\s\S]*?pinehill_unlocked = true') 'Exactly the complete five-bandit Forest group unlocks Pinehill.'

# Game Over for the active Forest quest still returns to the quest-start School
# checkpoint; removing the wrapper must not change that story checkpoint.
Assert-Contract ($state -match 'if task_index == DEEP_FOREST_BANDIT_TASK_INDEX:[\s\S]{0,220}"scene_path": "res://interiors/school\.tscn", "marker_name": "PlayerSpawn"') 'Deepest Forest Game Over fallback remains the School quest-start checkpoint.'
Assert-Contract ($state -match 'if task_index == FINAL_SCHOOL_TASK_INDEX:[\s\S]{0,220}"scene_path": "res://scenes/city_of_knowledge\.tscn", "marker_name": "spawn_from_pinehill"') 'Final School fallback returns to the City forest side without a wrapper marker.'
Assert-Contract ($state -match '"res://scenes/city_of_knowledge\.tscn":\s*return "spawn_from_pinehill"') 'City scene fallback respawn no longer requires spawn_from_deepest_forest.'
Assert-Contract ($pinehill -match '\[node name="spawn_from_deepest_forest"[^\]]*\]') 'The established Pinehill arrival marker remains available to the direct City-to-Pinehill passage.'
Assert-Contract (-not (Test-Path (Join-Path $projectRoot 'Door-Navigations-Scene2Scene/deepest_forest_to_pinehill.tscn')) -and -not (Test-Path (Join-Path $projectRoot 'Door-Navigations-Scene2Scene/deepest_forest_to_city.tscn'))) 'Dedicated Forest transition scenes are removed.'
Assert-Contract (-not (Test-Path (Join-Path $projectRoot 'Door-Navigations-Scene2Scene/pinehill_to_deepest_forest.tscn'))) 'The obsolete Pinehill-to-Forest alias door is removed.'
Assert-Contract ($state -match 'DEEPEST_FOREST_PATH:\s*"res://scenes/city_of_knowledge\.tscn"') 'Legacy Forest saves normalize to City before any scene is loaded.'

Write-Output ("CITY_FOREST_CONTINUOUS_MAP_CONTRACT_TEST {0}/{0} passed" -f $checks.Count)
