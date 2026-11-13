@echo off
setlocal EnableExtensions
title Roblox Touchscreen Switch - Emergency Touch Recovery

echo ======================================================================
echo   EMERGENCY TOUCHSCREEN RECOVERY (WINDOWS 11)
echo ======================================================================
echo.
echo Attempting to restore touchscreen via Scheduled Task first (No Admin Password needed)...
schtasks.exe /Run /TN "\RobloxTouchscreenSwitch\EnableTouchscreen" >nul 2>&1
if %errorLevel% equ 0 (
    timeout /t 2 /nobreak >nul
    echo [OK] Triggered Restore Touch Scheduled Task. Test your touchscreen now.
    echo If touch is still not responding, press any key to run direct Administrator hardware reset...
    pause >nul
)

:: Check for Administrator privileges for direct PnP hardware reset
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator elevation for direct hardware reset...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
    exit /b
)

echo.
echo Running direct Administrator PnP hardware enable and bus rescan...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module PnpDevice; Get-PnpDevice -Class 'HIDClass' | Where-Object { $_.FriendlyName -eq 'HID-compliant touch screen' } | ForEach-Object { Write-Host ('Enabling: ' + $_.InstanceId); Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue }"
pnputil.exe /scan-devices
echo.
echo [DONE] Direct touchscreen recovery completed.
pause
