<#
.SYNOPSIS
    Roblox Touchscreen Switch v1.1.0 - Protected SYSTEM Worker Script
.DESCRIPTION
    Executes strictly under NT AUTHORITY\SYSTEM via Windows Scheduled Tasks:
      - \RobloxTouchscreenSwitch\DisableTouchscreen (Mouse Mode)
      - \RobloxTouchscreenSwitch\EnableTouchscreen  (Restore Touch)
      - \RobloxTouchscreenSwitch\RestoreTouchOnBoot (Safety Startup Recovery)

    SECURITY & HARDWARE SAFEGUARDS (v1.1.0):
    1. Located in C:\Program Files\RobloxTouchscreenSwitch\ (Read/Execute only for Standard Users;
       Full Control restricted to SYSTEM and Administrators).
    2. Writes audit logs and status.json ONLY to C:\ProgramData\RobloxTouchscreenSwitch\, which is
       locked via NTFS ACLs to FullControl for SYSTEM/Administrators and Read-Only for Standard Users
       (preventing symlink/junction redirection attacks or audit log forgery).
    3. Refuses to write if C:\ProgramData\RobloxTouchscreenSwitch or its target files have ReparsePoint attributes.
    4. Matches touchscreens across ALL Windows locales using HID Usage Page 0x000D / Usage 0x0004
       ('HID_DEVICE_UP:000D_U:0004') OR English FriendlyName 'HID-compliant touch screen' inside PNPClass 'HIDClass',
       filtered strictly to Present/connected devices via Win32_PnPEntity (identical to the GUI).
    5. Treats ONLY ConfigManagerErrorCode == 22 as intentionally Disabled (Mouse Mode), flagging any
       non-zero, non-22 error code as a hardware/driver error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Disable', 'Enable')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$AppVersion = '1.1.0'

$InstallDir = 'C:\Program Files\RobloxTouchscreenSwitch'
$ConfigPath = Join-Path $InstallDir 'config.json'
$DataDir    = 'C:\ProgramData\RobloxTouchscreenSwitch'
$StatusPath = Join-Path $DataDir 'status.json'
$LogPath    = Join-Path $DataDir 'system-activity.log'

# Ensure DataDir exists and verify it is NOT a symlink/junction (ReparsePoint defense-in-depth)
if (-not (Test-Path -LiteralPath $DataDir)) {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
}
$DirItem = Get-Item -LiteralPath $DataDir -Force
if (($DirItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "SECURITY ABORT: '$DataDir' is a ReparsePoint (symlink/junction). Refusing to write as SYSTEM."
}

function Test-SafeTargetFile {
    param([string]$FilePath)
    if (Test-Path -LiteralPath $FilePath) {
        $Item = Get-Item -LiteralPath $FilePath -Force
        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "SECURITY ABORT: '$FilePath' is a ReparsePoint. Refusing to write as SYSTEM."
        }
    }
}

function Write-SystemLog {
    param(
        [string]$Level,
        [string]$Message
    )
    $Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Line = "[$Timestamp] [SYSTEM:$Action] [$Level] $Message"
    try {
        Test-SafeTargetFile -FilePath $LogPath
        Add-Content -LiteralPath $LogPath -Value $Line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function Save-StateReport {
    param(
        [string]$ResultCode,
        [string]$TouchState,
        [string]$DeviceStatus,
        [int]$ErrorCode,
        [string]$InstanceId,
        [string]$Message,
        [int]$MatchedCount
    )
    $Payload = [ordered]@{
        Version       = $AppVersion
        Timestamp     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        TimestampUtc  = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        LastAction    = $Action
        ResultCode    = $ResultCode
        TouchState    = $TouchState
        DeviceStatus  = $DeviceStatus
        ErrorCode     = $ErrorCode
        InstanceId    = $InstanceId
        MatchedCount  = $MatchedCount
        Message       = $Message
        ComputerName  = $env:COMPUTERNAME
    }
    try {
        Test-SafeTargetFile -FilePath $StatusPath
        $Json = $Payload | ConvertTo-Json -Depth 4
        $TempPath = Join-Path $DataDir 'status.json.tmp'
        Test-SafeTargetFile -FilePath $TempPath
        Set-Content -LiteralPath $TempPath -Value $Json -Encoding UTF8 -Force
        Move-Item -LiteralPath $TempPath -Destination $StatusPath -Force
    } catch {
        Write-SystemLog -Level 'WARN' -Message "Could not write status.json: $($_.Exception.Message)"
    }
}

Write-SystemLog -Level 'INFO' -Message "Starting scheduled action '$Action' (v$AppVersion) on $env:COMPUTERNAME."

# Load optional Admin-pinned InstanceId from protected Program Files config.json
$PinnedInstanceId = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $Cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($Cfg.PinnedInstanceId -and $Cfg.PinnedInstanceId.Trim().Length -gt 0) {
            $PinnedInstanceId = $Cfg.PinnedInstanceId.Trim()
        }
    } catch {
        Write-SystemLog -Level 'WARN' -Message "Failed to parse config.json: $($_.Exception.Message)"
    }
}

