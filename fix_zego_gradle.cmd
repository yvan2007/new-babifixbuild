@echo off
echo ============================================================
echo Fix ZEGOCLOUD Gradle Network Issue
echo ============================================================
echo.

cd /d "%~dp0"

powershell -ExecutionPolicy Bypass -File "%~dp0fix_zego_gradle.ps1"

echo.
pause
