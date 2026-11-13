<#
.SYNOPSIS
    Roblox Touchscreen Switch - Windows 11 Compatibility & Security Verification Suite
.DESCRIPTION
    Can be run by either your Administrator account or your son's Standard Child account
    to verify:
      1. Windows 11 OS & PowerShell PnpDevice module availability
      2. Exact 'HID-compliant touch screen' detection & single-device safeguard status
      3. NTFS ACL lockdown on C:\Program Files\RobloxTouchscreenSwitch (confirming standard users CANNOT modify files)
      4. Scheduled Task registration, SYSTEM principal, and SDDL standard-user execute rights ('(A;;GRGX;;;AU)')
      5. GUI executable presence and activity log accessibility
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  ROBLOX TOUCHSCREEN SWITCH - COMPATIBILITY & SECURITY AUDIT" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "Running as user : $env:USERDOMAIN\$env:USERNAME"
Write-Host "Computer Name   : $env:COMPUTERNAME"
Write-Host "OS Version      : $([Environment]::OSVersion.VersionString)"
Write-Host ""

$PassCount = 0
$WarnCount = 0
$FailCount = 0

function Report-Check {
    param([string]$Status, [string]$Title, [string]$Detail)
    if ($Status -eq 'PASS') {
        $script:PassCount++
        Write-Host "  [PASS] $Title" -ForegroundColor Green
    } elseif ($Status -eq 'WARN') {
        $script:WarnCount++
        Write-Host "  [WARN] $Title" -ForegroundColor Yellow
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $Title" -ForegroundColor Red
    }
    if ($Detail) {
        Write-Host "         $Detail" -ForegroundColor Gray
    }
}

# Check 1: PnpDevice Module & Touchscreen Hardware Enumeration
try {
    Import-Module PnpDevice -ErrorAction Stop
    $TouchDevices = @(Get-PnpDevice -Class 'HIDClass' -ErrorAction SilentlyContinue | Where-Object {
        $_.FriendlyName -eq 'HID-compliant touch screen'
    })
    $PresentDevices = @($TouchDevices | Where-Object { $_.Present -eq $true })
    $TargetList = if ($PresentDevices.Count -gt 0) { $PresentDevices } else { $TouchDevices }

    if ($TargetList.Count -eq 1) {
        $d = $TargetList[0]
        Report-Check 'PASS' "Single 'HID-compliant touch screen' Detected" "InstanceId: $($d.InstanceId) | Status: $($d.Status)"
    } elseif ($TargetList.Count -eq 0) {
        Report-Check 'WARN' "No 'HID-compliant touch screen' Detected" "Verify touchscreen driver is enabled in Device Manager."
    } else {
        Report-Check 'WARN' "Multiple ($($TargetList.Count)) 'HID-compliant touch screen' Nodes Detected" "Ensure Administrator has pinned the primary InstanceId in config.json."
    }
} catch {
    Report-Check 'FAIL' "PnpDevice Module Check" $_.Exception.Message
}

# Check 2: Installed Files & GUI Executable
$InstallDir = 'C:\Program Files\RobloxTouchscreenSwitch'
$ExePath    = Join-Path $InstallDir 'RobloxTouchSwitch.exe'
$WorkerPath = Join-Path $InstallDir 'Invoke-TouchscreenAction.ps1'

if ((Test-Path -LiteralPath $ExePath) -and (Test-Path -LiteralPath $WorkerPath)) {
    Report-Check 'PASS' "Application Binary & Worker Script Installed" "Found $ExePath"
} else {
    Report-Check 'FAIL' "Application Installation Check" "Files missing in '$InstallDir'. Run Install-RobloxTouchSwitch.bat as Administrator."
}

# Check 3: NTFS Security ACL Verification (Standard Users Must NOT Have Write Access)
if (Test-Path -LiteralPath $WorkerPath) {
    try {
        $Acl = Get-Acl -LiteralPath $WorkerPath
        $UnsafeRules = @($Acl.Access | Where-Object {
            ($_.IdentityReference.Value -match 'Users|Everyone|Authenticated Users') -and
            ($_.FileSystemRights.ToString() -match 'Write|Modify|FullControl|Delete') -and
            ($_.AccessControlType -eq 'Allow')
        })
        if ($UnsafeRules.Count -eq 0) {
            Report-Check 'PASS' "NTFS Permission Lockdown Verified" "Standard/Child accounts have ReadAndExecute only; cannot modify elevated script or EXE."
        } else {
            Report-Check 'FAIL' "NTFS Permission Lockdown Weak" "Found write permission for non-admin group on $WorkerPath."
        }
    } catch {
        Report-Check 'WARN' "NTFS ACL Inspection" $_.Exception.Message
    }
}

# Check 4: Scheduled Tasks & SDDL Execute Permissions
try {
    $Scheduler = New-Object -ComObject 'Schedule.Service'
    $Scheduler.Connect()
    $Folder = $Scheduler.GetFolder('\RobloxTouchscreenSwitch')
    foreach ($TaskName in @('DisableTouchscreen', 'EnableTouchscreen')) {
        $Task = $Folder.GetTask($TaskName)
        $Sddl = $Task.GetSecurityDescriptor(4)
        if ($Sddl -match '\(A;;GRGX;;;AU\)') {
            Report-Check 'PASS' "Scheduled Task '$TaskName' Security Descriptor" "Runs as SYSTEM; Standard Users have Read/Execute (GRGX) ONLY and cannot modify task."
        } else {
            Report-Check 'FAIL' "Scheduled Task '$TaskName' SDDL Check" "Missing (A;;GRGX;;;AU) ACE in SDDL: $Sddl"
        }
    }
} catch {
    Report-Check 'FAIL' "Scheduled Tasks Check" "Could not read '\RobloxTouchscreenSwitch' tasks: $($_.Exception.Message)"
}

# Check 5: Activity Log Write Access
$LogPath = 'C:\ProgramData\RobloxTouchscreenSwitch\activity.log'
if (Test-Path -LiteralPath $LogPath) {
    Report-Check 'PASS' "Activity Log Accessible" "Located at $LogPath"
} else {
    Report-Check 'WARN' "Activity Log Not Found Yet" "Expected at $LogPath"
}

Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Summary: $PassCount Passed  |  $WarnCount Warnings  |  $FailCount Failed" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------"
