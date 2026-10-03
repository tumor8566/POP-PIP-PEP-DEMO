@echo off
REM ================================================================
REM  pull_loop.bat - PPP project auto-pull loop (every 3 seconds)
REM  Double-click to run. No PowerShell policy needed. Ctrl+C to stop.
REM ================================================================
setlocal
cd /d "%~dp0.."
title PPP auto-pull (git)

echo ================================================
echo  PPP auto-pull loop - every 3 seconds
echo  Keep Godot open; it hot-reloads after each pull.
echo  Press Ctrl+C to stop.
echo ================================================

:loop
git pull --ff-only 2>&1 | findstr /v /i /c:"Already up to date"
timeout /t 3 /nobreak >nul
goto loop
