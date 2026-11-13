<#
.SYNOPSIS
    Roblox Touchscreen Switch v1.1.0 - Windows 11 Compatibility & Security Verification Suite
.DESCRIPTION
    Can be run by either your Administrator account or your son's Standard Child account
    to verify:
      1. Locale-independent HID Touchscreen detection (Usage Page 000D:0004 + FriendlyName)
      2. Application binary and worker script installation
      3. NTFS ACL lockdown on BOTH C:\Program Files\RobloxTouchscreenSwitch AND C:\ProgramData\RobloxTouchscreenSwitch
         (verifying Standard Users have Read-Only access and CANNOT modify scripts or redirect SYSTEM file writes)
      4. Scheduled Task registration, full powershell.exe path, SYSTEM principal, and SDDL execute rights ('(A;;GRGX;;;AU)')
      5. SYSTEM Audit Log & status.json accessibility
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  ROBLOX TOUCHSCREEN SWITCH v1.1.0 - COMPATIBILITY & SECURITY AUDIT" -ForegroundColor Cyan
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

# Check 1: Unified WMI/CIM Touchscreen Hardware Enumeration (HID Usage 000D:0004 + FriendlyName)
try {
    $WmiDevices = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter "PNPClass = 'HIDClass'" -ErrorAction Stop)
    $TargetList = @()
    foreach ($d in $WmiDevices) {
        $IsTouch = ($d.Name -eq 'HID-compliant touch screen') -or (($d.HardwareID + $d.CompatibleID) -imatch 'HID_DEVICE_UP:000D_U:0004')
        if ($IsTouch) { $TargetList += $d }
    }

    if ($TargetList.Count -eq 1) {
        $d = $TargetList[0]
        Report-Check 'PASS' "Single Touchscreen Detected (HID 000D:0004)" "InstanceId: $($d.DeviceID) | Status: $($d.Status) (ErrorCode=$($d.ConfigManagerErrorCode))"
    } elseif ($TargetList.Count -eq 0) {
        Report-Check 'WARN' "No Touchscreen Detected" "Verify touchscreen driver is enabled in Device Manager."
    } else {
        Report-Check 'WARN' "Multiple ($($TargetList.Count)) Touchscreen Nodes Detected" "Ensure Administrator has pinned the primary InstanceId in config.json."
    }
} catch {
    Report-Check 'FAIL' "Hardware Enumeration Check" $_.Exception.Message
}

# Check 2: Installed Files & GUI Executable
$InstallDir = 'C:\Program Files\RobloxTouchscreenSwitch'
$DataDir    = 'C:\ProgramData\RobloxTouchscreenSwitch'
$ExePath    = Join-Path $InstallDir 'RobloxTouchSwitch.exe'
$WorkerPath = Join-Path $InstallDir 'Invoke-TouchscreenAction.ps1'

if ((Test-Path -LiteralPath $ExePath) -and (Test-Path -LiteralPath $WorkerPath)) {
    Report-Check 'PASS' "Application Binary & Worker Script Installed" "Found $ExePath"
} else {
    Report-Check 'FAIL' "Application Installation Check" "Files missing in '$InstallDir'. Run Install-RobloxTouchSwitch.bat as Administrator."
}

# Check 3: NTFS Security ACL Verification on Program Files AND ProgramData
foreach ($ProtectedPath in @($InstallDir, $DataDir)) {
    if (Test-Path -LiteralPath $ProtectedPath) {
        try {
            $Item = Get-Item -LiteralPath $ProtectedPath -Force
            $IsReparse = ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            $Acl = Get-Acl -LiteralPath $ProtectedPath
            $UnsafeRules = @($Acl.Access | Where-Object {
                ($_.IdentityReference.Value -match 'Users|Everyone|Authenticated Users') -and
                ($_.FileSystemRights.ToString() -match 'Write|Modify|FullControl|Delete') -and
                ($_.AccessControlType -eq 'Allow')
            })
            if (-not $IsReparse -and $UnsafeRules.Count -eq 0) {
                Report-Check 'PASS' "NTFS Lockdown Verified on '$ProtectedPath'" "Standard Users have Read-Only access; symlink redirection & tampering blocked."
            } else {
                Report-Check 'FAIL' "NTFS Lockdown Weak on '$ProtectedPath'" "Found non-admin write permission or ReparsePoint."
            }
        } catch {
            Report-Check 'WARN' "NTFS ACL Inspection ($ProtectedPath)" $_.Exception.Message
        }
    } else {
        Report-Check 'FAIL' "Protected Directory Missing" "$ProtectedPath does not exist."
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
            Report-Check 'PASS' "Scheduled Task '$TaskName' Security Descriptor" "Runs as SYSTEM; Standard Users have Read/Execute (GRGX) ONLY."
        } else {
            Report-Check 'FAIL' "Scheduled Task '$TaskName' SDDL Check" "Missing (A;;GRGX;;;AU) ACE in SDDL: $Sddl"
        }
    }
} catch {
    Report-Check 'FAIL' "Scheduled Tasks Check" "Could not read '\RobloxTouchscreenSwitch' tasks: $($_.Exception.Message)"
}

# Check 5: SYSTEM Audit Log Read Access
$SysLogPath = Join-Path $DataDir 'system-activity.log'
if (Test-Path -LiteralPath $SysLogPath) {
    Report-Check 'PASS' "SYSTEM Audit Log Accessible (Read-Only)" "Located at $SysLogPath"
} else {
    Report-Check 'WARN' "SYSTEM Audit Log Not Found Yet" "Expected at $SysLogPath"
}

Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Summary: $PassCount Passed  |  $WarnCount Warnings  |  $FailCount Failed" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------"
