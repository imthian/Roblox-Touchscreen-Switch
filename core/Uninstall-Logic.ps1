<#
.SYNOPSIS
    Administrator Uninstaller for Roblox Touchscreen Switch (Windows 11 - v1.2.4)
.DESCRIPTION
    1. Restores the touchscreen (respecting PinnedInstanceIds and single-device safeguards).
    2. Independently VERIFIES that the touchscreen reported ErrorCode == 0 and Status == 'OK'.
       If verification fails, clearly alerts the Administrator that restoration is unconfirmed.
    3. Removes Scheduled Tasks, shortcuts, and application files.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$ScriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PackageRoot = Split-Path -Parent $ScriptRoot
$VersionFile = Join-Path $PackageRoot 'VERSION'
$AppVersion  = if (Test-Path -LiteralPath $VersionFile) { (Get-Content -LiteralPath $VersionFile -Raw).Trim() } else { '1.2.4' }

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  ROBLOX TOUCHSCREEN SWITCH v$AppVersion - ADMINISTRATOR UNINSTALLER" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Administrator privileges are required to uninstall Roblox Touchscreen Switch." -ForegroundColor Red
    exit 1
}

$TouchVerifiedHealthy = $false

Write-Host "[1/4] Restoring touchscreen before uninstalling..." -ForegroundColor Yellow
try {
    Import-Module PnpDevice -ErrorAction SilentlyContinue
    $ConfigPath = Join-Path $env:ProgramFiles 'RobloxTouchscreenSwitch\config.json'
    $PinnedIds = @()
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $Cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($Cfg.PinnedInstanceIds) {
                $PinnedIds = @($Cfg.PinnedInstanceIds | Where-Object { $_ -and $_.ToString().Trim().Length -gt 0 })
            } elseif ($Cfg.PinnedInstanceId -and $Cfg.PinnedInstanceId.ToString().Trim().Length -gt 0) {
                $PinnedIds = @($Cfg.PinnedInstanceId.ToString().Trim())
            }
        } catch { }
    }

    $WmiDevices = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter "PNPClass = 'HIDClass'" -ErrorAction SilentlyContinue)
    $AllTouch = @()
    foreach ($d in $WmiDevices) {
        $IsTouch = ($d.Name -eq 'HID-compliant touch screen') -or (($d.HardwareID + $d.CompatibleID) -imatch 'HID_DEVICE_UP:000D_U:0004')
        if ($IsTouch) { $AllTouch += $d }
    }

    if ($PinnedIds.Count -gt 0) {
        foreach ($pin in $PinnedIds) {
            $Matched = @($AllTouch | Where-Object { $_.DeviceID -ieq $pin })
            if ($Matched.Count -eq 1) {
                Enable-PnpDevice -InstanceId $Matched[0].DeviceID -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "  [OK] Re-enabled pinned touchscreen: $($Matched[0].DeviceID)" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Pinned touchscreen '$pin' was not detected; skipping automatic enable." -ForegroundColor Yellow
            }
        }
    } elseif ($AllTouch.Count -eq 1) {
        Enable-PnpDevice -InstanceId $AllTouch[0].DeviceID -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  [OK] Re-enabled single touchscreen: $($AllTouch[0].DeviceID)" -ForegroundColor Green
    } elseif ($AllTouch.Count -gt 1) {
        Write-Host "  [SAFEGUARD] Multiple ($($AllTouch.Count)) unpinned touchscreens found; skipping bulk enable to avoid modifying wrong devices." -ForegroundColor Yellow
    } else {
        Write-Host "  [INFO] No touchscreen device currently detected." -ForegroundColor Gray
    }

    # Independent Post-Enable Verification Step
    Start-Sleep -Seconds 1
    $AfterWmi = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter "PNPClass = 'HIDClass'" -ErrorAction SilentlyContinue)
    $VerifiedDevices = @()
    foreach ($d in $AfterWmi) {
        $IsTouch = ($d.Name -eq 'HID-compliant touch screen') -or (($d.HardwareID + $d.CompatibleID) -imatch 'HID_DEVICE_UP:000D_U:0004')
        if ($IsTouch) { $VerifiedDevices += $d }
    }

    if ($PinnedIds.Count -gt 0) {
        $AllPinsHealthy = $true
        foreach ($pin in $PinnedIds) {
            $check = @($VerifiedDevices | Where-Object { $_.DeviceID -ieq $pin })
            if ($check.Count -ne 1 -or $check[0].ConfigManagerErrorCode -ne 0 -or $check[0].Status -ne 'OK') {
                $AllPinsHealthy = $false
                break
            }
        }
        $TouchVerifiedHealthy = $AllPinsHealthy
    } elseif ($VerifiedDevices.Count -ge 1) {
        $BadNodes = @($VerifiedDevices | Where-Object { $_.ConfigManagerErrorCode -ne 0 -or $_.Status -ne 'OK' })
        $TouchVerifiedHealthy = ($BadNodes.Count -eq 0)
    }
} catch {
    Write-Host "  [WARN] Exception during PnP enable: $($_.Exception.Message)" -ForegroundColor Yellow
}

