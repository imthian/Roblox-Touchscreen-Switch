<#
.SYNOPSIS
    Roblox Touchscreen Switch - Protected SYSTEM Worker Script
.DESCRIPTION
    Executes strictly under NT AUTHORITY\SYSTEM via Windows Scheduled Tasks:
      - \RobloxTouchscreenSwitch\DisableTouchscreen (Mouse Mode)
      - \RobloxTouchscreenSwitch\EnableTouchscreen  (Restore Touch)
      - \RobloxTouchscreenSwitch\RestoreTouchOnBoot (Safety Startup Recovery)

    SECURITY & RELIABILITY ARCHITECTURE (v1.2.0):
    1. Dynamic Environment Paths: Uses $env:ProgramFiles and $env:ProgramData (never hardcoded C:\).
    2. Pre-Creation Takeover & Hardlink Defense:
       - If DataDir ($env:ProgramData\RobloxTouchscreenSwitch) is missing or has an untrusted owner
         (anything other than SYSTEM S-1-5-18 or Administrators S-1-5-32-544) or is a ReparsePoint,
         rebuilds and locks it with SetOwner(Administrators) + SYSTEM/Admin FullControl and Users Read-Only.
       - Checks both ReparsePoint AND NTFS Hardlink link-count (via fsutil hardlink list) before writing.
    3. Log Rotation: Caps system-activity.log at 512 KB (rotates to system-activity.old.log).
    4. Strict Pinned-Device Array Enforcement (No Fallback Guessing):
       - Supports PinnedInstanceIds (array of 1 or more composite touch nodes).
       - If PinnedInstanceIds is configured by the Administrator and ANY pinned device is missing,
         immediately stops with ERR_PINNED_MISSING (exit 15) instead of falling back to general matching.
    5. 2.5-Second State Transition Polling: Polls up to 10 times (250 ms intervals) after Disable/Enable-PnpDevice.
    6. Top-Level Exception Wrapper: Guarantees status.json is written on every failure path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Disable', 'Enable')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$InstallDir  = Join-Path $env:ProgramFiles 'RobloxTouchscreenSwitch'
$VersionFile = Join-Path $InstallDir 'VERSION'
$AppVersion  = if (Test-Path -LiteralPath $VersionFile) { (Get-Content -LiteralPath $VersionFile -Raw).Trim() } else { '1.2.0' }
$ConfigPath  = Join-Path $InstallDir 'config.json'
$DataDir     = Join-Path $env:ProgramData 'RobloxTouchscreenSwitch'
$StatusPath  = Join-Path $DataDir 'status.json'
$LogPath     = Join-Path $DataDir 'system-activity.log'
$OldLogPath  = Join-Path $DataDir 'system-activity.old.log'

$SidSystem = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
$SidAdmins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$SidUsers  = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')

function Initialize-LockedDataDir {
    $NeedsRebuild = $false
    if (-not (Test-Path -LiteralPath $DataDir)) {
        $NeedsRebuild = $true
    } else {
        $Item = Get-Item -LiteralPath $DataDir -Force
        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "SECURITY ABORT: '$DataDir' is a ReparsePoint (symlink/junction)."
        }
        $CurrentAcl = Get-Acl -LiteralPath $DataDir
        $OwnerSid = $CurrentAcl.GetOwner([System.Security.Principal.SecurityIdentifier])
        if ($OwnerSid -ne $SidSystem -and $OwnerSid -ne $SidAdmins) {
            $NeedsRebuild = $true
        }
    }

    if ($NeedsRebuild) {
        if (Test-Path -LiteralPath $DataDir) {
            Remove-Item -LiteralPath $DataDir -Recurse -Force
        }
        New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
        $InheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $PropFlags    = [System.Security.AccessControl.PropagationFlags]::None
        $RuleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule($SidSystem, [System.Security.AccessControl.FileSystemRights]::FullControl, $InheritFlags, $PropFlags, [System.Security.AccessControl.AccessControlType]::Allow)
        $RuleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule($SidAdmins, [System.Security.AccessControl.FileSystemRights]::FullControl, $InheritFlags, $PropFlags, [System.Security.AccessControl.AccessControlType]::Allow)
        $RuleUsers  = New-Object System.Security.AccessControl.FileSystemAccessRule($SidUsers,  [System.Security.AccessControl.FileSystemRights]::ReadAndExecute, $InheritFlags, $PropFlags, [System.Security.AccessControl.AccessControlType]::Allow)

        $DataAcl = New-Object System.Security.AccessControl.DirectorySecurity
        $DataAcl.SetOwner($SidAdmins)
        $DataAcl.SetAccessRuleProtection($true, $false)
        $DataAcl.AddAccessRule($RuleSystem)
        $DataAcl.AddAccessRule($RuleAdmins)
        $DataAcl.AddAccessRule($RuleUsers)
        Set-Acl -LiteralPath $DataDir -AclObject $DataAcl
    }
}

