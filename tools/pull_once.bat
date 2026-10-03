@echo off
REM ================================================================
REM  pull_once.bat - pull latest code once, then exit.
REM  Double-click to run. Use this for a single manual update.
REM ================================================================
cd /d "%~dp0.."
echo Pulling latest from GitHub ...
git pull --ff-only
echo.
echo Done.
pause >nul
