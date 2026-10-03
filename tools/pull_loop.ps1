# pull_loop.ps1 - Auto-pull latest code from GitHub (near real-time)
# Usage:
#   1) Clone this repo into your project folder (or open PowerShell in that folder)
#   2) Run:  powershell -ExecutionPolicy Bypass -File tools\pull_loop.ps1
#   Pulls every 3 seconds; keep the Godot editor open and it hot-reloads.
#   Press Ctrl+C to stop.
#
# If PowerShell refuses to run this file ("running scripts is disabled"),
# just use tools\pull_loop.bat instead (double-click, no policy needed).

$ErrorActionPreference = "SilentlyContinue"

# Always operate from the project root, no matter where it is launched from
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "=== PPP auto-pull (every 3s) ===" -ForegroundColor Cyan
Write-Host "Keep the Godot editor open; changes reload automatically after pull." -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray

while ($true) {
    try {
        $out = (& git pull --ff-only) 2>&1 | Out-String
        if ($out -notmatch "Already up to date") {
            $stamp = Get-Date -Format "HH:mm:ss"
            Write-Host ("[$stamp] " + ($out -replace "`r|`n", " ")) -ForegroundColor Green
        }
    } catch {
        $stamp = Get-Date -Format "HH:mm:ss"
        Write-Host ("[$stamp] pull failed: " + $_.Exception.Message) -ForegroundColor Red
    }
    Start-Sleep -Seconds 3
}
