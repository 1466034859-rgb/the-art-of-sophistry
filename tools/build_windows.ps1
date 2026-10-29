# Build a Windows executable for The Art of Sophistry.
# Requires Godot 4.7 export templates installed (Editor -> Manage Export Templates).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\build_windows.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot "build"

function Find-Godot {
    $candidates = @(
        "D:\Genshin\Godot\Godot_v4.7-stable_win64_console.exe",
        "D:\Genshin\Godot\Godot_v4.7-stable_win64.exe",
        "C:\Godot\Godot_v4.7-stable_win64_console.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-TemplateDir {
    $dir = Join-Path $env:APPDATA "Godot\export_templates\4.7.stable"
    if (Test-Path $dir) { return $dir }
    return $null
}

$godot = Find-Godot
if (-not $godot) {
    Write-Host "Godot 4.7 not found. Put it on PATH or edit Find-Godot in this script."
    exit 2
}

$templates = Get-TemplateDir
if (-not $templates) {
    Write-Host "Export templates for 4.7 are not installed."
    Write-Host "Open Godot -> Editor -> Manage Export Templates -> Download and Install."
    Write-Host "Then run this script again. The project itself still runs with F5 / run_game.bat."
    exit 0
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Write-Host "== exporting Windows build =="
& $godot --headless --path $ProjectRoot --export-release "Windows Desktop" (Join-Path $BuildDir "Sophistry.exe")
if (Test-Path (Join-Path $BuildDir "Sophistry.exe")) {
    Write-Host "OK: $BuildDir\Sophistry.exe"
    exit 0
}
Write-Host "Export failed. Check the preset name and template version."
exit 1
