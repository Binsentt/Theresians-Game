$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

$passed = 0
$failed = 0

function Assert-Contains([string]$Path, [string]$Pattern, [string]$Description) {
	$content = Get-Content -LiteralPath $Path -Raw
	if ($content -match $Pattern) {
		$script:passed++
		Write-Output "PASS $Description"
	} else {
		$script:failed++
		Write-Output "FAIL $Description"
	}
}

function Assert-NotContains([string]$Path, [string]$Pattern, [string]$Description) {
	$content = Get-Content -LiteralPath $Path -Raw
	if ($content -notmatch $Pattern) {
		$script:passed++
		Write-Output "PASS $Description"
	} else {
		$script:failed++
		Write-Output "FAIL $Description"
	}
}

function Assert-Count([string]$Path, [string]$Pattern, [int]$Expected, [string]$Description) {
	$content = Get-Content -LiteralPath $Path -Raw
	$count = [regex]::Matches($content, $Pattern).Count
	if ($count -eq $Expected) {
		$script:passed++
		Write-Output "PASS $Description"
	} else {
		$script:failed++
		Write-Output "FAIL $Description (expected=$Expected actual=$count)"
	}
}

function Assert-FileMissing([string]$RelativePath, [string]$Description) {
	if (-not (Test-Path -LiteralPath $RelativePath)) {
		$script:passed++
		Write-Output "PASS $Description"
	} else {
		$script:failed++
		Write-Output "FAIL $Description"
	}
}

$gameState = 'scripts/game_state.gd'
$progression = 'scripts/progression_battle_encounter.gd'
$oldLady = 'scripts/progression_old_man_interaction.gd'
$gameplay = 'scripts/gameplay_scene.gd'
$door = 'scripts/door.gd'
$pinehill = 'scenes/2nd Village/Pinehill Village.tscn'
$city = 'scenes/city_of_knowledge.tscn'
$school = 'interiors/school.tscn'
$teacherInteraction = 'scripts/teacher_task_interaction.gd'
$questUi = 'world/QuestUI.gd'
$ending = 'ui/journey_completion_screen.gd'
$cityToForest = 'Door-Navigations-Scene2Scene/city_of_knowledge_to_pine_hill.tscn'
$pinehillToCity = 'Door-Navigations-Scene2Scene/pinehill_to_city_of_knowledge.tscn'

