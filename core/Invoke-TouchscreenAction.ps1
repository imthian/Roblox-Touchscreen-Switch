<#
.SYNOPSIS
    Roblox Touchscreen Switch - Protected SYSTEM Worker Script
.DESCRIPTION
    Executes strictly under NT AUTHORITY\SYSTEM via Windows Scheduled Tasks:
      - \RobloxTouchscreenSwitch\DisableTouchscreen (Mouse Mode)
      - \RobloxTouchscreenSwitch\EnableTouchscreen  (Restore Touch)
      - \RobloxTouchscreenSwitch\RestoreTouchOnBoot (Safety Startup Recovery)

    SECURITY & HARDWARE SAFEGUARDS:
    1. Located in C:\Program Files\RobloxTouchscreenSwitch\ (Read/Execute only for Standard Users;
       Full Control restricted to SYSTEM and Administrators).
    2. Never accepts arbitrary device names or commands from standard users.
    3. Queries PnP devices strictly matching FriendlyName -eq 'HID-compliant touch screen'
       and Class -eq 'HIDClass', or locked to the pinned InstanceId in config.json.
    4. If 0 matching devices or >1 matching devices are detected (without an admin-pinned InstanceId),
       aborts immediately without touching any hardware and signals Administrator Intervention Required.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Disable', 'Enable')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$InstallDir = 'C:\Program Files\RobloxTouchscreenSwitch'
$ConfigPath = Join-Path $InstallDir 'config.json'
$DataDir    = 'C:\ProgramData\RobloxTouchscreenSwitch'
$StatusPath = Join-Path $DataDir 'status.json'
$LogPath    = Join-Path $DataDir 'activity.log'

if (-not (Test-Path -LiteralPath $DataDir)) {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
}

function Write-ActivityLog {
    param(
        [string]$Level,
        [string]$Message
    )
    $Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Line = "[$Timestamp] [SYSTEM:$Action] [$Level] $Message"
    try {
        Add-Content -LiteralPath $LogPath -Value $Line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Ignore logging lock collisions
    }
}

function Save-StateReport {
    param(
        [string]$ResultCode,
        [string]$TouchState,
        [string]$DeviceStatus,
        [string]$InstanceId,
        [string]$Message,
        [int]$MatchedCount
    )
    $Payload = [ordered]@{
        Timestamp     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        LastAction    = $Action
        ResultCode    = $ResultCode
        TouchState    = $TouchState
        DeviceStatus  = $DeviceStatus
        InstanceId    = $InstanceId
        MatchedCount  = $MatchedCount
        Message       = $Message
        ComputerName  = $env:COMPUTERNAME
    }
    try {
        $Json = $Payload | ConvertTo-Json -Depth 4
        Set-Content -LiteralPath $StatusPath -Value $Json -Encoding UTF8 -Force
    } catch {
        Write-ActivityLog -Level 'WARN' -Message "Could not write status.json: $($_.Exception.Message)"
    }
}

Write-ActivityLog -Level 'INFO' -Message "Starting scheduled action '$Action' on $env:COMPUTERNAME."

# Load optional Admin-pinned InstanceId from protected Program Files config.json
$PinnedInstanceId = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $Cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($Cfg.PinnedInstanceId -and $Cfg.PinnedInstanceId.Trim().Length -gt 0) {
            $PinnedInstanceId = $Cfg.PinnedInstanceId.Trim()
        }
    } catch {
        Write-ActivityLog -Level 'WARN' -Message "Failed to parse config.json: $($_.Exception.Message)"
    }
}

# Enumerate candidate touchscreen devices strictly in HIDClass
Import-Module PnpDevice -ErrorAction Stop

$AllTouchDevices = @(Get-PnpDevice -Class 'HIDClass' -ErrorAction SilentlyContinue | Where-Object {
    $_.FriendlyName -eq 'HID-compliant touch screen'
})

# Prefer currently present hardware nodes first; fallback to all registered nodes if disconnected
$PresentTouchDevices = @($AllTouchDevices | Where-Object { $_.Present -eq $true })
if ($PresentTouchDevices.Count -gt 0) {
    $CandidateDevices = $PresentTouchDevices
} else {
    $CandidateDevices = $AllTouchDevices
}

# Filter to PinnedInstanceId if configured by Administrator during installation
if ($PinnedInstanceId) {
    $PinnedMatches = @($CandidateDevices | Where-Object { $_.InstanceId -ieq $PinnedInstanceId })
    if ($PinnedMatches.Count -eq 1) {
        $CandidateDevices = $PinnedMatches
    } else {
        Write-ActivityLog -Level 'WARN' -Message "Pinned InstanceId '$PinnedInstanceId' was not matched among active devices (Found $($CandidateDevices.Count) general matches). Evaluating general safeguard rules."
    }
}

$MatchCount = $CandidateDevices.Count

# SAFEGUARD 1: Zero matching touchscreen devices found
if ($MatchCount -eq 0) {
    $Msg = "No 'HID-compliant touch screen' device was found in Device Manager (HIDClass). Verify that the touchscreen driver is installed and not hidden."
    Write-ActivityLog -Level 'ERROR' -Message $Msg
    Save-StateReport -ResultCode 'ERR_NOT_FOUND' -TouchState 'UNKNOWN' -DeviceStatus 'NotFound' -InstanceId '' -Message $Msg -MatchedCount 0
    exit 10
}

