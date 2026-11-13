# Changelog

All notable changes to **Roblox Touchscreen Switch** are documented in this file.

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
- Locked `ProgramData` ACLs to read-only for standard users and separated GUI logs into `%LOCALAPPDATA%`.
- Added locale-independent HID Usage (`HID_DEVICE_UP:000D_U:0004`) matching and strict `ConfigManagerErrorCode == 22` checks.

## [1.0.0] - 2026-11-04
- Initial release for MSI Claw A1M and ASUS ROG Ally Z1 Extreme.
