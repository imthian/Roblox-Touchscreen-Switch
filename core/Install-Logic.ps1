<#
.SYNOPSIS
    Administrator Installer for Roblox Touchscreen Switch v1.1.0 (Windows 11)
.DESCRIPTION
    1. Verifies Administrator privileges.
    2. Inspects touchscreen devices using locale-independent HID Usage (000D:0004) + FriendlyName and enforces single-device safeguard (or allows Admin pinning).
    3. Creates C:\Program Files\RobloxTouchscreenSwitch and locks NTFS ACLs (SYSTEM + Administrators FullControl; Users ReadAndExecute only).
    4. Creates C:\ProgramData\RobloxTouchscreenSwitch and locks NTFS ACLs (SYSTEM + Administrators FullControl; Users ReadAndExecute ONLY — preventing symlink redirection or log tampering).
    5. Compiles RobloxTouchSwitch.exe natively via Windows .NET Framework csc.exe.
    6. Registers three SYSTEM Scheduled Tasks in \RobloxTouchscreenSwitch\ using the full path to powershell.exe:
       - DisableTouchscreen (Triggerable by Authenticated Users via SDDL '(A;;GRGX;;;AU)')
       - EnableTouchscreen  (Triggerable by Authenticated Users via SDDL '(A;;GRGX;;;AU)')
       - RestoreTouchOnBoot (Automatic startup fail-safe so rebooting always restores touch)
    7. Creates All-Users Desktop and Start Menu shortcuts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$AppVersion = '1.1.0'

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  ROBLOX TOUCHSCREEN SWITCH v$AppVersion - WINDOWS 11 ADMIN INSTALLER" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verify Administrator Elevation
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Administrator privileges are required to install Roblox Touchscreen Switch." -ForegroundColor Red
    Write-Host "Please right-click 'Install-RobloxTouchSwitch.bat' and select 'Run as administrator'." -ForegroundColor Yellow
    exit 1
}

$ScriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PackageRoot = Split-Path -Parent $ScriptRoot
$InstallDir  = 'C:\Program Files\RobloxTouchscreenSwitch'
$DataDir     = 'C:\ProgramData\RobloxTouchscreenSwitch'
$LogPath     = Join-Path $DataDir 'system-activity.log'

# 2. Pre-Flight Hardware Inspection & Safeguard Check (Locale-Independent HID Usage 000D:0004 + FriendlyName)
Write-Host "[1/6] Inspecting Windows 11 HID Touchscreen Hardware..." -ForegroundColor Yellow

$WmiDevices = @(Get-CimInstance -Namespace 'root\CIMV2' -ClassName 'Win32_PnPEntity' -Filter "PNPClass = 'HIDClass'" -ErrorAction SilentlyContinue)
$ActiveCandidates = @()
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
        $ActiveCandidates += $dev
    }
}

