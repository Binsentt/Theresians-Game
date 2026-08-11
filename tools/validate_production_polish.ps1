$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

function Add-Error([string]$message) { $script:errors.Add($message) }
function Read-ProjectFile([string]$relativePath) {
    $path = Join-Path $repo $relativePath
    if (-not (Test-Path -LiteralPath $path)) { Add-Error "Missing required file: $relativePath"; return '' }
    Get-Content -LiteralPath $path -Raw
}
function Require-Match([string]$content, [string]$pattern, [string]$message) {
    if ($content -notmatch $pattern) { Add-Error $message }
}

$heartReferences = & rg -l --glob '*.tscn' --glob '*.gd' --glob '*.godot' --glob '*.cfg' --glob '!docs/**' --glob '!.godot/**' --glob '!tools/**' 'res://assets/hearts\.png' $repo 2>$null
foreach ($referenceFile in $heartReferences) { Add-Error "Active runtime reference still uses res://assets/hearts.png: $referenceFile" }

Require-Match (Read-ProjectFile 'player/life.tscn') 'res://assets/hearth\.png' 'player/life must use res://assets/hearth.png.'

$project = Read-ProjectFile 'project.godot'
Require-Match $project 'run/main_scene\s*=\s*"res://scenes/loading_screen\.tscn"' 'project.godot must set run/main_scene to res://scenes/loading_screen.tscn.'
Require-Match $project 'config/icon\s*=\s*"res://Images/Application-Logo\.png"' 'project.godot must set config/icon to res://Images/Application-Logo.png.'
Require-Match $project 'boot_splash/image\s*=\s*"res://Images/Loading Backgroud\.png"' 'project.godot must set boot_splash/image to res://Images/Loading Backgroud.png.'

$exports = Read-ProjectFile 'export_presets.cfg'
$androidPreset = [regex]::Match($exports, '(?ms)^\[preset\.(\d+)\]\r?\n(?:(?!^\[preset\.).)*?^platform\s*=\s*"Android"')
if (-not $androidPreset.Success) {
    Add-Error 'export_presets.cfg must contain an Android preset.'
} else {
    $androidIndex = [regex]::Escape($androidPreset.Groups[1].Value)
    Require-Match $exports ('(?ms)^\[preset\.' + $androidIndex + '\.options\]\r?\n(?:(?!^\[preset\.).)*?^launcher_icons/main_192x192\s*=\s*"res://Images/Application-Logo\.png"') 'The Android preset launcher_icons/main_192x192 must point to res://Images/Application-Logo.png.'
}

$loadingScene = Read-ProjectFile 'scenes/loading_screen.tscn'
$backgroundResource = [regex]::Match($loadingScene, '(?m)^\[ext_resource (?=[^\]]*type="Texture2D")(?=[^\]]*path="res://Images/Loading Backgroud\.png")(?=[^\]]*id="([^"]+)")[^\]]*\]')
if (-not $backgroundResource.Success) {
    Add-Error 'Loading scene must declare Loading Backgroud.png as an exact Texture2D ext_resource.'
} else {
    $backgroundId = [regex]::Escape($backgroundResource.Groups[1].Value)
    $backgroundNodes = [regex]::Matches($loadingScene, '(?ms)^\[node name="Background" type="TextureRect"[^\]]*\]\r?\n(?:(?!^\[node ).)*?^texture\s*=\s*ExtResource\("' + $backgroundId + '"\)')
    if ($backgroundNodes.Count -ne 1) { Add-Error 'Loading scene must contain exactly one Background TextureRect using Loading Backgroud.png.' }
}
if ([regex]::Matches($loadingScene, '(?m)^\[node [^\]]*type="ProgressBar"[^\]]*\]').Count -ne 1) { Add-Error 'Loading scene must contain exactly one ProgressBar node.' }
Require-Match $loadingScene '(?ms)^\[node [^\]]*type="ProgressBar"[^\]]*\]\r?\n(?:(?!^\[node ).)*?^show_percentage\s*=\s*false' 'Loading ProgressBar must set show_percentage=false in its own node block.'
Require-Match $loadingScene '(?m)^\[node name="DotsTimer" type="Timer"[^\]]*\]' 'Loading scene must contain an exact DotsTimer Timer node.'
Require-Match $loadingScene '(?m)^\[node name="ProgressTimer" type="Timer"[^\]]*\]' 'Loading scene must contain an exact ProgressTimer Timer node.'
Require-Match $loadingScene '(?ms)^\[node name="ErrorPanel"[^\]]*\]\r?\n(?:(?!^\[node ).)*?^visible\s*=\s*false' 'Loading ErrorPanel must set visible=false in its own node block.'

