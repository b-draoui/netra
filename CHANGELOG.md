# Changelog

## 1.0 - 2026-10-25
First public version.

- **A window for everything.** Home shows the health of the PC (disk space and wear, battery, Windows Update, antivirus, startup programs, last cleanup, updates) with the button that helps. **Analyze** shows what can be freed and deletes nothing; **Clean everything** runs the full maintenance after showing what it will do.
- **Clean**: every part on its own line with the space it frees, ticked or not. What cannot be undone (old driver versions, Recycle Bin) starts unticked. Options: restore point first, close the apps that keep files in use, optimize drives, install updates.
- **28 tools** in one place: cleaning (temporary files, browser and app caches, system junk, Windows Update cache, GPU shader caches, deep clean, old driver versions, Windows.old, hibernation file), network (check, DNS, reset), startup programs, boot time, health report, crashes, security check, drivers, disk check, memory test, Windows repair, space finder, app and driver updates (manual, notify or automatic), restore points, weekly auto-clean, history, self-test, problem reports.
- Each tool shows its progress, asks its questions with buttons, and has a **Stop** button. The work runs apart from the window, so the window stays usable while it works.
- **Update button**: when a new version is published on GitHub, YSO offers it. It is downloaded over HTTPS, checked against its SHA-256 file and read by PowerShell before it replaces YSO. The check can be turned off in Settings.
- **Installation in one line** (`install.ps1`): Program Files, Start menu, Desktop, and Settings > Apps > Installed apps with Uninstall, without "Windows protected your PC".
- English and French. Requires Windows 10 version 1607 or later, or Windows 11 (Intel, AMD or ARM).
- Tested on every change: about 600 automated checks on Linux, and the window, the self-test, the update check and the installation on Windows Server 2022, Windows Server 2025 and Windows 11.