Assert-Contains $gameState 'const PINEHILL_OLD_MAN_TASK_INDEX := 12' 'Pinehill Old Lady task retains canonical index'
Assert-Contains $gameState 'const PINEHILL_BANDIT_TASK_INDEX := 13' 'Four Guards task follows the Old Lady'
Assert-Contains $gameState 'const WIZARD_TASK_INDEX := 14' 'Wizard task follows the four Guards'
Assert-Contains $gameState 'const RETURN_CITY_TASK_INDEX := 15' 'Wizard completion advances to the return objective'
Assert-Contains $gameState 'const FINAL_SCHOOL_TASK_INDEX := 16' 'Return objective advances to School'
Assert-Contains $gameState 'const FINAL_TEACHER_TASK_INDEX := 17' 'Final Teacher follows School return'
Assert-Contains $oldLady 'current_task_index != GameState\.PINEHILL_OLD_MAN_TASK_INDEX' 'Old Lady interaction is gated to its task stage'
Assert-Contains $gameState 'current_task_index == PINEHILL_BANDIT_TASK_INDEX and pinehill_old_man_completed' 'Guard encounters require Old Lady completion'
Assert-Contains $gameState 'and are_all_progression_bandits_defeated\("pinehill"\)' 'Wizard requires all four Guard victories'
Assert-Contains $progression '"Boss-Wizard": \{"encounter_id": "pinehill_wizard"' 'Outdoor Wizard actor owns the single Wizard encounter route'
Assert-Contains $progression 'CITY_PATH: \{[\s\S]*?"Bandits"[\s\S]*?"Bandits5"' 'The shared City/Forest scene owns all five gated Forest encounter routes'
Assert-NotContains $progression 'if scene_path == CITY_PATH:\s*# The City is only the authored backdrop[\s\S]*?return' 'Active City/Forest scene is not skipped by encounter adapter installation'
Assert-Contains $progression '"Bandits": \{"encounter_id": "pinehill_bandits1", "difficulty": "Difficult"' 'First Pinehill Guard uses the Difficult battle route'
Assert-Contains $progression '"Bandits2": \{"encounter_id": "pinehill_bandits2", "difficulty": "Difficult"' 'Second Pinehill Guard uses the Difficult battle route'
Assert-Contains $progression '"Bandits3": \{"encounter_id": "pinehill_bandits3", "difficulty": "Difficult"' 'Third Pinehill Guard uses the Difficult battle route'
Assert-Contains $progression '"Bandits4": \{"encounter_id": "pinehill_bandits4", "difficulty": "Difficult"' 'Fourth Pinehill Guard uses the Difficult battle route'
Assert-Contains $pinehill '\[node name="old_adult_women" parent="\."' 'Pinehill keeps the authored Old Lady actor outdoors'
Assert-Contains $pinehill '\[node name="Boss-Wizard" parent="\."' 'Wizard is a scene-level outdoor actor'
Assert-NotContains $pinehill '\[node name="Boss-Wizard" parent="display-kase yung wizard sa labas lang"' 'Wizard is not nested under the house artwork'
Assert-NotContains 'MetroCity .2/MetroCity 2.1/wizard-house.tscn' 'ProgressionBattleEncounter|InteractableArea|script =' 'Wizard House artwork has no interaction or battle trigger'
Assert-Contains $pinehill 'path="res://Door-Navigations-Scene2Scene/pinehill_to_city_of_knowledge\.tscn"' 'Active Pinehill scene uses the City-return door resource'
Assert-Contains $pinehill '\[node name="Pinehill-to-City-of-Knowledge" parent="\."' 'Pinehill returns directly to the continuous City/Forest map'
Assert-NotContains $pinehill '\[node name="Pinehill-to-Deepest-Forest" parent="\."' 'The misleading Forest-wrapper return is not active in Pinehill'
Assert-Contains $pinehill '\[node name="spawn_from_deepest_forest" type="Marker2D"' 'Pinehill has a Forest-arrival spawn marker'
Assert-Contains $pinehill '\[node name="Bandits4" parent="\."' 'Pinehill contains the fourth required Guard actor'
Assert-Count $pinehill '\[node name="Boss-Wizard"' 1 'Canonical Pinehill scene contains exactly one Wizard actor'
Assert-Contains $gameState 'return_to_city_stage = 2' 'Wizard victory unlocks the City return stage'
Assert-FileMissing 'scenes/deepest_forest_path.tscn' 'Dedicated Deepest Forest scene has been removed'
Assert-FileMissing 'scripts/deepest_forest_path.gd' 'Dedicated Deepest Forest wrapper script has been removed'
Assert-FileMissing 'Door-Navigations-Scene2Scene/deepest_forest_to_pinehill.tscn' 'Dedicated Forest-to-Pinehill door has been removed'
Assert-FileMissing 'Door-Navigations-Scene2Scene/deepest_forest_to_city.tscn' 'Dedicated Forest-to-City door has been removed'
Assert-Contains $gameState 'DEEPEST_FOREST_PATH: "res://scenes/city_of_knowledge.tscn"' 'Legacy Forest saves normalize to the canonical City scene'
Assert-Contains $cityToForest 'destination_scene_path = "res://scenes/2nd Village/Pinehill Village.tscn"' 'Unlocked City forest-side passage enters canonical Pinehill directly'
Assert-Contains $cityToForest 'destination_spawn_marker_name = "spawn_from_deepest_forest"' 'City-to-Pinehill uses the established Pinehill arrival marker'
Assert-Contains $pinehillToCity 'destination_scene_path = "res://scenes/city_of_knowledge.tscn"' 'Active Pinehill return loads the shared City/Forest scene directly'
Assert-Contains $pinehillToCity 'destination_spawn_marker_name = "spawn_from_pinehill"' 'Active Pinehill return uses the forest-side City marker'
Assert-Contains $city '\[node name="SchoolDoor" type="Area2D"' 'City provides the return School entrance'
Assert-Contains $gameState 'current_task_index = FINAL_SCHOOL_TASK_INDEX' 'Returning to City activates the School objective'
Assert-Contains $gameState 'current_task_index == FINAL_SCHOOL_TASK_INDEX and return_to_city_stage >= 2' 'Final School entry is gated on Wizard completion'
Assert-Contains $school '\[node name="Teacher"' 'School contains the canonical Teacher actor'
Assert-Contains $teacherInteraction 'is_final_teacher_active' 'Teacher interaction is enabled by final-stage state'
Assert-Contains $gameState 'journey_complete = true' 'Final Teacher victory marks campaign completion'
Assert-Contains $questUi 'Teacher: Congratulations, Math Champion\. Keep practicing and keep learning\.' 'Required final Teacher dialogue remains exact'
Assert-Contains $questUi 'JOURNEY_COMPLETION_SCENE' 'Final Teacher victory launches the existing ending screen'
Assert-Contains $ending 'main_menu_button\.pressed\.connect\(_select_action\.bind\("main_menu"\)\)' 'Ending provides a Main Menu action'
Assert-Contains $gameplay '_sync_city_deep_forest_actors\(active_scene_path\)' 'Forest encounter visibility follows progression state in the shared City/Forest scene'

Write-Output "PINEHILL_ENDING_STATIC_CONTRACT passed=$passed failed=$failed"
if ($failed -gt 0) {
	exit 1
}
