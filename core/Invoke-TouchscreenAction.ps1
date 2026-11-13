<#
.SYNOPSIS
    Roblox Touchscreen Switch - Protected SYSTEM Worker Script (v1.2.3)
.DESCRIPTION
    Executes strictly under NT AUTHORITY\SYSTEM via Windows Scheduled Tasks:
      - \RobloxTouchscreenSwitch\DisableTouchscreen (Mouse Mode)
      - \RobloxTouchscreenSwitch\EnableTouchscreen  (Restore Touch)
      - \RobloxTouchscreenSwitch\RestoreTouchOnBoot (Safety Startup Recovery)

    SECURITY & RELIABILITY ARCHITECTURE (v1.2.3):
    1. Dynamic Environment Paths: Uses $env:ProgramFiles and $env:ProgramData.
    2. Atomic Directory Creation & Strict SID Allowlist Verification:
       - If $env:ProgramData\RobloxTouchscreenSwitch is missing, confirms non-existence, creates it atomically
         via [System.IO.Directory]::CreateDirectory($DataDir, $DataAcl), applies Set-Acl, and verifies it is empty.
       - Verifies the folder is NOT a ReparsePoint, is owned by SYSTEM (S-1-5-18) or Administrators (S-1-5-32-544),
         and enforces a strict SID Allowlist using GetAccessRules($true, $true, [SecurityIdentifier]) directly.
       - $WriteRightsMask is restricted strictly to write/modify/delete/takeownership bits (0xD0156), so legitimate
         ReadAndExecute rules (0x1200A9) pass cleanly (0x1200A9 -band 0xD0156 = 0).
    3. Strict $script:DataDirTrusted Gate: Refuses to write a single byte if DataDir fails verification.
    4. Two-Pass All-or-Nothing Pre-Check on Disable: Checks all target nodes for driver faults before
       disabling any node so a faulted node never leaves sibling nodes partially disabled.
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
$AppVersion  = if (Test-Path -LiteralPath $VersionFile) { (Get-Content -LiteralPath $VersionFile -Raw).Trim() } else { '1.2.3' }
$ConfigPath  = Join-Path $InstallDir 'config.json'
$DataDir     = Join-Path $env:ProgramData 'RobloxTouchscreenSwitch'
$StatusPath  = Join-Path $DataDir 'status.json'
$LogPath     = Join-Path $DataDir 'system-activity.log'
$OldLogPath  = Join-Path $DataDir 'system-activity.old.log'

$SidSystem = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
$SidAdmins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$SidUsers  = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Strict Write-Only Rights Mask (0xD0156):
# WriteData (0x2), AppendData (0x4), WriteExtendedAttributes (0x10), WriteAttributes (0x100),
# DeleteSubdirectoriesAndFiles (0x40), Delete (0x10000), ChangePermissions (0x40000), TakeOwnership (0x80000).
# Excludes Read-related bits so Users: ReadAndExecute (0x1200A9) passes cleanly (0x1200A9 -band 0xD0156 = 0).
$R = [System.Security.AccessControl.FileSystemRights]
$WriteRightsMask = [int]($R::WriteData -bor $R::AppendData -bor $R::WriteExtendedAttributes -bor `
                         $R::WriteAttributes -bor $R::DeleteSubdirectoriesAndFiles -bor `
                         $R::Delete -bor $R::ChangePermissions -bor $R::TakeOwnership)

$script:DataDirTrusted = $false