$loadingScript = Read-ProjectFile 'scripts/loading_screen.gd'
Require-Match $loadingScript 'enum\s+\w*\s*\{[^}]*\bSTARTUP\b[^}]*\bNEW_GAME\b[^}]*\bLOAD_GAME\b[^}]*\bCONNECTION_RETRY\b[^}]*\}' 'Loading controller must declare STARTUP, NEW_GAME, LOAD_GAME, and CONNECTION_RETRY in one enum/mode declaration.'
foreach ($functionName in 'prepare_new_game', 'prepare_load_game') {
    Require-Match $loadingScript ('(?m)^\s*static\s+func\s+' + $functionName + '\s*\(') "Loading controller must define static func $functionName."
}
$connectionPreparation = [regex]::Match($loadingScript, '(?ms)^\s*static\s+func\s+prepare_connection_retry\s*\((?<params>[^)]*)\)')
if (-not $connectionPreparation.Success -or $connectionPreparation.Groups['params'].Value -notmatch '\bmessage\s*:\s*String\b' -or $connectionPreparation.Groups['params'].Value -match '\bCallable\b|\bretry_callback\b|,') {
    Add-Error 'Loading controller prepare_connection_retry must accept message only and must not carry a Callable across scenes.'
}
if ($loadingScript -match '(?m)^\s*static\s+var\s+_pending_retry_callback\b') {
    Add-Error 'Loading controller must not store a pending retry Callable across a scene change.'
}
Require-Match $loadingScript '(?m)^\s*func\s+show_connection_error\s*\(' 'Loading controller must define instance func show_connection_error.'
$retryHandler = [regex]::Match($loadingScript, '(?ms)^func\s+_on_retry_button_pressed\s*\([^)]*\)\s*(?:->\s*[^:\r\n]+)?\s*:\s*\r?\n(?<body>(?:(?!^func\s).)*)')
if (-not $retryHandler.Success) {
    Add-Error 'Loading controller must define _on_retry_button_pressed().'
} else {
    if ($retryHandler.Groups['body'].Value -match '(?m)^\s*_retry_callback\s*=\s*Callable\s*\(') { Add-Error 'Retry must retain its active-screen callback for later attempts.' }
    Require-Match $retryHandler.Groups['body'].Value '(?m)^\s*call_deferred\s*\(' 'Retry must defer re-arming after the callback returns.'
}
Require-Match $loadingScript '(?ms)^func\s+_rearm_retry_button\s*\([^)]*\)\s*(?:->\s*[^:\r\n]+)?\s*:\s*\r?\n(?:(?!^func\s).)*?^\s*_retry_in_progress\s*=\s*false\s*$[\s\S]*?^\s*retry_button\.disabled\s*=\s*not\s+_retry_callback\.is_valid\s*\(\)' 'Loading controller must re-arm Retry only while its active-screen callback remains valid.'
$returnHandler = [regex]::Match($loadingScript, '(?ms)^func\s+_on_return_button_pressed\s*\([^)]*\)\s*(?:->\s*[^:\r\n]+)?\s*:\s*\r?\n(?<body>(?:(?!^func\s).)*)')
if (-not $returnHandler.Success) {
    Add-Error 'Loading controller must define _on_return_button_pressed().'
} else {
    Require-Match $returnHandler.Groups['body'].Value '(?ms)^\s*if\s+result\s*!=\s*OK\s*:\s*\r?\n(?:(?!^\S).)*?^\s*_rearm_retry_button\s*\(\)' 'A failed Return Main Menu transition must restore a valid Retry action.'
}

Require-Match (Read-ProjectFile 'scenes/texture_rect_2.gd') '(?m)^\s*LoadingScreenController\.prepare_new_game\s*\(' 'scenes/texture_rect_2.gd must call LoadingScreenController.prepare_new_game().'
$loadGameScript = Read-ProjectFile 'scripts/load_game_scene.gd'
Require-Match $loadGameScript '(?m)^\s*LoadingScreenController\.prepare_load_game\s*\(' 'scripts/load_game_scene.gd must call LoadingScreenController.prepare_load_game().'
Require-Match $loadGameScript '(?m)^\s*get_tree\(\)\.change_scene_to_file\s*\(\s*LOADING_SCENE_PATH\s*\)' 'scripts/load_game_scene.gd must call get_tree().change_scene_to_file(LOADING_SCENE_PATH).'

