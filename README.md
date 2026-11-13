# Roblox Touchscreen Switch (Windows 11 Handheld Utility)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version: 1.2.1](https://img.shields.io/badge/Version-1.2.1-brightgreen.svg)](CHANGELOG.md)
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

## What This Utility Does (v1.2.1)

**Roblox Touchscreen Switch** provides a handheld-friendly Windows Forms graphical app (`RobloxTouchSwitch.exe`) backed by narrowly restricted `NT AUTHORITY\SYSTEM` Scheduled Tasks:

1. **[ MOUSE MODE ] (Disable Touchscreen)**: Temporarily disables the touchscreen PnP device (`ConfigManagerErrorCode = 22`) so external mouse clicks and grabbing work normally in Roblox.
2. **[ RESTORE TOUCH ] (Enable Touchscreen)**: Re-enables the touchscreen (`ConfigManagerErrorCode = 0`, `Status = OK`) when returning to normal handheld use (the `SYSTEM` worker polls up to 2.5 seconds to confirm driver transition while the GUI polls `status.json` for up to 12.0 seconds).
3. **Hardened Standard User / Child Account Security**:
   - Installed once by an Administrator into `$env:ProgramFiles\RobloxTouchscreenSwitch\`.
   - **Pre-Creation Takeover, Junction & Hardlink Defense**: The installer verifies no `ReparsePoint` (symlink/junction) exists at root or inside `$env:ProgramData\RobloxTouchscreenSwitch\`, creates a clean directory owned by `BUILTIN\Administrators` (`SetOwner`), and locks NTFS ACLs to **Read & Execute Only** for Standard Users (`FullControl` restricted to `SYSTEM` and `Administrators`). The `SYSTEM` worker never recursively deletes directories; it gates all file writes behind `$script:DataDirTrusted` after verifying `ReparsePoint` attributes, `SYSTEM`/`Administrators` ownership, non-writable user ACLs, and NTFS hardlink counts (`fsutil hardlink list`).
   - **Separated & Rotated Logs**: The `SYSTEM` worker writes tamper-proof UTF-8 (no-BOM) audit records to `$env:ProgramData\RobloxTouchscreenSwitch\system-activity.log` and `status.json` (auto-rotating at `512 KB`), while the user GUI logs its own events to `%LOCALAPPDATA%\RobloxTouchscreenSwitch\gui-activity.log`.
   - **Custom Task Scheduler SDDL (`(A;;GRGX;;;AU)`)**: Grants Authenticated Users **Read & Run (`GRGX`)** rights on `\RobloxTouchscreenSwitch\DisableTouchscreen` and `\RobloxTouchscreenSwitch\EnableTouchscreen` with zero edit/delete rights and **zero stored Administrator passwords**.
4. **Built-In Hardware & Gaming Safeguards**:
   - **Locale-Independent Touchscreen Detection**: Matches devices in `PNPClass = 'HIDClass'` using the standard HID Digitizer/Touchscreen usage (`HID_DEVICE_UP:000D_U:0004`) as well as `HID-compliant touch screen`, working across all Windows 11 display languages.
   - **Multi-Node Composite Panel Support & Strict Pin Enforcement**: Some touch panels expose multiple `HID-compliant touch screen` nodes. During installation, the Administrator can pin a single node (`1`), multiple composite nodes (`1,2`), or `ALL` (toggled via a best-effort loop so every node is attempted). If a pinned device is ever disconnected, the utility fails closed with `ERR_PINNED_MISSING` rather than guessing or disabling another connected touch monitor.
   - **Exact Error Code 22 Checking**: Distinguishes between an intentionally disabled touchscreen (`ErrorCode == 22`) and an unexpected driver fault (any other non-zero error code).
   - **Automatic Boot Fail-Safe (`RestoreTouchOnBoot`)**: Automatically re-enables the touchscreen every time Windows boots up, so restarting the handheld always restores touch.
   - **Obscure 4-Key Chords**: Uses `Ctrl + Alt + Shift + M` (Mouse Mode) and `Ctrl + Alt + Shift + T` (Restore Touch) only when the window is focused, preventing accidental triggers during gameplay.

---

## Quick Installation

1. Log into your **Administrator account** and extract **`ROBLOX TOUCHSCREEN SWITCH (v1.2.1).zip`** (or clone this repository) inside your **Administrator account's own profile folder** (e.g., `C:\Users\<AdminUser>\Downloads\RobloxTouchscreenSwitch`)—never extract into a shared or child-writable directory before running the installer.
2. Right-click **`Install-RobloxTouchSwitch.bat`** and select **Run as administrator**.
3. The installer automatically:
   - Verifies your touchscreen hardware node(s) (`HID_DEVICE_UP:000D_U:0004`).
   - Compiles the native GUI executable (`$env:ProgramFiles\RobloxTouchscreenSwitch\RobloxTouchSwitch.exe`) using the built-in Windows .NET Framework compiler (`csc.exe`)—**no third-party runtimes required**. *(Note: Because the binary is compiled locally on your machine during install, environments enforcing strict enterprise AppLocker or Defender ASR rules may require whitelisting `$env:ProgramFiles\RobloxTouchscreenSwitch\RobloxTouchSwitch.exe`.)*
   - Sets `Administrators` ownership and locks down NTFS permissions on `$env:ProgramFiles\RobloxTouchscreenSwitch\` and `$env:ProgramData\RobloxTouchscreenSwitch\`.
   - Registers `\RobloxTouchscreenSwitch\DisableTouchscreen`, `\RobloxTouchscreenSwitch\EnableTouchscreen`, and `\RobloxTouchscreenSwitch\RestoreTouchOnBoot` using `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`.
   - Creates shortcuts on the **Public Desktop** and **Start Menu** (`Start -> All Apps -> Roblox Touchscreen Switch`) for all accounts on the PC.
4. Switch to your Standard User / Child Account and launch **Roblox Touchscreen Switch** from the Desktop, Start Menu, **Xbox PC App / Full Screen Experience**, **MSI Center M**, or **ASUS Armoury Crate SE**!

---

## Verification & Diagnostics

Run **`Run-Compatibility-Check.bat`** from either an Administrator or Standard User account to verify:
- Single or pinned touchscreen (`HID_DEVICE_UP:000D_U:0004`) hardware detection
- Installed binary and worker script presence
- Trusted `Administrators`/`SYSTEM` ownership, NTFS ACL write-protection, and anti-ReparsePoint verification on both `$env:ProgramFiles\RobloxTouchscreenSwitch` and `$env:ProgramData\RobloxTouchscreenSwitch`
- Scheduled Task SDDL (`(A;;GRGX;;;AU)`) permissions
- Read-only `system-activity.log` accessibility

### Release Archive Checksum (v1.2.1)
- `ROBLOX TOUCHSCREEN SWITCH (v1.2.1).zip` SHA-256: `44c6b9d7e1d41ff4ba74322b33b71af27ad95984abb5966f3403197f5441920e`
- Repository file hashes (with Unix LF line endings for `sha256sum -c SHA256SUMS.txt`): see [`SHA256SUMS.txt`](SHA256SUMS.txt).

---

## Emergency Touchscreen Recovery & Uninstallation

If your external mouse is unplugged while in **MOUSE MODE**:
1. **Shortcut Chord**: With the app window focused, press **`Ctrl + Alt + Shift + T`** on an attached keyboard.
2. **Simply Restart Windows**: The `RestoreTouchOnBoot` task automatically re-enables the touchscreen at boot before the login screen.
3. **Self-Verifying Emergency Script**: Run **`Emergency-Restore-Touchscreen.bat`**, which triggers the restore task (and direct PnP bus rescan if needed) and verifies `ConfigManagerErrorCode == 0` and `Status == 'OK'`.
4. **Clean Uninstall**: Right-click **`Uninstall-RobloxTouchSwitch.bat`** and select **Run as administrator**. It automatically re-enables the pinned/single touchscreen first, deletes the Scheduled Tasks and shortcuts, and removes the application folder.

---

## License

Released under the [MIT License](LICENSE). See [CHANGELOG.md](CHANGELOG.md) for full release notes and security hardening details.