function Initialize-LockedDataDir {
    if (-not (Test-Path -LiteralPath $DataDir)) {
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

        if (Test-Path -LiteralPath $DataDir) {
            throw "SECURITY ABORT: '$DataDir' already existed before atomic creation. Re-run Install-RobloxTouchSwitch.bat as Administrator."
        }

        [System.IO.Directory]::CreateDirectory($DataDir, $DataAcl) | Out-Null
        Set-Acl -LiteralPath $DataDir -AclObject $DataAcl

        $PreExistingItems = @(Get-ChildItem -LiteralPath $DataDir -Force -ErrorAction SilentlyContinue)
        if ($PreExistingItems.Count -gt 0) {
            throw "SECURITY ABORT: Newly created '$DataDir' was not empty. Re-run Install-RobloxTouchSwitch.bat as Administrator."
        }
    }

    $Item = Get-Item -LiteralPath $DataDir -Force
    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "SECURITY ABORT: '$DataDir' is a ReparsePoint (symlink/junction). Re-run Install-RobloxTouchSwitch.bat as Administrator."
    }

    $CurrentAcl = Get-Acl -LiteralPath $DataDir
    $OwnerSid = $CurrentAcl.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($OwnerSid -ne $SidSystem -and $OwnerSid -ne $SidAdmins) {
        throw "SECURITY ABORT: '$DataDir' is owned by untrusted SID '$($OwnerSid.Value)'. Re-run Install-RobloxTouchSwitch.bat as Administrator."
    }

    # Strict Allowlist Check: Uses direct SID enumeration to avoid translation exceptions on deleted accounts
    $AccessRules = $CurrentAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    foreach ($rule in $AccessRules) {
        if ($rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
            $HasWrite = ([int]$rule.FileSystemRights -band $WriteRightsMask) -ne 0
            if ($HasWrite) {
                $RuleSid = [System.Security.Principal.SecurityIdentifier]$rule.IdentityReference
                if ($RuleSid -ne $SidSystem -and $RuleSid -ne $SidAdmins) {
                    throw "SECURITY ABORT: '$DataDir' grants write/modify rights to untrusted SID '$($RuleSid.Value)'. Re-run Install-RobloxTouchSwitch.bat as Administrator."
                }
            }
        }
    }

    $script:DataDirTrusted = $true
}

function Test-SafeTargetFile {
    param([string]$FilePath)
    if (-not $script:DataDirTrusted) {
        throw "SECURITY ABORT: DataDir is not verified trusted."
    }
    if (Test-Path -LiteralPath $FilePath) {
        $Item = Get-Item -LiteralPath $FilePath -Force
        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "SECURITY ABORT: '$FilePath' is a ReparsePoint."
        }
        $FileAcl = Get-Acl -LiteralPath $FilePath
        $FileOwner = $FileAcl.GetOwner([System.Security.Principal.SecurityIdentifier])
        if ($FileOwner -ne $SidSystem -and $FileOwner -ne $SidAdmins) {
            throw "SECURITY ABORT: '$FilePath' is owned by untrusted SID '$($FileOwner.Value)'."
        }
        $FileRules = $FileAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
        foreach ($rule in $FileRules) {
            if ($rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
                $HasWrite = ([int]$rule.FileSystemRights -band $WriteRightsMask) -ne 0
                if ($HasWrite) {
                    $RuleSid = [System.Security.Principal.SecurityIdentifier]$rule.IdentityReference
                    if ($RuleSid -ne $SidSystem -and $RuleSid -ne $SidAdmins) {
                        throw "SECURITY ABORT: '$FilePath' grants write rights to untrusted SID '$($RuleSid.Value)'."
                    }
                }
            }
        }
        $FsUtil = Join-Path $env:SystemRoot 'System32\fsutil.exe'
        if (Test-Path -LiteralPath $FsUtil) {
            $Links = & $FsUtil hardlink list "$FilePath" 2>$null
            if ($Links -and @($Links).Count -gt 1) {
                throw "SECURITY ABORT: '$FilePath' has multiple NTFS hardlinks."
            }
        }
    }
}

function Write-SystemLog {
    param(
        [string]$Level,
        [string]$Message
    )
    if (-not $script:DataDirTrusted) { return }
    $Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Line = "[$Timestamp] [SYSTEM:$Action] [$Level] $Message`r`n"
    try {
        Test-SafeTargetFile -FilePath $LogPath
        if (Test-Path -LiteralPath $LogPath) {
            $Len = (Get-Item -LiteralPath $LogPath -Force).Length
            if ($Len -gt 524288) {
                Test-SafeTargetFile -FilePath $OldLogPath
                Move-Item -LiteralPath $LogPath -Destination $OldLogPath -Force
            }
        }
        [System.IO.File]::AppendAllText($LogPath, $Line, $Utf8NoBom)
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
    if (-not $script:DataDirTrusted) { return }
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
        [System.IO.File]::WriteAllText($TempPath, $Json, $Utf8NoBom)
        Move-Item -LiteralPath $TempPath -Destination $StatusPath -Force
    } catch {
        Write-SystemLog -Level 'WARN' -Message "Could not write status.json: $($_.Exception.Message)"
    }
}

