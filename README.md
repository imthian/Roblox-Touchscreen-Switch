# Roblox Touchscreen Switch (Windows 11 Handheld Utility)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-brightgreen.svg)](CHANGELOG.md)
[![Platform: Windows 11](https://img.shields.io/badge/Platform-Windows%2011-0078D6.svg)]()
[![Devices: MSI Claw | ROG Ally | Legion Go](https://img.shields.io/badge/Devices-MSI%20Claw%20%7C%20ASUS%20ROG%20Ally%20%7C%20Windows%20Handhelds-success.svg)]()

A lightweight, open-source Windows 11 graphical utility that fixes the **Roblox external mouse click/grab bug** (especially in games like *Fling Things and People*) on touchscreen gaming handhelds and laptops—such as the **MSI Claw A1M** and **ASUS ROG Ally Z1 Extreme**—while allowing **Standard Windows Users / Microsoft Child Accounts** to toggle the touchscreen **OFF (Mouse Mode)** and **ON (Restore Touch)** with **zero Administrator password prompts**.

---

## The Problem

When playing Roblox in docked or desktop mode with an external mouse on Windows 11 touchscreen handhelds (**MSI Claw**, **ASUS ROG Ally**, **Lenovo Legion Go**) or touchscreen laptops:
- The external mouse cursor moves normally.
- Mouse clicks work inside Roblox menus.
- **Mouse clicks and hold/drag actions fail to register during live gameplay** (for example, grabbing and throwing objects or players in *Fling Things and People*).
- Disabling the touchscreen device in Windows Device Manager immediately fixes the issue—but **Device Manager requires Administrator privileges**, leaving parents with a frustrating dilemma if their child plays on a **Standard User / Microsoft Family Child Account**.

---

## What This Utility Does (v1.1.0)

**Roblox Touchscreen Switch** provides a handheld-friendly Windows Forms graphical app (`RobloxTouchSwitch.exe`) backed by narrowly restricted `NT AUTHORITY\SYSTEM` Scheduled Tasks:

1. **[ MOUSE MODE ] (Disable Touchscreen)**: Temporarily disables the touchscreen PnP device (`ConfigManagerErrorCode = 22`) so external mouse clicks and grabbing work normally in Roblox.
2. **[ RESTORE TOUCH ] (Enable Touchscreen)**: Re-enables the touchscreen (`ConfigManagerErrorCode = 0`, `Status = OK`) when returning to normal handheld use (the SYSTEM task completes in ~1 second while the GUI polls `status.json` for up to 4.5 seconds to verify hardware state).
3. **Hardened Standard User / Child Account Security**:
   - Installed once by an Administrator into `C:\Program Files\RobloxTouchscreenSwitch\`.
   - **Strict NTFS ACLs on Both Program Files & ProgramData**: Both `C:\Program Files\RobloxTouchscreenSwitch\` and `C:\ProgramData\RobloxTouchscreenSwitch\` are locked to **Read & Execute Only** for Standard Users (`FullControl` restricted to `SYSTEM` and `Administrators`), with `ReparsePoint` checks before every write. Standard users cannot edit scripts, forge `system-activity.log`, or redirect `SYSTEM` file writes via symlinks/junctions.
   - **Separated Logs**: The `SYSTEM` worker writes tamper-proof audit records to `C:\ProgramData\RobloxTouchscreenSwitch\system-activity.log` and `status.json`, while the user GUI logs its own events to `%LOCALAPPDATA%\RobloxTouchscreenSwitch\gui-activity.log`.
   - **Custom Task Scheduler SDDL (`(A;;GRGX;;;AU)`)**: Grants Authenticated Users **Read & Run (`GRGX`)** rights on `\RobloxTouchscreenSwitch\DisableTouchscreen` and `\RobloxTouchscreenSwitch\EnableTouchscreen` with zero edit/delete rights and **zero stored Administrator passwords**.
4. **Built-In Hardware & Gaming Safeguards**:
   - **Locale-Independent Touchscreen Detection**: Matches devices in `PNPClass = 'HIDClass'` using the standard HID Digitizer/Touchscreen usage (`HID_DEVICE_UP:000D_U:0004`) as well as `HID-compliant touch screen`, working across all Windows 11 display languages using identical WMI/CIM rules in both the GUI and worker.
   - **Exact Error Code 22 Checking**: Distinguishes between an intentionally disabled touchscreen (`ErrorCode == 22`) and an unexpected driver fault (any other non-zero error code).
   - **Multi-Device Hard Stop**: If more than one matching touchscreen device is found (and no `PinnedInstanceId` was configured by the Administrator), the utility refuses to guess and halts safely.
   - **Automatic Boot Fail-Safe (`RestoreTouchOnBoot`)**: Automatically re-enables the touchscreen every time Windows boots up, so restarting the handheld always restores touch.
   - **Obscure 4-Key Chords**: Uses `Ctrl + Alt + Shift + M` (Mouse Mode) and `Ctrl + Alt + Shift + T` (Restore Touch) only when the window is focused, preventing accidental triggers during gameplay.

---

## Quick Installation

1. Download **`ROBLOX TOUCHSCREEN SWITCH (v1.1.0).zip`** from the **Releases** section (or clone this repository) and extract it to a local folder.
2. Right-click **`Install-RobloxTouchSwitch.bat`** and select **Run as administrator**.
3. The installer automatically:
   - Verifies your touchscreen hardware node (`HID_DEVICE_UP:000D_U:0004`).
   - Compiles the native GUI executable (`C:\Program Files\RobloxTouchscreenSwitch\RobloxTouchSwitch.exe`) using the built-in Windows .NET Framework compiler (`csc.exe`)—**no third-party runtimes required**.
   - Locks down NTFS permissions on `C:\Program Files\RobloxTouchscreenSwitch\` and `C:\ProgramData\RobloxTouchscreenSwitch\`.
   - Registers `\RobloxTouchscreenSwitch\DisableTouchscreen`, `\RobloxTouchscreenSwitch\EnableTouchscreen`, and `\RobloxTouchscreenSwitch\RestoreTouchOnBoot` using the full path `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`.
   - Creates shortcuts on the **Public Desktop** and **Start Menu** (`Start -> All Apps -> Roblox Touchscreen Switch`) for all accounts on the PC.
4. Switch to your Standard User / Child Account and launch **Roblox Touchscreen Switch** from the Desktop, Start Menu, **Xbox PC App / Full Screen Experience**, **MSI Center M**, or **ASUS Armoury Crate SE**!

---

## Verification & Diagnostics

Run **`Run-Compatibility-Check.bat`** from either an Administrator or Standard User account to verify:
- Single touchscreen (`HID_DEVICE_UP:000D_U:0004`) hardware detection
- Installed binary and worker script presence
- NTFS ACL write-protection and anti-ReparsePoint verification on both `C:\Program Files\RobloxTouchscreenSwitch` and `C:\ProgramData\RobloxTouchscreenSwitch`
- Scheduled Task SDDL (`(A;;GRGX;;;AU)`) permissions
- Read-only `system-activity.log` accessibility

---

## Emergency Touchscreen Recovery & Uninstallation

If your external mouse is unplugged while in **MOUSE MODE**:
1. **Shortcut Chord**: With the app window focused, press **`Ctrl + Alt + Shift + T`** on an attached keyboard.
2. **Simply Restart Windows**: The `RestoreTouchOnBoot` task automatically re-enables the touchscreen at boot before the login screen.
3. **Emergency Script**: Run **`Emergency-Restore-Touchscreen.bat`**.
4. **Clean Uninstall**: Right-click **`Uninstall-RobloxTouchSwitch.bat`** and select **Run as administrator**. It automatically re-enables the touchscreen first, deletes the Scheduled Tasks and shortcuts, and removes the application folder.

---

## License

Released under the [MIT License](LICENSE). See [CHANGELOG.md](CHANGELOG.md) for full release notes and security hardening details.
