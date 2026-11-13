# Changelog

All notable changes to **Roblox Touchscreen Switch** are documented in this file.

## [1.2.4] - 2026-11-09

### Security, Verification & Reliability Hardening
- **Uninstaller Hardware Health Verification**: `Uninstall-Logic.ps1` now queries WMI after re-enabling the touchscreen to independently verify `ConfigManagerErrorCode == 0` and `Status == 'OK'` (checking all pinned nodes if configured) before displaying `UNINSTALLATION COMPLETE - TOUCHSCREEN IS VERIFIED ENABLED (OK)`, or prints an explicit warning if restoration is unconfirmed.
- **Emergency Recovery Pinned-Device Verification**: `Emergency-Restore-Touchscreen.bat` now explicitly verifies that *every* configured pinned device in `config.json` is present and healthy (`ErrorCode == 0`, `Status == 'OK'`) before reporting success in both Step 1 and Step 2.
- **Shared Security Module (`core/SecurityValidation.psm1`)**: Consolidated the directory ACL validation logic into a shared PowerShell module with `Test-SafeDirectoryAcl` used verbatim by `Invoke-TouchscreenAction.ps1`, `Test-CompatibilityAndSecurity.ps1`, and the CI Pester test, preventing code drift.
- **Comprehensive Write Rights Mask (`0x500D0156`)**: Added `GenericWrite` (`0x40000000`) and `GenericAll` (`0x10000000`) to the write-mask check without impacting `ReadAndExecute` (`0x1200A9 -band 0x500D0156 = 0`).
- **Updated v1.2.4 Admin & Deployment Guide**: Added the revised 4-page PDF deployment guide (`Roblox_Touchscreen_Switch_Admin_and_Deployment_Guide.pdf`), aligned ZIP package filenames (`ROBLOX TOUCHSCREEN SWITCH (v1.2.4).zip`), and documented direct UAC Administrator PIN elevation when installing from a Standard Child Account.

## [1.2.3] - 2026-11-09

### Critical Fix (Permission Mask Correction)
- **Corrected `$WriteRightsMask` to 0xD0156 (Fixed ReadAndExecute Rejection)**:
  - In v1.2.2, `$WriteRightsMask` included `Modify` and `FullControl`, which include read bits and evaluate to `0x1F01FF`. Because `Users: ReadAndExecute` (0x1200A9) had non-zero overlap with `0x1F01FF`, the allowlist check incorrectly flagged the standard Users rule as granting write access and aborted execution with Exit Code 45.
  - Corrected `$WriteRightsMask` to list strictly write, modify, delete, and take-ownership bits:
    `WriteData | AppendData | WriteExtendedAttributes | WriteAttributes | DeleteSubdirectoriesAndFiles | Delete | ChangePermissions | TakeOwnership` (`0xD0156`).
  - `0x1200A9 -band 0xD0156 = 0`, allowing standard Users `ReadAndExecute` to pass cleanly while strictly catching any real write rights.
- **Direct SID Rule Enumeration**: Switched `$CurrentAcl.Access` to `$CurrentAcl.GetAccessRules($true, $true, [SecurityIdentifier])` in `Invoke-TouchscreenAction.ps1` and `Test-CompatibilityAndSecurity.ps1`, eliminating potential `Translate()` exceptions on deleted accounts.
- **Removed `EnableDelayedExpansion` from Emergency Script**: Removed delayed expansion from `Emergency-Restore-Touchscreen.bat` so paths with exclamation marks (`!`) do not get mangled by `set "SELF_BAT=%~f0"`.
- **Pre-Creation Existence Check**: Added an explicit `Test-Path` verification before `[System.IO.Directory]::CreateDirectory($DataDir, $DataAcl)` to verify non-existence.
- **Added Automated Pester CI Test**: Added a dedicated Pester test in `.github/workflows/ci.yml` that constructs ACLs with `SYSTEM`/`Admins` FullControl and `Users` ReadAndExecute, asserting that it passes `0xD0156`, and asserting that adding a write rule correctly fails.

## [1.2.2] - 2026-11-09

