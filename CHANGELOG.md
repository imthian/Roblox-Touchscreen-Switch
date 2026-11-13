# Changelog

All notable changes to **Roblox Touchscreen Switch** are documented in this file.

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
- Replaced nested `%errorLevel%` in `Emergency-Restore-Touchscreen.bat` with `if not errorlevel 1`.
- Added atomic `[System.IO.Directory]::CreateDirectory($DataDir, $DataAcl)`, empty check, and `$LogItemAcl.SetAccessRuleProtection($false, $false)`.
- Added two-pass all-or-nothing pre-check on `Disable`.

## [1.2.1] - 2026-11-09
- Eliminated `Remove-Item -Recurse` junction-following risk in PowerShell 5.1.
- Gated SYSTEM worker logging behind `$script:DataDirTrusted`.
- Added 12.0s GUI polling window, self-verifying emergency script, UTF-8 without BOM, and LF `SHA256SUMS.txt`.

## [1.2.0] - 2026-11-09
- Initial release of ownership hardening, composite touch arrays, and CI.

## [1.1.0] - 2026-11-05
- Locked ProgramData ACLs to read-only for standard users and separated GUI logs.

## [1.0.0] - 2026-11-04
- Initial release for MSI Claw A1M and ASUS ROG Ally Z1 Extreme.
