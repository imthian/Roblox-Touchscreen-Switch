# Changelog

All notable changes to **Roblox Touchscreen Switch** are documented in this file.

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
