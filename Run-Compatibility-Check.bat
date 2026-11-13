@echo off
setlocal EnableExtensions
title Roblox Touchscreen Switch v1.1.0 - Compatibility and Security Audit
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnostics\Test-CompatibilityAndSecurity.ps1"
echo.
pause
