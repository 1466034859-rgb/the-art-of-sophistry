# Dev helper for "The Art of Sophistry" (Godot 4.7 project)
# Tested with Windows PowerShell 5.1 and pwsh 7.
#
# Usage from the project root:
#   powershell -File tools\dev.ps1 import    # re-import project (refresh global class cache)
#   powershell -File tools\dev.ps1 test      # logic test suite (60 cards, 128 AI matches)
#   powershell -File tools\dev.ps1 ui        # UI smoke test (script drives a whole battle)
#   powershell -File tools\dev.ps1 boot      # boot main scene for 120 frames
#   powershell -File tools\dev.ps1 capture   # write screenshots/*.png (needs a real renderer)
#   powershell -File tools\dev.ps1 all       # import + test + ui + boot
#
# If a ".appdata" folder exists next to the project, the script points APPDATA at it
# (used by the headless sandbox to redirect Godot's user:// directory). On a normal
# dev machine that folder does not exist, so the system default is used.
param(
    [Parameter(Position = 0)]
    [string]$Action = "test",
    [string]$Godot = "D:\Genshin\Godot\Godot_v4.7-stable_win64_console.exe"
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SandboxAppData = Join-Path $ProjectRoot ".appdata"
if (Test-Path $SandboxAppData) {
    $env:APPDATA = $SandboxAppData
    New-Item -ItemType Directory -Force -Path $SandboxAppData | Out-Null
}

function Invoke-Godot([string[]]$Arguments) {
    return (& $Godot @Arguments 2>&1 | Out-String)
}

function Invoke-Import {
    Write-Host "== import ==" -ForegroundColor Cyan
    Invoke-Godot @("--headless", "--path", $ProjectRoot, "--editor", "--quit") | Out-Null
}

function Invoke-Test {
    Write-Host "== logic tests ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--headless", "--path", $ProjectRoot, "--script", "res://tests/test_battle.gd")
    Write-Host $out
    return ($out -match "RESULT PASS")
}

function Invoke-Ui {
    Write-Host "== ui smoke ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--headless", "--fixed-fps", "60", "--path", $ProjectRoot, "--script", "res://tests/test_ui.gd")
    Write-Host $out
    return ($out -match "RESULT PASS")
}

function Invoke-Boot {
    Write-Host "== boot ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--headless", "--fixed-fps", "60", "--path", $ProjectRoot, "--quit-after", "120")
    Write-Host $out
    return ($out -notmatch "SCRIPT ERROR")
}

function Invoke-Capture {
    Write-Host "== capture screenshots ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--fixed-fps", "60", "--path", $ProjectRoot, "--script", "res://tests/capture.gd")
    Write-Host $out
    return ($out -match "06_result")
}

function Get-ResultCode([bool]$Ok) {
    if ($Ok) { return 0 }
    return 1
}

function Invoke-Story {
    Write-Host "== story tests ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--headless", "--path", $ProjectRoot, "--script", "res://tests/test_story.gd")
    Write-Host $out
    return ($out -match "RESULT PASS")
}

function Invoke-CaptureStory {
    Write-Host "== capture story screenshots ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--fixed-fps", "60", "--path", $ProjectRoot, "--script", "res://tests/capture_story.gd")
    Write-Host $out
    return ($out -match "RESULT PASS")
}

function Invoke-StoryUi {
    Write-Host "== story UI full-play (4 scenes) ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--headless", "--fixed-fps", "60", "--path", $ProjectRoot, "--script", "res://tests/test_story_ui.gd")
    Write-Host $out
    return ($out -match "RESULT PASS")
}

function Invoke-StoryWrongUi {
    Write-Host "== story UI wrong-path regression (4 scenes) ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--headless", "--fixed-fps", "60", "--path", $ProjectRoot, "--script", "res://tests/test_story_wrong_ui.gd")
    Write-Host $out
    return ($out -match "RESULT PASS")
}

function Invoke-Feedback {
    Write-Host "== feedback / diagnostics self-check ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--headless", "--path", $ProjectRoot, "--script", "res://tests/test_feedback.gd")
    Write-Host $out
    return ($out -match "RESULT PASS")
}

function Invoke-Sfx {
    Write-Host "== sfx self-check ==" -ForegroundColor Cyan
    $out = Invoke-Godot @("--headless", "--path", $ProjectRoot, "--script", "res://tests/test_sfx.gd")
    Write-Host $out
    return ($out -match "RESULT PASS")
}

switch ($Action) {
    "import" { Invoke-Import }
    "test" { exit (Get-ResultCode (Invoke-Test)) }
    "story" { exit (Get-ResultCode (Invoke-Story)) }
    "story-ui" { exit (Get-ResultCode (Invoke-StoryUi)) }
    "story-wrong" { exit (Get-ResultCode (Invoke-StoryWrongUi)) }
    "feedback" { exit (Get-ResultCode (Invoke-Feedback)) }
    "sfx" { exit (Get-ResultCode (Invoke-Sfx)) }
    "ui" { exit (Get-ResultCode (Invoke-Ui)) }
    "boot" { exit (Get-ResultCode (Invoke-Boot)) }
    "capture" { exit (Get-ResultCode (Invoke-Capture)) }
    "capture-story" { exit (Get-ResultCode (Invoke-CaptureStory)) }
    "all" {
        Invoke-Import
        $testOk = Invoke-Test
        $storyOk = Invoke-Story
        $storyUiOk = Invoke-StoryUi
        $storyWrongOk = Invoke-StoryWrongUi
        $feedbackOk = Invoke-Feedback
        $sfxOk = Invoke-Sfx
        $uiOk = Invoke-Ui
        $bootOk = Invoke-Boot
        Write-Host ""
        Write-Host "test=$testOk story=$storyOk storyUi=$storyUiOk storyWrong=$storyWrongOk feedback=$feedbackOk sfx=$sfxOk ui=$uiOk boot=$bootOk"
        exit (Get-ResultCode ($testOk -and $storyOk -and $storyUiOk -and $storyWrongOk -and $feedbackOk -and $sfxOk -and $uiOk -and $bootOk))
    }
    default { Write-Host "unknown action: $Action"; exit 2 }
}
