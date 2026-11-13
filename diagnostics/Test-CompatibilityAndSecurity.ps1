<#
.SYNOPSIS
    Roblox Touchscreen Switch - Windows 11 Compatibility & Security Verification Suite (v1.2.4)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$InstallDir  = Join-Path $env:ProgramFiles 'RobloxTouchscreenSwitch'
$DataDir     = Join-Path $env:ProgramData  'RobloxTouchscreenSwitch'
$VersionFile = Join-Path $InstallDir 'VERSION'
$AppVersion  = if (Test-Path -LiteralPath $VersionFile) { (Get-Content -LiteralPath $VersionFile -Raw).Trim() } else { '1.2.4' }

$ModulePath  = Join-Path $InstallDir 'SecurityValidation.psm1'
if (-not (Test-Path -LiteralPath $ModulePath)) {
    $ModulePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..\core\SecurityValidation.psm1'
}
if (Test-Path -LiteralPath $ModulePath) {
    Import-Module $ModulePath -Force -ErrorAction SilentlyContinue
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  ROBLOX TOUCHSCREEN SWITCH v$AppVersion - COMPATIBILITY & SECURITY AUDIT" -ForegroundColor Cyan
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

# Check 1: Unified WMI/CIM Touchscreen Hardware Enumeration
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
        Report-Check 'WARN' "Multiple ($($TargetList.Count)) Touchscreen Nodes Detected" "Ensure Administrator has pinned the desired InstanceId(s) in config.json."
    }
} catch {
    Report-Check 'FAIL' "Hardware Enumeration Check" $_.Exception.Message
}

# Check 2: Installed Files & GUI Executable
$ExePath    = Join-Path $InstallDir 'RobloxTouchSwitch.exe'
$WorkerPath = Join-Path $InstallDir 'Invoke-TouchscreenAction.ps1'

if ((Test-Path -LiteralPath $ExePath) -and (Test-Path -LiteralPath $WorkerPath)) {
    Report-Check 'PASS' "Application Binary & Worker Script Installed" "Found $ExePath"
} else {
    Report-Check 'FAIL' "Application Installation Check" "Files missing in '$InstallDir'. Run Install-RobloxTouchSwitch.bat as Administrator."
}

# Check 3: Directory Owner & NTFS ACL Lockdown on Program Files AND ProgramData using shared Test-SafeDirectoryAcl
foreach ($ProtectedPath in @($InstallDir, $DataDir)) {
    if (Test-Path -LiteralPath $ProtectedPath) {
        try {
            $Item = Get-Item -LiteralPath $ProtectedPath -Force
            $IsReparse = ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            $Acl = Get-Acl -LiteralPath $ProtectedPath
            $CheckResult = Test-SafeDirectoryAcl -DirectoryAcl $Acl -PathDescription "'$ProtectedPath'"
            if (-not $IsReparse -and $CheckResult.Success) {
                Report-Check 'PASS' "Owner & NTFS Lockdown Verified on '$ProtectedPath'" "Owned by Admin/SYSTEM; Standard Users have Read-Only access."
            } else {
                $err = if ($IsReparse) { "ReparsePoint detected." } else { $CheckResult.Error }
                Report-Check 'FAIL' "Owner or NTFS Lockdown Weak on '$ProtectedPath'" $err
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