$PinnedInstanceId = ""
if ($ActiveCandidates.Count -eq 0) {
    Write-Host "  [WARNING] No touchscreen device (HID Usage 000D:0004) was currently detected." -ForegroundColor Yellow
    Write-Host "  Installation will proceed so the utility is ready, but please verify Device Manager." -ForegroundColor Yellow
}
elseif ($ActiveCandidates.Count -eq 1) {
    $Dev = $ActiveCandidates[0]
    Write-Host "  [OK] Verified single touchscreen device:" -ForegroundColor Green
    Write-Host "       Name       : $($Dev.Name)"
    Write-Host "       InstanceId : $($Dev.DeviceID)"
    Write-Host "       Status     : $($Dev.Status) (ErrorCode=$($Dev.ConfigManagerErrorCode))"
}
else {
    Write-Host "  [SAFEGUARD ALERT] Multiple ($($ActiveCandidates.Count)) touchscreen nodes detected:" -ForegroundColor Red
    for ($i = 0; $i -lt $ActiveCandidates.Count; $i++) {
        $d = $ActiveCandidates[$i]
        Write-Host "    [$($i+1)] InstanceId: $($d.DeviceID) | Name: $($d.Name) | Status: $($d.Status) (Code $($d.ConfigManagerErrorCode))" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  As Administrator, you may pin the exact InstanceId now, or press Enter to leave unpinned" -ForegroundColor Yellow
    Write-Host "  (if left unpinned while >1 devices exist, the utility will safely block execution)." -ForegroundColor Yellow
    $Choice = Read-Host "  Enter device number [1-$($ActiveCandidates.Count)] to pin, or press Enter to skip"
    if ($Choice -match '^\d+$' -and [int]$Choice -ge 1 -and [int]$Choice -le $ActiveCandidates.Count) {
        $PinnedInstanceId = $ActiveCandidates[[int]$Choice - 1].DeviceID
        Write-Host "  [OK] Pinned InstanceId: $PinnedInstanceId" -ForegroundColor Green
    }
}

# 3. Create Protected Program Files Directory & Lock Down NTFS ACLs
Write-Host ""
Write-Host "[2/6] Creating Protected Program Directory & Applying Security ACLs..." -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

Copy-Item -LiteralPath (Join-Path $ScriptRoot 'Invoke-TouchscreenAction.ps1') -Destination (Join-Path $InstallDir 'Invoke-TouchscreenAction.ps1') -Force
Copy-Item -LiteralPath (Join-Path $ScriptRoot 'RobloxTouchSwitchApp.cs')      -Destination (Join-Path $InstallDir 'RobloxTouchSwitchApp.cs') -Force

$IconSrc = Join-Path $PackageRoot 'assets\RobloxTouchSwitch.ico'
$PngSrc  = Join-Path $PackageRoot 'assets\RobloxTouchSwitch.png'
$ArtSrc  = Join-Path $PackageRoot 'assets\Xbox_Library_CoverArt.png'
if (Test-Path -LiteralPath $IconSrc) { Copy-Item -LiteralPath $IconSrc -Destination (Join-Path $InstallDir 'RobloxTouchSwitch.ico') -Force }
if (Test-Path -LiteralPath $PngSrc)  { Copy-Item -LiteralPath $PngSrc  -Destination (Join-Path $InstallDir 'RobloxTouchSwitch.png') -Force }
if (Test-Path -LiteralPath $ArtSrc)  { Copy-Item -LiteralPath $ArtSrc  -Destination (Join-Path $InstallDir 'Xbox_Library_CoverArt.png') -Force }

# Write protected config.json
$ConfigObj = [ordered]@{
    AppName          = 'Roblox Touchscreen Switch'
    Version          = $AppVersion
    InstalledDate    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    InstalledByAdmin = $env:USERNAME
    ComputerName     = $env:COMPUTERNAME
    PinnedInstanceId = $PinnedInstanceId
}
$ConfigObj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $InstallDir 'config.json') -Encoding UTF8 -Force

# Compile RobloxTouchSwitch.exe using built-in Windows .NET Framework csc.exe
Write-Host ""
Write-Host "[3/6] Building Native Windows 11 Graphical Application (RobloxTouchSwitch.exe)..." -ForegroundColor Yellow
$CscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$CscExe = $CscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $CscExe) {
    throw "Could not locate built-in .NET Framework compiler (csc.exe) under $env:WINDIR\Microsoft.NET."
}

