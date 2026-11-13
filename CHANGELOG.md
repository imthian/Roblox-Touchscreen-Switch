# Changelog

All notable changes to **Roblox Touchscreen Switch** are documented in this file.

## [1.2.1] - 2026-11-09

### Security Hardening (Junction & ReparsePoint Defense)
- **Eliminated `Remove-Item -Recurse` Junction-Following Risk (PowerShell 5.1)**:
  - **SYSTEM Worker (`Invoke-TouchscreenAction.ps1`)**: Never deletes an existing `$env:ProgramData\RobloxTouchscreenSwitch` directory as `SYSTEM`. If the directory is a `ReparsePoint`, owned by an untrusted SID, or has writable non-admin ACLs, the worker leaves `$script:DataDirTrusted = $false` and aborts immediately with Exit Code `45`.
  - **Strict `$script:DataDirTrusted` Gate**: `Write-SystemLog` and `Save-StateReport` check `$script:DataDirTrusted` first and refuse to write a single byte if `Initialize-LockedDataDir` threw a security exception.
  - **Admin Installer & Uninstaller (`Remove-DirectorySafely`)**: Inspect both the root directory and all recursive children for `FileAttributes.ReparsePoint` before calling `[System.IO.Directory]::Delete($TargetPath, $true)`, aborting immediately if any symlink or junction is detected.
- **Admin-Only Extraction Guidance**: Updated `README.md` and `README-FIRST.txt` to instruct extracting the installer inside the Administrator's own user profile (`C:\Users\<Admin>\Downloads`) rather than a child-writable folder prior to installation.

### Reliability & Repo Hygiene
- **Best-Effort Multi-Node Loop**: When multiple composite touchscreen nodes are pinned, `Disable` and `Enable` now iterate across every target node in a `try / catch` before evaluating combined state so a transient error on one node never leaves remaining nodes un-toggled.
- **UTF-8 Without BOM & BOM-Safe JSON Deserialization**: `Install-Logic.ps1` and `Invoke-TouchscreenAction.ps1` write `config.json`, `status.json`, and `system-activity.log` using `UTF8Encoding($false)` (no BOM), and `RobloxTouchSwitchApp.cs` strips any `\uFEFF` BOM prefix before calling `DataContractJsonSerializer.ReadObject`.
- **LF Line Endings in `SHA256SUMS.txt`**: Saved `SHA256SUMS.txt` with Unix LF (`\n`) line endings so `sha256sum -c SHA256SUMS.txt` passes cleanly in Git Bash, WSL, and Linux.
- **Pinned `PSScriptAnalyzer` in CI**: Pinned `Install-Module -Name PSScriptAnalyzer -RequiredVersion '1.23.0'` in `.github/workflows/ci.yml`.

## [1.2.0] - 2026-11-09
- Added `SetOwner($SidAdmins)` on `ProgramData`, `fsutil hardlink list` verification, strict `ERR_PINNED_MISSING` fail-closed behavior, composite `PinnedInstanceIds` array support, 2.5s driver polling, 12.0s GUI timeout detection, self-verifying `Emergency-Restore-Touchscreen.bat`, 512 KB log rotation, dynamic `$env:ProgramFiles` / `$env:ProgramData` paths, and GitHub Actions CI.

## [1.1.0] - 2026-11-05
- Locked `ProgramData` ACLs to read-only for standard users, separated GUI logs into `%LOCALAPPDATA%`, added locale-independent HID Usage (`HID_DEVICE_UP:000D_U:0004`) matching, and enforced strict `ConfigManagerErrorCode == 22` checks.

## [1.0.0] - 2026-11-04
- Initial release for MSI Claw A1M and ASUS ROG Ally Z1 Extreme.