function Test-SafeTargetFile {
    param([string]$FilePath)
    if (Test-Path -LiteralPath $FilePath) {
        $Item = Get-Item -LiteralPath $FilePath -Force
        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "SECURITY ABORT: '$FilePath' is a ReparsePoint."
        }
        $FileAcl = Get-Acl -LiteralPath $FilePath
        $FileOwner = $FileAcl.GetOwner([System.Security.Principal.SecurityIdentifier])
        if ($FileOwner -ne $SidSystem -and $FileOwner -ne $SidAdmins) {
            Remove-Item -LiteralPath $FilePath -Force
            return
        }
        $FsUtil = Join-Path $env:SystemRoot 'System32\fsutil.exe'
        if (Test-Path -LiteralPath $FsUtil) {
            $Links = & $FsUtil hardlink list "$FilePath" 2>$null
            if ($Links -and @($Links).Count -gt 1) {
                Remove-Item -LiteralPath $FilePath -Force
                throw "SECURITY ABORT: '$FilePath' had multiple NTFS hardlinks and was removed."
            }
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
        if (Test-Path -LiteralPath $LogPath) {
            $Len = (Get-Item -LiteralPath $LogPath -Force).Length
            if ($Len -gt 524288) {
                Test-SafeTargetFile -FilePath $OldLogPath
                Move-Item -LiteralPath $LogPath -Destination $OldLogPath -Force
            }
        }
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

# Top-level try/catch guarantees that EVERY failure path writes a status report to status.json
try {
    Initialize-LockedDataDir
    Write-SystemLog -Level 'INFO' -Message "Starting scheduled action '$Action' (v$AppVersion) on $env:COMPUTERNAME."

    # Read optional Admin-pinned InstanceId(s) from protected Program Files config.json
    $PinnedIds = @()
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $Cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($Cfg.PinnedInstanceIds) {
                foreach ($id in $Cfg.PinnedInstanceIds) {
                    if ($id -and $id.ToString().Trim().Length -gt 0) {
                        $PinnedIds += $id.ToString().Trim()
                    }
                }
            }
            elseif ($Cfg.PinnedInstanceId -and $Cfg.PinnedInstanceId.ToString().Trim().Length -gt 0) {
                $PinnedIds += $Cfg.PinnedInstanceId.ToString().Trim()
            }
        } catch {
            Write-SystemLog -Level 'WARN' -Message "Failed to parse config.json: $($_.Exception.Message)"
        }
    }

    # Query WMI/CIM for HIDClass devices (with explicit error handling instead of SilentlyContinue)
    $WmiDevices = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter "PNPClass = 'HIDClass'" -ErrorAction Stop)
    $AllTouchMatched = @()
    foreach ($dev in $WmiDevices) {
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
            $AllTouchMatched += $dev
        }
    }

    # Strict Pinned-Device Enforcement: NEVER fall back to guessing if a pinned device is missing
    if ($PinnedIds.Count -gt 0) {
        $TargetDevices = @()
        $MissingPins = @()
        foreach ($pin in $PinnedIds) {
            $found = @($AllTouchMatched | Where-Object { $_.DeviceID -ieq $pin })
            if ($found.Count -eq 1) {
                $TargetDevices += $found[0]
            } else {
                $MissingPins += $pin
            }
        }
        if ($MissingPins.Count -gt 0) {
            $MissStr = $MissingPins -join '; '
            $Msg = "PINNED DEVICE MISSING: Administrator pinned touchscreen InstanceId(s) '$MissStr', but it is not currently connected. Refusing to guess or toggle other touch devices."
            Write-SystemLog -Level 'ERROR' -Message $Msg
            Save-StateReport -ResultCode 'ERR_PINNED_MISSING' -TouchState 'UNKNOWN' -DeviceStatus 'PinnedMissing' -ErrorCode -3 -InstanceId $MissStr -Message $Msg -MatchedCount 0
            exit 15
        }
    } else {
        # Unpinned mode: require exactly 1 matching touchscreen device
        if ($AllTouchMatched.Count -eq 0) {
            $Msg = "No 'HID-compliant touch screen' (HID Usage 000D:0004) device was found in Device Manager (HIDClass). Verify that the touchscreen driver is installed and not hidden."
            Write-SystemLog -Level 'ERROR' -Message $Msg
            Save-StateReport -ResultCode 'ERR_NOT_FOUND' -TouchState 'UNKNOWN' -DeviceStatus 'NotFound' -ErrorCode -1 -InstanceId '' -Message $Msg -MatchedCount 0
            exit 10
        }
        if ($AllTouchMatched.Count -gt 1) {
            $Ids = ($AllTouchMatched | Select-Object -ExpandProperty DeviceID) -join '; '
            $Msg = "SAFEGUARD TRIGGERED: Multiple ($($AllTouchMatched.Count)) touchscreen devices were found ($Ids). Operation stopped. Re-run Install-RobloxTouchSwitch.bat as Administrator to pin the desired touchscreen node(s)."
            Write-SystemLog -Level 'ERROR' -Message $Msg
            Save-StateReport -ResultCode 'ERR_MULTIPLE_DEVICES' -TouchState 'UNKNOWN' -DeviceStatus 'MultipleFound' -ErrorCode -2 -InstanceId $Ids -Message $Msg -MatchedCount $AllTouchMatched.Count
            exit 20
        }
        $TargetDevices = $AllTouchMatched
    }

    Import-Module PnpDevice -ErrorAction Stop
    $IdsSummary = ($TargetDevices | Select-Object -ExpandProperty DeviceID) -join '; '

    if ($Action -eq 'Disable') {
        foreach ($dev in $TargetDevices) {
            $ErrCode = [int]$dev.ConfigManagerErrorCode
            if ($ErrCode -eq 22) {
                Write-SystemLog -Level 'INFO' -Message "Touchscreen '$($dev.DeviceID)' is already disabled (Code 22)."
            } elseif ($ErrCode -ne 0) {
                $DriverMsg = "Touchscreen '$($dev.DeviceID)' has hardware/driver error code $ErrCode (Status='$($dev.Status)'). Refusing to mask driver fault as Mouse Mode."
                Write-SystemLog -Level 'ERROR' -Message $DriverMsg
                Save-StateReport -ResultCode 'ERR_DRIVER_FAULT' -TouchState 'DRIVER_ERROR' -DeviceStatus $dev.Status -ErrorCode $ErrCode -InstanceId $dev.DeviceID -Message $DriverMsg -MatchedCount $TargetDevices.Count
                exit 32
            } else {
                Disable-PnpDevice -InstanceId $dev.DeviceID -Confirm:$false -ErrorAction Stop
            }
        }

        # Poll up to 2.5 seconds (10 x 250ms) for all target nodes to report ErrorCode == 22
        $AllDisabled = $false
        $LastStatus = 'Unknown'
        $LastCode = -1
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 250
            $CheckWmi = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter "PNPClass = 'HIDClass'" -ErrorAction SilentlyContinue)
            $DisabledCount = 0
            foreach ($dev in $TargetDevices) {
                $m = @($CheckWmi | Where-Object { $_.DeviceID -ieq $dev.DeviceID })
                if ($m.Count -eq 1) {
                    $LastCode = [int]$m[0].ConfigManagerErrorCode
                    $LastStatus = [string]$m[0].Status
                    if ($LastCode -eq 22) { $DisabledCount++ }
                }
            }
            if ($DisabledCount -eq $TargetDevices.Count) {
                $AllDisabled = $true
                break
            }
        }

        if ($AllDisabled) {
            $SuccessMsg = "MOUSE MODE ACTIVE: Touchscreen ($IdsSummary) is disabled (Code 22). External mouse clicks in Roblox are now enabled."
            Write-SystemLog -Level 'SUCCESS' -Message $SuccessMsg
            Save-StateReport -ResultCode 'SUCCESS' -TouchState 'MOUSE_MODE' -DeviceStatus $LastStatus -ErrorCode 22 -InstanceId $IdsSummary -Message $SuccessMsg -MatchedCount $TargetDevices.Count
            exit 0
        } else {
            $FailMsg = "Disable-PnpDevice completed, but device ErrorCode is $LastCode after 2.5s polling (expected 22, Status='$LastStatus')."
            Write-SystemLog -Level 'ERROR' -Message $FailMsg
            Save-StateReport -ResultCode 'ERR_VERIFY_FAILED' -TouchState 'UNKNOWN' -DeviceStatus $LastStatus -ErrorCode $LastCode -InstanceId $IdsSummary -Message $FailMsg -MatchedCount $TargetDevices.Count
            exit 30
        }
    }
    elseif ($Action -eq 'Enable') {
        foreach ($dev in $TargetDevices) {
            $ErrCode = [int]$dev.ConfigManagerErrorCode
            if ($ErrCode -eq 0 -and $dev.Status -eq 'OK') {
                Write-SystemLog -Level 'INFO' -Message "Touchscreen '$($dev.DeviceID)' is already enabled (Code 0, Status='OK')."
            } else {
                Enable-PnpDevice -InstanceId $dev.DeviceID -Confirm:$false -ErrorAction Stop
            }
        }

        # Poll up to 2.5 seconds (10 x 250ms) for all target nodes to report ErrorCode == 0 and Status == 'OK'
        $AllEnabled = $false
        $LastStatus = 'Unknown'
        $LastCode = -1
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 250
            $CheckWmi = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter "PNPClass = 'HIDClass'" -ErrorAction SilentlyContinue)
            $EnabledCount = 0
            foreach ($dev in $TargetDevices) {
                $m = @($CheckWmi | Where-Object { $_.DeviceID -ieq $dev.DeviceID })
                if ($m.Count -eq 1) {
                    $LastCode = [int]$m[0].ConfigManagerErrorCode
                    $LastStatus = [string]$m[0].Status
                    if ($LastCode -eq 0 -and $LastStatus -eq 'OK') { $EnabledCount++ }
                }
            }
            if ($EnabledCount -eq $TargetDevices.Count) {
                $AllEnabled = $true
                break
            }
        }

        if ($AllEnabled) {
            $SuccessMsg = "TOUCH RESTORED: Touchscreen ($IdsSummary) is enabled and working normally (Code 0)."
            Write-SystemLog -Level 'SUCCESS' -Message $SuccessMsg
            Save-StateReport -ResultCode 'SUCCESS' -TouchState 'TOUCH_ON' -DeviceStatus $LastStatus -ErrorCode 0 -InstanceId $IdsSummary -Message $SuccessMsg -MatchedCount $TargetDevices.Count
            exit 0
        } else {
            $FailMsg = "Enable-PnpDevice completed, but device ErrorCode is $LastCode after 2.5s polling (Status='$LastStatus')."
            Write-SystemLog -Level 'ERROR' -Message $FailMsg
            Save-StateReport -ResultCode 'ERR_VERIFY_FAILED' -TouchState 'DRIVER_ERROR' -DeviceStatus $LastStatus -ErrorCode $LastCode -InstanceId $IdsSummary -Message $FailMsg -MatchedCount $TargetDevices.Count
            exit 31
        }
    }
} catch {
    $FatalText = "Unhandled SYSTEM worker error: $($_.Exception.Message)"
    Write-SystemLog -Level 'ERROR' -Message $FatalText
    Save-StateReport -ResultCode 'ERR_FATAL_WORKER' -TouchState 'UNKNOWN' -DeviceStatus 'Exception' -ErrorCode -99 -InstanceId '' -Message $FatalText -MatchedCount 0
    exit 40
}