Get-Process -Name 'RobloxTouchSwitch' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[2/4] Removing Scheduled Tasks..." -ForegroundColor Yellow
foreach ($TaskName in @('DisableTouchscreen', 'EnableTouchscreen', 'RestoreTouchOnBoot')) {
    Unregister-ScheduledTask -TaskPath '\RobloxTouchscreenSwitch\' -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed task: \RobloxTouchscreenSwitch\$TaskName" -ForegroundColor Green
}
try {
    $Scheduler = New-Object -ComObject 'Schedule.Service'
    $Scheduler.Connect()
    $RootFolder = $Scheduler.GetFolder('\')
    $RootFolder.DeleteFolder('RobloxTouchscreenSwitch', 0)
    Write-Host "  [OK] Removed Scheduled Task folder '\RobloxTouchscreenSwitch'." -ForegroundColor Green
} catch { }

Write-Host ""
Write-Host "[3/4] Removing Desktop and Start Menu Shortcuts..." -ForegroundColor Yellow
$PublicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
$CommonStartMenu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Roblox Touchscreen Switch'

$DesktopLnk = Join-Path $PublicDesktop 'Roblox Touchscreen Switch.lnk'
if (Test-Path -LiteralPath $DesktopLnk) { Remove-Item -LiteralPath $DesktopLnk -Force -ErrorAction SilentlyContinue }
if (Test-Path -LiteralPath $CommonStartMenu) { Remove-Item -LiteralPath $CommonStartMenu -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "  [OK] Removed Public Desktop and Start Menu shortcuts." -ForegroundColor Green

Write-Host ""
Write-Host "[4/4] Removing Application Files..." -ForegroundColor Yellow
$InstallDir = Join-Path $env:ProgramFiles 'RobloxTouchscreenSwitch'
$DataDir    = Join-Path $env:ProgramData  'RobloxTouchscreenSwitch'

function Remove-DirectorySafely {
    param([string]$TargetPath)
    if (-not (Test-Path -LiteralPath $TargetPath)) { return }
    $RootItem = Get-Item -LiteralPath $TargetPath -Force
    if (($RootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Write-Host "  [SECURITY SKIP] '$TargetPath' is a ReparsePoint. Skipping automatic deletion." -ForegroundColor Red
        return
    }
    $ChildLinks = @(Get-ChildItem -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
        ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    })
    if ($ChildLinks.Count -gt 0) {
        Write-Host "  [SECURITY SKIP] '$TargetPath' contains nested ReparsePoints. Skipping automatic deletion." -ForegroundColor Red
        return
    }
    [System.IO.Directory]::Delete($TargetPath, $true)
    Write-Host "  [OK] Removed '$TargetPath'." -ForegroundColor Green
}

Remove-DirectorySafely -TargetPath $InstallDir

$DeleteLogsPrompt = Read-Host "Do you want to delete the SYSTEM audit logs in '$DataDir'? [Y/N] (Default: Y)"
if ($DeleteLogsPrompt -eq '' -or $DeleteLogsPrompt -match '^[Yy]') {
    Remove-DirectorySafely -TargetPath $DataDir
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
if ($TouchVerifiedHealthy) {
    Write-Host "  UNINSTALLATION COMPLETE - TOUCHSCREEN IS VERIFIED ENABLED (OK)" -ForegroundColor Green
} else {
    Write-Host "  UNINSTALLATION FINISHED - TOUCHSCREEN STATUS UNCONFIRMED" -ForegroundColor Yellow
    Write-Host "  Hardware verification could not confirm Status=OK (ErrorCode=0)." -ForegroundColor Yellow
    Write-Host "  If touch is unresponsive, run Device Manager -> Human Interface Devices" -ForegroundColor Yellow
    Write-Host "  -> right-click 'HID-compliant touch screen' -> Enable device, or restart Windows." -ForegroundColor Yellow
}
Write-Host "======================================================================" -ForegroundColor Cyan