### Security & Bug Fixes
- **Fixed `Emergency-Restore-Touchscreen.bat` Parse-Time `%errorLevel%` Bug**: Enabled `EnableDelayedExpansion` and replaced the nested `if %errorLevel% equ 0` inside the Step 1 block with `if not errorlevel 1`, ensuring `cmd.exe` evaluates the PowerShell verification exit code at runtime rather than reading `schtasks.exe`'s cached `0` exit code at block parse time.
- **Atomic `ProgramData` Directory Creation (Zero ACL Race Window)**: Both `Install-Logic.ps1` and `Invoke-TouchscreenAction.ps1` now pass the locked `DirectorySecurity` object directly into `[System.IO.Directory]::CreateDirectory($DataDir, $DataAcl)` in a single call, verify the newly created directory is completely empty before writing, and call `$LogItemAcl.SetAccessRuleProtection($false, $false)` so any explicit child ACEs are stripped.
- **Strict SID Allowlist ACL Verification**: `Initialize-LockedDataDir` (in `Invoke-TouchscreenAction.ps1`), `Test-SafeTargetFile`, and `Test-CompatibilityAndSecurity.ps1` now translate every `Allow` ACE to a `SecurityIdentifier` (`Translate([SecurityIdentifier])`) and fail closed if **any** identity other than `NT AUTHORITY\SYSTEM` (`S-1-5-18`) or `BUILTIN\Administrators` (`S-1-5-32-544`) holds write, modify, delete, create, or change-permissions rights.
- **Two-Pass All-or-Nothing Pre-Check on `Disable`**: When multiple composite touchscreen nodes are pinned, `Disable` now inspects all target nodes for non-0, non-22 driver faults in Pass 1 *before* calling `Disable-PnpDevice` on any node in Pass 2, preventing a faulted node from leaving sibling nodes in a half-disabled state.

## [1.2.1] - 2026-11-09

### Security Hardening (Junction & ReparsePoint Defense)
- **Eliminated `Remove-Item -Recurse` Junction-Following Risk (PowerShell 5.1)**:
  - **SYSTEM Worker (`Invoke-TouchscreenAction.ps1`)**: Never deletes an existing `$env:ProgramData\RobloxTouchscreenSwitch` directory as `SYSTEM`. If the directory is a `ReparsePoint`, owned by an untrusted SID, or has writable non-admin ACLs, the worker leaves `$script:DataDirTrusted = $false` and aborts immediately with Exit Code `45`.
  - **Strict `$script:DataDirTrusted` Gate**: `Write-SystemLog` and `Save-StateReport` are gated behind `$script:DataDirTrusted`, checking it first and refusing to write a single byte if `Initialize-LockedDataDir` threw a security exception.
  - **Admin Installer & Uninstaller (`Install-Logic.ps1` & `Uninstall-Logic.ps1` / `Remove-DirectorySafely`)**: Inspect both the root directory and all recursive children to verify zero `FileAttributes.ReparsePoint` attributes exist before calling `[System.IO.Directory]::Delete($TargetPath, $true)`, aborting immediately if any symlink or junction is detected.
- **Admin-Only Extraction Guidance**: Updated `README.md` and `README-FIRST.txt` to instruct extracting the installer inside the Administrator's own user profile (`C:\Users\<Admin>\Downloads`) rather than a child-writable folder prior to installation.

### Reliability, Verification & Repo Hygiene
- **Uninstaller Pin-Respecting Logic**: `Uninstall-Logic.ps1` honors `PinnedInstanceIds` from `config.json` and the single-device safety rule.
- **12.0-Second GUI Polling Window & Timeout Distinction**: Extended GUI `status.json` polling to `12.0s` (`40 x 300ms`) with a live countdown and dedicated `WORKER TIMEOUT` warning.
- **Self-Verifying Emergency Recovery Script**: Added WMI `ConfigManagerErrorCode == 0` verification to `Emergency-Restore-Touchscreen.bat`.
- **Best-Effort Multi-Node Loop**: When multiple composite touchscreen nodes are pinned, `Disable` and `Enable` now iterate across every target node in a `try / catch` before evaluating combined state so a transient error on one node never leaves remaining nodes un-toggled.
- **UTF-8 Without BOM & BOM-Safe JSON Deserialization**: `Install-Logic.ps1` and `Invoke-TouchscreenAction.ps1` write `config.json`, `status.json`, and `system-activity.log` using `UTF8Encoding($false)` (no BOM), and `RobloxTouchSwitchApp.cs` strips any `\uFEFF` BOM prefix before calling `DataContractJsonSerializer.ReadObject`.
- **LF Line Endings in `SHA256SUMS.txt`**: Saved `SHA256SUMS.txt` with Unix LF (`\n`) line endings so `sha256sum -c SHA256SUMS.txt` passes cleanly in Git Bash, WSL, and Linux.
- **Pinned `PSScriptAnalyzer` in CI**: Pinned `Install-Module -Name PSScriptAnalyzer -RequiredVersion '1.23.0'` in `.github/workflows/ci.yml`.

