@echo off
setlocal EnableExtensions
title Roblox Touchscreen Switch - Emergency Touch Recovery

echo ======================================================================
echo   EMERGENCY TOUCHSCREEN RECOVERY (WINDOWS 11)
echo ======================================================================
echo.

if /I "%~1"=="--elevated" goto :ElevatedRecovery

echo [Step 1] Attempting to restore touchscreen via Scheduled Task (No Admin Password needed)...
"%SystemRoot%\System32\schtasks.exe" /Run /TN "\RobloxTouchscreenSwitch\EnableTouchscreen" >nul 2>&1
if %errorLevel% equ 0 (
    timeout /t 3 /nobreak >nul
    echo [OK] Triggered Restore Touch Scheduled Task. Test your touchscreen now.
    echo If touch is still not responding, press any key to run direct Administrator hardware reset...
    pause >nul
)

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator elevation for direct hardware reset...
    set "SELF_BAT=%~f0"
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF_BAT -ArgumentList '--elevated' -Verb RunAs"
    exit /b
)

:ElevatedRecovery
echo.
echo [Step 2] Running direct Administrator PnP hardware enable and bus rescan...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ^
    "Import-Module PnpDevice; " ^
    "$cfgPath = Join-Path $env:ProgramFiles 'RobloxTouchscreenSwitch\config.json'; " ^
    "$pins = @(); " ^
    "if (Test-Path -LiteralPath $cfgPath) { try { $c = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json; if ($c.PinnedInstanceIds) { $pins = @($c.PinnedInstanceIds | Where-Object { $_ }) } elseif ($c.PinnedInstanceId) { $pins = @($c.PinnedInstanceId) } } catch {} }; " ^
    "if ($pins.Count -gt 0) { foreach ($p in $pins) { Write-Host ('Enabling pinned touchscreen: ' + $p); Enable-PnpDevice -InstanceId $p -Confirm:$false -ErrorAction SilentlyContinue } } " ^
    "else { Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter \"PNPClass = 'HIDClass'\" | Where-Object { ($_.Name -eq 'HID-compliant touch screen') -or (($_.HardwareID + $_.CompatibleID) -imatch 'HID_DEVICE_UP:000D_U:0004') } | ForEach-Object { Write-Host ('Enabling touchscreen: ' + $_.DeviceID); Enable-PnpDevice -InstanceId $_.DeviceID -Confirm:$false -ErrorAction SilentlyContinue } }"
"%SystemRoot%\System32\pnputil.exe" /scan-devices
echo.
echo [DONE] Direct touchscreen recovery completed.
pause
