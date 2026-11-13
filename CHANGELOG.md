# Changelog

All notable changes to **Roblox Touchscreen Switch** are documented in this file.

## [1.2.2] - 2026-11-09

### Security & Bug Fixes
- **Fixed `Emergency-Restore-Touchscreen.bat` Parse-Time `%errorLevel%` Bug**: Enabled `EnableDelayedExpansion` and replaced the nested `if %errorLevel% equ 0` inside the Step 1 block with `if not errorlevel 1`, ensuring `cmd.exe` evaluates the PowerShell verification exit code at runtime rather than reading `schtasks.exe`'s cached `0` exit code at block parse time.
- **Atomic `ProgramData` Directory Creation (Zero ACL Race Window)**: Both `Install-Logic.ps1` and `Invoke-TouchscreenAction.ps1` now pass the locked `DirectorySecurity` object directly into `[System.IO.Directory]::CreateDirectory($DataDir, $DataAcl)` in a single call, verify the newly created directory is completely empty before writing, and call `$LogItemAcl.SetAccessRuleProtection($false, $false)` so any explicit child ACEs are stripped.
- **Strict SID Allowlist ACL Verification**: `Initialize-LockedDataDir` (in `Invoke-TouchscreenAction.ps1`), `Test-SafeTargetFile`, and `Test-CompatibilityAndSecurity.ps1` now translate every `Allow` ACE to a `SecurityIdentifier` (`Translate([SecurityIdentifier])`) and fail closed if **any** identity other than `NT AUTHORITY\SYSTEM` (`S-1-5-18`) or `BUILTIN\Administrators` (`S-1-5-32-544`) holds write, modify, delete, create, or change-permissions rights.
- **Two-Pass All-or-Nothing Pre-Check on `Disable`**: When multiple composite touchscreen nodes are pinned, `Disable` now inspects all target nodes for non-0, non-22 driver faults in Pass 1 *before* calling `Disable-PnpDevice` on any node in Pass 2, preventing a faulted node from leaving sibling nodes in a half-disabled state.

## [1.2.1] - 2026-11-09

### Security Hardening & Verification Improvements
- **Eliminated `Remove-Item -Recurse` Junction-Following Risk (PowerShell 5.1)**:
  - `Invoke-TouchscreenAction.ps1` never deletes an existing `$env:ProgramData\RobloxTouchscreenSwitch` directory as `SYSTEM`; if untrusted, it leaves `$script:DataDirTrusted = $false` and aborts with Exit Code `45`.
  - `Write-SystemLog` and `Save-StateReport` are gated behind `$script:DataDirTrusted`.
  - `Install-Logic.ps1` and `Uninstall-Logic.ps1` verify zero `ReparsePoint` attributes exist at root or on any child item before calling `[System.IO.Directory]::Delete($TargetPath, $true)`.
- **Uninstaller Pin-Respecting Logic**: `Uninstall-Logic.ps1` honors `PinnedInstanceIds` from `config.json` and the single-device safety rule.
- **12.0-Second GUI Polling Window & Timeout Distinction**: Extended GUI `status.json` polling to `12.0s` (`40 x 300ms`) with a live countdown and dedicated `WORKER TIMEOUT` warning.
- **Self-Verifying Emergency Recovery Script**: Added WMI `ConfigManagerErrorCode == 0` verification to `Emergency-Restore-Touchscreen.bat`.
- **UTF-8 Without BOM, LF `SHA256SUMS.txt`, & Pinned `PSScriptAnalyzer`**: Switched JSON/log writes to `UTF8Encoding($false)`, stripped `\uFEFF` in C#, saved `SHA256SUMS.txt` with Unix LF endings, and pinned `PSScriptAnalyzer -RequiredVersion '1.23.0'` in CI.

## [1.2.0] - 2026-11-09
- Added `SetOwner($SidAdmins)` on `ProgramData`, `fsutil hardlink list` verification, strict `ERR_PINNED_MISSING` fail-closed behavior, composite `PinnedInstanceIds` array support, 2.5s driver polling, 512 KB log rotation, dynamic `$env:ProgramFiles` / `$env:ProgramData` paths, `DataContractJsonSerializer` parsing, single-source `VERSION` file, and GitHub Actions CI.

## [1.1.0] - 2026-11-05
- Locked `ProgramData` ACLs to read-only for standard users, separated GUI logs into `%LOCALAPPDATA%`, added locale-independent HID Usage (`HID_DEVICE_UP:000D_U:0004`) matching, and enforced strict `ConfigManagerErrorCode == 22` checks.

## [1.0.0] - 2026-11-04
- Initial release for MSI Claw A1M and ASUS ROG Ally Z1 Extreme.
