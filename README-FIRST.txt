========================================================================
ROBLOX TOUCHSCREEN SWITCH (v1.0.0) - QUICK START README
Target Devices: MSI Claw A1M (Intel), ASUS ROG Ally Z1 Extreme, & Windows 11 Handhelds
========================================================================

1. WHAT THIS UTILITY DOES
   Fixes the Roblox external mouse click/grab bug (such as in "Fling Things
   and People") on Windows 11 touchscreen handhelds and laptops by allowing
   a Standard User / Microsoft Child Account to safely toggle the
   "HID-compliant touch screen" device OFF (Mouse Mode) and ON (Restore Touch)
   without needing the Administrator password.

2. PACKAGE CONTENTS
   - Install-RobloxTouchSwitch.bat     : Run once as Administrator to install.
   - Uninstall-RobloxTouchSwitch.bat   : Run as Administrator to cleanly remove.
   - Emergency-Restore-Touchscreen.bat : Immediate recovery tool to re-enable touch.
   - Run-Compatibility-Check.bat       : Verifies hardware, ACLs, and task security.
   - core\Invoke-TouchscreenAction.ps1 : Protected SYSTEM worker with hardware safeguards.
   - core\RobloxTouchSwitchApp.cs      : Native Windows 11 GUI source (compiled on install).
   - assets\RobloxTouchSwitch.ico      : Application icon for Desktop & Start Menu.
   - assets\Xbox_Library_CoverArt.png  : Poster art for Xbox PC App / Handheld Launchers.

3. QUICK INSTALLATION (ON MSI CLAW A1M OR ASUS ROG ALLY)
   Step 1: Extract this entire ZIP folder to a local folder (e.g., Desktop or Downloads).
   Step 2: Log into your Administrator account (or stay in your son's account and
           approve the Windows UAC prompt with your Administrator credentials).
   Step 3: Double-click "Install-RobloxTouchSwitch.bat".
   Step 4: Switch to your son's Standard Microsoft Child account. He can now launch
           "Roblox Touchscreen Switch" from the Desktop, Start Menu, or Xbox App
           with zero password prompts!

See the accompanying PDF manual ("Roblox_Touchscreen_Switch_Admin_and_Deployment_Guide.pdf")
for complete testing instructions, security architecture details, Xbox Full Screen
Experience / MSI Center M / Armoury Crate SE setup, and emergency recovery steps.