$ExeOutput = Join-Path $InstallDir 'RobloxTouchSwitch.exe'
$CsSource  = Join-Path $InstallDir 'RobloxTouchSwitchApp.cs'
$IconArg   = if (Test-Path -LiteralPath (Join-Path $InstallDir 'RobloxTouchSwitch.ico')) { "/win32icon:`"$(Join-Path $InstallDir 'RobloxTouchSwitch.ico')`"" } else { "" }

Get-Process -Name 'RobloxTouchSwitch' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$CompileArgs = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    "/out:`"$ExeOutput`"",
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Management.dll',
    '/reference:System.Windows.Forms.dll'
)
if ($IconArg) { $CompileArgs += $IconArg }
$CompileArgs += "`"$CsSource`""

$CompileProc = Start-Process -FilePath $CscExe -ArgumentList ($CompileArgs -join ' ') -NoNewWindow -Wait -PassThru
if ($CompileProc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $ExeOutput)) {
    throw "Compilation of RobloxTouchSwitch.exe failed with exit code $($CompileProc.ExitCode)."
}
Write-Host "  [OK] Compiled native GUI executable: $ExeOutput" -ForegroundColor Green

# Harden NTFS permissions on C:\Program Files\RobloxTouchscreenSwitch
# SYSTEM (S-1-5-18) = FullControl
# Administrators (S-1-5-32-544) = FullControl
# Users (S-1-5-32-545) = ReadAndExecute ONLY
$SidSystem = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
$SidAdmins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$SidUsers  = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')

$InheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$PropFlags    = [System.Security.AccessControl.PropagationFlags]::None

$RuleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule($SidSystem, [System.Security.AccessControl.FileSystemRights]::FullControl, $InheritFlags, $PropFlags, [System.Security.AccessControl.AccessControlType]::Allow)
$RuleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule($SidAdmins, [System.Security.AccessControl.FileSystemRights]::FullControl, $InheritFlags, $PropFlags, [System.Security.AccessControl.AccessControlType]::Allow)
$RuleUsers  = New-Object System.Security.AccessControl.FileSystemAccessRule($SidUsers,  [System.Security.AccessControl.FileSystemRights]::ReadAndExecute, $InheritFlags, $PropFlags, [System.Security.AccessControl.AccessControlType]::Allow)

$Acl = New-Object System.Security.AccessControl.DirectorySecurity
$Acl.SetAccessRuleProtection($true, $false)
$Acl.AddAccessRule($RuleSystem)
$Acl.AddAccessRule($RuleAdmins)
$Acl.AddAccessRule($RuleUsers)
Set-Acl -LiteralPath $InstallDir -AclObject $Acl

Get-ChildItem -LiteralPath $InstallDir -Recurse | ForEach-Object {
    $ItemAcl = Get-Acl -LiteralPath $_.FullName
    $ItemAcl.SetAccessRuleProtection($false, $true)
    Set-Acl -LiteralPath $_.FullName -AclObject $ItemAcl
}
Write-Host "  [OK] Locked NTFS ACLs on '$InstallDir' (Standard Users = Read & Execute Only)." -ForegroundColor Green

# 4. Create Locked ProgramData Folder for SYSTEM Audit Logs & Status (Users = ReadAndExecute ONLY)
Write-Host ""
Write-Host "[4/6] Configuring Tamper-Proof SYSTEM Audit Log & Status Directory ($DataDir)..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $DataDir) {
    $ExistingDir = Get-Item -LiteralPath $DataDir -Force
    if (($ExistingDir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "SECURITY ABORT: Existing '$DataDir' is a ReparsePoint (symlink/junction). Remove it manually as Administrator."
    }
} else {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
}

# Lock C:\ProgramData\RobloxTouchscreenSwitch to SYSTEM/Admins FullControl and Users ReadAndExecute ONLY.
# Standard Users CANNOT delete, symlink, or modify files written by SYSTEM.
$DataAcl = New-Object System.Security.AccessControl.DirectorySecurity
$DataAcl.SetAccessRuleProtection($true, $false)
$DataAcl.AddAccessRule($RuleSystem)
$DataAcl.AddAccessRule($RuleAdmins)
$DataAcl.AddAccessRule($RuleUsers)
Set-Acl -LiteralPath $DataDir -AclObject $DataAcl

$InitLogLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INSTALLER] [INFO] Installed Roblox Touchscreen Switch v$AppVersion on $env:COMPUTERNAME by Administrator '$env:USERNAME'."
Add-Content -LiteralPath $LogPath -Value $InitLogLine -Encoding UTF8

Get-ChildItem -LiteralPath $DataDir -Recurse | ForEach-Object {
    $ItemAcl = Get-Acl -LiteralPath $_.FullName
    $ItemAcl.SetAccessRuleProtection($false, $true)
    Set-Acl -LiteralPath $_.FullName -AclObject $ItemAcl
}
Write-Host "  [OK] Locked NTFS ACLs on '$DataDir' (Standard Users = Read-Only; SYSTEM/Admins = FullControl)." -ForegroundColor Green

# 5. Register Narrowly Restricted SYSTEM Scheduled Tasks with Full PowerShell Path
Write-Host ""
Write-Host "[5/6] Registering Narrowly Restricted SYSTEM Scheduled Tasks..." -ForegroundColor Yellow

$TaskFolderName = '\RobloxTouchscreenSwitch'
$WorkerScript   = Join-Path $InstallDir 'Invoke-TouchscreenAction.ps1'
$PsFullPath     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$Principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

# Task 1: DisableTouchscreen (Mouse Mode)
$ActionDisable = New-ScheduledTaskAction -Execute $PsFullPath -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WorkerScript`" -Action Disable"
Register-ScheduledTask -TaskPath "$TaskFolderName\" -TaskName 'DisableTouchscreen' -Action $ActionDisable -Principal $Principal -Settings $Settings -Description 'Disables HID-compliant touch screen for Roblox Mouse Mode.' -Force | Out-Null

