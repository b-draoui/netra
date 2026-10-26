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

Fixes after the first tests on real PCs (same version, corrected build):

- **Driver updates** are installed one at a time, so one that fails no longer stops the others, and each failure gives Windows' own reason. Before, one update could make all of them fail with error 0x80131501.
- **Firmware updates** (BIOS, UEFI, built-in software of a device) are listed apart and never installed, as promised.
- **An app whose new version uses another installer** (winget error 0x8A15008E): YSO explains it and offers to reinstall it (remove the old version, install the new one). Automatic updates never do this.
- **Install all of them**: next to "the recommended ones", a choice to install every update found, new major versions included.
- **Battery above 100 %**: the health shown is never above 100 %. After many charge cycles, YSO says the charge gauge needs a reset and how to do it, instead of showing it as healthy.
- "Yesterday" means the calendar day: an update installed yesterday evening is no longer shown as today.
- Copied text no longer shows "Drive C::"; the update list keeps a space between versions and notes.
- **Windows Update cache**: kept when Windows has downloaded updates it has not installed yet (one PC had 9 GB of them): deleting them only made Windows download them again. YSO names the update and says what to do; Analyze no longer counts it.
- Readable names for apps found by their cache layout (Ollama, Outlook, Microsoft Store, Windows Settings instead of "ollama app.exe", "Olk"...).
- Installed copies of 1.0 offer these fixes with their Update button.
