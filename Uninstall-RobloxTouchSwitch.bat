@echo off
setlocal EnableExtensions
title Roblox Touchscreen Switch - Administrator Uninstaller

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges via Windows UAC...
    set "SELF_BAT=%~f0"
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF_BAT -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\Uninstall-Logic.ps1"
echo.
pause