## [1.2.0] - 2026-11-09

### Security Hardening
- **Eliminated `ProgramData` Pre-Creation Ownership Takeover & Hardlink Races**:
  - `Install-Logic.ps1` now removes any pre-existing `$env:ProgramData\RobloxTouchscreenSwitch` directory before creating a fresh directory, explicitly assigns ownership to `BUILTIN\Administrators` (`$DataAcl.SetOwner($SidAdmins)`), and sets `FullControl` for `SYSTEM`/`Administrators` and `ReadAndExecute` only for `Users`.
  - `Invoke-TouchscreenAction.ps1` (`Initialize-LockedDataDir`) verifies that `$env:ProgramData\RobloxTouchscreenSwitch` and its files are owned by `SYSTEM` or `Administrators`, checks `ReparsePoint` attributes, and inspects NTFS hardlink counts via `fsutil.exe hardlink list` before writing.
- **Apostrophe-Safe Batch UAC Elevation**: All `.bat` launchers now pass `%~f0` via an environment variable (`set "SELF_BAT=%~f0"` -> `Start-Process -FilePath $env:SELF_BAT`) so paths containing apostrophes (e.g., `C:\Users\O'Brien\...`) never break PowerShell command-line quoting or allow injection.

### Bug Fixes & Reliability Improvements
- **Strict Pinned-Device Enforcement (No Fallback Guessing)**: If the Administrator configures `PinnedInstanceIds` in `config.json` and a pinned touchscreen node is disconnected or missing, both the `SYSTEM` worker and GUI immediately halt with `ERR_PINNED_MISSING` (Exit Code `15`) rather than falling back to general device matching.
- **Multi-Node Composite Touchscreen Pinning (`PinnedInstanceIds`)**: Some touch panels expose two composite `HID-compliant touch screen` nodes. The installer now supports pinning a single index (`1`), a comma-separated list (`1,2`), or `ALL`, and both the worker and GUI toggle all pinned nodes together.
- **Guaranteed `status.json` Reporting & GUI Unreported-Worker Alert**: Wrapped the entire `Invoke-TouchscreenAction.ps1` execution body in a top-level `try / catch` block so every failure path (`Import-Module`, WMI/CIM query error, or security abort) writes a structured report to `status.json`. If `status.json` is not updated within 5.4 seconds after task launch, the GUI now displays a `"Worker Did Not Report Back"` alert.
- **2.5-Second State Verification Polling**: Replaced the single `350 ms` sleep after `Disable-PnpDevice` / `Enable-PnpDevice` with a 10-iteration (`250 ms` interval, up to `2.5 seconds`) verification poll so slower touch controller drivers do not trigger false `ERR_VERIFY_FAILED` errors.
- **Dynamic System Paths (`$env:ProgramFiles` & `$env:ProgramData`)**: Replaced all hardcoded `C:\Program Files` and `C:\ProgramData` paths across PowerShell, C#, and Batch scripts with `$env:ProgramFiles`, `$env:ProgramData`, `Environment.SpecialFolder.ProgramFiles`, and `Environment.SpecialFolder.CommonApplicationData`.
- **Log Rotation & Bounded Tail Reading**: Both `system-activity.log` and `gui-activity.log` now automatically rotate at `512 KB` (to `.old.log`), and the GUI reads only the last `32 KB` via `FileStream.Seek` rather than loading entire files with `File.ReadAllLines`.
- **Native `DataContractJsonSerializer` Parsing**: Replaced regular-expression JSON parsing in `RobloxTouchSwitchApp.cs` with `.NET` `DataContractJsonSerializer`.

### Repository Hygiene & CI
- **Single-Source `VERSION` File**: Added a root `VERSION` file (`1.2.0`) read dynamically by the installer, worker, uninstaller, diagnostics, and GUI.
- **GitHub Actions CI Workflow**: Added `.github/workflows/ci.yml` running `PSScriptAnalyzer` on all PowerShell scripts and compiling `RobloxTouchSwitchApp.cs` on `windows-latest` on every push and pull request.
- **Clean Repo Root**: Removed `Roblox_Touchscreen_Switch_Admin_and_Deployment_Guide.pdf` from the GitHub repository root (keep the PDF as a GitHub Release attachment alongside the installer ZIP).