$gameOverScene = Read-ProjectFile 'scenes/game_over_scene.tscn'
$soundHeaders = [regex]::Matches($gameOverScene, '(?m)^\[node name="GameOverSound" type="AudioStreamPlayer"[^\]]*\]')
if ($soundHeaders.Count -ne 1) { Add-Error 'Game Over scene must contain exactly one GameOverSound AudioStreamPlayer.' }
$mp3Resource = [regex]::Match($gameOverScene, '(?m)^\[ext_resource (?=[^\]]*type="AudioStream")(?=[^\]]*path="res://bg-musics/game over sound effects\.mp3")(?=[^\]]*id="([^"]+)")[^\]]*\]')
if (-not $mp3Resource.Success) {
    Add-Error 'Game Over scene must declare res://bg-musics/game over sound effects.mp3 as an AudioStream ext_resource.'
} else {
    $mp3Id = [regex]::Escape($mp3Resource.Groups[1].Value)
    $soundBlocks = [regex]::Matches($gameOverScene, '(?ms)^\[node name="GameOverSound" type="AudioStreamPlayer"[^\]]*\]\r?\n(?:(?!^\[node ).)*?^stream\s*=\s*ExtResource\("' + $mp3Id + '"\)(?:(?!^\[node ).)*?^bus\s*=\s*&?"SFX"')
    if ($soundHeaders.Count -eq 1 -and $soundBlocks.Count -ne 1) { Add-Error 'The sole GameOverSound AudioStreamPlayer must bind the provided MP3 on bus SFX.' }
    $soundNodeBlock = [regex]::Match($gameOverScene, '(?ms)^\[node name="GameOverSound" type="AudioStreamPlayer"[^\]]*\]\r?\n(?:(?!^\[node ).)*')
    if ($soundNodeBlock.Success -and $soundNodeBlock.Value -match '(?m)^autoplay\s*=\s*true') { Add-Error 'GameOverSound must not enable autoplay.' }
}
$gameOverImport = Read-ProjectFile 'bg-musics/game over sound effects.mp3.import'
Require-Match $gameOverImport '(?m)^loop\s*=\s*false' 'Game Over MP3 import must set loop=false.'

$gameOverScript = Read-ProjectFile 'scripts/game_over_scene.gd'
$guard = [regex]::Match($gameOverScript, '(?m)^\s*var\s+_game_over_sound_played\s*:\s*bool\s*=\s*false\s*$')
if (-not $guard.Success) { Add-Error 'Game Over script must define _game_over_sound_played: bool = false.' }
$playOnce = [regex]::Match($gameOverScript, '(?ms)^func\s+_play_game_over_sound_once\s*\([^)]*\)\s*(?:->\s*[^:\r\n]+)?\s*:\s*\r?\n(?<body>(?:(?!^func\s).)*)')
if (-not $playOnce.Success) {
    Add-Error 'Game Over script must define _play_game_over_sound_once().'
} else {
    Require-Match $playOnce.Groups['body'].Value '(?ms)^\s*if\s+_game_over_sound_played\s*:\s*\r?\n\s*return[\s\S]*?^\s*_game_over_sound_played\s*=\s*true\s*$[\s\S]*?^\s*game_over_sound\.play\s*\(' 'Game Over script must guard, return, set, then play within _play_game_over_sound_once().'
}
$ready = [regex]::Match($gameOverScript, '(?ms)^func\s+_ready\s*\([^)]*\)\s*(?:->\s*[^:\r\n]+)?\s*:\s*\r?\n(?<body>(?:(?!^func\s).)*)')
if (-not $ready.Success -or $ready.Groups['body'].Value -notmatch '(?m)^\s*_play_game_over_sound_once\s*\(') { Add-Error 'Game Over _ready must invoke _play_game_over_sound_once().' }
if (-not $ready.Success -or $ready.Groups['body'].Value -notmatch '(?m)^\s*MusicManager\.stop_music\s*\(') { Add-Error 'Game Over _ready must call MusicManager.stop_music().' }

if ($errors.Count -eq 0) { Write-Output 'PRODUCTION_POLISH_STATIC_TEST PASSED'; exit 0 }
foreach ($failureMessage in $errors) { Write-Output $failureMessage }
Write-Output 'PRODUCTION_POLISH_STATIC_TEST FAILED'
exit 1
