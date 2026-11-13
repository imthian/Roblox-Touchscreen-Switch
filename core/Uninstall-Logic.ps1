<#
.SYNOPSIS
    Administrator Uninstaller for Roblox Touchscreen Switch (Windows 11)
.DESCRIPTION
    1. Automatically re-enables the 'HID-compliant touch screen' device first so the handheld is never left with touch disabled.
    2. Removes the Scheduled Tasks and '\RobloxTouchscreenSwitch' task folder.
    3. Removes All-Users Desktop and Start Menu shortcuts.
    4. Removes C:\Program Files\RobloxTouchscreenSwitch (and optionally C:\ProgramData\RobloxTouchscreenSwitch).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  ROBLOX TOUCHSCREEN SWITCH - ADMINISTRATOR UNINSTALLER" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Administrator privileges are required to uninstall Roblox Touchscreen Switch." -ForegroundColor Red
    exit 1
}

# 1. Safety First: Ensure Touchscreen is Re-Enabled before removing anything
Write-Host "[1/4] Restoring 'HID-compliant touch screen' before uninstalling..." -ForegroundColor Yellow
try {
    Import-Module PnpDevice -ErrorAction SilentlyContinue
    $TouchDevs = @(Get-PnpDevice -Class 'HIDClass' -ErrorAction SilentlyContinue | Where-Object {
        $_.FriendlyName -eq 'HID-compliant touch screen'
    })
    foreach ($d in $TouchDevs) {
        if ($d.Status -ne 'OK' -or $d.ConfigManagerErrorCode -eq 22) {
            Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "  [OK] Re-enabled touchscreen: $($d.InstanceId)" -ForegroundColor Green
        } else {
            Write-Host "  [OK] Touchscreen is already enabled: $($d.InstanceId)" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  [WARN] Could not verify PnP state during uninstall: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 2. Stop running GUI if open
Get-Process -Name 'RobloxTouchSwitch' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 3. Remove Scheduled Tasks
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

# 4. Remove Shortcuts & Program Files
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
$InstallDir = 'C:\Program Files\RobloxTouchscreenSwitch'
$DataDir    = 'C:\ProgramData\RobloxTouchscreenSwitch'

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed '$InstallDir'." -ForegroundColor Green
}

$KeepLogs = Read-Host "Do you want to delete the troubleshooting activity logs in '$DataDir'? [Y/N] (Default: Y)"
if ($KeepLogs -eq '' -or $KeepLogs -match '^[Yy]') {
    if (Test-Path -LiteralPath $DataDir) {
        Remove-Item -LiteralPath $DataDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Removed '$DataDir'." -ForegroundColor Green
    }
} else {
    Write-Host "  [INFO] Retained activity logs in '$DataDir'." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  UNINSTALLATION COMPLETE - TOUCHSCREEN IS ENABLED" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