## [1.1.0] - 2026-11-05

### Security (Critical Hardening)
- **Locked `C:\ProgramData\RobloxTouchscreenSwitch` ACLs to Read-Only for Standard Users**: Standard users (`Users` group `S-1-5-32-545`) now receive `ReadAndExecute` only on `C:\ProgramData\RobloxTouchscreenSwitch`, while `NT AUTHORITY\SYSTEM` and `Administrators` hold `FullControl`. This prevents standard users from forging the `system-activity.log` audit trail or replacing the folder/files with symlinks or NTFS junctions to redirect `SYSTEM` file writes.
- **ReparsePoint Guardrails**: Both the installer and the `SYSTEM` worker (`Invoke-TouchscreenAction.ps1`) inspect `FileAttributes.ReparsePoint` on `C:\ProgramData\RobloxTouchscreenSwitch`, `system-activity.log`, and `status.json` before writing.
- **Separated User GUI Logging**: The WinForms GUI (`RobloxTouchSwitch.exe`) now writes user-level UI events to `%LOCALAPPDATA%\RobloxTouchscreenSwitch\gui-activity.log` while reading `C:\ProgramData\RobloxTouchscreenSwitch\system-activity.log` and `status.json` in read-only mode.
- **Full System32 Executable Paths**: Scheduled tasks and batch launchers now explicitly invoke `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` and `%SystemRoot%\System32\schtasks.exe`.

### Bug Fixes
- **Active `status.json` Inspection in GUI**: After triggering a Scheduled Task, the GUI now polls `status.json` (up to 4.5 seconds) for a newer `TimestampUtc` from the `SYSTEM` worker and immediately surfaces any worker errors (`ERR_NOT_FOUND`, `ERR_MULTIPLE_DEVICES`, `ERR_DRIVER_FAULT`, `ERR_VERIFY_FAILED`, `ERR_EXCEPTION`).
- **Strict Error Code 22 Validation**: Both the `SYSTEM` worker and the GUI now treat **only** `ConfigManagerErrorCode == 22` as intentionally disabled (**MOUSE MODE ACTIVE**). Any other non-zero error code is reported as a `[!] TOUCHSCREEN DRIVER ERROR` rather than falsely showing Mouse Mode.
- **Safe `WaitForExit` Timeout Handling**: `RobloxTouchSwitchApp.cs` now checks the boolean return value of `p.WaitForExit(8000)` before reading `p.ExitCode`, killing the process and reporting a clean timeout if `schtasks.exe` hangs.
- **Locale-Independent Hardware Matching**: Both the GUI and `SYSTEM` worker now query `Win32_PnPEntity` for `PNPClass = 'HIDClass'` and match devices where **either** the `HardwareID`/`CompatibleID` contains the standard HID Digitizer/Touchscreen usage (`HID_DEVICE_UP:000D_U:0004`) **or** `Name = 'HID-compliant touch screen'`. This works across English, German, French, and all other Windows 11 display languages.
- **Unified Device Enumeration**: Both the C# GUI and PowerShell worker use the exact same `Win32_PnPEntity` (`PNPClass = 'HIDClass'`) filter and `PinnedInstanceId` logic, eliminating edge-case count mismatches.
- **Emergency Recovery Script `--elevated` Handling**: `Emergency-Restore-Touchscreen.bat` now checks `if /I "%~1"=="--elevated"` to jump straight to elevated recovery without re-triggering the scheduled task, and honors `PinnedInstanceId` in `config.json` when present.

### Polish
- **Removed Surrogate-Pair Emojis from WinForms Controls**: Replaced supplementary-plane emojis in WinForms button and banner labels with clean ASCII/BMP text so legacy `.NET Framework` GDI+ never renders empty square boxes (`□`).
- **Clear Variable Naming in Uninstaller**: Renamed `$KeepLogs` to `$DeleteLogsPrompt` in `Uninstall-Logic.ps1` to match the prompt wording.
- **Clean GitHub Repo Root**: Moved the 221 KB PDF deployment manual out of the GitHub repository root (to be attached as a GitHub Release asset alongside the installer ZIP and `SHA256SUMS.txt`).

## [1.0.0] - 2026-11-04
- Initial release for MSI Claw A1M and ASUS ROG Ally Z1 Extreme.