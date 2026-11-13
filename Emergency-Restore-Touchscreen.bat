@echo off
setlocal EnableExtensions
title Roblox Touchscreen Switch v1.1.0 - Emergency Touch Recovery

echo ======================================================================
echo   EMERGENCY TOUCHSCREEN RECOVERY (WINDOWS 11 - v1.1.0)
echo ======================================================================
echo.

:: If already launched with --elevated, skip the Scheduled Task step and go straight to Admin PnP recovery
if /I "%~1"=="--elevated" goto :ElevatedRecovery

echo [Step 1] Attempting to restore touchscreen via Scheduled Task (No Admin Password needed)...
"%SystemRoot%\System32\schtasks.exe" /Run /TN "\RobloxTouchscreenSwitch\EnableTouchscreen" >nul 2>&1
if %errorLevel% equ 0 (
    timeout /t 2 /nobreak >nul
    echo [OK] Triggered Restore Touch Scheduled Task. Test your touchscreen now.
    echo If touch is still not responding, press any key to run direct Administrator hardware reset...
    pause >nul
)

:: Check if we already have Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator elevation for direct hardware reset...
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
    exit /b
)

:ElevatedRecovery
echo.
echo [Step 2] Running direct Administrator PnP hardware enable and bus rescan...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ^
    "Import-Module PnpDevice; " ^
    "$cfgPath = 'C:\Program Files\RobloxTouchscreenSwitch\config.json'; " ^
    "$pinned = $null; " ^
    "if (Test-Path $cfgPath) { try { $pinned = (Get-Content $cfgPath -Raw | ConvertFrom-Json).PinnedInstanceId } catch {} }; " ^
    "if ($pinned) { Write-Host ('Enabling pinned touchscreen: ' + $pinned); Enable-PnpDevice -InstanceId $pinned -Confirm:$false -ErrorAction SilentlyContinue } " ^
    "else { Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter \"PNPClass = 'HIDClass'\" | Where-Object { ($_.Name -eq 'HID-compliant touch screen') -or (($_.HardwareID + $_.CompatibleID) -imatch 'HID_DEVICE_UP:000D_U:0004') } | ForEach-Object { Write-Host ('Enabling touchscreen: ' + $_.DeviceID); Enable-PnpDevice -InstanceId $_.DeviceID -Confirm:$false -ErrorAction SilentlyContinue } }"
"%SystemRoot%\System32\pnputil.exe" /scan-devices
echo.
echo [DONE] Direct touchscreen recovery completed.
pause