# Unified Device Discovery Rule (Matches both English FriendlyName AND locale-independent HID Usage Page 0x000D Usage 0x0004)
function Get-MatchingTouchDevices {
    param([string]$PinnedId)

    $WmiDevices = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter "PNPClass = 'HIDClass'" -ErrorAction SilentlyContinue)
    $Matched = @()

    foreach ($dev in $WmiDevices) {
        # Win32_PnPEntity retrieved from live CIM enumerates currently present PnP nodes
        $IsTouchName = ($dev.Name -eq 'HID-compliant touch screen')
        $IsTouchUsage = $false
        if ($dev.HardwareID) {
            foreach ($id in $dev.HardwareID) {
                if ($id -imatch 'HID_DEVICE_UP:000D_U:0004') { $IsTouchUsage = $true; break }
            }
        }
        if (-not $IsTouchUsage -and $dev.CompatibleID) {
            foreach ($id in $dev.CompatibleID) {
                if ($id -imatch 'HID_DEVICE_UP:000D_U:0004') { $IsTouchUsage = $true; break }
            }
        }

        if ($IsTouchName -or $IsTouchUsage) {
            $Matched += $dev
        }
    }

    if ($PinnedId) {
        $PinnedMatches = @($Matched | Where-Object { $_.DeviceID -ieq $PinnedId })
        if ($PinnedMatches.Count -eq 1) {
            return $PinnedMatches
        } else {
            Write-SystemLog -Level 'WARN' -Message "Pinned InstanceId '$PinnedId' was not matched among active devices (Found $($Matched.Count) general matches). Evaluating general safeguard rules."
        }
    }
    return $Matched
}

$CandidateDevices = @(Get-MatchingTouchDevices -PinnedId $PinnedInstanceId)
$MatchCount = $CandidateDevices.Count

# SAFEGUARD 1: Zero matching touchscreen devices found
if ($MatchCount -eq 0) {
    $Msg = "No 'HID-compliant touch screen' (HID Usage 000D:0004) device was found in Device Manager (HIDClass). Verify that the touchscreen driver is installed and not hidden."
    Write-SystemLog -Level 'ERROR' -Message $Msg
    Save-StateReport -ResultCode 'ERR_NOT_FOUND' -TouchState 'UNKNOWN' -DeviceStatus 'NotFound' -ErrorCode -1 -InstanceId '' -Message $Msg -MatchedCount 0
    exit 10
}

# SAFEGUARD 2: Multiple matching touchscreen devices found -> STOP and request Administrator intervention
if ($MatchCount -gt 1) {
    $Ids = ($CandidateDevices | Select-Object -ExpandProperty DeviceID) -join '; '
    $Msg = "SAFEGUARD TRIGGERED: Multiple ($MatchCount) touchscreen devices were found ($Ids). Operation stopped to avoid disabling the wrong HID device. Administrator intervention is required."
    Write-SystemLog -Level 'ERROR' -Message $Msg
    Save-StateReport -ResultCode 'ERR_MULTIPLE_DEVICES' -TouchState 'UNKNOWN' -DeviceStatus 'MultipleFound' -ErrorCode -2 -InstanceId $Ids -Message $Msg -MatchedCount $MatchCount
    exit 20
}

# Exactly 1 verified touchscreen device found
$TargetDevice = $CandidateDevices[0]
$TargetId     = $TargetDevice.DeviceID
$InitErrCode  = [int]$TargetDevice.ConfigManagerErrorCode
Write-SystemLog -Level 'INFO' -Message "Verified single target touchscreen: Name='$($TargetDevice.Name)', InstanceId='$TargetId', Status='$($TargetDevice.Status)', ErrorCode=$InitErrCode."

Import-Module PnpDevice -ErrorAction Stop

