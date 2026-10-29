# Launch The Art of Sophistry (project mode, no export needed).
# Usage: double-click run_game.bat, or:
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_game.ps1

$ErrorActionPreference = "Stop"

function Find-Godot {
    $candidates = @(
        "D:\Genshin\Godot\Godot_v4.7-stable_win64.exe",
        "D:\Genshin\Godot\Godot_v4.7-stable_win64_console.exe",
        "C:\Godot\Godot_v4.7-stable_win64.exe",
        "C:\Godot\Godot_v4.7-stable_win64_console.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$godot = Find-Godot
if (-not $godot) {
    Write-Host "Godot 4.7 not found."
    Write-Host "Install Godot 4.7, or put godot.exe on PATH, then run this again."
    Write-Host "You can also open project.godot in the Godot editor and press F5."
    Read-Host "Press Enter to close"
    exit 2
}

Start-Process -FilePath $godot -ArgumentList @("--path", $PSScriptRoot)
