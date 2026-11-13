@echo off
setlocal EnableExtensions
title Roblox Touchscreen Switch - Compatibility and Security Audit
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnostics\Test-CompatibilityAndSecurity.ps1"
echo.
pause