try {
    if ($Action -eq 'Disable') {
        if ($InitErrCode -eq 22) {
            Write-SystemLog -Level 'INFO' -Message "Touchscreen '$TargetId' is already disabled (ConfigManagerErrorCode=22). Confirming MOUSE MODE."
        } elseif ($InitErrCode -ne 0) {
            $DriverMsg = "Touchscreen '$TargetId' has hardware/driver error code $InitErrCode (Status='$($TargetDevice.Status)'). Refusing to mask driver fault as Mouse Mode."
            Write-SystemLog -Level 'ERROR' -Message $DriverMsg
            Save-StateReport -ResultCode 'ERR_DRIVER_FAULT' -TouchState 'DRIVER_ERROR' -DeviceStatus $TargetDevice.Status -ErrorCode $InitErrCode -InstanceId $TargetId -Message $DriverMsg -MatchedCount 1
            exit 32
        } else {
            Disable-PnpDevice -InstanceId $TargetId -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 350
        }

        $Refreshed = @(Get-MatchingTouchDevices -PinnedId $TargetId)
        $NewErrCode = if ($Refreshed.Count -eq 1) { [int]$Refreshed[0].ConfigManagerErrorCode } else { -1 }
        $NewStatus  = if ($Refreshed.Count -eq 1) { [string]$Refreshed[0].Status } else { 'Unknown' }

        if ($NewErrCode -eq 22) {
            $SuccessMsg = "MOUSE MODE ACTIVE: Touchscreen ($TargetId) is disabled (Code 22). External mouse clicks in Roblox are now enabled."
            Write-SystemLog -Level 'SUCCESS' -Message $SuccessMsg
            Save-StateReport -ResultCode 'SUCCESS' -TouchState 'MOUSE_MODE' -DeviceStatus $NewStatus -ErrorCode 22 -InstanceId $TargetId -Message $SuccessMsg -MatchedCount 1
            exit 0
        } else {
            $FailMsg = "Disable-PnpDevice completed, but device ErrorCode is $NewErrCode (expected 22, Status='$NewStatus')."
            Write-SystemLog -Level 'ERROR' -Message $FailMsg
            Save-StateReport -ResultCode 'ERR_VERIFY_FAILED' -TouchState 'UNKNOWN' -DeviceStatus $NewStatus -ErrorCode $NewErrCode -InstanceId $TargetId -Message $FailMsg -MatchedCount 1
            exit 30
        }
    }
    elseif ($Action -eq 'Enable') {
        if ($InitErrCode -eq 0 -and $TargetDevice.Status -eq 'OK') {
            Write-SystemLog -Level 'INFO' -Message "Touchscreen '$TargetId' is already enabled (ErrorCode=0, Status='OK'). Confirming TOUCH ENABLED."
        } else {
            Enable-PnpDevice -InstanceId $TargetId -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 350
        }

        $Refreshed = @(Get-MatchingTouchDevices -PinnedId $TargetId)
        $NewErrCode = if ($Refreshed.Count -eq 1) { [int]$Refreshed[0].ConfigManagerErrorCode } else { -1 }
        $NewStatus  = if ($Refreshed.Count -eq 1) { [string]$Refreshed[0].Status } else { 'Unknown' }

        if ($NewErrCode -eq 0 -and $NewStatus -eq 'OK') {
            $SuccessMsg = "TOUCH RESTORED: Touchscreen ($TargetId) is enabled and working normally (Code 0)."
            Write-SystemLog -Level 'SUCCESS' -Message $SuccessMsg
            Save-StateReport -ResultCode 'SUCCESS' -TouchState 'TOUCH_ON' -DeviceStatus $NewStatus -ErrorCode 0 -InstanceId $TargetId -Message $SuccessMsg -MatchedCount 1
            exit 0
        } else {
            $FailMsg = "Enable-PnpDevice completed, but device ErrorCode is $NewErrCode (Status='$NewStatus')."
            Write-SystemLog -Level 'ERROR' -Message $FailMsg
            Save-StateReport -ResultCode 'ERR_VERIFY_FAILED' -TouchState 'DRIVER_ERROR' -DeviceStatus $NewStatus -ErrorCode $NewErrCode -InstanceId $TargetId -Message $FailMsg -MatchedCount 1
            exit 31
        }
    }
} catch {
    $ErrText = "Hardware toggle failed for '$TargetId': $($_.Exception.Message)"
    Write-SystemLog -Level 'ERROR' -Message $ErrText
    Save-StateReport -ResultCode 'ERR_EXCEPTION' -TouchState 'UNKNOWN' -DeviceStatus 'Exception' -ErrorCode -99 -InstanceId $TargetId -Message $ErrText -MatchedCount 1
    exit 40
}