# SAFEGUARD 2: Multiple matching touchscreen devices found -> STOP and request Administrator intervention
if ($MatchCount -gt 1) {
    $Ids = ($CandidateDevices | Select-Object -ExpandProperty InstanceId) -join '; '
    $Msg = "SAFEGUARD TRIGGERED: Multiple ($MatchCount) 'HID-compliant touch screen' devices were found ($Ids). Operation stopped to avoid disabling the wrong HID device. Administrator intervention is required."
    Write-ActivityLog -Level 'ERROR' -Message $Msg
    Save-StateReport -ResultCode 'ERR_MULTIPLE_DEVICES' -TouchState 'UNKNOWN' -DeviceStatus 'MultipleFound' -InstanceId $Ids -Message $Msg -MatchedCount $MatchCount
    exit 20
}

# Exactly 1 verified touchscreen device found
$TargetDevice = $CandidateDevices[0]
$TargetId     = $TargetDevice.InstanceId
Write-ActivityLog -Level 'INFO' -Message "Verified single target touchscreen: FriendlyName='$($TargetDevice.FriendlyName)', InstanceId='$TargetId', CurrentStatus='$($TargetDevice.Status)'."

try {
    if ($Action -eq 'Disable') {
        if ($TargetDevice.Status -eq 'Error' -or $TargetDevice.ConfigManagerErrorCode -eq 22) {
            Write-ActivityLog -Level 'INFO' -Message "Touchscreen '$TargetId' is already disabled (Code 22). Confirming MOUSE MODE."
        } else {
            Disable-PnpDevice -InstanceId $TargetId -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 400
        }

        $Refreshed = Get-PnpDevice -InstanceId $TargetId -ErrorAction Stop
        $IsDisabled = ($Refreshed.ConfigManagerErrorCode -eq 22) -or ($Refreshed.Status -ne 'OK')
        if ($IsDisabled) {
            $SuccessMsg = "MOUSE MODE ACTIVE: 'HID-compliant touch screen' ($TargetId) is disabled. External mouse clicks in Roblox are now enabled."
            Write-ActivityLog -Level 'SUCCESS' -Message $SuccessMsg
            Save-StateReport -ResultCode 'SUCCESS' -TouchState 'MOUSE_MODE' -DeviceStatus $Refreshed.Status -InstanceId $TargetId -Message $SuccessMsg -MatchedCount 1
            exit 0
        } else {
            $FailMsg = "Disable-PnpDevice completed, but device status is still '$($Refreshed.Status)' (ErrorCode=$($Refreshed.ConfigManagerErrorCode))."
            Write-ActivityLog -Level 'ERROR' -Message $FailMsg
            Save-StateReport -ResultCode 'ERR_VERIFY_FAILED' -TouchState 'TOUCH_ON' -DeviceStatus $Refreshed.Status -InstanceId $TargetId -Message $FailMsg -MatchedCount 1
            exit 30
        }
    }
    elseif ($Action -eq 'Enable') {
        if ($TargetDevice.Status -eq 'OK' -and $TargetDevice.ConfigManagerErrorCode -eq 0) {
            Write-ActivityLog -Level 'INFO' -Message "Touchscreen '$TargetId' is already enabled (Status OK). Confirming TOUCH ENABLED."
        } else {
            Enable-PnpDevice -InstanceId $TargetId -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 400
        }

        $Refreshed = Get-PnpDevice -InstanceId $TargetId -ErrorAction Stop
        if ($Refreshed.Status -eq 'OK' -and $Refreshed.ConfigManagerErrorCode -eq 0) {
            $SuccessMsg = "TOUCH RESTORED: 'HID-compliant touch screen' ($TargetId) is enabled and working normally."
            Write-ActivityLog -Level 'SUCCESS' -Message $SuccessMsg
            Save-StateReport -ResultCode 'SUCCESS' -TouchState 'TOUCH_ON' -DeviceStatus $Refreshed.Status -InstanceId $TargetId -Message $SuccessMsg -MatchedCount 1
            exit 0
        } else {
            $FailMsg = "Enable-PnpDevice completed, but device status is '$($Refreshed.Status)' (ErrorCode=$($Refreshed.ConfigManagerErrorCode))."
            Write-ActivityLog -Level 'ERROR' -Message $FailMsg
            Save-StateReport -ResultCode 'ERR_VERIFY_FAILED' -TouchState 'MOUSE_MODE' -DeviceStatus $Refreshed.Status -InstanceId $TargetId -Message $FailMsg -MatchedCount 1
            exit 31
        }
    }
} catch {
    $ErrText = "Hardware toggle failed for '$TargetId': $($_.Exception.Message)"
    Write-ActivityLog -Level 'ERROR' -Message $ErrText
    Save-StateReport -ResultCode 'ERR_EXCEPTION' -TouchState 'UNKNOWN' -DeviceStatus 'Exception' -InstanceId $TargetId -Message $ErrText -MatchedCount 1
    exit 40
}
