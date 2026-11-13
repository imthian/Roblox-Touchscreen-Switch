@echo off
setlocal EnableExtensions
title Roblox Touchscreen Switch - Emergency Touch Recovery

echo ======================================================================
echo   EMERGENCY TOUCHSCREEN RECOVERY (WINDOWS 11 - v1.2.4)
echo ======================================================================
echo.

if /I "%~1"=="--elevated" goto :ElevatedRecovery

echo [Step 1] Attempting to restore touchscreen via Scheduled Task (No Admin Password needed)...
"%SystemRoot%\System32\schtasks.exe" /Run /TN "\RobloxTouchscreenSwitch\EnableTouchscreen" >nul 2>&1
if not errorlevel 1 (
    timeout /t 3 /nobreak >nul
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ^
        "$cfgPath = Join-Path $env:ProgramFiles 'RobloxTouchscreenSwitch\config.json'; " ^
        "$pins = @(); " ^
        "if (Test-Path -LiteralPath $cfgPath) { try { $c = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json; if ($c.PinnedInstanceIds) { $pins = @($c.PinnedInstanceIds | Where-Object { $_ }) } elseif ($c.PinnedInstanceId) { $pins = @($c.PinnedInstanceId) } } catch {} }; " ^
        "$devs = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter \"PNPClass = 'HIDClass'\" | Where-Object { ($_.Name -eq 'HID-compliant touch screen') -or (($_.HardwareID + $_.CompatibleID) -imatch 'HID_DEVICE_UP:000D_U:0004') }); " ^
        "if ($pins.Count -gt 0) { " ^
        "  $missing = @(); $unhealthy = @(); " ^
        "  foreach ($p in $pins) { " ^
        "    $m = @($devs | Where-Object { $_.DeviceID -ieq $p }); " ^
        "    if ($m.Count -ne 1) { $missing += $p } elseif ($m[0].ConfigManagerErrorCode -ne 0 -or $m[0].Status -ne 'OK') { $unhealthy += $p } " ^
        "  }; " ^
        "  if ($missing.Count -eq 0 -and $unhealthy.Count -eq 0) { Write-Host '[VERIFIED] All pinned touchscreens are active and healthy (ErrorCode=0, Status=OK).' -ForegroundColor Green; exit 0 } " ^
        "  else { Write-Host '[WARN] Pinned touchscreen(s) not healthy. Proceeding to direct Administrator recovery...' -ForegroundColor Yellow; exit 1 } " ^
        "} else { " ^
        "  if ($devs.Count -gt 0 -and @($devs | Where-Object { $_.ConfigManagerErrorCode -ne 0 -or $_.Status -ne 'OK' }).Count -eq 0) { Write-Host '[VERIFIED] Touchscreen is active and healthy (ErrorCode=0, Status=OK).' -ForegroundColor Green; exit 0 } " ^
        "  else { Write-Host '[WARN] Touchscreen is not healthy. Proceeding to direct Administrator recovery...' -ForegroundColor Yellow; exit 1 } " ^
        "}"
    if not errorlevel 1 (
        echo.
        pause
        exit /b 0
    )
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
echo [Step 2] Running direct Administrator PnP hardware enable, bus rescan, and state verification...
"%SystemRoot%\System32\pnputil.exe" /scan-devices >nul 2>&1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ^
    "Import-Module PnpDevice; " ^
    "$cfgPath = Join-Path $env:ProgramFiles 'RobloxTouchscreenSwitch\config.json'; " ^
    "$pins = @(); " ^
    "if (Test-Path -LiteralPath $cfgPath) { try { $c = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json; if ($c.PinnedInstanceIds) { $pins = @($c.PinnedInstanceIds | Where-Object { $_ }) } elseif ($c.PinnedInstanceId) { $pins = @($c.PinnedInstanceId) } } catch {} }; " ^
    "if ($pins.Count -gt 0) { foreach ($p in $pins) { Write-Host ('Enabling pinned touchscreen: ' + $p); Enable-PnpDevice -InstanceId $p -Confirm:$false -ErrorAction SilentlyContinue } } " ^
    "else { Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter \"PNPClass = 'HIDClass'\" | Where-Object { ($_.Name -eq 'HID-compliant touch screen') -or (($_.HardwareID + $_.CompatibleID) -imatch 'HID_DEVICE_UP:000D_U:0004') } | ForEach-Object { Write-Host ('Enabling touchscreen: ' + $_.DeviceID); Enable-PnpDevice -InstanceId $_.DeviceID -Confirm:$false -ErrorAction SilentlyContinue } }; " ^
    "Start-Sleep -Seconds 2; " ^
    "$after = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter \"PNPClass = 'HIDClass'\" | Where-Object { ($_.Name -eq 'HID-compliant touch screen') -or (($_.HardwareID + $_.CompatibleID) -imatch 'HID_DEVICE_UP:000D_U:0004') }); " ^
    "if ($pins.Count -gt 0) { " ^
    "  $miss = @(); $fault = @(); " ^
    "  foreach ($p in $pins) { " ^
    "    $node = @($after | Where-Object { $_.DeviceID -ieq $p }); " ^
    "    if ($node.Count -ne 1) { $miss += $p } elseif ($node[0].ConfigManagerErrorCode -ne 0 -or $node[0].Status -ne 'OK') { $fault += \"$p (Status=$($node[0].Status), Code=$($node[0].ConfigManagerErrorCode))\" } " ^
    "  }; " ^
    "  if ($miss.Count -gt 0) { Write-Host (\"[RECOVERY FAILED] Configured pinned device(s) missing: $($miss -join '; ')\") -ForegroundColor Red; exit 10 }; " ^
    "  if ($fault.Count -gt 0) { Write-Host (\"[RECOVERY FAILED] Device fault: $($fault -join '; ')\") -ForegroundColor Red; exit 20 }; " ^
    "  Write-Host '[RECOVERY VERIFIED] All configured pinned touchscreens are active (Status=OK, ErrorCode=0).' -ForegroundColor Green; exit 0; " ^
    "} else { " ^
    "  if ($after.Count -eq 0) { Write-Host '[RECOVERY FAILED] No touchscreen device was detected after bus rescan.' -ForegroundColor Red; exit 10 }; " ^
    "  $bad = @($after | Where-Object { $_.ConfigManagerErrorCode -ne 0 -or $_.Status -ne 'OK' }); " ^
    "  if ($bad.Count -gt 0) { foreach ($b in $bad) { Write-Host (\"[RECOVERY FAILED] Device $($b.DeviceID) reported Status=$($b.Status), Code=$($b.ConfigManagerErrorCode)\") -ForegroundColor Red }; exit 20 } " ^
    "  else { foreach ($ok in $after) { Write-Host (\"[RECOVERY VERIFIED] Touchscreen $($ok.DeviceID) is active (Status=OK, ErrorCode=0).\") -ForegroundColor Green }; exit 0 } " ^
    "}"
echo.
pause