try {
    Initialize-LockedDataDir
    Write-SystemLog -Level 'INFO' -Message "Starting scheduled action '$Action' (v$AppVersion) on $env:COMPUTERNAME."

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
        $PreFaults = @()
        $FirstFaultCode = 32
        $FirstFaultStatus = 'DriverError'

        foreach ($dev in $TargetDevices) {
            $ErrCode = [int]$dev.ConfigManagerErrorCode
            if ($ErrCode -ne 0 -and $ErrCode -ne 22) {
                $PreFaults += "$($dev.DeviceID) (Code $ErrCode, Status='$($dev.Status)')"
                if ($FirstFaultCode -eq 32) {
                    $FirstFaultCode = $ErrCode
                    $FirstFaultStatus = [string]$dev.Status
                }
            }
        }

        if ($PreFaults.Count -gt 0) {
            $DriverMsg = "Touchscreen node(s) reported hardware/driver error before disable: $($PreFaults -join '; '). Aborting without disabling healthy nodes."
            Write-SystemLog -Level 'ERROR' -Message $DriverMsg
            Save-StateReport -ResultCode 'ERR_DRIVER_FAULT' -TouchState 'DRIVER_ERROR' -DeviceStatus $FirstFaultStatus -ErrorCode $FirstFaultCode -InstanceId $IdsSummary -Message $DriverMsg -MatchedCount $TargetDevices.Count
            exit 32
        }

        $ToggleErrors = @()
        foreach ($dev in $TargetDevices) {
            $ErrCode = [int]$dev.ConfigManagerErrorCode
            if ($ErrCode -eq 22) {
                Write-SystemLog -Level 'INFO' -Message "Touchscreen '$($dev.DeviceID)' is already disabled (Code 22)."
            } else {
                try {
                    Disable-PnpDevice -InstanceId $dev.DeviceID -Confirm:$false -ErrorAction Stop
                } catch {
                    $ToggleErrors += "$($dev.DeviceID): $($_.Exception.Message)"
                }
            }
        }

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
            $ExtraErr = if ($ToggleErrors.Count -gt 0) { " Errors: $($ToggleErrors -join '; ')" } else { "" }
            $FailMsg = "Disable-PnpDevice finished, but device ErrorCode is $LastCode after 2.5s polling (expected 22, Status='$LastStatus').$ExtraErr"
            Write-SystemLog -Level 'ERROR' -Message $FailMsg
            Save-StateReport -ResultCode 'ERR_VERIFY_FAILED' -TouchState 'UNKNOWN' -DeviceStatus $LastStatus -ErrorCode $LastCode -InstanceId $IdsSummary -Message $FailMsg -MatchedCount $TargetDevices.Count
            exit 30
        }
    }
    elseif ($Action -eq 'Enable') {
        $ToggleErrors = @()
        foreach ($dev in $TargetDevices) {
            $ErrCode = [int]$dev.ConfigManagerErrorCode
            if ($ErrCode -eq 0 -and $dev.Status -eq 'OK') {
                Write-SystemLog -Level 'INFO' -Message "Touchscreen '$($dev.DeviceID)' is already enabled (Code 0, Status='OK')."
            } else {
                try {
                    Enable-PnpDevice -InstanceId $dev.DeviceID -Confirm:$false -ErrorAction Stop
                } catch {
                    $ToggleErrors += "$($dev.DeviceID): $($_.Exception.Message)"
                    Write-SystemLog -Level 'WARN' -Message "Enable-PnpDevice error on '$($dev.DeviceID)': $($_.Exception.Message)"
                }
            }
        }

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
            $ExtraErr = if ($ToggleErrors.Count -gt 0) { " Errors: $($ToggleErrors -join '; ')" } else { "" }
            $FailMsg = "Enable-PnpDevice finished, but device ErrorCode is $LastCode after 2.5s polling (Status='$LastStatus').$ExtraErr"
            Write-SystemLog -Level 'ERROR' -Message $FailMsg
            Save-StateReport -ResultCode 'ERR_VERIFY_FAILED' -TouchState 'DRIVER_ERROR' -DeviceStatus $LastStatus -ErrorCode $LastCode -InstanceId $IdsSummary -Message $FailMsg -MatchedCount $TargetDevices.Count
            exit 31
        }
    }
} catch {
    $FatalText = "Unhandled SYSTEM worker error: $($_.Exception.Message)"
    if ($script:DataDirTrusted) {
        Write-SystemLog -Level 'ERROR' -Message $FatalText
        Save-StateReport -ResultCode 'ERR_FATAL_WORKER' -TouchState 'UNKNOWN' -DeviceStatus 'Exception' -ErrorCode -99 -InstanceId '' -Message $FatalText -MatchedCount 0
        exit 40
    } else {
        exit 45
    }
}
