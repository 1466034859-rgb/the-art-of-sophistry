# Package a playtest zip for sharing.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\make_share_zip.ps1
# Output: dist\Sophistry-playtest.zip

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DistDir = Join-Path $ProjectRoot "dist"
$Staging = Join-Path $DistDir "Sophistry-playtest"

if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Staging | Out-Null

$files = @("project.godot", "icon.svg", "run_game.bat", "run_game.ps1", "README.md", "export_presets.cfg", ".gitignore")
foreach ($file in $files) {
    $source = Join-Path $ProjectRoot $file
    if (Test-Path $source) { Copy-Item $source (Join-Path $Staging $file) -Force }
}
$dirs = @("scenes", "core", "autoload", "ai", "ui", "data", "docs", "tests", "tools")
foreach ($dir in $dirs) {
    $source = Join-Path $ProjectRoot $dir
    if (Test-Path $source) {
        Copy-Item $source (Join-Path $Staging $dir) -Recurse -Force
    }
}
# Keep the package small: drop caches, local logs, and generated screenshots.
foreach ($junk in @(".godot", ".appdata", "dist", "screenshots")) {
    $path = Join-Path $Staging $junk
    if (Test-Path $path) { Remove-Item $path -Recurse -Force }
}
# Drop debug-only tests from the player package.
$debugTests = @("tests\capture.gd", "tests\capture_story.gd", "tests\capture_wrong.gd", "tests\check_caps.gd", "tests\test_ui.gd")
foreach ($test in $debugTests) {
    $path = Join-Path $Staging $test
    if (Test-Path $path) { Remove-Item $path -Force }
}

$zip = Join-Path $DistDir "Sophistry-playtest.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $Staging "*") -DestinationPath $zip -Force
Write-Host "OK: $zip"
Write-Host "Player needs Godot 4.7 installed, then double-click run_game.bat."