# Task 2: EnableTouchscreen (Restore Touch)
$ActionEnable = New-ScheduledTaskAction -Execute $PsFullPath -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WorkerScript`" -Action Enable"
Register-ScheduledTask -TaskPath "$TaskFolderName\" -TaskName 'EnableTouchscreen' -Action $ActionEnable -Principal $Principal -Settings $Settings -Description 'Re-enables HID-compliant touch screen for handheld touch operation.' -Force | Out-Null

# Task 3: RestoreTouchOnBoot (Safety Fail-Safe at Windows Startup)
$TriggerBoot = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskPath "$TaskFolderName\" -TaskName 'RestoreTouchOnBoot' -Action $ActionEnable -Trigger $TriggerBoot -Principal $Principal -Settings $Settings -Description 'Fail-safe: Automatically restores touchscreen at Windows startup.' -Force | Out-Null

$Scheduler = New-Object -ComObject 'Schedule.Service'
$Scheduler.Connect()
$TaskFolder = $Scheduler.GetFolder($TaskFolderName)

try {
    $FolderSddl = $TaskFolder.GetSecurityDescriptor(4)
    if ($FolderSddl -notmatch ';\s*AU\)' -and $FolderSddl -notmatch 'S-1-5-11') {
        $FolderSddl = $FolderSddl + '(A;;GRGX;;;AU)'
        $TaskFolder.SetSecurityDescriptor($FolderSddl, 0)
    }
} catch { }

foreach ($TaskName in @('DisableTouchscreen', 'EnableTouchscreen')) {
    $RegisteredTask = $TaskFolder.GetTask($TaskName)
    $CurrentSddl = $RegisteredTask.GetSecurityDescriptor(4)
    if ($CurrentSddl -notmatch '\(A;;GRGX;;;AU\)') {
        $UpdatedSddl = $CurrentSddl + '(A;;GRGX;;;AU)'
        $RegisteredTask.SetSecurityDescriptor($UpdatedSddl, 0)
    }
    Write-Host "  [OK] Task '$TaskFolderName\$TaskName' registered as SYSTEM (Standard Users granted Read+Run ONLY)." -ForegroundColor Green
}
Write-Host "  [OK] Fail-safe boot task '$TaskFolderName\RestoreTouchOnBoot' registered." -ForegroundColor Green

# 6. Create All-Users Desktop & Start Menu Shortcuts
Write-Host ""
Write-Host "[6/6] Creating Desktop and Start Menu Shortcuts for All Users..." -ForegroundColor Yellow
$WshShell = New-Object -ComObject WScript.Shell

$PublicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
$CommonStartMenu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Roblox Touchscreen Switch'
if (-not (Test-Path -LiteralPath $CommonStartMenu)) {
    New-Item -Path $CommonStartMenu -ItemType Directory -Force | Out-Null
}

$ShortcutLocations = @(
    (Join-Path $PublicDesktop 'Roblox Touchscreen Switch.lnk'),
    (Join-Path $CommonStartMenu 'Roblox Touchscreen Switch.lnk')
)

foreach ($LnkPath in $ShortcutLocations) {
    $Shortcut = $WshShell.CreateShortcut($LnkPath)
    $Shortcut.TargetPath = $ExeOutput
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.Description = 'Switch between Mouse Mode (Disable Touchscreen) and Restore Touch for Roblox'
    if (Test-Path -LiteralPath (Join-Path $InstallDir 'RobloxTouchSwitch.ico')) {
        $Shortcut.IconLocation = "$(Join-Path $InstallDir 'RobloxTouchSwitch.ico'),0"
    }
    $Shortcut.Save()
    Write-Host "  [OK] Created shortcut: $LnkPath" -ForegroundColor Green
}

$MouseLnk = $WshShell.CreateShortcut((Join-Path $CommonStartMenu 'Roblox - Mouse Mode (Touch OFF).lnk'))
$MouseLnk.TargetPath = $ExeOutput
$MouseLnk.Arguments = '--mouse'
$MouseLnk.WorkingDirectory = $InstallDir
$MouseLnk.Description = 'Immediately activate Mouse Mode for Roblox'
if (Test-Path -LiteralPath (Join-Path $InstallDir 'RobloxTouchSwitch.ico')) {
    $MouseLnk.IconLocation = "$(Join-Path $InstallDir 'RobloxTouchSwitch.ico'),0"
}
$MouseLnk.Save()

$TouchLnk = $WshShell.CreateShortcut((Join-Path $CommonStartMenu 'Roblox - Restore Touch (Touch ON).lnk'))
$TouchLnk.TargetPath = $ExeOutput
$TouchLnk.Arguments = '--touch'
$TouchLnk.WorkingDirectory = $InstallDir
$TouchLnk.Description = 'Immediately restore handheld touchscreen'
if (Test-Path -LiteralPath (Join-Path $InstallDir 'RobloxTouchSwitch.ico')) {
    $TouchLnk.IconLocation = "$(Join-Path $InstallDir 'RobloxTouchSwitch.ico'),0"
}
$TouchLnk.Save()

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE (v$AppVersion)!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  - GUI App Installed : $ExeOutput"
Write-Host "  - Desktop Shortcut  : Created on Public Desktop (available to your son's account)"
Write-Host "  - Start Menu Folder : Start -> All Apps -> Roblox Touchscreen Switch"
Write-Host "  - SYSTEM Audit Log  : $LogPath (Read-Only for Standard Users)"
Write-Host "  - User GUI Log      : %LOCALAPPDATA%\RobloxTouchscreenSwitch\gui-activity.log"
Write-Host ""
