@echo off
setlocal EnableExtensions
title Roblox Touchscreen Switch v1.1.0 - Administrator Installer

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges via Windows UAC...
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\Install-Logic.ps1"
echo.
pause
