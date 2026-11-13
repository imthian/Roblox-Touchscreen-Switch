# 🎮 Roblox Touchscreen Switch (Windows 11 Handheld Utility)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows 11](https://img.shields.io/badge/Platform-Windows%2011-0078D6.svg)]()
[![Devices: MSI Claw | ROG Ally | Legion Go](https://img.shields.io/badge/Devices-MSI%20Claw%20%7C%20ASUS%20ROG%20Ally%20%7C%20Windows%20Handhelds-success.svg)]()

A lightweight, open-source Windows 11 graphical utility that fixes the **Roblox external mouse click/grab bug** (especially in games like *Fling Things and People*) on touchscreen gaming handhelds and laptops—such as the **MSI Claw A1M** and **ASUS ROG Ally Z1 Extreme**—while allowing **Standard Windows Users / Microsoft Child Accounts** to toggle the touchscreen **OFF (Mouse Mode)** and **ON (Restore Touch)** with **zero Administrator password prompts**.

---

## 🐛 The Problem

When playing Roblox in docked or desktop mode with an external mouse on Windows 11 touchscreen handhelds (**MSI Claw**, **ASUS ROG Ally**, **Lenovo Legion Go**) or touchscreen laptops:
- The external mouse cursor moves normally.
- Mouse clicks work inside Roblox menus.
- **Mouse clicks and hold/drag actions fail to register during live gameplay** (for example, grabbing and throwing objects or players in *Fling Things and People*).
- Disabling the `HID-compliant touch screen` device in Windows Device Manager immediately fixes the issue—but **Device Manager requires Administrator privileges**, leaving parents with a frustrating dilemma if their child plays on a **Standard User / Microsoft Family Child Account**.

---

## ✨ What This Utility Does

**Roblox Touchscreen Switch** provides a handheld-friendly Windows Forms graphical app (`RobloxTouchSwitch.exe`) backed by narrowly restricted `NT AUTHORITY\SYSTEM` Scheduled Tasks:

1. **🖱️ MOUSE MODE (Disable Touchscreen)**: Temporarily disables the `HID-compliant touch screen` PnP device so external mouse clicks and grabbing work normally in Roblox.
2. **👆 RESTORE TOUCH (Enable Touchscreen)**: Re-enables the touchscreen in 1 second when returning to normal handheld use.
3. **🔒 Standard User / Child Account Safe (No Admin Password Needed)**:
   - Installed once by an Administrator into `C:\Program Files\RobloxTouchscreenSwitch\`.
   - Folder and script NTFS ACLs are locked to **Read & Execute Only** for Standard Users (`FullControl` restricted to `SYSTEM` and `Administrators`).
   - Uses custom Task Scheduler Security Descriptors (`SDDL: (A;;GRGX;;;AU)`) so a Standard User can **trigger** the `DisableTouchscreen` and `EnableTouchscreen` tasks without UAC prompts, but **cannot edit the tasks, modify the scripts, or execute arbitrary commands**.
   - **Never** stores or caches Administrator passwords anywhere.
4. **🛡️ Built-In Hardware & Gaming Safeguards**:
   - Targets **only** `Class -eq 'HIDClass'` and `FriendlyName -eq 'HID-compliant touch screen'`.
   - **Multi-Device Hard Stop**: If more than one matching touchscreen device is found (and no `PinnedInstanceId` was configured by the Administrator), the utility refuses to guess and halts safely.
   - **Automatic Boot Fail-Safe (`RestoreTouchOnBoot`)**: Automatically re-enables the touchscreen every time Windows boots up, so restarting the handheld always restores touch.
   - **Obscure 4-Key Chords**: Uses `Ctrl + Alt + Shift + M` (Mouse Mode) and `Ctrl + Alt + Shift + T` (Restore Touch) only when the window is focused, preventing accidental triggers during gameplay.

---

## 🚀 Quick Installation

1. Download the latest release ZIP (or clone this repository) and extract it to a local folder.
2. Right-click **`Install-RobloxTouchSwitch.bat`** and select **Run as administrator**.
3. The installer automatically:
   - Verifies your `HID-compliant touch screen` hardware node.
   - Compiles the native GUI executable (`C:\Program Files\RobloxTouchscreenSwitch\RobloxTouchSwitch.exe`) using the built-in Windows .NET Framework compiler (`csc.exe`)—**no third-party runtimes required**.
   - Locks down NTFS permissions on `C:\Program Files\RobloxTouchscreenSwitch\`.
   - Registers `\RobloxTouchscreenSwitch\DisableTouchscreen`, `\RobloxTouchscreenSwitch\EnableTouchscreen`, and `\RobloxTouchscreenSwitch\RestoreTouchOnBoot`.
   - Creates shortcuts on the **Public Desktop** and **Start Menu** (`Start -> All Apps -> Roblox Touchscreen Switch`) for all accounts on the PC.
4. Switch to your Standard User / Child Account and launch **Roblox Touchscreen Switch** from the Desktop, Start Menu, **Xbox PC App / Full Screen Experience**, **MSI Center M**, or **ASUS Armoury Crate SE**!

---

## 🧪 Verification & Diagnostics

Run **`Run-Compatibility-Check.bat`** from either an Administrator or Standard User account to verify:
- Single `HID-compliant touch screen` hardware detection
- Installed binary and worker script presence
- NTFS ACL write-protection against standard users
- Scheduled Task SDDL (`(A;;GRGX;;;AU)`) permissions
- Activity log (`C:\ProgramData\RobloxTouchscreenSwitch\activity.log`) status

### Sample Activity Log (Verified on ASUS ROG Ally Z1 Extreme)
```text
[2026-11-04 19:47:18] [GUI:imthi] [INFO] Requesting Scheduled Task '\RobloxTouchscreenSwitch\DisableTouchscreen' for 'MOUSE MODE (Disable Touchscreen)'.
[2026-11-04 19:47:19] [SYSTEM:Disable] [INFO] Starting scheduled action 'Disable' on ROGALLY.
[2026-11-04 19:47:19] [SYSTEM:Disable] [INFO] Verified single target touchscreen: FriendlyName='HID-compliant touch screen', InstanceId='HID\NVTK0603&COL01\4&1F1D96E&0&0000', CurrentStatus='OK'.
[2026-11-04 19:47:20] [SYSTEM:Disable] [SUCCESS] MOUSE MODE ACTIVE: 'HID-compliant touch screen' (HID\NVTK0603&COL01\4&1F1D96E&0&0000) is disabled. External mouse clicks in Roblox are now enabled.
```

---

## 🛟 Emergency Touchscreen Recovery & Uninstallation

If your external mouse is unplugged while in **MOUSE MODE**:
1. **Shortcut Chord**: With the app window focused, press **`Ctrl + Alt + Shift + T`** on an attached keyboard.
2. **Simply Restart Windows**: The `RestoreTouchOnBoot` task automatically re-enables the touchscreen at boot before the login screen.
3. **Emergency Script**: Run **`Emergency-Restore-Touchscreen.bat`**.
4. **Clean Uninstall**: Right-click **`Uninstall-RobloxTouchSwitch.bat`** and select **Run as administrator**. It automatically re-enables the touchscreen first, deletes the Scheduled Tasks and shortcuts, and removes the application folder.

---

## 📄 License

Released under the [MIT License](LICENSE). Free to use, share, and modify!
