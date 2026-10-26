<#
.SYNOPSIS
    YSO - Your System Optimizer 1.0: a Windows cleaner, health check, updater and maintenance tool.

.DESCRIPTION
    One PowerShell script with a window (WPF). English by default; French in Settings.

    Design rules
      * Measure everything: each cleaning reports files removed and space freed.
      * Never touch personal data: Downloads, Documents, cookies, passwords, history,
        bookmarks. Recycle Bin, Windows.old and the hibernation file only after you confirm.
      * Skip files in use, keep recent temp files, respect your "never touch" folders.
      * Never follow junctions / symlinks while deleting; refuse system and profile roots.
      * Diagnostics are read-only. Anything that changes a setting asks first.
      * Every run is logged to %ProgramData%\YSO\Logs.
      * Errors never close YSO: they are saved to errors.log instead.
      * Self-test (T) checks every feature on the PC it runs on; Report a problem (P)
        packs the results and logs, with personal details removed, into one zip.
      * Updates (28): apps with winget, drivers with Windows Update - when you start
        them, or automatically on a schedule. Never restarts the PC, never updates the BIOS.
      * Deliberately absent: registry cleaners, RAM boosters, service killing,
        removing Windows components and network "tweaks".

.EXAMPLE
    Double-click YSO.bat (keep it in the same folder as this file): the YSO window opens.
    Installed with install.ps1, YSO is in the Start menu and on the Desktop instead.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\YSO.ps1 -DryRun
    Analyze-only mode: shows what would be freed, deletes nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\YSO.ps1 -Auto
    Unattended clean of the categories chosen in Settings (used by the weekly task).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\YSO.ps1 -SelfTest
    Runs the self-test without the menu and exits with the number of broken checks
    (0 = everything works). Meant for automated testing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\YSO.ps1 -AutoUpdate
    Installs the app and driver updates chosen in Updates (28) (used by the automatic
    updates task). With -DryRun it only lists them and writes a report.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\YSO.ps1 -Install
    Installs YSO like any program: Program Files, Start menu, Desktop, and "Installed apps"
    (where -Uninstall removes it again). install.ps1 does this after downloading YSO.
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$DryRun,
    [switch]$SelfTest,
    [switch]$AutoUpdate,
    [switch]$Console,       # the text menu (used by YSO itself when the window cannot open)
    [switch]$Install,       # install YSO (Program Files, Start menu, Desktop, Installed apps)
    [switch]$Uninstall,     # remove it again (asks whether to keep the history and settings)
    [switch]$Engine,        # used by the window: loads YSO's functions only, in its second PowerShell
    [string]$Snapshot = ''  # for automated testing: draws every page of the window into PNG files in this folder
)

# ==================================================================
#  Start-up checks. Plain code on purpose: it has to work even where
#  PowerShell is restricted, so it can explain the problem instead of crashing.
#  Exit code 3 = "stopped on purpose, the reason was shown".
# ==================================================================
$ysoFr = $false   # English unless French was chosen in Settings (or 'auto' on a French Windows)
try {
    $ysoSettingsFile = Join-Path "$env:ProgramData" 'YSO\settings.json'
    if (Test-Path -LiteralPath $ysoSettingsFile) {
        $ysoPref = "$((Get-Content -LiteralPath $ysoSettingsFile -Raw | ConvertFrom-Json).Language)"
        if ($ysoPref -eq 'fr') { $ysoFr = $true }
        elseif ($ysoPref -eq 'auto') { $ysoFr = ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr') }
    }
} catch { }
$ysoStop = $null
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    $mode = "$($ExecutionContext.SessionState.LanguageMode)"
    if ($ysoFr) {
        $ysoStop = @(
            "PowerShell est en mode restreint sur ce PC ($mode), YSO ne peut donc pas fonctionner.",
            "Cela arrive surtout sur les PC gérés par une école ou une entreprise, et peut aussi venir de Smart App Control (Sécurité Windows).",
            "Rien n'a été modifié sur ce PC."
        )
    } else {
        $ysoStop = @(
            "PowerShell is in restricted mode on this PC ($mode), so YSO cannot run.",
            'This mostly happens on PCs managed by a school or company, and may also come from Smart App Control (Windows Security).',
            'Nothing was changed on this PC.'
        )
    }
} elseif ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    $found = "$($PSVersionTable.PSVersion)"
    if ($ysoFr) {
        $ysoStop = @(
            'YSO a besoin de Windows PowerShell 5.1 (inclus dans Windows 10 version 1607 ou plus récente, et dans Windows 11).',
            "Version trouvée : $found. Rien n'a été modifié."
        )
    } else {
        $ysoStop = @(
            'YSO needs Windows PowerShell 5.1 (included in Windows 10 version 1607 or later, and in Windows 11).',
            "Version found: $found. Nothing was changed."
        )
    }
}
if ($ysoStop) {
    Write-Host ''
    $first = $true
    foreach ($line in $ysoStop) {
        if ($first) { Write-Host "  [!] $line" -ForegroundColor Red; $first = $false }
        else { Write-Host "      $line" }
    }
    Write-Host ''
    if (-not $Auto -and -not $SelfTest -and -not $AutoUpdate) { [void](Read-Host '  OK') }
    exit 3
}

# ==================================================================
#  Elevation: relaunch as administrator if needed (one UAC prompt)
# ==================================================================
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Auto)   { $relaunch += '-Auto' }
    if ($DryRun) { $relaunch += '-DryRun' }
    if ($SelfTest) { $relaunch += '-SelfTest' }
    if ($AutoUpdate) { $relaunch += '-AutoUpdate' }
    if ($Console) { $relaunch += '-Console' }
    if ($Install) { $relaunch += '-Install' }
    if ($Uninstall) { $relaunch += '-Uninstall' }
    # The window needs no console: the elevated PowerShell starts hidden (it shows its console
    # again by itself if the window cannot open).
    $hidden = -not ($Auto -or $SelfTest -or $AutoUpdate -or $Console)
    try {
        if ($hidden) { Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunch -WindowStyle Hidden -ErrorAction Stop }
        else { Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunch -ErrorAction Stop }
    } catch {
        $msg = 'Administrator rights are required (the UAC prompt was declined).'
        if ($ysoFr) {
            $msg = "Les droits administrateur sont nécessaires (la demande UAC a été refusée)."
        }
        if ($hidden) {
            # started from the Start menu or the Desktop: there may be no console to write in
            try {
                Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
                [void][System.Windows.MessageBox]::Show($msg, 'YSO', 'OK', 'Warning')
                exit 3
            } catch { }
        }
        Write-Host ''
        Write-Host "  [!] $msg" -ForegroundColor Red
        Write-Host ''
        [void](Read-Host '  OK')
        exit 3
    }
    exit 0
}

# ==================================================================
#  Translation helpers (defined first: used while setting up state)
# ==================================================================
$script:Lang = 'en'
$script:FR   = @{}

function L {
    # Returns the French text when French is active, then fills {0} {1} ... with extra arguments.
    #   L 'Freed {0}' $size
    param([string]$Text)
    $out = $Text
    if ($script:Lang -eq 'fr' -and $Text -and $script:FR.ContainsKey($Text)) { $out = $script:FR[$Text] }
    if ($args.Count -gt 0) { return ($out -f $args) }
    return $out
}

function N([string]$Text) { return $Text }   # marks text that is translated later, when displayed

# ==================================================================
#  Settings & state
# ==================================================================
$script:Version       = '1.0'
$script:DataDir       = Join-Path $env:ProgramData 'YSO'
$script:LogDir        = Join-Path $script:DataDir 'Logs'
$script:SettingsPath  = Join-Path $script:DataDir 'settings.json'
$script:HistoryPath   = Join-Path $script:DataDir 'history.csv'
$script:DnsBackupPath = Join-Path $script:DataDir 'dns-backup.json'
$script:TaskName      = 'YSO Weekly Clean'
$script:UpdateTaskName = 'YSO Auto Updates'
$script:UpdateHistoryPath = Join-Path $script:DataDir 'updates.csv'
$script:ReportDir     = Join-Path $script:DataDir 'Reports'
$script:InstallDir    = [System.IO.Path]::Combine("$env:ProgramFiles", 'YSO')
$script:UninstallKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YSO'
$script:ReleaseRepo   = 'b-draoui/yso'   # where new versions of YSO are published (GitHub Releases)
$script:ProjectUrl    = 'https://github.com/' + $script:ReleaseRepo
$script:UpdateCheckPath = Join-Path $script:DataDir 'yso-version-check.json'
$script:SelfPath      = $PSCommandPath   # this file: compared with the published one (same version, newer build)
$script:ErrorLogPath  = Join-Path $script:DataDir 'errors.log'
$script:OsMajor       = [Environment]::OSVersion.Version.Major
$script:Build         = [Environment]::OSVersion.Version.Build
$script:OsText        = 'Windows'
$script:IsServer      = $false
$script:ErrorCount    = 0
$script:TranscriptOn  = $false
$script:Checks        = New-Object System.Collections.Generic.List[object]
$script:LastSelfTestBroken = 0
$script:Uncovered     = @()
$script:LastEventError = $null
$script:WingetVersion = $null
$script:WingetVersionRead = $false
$script:UpdateMutex   = $null
$script:WuSession     = $null
$script:ProgressClock = [System.Diagnostics.Stopwatch]::StartNew()
$script:ProgressHandler = $null   # set by a graphical interface to receive progress instead of the console
$script:ProgressParent = -1
$script:StopSignal    = $null    # set by the window: a shared table whose 'Stop' entry asks the running job to stop
$script:LastRun       = $null    # what the last option did (status, results, free space): read by the window
$script:GuiFailure    = ''       # why the window could not open (shown before the console menu opens instead)
# Every key of the menu that runs an option (Invoke-MenuOption); M, L and Q only change the menu itself.
$script:MenuKeys      = @(@(1..28 | ForEach-Object { "$_" }) + @('A', 'F', 'R', 'S', 'H', 'T', 'P', 'O'))
$script:HealthCache   = $null
$script:DetectedApps  = @()
$script:DryRun        = [bool]$DryRun
$script:Results       = New-Object System.Collections.Generic.List[object]
$script:Profiles      = @()
$script:Settings      = $null
$script:SettingsError = $false
$script:SigCache      = @{}
$script:BrowserProcs  = @('chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi')
$script:AppProcs      = @('Code', 'Discord', 'Teams', 'ms-teams', 'Spotify', 'steam', 'EpicGamesLauncher')
# Apps YSO may offer to close: closing them loses nothing. Never VS Code (unsaved work),
# Teams (calls) or Steam (games and downloads) - for those it only warns.
$script:SafeToCloseApps = @('Spotify', 'Discord', 'EpicGamesLauncher')
$script:ScriptHosts   = @('powershell.exe', 'pwsh.exe', 'cmd.exe', 'wscript.exe', 'cscript.exe', 'mshta.exe', 'rundll32.exe', 'regsvr32.exe')

# Our own copy of the hidden "Ultimate Performance" plan gets a fixed GUID,
# so choosing it again never piles up duplicate plans.
$script:PlanUltimateTemplate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$script:PlanUltimateYso    = '4f7a2c19-8b3e-4d6a-9c51-2e8f0b7d3a64'
$script:PlanHigh             = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:PlanBalanced         = '381b4222-f694-41f0-9685-ff5bb260df2e'

# Disk Cleanup handlers that are safe to run unattended. Anything not listed is
# never enabled - in particular "DownloadsFolder" (deletes your Downloads!),
# "Recycle Bin", "Previous Installations" (only via option 9, after asking),
# "Windows ESD installation files" (needed by Reset this PC),
# "User file versions" (File History) and "Device Driver Packages".
$script:SafeCleanupHandlers = @(
    'Active Setup Temp Folders', 'BranchCache', 'Content Indexer Cleaner',
    'D3D Shader Cache', 'Delivery Optimization Files',
    'Diagnostic Data Viewer database files', 'Downloaded Program Files',
    'Feedback Hub Archive log files', 'Internet Cache Files', 'Offline Pages Files',
    'Old ChkDsk Files', 'RetailDemo Offline Content', 'Setup Log Files',
    'System error memory dump files', 'System error minidump files',
    'Temporary Files', 'Temporary Setup Files', 'Thumbnail Cache', 'Update Cleanup',
    'Upgrade Discarded Files', 'Windows Defender', 'Windows Error Reporting Files',
    'Windows Upgrade Log Files'
)

# Categories the weekly auto-clean can run (settings key -> display name).
$script:AutoCleanNames = [ordered]@{
    TempFiles     = (N 'Temporary files')
    BrowserCaches = (N 'Browser caches')
    SystemJunk    = (N 'System junk')
    UpdateCache   = (N 'Windows Update cache')
    ShaderCaches  = (N 'GPU shader caches')
    DevAppCaches  = (N 'Developer & app caches')
    SiteOfflineCaches = (N 'Site offline caches')
}

$script:DnsProviders = [ordered]@{
    '1' = @{ Name = 'Cloudflare'; Note = (N 'fast, privacy-focused');        Servers = @('1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001') }
    '2' = @{ Name = 'Google';     Note = (N 'fast, very reliable');          Servers = @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844') }
    '3' = @{ Name = 'Quad9';      Note = (N 'blocks known malicious sites'); Servers = @('9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9') }
}

# Device Manager problem codes worth explaining (22 = disabled, 45 = unplugged: not problems).
$script:DeviceProblems = @{
    1  = (N 'not configured correctly');           3  = (N 'driver may be corrupted')
    10 = (N 'cannot start');                       12 = (N 'not enough free resources')
    14 = (N 'needs a restart');                    18 = (N 'drivers need to be reinstalled')
    19 = (N 'configuration is damaged');           21 = (N 'being removed')
    24 = (N 'not present or drivers missing');     28 = (N 'drivers not installed')
    29 = (N 'disabled in the firmware');           31 = (N 'not working properly')
    32 = (N 'driver service is disabled');         37 = (N 'driver failed to start')
    39 = (N 'driver missing or corrupted');        43 = (N 'stopped by Windows after reporting problems')
    48 = (N 'blocked: known compatibility problem'); 52 = (N 'driver signature cannot be verified')
}

# ==================================================================
#  UI helpers (all of them translate the text they are given)
# ==================================================================
function Write-Step([string]$Text) { Write-Host ('  [*] ' + (L $Text)) -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host ('  [+] ' + (L $Text)) -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host ('  [!] ' + (L $Text)) -ForegroundColor Yellow }
function Write-Bad([string]$Text)  { Write-Host ('  [x] ' + (L $Text)) -ForegroundColor Red }
function Write-Info([string]$Text) { Write-Host ('      ' + (L $Text)) -ForegroundColor Gray }

function Write-YsoProgress {
    # The one place long jobs report progress: a bar at the top of the console today; a graphical
    # interface only has to set $script:ProgressHandler. Throttled: redrawing too often slows work down.
    param([string]$Activity, [string]$Status = '', [int]$Percent = -1, [switch]$Completed, [switch]$Force, [int]$Id = 1, [int]$ParentId = -2)
    if (-not $Completed) { Assert-NotStopped }   # long jobs report progress often: the place where Stop takes effect
    if ($script:ProgressHandler) { & $script:ProgressHandler $Activity $Status $Percent ([bool]$Completed) $Id; return }
    if (Test-Unattended) { return }
    if ($ParentId -eq -2) { $ParentId = $script:ProgressParent }   # inside F or A: shown under their own bar
    $p = @{ Id = $Id; Activity = $(if ($Activity) { $Activity } else { ' ' }) }
    if ($ParentId -ge 0 -and $ParentId -ne $Id) { $p.ParentId = $ParentId }
    if ($Completed) { Write-Progress @p -Completed; return }
    if (-not $Force -and $script:ProgressClock.ElapsedMilliseconds -lt 200) { return }
    $script:ProgressClock.Restart()
    if ($Status) { $p.Status = $Status }
    if ($Percent -ge 0) { $p.PercentComplete = [math]::Min(100, $Percent) }
    Write-Progress @p
}

function Wait-ProcessWithProgress($Process, [string]$Activity) {
    # For Windows tools that show no percentage (Disk Cleanup, DISM): at least the time spent.
    if (-not $Process) { return }
    $t = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        while (-not $Process.WaitForExit(1000)) {
            Write-YsoProgress -Activity $Activity -Status (L 'working for {0} min {1:00} s' ([int][math]::Floor($t.Elapsed.TotalMinutes)) $t.Elapsed.Seconds) -Force
        }
    } catch {
        # Stopped from the window: a Windows tool is never killed halfway, it finishes on its own.
        if (Test-StopError $_) { Write-Warn (L '{0} keeps running in the background and finishes by itself.' $Activity) }
        throw
    } finally {
        Write-YsoProgress -Activity $Activity -Completed
    }
}

function Assert-NotStopped {
    # The window's Stop button: the running job ends at its next progress report.
    if ($script:StopSignal -and $script:StopSignal['Stop']) {
        throw (New-Object System.OperationCanceledException (L 'Stopped at your request.'))
    }
}

function Test-StopError($ErrorRecord) {
    # True when an error is the Stop button (also when PowerShell wrapped it in another error).
    $e = $ErrorRecord
    if ($e -is [System.Management.Automation.ErrorRecord]) { $e = $e.Exception }
    while ($e) {
        if ($e -is [System.OperationCanceledException]) { return $true }
        $e = $e.InnerException
    }
    return $false
}

function Invoke-Plan {
    # Runs the steps of a long job (F, A) one by one, with an overall progress bar; a failing step is
    # saved and skipped (Invoke-Step). $Steps: @( @('context', 'Name shown', { code }), ... )
    param([string]$Activity, [object[]]$Steps)
    $script:ProgressParent = 0
    try {
        for ($i = 0; $i -lt $Steps.Count; $i++) {
            Write-YsoProgress -Id 0 -ParentId -1 -Activity $Activity -Status (L 'step {0} of {1}: {2}' ($i + 1) $Steps.Count (L $Steps[$i][1])) -Percent (100 * $i / $Steps.Count) -Force
            Invoke-Step $Steps[$i][0] $Steps[$i][2]
        }
    } finally {
        Write-YsoProgress -Id 0 -ParentId -1 -Activity $Activity -Completed
        $script:ProgressParent = -1
    }
}

function Write-Section([string]$Title) {
    Write-Host ''
    Write-Host ('  ' + (L $Title)) -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 64)) -ForegroundColor DarkGray
}

function Write-Kv {
    param([string]$Key, $Value, [string]$Color = 'Gray')
    if (-not $Color) { $Color = 'Gray' }
    Write-Host ('  {0,-29} ' -f (L $Key)) -NoNewline -ForegroundColor DarkGray
    Write-Host "$Value" -ForegroundColor $Color
}

function Write-Option([string]$Key, [string]$Text) {
    Write-Host ('   {0,-4}' -f $Key) -NoNewline -ForegroundColor Green
    Write-Host (L $Text)
}

function Read-Choice([string]$Prompt = (N 'Choose')) {
    return "$(Read-Host ('  ' + (L $Prompt)))".Trim().ToUpper()
}

function Test-Unattended {
    # Started by a scheduled task or for automated testing: nobody is there to answer.
    return [bool]($Auto -or $AutoUpdate -or $SelfTest)
}

function Confirm-Action {
    param([string]$Question, [bool]$Default = $false)
    if (Test-Unattended) { return $Default }
    $hint = if ($Default) { L '[Y/n]' } else { L '[y/N]' }
    $answer = "$(Read-Host ('  [?] ' + (L $Question) + ' ' + $hint))".Trim().ToUpper()
    if (-not $answer) { return $Default }
    return ($answer.StartsWith('Y') -or $answer.StartsWith('O'))   # O = oui
}

function Wait-Key {
    if (Test-Unattended) { return }
    Write-Host ''
    [void](Read-Host ('  ' + (L 'Press Enter to return to the menu')))
}

function Format-Size([double]$Bytes) {
    $u = if ($script:Lang -eq 'fr') { @('o', 'Ko', 'Mo', 'Go') } else { @('B', 'KB', 'MB', 'GB') }
    if ($Bytes -ge 1GB) { return ('{0:N2} ' -f ($Bytes / 1GB)) + $u[3] }
    if ($Bytes -ge 1MB) { return ('{0:N1} ' -f ($Bytes / 1MB)) + $u[2] }
    if ($Bytes -ge 1KB) { return ('{0:N0} ' -f ($Bytes / 1KB)) + $u[1] }
    return ('{0:N0} ' -f $Bytes) + $u[0]
}

function Format-OnOff($Value) { if ($Value) { return (L 'ON') } else { return (L 'OFF') } }
function Get-StatusColor($Good, [string]$BadColor = 'Red') { if ($Good) { return 'Green' } else { return $BadColor } }

function Get-Truncated([string]$Text, [int]$Max) {
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max - 3) + '...'
}

function Get-ShortPath([string]$Path, [int]$Max = 70) {
    if ($null -eq $Path) { return '' }
    if ($Path.Length -le $Max) { return $Path }
    return '...' + $Path.Substring($Path.Length - ($Max - 3))
}

# ==================================================================
#  System helpers
# ==================================================================
function Esc([string]$Text) { [Management.Automation.WildcardPattern]::Escape($Text) }

function Get-FixedVolumes {
    return @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | Sort-Object DriveLetter)
}

function Get-FreeBytes {
    # Free space of ALL internal drives added together (what cleaning changes, wherever it happens).
    $sum = [long]0
    foreach ($v in Get-FixedVolumes) { $sum += [long]$v.SizeRemaining }
    return $sum
}

function Get-FreeSpaceText {
    # Free space drive by drive, e.g. "C: 142,04 Go, D: 3,20 Go" - matches what Explorer shows.
    $v = Get-FixedVolumes
    if ($v.Count -eq 0) { return '?' }
    return (($v | ForEach-Object { '{0}: {1}' -f $_.DriveLetter, (Format-Size $_.SizeRemaining) }) -join ', ')
}

function Get-DriveLettersText {
    $v = Get-FixedVolumes
    if ($v.Count -eq 0) { return '?' }
    return (($v | ForEach-Object { "$($_.DriveLetter):" }) -join ' + ')
}

function Get-UptimeText {
    try {
        $u = (Get-Date) - (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        return ('{0}d {1}h' -f $u.Days, $u.Hours)
    } catch { return '?' }
}

function Get-BatteryHealth {
    # Returns Design, Full, Percent, Cycles - or $null when the battery does not tell.
    $design = 0; $full = 0; $cycles = $null
    try {
        $design = [double](@(Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStaticData -ErrorAction Stop)[0].DesignedCapacity)
        $full   = [double](@(Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop)[0].FullChargedCapacity)
    } catch { }
    try {
        $c = [int](@(Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryCycleCount -ErrorAction Stop)[0].CycleCount)
        if ($c -gt 0) { $cycles = $c }   # 0 = not counted
    } catch { }
    if (-not ($design -gt 0 -and $full -gt 0) -and $env:TEMP) {
        $xmlPath = Join-Path $env:TEMP ('yso-battery_{0}.xml' -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        try {
            & powercfg.exe /batteryreport /xml /output "$xmlPath" 2>&1 | Out-Null
            if (Test-Path -LiteralPath $xmlPath) {
                [xml]$x = Get-Content -LiteralPath $xmlPath -Raw
                $bats = @($x.BatteryReport.Batteries.Battery | Where-Object { $_ })
                $design = [double](($bats | ForEach-Object { [double]"$($_.DesignCapacity)" } | Measure-Object -Sum).Sum)
                $full   = [double](($bats | ForEach-Object { [double]"$($_.FullChargeCapacity)" } | Measure-Object -Sum).Sum)
                if ($null -eq $cycles -and $bats.Count -gt 0 -and "$($bats[0].CycleCount)" -match '^\d+$' -and [int]"$($bats[0].CycleCount)" -gt 0) { $cycles = [int]"$($bats[0].CycleCount)" }   # 0 = not counted
            }
        } catch { } finally { Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue }
    }
    if ($design -gt 0 -and $full -gt 0) {
        # Reported: what the battery says. Percent: never above 100 (a battery cannot be better than new).
        $reported = [int][math]::Round(100 * $full / $design)
        return [pscustomobject]@{ Design = $design; Full = $full; Reported = $reported; Percent = [math]::Min(100, $reported); Cycles = $cycles }
    }
    return $null
}

function Get-BatteryVerdict($Battery) {
    # What to say about a battery. Above 100 %: a new battery can hold a little more than its rated
    # capacity, but after many charge cycles it means the battery's charge gauge is off.
    $p = [int]$Battery.Reported
    if ($p -gt 100) {
        if ($null -ne $Battery.Cycles -and $Battery.Cycles -ge 100) {
            return [pscustomobject]@{ Level = 'Info'; Text = (L 'reports {0} % after {1} charge cycles: its charge gauge needs a reset' $p $Battery.Cycles); GaugeOff = $true }
        }
        return [pscustomobject]@{ Level = 'Good'; Text = (L 'as good as new (it reports {0} %)' $p); GaugeOff = $false }
    }
    $lvl = if ($p -lt 60) { 'Bad' } elseif ($p -lt 80) { 'Warn' } else { 'Good' }
    return [pscustomobject]@{ Level = $lvl; Text = (L '{0} % of its original capacity' $p); GaugeOff = $false }
}

function Test-IsLaptop {
    try { return (@(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop).Count -gt 0) } catch { return $false }
}

function Get-ProfilePaths {
    # Real user profiles (skips SYSTEM / service accounts), wherever they live.
    $list = @()
    try {
        $list = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop |
            Where-Object { -not $_.Special -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) } |
            ForEach-Object { $_.LocalPath })
    } catch { }
    if ($list.Count -eq 0 -and $env:USERPROFILE) { $list = @($env:USERPROFILE) }
    return @($list | Sort-Object -Unique)
}

function Test-PendingReboot {
    return (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
           (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

function Test-ProtectedPath([string]$Path) {
    # Safety net: never purge a drive root, Windows, Program Files, Users or a profile root.
    $p = $Path.TrimEnd('\', '/')
    if ($p.Length -le 3) { return $true }
    $blocked = @($env:SystemDrive, $env:WINDIR, "$env:WINDIR\System32", $env:ProgramFiles,
                 ${env:ProgramFiles(x86)}, $env:ProgramData, "$env:SystemDrive\Users") + $script:Profiles
    foreach ($b in $blocked) {
        if ($b -and ($p -ieq $b.TrimEnd('\', '/'))) { return $true }
    }
    return $false
}

function Test-Excluded([string]$Path) {
    # Your "never touch" folders (Settings > O).
    foreach ($x in @($script:Settings.ExcludeFolders)) {
        if (-not $x) { continue }
        $b = "$x".TrimEnd('\', '/')
        if ($Path -ieq $b -or
            $Path.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $Path.StartsWith($b + '/', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# ==================================================================
#  Settings file  (%ProgramData%\YSO\settings.json)
# ==================================================================
function Get-DefaultSettings {
    return [ordered]@{
        Language        = 'en'      # English by default; French (or 'auto' = like Windows) in Settings
        TempMinAgeHours = 24
        LogMinAgeDays   = 14
        ExcludeFolders  = [string[]]@()
        AutoClean       = [ordered]@{
            TempFiles = $true; BrowserCaches = $true; SystemJunk = $true; UpdateCache = $true
            ShaderCaches = $false; DevAppCaches = $false; SiteOfflineCaches = $false
        }
        MenuMode        = 'simple'  # console menu: 'simple' (essentials + PC health) or 'advanced' (every option)
        CheckForUpdates = $true     # the window asks GitHub for a newer YSO (at most once an hour)
        Updates         = [ordered]@{
            Mode = 'manual'           # 'manual', 'notify' (tells you, installs nothing) or 'auto'
            Frequency = 'weekly'; Day = 'Sunday'; Time = '12:00'   # used when updates run on a schedule
            Apps = $true; Drivers = $true; OptionalDrivers = $false; Notify = $true
            MajorVersions = $false   # 7.x -> 8.x can change how an app works: you choose those yourself
            # Never updated automatically (you can still update them in 28 > 1): updates of these can
            # break projects, virtual machines or containers; App Installer is winget itself. * = any text.
            ExcludeApps = [string[]]@('OpenJS.NodeJS*', 'Oracle.VirtualBox', 'Docker.DockerDesktop', 'Microsoft.VisualStudio.*', 'Microsoft.AppInstaller')
        }
    }
}

function Test-AppIdPattern([string]$Text) {
    # A winget Id like Git.Git, or a pattern of one (* = any text)
    return ($Text.Length -le 128 -and $Text -match '^[A-Za-z0-9\*][\w\.\-\+\*]*$')
}

function ConvertTo-BoolOrNull($Value) {
    if ($Value -is [bool]) { return $Value }
    if ("$Value" -match '^(true|1)$') { return $true }
    if ("$Value" -match '^(false|0)$') { return $false }
    return $null
}

function Resolve-Language([string]$Preference) {
    if ($Preference -eq 'en' -or $Preference -eq 'fr') { return $Preference }
    try { if ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr') { return 'fr' } } catch { }
    return 'en'
}

function Import-Settings {
    $s = Get-DefaultSettings
    $script:SettingsError = $false
    if (Test-Path -LiteralPath $script:SettingsPath) {
        try {
            $j = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if (@('auto', 'en', 'fr') -contains "$($j.Language)") { $s.Language = "$($j.Language)" }
            if (@('simple', 'advanced') -contains "$($j.MenuMode)") { $s.MenuMode = "$($j.MenuMode)".ToLower() }
            $v = ConvertTo-BoolOrNull $j.CheckForUpdates
            if ($null -ne $v) { $s.CheckForUpdates = $v }
            $n = 0
            if ([int]::TryParse("$($j.TempMinAgeHours)", [ref]$n) -and $n -ge 1 -and $n -le 720) { $s.TempMinAgeHours = $n }
            if ([int]::TryParse("$($j.LogMinAgeDays)", [ref]$n) -and $n -ge 1 -and $n -le 365) { $s.LogMinAgeDays = $n }
            # full paths only (a drive letter alone or a relative path would mean nothing, or everything)
            $s.ExcludeFolders = [string[]]@(@($j.ExcludeFolders) | Where-Object { $_ } |
                ForEach-Object { [Environment]::ExpandEnvironmentVariables("$_").Trim().TrimEnd('\') } |
                Where-Object { $_.Length -ge 4 -and $_.Length -le 260 -and $_ -match '^([A-Za-z]:\\|\\\\|/)' })
            if ($j.AutoClean) {
                foreach ($k in @($s.AutoClean.Keys)) {
                    $v = ConvertTo-BoolOrNull $j.AutoClean.$k
                    if ($null -ne $v) { $s.AutoClean[$k] = $v }
                }
            }
            if ($j.Updates) {
                $ju = $j.Updates
                $su = $s.Updates
                if (@('manual', 'notify', 'auto') -contains "$($ju.Mode)") { $su.Mode = "$($ju.Mode)".ToLower() }
                if (@('daily', 'weekly') -contains "$($ju.Frequency)") { $su.Frequency = "$($ju.Frequency)".ToLower() }
                $day = @([Enum]::GetNames([System.DayOfWeek]) | Where-Object { $_ -ieq "$($ju.Day)" })
                if ($day.Count -eq 1) { $su.Day = $day[0] }
                if ("$($ju.Time)" -match '^([01]\d|2[0-3]):[0-5]\d$') { $su.Time = "$($ju.Time)" }
                foreach ($k in @('Apps', 'Drivers', 'OptionalDrivers', 'Notify', 'MajorVersions')) {
                    $v = ConvertTo-BoolOrNull $ju.$k
                    if ($null -ne $v) { $su[$k] = $v }
                }
                if ($ju.PSObject.Properties['ExcludeApps']) {
                    $su.ExcludeApps = [string[]]@(@($ju.ExcludeApps) | ForEach-Object { "$_".Trim() } | Where-Object { Test-AppIdPattern $_ })
                }
            }
        } catch {
            $script:SettingsError = $true
            $s = Get-DefaultSettings
        }
    }
    $script:Settings = $s
    $script:Lang = Resolve-Language $s.Language
}

function Save-Settings {
    try {
        New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
        $script:Settings.ExcludeFolders = [string[]]@($script:Settings.ExcludeFolders)
        $script:Settings.Updates.ExcludeApps = [string[]]@($script:Settings.Updates.ExcludeApps)
        ConvertTo-Json -InputObject $script:Settings -Depth 5 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
        return $true
    } catch {
        Write-Warn (L 'Could not save settings: {0}' $_.Exception.Message)
        return $false
    }
}

# ==================================================================
#  Results, summary & history
# ==================================================================
function Add-Result([string]$Category, [long]$Files, [long]$Bytes, [long]$Skipped) {
    # $Category is kept in English (stable for the history file) and translated when shown.
    $script:Results.Add([pscustomobject]@{
        Category = $Category; Files = $Files; Bytes = $Bytes; Skipped = $Skipped
    })
}

function Show-Summary {
    param([double]$FreeBefore = -1)
    if ($script:Results.Count -eq 0) { return }
    $title = if ($script:DryRun) { N 'ANALYSIS - space you can reclaim (nothing was deleted)' } else { N 'SUMMARY' }
    Write-Section $title
    $fmt = '  {0,-32}{1,12}{2,16}'
    Write-Host ($fmt -f (L 'Category'), (L 'Files'), (L 'Size')) -ForegroundColor DarkGray
    $total = [long]0
    foreach ($r in $script:Results) {
        $filesText = if ($r.Files -lt 0) { '-' } else { '{0:N0}' -f $r.Files }
        Write-Host ($fmt -f (L $r.Category), $filesText, (Format-Size $r.Bytes))
        $total += $r.Bytes
    }
    Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
    Write-Host ($fmt -f (L 'TOTAL'), '', (Format-Size $total)) -ForegroundColor Green
    if ($FreeBefore -ge 0 -and -not $script:DryRun) {
        $freeAfter = Get-FreeBytes
        Write-Info (L 'Free disk space ({0}): {1}  ->  {2}' (Get-DriveLettersText) (Format-Size $FreeBefore) (Format-Size $freeAfter))
        # Free space is measured on the whole disk, so other programs writing or freeing
        # space at the same time show up too. Say so when the difference is noticeable.
        $gap = [math]::Abs(($freeAfter - $FreeBefore) - $total)
        if ($gap -gt 100MB -and $gap -gt 0.1 * $total) {
            Write-Info 'The change in free space differs from what YSO removed: other programs were writing or freeing space at the same time.'
        }
    }
}

function Save-History([string]$Mode) {
    if ($script:DryRun -or $script:Results.Count -eq 0) { return }
    $run = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $rows = @(foreach ($r in $script:Results) {
        if ($r.Bytes -gt 0 -or $r.Files -gt 0) {
            [pscustomobject]@{ Run = $run; Mode = $Mode; Category = $r.Category; Files = $r.Files; Bytes = $r.Bytes }
        }
    })
    if ($rows.Count -eq 0) { return }
    try { $rows | Export-Csv -LiteralPath $script:HistoryPath -Append -NoTypeInformation -Encoding UTF8 } catch { }
}

function Show-History {
    Write-Section 'CLEANUP HISTORY'
    $rows = @()
    if (Test-Path -LiteralPath $script:HistoryPath) {
        $rows = @(Import-Csv -LiteralPath $script:HistoryPath -ErrorAction SilentlyContinue | Where-Object { $_.Run -and $_.Run.Length -ge 16 })
    }
    if ($rows.Count -eq 0) {
        Write-Info 'No cleanups recorded yet. Run any cleaning option and it will show up here.'
        return
    }
    foreach ($r in $rows) { $r.Bytes = [long]$r.Bytes }
    $total = [long](($rows | Measure-Object -Property Bytes -Sum).Sum)
    $runs  = @($rows | Group-Object Run)
    $first = (@($rows | Sort-Object Run)[0]).Run.Substring(0, 10)
    Write-Kv 'Freed in total' (L '{0} in {1} cleanups (since {2})' (Format-Size $total) $runs.Count $first) 'Green'

    Write-Section 'BY MONTH'
    $months = @($rows | Group-Object { $_.Run.Substring(0, 7) } | Sort-Object Name | Select-Object -Last 12)
    $sums   = @($months | ForEach-Object { [long](($_.Group | Measure-Object -Property Bytes -Sum).Sum) })
    $max    = ($sums | Measure-Object -Maximum).Maximum
    for ($i = 0; $i -lt $months.Count; $i++) {
        $len = if ($max -gt 0) { [int][math]::Round(32 * $sums[$i] / $max) } else { 0 }
        if ($sums[$i] -gt 0 -and $len -lt 1) { $len = 1 }
        Write-Host ('  {0}  ' -f $months[$i].Name) -NoNewline -ForegroundColor DarkGray
        Write-Host (('#' * $len).PadRight(33)) -NoNewline -ForegroundColor Green
        Write-Host (Format-Size $sums[$i])
    }

    Write-Section 'LAST 10 CLEANUPS'
    foreach ($g in @($runs | Sort-Object Name -Descending | Select-Object -First 10)) {
        $sum = [long](($g.Group | Measure-Object -Property Bytes -Sum).Sum)
        Write-Host ('  {0}   {1,-10} {2,12}' -f $g.Name.Substring(0, 16), (L $g.Group[0].Mode), (Format-Size $sum))
    }

    Write-Section 'BY CATEGORY'
    $cats = @($rows | Group-Object Category | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Sum = [long](($_.Group | Measure-Object -Property Bytes -Sum).Sum) }
    } | Sort-Object Sum -Descending)
    foreach ($c in $cats) { Write-Kv $c.Name (Format-Size $c.Sum) }
}

# ==================================================================
#  Error capture & privacy (used by every option, the self-test and reports)
# ==================================================================
function Get-OsText {
    $caption = 'Windows'
    $arch = "$env:PROCESSOR_ARCHITECTURE"
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $caption = "$($os.Caption)".Trim()
        $script:IsServer = ($os.ProductType -ne 1)
    } catch { }
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $release = ''
    if ($cv.DisplayVersion) { $release = "$($cv.DisplayVersion)" } elseif ($cv.ReleaseId) { $release = "$($cv.ReleaseId)" }
    $build = if ($cv.CurrentBuild) { "$($cv.CurrentBuild)" } else { "$script:Build" }
    if ($null -ne $cv.UBR) { $build += ".$($cv.UBR)" }
    return (('{0} {1} (build {2}, {3})' -f $caption, $release, $build, $arch) -replace '\s{2,}', ' ')
}

function Test-UsersCanWrite([string]$Path) {
    # True when standard users (or everyone) may create or change files in this folder.
    $acl = Get-Acl -LiteralPath $Path
    $write = [System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, Delete, ChangePermissions, TakeOwnership'
    foreach ($r in $acl.Access) {
        if ($r.AccessControlType -ne 'Allow' -or -not ($r.FileSystemRights -band $write)) { continue }
        try { $sid = $r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { continue }
        # Users, Authenticated Users, Everyone, Interactive
        if (@('S-1-5-32-545', 'S-1-5-11', 'S-1-1-0', 'S-1-5-4') -contains $sid) { return $true }
    }
    return $false
}

function Protect-YsoDataDir {
    # YSO runs with administrator rights and trusts its settings: only administrators and Windows may
    # change them. Users can still read the logs and the history. (By default, any user may create
    # files in a new folder of ProgramData.)
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { return }
    try {
        New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
        if (-not (Test-UsersCanWrite $script:DataDir)) { return }
        $new = New-Object System.Security.AccessControl.DirectorySecurity
        $new.SetAccessRuleProtection($true, $false)
        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($p in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
            $sid = New-Object System.Security.Principal.SecurityIdentifier $p[0]
            $new.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $sid, $p[1], $inherit, 'None', 'Allow'))
        }
        Set-Acl -LiteralPath $script:DataDir -AclObject $new
    } catch { Write-YsoError -Context 'protect the data folder' -ErrorRecord $_ }
}

function Write-YsoError {
    # Saves the full details of an error to errors.log (it is never sent anywhere by itself).
    param([string]$Context, $ErrorRecord)
    $script:ErrorCount++
    try {
        New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
        $existing = Get-Item -LiteralPath $script:ErrorLogPath -ErrorAction SilentlyContinue
        if ($existing -and $existing.Length -gt 1MB) {
            Move-Item -LiteralPath $script:ErrorLogPath -Destination ($script:ErrorLogPath -replace '\.log$', '.old.log') -Force
        }
        $inv = $ErrorRecord.InvocationInfo
        $lines = @(
            ('==== {0:yyyy-MM-dd HH:mm:ss} | {1} | YSO {2} | {3} | PowerShell {4} | {5}' -f (Get-Date), $Context, $script:Version, $script:OsText, $PSVersionTable.PSVersion, $script:Lang),
            ('Message : ' + $ErrorRecord.Exception.Message),
            ('Type    : ' + $ErrorRecord.Exception.GetType().FullName),
            ('Command : ' + "$($inv.MyCommand)"),
            ('Line    : ' + "$($inv.ScriptLineNumber): " + "$($inv.Line)".Trim()),
            'Stack   :'
        )
        $lines += @("$($ErrorRecord.ScriptStackTrace)" -split "`r?`n" | ForEach-Object { '  ' + $_ })
        $lines += ''
        Add-Content -LiteralPath $script:ErrorLogPath -Value $lines -Encoding UTF8
    } catch { }
}

function Show-OptionError($ErrorRecord) {
    Write-Host ''
    Write-Bad 'Something went wrong in this option, so it stopped. The details were saved.'
    Write-Info (L 'Error: {0}' $ErrorRecord.Exception.Message)
    Write-Info 'Use P (Report a problem) to send them - it helps fix YSO.'
}

function Invoke-Step {
    # Runs one step of a longer job; if it fails, the error is saved and the job continues.
    param([string]$Context, [scriptblock]$Block)
    try { & $Block | Out-Null }
    catch {
        if (Test-StopError $_) { throw }   # Stop ends the whole job, not just this step
        Write-YsoError -Context $Context -ErrorRecord $_
        Write-Bad (L 'This step failed and was skipped: {0}' $_.Exception.Message)
    }
}

function Protect-Text([string]$Text) {
    # Removes personal details before a report leaves this PC: user names, the PC name,
    # private IP addresses and the Wi-Fi network name.
    if (-not $Text) { return $Text }
    $out = $Text
    $roots = @(@($script:Profiles) + @($env:USERPROFILE) | Where-Object { $_ } | Sort-Object Length -Descending -Unique)
    foreach ($p in $roots) {
        $hidden = (Join-Path (Split-Path -Path $p -Parent) '<user>').Replace('$', '$$')
        $out = [regex]::Replace($out, [regex]::Escape($p) + '(?![\w])', $hidden, 'IgnoreCase')
    }
    if ($env:COMPUTERNAME -and $env:COMPUTERNAME.Length -ge 3) {
        $out = [regex]::Replace($out, '(?<![\w-])' + [regex]::Escape($env:COMPUTERNAME) + '(?![\w-])', '<pc>', 'IgnoreCase')
    }
    $names = @(@($env:USERNAME) + @($roots | ForEach-Object { Split-Path -Path $_ -Leaf }) |
        Where-Object { $_ -and $_.Length -ge 3 } | Sort-Object Length -Descending -Unique)
    foreach ($n in $names) {
        $out = [regex]::Replace($out, '(?<![\w])' + [regex]::Escape($n) + '(?![\w])', '<user>', 'IgnoreCase')
    }
    $private = '(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}|169\.254(?:\.\d{1,3}){2}|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])(?:\.\d{1,3}){2})'
    $out = [regex]::Replace($out, '(?<!\d)(?<!\d\.)' + $private + '(?!\.?\d)', '<ip>')
    $labels = @('Wi-Fi network')
    if ($script:FR.ContainsKey('Wi-Fi network')) { $labels += $script:FR['Wi-Fi network'] }
    foreach ($label in $labels) {
        $out = [regex]::Replace($out, '(?m)^(\s*' + [regex]::Escape($label) + '\s+)[^\r\n]+', '${1}<hidden>')
    }
    return $out
}

# ==================================================================
#  Deletion engine
# ==================================================================
function Get-LongPath([string]$Path, [switch]$Always) {
    # Windows PowerShell 5.1 cannot reach paths of 260 characters or more, unless they start with \\?\.
    if ($Path.StartsWith('\\?\') -or (-not $Always -and $Path.Length -lt 240)) { return $Path }
    if ($Path -match '^[A-Za-z]:\\') { return '\\?\' + $Path }
    if ($Path -match '^\\\\[^?.]') { return '\\?\UNC\' + $Path.Substring(2) }
    return $Path
}

function ConvertFrom-LongPath([string]$Path) {
    if ($Path.StartsWith('\\?\UNC\')) { return '\\' + $Path.Substring(8) }
    if ($Path.StartsWith('\\?\')) { return $Path.Substring(4) }
    return $Path
}

function Get-Tree {
    # Lists files and folders under $Root WITHOUT following junctions/symlinks
    # and without entering your "never touch" folders.
    param([string]$Root, [string]$Filter = '*')
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $dirs  = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push((Get-LongPath $Root))
    while ($stack.Count -gt 0) {
        $path = $stack.Pop()
        $dir  = [System.IO.DirectoryInfo]::new($path)
        $found = $null
        try { $found = $dir.GetFiles($Filter) }
        catch {
            # a name inside makes the path too long: read the folder again through \\?\
            $alt = Get-LongPath $path -Always
            if ($alt -ne $path) { try { $dir = [System.IO.DirectoryInfo]::new($alt); $found = $dir.GetFiles($Filter) } catch { } }
        }
        if ($found) { foreach ($f in $found) { $files.Add($f) } }
        try {
            foreach ($d in $dir.GetDirectories()) {
                if ($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                if (Test-Excluded (ConvertFrom-LongPath $d.FullName)) { continue }
                $dirs.Add($d)
                $stack.Push((Get-LongPath $d.FullName))
            }
        } catch { }
    }
    return [pscustomobject]@{ Files = $files; Dirs = $dirs }
}

function Invoke-Purge {
    # Targets: hashtables @{ Path = '...' (wildcards OK); Days = n (keep newer); Filter = '*.log' }
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Targets,
        [switch]$Quiet
    )
    $count = [long]0; $bytes = [long]0; $skipped = [long]0
    $activity = L $Category
    foreach ($t in $Targets) {
        $days   = if ($t.Days)   { [double]$t.Days } else { 0 }
        $filter = if ($t.Filter) { [string]$t.Filter } else { '*' }
        $cutoff = (Get-Date).AddDays(-$days)
        $roots  = @(Resolve-Path -Path $t.Path -ErrorAction SilentlyContinue | ForEach-Object { $_.ProviderPath })
        foreach ($root in $roots) {
            if (Test-ProtectedPath $root) { Write-Warn (L 'Refusing to touch protected path: {0}' $root); continue }
            if (Test-Excluded $root) { continue }
            $item = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            $tree = $null
            if ($item.PSIsContainer) {
                $tree = Get-Tree -Root $item.FullName -Filter $filter
                $candidates = $tree.Files
            } else {
                $candidates = @($item)
            }
            $n = 0; $total = [math]::Max(1, @($candidates).Count)
            foreach ($f in $candidates) {
                $n++
                if (($n % 25) -eq 1 -or $n -eq $total) { Write-YsoProgress -Activity $activity -Status (L '{0:N0} files, {1}' $count (Format-Size $bytes)) -Percent (100 * $n / $total) }
                if ($days -gt 0 -and $f.LastWriteTime -gt $cutoff) { continue }
                $len = $f.Length
                if ($script:DryRun) { $count++; $bytes += $len; continue }
                try {
                    if ($f.IsReadOnly) { $f.IsReadOnly = $false }
                    $f.Delete()
                    $count++; $bytes += $len
                } catch { $skipped++ }
            }
            if ($tree -and -not $script:DryRun) {
                # Remove folders left empty, deepest first. Folder dates were read
                # before deleting, so recently created folders are kept.
                # deepest first (longest path first), sorted without a pipeline: big trees have thousands of folders
                $darr = $tree.Dirs.ToArray()
                $keys = New-Object 'int[]' $darr.Length
                for ($k = 0; $k -lt $darr.Length; $k++) { $keys[$k] = - $darr[$k].FullName.Length }
                [Array]::Sort($keys, $darr)
                foreach ($d in $darr) {
                    if ($days -gt 0 -and $d.LastWriteTime -gt $cutoff) { continue }
                    try { [System.IO.Directory]::Delete($d.FullName, $false) } catch { }
                }
            }
        }
    }
    Write-YsoProgress -Activity $activity -Completed
    if ($Quiet) { return [pscustomobject]@{ Files = $count; Bytes = $bytes; Skipped = $skipped } }
    Add-Result -Category $Category -Files $count -Bytes $bytes -Skipped $skipped
    if ($script:DryRun) {
        Write-Info (L '{0,-30} {1,12} reclaimable  ({2:N0} files)' (L $Category) (Format-Size $bytes) $count)
    } else {
        Write-Ok (L '{0}: {1:N0} files removed, {2} freed' (L $Category) $count (Format-Size $bytes))
        if ($skipped -gt 0) { Write-Info (L '{0:N0} files are in use and were skipped (normal).' $skipped) }
    }
}

function Invoke-CleanMgr([string[]]$Handlers, [int]$Id) {
    # Runs Windows Disk Cleanup with ONLY the listed categories, then removes our marks.
    $cleanmgr = Join-Path $env:WINDIR 'System32\cleanmgr.exe'
    if (-not (Test-Path -LiteralPath $cleanmgr)) { return $false }
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $flag = 'StateFlags{0:D4}' -f $Id
    $keys = @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)
    try {
        foreach ($k in $keys) {
            if ($Handlers -contains $k.PSChildName) {
                New-ItemProperty -Path $k.PSPath -Name $flag -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
        Wait-ProcessWithProgress (Start-Process -FilePath $cleanmgr -ArgumentList "/sagerun:$Id" -PassThru) (L 'Windows Disk Cleanup')
    } finally {
        foreach ($k in $keys) { Remove-ItemProperty -Path $k.PSPath -Name $flag -ErrorAction SilentlyContinue }
    }
    return $true
}

# ==================================================================
#  CLEAN  (1-10)
# ==================================================================
function Clear-TempFiles {
    $hours = [double]$script:Settings.TempMinAgeHours
    Write-Step (L 'Temporary files - every user profile + Windows (files older than {0} h)' $hours)
    $days = $hours / 24
    $W = Esc $env:WINDIR
    $targets = @(
        @{ Path = "$W\Temp"; Days = $days },
        @{ Path = "$W\SystemTemp"; Days = $days }
    )
    foreach ($p in $script:Profiles) {
        $targets += @{ Path = "$(Esc $p)\AppData\Local\Temp"; Days = $days }
    }
    Invoke-Purge -Category 'Temporary files' -Targets $targets
}

function Close-Apps([string[]]$Names) {
    # Asks the apps to close, then stops what is still running (Spotify keeps running near the clock).
    Write-Info 'Closing...'
    foreach ($p in @(Get-Process -Name $Names -ErrorAction SilentlyContinue)) {
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() }
    }
    Start-Sleep -Seconds 3
    Get-Process -Name $Names -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

function Close-Browsers {
    Write-Info 'Closing browsers...'
    foreach ($p in @(Get-Process -Name $script:BrowserProcs -ErrorAction SilentlyContinue)) {
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() }
    }
    Start-Sleep -Seconds 4
    Get-Process -Name $script:BrowserProcs -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

function Get-BrowserCacheTargets {
    # Where browsers keep their caches (used by option 2 and by the self-test coverage check).
    $targets = @()
    # Cache folders inside each browser profile, and next to the profiles. Dawn* = newer GPU caches.
    # Service Worker storage is NOT here: it is site data (offline copies of web apps).
    $profileCaches = @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache')
    # component_crx_cache / extensions_crx_cache = copies of downloaded browser components and extensions (already installed).
    $sharedCaches  = @('ShaderCache', 'GrShaderCache', 'GraphiteDawnCache', 'component_crx_cache', 'extensions_crx_cache', 'Crashpad\reports')
    foreach ($p in $script:Profiles) {
        $L = "$(Esc $p)\AppData\Local"
        $R = "$(Esc $p)\AppData\Roaming"
        $chromium = @(
            "$L\Google\Chrome\User Data", "$L\Microsoft\Edge\User Data",
            "$L\BraveSoftware\Brave-Browser\User Data", "$L\Vivaldi\User Data",
            "$L\Chromium\User Data"
        )
        foreach ($ud in $chromium) {
            foreach ($sub in $profileCaches) { $targets += @{ Path = "$ud\*\$sub" } }
            foreach ($sub in $sharedCaches)  { $targets += @{ Path = "$ud\$sub" } }
        }
        # Opera keeps its web cache in Local but the rest of its profile in Roaming.
        foreach ($root in @("$L\Opera Software\*", "$L\Opera Software\*\*", "$R\Opera Software\*", "$R\Opera Software\*\*",
                            "$R\Opera Software\*\_side_profiles\*")) {
            foreach ($sub in ($profileCaches + $sharedCaches)) { $targets += @{ Path = "$root\$sub" } }
        }
        foreach ($sub in @('Mozilla\Firefox\Profiles\*\cache2', 'Mozilla\Firefox\Profiles\*\startupCache')) {
            $targets += @{ Path = "$L\$sub" }
        }
    }
    return $targets
}

function Get-StaleFolderTargets {
    # Subfolders where nothing at all was written for $Days days - e.g. VS Code data of projects you no longer open.
    # Whole folders only: a folder still in use keeps all its files, even old ones.
    param([string]$Parent, [int]$Days)
    $out = @()
    if (-not $Parent -or -not (Test-Path -LiteralPath $Parent -PathType Container)) { return $out }
    $cutoff = (Get-Date).AddDays(-$Days)
    foreach ($d in @(Get-ChildItem -LiteralPath $Parent -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
        # Judge by the files only: a folder's own date also changes when it is copied or restored.
        $files = (Get-Tree -Root $d.FullName).Files
        $newest = if ($files.Count -gt 0) { [datetime]::MinValue } else { $d.LastWriteTime }
        foreach ($f in $files) { if ($f.LastWriteTime -gt $newest) { $newest = $f.LastWriteTime } }
        if ($newest -lt $cutoff) { $out += @{ Path = (Esc $d.FullName) } }
    }
    return $out
}

function Get-SiteOfflineCacheTargets {
    # Offline copies kept by websites and installed web apps (Service Workers). Not cookies, not logins.
    $targets = @()
    foreach ($p in $script:Profiles) {
        $L = "$(Esc $p)\AppData\Local"
        $R = "$(Esc $p)\AppData\Roaming"
        $profiles = @("$L\Google\Chrome\User Data\*", "$L\Microsoft\Edge\User Data\*", "$L\BraveSoftware\Brave-Browser\User Data\*",
                      "$L\Vivaldi\User Data\*", "$L\Chromium\User Data\*",
                      "$R\Opera Software\*", "$R\Opera Software\*\*", "$R\Opera Software\*\_side_profiles\*")
        foreach ($root in $profiles) {
            foreach ($sub in @('Service Worker\CacheStorage', 'Service Worker\ScriptCache')) { $targets += @{ Path = "$root\$sub" } }
        }
    }
    return $targets
}

function Clear-SiteOfflineCaches {
    # Optional (asked, never automatic unless chosen in Settings): you stay logged in everywhere,
    # but web apps lose what they saved for offline use and download it again.
    param([switch]$Confirmed)
    $targets = @(Get-SiteOfflineCacheTargets)
    $previous = $script:DryRun
    $script:DryRun = $true
    try { $m = Invoke-Purge -Category 'Site offline caches' -Targets $targets -Quiet } finally { $script:DryRun = $previous }
    if ($script:DryRun) {
        if ($m.Bytes -gt 0) {
            Add-Result -Category 'Site offline caches' -Files $m.Files -Bytes $m.Bytes -Skipped 0
            Write-Info (L '{0,-30} {1,12} only if you choose (option 2)' (L 'Site offline caches') (Format-Size $m.Bytes))
        }
        return
    }
    if ($m.Bytes -lt 50MB) { return }
    if (@(Get-Process -Name $script:BrowserProcs -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Info (L 'Websites also keep {0} of offline copies - they can only be removed with the browsers closed.' (Format-Size $m.Bytes))
        return
    }
    if (-not $Confirmed) {
        Write-Host ''
        Write-Info (L 'Websites and web apps also keep {0} of offline copies (Service Workers).' (Format-Size $m.Bytes))
        Write-Info 'Removing them does not log you out, but web apps lose what they saved for offline use.'
        if (-not (Confirm-Action 'Remove them too?' $false)) { return }
    }
    Write-Step 'Offline copies kept by websites (Service Workers)'
    Invoke-Purge -Category 'Site offline caches' -Targets $targets
}

function Clear-BrowserCaches {
    param([switch]$NoPrompt, [switch]$CloseBrowsers)
    Write-Step 'Browser caches - Chrome, Edge, Brave, Vivaldi, Opera, Firefox (every profile)'
    Write-Info 'Passwords, cookies, history, bookmarks and open tabs are NOT touched.'
    if (-not $script:DryRun) {
        $running = @(Get-Process -Name $script:BrowserProcs -ErrorAction SilentlyContinue)
        if ($running.Count -gt 0) {
            $close = [bool]$CloseBrowsers
            if (-not $NoPrompt -and -not $close) {
                $names = ($running | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
                Write-Warn (L 'Open browsers: {0} - files they are using will be skipped.' $names)
                $close = Confirm-Action 'Close them now for a complete clean? (tabs are restored on reopen)' $false
            }
            if ($close) { Close-Browsers }
        }
    }
    Invoke-Purge -Category 'Browser caches' -Targets @(Get-BrowserCacheTargets)
    if (-not $NoPrompt -and -not $script:DryRun) { Clear-SiteOfflineCaches }
}

function Clear-SystemJunk {
    $keepDays = [double]$script:Settings.LogMinAgeDays
    Write-Step (L 'System junk - error reports, crash dumps, logs older than {0} days, thumbnail cache' $keepDays)
    $W  = Esc $env:WINDIR
    $PD = Esc $env:ProgramData
    $targets = @(
        @{ Path = "$PD\Microsoft\Windows\WER\ReportArchive" },
        @{ Path = "$PD\Microsoft\Windows\WER\ReportQueue" },
        @{ Path = "$PD\Microsoft\Windows\WER\Temp" },
        @{ Path = "$W\Logs"; Days = $keepDays },
        @{ Path = "$W\Minidump"; Days = $keepDays },
        @{ Path = "$W\MEMORY.DMP"; Days = $keepDays },
        @{ Path = "$W\LiveKernelReports"; Days = $keepDays; Filter = '*.dmp' }
    )
    foreach ($p in $script:Profiles) {
        $L = "$(Esc $p)\AppData\Local"
        $targets += @{ Path = "$L\CrashDumps" }
        $targets += @{ Path = "$L\Microsoft\Windows\WER" }
        $targets += @{ Path = "$L\Microsoft\Windows\Explorer\thumbcache_*.db" }
    }
    # Deliberately NOT touched: Windows\Prefetch (deleting it makes boot and app launch SLOWER).
    Invoke-Purge -Category 'System junk' -Targets $targets
}

function Get-DownloadedUpdates {
    # Updates Windows Update has downloaded but not installed yet (from its last check: no internet
    # needed). Their files are in the download cache: deleting them only makes Windows download them again.
    try {
        $searcher = (New-UpdateSession).CreateUpdateSearcher()
        $searcher.Online = $false
        $found = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $titles = @()
        for ($i = 0; $i -lt $found.Updates.Count; $i++) {
            $u = $found.Updates.Item($i)
            if ($u.IsDownloaded) { $titles += "$($u.Title)" }
        }
        return $titles
    } catch { return @() }
}

function Clear-UpdateCache {
    Write-Step 'Windows Update download cache + Delivery Optimization cache'
    $download = "$(Esc $env:WINDIR)\SoftwareDistribution\Download"
    $restart = [bool](Test-PendingReboot)
    $installing = [bool](Get-Process -Name 'TiWorker' -ErrorAction SilentlyContinue)
    $waiting = @()
    if (-not $restart -and -not $installing) { $waiting = @(Get-DownloadedUpdates) }
    if ($waiting.Count -gt 0) {
        $name = Get-Truncated $waiting[0] 70
        if ($waiting.Count -gt 1) { $name += ' ' + (L '(and {0} more)' ($waiting.Count - 1)) }
        $waitText = L 'Windows Update has downloaded updates it has not installed yet ({0}): its download cache is kept, or Windows would download them again. Install them (Settings > Windows Update), then clean again.' $name
    }
    if ($script:DryRun) {
        # Analyze shows what the cleaning would really remove.
        if ($restart) { Write-Info 'Updates are waiting for a restart: the Windows Update download cache would be kept.' }
        elseif ($waiting.Count -gt 0) { Write-Info $waitText }
        else { Invoke-Purge -Category 'Windows Update cache' -Targets @(@{ Path = $download }) }
        return
    }
    if ($restart) {
        # Downloads of updates waiting for the restart must stay; Delivery Optimization below still runs.
        Write-Warn 'Updates are waiting for a restart: the Windows Update download cache is kept. Restart, then run this again.'
    } elseif ($installing) {
        Write-Warn 'Windows Update is installing something right now: its download cache is kept. Try again later.'
    } elseif ($waiting.Count -gt 0) {
        Write-Warn $waitText
    } else {
        $wasRunning = @(Get-Service -Name 'wuauserv', 'bits' -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.Name })
        $paused = $true
        try {
            Stop-Service -Name 'wuauserv', 'bits' -Force -ErrorAction Stop
        } catch {
            Write-Warn (L 'Could not pause Windows Update: {0}' $_.Exception.Message)
            $paused = $false
        }
        if ($paused) {
            try {
                Invoke-Purge -Category 'Windows Update cache' -Targets @(@{ Path = $download })
            } finally {
                foreach ($s in $wasRunning) { Start-Service -Name $s -ErrorAction SilentlyContinue }
            }
        }
    }
    if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) {
        $before = Get-FreeBytes
        # *> $null also hides the cmdlet's own English messages ("Deleting...", "Successfully deleted...").
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop *> $null } catch { }
        $gain = [math]::Max([long]0, [long]((Get-FreeBytes) - $before))
        Add-Result -Category 'Delivery Optimization' -Files -1 -Bytes $gain -Skipped 0
        Write-Ok (L 'Delivery Optimization cache: {0} freed' (Format-Size $gain))
    }
}

function Get-RecycleBinBytes {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sum = [long]0
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue)) {
        if ($v.DriveType -ne 'Fixed' -or -not $v.DriveLetter) { continue }
        $bin = "$($v.DriveLetter):\`$Recycle.Bin\$sid"
        if (Test-Path -LiteralPath $bin) {
            foreach ($f in (Get-Tree -Root $bin).Files) { $sum += $f.Length }
        }
    }
    return $sum
}

function Clear-YsoRecycleBin {
    param([switch]$Confirmed)
    Write-Step 'Recycle Bin (all drives)'
    $size = Get-RecycleBinBytes
    if ($size -le 0) { Write-Ok 'Recycle Bin is already empty.'; return }
    if ($script:DryRun) {
        Add-Result -Category 'Recycle Bin' -Files -1 -Bytes $size -Skipped 0
        Write-Info (L '{0,-30} {1,12} in the bin (only deleted if you confirm)' (L 'Recycle Bin') (Format-Size $size))
        return
    }
    if (-not $Confirmed) {
        $q = L 'Permanently delete {0} from the Recycle Bin? This cannot be undone.' (Format-Size $size)
        if (-not (Confirm-Action $q $false)) { Write-Info 'Recycle Bin kept.'; return }
    }
    try { Clear-RecycleBin -Force -ErrorAction Stop } catch { }   # can throw harmless path errors
    $freed = [math]::Max([long]0, [long]($size - (Get-RecycleBinBytes)))
    Add-Result -Category 'Recycle Bin' -Files -1 -Bytes $freed -Skipped 0
    Write-Ok (L 'Recycle Bin emptied: {0} freed' (Format-Size $freed))
}

function Get-SteamRoots {
    # Steam's install folder plus every Steam library folder on other drives.
    $roots = @()
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        $ip = (Get-ItemProperty -Path $key -Name InstallPath -ErrorAction SilentlyContinue).InstallPath
        if ($ip -and (Test-Path -LiteralPath $ip)) { $roots += "$ip".TrimEnd('\') }
    }
    if ($roots.Count -eq 0) {
        $sp = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
        $candidates = @($sp)
        foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) { if ($pf) { $candidates += (Join-Path $pf 'Steam') } }   # no (x86) on 32-bit Windows
        foreach ($c in $candidates) {
            if ($c -and (Test-Path -LiteralPath (Join-Path "$c" 'steam.exe'))) { $roots += ("$c" -replace '/', '\').TrimEnd('\'); break }
        }
    }
    $main = @($roots)[0]
    if ($main) {
        $vdf = Join-Path $main 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $lib = $m.Groups[1].Value -replace '\\\\', '\'
                if (Test-Path -LiteralPath $lib) { $roots += $lib.TrimEnd('\') }
            }
        }
    }
    # Unique, but keep the order: the install folder must stay first.
    $seen = @{}
    return @($roots | Where-Object { $k = "$_".ToLowerInvariant(); if ($seen.ContainsKey($k)) { $false } else { $seen[$k] = $true; $true } })
}

function Clear-ShaderCaches {
    Write-Step 'GPU shader caches - DirectX, NVIDIA, AMD, Intel, Steam'
    Write-Info 'Games rebuild these on next launch (first load may stutter briefly).'
    Write-Info 'Most useful after a driver update or when you see graphics glitches.'
    $targets = @()
    foreach ($p in $script:Profiles) {
        $L  = "$(Esc $p)\AppData\Local"
        $LL = "$(Esc $p)\AppData\LocalLow"
        foreach ($c in @("$L\D3DSCache", "$L\NVIDIA\DXCache", "$L\NVIDIA\GLCache",
                         "$L\AMD\DxCache", "$L\AMD\DxcCache", "$L\AMD\GLCache", "$L\AMD\VkCache",
                         "$LL\NVIDIA\PerDriverVersion\DXCache", "$LL\Intel\ShaderCache")) {
            $targets += @{ Path = $c }
        }
    }
    foreach ($s in Get-SteamRoots) { $targets += @{ Path = "$(Esc $s)\steamapps\shadercache" } }
    Invoke-Purge -Category 'GPU shader caches' -Targets $targets
}

function Get-AppCacheTargets {
    # Where apps keep their caches (used by option 7 and by the self-test coverage check).
    $targets = @()
    foreach ($p in $script:Profiles) {
        $base = Esc $p
        $L = "$base\AppData\Local"
        $R = "$base\AppData\Roaming"
        $teams = "$L\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\*"
        foreach ($c in @(
            "$L\npm-cache\_cacache", "$L\npm-cache\_logs",               # npm
            "$L\pip\Cache",                                               # pip
            "$L\NuGet\v3-cache", "$L\NuGet\plugins-cache",                # NuGet download caches (not your packages)
            "$L\Yarn\Cache",                                              # Yarn 1
            "$base\.gradle\caches\build-cache-*",                            # Gradle build cache
            "$R\Code\Cache", "$R\Code\CachedData", "$R\Code\Code Cache",  # VS Code
            "$R\Code\GPUCache", "$R\Code\CachedExtensionVSIXs", "$R\Code\logs",
            "$R\discord\Cache", "$R\discord\Code Cache", "$R\discord\GPUCache",
            "$R\Microsoft\Teams\Cache", "$R\Microsoft\Teams\Code Cache", "$R\Microsoft\Teams\GPUCache",
            "$teams\Cache", "$teams\Code Cache", "$teams\GPUCache",       # new Teams
            "$L\Spotify\Data",                                            # Spotify streaming cache
            "$L\Packages\SpotifyAB.SpotifyMusic_*\LocalCache\Spotify\Data", # Spotify from the Microsoft Store
            "$R\Code\Crashpad\reports", "$R\discord\Crashpad\reports",      # crash reports
            "$L\Steam\htmlcache\Cache", "$L\Steam\htmlcache\Code Cache", "$L\Steam\htmlcache\GPUCache", # Steam's built-in browser
            "$L\EpicGamesLauncher\Saved\webcache*"                        # Epic launcher web cache
        )) { $targets += @{ Path = $c } }
        # Built-in browsers of Spotify (classic + Microsoft Store) and OneDrive: only their cache folders, never their logins.
        foreach ($web in @("$L\Spotify\Browser", "$L\Packages\SpotifyAB.SpotifyMusic_*\LocalCache\Spotify\Browser", "$L\Microsoft\OneDrive\EBWebView")) {
            foreach ($sub in @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache')) {
                $targets += @{ Path = "$web\$sub" }
                $targets += @{ Path = "$web\*\$sub" }
            }
            foreach ($sub in @('ShaderCache', 'GrShaderCache', 'GraphiteDawnCache', 'component_crx_cache')) { $targets += @{ Path = "$web\$sub" } }
        }
        $targets += @{ Path = "$L\Spotify\component_crx_cache" }
        $targets += @{ Path = "$L\Packages\SpotifyAB.SpotifyMusic_*\LocalCache\Spotify\component_crx_cache" }
        # VS Code: saved data of projects not opened for 60 days (rebuilt if the project is opened again)
        $targets += @(Get-StaleFolderTargets -Parent (Join-Path $p 'AppData\Roaming\Code\User\workspaceStorage') -Days 60)
        foreach ($log in @("$L\Microsoft\OneDrive\logs", "$L\Microsoft\OneDrive\setup\logs")) {
            $targets += @{ Path = $log; Days = [double]$script:Settings.LogMinAgeDays }   # keeps recent logs for troubleshooting
        }
        $targets += @{ Path = "$base\.gradle\daemon\*"; Filter = '*.log' }
    }
    $steam = @(Get-SteamRoots)
    if ($steam.Count -gt 0) {
        $main = Esc $steam[0]   # the Steam install folder (libraries only hold games)
        $targets += @{ Path = "$main\appcache\httpcache" }
        $targets += @{ Path = "$main\appcache\librarycache" }                                   # game pictures, downloaded again
        $targets += @{ Path = "$main\dumps" }                                                   # Steam crash dumps
        $targets += @{ Path = "$main\logs"; Days = [double]$script:Settings.LogMinAgeDays }      # keeps recent logs
    }
    return $targets
}

function Test-ChromiumCache([string]$Dir, [string]$Kind) {
    # True when $Dir is laid out like a Chromium cache, so a folder that is merely called "Cache" is left alone.
    switch ($Kind) {
        'Cache'      { return ([System.IO.Directory]::Exists([System.IO.Path]::Combine($Dir, 'Cache_Data')) -or
                               [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'index')) -or
                               [System.IO.Directory]::Exists([System.IO.Path]::Combine($Dir, 'index-dir'))) }
        'Code Cache' { return ([System.IO.Directory]::Exists([System.IO.Path]::Combine($Dir, 'js')) -or
                               [System.IO.Directory]::Exists([System.IO.Path]::Combine($Dir, 'wasm'))) }
        default      { return [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'index')) }   # GPU, Dawn and shader caches
    }
}

function Get-AppNameFromPath([string]$Dir, [string]$Base) {
    $rel = $Dir.Substring([math]::Min($Dir.Length, $Base.Length)).TrimStart('\', '/')
    $segs = @($rel -split '[\\/]' | Where-Object { $_ })
    if ($segs.Count -eq 0) { return '?' }
    if ($segs[0] -eq 'Packages' -and $segs.Count -gt 1) {
        $pkg = ($segs[1] -split '_')[0]                      # 5319275A.WhatsAppDesktop_cv1g1gvanyjgm -> 5319275A.WhatsAppDesktop
        $friendly = @{
            'MicrosoftWindows.Client.CBS' = (N 'Windows search and Start'); 'MicrosoftWindows.Client.WebExperience' = (N 'Windows widgets')
            '5319275A.WhatsAppDesktop' = 'WhatsApp'; 'Microsoft.OutlookForWindows' = 'Outlook'; 'Microsoft.Copilot' = 'Copilot'
            'Microsoft.MicrosoftOfficeHub' = 'Microsoft 365'; 'Microsoft.BingSearch' = 'Bing'; 'Microsoft.Windows.DevHome' = 'Dev Home'
            'windows.immersivecontrolpanel' = (N 'Windows Settings'); 'Microsoft.WindowsStore' = 'Microsoft Store'
            'Microsoft.Windows.ShellExperienceHost' = (N 'Windows taskbar and notifications'); 'MicrosoftTeams' = 'Teams'; 'MSTeams' = 'Teams'
            'Microsoft.MicrosoftSolitaireCollection' = 'Solitaire'; 'Microsoft.SkypeApp' = 'Skype'; 'E046963F.LenovoCompanion' = 'Lenovo Vantage'
            'Microsoft.GetHelp' = (N 'Windows Get Help'); 'Clipchamp.Clipchamp' = 'Clipchamp'; 'Microsoft.Windows.Photos' = (N 'Photos')
        }
        if ($friendly.ContainsKey($pkg)) { return (L $friendly[$pkg]) }
        return (Get-ReadableAppName (($pkg -split '\.')[-1]))
    }
    if (@('Microsoft', 'Google', 'Programs') -contains $segs[0] -and $segs.Count -gt 1) {
        # Microsoft\Windows\<part>: the part says more than "Windows"
        if ($segs[0] -eq 'Microsoft' -and $segs[1] -eq 'Windows' -and $segs.Count -gt 2) { return ('Windows ' + (Get-ReadableAppName $segs[2])) }
        return (Get-ReadableAppName $segs[1])
    }
    return (Get-ReadableAppName $segs[0])
}

function Get-ReadableAppName([string]$Name) {
    # The folder name an app gives itself, made readable: "ollama app.exe" -> "Ollama", "Olk" -> "Outlook".
    $n = ($Name -replace '(?i)\.exe(\.WebView2)?$', '' -replace '(?i)\.WebView2$', '').Trim()
    $known = @{ 'Olk' = 'Outlook'; 'ollama app' = 'Ollama'; 'WindowsStore' = 'Microsoft Store'; 'MicrosoftTeams' = 'Teams'
                'immersivecontrolpanel' = (N 'Windows Settings'); 'ShellExperienceHost' = (N 'Windows taskbar and notifications') }
    foreach ($k in $known.Keys) { if ($n -ieq $k) { return (L $known[$k]) } }
    if ($n -cmatch '^[a-z]' -and $n -notmatch '[A-Z]') { $n = $n.Substring(0, 1).ToUpperInvariant() + $n.Substring(1) }   # "ollama" -> "Ollama"
    return $n
}

function Get-DetectedAppCacheTargets {
    # Apps built on Chromium - Electron apps (Slack, Notion, Figma, Signal, Obsidian...) and WebView2 apps
    # (WhatsApp, the new Outlook...) - keep their caches with the same layout. Finding them by that layout
    # cleans apps YSO does not know by name. Only the caches: logins, messages and settings stay.
    param([int]$MaxDepth = 7, [int]$MaxFolders = 60000)
    $kinds   = @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'ShaderCache', 'GrShaderCache', 'GraphiteDawnCache')
    $markers = @('Local Storage', 'Session Storage', 'Preferences', 'Local State', 'Network', 'Cookies', 'IndexedDB')
    $skip    = @('node_modules', '.git', 'Temp', 'Programs', 'npm-cache', 'pip', 'NuGet', 'IndexedDB', 'Local Storage', 'Session Storage',
                 'Service Worker', 'blob_storage', 'databases', 'File System', 'WebStorage', 'CrashDumps', 'D3DSCache', 'INetCache',
                 'WindowsApps', 'Extensions', 'AC', 'TempState', 'SystemAppData', 'Packages_Backup') + $kinds
    # (compared with / only, so the same code works with both kinds of separators)
    $known = @(@(Get-AppDataRoots) | ForEach-Object { $_.Path.Replace('\', '/').TrimEnd('/') })
    foreach ($p in $script:Profiles) { $known += ([System.IO.Path]::Combine($p, 'AppData', 'Local', 'Chromium', 'User Data')).Replace('\', '/') }
    $out = @(); $apps = @{}; $visited = 0
    foreach ($p in $script:Profiles) {
        foreach ($base in @([System.IO.Path]::Combine($p, 'AppData', 'Local'), [System.IO.Path]::Combine($p, 'AppData', 'Roaming'))) {
            if (-not [System.IO.Directory]::Exists($base)) { continue }
            $queue = New-Object System.Collections.Generic.Queue[object]
            $queue.Enqueue(@($base, 0))
            while ($queue.Count -gt 0 -and $visited -lt $MaxFolders) {
                $item = $queue.Dequeue(); $dir = [string]$item[0]; $depth = [int]$item[1]
                $visited++
                if (($visited % 200) -eq 0) { Write-YsoProgress -Activity (L 'Looking for other app caches') -Status (L '{0:N0} folders' $visited) }
                try { $subs = [System.IO.Directory]::GetDirectories($dir) } catch { continue }
                $names = @{}
                foreach ($sd in $subs) { $names[[System.IO.Path]::GetFileName($sd)] = $sd }
                $hits = @(foreach ($k in $kinds) { if ($names.ContainsKey($k) -and (Test-ChromiumCache $names[$k] $k)) { $names[$k] } })
                if ($hits.Count -gt 0) {
                    $marked = $false
                    foreach ($m in $markers) { if ($names.ContainsKey($m) -or [System.IO.File]::Exists([System.IO.Path]::Combine($dir, $m))) { $marked = $true; break } }
                    if ($marked) {
                        foreach ($h in $hits) { $out += @{ Path = (Esc $h) } }
                        $apps[(Get-AppNameFromPath $dir $base)] = $true
                    }
                }
                if ($depth -ge $MaxDepth) { continue }
                foreach ($sd in $subs) {
                    if ($skip -contains [System.IO.Path]::GetFileName($sd)) { continue }
                    try { if ([System.IO.File]::GetAttributes($sd) -band [System.IO.FileAttributes]::ReparsePoint) { continue } } catch { continue }
                    $t = $sd.Replace('\', '/').TrimEnd('/')
                    $isKnown = $false
                    foreach ($k in $known) { if ($t -ieq $k -or $t.StartsWith($k + '/', 'OrdinalIgnoreCase')) { $isKnown = $true; break } }
                    if (-not $isKnown) { $queue.Enqueue(@($sd, ($depth + 1))) }
                }
            }
        }
    }
    Write-YsoProgress -Activity (L 'Looking for other app caches') -Completed
    $script:DetectedApps = @($apps.Keys | Sort-Object)
    return $out
}

function Clear-DevAppCaches {
    param([switch]$NoPrompt)
    Write-Step 'Developer & app caches - npm, pip, NuGet, Yarn, Gradle, VS Code, Discord, Teams, Spotify, Steam, Epic, OneDrive logs'
    Write-Info 'Only caches and old logs: projects, installed packages, settings, logins and game files are not touched.'
    Write-Info 'VS Code: also removes the saved data of projects not opened for 60 days (rebuilt if you open them again).'
    if (-not $script:DryRun -and -not $NoPrompt) {
        $open = @(Get-Process -Name $script:AppProcs -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
        $closable = @($open | Where-Object { $script:SafeToCloseApps -contains $_ })
        $others   = @($open | Where-Object { $script:SafeToCloseApps -notcontains $_ })
        if ($closable.Count -gt 0) {
            Write-Warn (L 'Open: {0} - files they are using would be skipped.' ($closable -join ', '))
            if (Confirm-Action 'Close them now for a complete clean? (nothing is lost, reopen them afterwards)' $false) { Close-Apps $closable }
        }
        if ($others.Count -gt 0) {
            Write-Warn (L 'Still open: {0} - files they are using will be skipped. Close them for a complete clean.' ($others -join ', '))
        }
    }
    Invoke-Purge -Category 'Developer & app caches' -Targets @(Get-AppCacheTargets)
    $other = @(Get-DetectedAppCacheTargets)
    if ($other.Count -gt 0) {
        Write-Step (L 'Other apps built on Chromium (found by their cache layout): {0}' ($script:DetectedApps -join ', '))
        Invoke-Purge -Category 'Other app caches' -Targets $other
    }
}

function ConvertTo-VersionSafe([string]$Text) {
    $v = $null
    if ([version]::TryParse(("$Text" -replace '[^\d\.]', '').Trim('.'), [ref]$v)) { return $v }
    return [version]'0.0'
}

function Get-OldDriverPackages {
    # Windows keeps every version of a driver it ever installed - a graphics driver is often 1 GB each time.
    # Old = a third-party driver package of which a newer version is installed, and that no device uses.
    # Anything YSO cannot check is kept.
    $all = @(Get-WindowsDriver -Online -ErrorAction Stop)
    $inUse = @{}
    foreach ($d in @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop)) {
        if ($d.InfName) { $inUse["$($d.InfName)".ToLowerInvariant()] = $true }
    }
    $old = @()
    $groups = @($all | Where-Object { "$($_.Driver)" -match '^oem\d+\.inf$' -and $_.OriginalFileName } |
        Group-Object { ('{0}|{1}|{2}' -f [System.IO.Path]::GetFileName("$($_.OriginalFileName)"), $_.ProviderName, $_.ClassName).ToLowerInvariant() })
    foreach ($g in $groups) {
        if ($g.Count -lt 2) { continue }
        $sorted = @($g.Group | Sort-Object @{ Expression = { ConvertTo-VersionSafe $_.Version }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        for ($i = 1; $i -lt $sorted.Count; $i++) {
            $d = $sorted[$i]
            if ($inUse.ContainsKey("$($d.Driver)".ToLowerInvariant())) { continue }
            $folder = [System.IO.Path]::GetDirectoryName("$($d.OriginalFileName)")
            $size = [long]0
            if ($folder -and (Test-Path -LiteralPath $folder)) { foreach ($f in (Get-Tree -Root $folder).Files) { $size += $f.Length } }
            $old += [pscustomobject]@{
                Inf = "$($d.Driver)"; Name = [System.IO.Path]::GetFileName("$($d.OriginalFileName)"); Provider = "$($d.ProviderName)"
                Class = "$($d.ClassName)"; Version = "$($d.Version)"; Newest = "$($sorted[0].Version)"; Bytes = $size
            }
        }
    }
    return $old
}

function Find-OldDrivers {
    # Get-OldDriverPackages without errors: when Windows cannot list its drivers, nothing is offered.
    try { return @(Get-OldDriverPackages) } catch { return @() }
}

function Remove-OldDriverPackages([object[]]$Packages) {
    Write-Step (L 'Removing {0} old driver version(s)...' @($Packages).Count)
    $before = Get-FreeBytes
    $done = 0; $failed = 0; $n = 0
    foreach ($d in $Packages) {
        $n++
        Write-YsoProgress -Activity (L 'Old driver versions') -Status ('{0} {1}' -f $d.Provider, $d.Version) -Percent (100 * $n / @($Packages).Count)
        if ($script:DryRun) { continue }
        [void](& pnputil.exe /delete-driver $d.Inf 2>&1)   # without /force: Windows refuses if a device still uses it
        if ($LASTEXITCODE -eq 0) { $done++ } else { $failed++ }
    }
    Write-YsoProgress -Activity (L 'Old driver versions') -Completed
    $gain = [math]::Max([long]0, [long]((Get-FreeBytes) - $before))
    Add-Result -Category 'Old driver versions' -Files -1 -Bytes $gain -Skipped $failed
    Write-Ok (L 'Old driver versions: {0} removed, {1} freed' $done (Format-Size $gain))
    if ($failed -gt 0) { Write-Info (L '{0} could not be removed (Windows still needs them) - normal.' $failed) }
}

function Get-OldDriversText([object[]]$Packages) {
    $sum = [long](@($Packages | Measure-Object -Property Bytes -Sum).Sum)
    $names = @($Packages | ForEach-Object { $_.Provider } | Sort-Object -Unique)
    return (L '{0} old version(s), {1} ({2})' @($Packages).Count (Format-Size $sum) ((Get-Truncated ($names -join ', ') 40)))
}

function Invoke-DeepClean {
    # -OldDrivers: 'ask' (option 8), 'yes' or 'no' (already asked by F)
    param([string]$OldDrivers = 'ask')
    Write-Step 'Deep clean - Windows Disk Cleanup (safe categories only) + component store'
    Write-Info 'Can take 10-30 minutes. Downloads, Recycle Bin and Windows.old are never included.'
    if ($script:DryRun) { return }
    $before = Get-FreeBytes
    Write-Info 'Running Disk Cleanup...'
    if (-not (Invoke-CleanMgr -Handlers $script:SafeCleanupHandlers -Id 4242)) {
        Write-Warn 'Disk Cleanup is not available on this Windows build - skipping that part.'
    }
    if (Test-PendingReboot) {
        Write-Warn 'Windows is waiting for a restart: the component store (old Windows Update files) can only be cleaned after it. Restart, then run this again.'
    } else {
        Write-Info 'Cleaning the component store (superseded Windows Update files)...'
        Wait-ProcessWithProgress (Start-Process -FilePath 'dism.exe' -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup' -NoNewWindow -PassThru) (L 'Component store')
    }
    $gain = [math]::Max([long]0, [long]((Get-FreeBytes) - $before))
    Add-Result -Category 'Deep clean' -Files -1 -Bytes $gain -Skipped 0
    Write-Ok (L 'Deep clean freed {0}' (Format-Size $gain))
    Write-Info 'Windows finishes part of this cleanup during the next restart: more space shows up then.'
    if ($OldDrivers -ne 'no') {
        Write-Step 'Looking for old driver versions...'
        $old = @(Find-OldDrivers)
        if ($old.Count -eq 0) { Write-Ok 'No old driver versions to remove.' }
        else {
            Write-Info (Get-OldDriversText $old)
            $go = ($OldDrivers -eq 'yes')
            if ($OldDrivers -eq 'ask') { $go = Confirm-Action 'Remove them? You will not be able to go back to these driver versions.' $false }
            if ($go) { Remove-OldDriverPackages $old }
        }
    }
}

function Remove-WindowsOld {
    Write-Step 'Previous Windows version (Windows.old)'
    $path = Join-Path $env:SystemDrive 'Windows.old'
    if (-not (Test-Path -LiteralPath $path)) { Write-Ok 'There is no Windows.old folder - nothing to remove.'; return }
    $item = Get-Item -LiteralPath $path -Force
    Write-Info 'Measuring...'
    $size = [long]0
    foreach ($f in (Get-Tree -Root $path).Files) { $size += $f.Length }
    Write-Kv 'Size (approx.)' (Format-Size $size)
    Write-Kv 'Created' $item.CreationTime.ToString('d')
    $window = $null
    try {
        $out = @(& dism.exe /Online /Get-OSUninstallWindow 2>$null)
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $out) { if ("$line" -match ':\s*(\d+)\s*$') { $window = [int]$Matches[1] } }
        }
    } catch { }
    $canRollBack = $false
    if ($null -ne $window) {
        $until = $item.CreationTime.AddDays($window)
        if ($until -gt (Get-Date)) {
            $canRollBack = $true
            Write-Warn (L 'You can still go back to your previous Windows version until {0}.' $until.ToString('d'))
            Write-Info 'Removing Windows.old takes that option away for good.'
        }
    }
    if (-not $canRollBack) { Write-Info 'Going back to the previous version is no longer possible, so this is just leftover files.' }
    if ($script:DryRun) { Add-Result -Category 'Windows.old' -Files -1 -Bytes $size -Skipped 0; return }
    if (-not (Confirm-Action 'Remove Windows.old now?' (-not $canRollBack))) { Write-Info 'Kept.'; return }
    $before = Get-FreeBytes
    Write-Info 'Running Disk Cleanup (previous Windows installations)...'
    if (-not (Invoke-CleanMgr -Handlers @('Previous Installations') -Id 4243)) {
        Write-Warn 'Disk Cleanup is not available on this Windows build.'
        return
    }
    $gain = [math]::Max([long]0, [long]((Get-FreeBytes) - $before))
    Add-Result -Category 'Windows.old' -Files -1 -Bytes $gain -Skipped 0
    if (Test-Path -LiteralPath $path) { Write-Warn 'Part of Windows.old is still there. Restart and run this again.' }
    else { Write-Ok (L 'Windows.old removed: {0} freed' (Format-Size $gain)) }
}

function Set-Hibernation {
    Write-Section 'HIBERNATION FILE'
    $hib  = Get-Item -LiteralPath (Join-Path $env:SystemDrive 'hiberfil.sys') -Force -ErrorAction SilentlyContinue
    $fast = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    Write-Kv 'hiberfil.sys' $(if ($hib) { Format-Size $hib.Length } else { L 'not present (hibernation is off)' })
    Write-Kv 'Fast Startup' (Format-OnOff ($hib -and $fast -eq 1))
    Write-Host ''
    Write-Info 'Windows keeps this file for Hibernate and Fast Startup.'
    Write-Info 'Reduced: keeps Fast Startup, drops Hibernate - the file shrinks to about half.'
    Write-Info 'Off: frees all of it, but turns off Hibernate and Fast Startup (cold boots get a bit slower).'
    if (Test-IsLaptop) { Write-Warn 'Laptop detected: Hibernate saves your work when the battery runs out - Reduced or Full is safer.' }
    Write-Host ''
    Write-Option '1' 'Reduced (good choice for desktops)'
    Write-Option '2' 'Off (frees the most space)'
    Write-Option '3' 'Full (Windows default)'
    Write-Option '0' 'Back'
    $steps = $null
    switch (Read-Choice) {
        '1' { $steps = @(@('/hibernate', 'on'), @('/hibernate', '/type', 'reduced')) }
        '2' { $steps = @(, @('/hibernate', 'off')) }
        '3' { $steps = @(@('/hibernate', 'on'), @('/hibernate', '/type', 'full')) }
        default { return }
    }
    if ($script:DryRun) { Write-Info 'Analyze-only mode: nothing was changed.'; return }
    $before = Get-FreeBytes
    foreach ($s in $steps) {
        $out = & powercfg.exe @s 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Warn (($out | Out-String).Trim()); return }
    }
    $delta = [long]((Get-FreeBytes) - $before)
    if ($delta -gt 0) { Add-Result -Category 'Hibernation file' -Files -1 -Bytes $delta -Skipped 0 }
    $sign = if ($delta -lt 0) { '-' } else { '+' }
    Write-Ok (L 'Done. Free space changed by {0}{1}.' $sign (Format-Size ([math]::Abs($delta))))
}

# ==================================================================
#  NETWORK  (11-14)
# ==================================================================
function Measure-Ping([string]$Target, [int]$Count = 4) {
    $times = New-Object System.Collections.Generic.List[double]
    $lost  = 0
    $ping  = New-Object System.Net.NetworkInformation.Ping
    try {
        # Warm-up, not counted: the first ping often wakes up the Wi-Fi and is much slower.
        try { [void]$ping.Send($Target, 1500) } catch { }
        for ($i = 0; $i -lt $Count; $i++) {
            try {
                $r = $ping.Send($Target, 1500)
                if ($r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $times.Add([double]$r.RoundtripTime) } else { $lost++ }
            } catch { $lost++ }
        }
    } finally { $ping.Dispose() }
    $avg = $null; $max = $null
    if ($times.Count -gt 0) {
        $avg = ($times | Measure-Object -Average).Average
        $max = ($times | Measure-Object -Maximum).Maximum
    }
    return [pscustomobject]@{ Avg = $avg; Max = $max; Loss = [int](100 * $lost / $Count) }
}

function Write-PingResult([string]$Label, $Result) {
    if ($null -eq $Result.Avg) { Write-Kv $Label (L 'no reply') 'Yellow'; return }
    $color = 'Green'
    if ($Result.Loss -gt 0 -or $Result.Avg -gt 100) { $color = 'Yellow' }
    if ($Result.Loss -ge 50 -or $Result.Avg -gt 250) { $color = 'Red' }
    Write-Kv $Label (L '{0:N0} ms average, {1:N0} ms worst, {2}% lost' $Result.Avg $Result.Max $Result.Loss) $color
}

function Measure-Dns([string]$Server) {
    $ms = New-Object System.Collections.Generic.List[double]
    foreach ($name in @('www.microsoft.com', 'www.wikipedia.org', 'www.github.com')) {
        try {
            $t = Measure-Command { Resolve-DnsName -Name $name -Server $Server -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop | Out-Null }
            $ms.Add($t.TotalMilliseconds)
        } catch { }
    }
    if ($ms.Count -eq 0) { return $null }
    return ($ms | Measure-Object -Average).Average
}

function Test-NetworkQuality {
    Write-Step 'Testing your connection (about 20 seconds, nothing is changed)...'
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    if (-not $route) { Write-Bad 'No route to the internet - this PC seems to be offline.'; return }
    $adapter = Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue
    $ip  = @(Get-NetIPAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress })
    $dns = @((Get-DnsClientServerAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses | Where-Object { $_ })

    Write-Section 'CONNECTION'
    if ($adapter) {
        Write-Kv 'Adapter' ('{0} ({1})' -f $adapter.Name, $adapter.InterfaceDescription)
        Write-Kv 'Link speed' $adapter.LinkSpeed
    }
    Write-Kv 'IP address' ($ip -join ', ')
    Write-Kv 'Router (gateway)' $route.NextHop
    Write-Kv 'DNS servers' $(if ($dns.Count) { $dns -join ', ' } else { '-' })
    $isWifi = $adapter -and ("$($adapter.PhysicalMediaType)" -match '802\.11' -or "$($adapter.InterfaceDescription)" -match 'Wi-?Fi|Wireless|WLAN|802\.11')
    $signal = $null
    if ($isWifi) {
        $w = @(netsh.exe wlan show interfaces 2>$null)
        $ssidLine = $w | Where-Object { $_ -match '^\s*SSID\s*:' } | Select-Object -First 1
        $sigMatch = $w | Select-String -Pattern ':\s*(\d{1,3})\s?%' | Select-Object -First 1
        if ($ssidLine) { Write-Kv 'Wi-Fi network' (("$ssidLine" -split ':', 2)[1].Trim()) }
        if ($sigMatch) {
            $signal = [int]$sigMatch.Matches[0].Groups[1].Value
            $q = if ($signal -ge 80) { L 'excellent' } elseif ($signal -ge 60) { L 'good' } elseif ($signal -ge 40) { L 'fair - expect slowdowns' } else { L 'weak - move closer to the router' }
            Write-Kv 'Wi-Fi signal' ('{0}% ({1})' -f $signal, $q) $(if ($signal -ge 60) { 'Green' } elseif ($signal -ge 40) { 'Yellow' } else { 'Red' })
        } else {
            Write-Kv 'Wi-Fi signal' (L 'unavailable (Windows may need Location turned on)') 'DarkGray'
        }
    }

    Write-Section 'LATENCY (lower is better)'
    $gw = $null
    if ($route.NextHop -and $route.NextHop -ne '0.0.0.0') { $gw = Measure-Ping $route.NextHop; Write-PingResult 'Your router' $gw }
    $cf = Measure-Ping '1.1.1.1'; Write-PingResult 'Internet (Cloudflare)' $cf
    $gg = Measure-Ping '8.8.8.8'; Write-PingResult 'Internet (Google)' $gg

    Write-Section 'DNS SPEED (time to look up a website)'
    $results = @()
    if ($dns.Count) { $results += [pscustomobject]@{ Name = (L 'Your DNS ({0})' $dns[0]); Ms = (Measure-Dns $dns[0]) } }
    foreach ($k in $script:DnsProviders.Keys) {
        $p = $script:DnsProviders[$k]
        $results += [pscustomobject]@{ Name = ('{0} ({1})' -f $p.Name, $p.Servers[0]); Ms = (Measure-Dns $p.Servers[0]) }
    }
    foreach ($r in $results) {
        if ($null -eq $r.Ms) { Write-Kv $r.Name (L 'no answer') 'Yellow' }
        else { Write-Kv $r.Name (L '{0:N0} ms' $r.Ms) $(if ($r.Ms -lt 50) { 'Green' } elseif ($r.Ms -lt 150) { 'Yellow' } else { 'Red' }) }
    }

    Write-Section 'VERDICT'
    $issues = 0
    if ($gw -and $null -ne $gw.Avg -and ($gw.Loss -gt 0 -or $gw.Avg -gt 20)) {
        $issues++
        Write-Warn 'The link between this PC and your router is weak or losing packets - on Wi-Fi, move closer, use 5 GHz, or try a cable.'
    }
    $net = @(@($cf.Avg, $gg.Avg) | Where-Object { $null -ne $_ })
    if ($net.Count -eq 0) {
        $issues++
        Write-Warn 'The internet servers did not answer. Your provider may be down, or ping is blocked on this network.'
    } elseif (($net | Measure-Object -Minimum).Minimum -gt 100) {
        $issues++
        Write-Warn 'Internet latency is high. This usually comes from your provider or a busy network, not from this PC.'
    }
    $timed = @($results | Where-Object { $null -ne $_.Ms })
    if ($dns.Count -and $timed.Count -gt 1 -and $null -ne $results[0].Ms) {
        $best = ($timed | Sort-Object Ms | Select-Object -First 1)
        if (($results[0].Ms - $best.Ms) -gt 30) {
            $issues++
            Write-Info (L 'A faster DNS ({0}) could make websites start loading sooner - see option 12.' $best.Name)
        }
    }
    if ($signal -and $signal -lt 40) { $issues++ }
    if ($issues -eq 0) { Write-Ok 'Everything looks healthy.' }
}

function Save-DnsBackup($Adapters) {
    # Remembers manually set DNS servers so option "restore" can put them back exactly.
    $list = @(foreach ($a in $Adapters) {
        $g  = "$($a.InterfaceGuid)"
        $v4 = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g" -Name NameServer -ErrorAction SilentlyContinue).NameServer
        $v6 = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$g" -Name NameServer -ErrorAction SilentlyContinue).NameServer
        [pscustomobject]@{ Guid = $g; Name = $a.Name; Servers = [string[]]@(("$v4 $v6") -split '[,\s]+' | Where-Object { $_ }) }
    })
    try { ConvertTo-Json -InputObject $list -Depth 3 | Set-Content -LiteralPath $script:DnsBackupPath -Encoding UTF8 } catch { }
}

function Restore-DnsServers($Adapters) {
    $saved = @()
    if (Test-Path -LiteralPath $script:DnsBackupPath) {
        try { $saved = @((Get-Content -LiteralPath $script:DnsBackupPath -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_ }) } catch { }
    }
    foreach ($a in $Adapters) {
        $s = $saved | Where-Object { $_.Guid -eq "$($a.InterfaceGuid)" } | Select-Object -First 1
        $servers = @()
        if ($s) { $servers = @($s.Servers | Where-Object { $_ }) }
        try {
            if ($servers.Count -gt 0) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $servers -ErrorAction Stop }
            else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop }
            Write-Ok (L '{0}: DNS restored' $a.Name)
        } catch { Write-Warn ('{0}: {1}' -f $a.Name, $_.Exception.Message) }
    }
    Remove-Item -LiteralPath $script:DnsBackupPath -Force -ErrorAction SilentlyContinue
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Set-DnsServers {
    Write-Section 'DNS SERVERS'
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    if ($adapters.Count -eq 0) { Write-Warn 'No connected network adapter found.'; return }
    foreach ($a in $adapters) {
        $cur = @((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
        Write-Kv $a.Name $(if ($cur.Count) { $cur -join ', ' } else { '-' })
    }
    $hasBackup = Test-Path -LiteralPath $script:DnsBackupPath
    Write-Host ''
    foreach ($k in $script:DnsProviders.Keys) {
        $p = $script:DnsProviders[$k]
        Write-Option $k ('{0} - {1}' -f $p.Name, (L $p.Note))
    }
    if ($hasBackup) { Write-Option '4' 'Restore my previous DNS settings' } else { Write-Option '4' 'Automatic (what your network provides)' }
    Write-Option '0' 'Back'
    Write-Info 'Tip: run Network check (11) first to see which one is fastest for you.'
    $c = Read-Choice
    if (-not $c -or $c -eq '0') { return }
    if ($script:DryRun) { Write-Info 'Analyze-only mode: nothing was changed.'; return }
    if ($script:DnsProviders.Contains($c)) {
        if (-not $hasBackup) { Save-DnsBackup $adapters }
        $prov = $script:DnsProviders[$c]
        foreach ($a in $adapters) {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $prov.Servers -ErrorAction Stop
                Write-Ok (L '{0}: now using {1}' $a.Name $prov.Name)
            } catch { Write-Warn ('{0}: {1}' -f $a.Name, $_.Exception.Message) }
        }
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Info 'You can go back at any time with option 4 on this screen.'
    } elseif ($c -eq '4') {
        Restore-DnsServers $adapters
    }
}

function Clear-Dns {
    Write-Step 'Flushing DNS cache'
    if ($script:DryRun) { return }
    try { Clear-DnsClientCache -ErrorAction Stop } catch { ipconfig /flushdns | Out-Null }
    Write-Ok 'DNS cache flushed.'
}

function Reset-NetworkStack {
    Write-Warn 'A full network reset fixes broken connections, but it also:'
    Write-Info '- erases manually set (static) IP / DNS settings'
    Write-Info '- can break some VPN or proxy software until it is reconfigured'
    Write-Info '- needs a restart to finish'
    $static = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.Dhcp -eq 'Disabled' -and $_.ConnectionState -eq 'Connected' -and $_.InterfaceAlias -notlike 'Loopback*' })
    if ($static.Count -gt 0) {
        Write-Warn (L 'Static IP detected on: {0}' (($static | ForEach-Object { $_.InterfaceAlias }) -join ', '))
    }
    if (-not (Confirm-Action 'Reset the network stack now?' $false)) { Write-Info 'Cancelled.'; return }
    if ($script:DryRun) { Write-Info 'Analyze-only mode: nothing was changed.'; return }
    $backup = Join-Path $script:LogDir ('network-before-reset_{0:yyyyMMdd_HHmmss}.txt' -f (Get-Date))
    ipconfig /all | Out-File -FilePath $backup -Encoding UTF8
    netsh winsock reset | Out-Null
    netsh int ip reset | Out-Null
    netsh int ipv6 reset | Out-Null
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Ok 'Network stack reset.'
    Write-Info (L 'Your previous network settings were saved to: {0}' $backup)
    Write-Warn 'Restart your PC to finish.'
    if (Confirm-Action 'Restart now?' $false) { Restart-Computer -Force }
}

# ==================================================================
#  OPTIMIZE  (15-18)
# ==================================================================
function Optimize-Drives {
    Write-Step 'Optimizing drives - Windows picks TRIM for SSDs and defrag for hard drives'
    if ($script:DryRun) { return }
    $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and ($_.FileSystem -eq 'NTFS' -or $_.FileSystem -eq 'ReFS') })
    foreach ($v in $volumes) {
        $letter = "$($v.DriveLetter)"
        $media  = '?'
        try {
            $num = (Get-Partition -DriveLetter $letter -ErrorAction Stop).DiskNumber
            $pd  = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq "$num" } | Select-Object -First 1
            if ($pd) { $media = "$($pd.MediaType)" }
        } catch { }
        Write-Info "${letter}: ($media)..."
        try {
            Optimize-Volume -DriveLetter $letter -ErrorAction Stop
            Write-Ok (L '{0}: optimized.' $letter)
        } catch {
            Write-Warn ('{0}: {1}' -f $letter, $_.Exception.Message)
        }
    }
}

function Set-YsoPowerPlan {
    $active = (powercfg /getactivescheme) -join ' '
    Write-Section 'POWER PLAN'
    Write-Kv 'Current' ($active -replace '^[^:]*:\s*', '')
    if (Test-IsLaptop) { Write-Warn 'Laptop detected: performance plans mean more heat, more fan noise and less battery.' }
    Write-Host ''
    Write-Option '1' 'Ultimate Performance (desktops - maximum responsiveness)'
    Write-Option '2' 'High Performance'
    Write-Option '3' 'Balanced (Windows default - best for laptops)'
    Write-Option '0' 'Back'
    $want = $null; $name = ''
    switch (Read-Choice) {
        '1' {
            if (((powercfg /list) -join ' ') -notmatch $script:PlanUltimateYso) {
                powercfg /duplicatescheme $script:PlanUltimateTemplate $script:PlanUltimateYso 2>&1 | Out-Null
            }
            $want = $script:PlanUltimateYso; $name = (N 'Ultimate Performance')
        }
        '2' { $want = $script:PlanHigh; $name = (N 'High Performance') }
        '3' { $want = $script:PlanBalanced; $name = (N 'Balanced') }
        default { return }
    }
    if ($script:DryRun) { Write-Info 'Analyze-only mode: nothing was changed.'; return }
    powercfg /setactive $want 2>&1 | Out-Null
    if (((powercfg /getactivescheme) -join ' ') -match $want) { Write-Ok (L '{0} plan is now active.' (L $name)); return }
    if ($want -eq $script:PlanUltimateYso) {
        powercfg /setactive $script:PlanHigh 2>&1 | Out-Null
        if (((powercfg /getactivescheme) -join ' ') -match $script:PlanHigh) {
            Write-Ok 'Ultimate is not available here - High Performance is now active instead.'
            return
        }
    }
    Write-Warn 'This PC only offers the Balanced plan (normal on Modern Standby laptops).'
    Write-Info 'Use Settings > System > Power > Power mode > Best performance instead.'
    if (Confirm-Action 'Open Power settings now?' $true) { Start-Process 'ms-settings:powersleep' }
}

function Get-StartupSources {
    # Where Windows looks for programs to start, and where Task Manager stores "on/off" for each one.
    $u  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion'
    $m  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
    $sa = 'Explorer\StartupApproved'
    return @(
        @{ Type = 'Run';    Path = "$u\Run"; Approved = "$u\$sa\Run"; Scope = (N 'you') },
        @{ Type = 'Run';    Path = "$m\Run"; Approved = "$m\$sa\Run"; Scope = (N 'everyone') },
        @{ Type = 'Run';    Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "$m\$sa\Run32"; Scope = (N 'everyone') },
        @{ Type = 'Folder'; Path = [Environment]::GetFolderPath('Startup');       Approved = "$u\$sa\StartupFolder"; Scope = (N 'you') },
        @{ Type = 'Folder'; Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "$m\$sa\StartupFolder"; Scope = (N 'everyone') }
    )
}

function Get-RunValues([string]$Key) {
    $h = [ordered]@{}
    $item = Get-Item -LiteralPath $Key -ErrorAction SilentlyContinue
    if (-not $item) { return $h }
    foreach ($n in @($item.GetValueNames())) { if ($n) { $h[$n] = "$($item.GetValue($n))" } }
    return $h
}

function Get-ApprovedBytes([string]$Key, [string]$Name) {
    $item = Get-Item -LiteralPath $Key -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    $v = $item.GetValue($Name, $null)
    if ($v -is [byte[]]) { return , $v }
    return $null
}

function Set-ApprovedBytes([string]$Key, [string]$Name, [byte[]]$Bytes) {
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force | Out-Null }
    New-ItemProperty -LiteralPath $Key -Name $Name -Value $Bytes -PropertyType Binary -Force -ErrorAction Stop | Out-Null
}

function Test-StartupApproved($Bytes) {
    # Task Manager writes 02 (on) or 03 (off) in the first byte; Windows also uses 06 / 07. Nothing = on.
    if ($null -eq $Bytes -or @($Bytes).Count -eq 0) { return $true }
    return ((([int]$Bytes[0]) -band 1) -eq 0)
}

function New-StartupApprovedBytes([bool]$Enabled) {
    # Exactly what Task Manager writes: 02 + zeros = on; 03 + three zeros + the time it was switched off = off.
    if ($Enabled) { return , [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
    return , [byte[]](@(3, 0, 0, 0) + @([BitConverter]::GetBytes([long](Get-Date).ToFileTimeUtc())))
}

function Get-ShortcutTarget([string]$Path) {
    try { return (New-Object -ComObject 'WScript.Shell').CreateShortcut($Path).TargetPath } catch { return $null }
}

function Get-StartupEntries {
    # Every program that starts with Windows, on or off. -Fast skips the digital signatures (counting only).
    param([switch]$Fast)
    $list = @()
    foreach ($src in Get-StartupSources) {
        $found = @()
        if ($src.Type -eq 'Run') {
            $vals = Get-RunValues $src.Path
            foreach ($n in @($vals.Keys)) { $found += , @($n, $vals[$n], $n) }
        } elseif ($src.Path -and (Test-Path -LiteralPath $src.Path)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $src.Path -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
                $target = $f.FullName
                if ($f.Extension -eq '.lnk' -and -not $Fast) { $t = Get-ShortcutTarget $f.FullName; if ($t) { $target = $t } }
                $found += , @([System.IO.Path]::GetFileNameWithoutExtension($f.Name), $target, $f.Name)
            }
        }
        foreach ($x in $found) {
            $exe = Resolve-ExePath $x[1]
            $sig = if ($Fast) { [pscustomobject]@{ Status = '?'; Signer = '' } } else { Get-SignerInfo $exe }
            $list += [pscustomobject]@{
                Name = $x[0]; Command = $x[1]; Exe = $exe; Publisher = $sig.Signer; Signed = ($sig.Status -eq 'Valid')
                Enabled = (Test-StartupApproved (Get-ApprovedBytes $src.Approved $x[2])); Scope = $src.Scope
                Approved = $src.Approved; ValueName = $x[2]; IsWindows = ("$($sig.Signer)" -match '^Microsoft Windows')
            }
        }
    }
    return $list
}

function Set-StartupEntryState($Entry, [bool]$Enabled) {
    Set-ApprovedBytes $Entry.Approved $Entry.ValueName (New-StartupApprovedBytes $Enabled)
    $Entry.Enabled = $Enabled
    try {
        [pscustomobject]@{ When = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Name = $Entry.Name; State = $(if ($Enabled) { 'on' } else { 'off' }); Command = $Entry.Command } |
            Export-Csv -LiteralPath (Join-Path $script:DataDir 'startup-changes.csv') -Append -NoTypeInformation -Encoding UTF8
    } catch { }
}

function Get-BootSlowApps {
    # Programs Windows itself measured slowing down a boot in the last 90 days (exe name -> seconds).
    $h = @{}
    foreach ($e in @(Get-EventsSafe @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 101; StartTime = (Get-Date).AddDays(-90) })) {
        $f = Get-EventFields $e
        $n = "$($f['Name'])".ToLowerInvariant()
        if ($n) { $h[$n] = [math]::Max([double]$h[$n], [double]$f['DegradationTime'] / 1000) }
    }
    return $h
}

function Show-StartupApps {
    while ($true) {
        Clear-Host
        Write-Section 'PROGRAMS THAT START WITH WINDOWS'
        $entries = @(Get-StartupEntries | Sort-Object @{ Expression = { -not $_.Enabled } }, Name)
        $slow = Get-BootSlowApps
        if ($entries.Count -eq 0) { Write-Info 'No startup entries found.' }
        $i = 0
        foreach ($e in $entries) {
            $i++
            Write-Host ('  {0,3}  ' -f $i) -NoNewline -ForegroundColor Green
            if ($e.Enabled) { Write-Host ('{0,-10}' -f (L 'ON')) -NoNewline -ForegroundColor Green } else { Write-Host ('{0,-10}' -f (L 'OFF')) -NoNewline -ForegroundColor DarkGray }
            Write-Host (' ' + (Get-Truncated $e.Name 30).PadRight(31)) -NoNewline
            $pub = if ($e.Publisher) { $e.Publisher } else { L '(not signed)' }
            Write-Host ((Get-Truncated $pub 28).PadRight(29)) -NoNewline -ForegroundColor $(if ($e.Publisher) { 'Gray' } else { 'Yellow' })
            Write-Host ((L $e.Scope).PadRight(10)) -NoNewline -ForegroundColor DarkGray
            $leaf = if ($e.Exe) { @("$($e.Exe)" -split '[\\/]')[-1].ToLowerInvariant() } else { '' }
            if ($leaf -and $slow.ContainsKey($leaf)) { Write-Host (L '+{0:N1} s at boot' $slow[$leaf]) -ForegroundColor Yellow } else { Write-Host '' }
        }
        $on = @($entries | Where-Object { $_.Enabled }).Count
        Write-Host ''
        Write-Info (L '{0} start with Windows, {1} switched off.' $on ($entries.Count - $on))
        Write-Info 'Switching one off only stops it starting by itself: it stays installed, and you can switch it back on here, in Task Manager or in Settings.'
        Write-Info 'Apps from the Microsoft Store manage their own startup: S opens Windows Settings.'
        $c = Read-Choice 'Number = switch on/off, S = Windows Settings, Enter = back'
        if (-not $c) { return }
        if ($c -eq 'S') {
            if ($script:Build -ge 17134) { Start-Process 'ms-settings:startupapps' } else { Start-Process taskmgr.exe }
            continue
        }
        if ($c -notmatch '^\d+$' -or [int]$c -lt 1 -or [int]$c -gt $entries.Count) { continue }
        $e = $entries[[int]$c - 1]
        if ($e.Enabled -and $e.IsWindows -and -not (Confirm-Action (L '{0} is part of Windows. Switch it off anyway?' $e.Name) $false)) { continue }
        if ($script:DryRun) { Write-Info 'Analyze-only mode: nothing was changed.'; Start-Sleep -Seconds 2; continue }
        try {
            Set-StartupEntryState $e (-not $e.Enabled)
            if ($e.Enabled) { Write-Ok (L '{0} will start with Windows again.' $e.Name) } else { Write-Ok (L '{0} will no longer start with Windows.' $e.Name) }
        } catch { Write-Warn (L 'Could not change it: {0}' $_.Exception.Message) }
        Start-Sleep -Seconds 1
    }
}

function Get-EventFields($Record) {
    $h = @{}
    try { foreach ($d in ([xml]$Record.ToXml()).Event.EventData.Data) { $h[$d.Name] = $d.'#text' } } catch { }
    return $h
}

function Get-EventsSafe {
    # Reads a Windows event log without crashing. When a log is missing or cannot be queried on this Windows
    # (seen on Windows Server), Get-WinEvent throws "The parameter is incorrect" even with -ErrorAction
    # SilentlyContinue. Returns the events (or nothing); $script:LastEventError says why nothing could be
    # read, and is $null when the log was read fine (with or without matching events).
    param([hashtable]$Filter, [int]$MaxEvents = 0)
    $script:LastEventError = $null
    $query = @{ FilterHashtable = $Filter; ErrorAction = 'SilentlyContinue' }
    if ($MaxEvents -gt 0) { $query.MaxEvents = $MaxEvents }
    try { return @(Get-WinEvent @query) }
    catch {
        $script:LastEventError = ("$($_.Exception.Message)" -replace '\s*[\r\n]+\s*', ' ').Trim()
        if (-not $script:LastEventError) { $script:LastEventError = '?' }
        return @()
    }
}

function Show-BootTimes {
    Write-Step 'Reading the boot records Windows keeps (read-only)...'
    $log   = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    $boots = @(Get-EventsSafe @{ LogName = $log; Id = 100 } -MaxEvents 10)
    if ($boots.Count -eq 0) {
        if ($script:LastEventError) { Write-Warn (L 'Windows cannot read its boot records here: {0}' $script:LastEventError) }
        else { Write-Warn 'Windows has no boot records yet (the Diagnostic Policy Service may be off, or the PC has not restarted recently).' }
        return
    }
    Write-Section 'LAST BOOTS'
    $totals = @()
    foreach ($e in $boots) {
        $f    = Get-EventFields $e
        $t    = [double]$f['BootTime'] / 1000
        $main = [double]$f['MainPathBootTime'] / 1000
        $post = [double]$f['BootPostBootTime'] / 1000
        $totals += $t
        $color = if ($t -lt 30) { 'Green' } elseif ($t -lt 60) { 'Yellow' } else { 'Red' }
        Write-Host ('  {0:yyyy-MM-dd HH:mm}  ' -f $e.TimeCreated) -NoNewline -ForegroundColor DarkGray
        Write-Host ('{0,6:N1} s' -f $t) -NoNewline -ForegroundColor $color
        Write-Host ('   ' + (L '(Windows {0:N1} s + desktop {1:N1} s)' $main $post)) -ForegroundColor DarkGray
    }
    $avg = ($totals | Measure-Object -Average).Average
    $verdict = if ($avg -lt 30) { L 'fast' } elseif ($avg -lt 60) { L 'normal' } elseif ($avg -lt 120) { L 'slow' } else { L 'very slow' }
    Write-Host ''
    Write-Kv 'Average boot' (L '{0:N1} s ({1})' $avg $verdict) $(if ($avg -lt 30) { 'Green' } elseif ($avg -lt 60) { 'Yellow' } else { 'Red' })
    Write-Info 'Only full boots are measured: Restart, or Shut down when Fast Startup is off.'

    $slow = @(Get-EventsSafe @{ LogName = $log; Id = 101, 102, 103; StartTime = (Get-Date).AddDays(-90) })
    if ($slow.Count -eq 0) { Write-Ok 'No program has noticeably slowed down your boots recently.'; return }
    Write-Section 'WHAT SLOWED BOOTS DOWN (last 90 days)'
    $rows = @(foreach ($e in $slow) {
        $f = Get-EventFields $e
        $kind = switch ($e.Id) { 101 { N 'App' } 102 { N 'Driver' } default { N 'Service' } }
        $name = if ($f['FriendlyName']) { $f['FriendlyName'] } elseif ($f['Name']) { $f['Name'] } else { '?' }
        [pscustomobject]@{ Kind = $kind; Name = $name; Delay = [double]$f['DegradationTime'] }
    })
    $groups = @($rows | Group-Object Kind, Name | ForEach-Object {
        [pscustomobject]@{
            Kind = $_.Group[0].Kind; Name = $_.Group[0].Name; Count = $_.Count
            Avg  = ($_.Group | Measure-Object -Property Delay -Average).Average
        }
    } | Sort-Object { $_.Avg * $_.Count } -Descending | Select-Object -First 10)
    foreach ($g in $groups) {
        Write-Host ('  {0,-9} ' -f (L $g.Kind)) -NoNewline -ForegroundColor Yellow
        Write-Host ((Get-Truncated $g.Name 40).PadRight(41)) -NoNewline
        Write-Host (L '+{0:N1} s, {1} time(s)' ($g.Avg / 1000) $g.Count) -ForegroundColor DarkGray
    }
    Write-Info 'Apps: switch them off in Startup programs (17). Drivers and services: update or uninstall the program they belong to.'
}

# ==================================================================
#  DIAGNOSE & REPAIR  (19-26) - read-only unless you confirm a fix
# ==================================================================
function Get-WindowsUpdateStatus {
    # When Windows last installed an update, when it last checked, and what is waiting. -Pending also
    # counts the updates Windows Update already knows about (from its last check, no download).
    param([switch]$Pending)
    $st = [pscustomobject]@{ Disabled = $false; LastInstall = $null; LastCheck = $null; Pending = $null; RestartPending = (Test-PendingReboot) }
    $svc = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
    if ($svc -and "$($svc.StartType)" -eq 'Disabled') { $st.Disabled = $true }
    try {
        $searcher = (New-UpdateSession).CreateUpdateSearcher()
        $n = [int]$searcher.GetTotalHistoryCount()
        if ($n -gt 0) {
            $hist = $searcher.QueryHistory(0, [math]::Min($n, 100))
            for ($i = 0; $i -lt $hist.Count; $i++) {
                $e = $hist.Item($i)
                if ([int]$e.Operation -eq 1 -and @(2, 3) -contains [int]$e.ResultCode) {
                    $d = ([datetime]$e.Date).ToLocalTime()
                    if (-not $st.LastInstall -or $d -gt $st.LastInstall) { $st.LastInstall = $d }
                }
            }
        }
        if ($Pending -and -not $st.Disabled) {
            $searcher.Online = $false
            $st.Pending = [int]$searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'").Updates.Count
        }
    } catch { }
    if (-not $st.LastInstall) {
        try { $st.LastInstall = @(Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn)[-1].InstalledOn } catch { }
    }
    try {
        $d = (New-Object -ComObject 'Microsoft.Update.AutoUpdate').Results.LastSearchSuccessDate
        if ($d -and ([datetime]$d).Year -gt 2000) { $st.LastCheck = ([datetime]$d).ToLocalTime() }
    } catch { }
    return $st
}

function Format-DaysAgo($Date) {
    if (-not $Date) { return (L 'unknown') }
    $days = [int](((Get-Date).Date - ([datetime]$Date).Date).TotalDays)   # calendar days: yesterday 23:00 is yesterday
    if ($days -le 0) { return (L 'today') }
    if ($days -eq 1) { return (L 'yesterday') }
    return (L '{0} days ago' $days)
}

function New-HealthItem([string]$Name, [string]$Level, [string]$Text, [string]$Action = '') {
    # Level: Good, Warn, Bad, Info. Action: the menu key that helps.
    return [pscustomobject]@{ Name = $Name; Level = $Level; Text = $Text; Action = $Action }
}

function Get-HealthItems {
    # The state of the PC in a few lines - data only, so the console and a graphical interface show
    # the same thing. Each check stands alone: one that fails never hides the others.
    $items = New-Object System.Collections.Generic.List[object]
    try {
        $sys = "$env:SystemDrive".TrimEnd(':', '\')
        $v = @(Get-FixedVolumes | Where-Object { "$($_.DriveLetter)" -eq $sys }) | Select-Object -First 1
        if ($v -and $v.Size -gt 0) {
            $pct = 100 * $v.SizeRemaining / $v.Size
            $lvl = if ($pct -lt 5) { 'Bad' } elseif ($pct -lt 15) { 'Warn' } else { 'Good' }
            $items.Add((New-HealthItem (N 'Disk space') $lvl (L '{0}: {1} free of {2} ({3:N0} %)' $sys (Format-Size $v.SizeRemaining) (Format-Size $v.Size) $pct) $(if ($lvl -ne 'Good') { 'F' } else { '' })))
        }
    } catch { }
    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop)
        $wear = $null
        try { foreach ($r in @($disks | Get-StorageReliabilityCounter -ErrorAction Stop)) { if ($null -ne $r.Wear -and ($null -eq $wear -or $r.Wear -gt $wear)) { $wear = [int]$r.Wear } } } catch { }
        if (@($disks | Where-Object { "$($_.HealthStatus)" -eq 'Unhealthy' }).Count -gt 0) { $items.Add((New-HealthItem (N 'Disk health') 'Bad' (L 'a drive reports a failure - back up your files now') '19')) }
        elseif (@($disks | Where-Object { "$($_.HealthStatus)" -eq 'Warning' }).Count -gt 0 -or $wear -ge 80) { $items.Add((New-HealthItem (N 'Disk health') 'Warn' $(if ($wear -ge 80) { L 'worn ({0} %) - keep backups up to date' $wear } else { L 'a drive reports a warning' }) '19')) }
        elseif ($disks.Count -gt 0) { $items.Add((New-HealthItem (N 'Disk health') 'Good' $(if ($null -ne $wear) { L 'healthy (wear {0} %)' $wear } else { L 'healthy' }))) }
    } catch { }
    try {
        if (Test-IsLaptop) {
            $bh = Get-BatteryHealth
            if ($bh) {
                $v = Get-BatteryVerdict $bh
                $items.Add((New-HealthItem (N 'Battery') $v.Level $v.Text $(if ($v.Level -ne 'Good') { '19' } else { '' })))
            }
        }
    } catch { }
    try {
        $wu = Get-WindowsUpdateStatus
        $age = if ($wu.LastInstall) { ((Get-Date) - $wu.LastInstall).TotalDays } else { 999 }
        $lvl = if ($wu.Disabled -or $age -gt 90) { 'Bad' } elseif ($age -gt 40 -or $wu.RestartPending) { 'Warn' } else { 'Good' }
        $text = if ($wu.Disabled) { L 'turned off on this PC' } else { L 'last update installed {0}' (Format-DaysAgo $wu.LastInstall) }
        if ($wu.RestartPending) { $text += ' - ' + (L 'restart to finish') }
        $items.Add((New-HealthItem (N 'Windows Update') $lvl $text $(if ($lvl -ne 'Good') { '19' } else { '' })))
    } catch { }
    try {
        $sec = $null
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            if ($mp.RealTimeProtectionEnabled) {
                if ($mp.AntivirusSignatureAge -gt 7) { $sec = New-HealthItem (N 'Security') 'Warn' (L 'Microsoft Defender on, definitions {0} days old' $mp.AntivirusSignatureAge) '21' }
                else { $sec = New-HealthItem (N 'Security') 'Good' (L 'Microsoft Defender on') }
            }
        } catch { }
        if (-not $sec) {
            $av = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
                Where-Object { (([int]$_.productState) -band 0x1000) -ne 0 } | ForEach-Object { $_.displayName })
            if ($av.Count -gt 0) { $sec = New-HealthItem (N 'Security') 'Good' (L '{0} on' ($av -join ', ')) }
            else { $sec = New-HealthItem (N 'Security') 'Bad' (L 'no antivirus is protecting this PC') '21' }
        }
        $items.Add($sec)
    } catch { }
    try {
        $n = @(Get-StartupEntries -Fast | Where-Object { $_.Enabled }).Count
        $items.Add((New-HealthItem (N 'Startup programs') $(if ($n -gt 12) { 'Warn' } else { 'Good' }) (L '{0} start with Windows' $n) $(if ($n -gt 12) { '17' } else { '' })))
    } catch { }
    try {
        $last = $null
        if (Test-Path -LiteralPath $script:HistoryPath) {
            $runs = @(Import-Csv -LiteralPath $script:HistoryPath -ErrorAction Stop | Where-Object { $_.Run -and $_.Run.Length -ge 10 } | ForEach-Object { $_.Run } | Sort-Object)
            if ($runs.Count -gt 0) { $last = [datetime]::ParseExact($runs[-1].Substring(0, 10), 'yyyy-MM-dd', $null) }
        }
        $auto = [bool](Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue)
        if ($auto) { $items.Add((New-HealthItem (N 'Cleaning') 'Good' ((L 'weekly auto-clean on') + $(if ($last) { ', ' + (L 'last {0}' (Format-DaysAgo $last)) } else { '' })))) }
        elseif (-not $last) { $items.Add((New-HealthItem (N 'Cleaning') 'Warn' (L 'never cleaned with YSO') 'A')) }
        else {
            $age = ((Get-Date) - $last).TotalDays
            $items.Add((New-HealthItem (N 'Cleaning') $(if ($age -gt 60) { 'Warn' } else { 'Good' }) (L 'last cleanup {0}' (Format-DaysAgo $last)) $(if ($age -gt 60) { 'F' } else { '' })))
        }
    } catch { }
    try {
        $mode = Get-UpdateMode
        $lastRun = @(Get-UpdateHistoryRows | Where-Object { $_.Kind -eq 'Run' }) | Select-Object -Last 1
        if ($mode -ne 'manual') { $items.Add((New-HealthItem (N 'App updates') 'Good' ((Get-UpdateModeText $mode) + ', ' + (Get-UpdateScheduleText)))) }
        elseif ($lastRun) { $items.Add((New-HealthItem (N 'App updates') 'Info' (L 'manual, last check {0}' (Format-DaysAgo ([datetime]::ParseExact("$($lastRun.Run)".Substring(0, 10), 'yyyy-MM-dd', $null)))) '28')) }
        else { $items.Add((New-HealthItem (N 'App updates') 'Info' (L 'manual - never checked with YSO') '28')) }
    } catch { }
    try {
        $up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        if ($up.TotalDays -gt 14) { $items.Add((New-HealthItem (N 'Restart') 'Warn' (L 'not restarted for {0} days - Restart (not Shut down) once in a while' ([int]$up.TotalDays)))) }
    } catch { }
    return $items
}

function Get-HealthItemsCached {
    # The menu shows the health of the PC: measured again after an option ran, or after 5 minutes.
    if ($script:HealthCache -and ((Get-Date) - $script:HealthCache.When).TotalMinutes -lt 5) { return $script:HealthCache.Items }
    $items = @(Get-HealthItems)
    $script:HealthCache = [pscustomobject]@{ When = (Get-Date); Items = $items }
    return $items
}

function Show-HealthDashboard([object[]]$Items) {
    $marks = @{ Good = @(' OK ', 'Green'); Warn = @(' !! ', 'Yellow'); Bad = @(' XX ', 'Red'); Info = @(' -- ', 'DarkGray') }
    foreach ($i in $Items) {
        $m = $marks[$i.Level]; if (-not $m) { $m = $marks['Info'] }
        Write-Host '  [' -NoNewline -ForegroundColor DarkGray
        Write-Host $m[0] -NoNewline -ForegroundColor $m[1]
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host ((Get-Truncated (L $i.Name) 24).PadRight(25)) -NoNewline
        Write-Host (Get-Truncated $i.Text 68) -NoNewline -ForegroundColor Gray
        if ($i.Action) { Write-Host ('  -> ' + $i.Action) -ForegroundColor Cyan } else { Write-Host '' }
    }
}

function Show-HealthReport {
    Write-Step 'Collecting system health (read-only)...'
    Write-Section 'AT A GLANCE'
    $script:HealthCache = $null
    Show-HealthDashboard @(Get-HealthItemsCached)
    Write-Info 'The arrow shows the option that helps.'
    $os       = Get-CimInstance Win32_OperatingSystem
    $cpu      = @(Get-CimInstance Win32_Processor)
    $uptime   = (Get-Date) - $os.LastBootUpTime
    $ramTotal = [double]$os.TotalVisibleMemorySize * 1KB
    $ramFree  = [double]$os.FreePhysicalMemory * 1KB
    $ramPct   = [math]::Round(100 * ($ramTotal - $ramFree) / $ramTotal)
    $cpuLoad  = [math]::Round([double](($cpu | Measure-Object -Property LoadPercentage -Average).Average))

    Write-Section 'SYSTEM'
    Write-Kv 'Windows'   ('{0} (build {1})' -f $os.Caption, $os.BuildNumber)
    Write-Kv 'Processor' ("$($cpu[0].Name)".Trim())
    Write-Kv 'CPU load'  "$cpuLoad %" $(if ($cpuLoad -gt 80) { 'Yellow' } else { 'Green' })
    Write-Kv 'Memory'    (L '{0} of {1} in use ({2} %)' (Format-Size ($ramTotal - $ramFree)) (Format-Size $ramTotal) $ramPct) $(if ($ramPct -gt 85) { 'Yellow' } else { 'Green' })
    $upText = '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    if ($uptime.TotalDays -gt 7) { $upText += '  ' + (L '- use Restart (not Shut down) once in a while') }
    Write-Kv 'Uptime' $upText $(if ($uptime.TotalDays -gt 7) { 'Yellow' } else { 'Green' })

    Write-Section 'STORAGE'
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | Sort-Object DriveLetter)) {
        if ($v.Size -le 0) { continue }
        $pct   = [math]::Round(100 * $v.SizeRemaining / $v.Size)
        $color = if ($pct -lt 5) { 'Red' } elseif ($pct -lt 15) { 'Yellow' } else { 'Green' }
        Write-Kv (L 'Drive {0}:' $v.DriveLetter) (L '{0} free of {1} ({2} % free)' (Format-Size $v.SizeRemaining) (Format-Size $v.Size) $pct) $color
    }
    try {
        foreach ($pd in @(Get-PhysicalDisk -ErrorAction Stop)) {
            $notes = @()
            try {
                $rel = $pd | Get-StorageReliabilityCounter -ErrorAction Stop
                if ($null -ne $rel.Wear -and $rel.Wear -gt 0) { $notes += (L 'wear {0} %' $rel.Wear) }
                if ($rel.Temperature -gt 0)                   { $notes += "$($rel.Temperature) C" }
                if ($rel.ReadErrorsUncorrected -gt 0)         { $notes += (L '{0} uncorrected read errors' $rel.ReadErrorsUncorrected) }
            } catch { }
            $detail = "$($pd.FriendlyName) - $($pd.HealthStatus)"
            if ($notes.Count -gt 0) { $detail += ' (' + ($notes -join ', ') + ')' }
            Write-Kv (L '{0} disk' "$($pd.MediaType)") $detail $(if ("$($pd.HealthStatus)" -eq 'Healthy') { 'Green' } else { 'Red' })
        }
    } catch { }

    Write-Section 'TOP MEMORY USERS'
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
        ForEach-Object { Write-Kv $_.ProcessName (Format-Size $_.WorkingSet64) }

    Write-Section 'STATUS'
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        Write-Kv 'Defender real-time' (Format-OnOff $mp.RealTimeProtectionEnabled) (Get-StatusColor $mp.RealTimeProtectionEnabled)
        Write-Kv 'Virus definitions' (L '{0} day(s) old' $mp.AntivirusSignatureAge) $(if ($mp.AntivirusSignatureAge -gt 7) { 'Yellow' } else { 'Green' })
    } catch {
        Write-Kv 'Defender' (L 'not active (another antivirus may be in charge)')
    }
    $pending = Test-PendingReboot
    Write-Kv 'Restart pending' $(if ($pending) { L 'YES - restart to finish installing updates' } else { L 'no' }) $(if ($pending) { 'Yellow' } else { 'Green' })

    Write-Section 'WINDOWS UPDATE'
    Write-Info 'Reading what Windows Update recorded (no download)...'
    $wu = Get-WindowsUpdateStatus -Pending
    if ($wu.Disabled) { Write-Kv 'Windows Update' (L 'turned off on this PC (its service is disabled)') 'Red' }
    $age = if ($wu.LastInstall) { ((Get-Date) - $wu.LastInstall).TotalDays } else { 999 }
    Write-Kv 'Last update installed' ('{0}  ({1})' -f $(if ($wu.LastInstall) { $wu.LastInstall.ToString('d') } else { '?' }), (Format-DaysAgo $wu.LastInstall)) $(if ($age -gt 90) { 'Red' } elseif ($age -gt 40) { 'Yellow' } else { 'Green' })
    if ($wu.LastCheck) { Write-Kv 'Last check' ('{0}  ({1})' -f $wu.LastCheck.ToString('d'), (Format-DaysAgo $wu.LastCheck)) }
    if ($null -ne $wu.Pending) { Write-Kv 'Waiting to install' (L '{0} update(s)' $wu.Pending) $(if ($wu.Pending -gt 0) { 'Yellow' } else { 'Green' }) }
    if ($age -gt 40) { Write-Info 'Open Settings > Windows Update and check for updates. App and driver updates: option 28.' }

    Write-Section 'OTHER'
    $errors = @(Get-EventsSafe @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) }).Count
    if ($script:LastEventError) { Write-Kv 'System errors (7 days)' (L 'could not be read') 'DarkGray' }
    else { Write-Kv 'System errors (7 days)' $errors $(if ($errors -gt 25) { 'Yellow' } else { 'Green' }) }
    Write-Info 'Full security details: option 21. Crash details: option 20.'

    if (Test-IsLaptop) {
        $battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        Write-Section 'BATTERY'
        Write-Kv 'Charge' "$($battery[0].EstimatedChargeRemaining) %"
        $bh = Get-BatteryHealth
        if ($bh) {
            $v = Get-BatteryVerdict $bh
            Write-Kv 'Health' $v.Text $(switch ($v.Level) { 'Bad' { 'Red' } 'Warn' { 'Yellow' } 'Info' { 'Cyan' } default { 'Green' } })
            if ($null -ne $bh.Cycles) { Write-Kv 'Charge cycles' $bh.Cycles }
            if ($v.GaugeOff) {
                Write-Info 'A battery used this much cannot hold more than when it was new: its charge gauge is off, so its real wear is not known.'
                Write-Info 'To reset the gauge: use the battery gauge reset of your PC maker''s app (Lenovo Vantage has one), or charge to 100 %, let the PC run on battery down to about 5 % in one go, then charge to 100 % again.'
            }
        } else {
            Write-Kv 'Health' (L 'not reported by this battery') 'DarkGray'
        }
        if (Confirm-Action 'Create a detailed battery report (opens in your browser)?' $false) {
            $out = Join-Path $script:LogDir 'battery-report.html'
            powercfg /batteryreport /output "$out" | Out-Null
            if (Test-Path -LiteralPath $out) { Start-Process explorer.exe -ArgumentList "`"$out`"" }
        }
    }
}

function Show-RecentProblems {
    Write-Step 'Reading the Windows event logs (read-only - nothing is cleared)...'
    $since  = (Get-Date).AddDays(-30)
    $unread = @()
    $bsod   = @(Get-EventsSafe @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since })
    if ($script:LastEventError) { $unread += $script:LastEventError }
    $power  = @(Get-EventsSafe @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since })
    if ($script:LastEventError) { $unread += $script:LastEventError }
    $crash  = @(Get-EventsSafe @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since })
    if ($script:LastEventError) { $unread += $script:LastEventError }
    $freeze = @(Get-EventsSafe @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = $since })
    if ($script:LastEventError) { $unread += $script:LastEventError }

    Write-Section 'LAST 30 DAYS'
    Write-Kv 'Blue screens'         $bsod.Count $(if ($bsod.Count -gt 0) { 'Red' } else { 'Green' })
    Write-Kv 'Unexpected shutdowns' (L '{0}  (includes holding the power button)' $power.Count) $(if ($power.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Kv 'App crashes'          $crash.Count  $(if ($crash.Count -gt 10) { 'Yellow' } else { 'Green' })
    Write-Kv 'App freezes'          $freeze.Count $(if ($freeze.Count -gt 10) { 'Yellow' } else { 'Green' })
    if ($bsod.Count -gt 0) { Write-Info 'Blue screens: run Memory test (25) and Driver problems (23).' }
    if ($unread.Count -gt 0) { Write-Warn (L 'Some event logs could not be read, so these numbers may be too low: {0}' $unread[0]) }

    if ($crash.Count -gt 0) {
        Write-Section 'APPS THAT CRASH THE MOST'
        $crash | Group-Object { "$($_.Properties[0].Value)" } | Sort-Object Count -Descending | Select-Object -First 5 |
            ForEach-Object { Write-Kv $_.Name (L '{0} crash(es)' $_.Count) }
    }

    $errors = @(Get-EventsSafe @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) })
    if ($errors.Count -gt 0) {
        Write-Section 'TOP ERROR SOURCES (last 7 days)'
        $errors | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object {
            $msg = ("$($_.Group[0].Message)" -split "`r?`n")[0]
            if (-not $msg) { $msg = L '(event id {0})' $_.Group[0].Id }
            Write-Host ('  {0,5}x  {1,-31} {2}' -f $_.Count, (Get-Truncated $_.Name 30), (Get-Truncated $msg 60))
        }
    }
    Write-Info ''
    Write-Info 'A few errors are normal on every PC. Look for ones that repeat or match when problems happen.'
    if (Confirm-Action 'Open Reliability Monitor (a timeline of problems)?' $false) { Start-Process perfmon.exe -ArgumentList '/rel' }
}

function Show-SecurityCheck {
    Write-Step 'Checking your security settings (read-only)...'
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }

    Write-Section 'MICROSOFT DEFENDER'
    if ($mp) {
        Write-Kv 'Real-time protection' (Format-OnOff $mp.RealTimeProtectionEnabled) (Get-StatusColor $mp.RealTimeProtectionEnabled)
        if ($null -ne $mp.IsTamperProtected) {
            Write-Kv 'Tamper protection' (Format-OnOff $mp.IsTamperProtected) (Get-StatusColor $mp.IsTamperProtected 'Yellow')
        }
        Write-Kv 'Virus definitions'    (L '{0} day(s) old' $mp.AntivirusSignatureAge) $(if ($mp.AntivirusSignatureAge -gt 7) { 'Yellow' } else { 'Green' })
        $scanAge = if ($mp.QuickScanAge -ge 0 -and $mp.QuickScanAge -lt 10000) { L '{0} day(s) ago' $mp.QuickScanAge } else { L 'never' }
        Write-Kv 'Last quick scan' $scanAge $(if ($mp.QuickScanAge -le 14) { 'Green' } else { 'Yellow' })
        $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-30) })
        Write-Kv 'Threats found (30 days)' $threats.Count $(if ($threats.Count -gt 0) { 'Red' } else { 'Green' })
    } else {
        Write-Kv 'Defender' (L 'not active (another antivirus may be in charge)') 'Yellow'
    }

    Write-Section 'WINDOWS'
    $fwNames = @{ Domain = (N 'Domain network'); Private = (N 'Private network'); Public = (N 'Public network') }
    try {
        foreach ($fp in @(Get-NetFirewallProfile -ErrorAction Stop)) {
            $on = ([int]$fp.Enabled -ne 0)
            $label = if ($fwNames.ContainsKey("$($fp.Name)")) { L $fwNames["$($fp.Name)"] } else { "$($fp.Name)" }
            Write-Kv (L 'Firewall: {0}' $label) (Format-OnOff $on) (Get-StatusColor $on)
        }
    } catch { }
    try {
        $hf = Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if ($hf) {
            $age = [int]((Get-Date) - $hf.InstalledOn).TotalDays
            Write-Kv 'Last Windows update' (L '{0} ({1} days ago)' $hf.InstalledOn.ToString('d') $age) $(if ($age -gt 60) { 'Red' } elseif ($age -gt 35) { 'Yellow' } else { 'Green' })
        }
    } catch { }
    $lua = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction SilentlyContinue).EnableLUA
    Write-Kv 'User Account Control' (Format-OnOff ($lua -ne 0)) (Get-StatusColor ($lua -ne 0))
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        Write-Kv 'Secure Boot' (Format-OnOff $sb) (Get-StatusColor $sb 'Yellow')
    } catch {
        Write-Kv 'Secure Boot' (L 'not supported (legacy BIOS)') 'Yellow'
    }
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        $tpmText = if ($tpm.TpmPresent -and $tpm.TpmReady) { L 'present and ready' } elseif ($tpm.TpmPresent) { L 'present, not ready' } else { L 'not found' }
        Write-Kv 'TPM security chip' $tpmText (Get-StatusColor ($tpm.TpmPresent -and $tpm.TpmReady) 'Yellow')
    } catch { }
    $bitlocker = $null
    try {
        $bitlocker = ("$((Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop).ProtectionStatus)" -eq 'On')
    } catch {
        try {
            $ev = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$env:SystemDrive'" -ErrorAction Stop
            if ($ev) { $bitlocker = ($ev.ProtectionStatus -eq 1) }
        } catch { }
    }
    if ($null -ne $bitlocker) {
        Write-Kv (L 'Encryption of {0}' $env:SystemDrive) $(if ($bitlocker) { L 'ON (BitLocker)' } else { L 'OFF - files are readable if the PC is stolen' }) (Get-StatusColor $bitlocker 'Yellow')
    }

    Write-Host ''
    Write-Option '1' 'Update virus definitions'
    Write-Option '2' 'Run a quick scan (5-15 minutes)'
    Write-Option '3' 'Open Windows Security'
    Write-Option '0' 'Back'
    switch (Read-Choice) {
        '1' {
            if (-not $mp) { Write-Warn 'Microsoft Defender is not active on this PC.'; return }
            Write-Info 'Updating...'
            try { Update-MpSignature -ErrorAction Stop; Write-Ok 'Virus definitions are up to date.' } catch { Write-Warn $_.Exception.Message }
        }
        '2' {
            if (-not $mp) { Write-Warn 'Microsoft Defender is not active on this PC.'; return }
            $start = Get-Date
            Write-Info 'Scanning... you can keep using the PC.'
            try { Start-MpScan -ScanType QuickScan -ErrorAction Stop } catch { Write-Warn $_.Exception.Message; return }
            $found = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $start })
            if ($found.Count -gt 0) { Write-Bad (L 'Defender found {0} threat(s). Open Windows Security to review them.' $found.Count) }
            else { Write-Ok 'Quick scan finished: no threats found.' }
        }
        '3' {
            if ($script:Build -ge 15063) { Start-Process 'windowsdefender:' }
            else { Start-Process 'ms-settings:windowsdefender' }
        }
    }
}

function Resolve-ExePath([string]$CommandLine) {
    # Turns a command line ("C:\x\app.exe" -flag, %windir%\..., \SystemRoot\...) into the file it runs.
    if (-not $CommandLine) { return '' }
    $c = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    $c = $c -replace '^\\\?\?\\', ''
    if ($c -match '^\\SystemRoot\\') { $c = $env:WINDIR + $c.Substring(11) }
    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 1) { $c = $c.Substring(1, $end - 1) }
    }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd|ps1|vbs|js|dll|scr|sys))(?=\s|$|,|")', 'IgnoreCase')
    $p = if ($m.Success) { $m.Groups[1].Value } else { ($c -split '\s+')[0] }
    if ($p -notmatch '^[A-Za-z]:\\' -and $p -notmatch '^\\\\') {
        foreach ($base in @($env:WINDIR, [System.IO.Path]::Combine("$env:WINDIR", 'System32'))) {
            try {
                $cand = [System.IO.Path]::Combine($base, $p)
                if (Test-Path -LiteralPath $cand -PathType Leaf) { return $cand }
            } catch { }
        }
        $cmd = Get-Command -Name $p -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    return $p
}

function Get-SignerInfo([string]$Path) {
    if ($Path -and $script:SigCache.ContainsKey($Path)) { return $script:SigCache[$Path] }
    $r = [pscustomobject]@{ Status = 'Missing'; Signer = '' }
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        try {
            $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
            $signer = ''
            if ($s.SignerCertificate) {
                $subj = $s.SignerCertificate.Subject
                if ($subj -match '^CN="([^"]+)"') { $signer = $Matches[1] }
                elseif ($subj -match '^CN=([^,]+)') { $signer = $Matches[1] }
            }
            $r = [pscustomobject]@{ Status = "$($s.Status)"; Signer = $signer }
        } catch { $r = [pscustomobject]@{ Status = 'UnknownError'; Signer = '' } }
    }
    if ($Path) { $script:SigCache[$Path] = $r }
    return $r
}

function Test-UserWritable([string]$Path) {
    if (-not $Path) { return $false }
    return ($Path -match '\\(AppData|Temp|Downloads|Desktop)\\' -or $Path -like "$env:SystemDrive\Users\Public\*")
}

function New-AuditItem {
    param([string]$Kind, [string]$Name, [string]$Command, [string]$Exe, [string]$Detail, [bool]$MicrosoftPath = $false)
    if (-not $Exe) { $Exe = Resolve-ExePath $Command }
    $sig   = Get-SignerInfo $Exe
    $leaf  = ''
    try { $leaf = ("$Exe" -split '[\\/]')[-1].ToLower() } catch { }
    $flags = @(); $level = 0
    switch ($sig.Status) {
        'Valid'                  { }
        'NotSigned'              { $flags += (N 'not signed'); $level = 1 }
        'Missing'                { $flags += (N 'file is missing (leftover entry)') }
        'NotSupportedFileFormat' { $flags += (N 'signature cannot be checked'); $level = 1 }
        'HashMismatch'           { $flags += (N 'signature does not match the file'); $level = 2 }
        default                  { $flags += (N 'signature not trusted'); $level = 1 }
    }
    $userPath = Test-UserWritable $Exe
    if ($userPath) { $flags += (N 'runs from a user folder') }
    if ($userPath -and $sig.Status -ne 'Valid' -and $sig.Status -ne 'Missing') { $level = 2 }
    if (-not $MicrosoftPath -and $script:ScriptHosts -contains $leaf) { $flags += (N 'runs a script or command'); $level = [math]::Max($level, 1) }
    $isMs = ($sig.Status -eq 'Valid' -and $sig.Signer -like 'Microsoft*')
    return [pscustomobject]@{
        Kind = $Kind; Name = $Name; Command = $Command; File = $Exe; Signer = $sig.Signer
        Status = $sig.Status; Flags = $flags; Level = $level; IsMicrosoft = $isMs; Detail = $Detail
    }
}

function Get-AutorunItems {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($s in @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)) {
        $items.Add((New-AuditItem -Kind (N 'Startup') -Name $s.Name -Command $s.Command -Detail $s.Location))
    }
    foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        if (-not $s.PathName) { continue }
        $exe = Resolve-ExePath $s.PathName
        if ($exe -like '*\svchost.exe') {
            # Shared-host services: the code that actually runs is the ServiceDll.
            $dll = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)\Parameters" -Name ServiceDll -ErrorAction SilentlyContinue).ServiceDll
            if ($dll) { $exe = [Environment]::ExpandEnvironmentVariables($dll) }
        }
        $items.Add((New-AuditItem -Kind (N 'Service') -Name $s.DisplayName -Command $s.PathName -Exe $exe -Detail ('{0}, {1}' -f $s.State, $s.StartMode)))
    }
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        foreach ($a in @($t.Actions)) {
            if (-not $a.Execute) { continue }   # COM-handler actions have no file
            $cmd = ('"{0}" {1}' -f "$($a.Execute)".Trim('"'), $a.Arguments).Trim()
            $items.Add((New-AuditItem -Kind (N 'Task') -Name ($t.TaskPath + $t.TaskName) -Command $cmd -Detail "$($t.State)" -MicrosoftPath ($t.TaskPath -like '\Microsoft\*')))
        }
    }
    return $items
}

function Show-Audit {
    Write-Step 'Collecting startup entries, services and scheduled tasks, and checking their digital signatures...'
    Write-Info 'This takes 10-60 seconds. Nothing is changed.'
    $all     = @(Get-AutorunItems)
    $shown   = @($all | Where-Object { -not $_.IsMicrosoft -or $_.Level -gt 0 })
    $flagged = @($shown | Where-Object { $_.Level -gt 0 } | Sort-Object Level -Descending)
    $others  = @($shown | Where-Object { $_.Level -eq 0 })
    $red     = @($flagged | Where-Object { $_.Level -ge 2 }).Count

    Write-Section 'SUMMARY'
    Write-Kv 'Items checked' $all.Count
    Write-Kv 'Microsoft (not listed)' ($all.Count - $shown.Count)
    Write-Kv 'Third-party, signed' $others.Count
    Write-Kv 'Worth a look' $flagged.Count $(if ($red -gt 0) { 'Red' } elseif ($flagged.Count -gt 0) { 'Yellow' } else { 'Green' })

    if ($flagged.Count -gt 0) {
        Write-Section 'WORTH A LOOK'
        foreach ($it in $flagged) {
            $color = if ($it.Level -ge 2) { 'Red' } else { 'Yellow' }
            Write-Host ('  [{0}] ' -f (L $it.Kind)) -NoNewline -ForegroundColor $color
            Write-Host $it.Name -ForegroundColor White
            Write-Host ('        ' + (Get-ShortPath $it.Command 90)) -ForegroundColor Gray
            Write-Host ('        ' + (($it.Flags | ForEach-Object { L $_ }) -join ', ')) -ForegroundColor $color
        }
    }
    if ($others.Count -gt 0) {
        Write-Section 'OTHER THIRD-PARTY ITEMS'
        foreach ($it in ($others | Sort-Object Kind, Name)) {
            $who = if ($it.Signer) { $it.Signer } else { '-' }
            Write-Host ('  {0,-10} {1,-40} {2}' -f (L $it.Kind), (Get-Truncated $it.Name 39), (Get-Truncated $who 30))
        }
    }
    $csv = Join-Path $script:LogDir ('autorun-audit_{0:yyyyMMdd_HHmmss}.csv' -f (Get-Date))
    try {
        $all | Select-Object Kind, Name, Status, Signer, File, Command, Detail, @{ n = 'Flags'; e = { $_.Flags -join '; ' } } |
            Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
        Write-Info ''
        Write-Info (L 'Full list (Microsoft items included) saved to: {0}' $csv)
    } catch { }
    Write-Info 'Not signed does not mean malware - many small or open-source tools are unsigned.'
    Write-Info 'Look up names you do not recognize. To remove one, uninstall its program (Settings > Apps).'

    $files = @($flagged | Where-Object { $_.Status -ne 'Missing' -and $_.File -and (Test-Path -LiteralPath $_.File -PathType Leaf) } |
        ForEach-Object { $_.File } | Sort-Object -Unique)
    if ($files.Count -gt 0 -and (Get-Command -Name 'Start-MpScan' -ErrorAction SilentlyContinue)) {
        if (Confirm-Action (L 'Scan the {0} flagged file(s) with Microsoft Defender now?' $files.Count) $true) {
            $start = Get-Date
            foreach ($f in $files) {
                Write-Info (L 'Scanning {0}' (Get-ShortPath $f 70))
                try { Start-MpScan -ScanType CustomScan -ScanPath $f -ErrorAction Stop } catch { Write-Warn $_.Exception.Message }
            }
            $found = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $start })
            if ($found.Count -gt 0) { Write-Bad (L 'Defender found {0} threat(s). Open Windows Security to review them.' $found.Count) }
            else { Write-Ok 'Defender found nothing in these files.' }
        }
    }
}

function Show-DriverProblems {
    Write-Step 'Checking devices and drivers (read-only)...'
    $devices  = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 45 })
    $disabled = @($devices | Where-Object { $_.ConfigManagerErrorCode -eq 22 })
    $broken   = @($devices | Where-Object { $_.ConfigManagerErrorCode -ne 22 })
    if ($broken.Count -eq 0) {
        Write-Ok 'All devices are working normally.'
    } else {
        Write-Section 'DEVICES WITH PROBLEMS'
        foreach ($d in $broken) {
            $code = [int]$d.ConfigManagerErrorCode
            $why  = if ($script:DeviceProblems.ContainsKey($code)) { L $script:DeviceProblems[$code] } else { L 'problem code {0}' $code }
            $name = if ($d.Name) { $d.Name } else { $d.DeviceID }
            Write-Host '  [x] ' -NoNewline -ForegroundColor Red
            Write-Host $name -NoNewline -ForegroundColor White
            Write-Host ('  ({0})' -f $d.PNPClass) -ForegroundColor DarkGray
            Write-Host ('      ' + $why + ' - ' + (L 'code {0}' $code)) -ForegroundColor Yellow
        }
    }
    if ($disabled.Count -gt 0) {
        Write-Info (L '{0} device(s) are disabled on purpose (not a problem): {1}' $disabled.Count (($disabled | ForEach-Object { $_.Name }) -join ', '))
    }
    Write-Host ''
    Write-Option '1' 'Open Device Manager'
    Write-Option '2' 'Look for driver updates (Windows Update > Optional updates)'
    Write-Option '3' 'Rescan hardware'
    Write-Option '0' 'Back'
    switch (Read-Choice) {
        '1' { Start-Process devmgmt.msc }
        '2' {
            if ($script:Build -ge 19041) { Start-Process 'ms-settings:windowsupdate-optionalupdates' }
            else { Start-Process 'ms-settings:windowsupdate' }
        }
        '3' {
            if ($script:Build -lt 19041) {
                Write-Warn 'Rescanning from here needs Windows 10 version 2004 or later. In Device Manager, use Action > Scan for hardware changes.'
            } else {
                pnputil.exe /scan-devices | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Ok 'Hardware rescanned. Run this check again to see if anything changed.' }
                else { Write-Warn (L 'The rescan failed (code {0}). In Device Manager, use Action > Scan for hardware changes.' $LASTEXITCODE) }
            }
        }
    }
}

function Test-Drives {
    Write-Step 'Scanning drives for file-system errors (online - you can keep working)...'
    $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.FileSystem -eq 'NTFS' })
    foreach ($v in $volumes) {
        $letter = "$($v.DriveLetter)"
        try {
            $result = "$(Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop)"
        } catch {
            Write-Warn (L '{0}: scan failed - {1}' $letter $_.Exception.Message)
            continue
        }
        if ($result -eq 'NoErrorsFound') { Write-Ok (L '{0}: no errors found.' $letter); continue }
        Write-Warn ('{0}: {1}' -f $letter, $result)
        if ($script:DryRun) { continue }
        if ("${letter}:" -ieq $env:SystemDrive) {
            if (Confirm-Action (L 'Repair {0}: at the next restart?' $letter) $true) {
                # Marks the volume dirty so Windows repairs it before it loads (works in any language).
                fsutil dirty set "${letter}:" | Out-Null
                Write-Ok 'Repair scheduled. Restart when convenient - it runs before Windows starts.'
            }
        } elseif (Confirm-Action (L 'Repair {0}: now? (the drive may be unavailable for a moment)' $letter) $true) {
            try {
                Repair-Volume -DriveLetter $letter -SpotFix -ErrorAction Stop | Out-Null
                Write-Ok (L '{0}: repaired.' $letter)
            } catch { Write-Warn $_.Exception.Message }
        }
    }
}

function Start-MemoryTest {
    Write-Section 'MEMORY TEST'
    $last = @(Get-EventsSafe @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1) | Select-Object -First 1
    if ($last) {
        Write-Kv 'Last test' $last.TimeCreated.ToString('g')
        Write-Kv 'Result' (Get-Truncated ("$($last.Message)" -split "`r?`n")[0] 90)
    } else {
        Write-Info 'No memory test has been run on this PC yet.'
    }
    Write-Host ''
    Write-Info 'Windows Memory Diagnostic checks your RAM for faults - a common cause of blue screens and random crashes.'
    Write-Info 'It runs after a restart, before Windows loads, and takes 10-30 minutes. Save your work first.'
    Write-Info 'The result shows as a notification after Windows starts again (and here, next time).'
    if ($script:DryRun) { return }
    if (Confirm-Action 'Open Windows Memory Diagnostic now? (you then choose: restart now, or at next start)' $false) { Start-Process mdsched.exe }
}

function Invoke-SystemRepair {
    Write-Warn 'Checks and repairs Windows system files. Takes 15-45 minutes; DISM needs internet.'
    if (-not (Confirm-Action 'Start now?' $true)) { return }
    if ($script:DryRun) { Write-Info 'Analyze-only mode: nothing was changed.'; return }
    Write-Step 'Step 1/2 - DISM: repairing the Windows component store...'
    $dism = Start-Process -FilePath 'dism.exe' -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth' -NoNewWindow -Wait -PassThru
    if ($dism.ExitCode -eq 0) { Write-Ok 'DISM finished without problems.' }
    else { Write-Warn (L 'DISM returned code {0}. Details: {1}' $dism.ExitCode "$env:WINDIR\Logs\DISM\dism.log") }
    Write-Step 'Step 2/2 - SFC: verifying protected system files...'
    Start-Process -FilePath 'sfc.exe' -ArgumentList '/scannow' -NoNewWindow -Wait | Out-Null
    Write-Info (L 'If SFC repaired files, restart your PC. Details: {0}' "$env:WINDIR\Logs\CBS\CBS.log")
}

# ==================================================================
#  SPACE & APPS  (27-28)
# ==================================================================
function Get-FolderSizes {
    # One pass over a drive or folder: size of every folder (without following links)
    # plus every file of 50 MB or more. Read-only.
    param([string]$Root, [long]$BigFileMin = 50MB)
    $cmp      = [StringComparer]::OrdinalIgnoreCase
    $own      = New-Object 'System.Collections.Generic.Dictionary[string,long]' $cmp
    $children = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' $cmp
    $total    = New-Object 'System.Collections.Generic.Dictionary[string,long]' $cmp
    $order    = New-Object System.Collections.Generic.List[string]
    $big      = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $stack    = New-Object System.Collections.Generic.Stack[string]
    $denied   = 0
    $fileCount = [long]0
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $path = $stack.Pop()
        $order.Add($path)
        $kids = New-Object System.Collections.Generic.List[string]
        $children[$path] = $kids
        $sum = [long]0
        $di  = [System.IO.DirectoryInfo]::new($path)
        $files = $null
        try { $files = @($di.GetFiles()) }
        catch {
            $alt = Get-LongPath $path -Always
            if ($alt -ne $path) { try { $di = [System.IO.DirectoryInfo]::new($alt); $files = @($di.GetFiles()) } catch { } }
            if ($null -eq $files) { $denied++ }
        }
        foreach ($f in @($files)) {
            if ($null -eq $f) { continue }
            $len = $f.Length
            $sum += $len
            $fileCount++
            if ($len -ge $BigFileMin) { $big.Add($f) }
        }
        try {
            foreach ($d in $di.EnumerateDirectories()) {
                if ($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                $child = Get-LongPath $d.FullName
                $kids.Add($child)
                $stack.Push($child)
            }
        } catch { }
        $own[$path] = $sum
        if ($order.Count % 100 -eq 0) {
            Write-YsoProgress -Activity (L 'Scanning') -Status (L '{0:N0} files in {1:N0} folders' $fileCount $order.Count)
        }
    }
    Write-YsoProgress -Activity (L 'Scanning') -Completed
    # Children are always discovered after their parent, so walking backwards adds them up first.
    for ($i = $order.Count - 1; $i -ge 0; $i--) {
        $p = $order[$i]
        $t = $own[$p]
        foreach ($k in $children[$p]) { $t += $total[$k] }
        $total[$p] = $t
    }
    return [pscustomobject]@{
        Root = $Root; Own = $own; Children = $children; Total = $total; Big = $big
        Denied = $denied; Files = $fileCount; Folders = $order.Count
    }
}

function Show-BigFiles($Scan) {
    Clear-Host
    Write-Section 'BIGGEST FILES'
    $top = @($Scan.Big | Sort-Object Length -Descending | Select-Object -First 25)
    if ($top.Count -eq 0) { Write-Info 'No files of 50 MB or more were found.'; Wait-Key; return }
    $i = 0
    foreach ($f in $top) {
        $i++
        Write-Host ('  {0,3}  ' -f $i) -NoNewline -ForegroundColor Green
        Write-Host ('{0,10}  {1:yyyy-MM-dd}  ' -f (Format-Size $f.Length), $f.LastWriteTime) -NoNewline
        Write-Host (Get-ShortPath (ConvertFrom-LongPath $f.FullName) 76) -ForegroundColor Gray
    }
    Write-Host ''
    Write-Info 'Nothing is deleted here. Type a number to show that file in Explorer, then decide yourself.'
    $c = Read-Choice 'Number, or Enter to go back'
    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $top.Count) {
        Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f (ConvertFrom-LongPath $top[[int]$c - 1].FullName))
    }
}

function Show-SpaceFinder {
    Write-Section 'SPACE FINDER'
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | Sort-Object DriveLetter)) {
        Write-Kv (L 'Drive {0}:' $v.DriveLetter) (L '{0} used of {1}' (Format-Size ($v.Size - $v.SizeRemaining)) (Format-Size $v.Size))
    }
    $default = "$env:SystemDrive".TrimEnd(':')
    if (-not $default) { $default = 'C' }
    $answer = [Environment]::ExpandEnvironmentVariables("$(Read-Host ('  ' + (L 'Drive letter or folder to scan [{0}]' $default)))".Trim().Trim('"'))
    if (-not $answer) { $answer = $default }
    $root = if ($answer -match '^[A-Za-z]:?\\?$') { $answer.Substring(0, 1).ToUpper() + ':\' } else { $answer }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { Write-Warn (L 'Folder not found: {0}' $root); return }
    $root = (Get-Item -LiteralPath $root -Force).FullName
    Write-Info 'Scanning - a full drive can take a minute or two. Nothing is changed.'
    $scan = Get-FolderSizes -Root $root
    $cur  = $root
    $back = New-Object System.Collections.Generic.Stack[string]
    while ($true) {
        Clear-Host
        Write-Section (L 'SPACE FINDER - {0}' (ConvertFrom-LongPath $cur))
        $curTotal = $scan.Total[$cur]
        Write-Info (L 'Total {0}  -  {1:N0} files scanned, {2:N0} protected folders skipped' (Format-Size $curTotal) $scan.Files $scan.Denied)
        Write-Host ''
        $items = @($scan.Children[$cur] | ForEach-Object { [pscustomobject]@{ Path = $_; Size = $scan.Total[$_] } } |
            Sort-Object Size -Descending | Select-Object -First 15)
        $i = 0
        foreach ($it in $items) {
            $i++
            $share = if ($curTotal -gt 0) { $it.Size / $curTotal } else { 0 }
            $bar = ('#' * [int][math]::Round(20 * $share)).PadRight(20, '-')
            Write-Host ('  {0,3}  ' -f $i) -NoNewline -ForegroundColor Green
            Write-Host ('{0,10}  [{1}] {2,3:N0}%  ' -f (Format-Size $it.Size), $bar, (100 * $share)) -NoNewline
            Write-Host ([System.IO.Path]::GetFileName($it.Path))
        }
        if ($items.Count -eq 0) { Write-Info 'No subfolders here.' }
        $ownSize = $scan.Own[$cur]
        if ($ownSize -gt 0) {
            Write-Host ('       {0,10}  ' -f (Format-Size $ownSize)) -NoNewline
            Write-Host (L '(files directly in this folder)') -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host ('  ' + (L '[number] open folder   [B] back   [F] biggest files   [E] show in Explorer   [Q] done')) -ForegroundColor DarkGray
        $c = Read-Choice
        if ($c -eq 'Q') { break }
        elseif ($c -eq 'B') { if ($back.Count -gt 0) { $cur = $back.Pop() } }
        elseif ($c -eq 'E') { Start-Process explorer.exe -ArgumentList "`"$(ConvertFrom-LongPath $cur)`"" }
        elseif ($c -eq 'F') { Show-BigFiles $scan }
        elseif ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $items.Count) {
            $back.Push($cur)
            $cur = $items[[int]$c - 1].Path
        }
    }
}

# ==================================================================
#  UPDATES  (28) - apps with winget, drivers with Windows Update
#  Manual: you see the list and choose. Automatic: a scheduled task runs
#  "-AutoUpdate" as you (elevated), installs what is safe and never restarts the PC.
# ==================================================================
function Get-WingetPath {
    $cmd = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    if ($env:LOCALAPPDATA) {
        $cand = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $cand) { return $cand }
    }
    return $null
}

function Invoke-Winget([string[]]$Arguments) {
    # Runs winget and returns its exit code and output lines. winget writes UTF-8: without this,
    # accented app names and the "…" of shortened names come out garbled in Windows PowerShell.
    $exe = Get-WingetPath
    $saved = $null
    try { $saved = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    try {
        $lines = @(& $exe @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally {
        if ($null -ne $saved) { try { [Console]::OutputEncoding = $saved } catch { } }
    }
    return [pscustomobject]@{ Code = [int]$code; Lines = $lines }
}

function Get-WingetVersion {
    # [version] of winget, or $null. Read once per session.
    if ($script:WingetVersionRead) { return $script:WingetVersion }
    $script:WingetVersionRead = $true
    $script:WingetVersion = $null
    if (-not (Get-WingetPath)) { return $null }
    try {
        $text = "$(@((Invoke-Winget @('--version')).Lines) -join ' ')"
        $m = [regex]::Match($text, '(\d+)\.(\d+)(\.\d+)?')
        if ($m.Success) { $script:WingetVersion = [version]$m.Value }
    } catch { }
    return $script:WingetVersion
}

function Get-WingetQuietArgs {
    # --disable-interactivity exists since winget 1.4; older versions refuse unknown arguments.
    $v = Get-WingetVersion
    if ($v -and $v -ge [version]'1.4') { return @('--disable-interactivity') }
    return @()
}

function Format-HexCode([long]$Code) { return ('0x{0:X8}' -f ($Code -band 0xFFFFFFFFL)) }

function ConvertFrom-WingetRow([string]$Row, [int[]]$Starts) {
    # One table row -> Name, Id, Version, Available (or $null when it is not a row).
    $n = $Starts.Count
    $cells = $null
    $aligned = ($Row.Length -gt $Starts[3])
    for ($k = 1; $aligned -and $k -lt $n; $k++) {
        if ($Starts[$k] -lt $Row.Length -and $Row[$Starts[$k] - 1] -ne ' ') { $aligned = $false }
    }
    if ($aligned) {
        $cells = @(for ($k = 0; $k -lt $n; $k++) {
            $from = $Starts[$k]
            $to = if ($k + 1 -lt $n) { [math]::Min($Starts[$k + 1], $Row.Length) } else { $Row.Length }
            if ($from -lt $Row.Length -and $to -gt $from) { $Row.Substring($from, $to - $from).Trim() } else { '' }
        })
    } else {
        # Wide characters (Chinese, Japanese...) shift the columns: read the row from the right instead.
        $t = New-Object System.Collections.Generic.List[string]
        foreach ($w in @($Row.Trim() -split '\s+')) { $t.Add($w) }
        $cells = @('', '', '', '', '')
        if ($n -ge 5 -and $t.Count -ge 5) { $cells[4] = $t[$t.Count - 1]; $t.RemoveAt($t.Count - 1) }
        if ($t.Count -lt 4) { return $null }
        $cells[3] = $t[$t.Count - 1]; $t.RemoveAt($t.Count - 1)
        $cells[2] = $t[$t.Count - 1]; $t.RemoveAt($t.Count - 1)
        if ($t.Count -ge 3 -and @('<', '>') -contains $t[$t.Count - 1]) { $cells[2] = $t[$t.Count - 1] + ' ' + $cells[2]; $t.RemoveAt($t.Count - 1) }
        $cells[1] = $t[$t.Count - 1]; $t.RemoveAt($t.Count - 1)
        $cells[0] = ($t -join ' ')
    }
    $ellipsis = [string][char]0x2026
    $name = $cells[0]; $id = $cells[1]; $ver = $cells[2]; $avail = $cells[3]
    if (-not $name -or -not $ver) { return $null }
    if ($id -notmatch '^[^\s\.]+(\.[^\s]+)+$' -and -not ($id.EndsWith($ellipsis) -and $id -notmatch '\s')) { return $null }
    if ($avail -notmatch '\d') { return $null }
    return [pscustomobject]@{ Name = $name; Id = $id; Version = $ver; Available = $avail; Table = 'Normal'; Note = '' }
}

function ConvertFrom-WingetTable([string[]]$Lines) {
    # winget has no machine-readable output for updates, so its text tables are read like this, in
    # any language: the header is the line above the line of dashes, each column starts where a word
    # of the header starts, and the order is always Name, Id, Version, Available (, Source).
    # The first table lists normal updates. Tables printed after a sentence are apps winget will not
    # update on its own (they need explicit targeting or their own updater): Table = 'Special'.
    $text = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($Lines)) {
        $l = ("$raw" -replace '\x1b\[[0-9;?]*[A-Za-z]', '').Replace([string][char]8, '')
        $parts = @($l -split "`r" | Where-Object { $_.Trim() })   # spinners and progress bars rewrite the line
        $l = if ($parts.Count -gt 0) { $parts[$parts.Count - 1].TrimEnd() } else { '' }
        $t = $l.Trim()
        if ($t -match '^[-\\|/]$' -or $t -match '[▀-▟]') { continue }
        $text.Add($l)
    }
    $rows = @()
    $tableNo = 0
    for ($i = 1; $i -lt $text.Count; $i++) {
        if ($text[$i] -notmatch '^\s*-{10,}\s*$') { continue }
        $header = $text[$i - 1]
        $starts = @(for ($c = 0; $c -lt $header.Length; $c++) {
            if ($header[$c] -ne ' ' -and ($c -eq 0 -or $header[$c - 1] -eq ' ')) { $c }
        })
        if ($starts.Count -lt 4) { continue }
        $before = ''
        for ($b = $i - 2; $b -ge 0; $b--) { if ($text[$b].Trim()) { $before = $text[$b]; break } }
        $kind = 'Normal'
        if ($tableNo -gt 0 -or $before -match '(?i)explicit|cannot be upgraded|publisher|explicite|diteur') { $kind = 'Special' }
        $tableNo++
        for ($j = $i + 1; $j -lt $text.Count; $j++) {
            if (-not $text[$j].Trim()) { break }
            $row = ConvertFrom-WingetRow $text[$j] $starts
            if (-not $row) { break }
            $row.Table = $kind
            $rows += $row
        }
    }
    return $rows
}

function Resolve-WingetIds([object[]]$Rows) {
    # winget shortens long Ids with "…" to fit its table. The full Ids come from "winget export".
    $ellipsis = [string][char]0x2026
    $cut = @($Rows | Where-Object { $_.Id.EndsWith($ellipsis) })
    if ($cut.Count -eq 0) { return }
    $ids = @()
    $file = [System.IO.Path]::Combine("$env:TEMP", ('yso-winget_{0}.json' -f [guid]::NewGuid().ToString('N').Substring(0, 6)))
    try {
        [void](Invoke-Winget (@('export', '--output', $file, '--source', 'winget', '--accept-source-agreements') + @(Get-WingetQuietArgs)))
        if (Test-Path -LiteralPath $file) {
            $j = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            $ids = @(@($j.Sources) | ForEach-Object { @($_.Packages) } | ForEach-Object { "$($_.PackageIdentifier)" } | Where-Object { $_ })
        }
    } catch { } finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    foreach ($r in $cut) {
        $prefix = $r.Id.Substring(0, $r.Id.Length - 1)
        $match = @($ids | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } | Sort-Object -Unique)
        if ($match.Count -eq 1) { $r.Id = $match[0] }
        else { $r.Note = N 'could not be identified (its name is cut off in winget)' }
    }
}

function Get-AppUpdates {
    # Ok, Reason (+ ReasonArg), Apps (normal updates), Others (apps winget does not update by itself), Raw
    $r = [pscustomobject]@{ Ok = $false; Reason = ''; ReasonArg = ''; Apps = @(); Others = @(); Raw = @(); ParseFailed = $false }
    if (-not (Get-WingetPath)) {
        $r.Reason = if ($script:Build -lt 17763) { N 'needs Windows 10 version 1809 or later' } else { N 'winget (App Installer) is not installed' }
        return $r
    }
    $res = Invoke-Winget (@('upgrade', '--source', 'winget', '--accept-source-agreements') + @(Get-WingetQuietArgs))
    $r.Raw = @($res.Lines)
    $rows = @(ConvertFrom-WingetTable $res.Lines)
    $hasTable = @($res.Lines | Where-Object { "$_" -match '(^|\r)\s*-{10,}\s*$' }).Count -gt 0
    if ($rows.Count -eq 0 -and $hasTable) {
        $r.Reason = N 'could not read the list printed by winget'
        $r.ParseFailed = $true
        return $r
    }
    $hex = Format-HexCode $res.Code
    if ($rows.Count -eq 0 -and $res.Code -ne 0 -and @('0x8A150014', '0x8A15002B') -notcontains $hex) {
        $r.Reason = N 'winget failed ({0})'
        $r.ReasonArg = $hex
        return $r
    }
    Resolve-WingetIds $rows
    $r.Apps = @($rows | Where-Object { $_.Table -eq 'Normal' -and -not $_.Note })
    $r.Others = @($rows | Where-Object { $_.Table -ne 'Normal' -or $_.Note })
    $r.Ok = $true
    return $r
}

function Get-UpdateMessage([string]$Hex) {
    # English text for a winget or Windows Update result code (translated when shown).
    switch ($Hex) {
        '0x8A150101' { return (N 'the app is open - close it and try again') }
        '0x8A150103' { return (N 'the app is open - close it and try again') }
        '0x8A150111' { return (N 'the app is open - close it and try again') }
        '0x8A150102' { return (N 'another installation is running - try again later') }
        '0x8A150104' { return (N 'a component it needs is missing') }
        '0x8A150110' { return (N 'a component it needs is missing') }
        '0x8A150105' { return (N 'the disk is full') }
        '0x8A150107' { return (N 'no internet connection') }
        '0x8A150109' { return (N 'restart the PC to finish') }
        '0x8A15010B' { return (N 'restart the PC to finish') }
        '0x8A15010A' { return (N 'restart the PC, then try again') }
        '0x8A15010C' { return (N 'cancelled') }
        '0x8A15010F' { return (N 'blocked by your organization') }
        '0x8A150114' { return (N 'its installer cannot update it - update it from the app itself') }
        '0x8A15002B' { return (N 'no update applies to this version') }
        '0x8A15008E' { return (N 'the new version uses another installer than the installed one') }
        '0x80070422' { return (N 'Windows Update is turned off on this PC (its service is disabled)') }
        '0x80070005' { return (N 'access denied') }
        '0x8024402C' { return (N 'no connection to Windows Update') }
        '0x80072EE7' { return (N 'no connection to Windows Update') }
        '0x80072EFD' { return (N 'no connection to Windows Update') }
        '0x80072EE2' { return (N 'no connection to Windows Update') }
        '0x8024401C' { return (N 'no connection to Windows Update') }
        '0x80240016' { return (N 'another installation is running - try again later') }
        default      { return '' }
    }
}

function Install-AppUpdate($Item) {
    # The Id comes from winget's own list; anything that does not look like one is never passed on.
    if ("$($Item.Id)" -notmatch '^[A-Za-z0-9][\w\.\-\+]{0,127}$') { return (New-UpdateResult $Item 'Failed' 'invalid Id') }
    $a = @('upgrade', '--id', $Item.Id, '--exact', '--source', 'winget', '--silent',
           '--accept-package-agreements', '--accept-source-agreements') + @(Get-WingetQuietArgs)
    $res = Invoke-Winget $a
    $hex = Format-HexCode $res.Code
    return (New-UpdateResult $Item (Get-AppUpdateStatus $hex) $hex)
}

function Get-AppUpdateStatus([string]$Hex) {
    switch ($Hex) {
        '0x00000000' { return 'Updated' }
        '0x8A150109' { return 'Restart' }
        '0x8A15010B' { return 'Restart' }
        '0x8A15002B' { return 'NotApplicable' }
        '0x8A150101' { return 'InUse' }
        '0x8A150103' { return 'InUse' }
        '0x8A150111' { return 'InUse' }
        default      { return 'Failed' }
    }
}

function Install-AppByReinstall($Item) {
    # When the new version uses another installer than the installed one (0x8A15008E), winget cannot
    # update it in place: the installed version is removed, then the new one is installed.
    if ("$($Item.Id)" -notmatch '^[A-Za-z0-9][\w\.\-\+]{0,127}$') { return (New-UpdateResult $Item 'Failed' 'invalid Id') }
    $q = @(Get-WingetQuietArgs)
    $un = Invoke-Winget (@('uninstall', '--id', $Item.Id, '--exact', '--silent', '--accept-source-agreements') + $q)
    if ($un.Code -ne 0) { return (New-UpdateResult $Item 'Failed' (Format-HexCode $un.Code) (L 'the installed version could not be removed')) }
    $in = Invoke-Winget (@('install', '--id', $Item.Id, '--exact', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements') + $q)
    $hex = Format-HexCode $in.Code
    $r = New-UpdateResult $Item (Get-AppUpdateStatus $hex) $hex
    if ($r.Status -eq 'Failed') { $r.Detail = (L 'removed, but the new version did not install: install it from its website') }
    return $r
}

function New-UpdateResult($Item, [string]$Status, [string]$Hex = '', [string]$Detail = '') {
    return [pscustomobject]@{
        Kind = $Item.Kind; Name = $Item.Name; Id = $Item.Id; From = $Item.From; To = $Item.To
        Status = $Status; Code = $Hex; Detail = $Detail
    }
}

function New-UpdateSession {
    # One Windows Update session for the search and the installation that follows it.
    if ($script:WuSession) { return $script:WuSession }
    $s = New-Object -ComObject 'Microsoft.Update.Session'
    $s.ClientApplicationID = 'YSO'
    $script:WuSession = $s
    return $s
}

function New-UpdateCollection {
    # The comma keeps the empty list as it is: without it, PowerShell unrolls it and returns nothing.
    return , (New-Object -ComObject 'Microsoft.Update.UpdateColl')
}

function Get-ComErrorHex($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    return (Format-HexCode $ex.HResult)
}

function Get-ErrorText($ErrorRecord) {
    # The innermost message: PowerShell wraps the error Windows gave in its own.
    $ex = $ErrorRecord.Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    $m = ("$($ex.Message)" -replace '\s+', ' ').Trim()
    return (Get-Truncated $m 160)
}

function Get-DriverUpdates {
    # Drivers Windows Update has for this PC. Optional = Microsoft says to install them only
    # when a device has a problem (Settings > Windows Update > Optional updates).
    $r = [pscustomobject]@{ Ok = $false; Reason = ''; ReasonArg = ''; Drivers = @(); Firmware = @() }
    $svc = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
    if ($svc -and "$($svc.StartType)" -eq 'Disabled') {
        $r.Reason = N 'Windows Update is turned off on this PC (its service is disabled)'
        return $r
    }
    try {
        $session = New-UpdateSession
        $searcher = $session.CreateUpdateSearcher()
        $found = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    } catch {
        $hex = Get-ComErrorHex $_
        $known = Get-UpdateMessage $hex
        if ($known) { $r.Reason = $known } else { $r.Reason = N 'Windows Update error {0}'; $r.ReasonArg = $hex }
        return $r
    }
    $list = @()
    $firmware = @()
    for ($i = 0; $i -lt $found.Updates.Count; $i++) {
        $u = $found.Updates.Item($i)
        # Firmware (BIOS, UEFI, the built-in software of a device) is never installed by YSO.
        if ("$($u.DriverClass)" -match '(?i)^firmware$' -or "$($u.Title)" -match '(?i)\b(firmware|bios|uefi)\b') {
            $firmware += [pscustomobject]@{ Name = "$($u.Title)"; Class = "$($u.DriverClass)" }
            continue
        }
        $date = ''
        try { if ($u.DriverVerDate) { $date = ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } } catch { }
        $list += [pscustomobject]@{
            Kind = 'Driver'; Name = "$($u.Title)"; Id = "$($u.Identity.UpdateID)"; From = ''; To = $date
            Class = "$($u.DriverClass)"; Optional = [bool]$u.BrowseOnly; Excluded = $false; InUse = $false
            Major = $false; Update = $u
        }
    }
    $r.Drivers = $list
    $r.Firmware = $firmware
    $r.Ok = $true
    return $r
}

function Install-DriverUpdates([object[]]$Drivers) {
    # One driver at a time: a driver that cannot be installed never stops the others, and each result
    # says why. Every failure is written to errors.log with Windows' own message.
    $results = @()
    $all = @($Drivers)
    if ($all.Count -eq 0) { return $results }
    try { $session = New-UpdateSession }
    catch {
        Write-YsoError -Context 'driver updates: Windows Update' -ErrorRecord $_
        foreach ($d in $all) { $results += (New-UpdateResult $d 'Failed' (Get-ComErrorHex $_) (Get-ErrorText $_)) }
        return $results
    }
    $n = 0
    foreach ($d in $all) {
        $n++
        Write-YsoProgress -Activity (L 'Driver updates') -Status ('{0}/{1}  {2}' -f $n, $all.Count, $d.Name) -Percent (100 * ($n - 1) / $all.Count) -Force
        $step = 'prepare'
        try {
            $u = $d.Update
            if ($null -eq $u) { throw 'Windows Update no longer offers this update. Look for updates again.' }
            $step = 'license'
            if (-not $u.EulaAccepted) {
                try { $u.AcceptEula() }
                catch {
                    # PowerShell may not see the method on some updates: the same call through IDispatch
                    if ($_.Exception.InnerException) { throw }
                    $base = $u.psobject.BaseObject
                    [void]$base.GetType().InvokeMember('AcceptEula', [System.Reflection.BindingFlags]::InvokeMethod, $null, $base, $null)
                }
            }
            $coll = New-UpdateCollection
            [void]$coll.Add($u)
            if (-not $u.IsDownloaded) {
                $step = 'download'
                $dl = $session.CreateUpdateDownloader()
                $dl.Updates = $coll
                $down = $dl.Download()
                $dc = [int]$down.ResultCode   # 2 = succeeded, 3 = succeeded with errors, 4 = failed, 5 = aborted
                if ($dc -ne 2 -and $dc -ne 3) {
                    $results += (New-UpdateResult $d 'Failed' (Format-HexCode ($down.GetUpdateResult(0).HResult)) (L 'the download failed'))
                    continue
                }
            }
            $step = 'install'
            $inst = $session.CreateUpdateInstaller()
            $inst.Updates = $coll
            try { $inst.ForceQuiet = $true } catch { }
            $res = $inst.Install()
            $one = $res.GetUpdateResult(0)
            $code = [int]$one.ResultCode
            if ($code -eq 2 -or $code -eq 3) {
                $results += (New-UpdateResult $d $(if ($one.RebootRequired -or $res.RebootRequired) { 'Restart' } else { 'Updated' }) (Format-HexCode ($one.HResult)))
            } else {
                $results += (New-UpdateResult $d 'Failed' (Format-HexCode ($one.HResult)) (L 'Windows Update could not install it'))
            }
        } catch {
            if (Test-StopError $_) { throw }
            Write-YsoError -Context ('driver update (' + $step + '): ' + $d.Name) -ErrorRecord $_
            $results += (New-UpdateResult $d 'Failed' (Get-ComErrorHex $_) ('{0}: {1}' -f $step, (Get-ErrorText $_)))
        }
    }
    Write-YsoProgress -Activity (L 'Driver updates') -Completed
    return $results
}

function Test-UpdateExcluded([string]$Id) {
    # Apps never updated automatically (Settings: 28 > 5). * works as a wildcard.
    foreach ($p in @($script:Settings.Updates.ExcludeApps)) {
        if ("$p".Trim() -and $Id -like "$p".Trim()) { return $true }
    }
    return $false
}

function Test-MajorUpgrade([string]$From, [string]$To) {
    # 7.0.45 -> 9.0.2 is a new major version: it can change how an app works or need extra steps
    # (databases, compilers...). When a version has no number at all, it counts as major too.
    $a = [regex]::Match("$From", '\d+')
    $b = [regex]::Match("$To", '\d+')
    if (-not $a.Success -or -not $b.Success) { return $true }
    return ([double]$b.Value -gt [double]$a.Value)
}

function Test-GenericFolder([string]$Dir) {
    # Folders shared by many programs: a program running from them says nothing about one app.
    if (-not $Dir) { return $true }
    $d = $Dir.TrimEnd('\', '/')
    if ($d.Length -le 3) { return $true }
    $generic = @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA, $env:USERPROFILE)
    if ($env:LOCALAPPDATA) { $generic += $env:LOCALAPPDATA.TrimEnd('\') + '\Programs' }
    if ($env:ProgramFiles) { $generic += @(($env:ProgramFiles.TrimEnd('\') + '\Common Files'), ($env:ProgramFiles.TrimEnd('\') + '\WindowsApps')) }
    foreach ($g in @($generic | Where-Object { $_ })) { if ($d -ieq "$g".TrimEnd('\', '/')) { return $true } }
    if ($env:WINDIR -and ($d + '\').StartsWith($env:WINDIR.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Get-UninstallEntries {
    $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
    return @(foreach ($k in $keys) { Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } })
}

function Get-RunningExePaths {
    try {
        return @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | ForEach-Object { "$($_.ExecutablePath)" } | Where-Object { $_ } | Sort-Object -Unique)
    } catch { return @() }
}

function Get-AppsInUse([object[]]$Items) {
    # Ids of the apps that have a program running right now, found through the folders Windows
    # lists for installed programs. An app YSO cannot place counts as not running.
    $running = @(Get-RunningExePaths)
    if ($running.Count -eq 0 -or @($Items).Count -eq 0) { return @() }
    $ellipsis = [string][char]0x2026
    $entries = @(Get-UninstallEntries)
    $inUse = @()
    foreach ($it in $Items) {
        $name = "$($it.Name)"
        $short = if ($name.EndsWith($ellipsis)) { $name.Substring(0, $name.Length - 1) } else { $null }
        $dirs = @()
        foreach ($e in $entries) {
            $dn = "$($e.DisplayName)".Trim()
            if (-not ($dn -ieq $name -or ($short -and $dn.StartsWith($short, [StringComparison]::OrdinalIgnoreCase)))) { continue }
            if ($e.InstallLocation) { $dirs += "$($e.InstallLocation)".Trim().Trim('"') }
            foreach ($v in @($e.DisplayIcon, $e.UninstallString)) {
                if (-not $v) { continue }
                $exe = Resolve-ExePath ("$v" -replace ',\s*-?\d+\s*$', '')
                if ($exe -and $exe.Contains('\')) { $dirs += $exe.Substring(0, $exe.LastIndexOf('\')) }
            }
        }
        foreach ($d in @($dirs | Where-Object { -not (Test-GenericFolder $_) })) {
            $prefix = $d.TrimEnd('\') + '\'
            if (@($running | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { $inUse += $it.Id; break }
        }
    }
    return @($inUse | Sort-Object -Unique)
}

function Find-Updates([string]$Mode) {
    # Looks for app and driver updates. Mode Manual looks for both; Auto and Full follow Settings.
    $u = $script:Settings.Updates
    $f = [pscustomobject]@{ Items = @(); Others = @(); Apps = $null; Drivers = $null }
    if ($Mode -eq 'Manual' -or $u.Apps) {
        Write-Step 'Looking for app updates (winget)...'
        $f.Apps = Get-AppUpdates
        if ($f.Apps.Ok) {
            $items = @(foreach ($a in $f.Apps.Apps) {
                [pscustomobject]@{
                    Kind = 'App'; Name = $a.Name; Id = $a.Id; From = $a.Version; To = $a.Available
                    Class = ''; Optional = $false; Excluded = (Test-UpdateExcluded $a.Id); InUse = $false; Update = $null
                    Major = (Test-MajorUpgrade $a.Version $a.Available)
                }
            })
            $open = @(Get-AppsInUse $items)
            foreach ($it in $items) { $it.InUse = ($open -contains $it.Id) }
            $f.Items += $items
            $f.Others = @($f.Apps.Others)
        } else {
            if ($f.Apps.ParseFailed) {
                # Not normal: record it so the self-test and "P" reports show it.
                try { throw ('winget output could not be read: ' + ((@($f.Apps.Raw) | Select-Object -First 12) -join ' | ')) }
                catch { Write-YsoError -Context 'updates: winget list' -ErrorRecord $_ }
            }
            Write-Warn ((L 'App updates') + ': ' + (L $f.Apps.Reason $f.Apps.ReasonArg))
        }
    }
    if ($Mode -eq 'Manual' -or $u.Drivers) {
        Write-Step 'Looking for driver updates (Windows Update - can take a few minutes)...'
        $f.Drivers = Get-DriverUpdates
        if ($f.Drivers.Ok) { $f.Items += @($f.Drivers.Drivers) }
        else { Write-Warn ((L 'Driver updates') + ': ' + (L $f.Drivers.Reason $f.Drivers.ReasonArg)) }
    }
    return $f
}

function Test-RecommendedUpdate($Item, [string]$Mode) {
    # What "install the recommended ones" and automatic updates take.
    if ($Item.Kind -eq 'App') {
        if ($Item.Excluded) { return $false }
        if ($Item.Major -and -not ($Mode -ne 'Manual' -and $script:Settings.Updates.MajorVersions)) { return $false }
        if ($Item.InUse -and $Mode -ne 'Manual') { return $false }
        return $true
    }
    if ($Item.Optional) { return ($Mode -ne 'Manual' -and [bool]$script:Settings.Updates.OptionalDrivers) }
    return $true
}

function Show-UpdateList([object[]]$Items, [object[]]$Others, [object[]]$Firmware = @()) {
    $apps = @($Items | Where-Object { $_.Kind -eq 'App' })
    $drivers = @($Items | Where-Object { $_.Kind -eq 'Driver' })
    $n = 0
    if ($apps.Count -gt 0) {
        Write-Section 'APP UPDATES (winget)'
        foreach ($a in $apps) {
            $n++
            $notes = @()
            if ($a.Excluded) { $notes += (L 'not automatic') }
            elseif ($a.Major) { $notes += (L 'new major version') }
            if ($a.InUse) { $notes += (L 'open now') }
            Write-Host ('  {0,3}  ' -f $n) -NoNewline -ForegroundColor Green
            Write-Host ((Get-Truncated $a.Name 34).PadRight(35)) -NoNewline
            Write-Host (('{0} -> {1}' -f (Get-Truncated $a.From 14), (Get-Truncated $a.To 14)).PadRight(32) + '  ') -NoNewline -ForegroundColor Gray
            Write-Host ($notes -join ', ') -ForegroundColor Yellow
        }
        if (@($apps | Where-Object { $_.Major -and -not $_.Excluded }).Count -gt 0) {
            Write-Info 'New major version: it can change how the app works - pick it yourself when you are ready.'
        }
    }
    if ($drivers.Count -gt 0) {
        Write-Section 'DRIVER UPDATES (Windows Update)'
        foreach ($d in $drivers) {
            $n++
            Write-Host ('  {0,3}  ' -f $n) -NoNewline -ForegroundColor Green
            Write-Host ((Get-Truncated $d.Name 66).PadRight(67)) -NoNewline
            if ($d.Optional) { Write-Host (L 'optional') -ForegroundColor Yellow } else { Write-Host (L 'recommended') -ForegroundColor Gray }
        }
        if (@($drivers | Where-Object { $_.Optional }).Count -gt 0) {
            Write-Info 'Optional drivers: Microsoft advises installing them only if that device has a problem.'
        }
    }
    if (@($Others).Count -gt 0) {
        Write-Section 'ALSO NEWER, BUT NOT UPDATED BY YSO'
        foreach ($o in $Others) {
            Write-Host ('       {0}' -f (Get-Truncated $o.Name 34).PadRight(35)) -NoNewline
            Write-Host ('{0} -> {1}' -f $o.Version, $o.Available) -ForegroundColor DarkGray
        }
        Write-Info 'These apps update themselves or need their own updater (winget does not update them automatically).'
    }
    if (@($Firmware).Count -gt 0) {
        Write-Section 'FIRMWARE (NOT INSTALLED BY YSO)'
        foreach ($fw in $Firmware) { Write-Host ('       ' + (Get-Truncated $fw.Name 70)) -ForegroundColor DarkGray }
        Write-Info 'Firmware updates change the BIOS or the built-in software of a device. YSO leaves them to Windows Update (Settings > Windows Update) or to your PC maker''s app.'
    }
}

function Read-UpdateSelection([int]$Count, [int[]]$Recommended) {
    # A = the recommended ones; T = all; "1,3" or "2-4" = only those; Enter = nothing. Returns 1-based numbers.
    if (@($Recommended).Count -gt 0) { Write-Option 'A' 'Install the recommended ones' }
    Write-Option 'T' 'Install all of them (new major versions too)'
    $ans = Read-Choice 'Or type numbers (e.g. 1,3 or 2-4), Enter = nothing'
    if (-not $ans) { return @() }
    if ($ans -eq 'A') { return @($Recommended) }
    if ($ans -eq 'T') { return @(1..$Count) }
    $picked = @()
    foreach ($tok in @($ans -split '[,;\s]+' | Where-Object { $_ })) {
        if ($tok -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $x = $a; $a = $b; $b = $x }
            for ($k = $a; $k -le $b; $k++) { if ($k -ge 1 -and $k -le $Count) { $picked += $k } }
        } elseif ($tok -match '^\d+$' -and [int]$tok -ge 1 -and [int]$tok -le $Count) { $picked += [int]$tok }
        else { Write-Warn (L 'Ignored: {0}' $tok) }
    }
    return @($picked | Sort-Object -Unique)
}

function Write-UpdateResult($Result) {
    $what = if ($Result.Kind -eq 'App') { '{0} {1}' -f $Result.Name, $Result.To } else { $Result.Name }
    $msg = Get-UpdateMessage $Result.Code
    switch ($Result.Status) {
        'Updated'       { Write-Ok $what }
        'Restart'       { Write-Ok ($what + ' - ' + (L 'restart the PC to finish')) }
        'NotApplicable' { Write-Info ($Result.Name + ': ' + (L 'no update applies to this version')) }
        'InUse'         { Write-Warn ($Result.Name + ': ' + (L 'the app is open - close it and try again')) }
        'Skipped'       { Write-Info ($Result.Name + ': ' + (L 'skipped - the app was open')) }
        default {
            $why = if ($msg) { L $msg } else { L 'error {0}' $Result.Code }
            if ($Result.Detail -and -not $msg) { $why += ' (' + $Result.Detail + ')' }
            Write-Bad ($Result.Name + ': ' + $why)
        }
    }
}

function Install-ChosenUpdates([object[]]$Chosen, [string]$Mode = 'Manual') {
    $results = @()
    $apps = @($Chosen | Where-Object { $_.Kind -eq 'App' })
    $i = 0
    foreach ($a in $apps) {
        $i++
        Write-YsoProgress -Activity (L 'Updates') -Status ('{0}/{1}  {2}' -f $i, $apps.Count, $a.Name) -Percent (100 * ($i - 1) / [math]::Max(1, $apps.Count)) -Force
        Write-Host ('  [{0}/{1}] ' -f $i, $apps.Count) -NoNewline -ForegroundColor DarkGray
        Write-Host (L 'Updating {0} ({1} -> {2})...' $a.Name $a.From $a.To)
        $r = Install-AppUpdate $a
        if ($r.Code -eq '0x8A15008E' -and $Mode -eq 'Manual' -and -not (Test-Unattended)) {
            Write-Warn (L '{0}: the new version uses another installer than the installed one, so it cannot be updated in place.' $a.Name)
            if (Confirm-Action (L 'Reinstall {0}? YSO removes the installed version, then installs {1}. Most apps keep your data, but some forget their settings.' $a.Name $a.To) $false) {
                $r = Install-AppByReinstall $a
            }
        }
        Write-UpdateResult $r
        $results += $r
    }
    Write-YsoProgress -Activity (L 'Updates') -Completed
    $drivers = @($Chosen | Where-Object { $_.Kind -eq 'Driver' })
    if ($drivers.Count -gt 0) {
        Write-YsoProgress -Activity (L 'Updates') -Status (L 'Downloading and installing {0} driver(s) with Windows Update...' $drivers.Count) -Force
        Write-Step (L 'Downloading and installing {0} driver(s) with Windows Update...' $drivers.Count)
        foreach ($r in @(Install-DriverUpdates $drivers)) { Write-UpdateResult $r; $results += $r }
    }
    return $results
}

function Show-DriverSources {
    # Drivers Windows Update does not have: graphics drivers come from the GPU maker, BIOS and
    # some laptop drivers from the PC maker. YSO only points to them.
    try {
        foreach ($g in @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)) {
            $name = "$($g.Name)"
            $tool = $null
            if ($name -match 'NVIDIA') { $tool = 'NVIDIA App' }
            elseif ($name -match 'AMD|Radeon') { $tool = 'AMD Software: Adrenalin Edition' }
            elseif ($name -match 'Intel') { $tool = 'Intel Driver & Support Assistant' }
            if (-not $tool) { continue }
            $date = $null
            try { if ($g.DriverDate) { $date = [datetime]$g.DriverDate } } catch { }
            $dateText = if ($date) { $date.ToString('yyyy-MM-dd') } else { '?' }
            Write-Kv (Get-Truncated $name 29) (L 'driver {0} ({1})' $g.DriverVersion $dateText)
            if ($date -and ((Get-Date) - $date).TotalDays -gt 180) {
                Write-Info (L 'Newer graphics drivers come from {0} - Windows Update often has older ones.' $tool)
            }
        }
    } catch { }
    $maker = Get-PcMakerTool
    if ($maker) { Write-Info (L 'BIOS and some drivers for this PC come from {0}: use {1}. YSO never updates the BIOS.' $maker[0] $maker[1]) }
}

function Get-PcMakerTool {
    try { $m = "$((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Manufacturer)" } catch { return $null }
    if ($m -match 'Micro-Star|^MSI') { return @('MSI', 'MSI Center') }
    if ($m -match '^Dell') { return @('Dell', 'Dell Command | Update') }
    if ($m -match '^HP$|^HP |Hewlett') { return @('HP', 'HP Support Assistant') }
    if ($m -match '^LENOVO') { return @('Lenovo', 'Lenovo Vantage') }
    if ($m -match 'ASUSTeK|^ASUS') { return @('ASUS', 'MyASUS') }
    if ($m -match '^Acer') { return @('Acer', 'Acer Care Center') }
    return $null
}

function Enter-UpdateLock {
    # One update run at a time (the automatic one may be running when you start one).
    try {
        $script:UpdateMutex = New-Object System.Threading.Mutex($false, 'Global\YsoUpdates')
        if ($script:UpdateMutex.WaitOne(0)) { return $true }
        $script:UpdateMutex.Dispose(); $script:UpdateMutex = $null
        return $false
    } catch { return $true }   # an abandoned lock is ours now; any other problem: go on
}

function Exit-UpdateLock {
    try { if ($script:UpdateMutex) { $script:UpdateMutex.ReleaseMutex() } } catch { }
    try { if ($script:UpdateMutex) { $script:UpdateMutex.Dispose() } } catch { }
    $script:UpdateMutex = $null
}

function Save-UpdateHistory([string]$Mode, [int]$Found, [object[]]$Results) {
    $run = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $ok = @($Results | Where-Object { $_.Status -eq 'Updated' -or $_.Status -eq 'Restart' }).Count
    $bad = @($Results | Where-Object { $_.Status -eq 'Failed' -or $_.Status -eq 'InUse' }).Count
    $rows = @([pscustomobject]@{ Run = $run; Mode = $Mode; Kind = 'Run'; Name = ''; Id = ''; From = ''; To = ''; Status = ''; Code = ''; Found = $Found; Installed = $ok; NotInstalled = $bad })
    foreach ($r in @($Results)) {
        $rows += [pscustomobject]@{ Run = $run; Mode = $Mode; Kind = $r.Kind; Name = $r.Name; Id = $r.Id; From = $r.From; To = $r.To; Status = $r.Status; Code = $r.Code; Found = ''; Installed = ''; NotInstalled = '' }
    }
    try {
        New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
        $rows | Export-Csv -LiteralPath $script:UpdateHistoryPath -Append -NoTypeInformation -Encoding UTF8
    } catch { }
}

function Get-UpdateHistoryRows {
    if (-not (Test-Path -LiteralPath $script:UpdateHistoryPath)) { return @() }
    return @(Import-Csv -LiteralPath $script:UpdateHistoryPath -ErrorAction SilentlyContinue | Where-Object { $_.Run })
}

function Get-UpdateRunText($RunRow) {
    $when = "$($RunRow.Run)"
    if ($when.Length -ge 16) { $when = $when.Substring(0, 16) }
    $mode = switch ("$($RunRow.Mode)") { 'Auto' { L 'Auto' } 'Notify' { L 'Notify' } 'Full' { L 'Full maintenance' } default { L 'Manual' } }
    return (L '{0} ({1}): {2} found, {3} installed, {4} not installed' $when $mode $RunRow.Found $RunRow.Installed $RunRow.NotInstalled)
}

function Show-UpdateHistory {
    Write-Section 'UPDATE HISTORY'
    $rows = @(Get-UpdateHistoryRows)
    if ($rows.Count -eq 0) { Write-Info 'Nothing yet: runs of option 28 and automatic updates show up here.'; return }
    $statusText = @{
        Updated = (N 'installed'); Restart = (N 'installed - restart the PC to finish'); Failed = (N 'not installed')
        InUse = (N 'not installed: the app was open'); Skipped = (N 'skipped - the app was open'); NotApplicable = (N 'no update applies to this version')
    }
    foreach ($g in @($rows | Group-Object Run | Sort-Object Name -Descending | Select-Object -First 10)) {
        $head = @($g.Group | Where-Object { $_.Kind -eq 'Run' }) | Select-Object -First 1
        Write-Host ''
        if ($head) { Write-Host ('  ' + (Get-UpdateRunText $head)) -ForegroundColor Cyan }
        foreach ($r in @($g.Group | Where-Object { $_.Kind -ne 'Run' })) {
            $s = if ($statusText.ContainsKey($r.Status)) { L $statusText[$r.Status] } else { $r.Status }
            if ($r.Status -eq 'Failed') { $why = Get-UpdateMessage $r.Code; $s += ': ' + $(if ($why) { L $why } else { $r.Code }) }
            $color = switch ($r.Status) { 'Updated' { 'Green' } 'Restart' { 'Green' } 'Failed' { 'Red' } default { 'Yellow' } }
            $ver = if ($r.Kind -eq 'App') { ' {0} -> {1}' -f $r.From, $r.To } else { '' }
            Write-Host ('     ' + (Get-Truncated ($r.Name + $ver) 62).PadRight(63)) -NoNewline
            Write-Host $s -ForegroundColor $color
        }
    }
}

function Write-UpdateReport([string]$Mode, $Found, [object[]]$Chosen, [object[]]$Results) {
    # Plain English report (like the self-test's): what was found, what was chosen and what happened.
    try {
        New-Item -ItemType Directory -Path $script:ReportDir -Force | Out-Null
        $path = Join-Path $script:ReportDir ('updates_{0:yyyyMMdd_HHmmss}.txt' -f (Get-Date))
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('YSO update report')
        $lines.Add(('YSO        : {0}' -f $script:Version))
        $lines.Add(('Date       : {0:yyyy-MM-dd HH:mm}' -f (Get-Date)))
        $lines.Add(('Windows    : {0}' -f $script:OsText))
        $lines.Add(('Mode       : {0}{1}' -f $Mode, $(if ($script:DryRun) { ' (check only, nothing installed)' } else { '' })))
        $wv = Get-WingetVersion
        $lines.Add(('winget     : {0}' -f $(if ($wv) { "$wv" } elseif (Get-WingetPath) { 'version unknown' } else { 'not installed' })))
        if ($Found.Apps) {
            if ($Found.Apps.Ok) { $lines.Add(('Apps       : {0} update(s), {1} not updated by winget itself' -f @($Found.Apps.Apps).Count, @($Found.Apps.Others).Count)) }
            else { $lines.Add(('Apps       : ' + ($Found.Apps.Reason -f $Found.Apps.ReasonArg))) }
        }
        if ($Found.Drivers) {
            if ($Found.Drivers.Ok) { $lines.Add(('Drivers    : {0} update(s), {1} optional' -f @($Found.Drivers.Drivers).Count, @($Found.Drivers.Drivers | Where-Object { $_.Optional }).Count)) }
            else { $lines.Add(('Drivers    : ' + ($Found.Drivers.Reason -f $Found.Drivers.ReasonArg))) }
        }
        $lines.Add('')
        $lines.Add('FOUND')
        foreach ($it in @($Found.Items)) {
            $flags = @()
            if ($it.Excluded) { $flags += 'excluded' }
            if ($it.InUse) { $flags += 'open' }
            if ($it.Optional) { $flags += 'optional' }
            if ($it.Major) { $flags += 'major' }
            if (@($Chosen) -contains $it) { $flags += 'chosen' }
            if ($it.Kind -eq 'App') { $lines.Add(('  App     {0} | {1} | {2} -> {3}  {4}' -f $it.Name, $it.Id, $it.From, $it.To, ($flags -join ' '))) }
            else { $lines.Add(('  Driver  {0} | {1} | {2}  {3}' -f $it.Name, $it.Class, $it.To, ($flags -join ' '))) }
        }
        foreach ($o in @($Found.Others)) { $lines.Add(('  Other   {0} | {1} | {2} -> {3}  {4}' -f $o.Name, $o.Id, $o.Version, $o.Available, $o.Note)) }
        if (@($Found.Items).Count -eq 0 -and @($Found.Others).Count -eq 0) { $lines.Add('  (nothing)') }
        if (@($Results).Count -gt 0) {
            $lines.Add('')
            $lines.Add('RESULTS')
            foreach ($r in $Results) { $lines.Add(('  {0,-13} {1,-7} {2} {3}' -f $r.Status, $r.Kind, $r.Name, $r.Code)) }
        }
        if ($script:DryRun -and $Found.Apps -and @($Found.Apps.Raw).Count -gt 0) {
            $lines.Add('')
            $lines.Add('WINGET OUTPUT (first 40 lines, for checking how it was read)')
            foreach ($l in @($Found.Apps.Raw | Select-Object -First 40)) {
                $parts = @("$l" -split "`r" | Where-Object { $_.Trim() })
                if ($parts.Count -gt 0) { $lines.Add('  ' + $parts[$parts.Count - 1].TrimEnd()) }
            }
        }
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Get-ChildItem -LiteralPath $script:ReportDir -Filter 'updates_*.txt' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force -ErrorAction SilentlyContinue
        return $path
    } catch {
        Write-YsoError -Context 'updates: report' -ErrorRecord $_
        return $null
    }
}

function Show-Toast([string]$Title, [string]$Text) {
    # A Windows notification after automatic updates. Silently does nothing where it cannot work.
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml(('<toast><visual><binding template="ToastGeneric"><text>{0}</text><text>{1}</text></binding></visual></toast>' -f
            [Security.SecurityElement]::Escape($Title), [Security.SecurityElement]::Escape($Text)))
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show((New-Object Windows.UI.Notifications.ToastNotification $xml))
        return $true
    } catch { return $false }
}

function Invoke-UpdateRun {
    # Mode Manual = option 28 (you choose), Auto = scheduled task, Full = a step of F.
    # Auto and Full install the recommended updates only: never apps you excluded, never apps that
    # are open (their installer could close them), optional drivers only if enabled in Settings.
    param([string]$Mode = 'Manual')
    $summary = [pscustomobject]@{ Found = 0; Installed = 0; NotInstalled = 0; Restart = $false; Busy = $false }
    if (-not (Enter-UpdateLock)) {
        Write-Warn 'YSO is already installing updates (automatic updates may be running). Try again in a few minutes.'
        $summary.Busy = $true
        return $summary
    }
    try {
        $found = Find-Updates $Mode
        $items = @($found.Items)
        $firmware = @(if ($found.Drivers) { $found.Drivers.Firmware })
        $summary.Found = $items.Count
        if ($items.Count -eq 0 -and @($found.Others).Count -eq 0 -and $firmware.Count -eq 0) {
            Write-Host ''
            Write-Ok 'Everything is up to date.'
        } else {
            Show-UpdateList $items $found.Others $firmware
        }
        if ($Mode -eq 'Manual') {
            Write-Host ''
            Show-DriverSources
        }
        $recommended = @(for ($k = 0; $k -lt $items.Count; $k++) { if (Test-RecommendedUpdate $items[$k] $Mode) { $k + 1 } })
        $chosen = @()
        if ($items.Count -gt 0) {
            if ($Mode -eq 'Manual' -and -not $script:DryRun) {
                Write-Host ''
                if ($recommended.Count -gt 0) { Write-Info (L 'Recommended: {0}' ($recommended -join ', ')) }
                $chosen = @(Read-UpdateSelection $items.Count $recommended | ForEach-Object { $items[$_ - 1] })
            } else {
                $chosen = @($recommended | ForEach-Object { $items[$_ - 1] })
            }
        }
        if ($Mode -eq 'Auto' -and $script:Settings.Updates.Mode -eq 'notify') {
            # Notify only: tell, install nothing.
            Write-Host ''
            Write-Info (L 'Notify only: nothing was installed ({0} update(s) available).' $items.Count)
            if ($items.Count -gt 0 -and -not $script:DryRun) { [void](Send-UpdateNotice $items) }
            if (-not $script:DryRun) { Save-UpdateHistory 'Notify' $items.Count @() }
            [void](Write-UpdateReport 'Notify' $found @() @())
            return $summary
        }
        $skippedOpen = @()
        if ($Mode -ne 'Manual') {
            $skippedOpen = @($items | Where-Object { $_.Kind -eq 'App' -and $_.InUse -and -not $_.Excluded } | ForEach-Object { New-UpdateResult $_ 'Skipped' })
        }
        if ($script:DryRun) {
            Write-Host ''
            Write-Info (L 'Check only: nothing was installed ({0} update(s) would be).' $chosen.Count)
            [void](Write-UpdateReport $Mode $found $chosen @())
            return $summary
        }
        $results = @()
        if ($chosen.Count -gt 0) {
            Write-Host ''
            if ($Mode -eq 'Manual') {
                $open = @($chosen | Where-Object { $_.InUse } | ForEach-Object { $_.Name })
                if ($open.Count -gt 0) {
                    Write-Warn (L 'Open now: {0}. Their installers may close them - save your work first.' ($open -join ', '))
                    if (-not (Confirm-Action 'Continue?' $true)) { return $summary }
                }
            }
            if (@($chosen | Where-Object { $_.Kind -eq 'Driver' }).Count -gt 0 -and $Mode -ne 'Full') {
                if ($Mode -eq 'Auto') { [void](New-YsoRestorePoint -Quiet) }
                elseif (Confirm-Action 'Create a restore point before installing drivers? (recommended)' $true) { [void](New-YsoRestorePoint) }
            }
            Write-Info 'Installing - this can take a while. Your PC will not be restarted.'
            $results = @(Install-ChosenUpdates $chosen $Mode)
        }
        $all = @($results) + @($skippedOpen)
        $summary.Installed = @($results | Where-Object { $_.Status -eq 'Updated' -or $_.Status -eq 'Restart' }).Count
        $summary.NotInstalled = @($results | Where-Object { $_.Status -eq 'Failed' -or $_.Status -eq 'InUse' }).Count
        $summary.Restart = (@($results | Where-Object { $_.Status -eq 'Restart' }).Count -gt 0)
        if ($chosen.Count -gt 0) {
            Write-Host ''
            Write-Kv 'Updates' (L '{0} installed, {1} not installed' $summary.Installed $summary.NotInstalled) $(if ($summary.NotInstalled -gt 0) { 'Yellow' } else { 'Green' })
            if ($summary.Restart) { Write-Warn 'Restart the PC to finish some updates (YSO never restarts it by itself).' }
        }
        foreach ($s in $skippedOpen) { Write-UpdateResult $s }
        if ($Mode -ne 'Manual' -or $chosen.Count -gt 0) { Save-UpdateHistory $Mode $items.Count $all }
        [void](Write-UpdateReport $Mode $found $chosen $all)
        if ($Mode -eq 'Auto' -and $script:Settings.Updates.Notify -and @($all).Count -gt 0) {
            $text = L '{0} update(s) installed.' $summary.Installed
            if ($summary.NotInstalled -gt 0) { $text += ' ' + (L '{0} could not be installed - see Updates (28).' $summary.NotInstalled) }
            if ($skippedOpen.Count -gt 0) { $text += ' ' + (L '{0} skipped because the app was open.' $skippedOpen.Count) }
            if ($summary.Restart) { $text += ' ' + (L 'Restart to finish.') }
            [void](Show-Toast 'YSO' $text)
        }
    } finally {
        Exit-UpdateLock
    }
    return $summary
}

function Install-YsoCopy([string]$Source = $PSCommandPath) {
    # Scheduled tasks run a copy of YSO in Program Files, which normal users cannot edit.
    # (Pointing an elevated task at a file in Downloads would let any program hijack it.)
    if (-not $Source) { return $null }
    $dir = Join-Path $env:ProgramFiles 'YSO'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $target = Join-Path $dir 'YSO.ps1'
    if ($Source -ne $target) { Copy-Item -LiteralPath $Source -Destination $target -Force }
    return $target
}

function Remove-YsoCopyIfUnused {
    if (Test-YsoInstalled) { return }   # installed YSO lives there: only Uninstall removes it
    foreach ($t in @($script:TaskName, $script:UpdateTaskName)) {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { return }
    }
    Remove-Item -LiteralPath (Join-Path $env:ProgramFiles 'YSO') -Recurse -Force -ErrorAction SilentlyContinue
}

function Update-YsoCopy([string]$Source = $PSCommandPath) {
    # Scheduled tasks always use the newest YSO you started: when this file differs from the
    # copy they run (Program Files), the copy is replaced - unless the copy is a newer version.
    try {
        $copy = Join-Path $env:ProgramFiles 'YSO\YSO.ps1'
        if (-not $Source -or -not (Test-Path -LiteralPath $copy) -or $Source -ieq $copy) { return }
        if ((Get-FileHash -LiteralPath $copy).Hash -eq (Get-FileHash -LiteralPath $Source).Hash) { return }
        # Never goes back to an older YSO. A copy without the update button comes from a test build
        # made before 1.0: it is replaced.
        $text = Get-Content -LiteralPath $copy -Raw
        $m = [regex]::Match($text, "\`$script:Version\s*=\s*'([\d\.]+)'")
        if ($text -match '\$script:ReleaseRepo\s*=' -and $m.Success -and [version]$m.Groups[1].Value -gt [version]$script:Version) { return }
        Copy-Item -LiteralPath $Source -Destination $copy -Force
    } catch { Write-YsoError -Context 'update the copy used by scheduled tasks' -ErrorRecord $_ }
}

function Get-DayName([string]$Day) {
    try {
        $culture = if ($script:Lang -eq 'fr') { New-Object System.Globalization.CultureInfo('fr-FR') } else { [System.Globalization.CultureInfo]::InvariantCulture }
        return $culture.DateTimeFormat.GetDayName([System.DayOfWeek]$Day)
    } catch { return $Day }
}

function Get-UpdateScheduleText {
    $u = $script:Settings.Updates
    if ($u.Frequency -eq 'daily') { return (L 'every day at {0}' $u.Time) }
    return (L 'every {0} at {1}' (Get-DayName $u.Day) $u.Time)
}

function Get-UpdateScopeText {
    $u = $script:Settings.Updates
    $parts = @()
    if ($u.Apps) { $parts += (L 'apps') }
    if ($u.Apps -and $u.MajorVersions) { $parts += (L 'new major versions') }
    if ($u.Drivers) { $parts += $(if ($u.OptionalDrivers) { L 'all drivers' } else { L 'recommended drivers' }) }
    if ($parts.Count -eq 0) { return (L '(nothing)') }
    return ($parts -join ', ')
}

function Get-CurrentUserName { return [Security.Principal.WindowsIdentity]::GetCurrent().Name }

function Register-UpdateTask {
    # Runs as you (so winget sees the apps installed for your account), with administrator rights
    # (installers and drivers need them), only while you are logged on, never on battery at start.
    $target = Install-YsoCopy
    if (-not $target) { Write-Warn 'Start YSO from its file to use this option.'; return $false }
    $u = $script:Settings.Updates
    $at = [datetime]::ParseExact($u.Time, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    $trigger = if ($u.Frequency -eq 'daily') { New-ScheduledTaskTrigger -Daily -At $at } else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek $u.Day -At $at }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`" -AutoUpdate"
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 3)
    $principal = New-ScheduledTaskPrincipal -UserId (Get-CurrentUserName) -LogonType Interactive -RunLevel Highest
    try {
        Register-ScheduledTask -TaskName $script:UpdateTaskName -Action $action -Trigger $trigger -Settings $settings `
            -Principal $principal -Description 'YSO - Your System Optimizer - automatic app and driver updates' -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Warn (L 'Could not create the scheduled task: {0}' $_.Exception.Message)
        return $false
    }
}

function Get-UpdateMode {
    # manual = only when you start it; notify = checks on schedule and tells you; auto = installs on schedule
    if (-not (Get-ScheduledTask -TaskName $script:UpdateTaskName -ErrorAction SilentlyContinue)) { return 'manual' }
    if ($script:Settings.Updates.Mode -eq 'notify') { return 'notify' }
    return 'auto'
}

function Get-UpdateModeText([string]$Mode) {
    switch ($Mode) {
        'auto'   { return (L 'AUTOMATIC') }
        'notify' { return (L 'NOTIFY ONLY') }
        default  { return (L 'MANUAL') }
    }
}

function Set-UpdateMode([string]$Mode) {
    if ($Mode -eq 'manual') {
        try { Unregister-ScheduledTask -TaskName $script:UpdateTaskName -Confirm:$false -ErrorAction Stop } catch { }
        Remove-YsoCopyIfUnused
        $script:Settings.Updates.Mode = 'manual'
        [void](Save-Settings)
        Write-Ok 'Manual: updates are checked and installed only when you start them (28 > 1).'
        return
    }
    Write-Info (L 'Runs {0} (or at the next startup if the PC was off), while you are logged on, only when plugged in.' (Get-UpdateScheduleText))
    if ($Mode -eq 'notify') {
        Write-Info 'It only checks: a notification tells you when updates are available. Nothing is installed until you choose (28 > 1).'
    } else {
        Write-Info (L 'It updates: {0}. Never: apps you excluded, apps that are open at that moment.' (Get-UpdateScopeText))
        if (-not $script:Settings.Updates.MajorVersions) { Write-Info 'New major versions (like 7.x -> 8.x) are left for you to install in 28 > 1.' }
        Write-Info 'It never restarts the PC: when an update needs a restart, a notification tells you.'
    }
    if (-not (Confirm-Action (L 'Switch to {0}?' (Get-UpdateModeText $Mode)) $true)) { return }
    $script:Settings.Updates.Mode = $Mode
    [void](Save-Settings)
    if (Register-UpdateTask) { Write-Ok (L 'Updates: {0}. Results: Updates (28) > 6.' (Get-UpdateModeText $Mode)) }
}

function Get-UpdateSignature([object[]]$Items) {
    return ((@($Items | ForEach-Object { '{0}|{1}|{2}' -f $_.Kind, $_.Id, $_.To }) | Sort-Object) -join ';')
}

function Send-UpdateNotice([object[]]$Items) {
    # "Notify only" mode: one notification per new set of updates (again after 7 days if still there).
    $file = Join-Path $script:DataDir 'last-update-notice.txt'
    $sig = Get-UpdateSignature $Items
    try {
        if (Test-Path -LiteralPath $file) {
            $prev = @(Get-Content -LiteralPath $file -Encoding UTF8)
            if ($prev.Count -ge 2 -and $prev[1] -eq $sig -and ((Get-Date) - [datetime]::ParseExact($prev[0], 'yyyy-MM-dd HH:mm', $null)).TotalDays -lt 7) { return $false }
        }
    } catch { }
    $apps = @($Items | Where-Object { $_.Kind -eq 'App' }).Count
    $text = L '{0} update(s) available ({1} app(s), {2} driver(s)). Open YSO > Updates (28) to install them.' @($Items).Count $apps (@($Items).Count - $apps)
    [void](Show-Toast 'YSO' $text)
    try { Set-Content -LiteralPath $file -Value @((Get-Date -Format 'yyyy-MM-dd HH:mm'), $sig) -Encoding UTF8 } catch { }
    return $true
}

function Show-UpdatesMenu {
    while ($true) {
        Clear-Host
        Write-Section 'UPDATES - apps and drivers'
        $mode = Get-UpdateMode
        $task = ($mode -ne 'manual')
        $u = $script:Settings.Updates
        if ($task) {
            Write-Kv 'Mode' ((Get-UpdateModeText $mode) + ' - ' + (Get-UpdateScheduleText)) 'Green'
            try {
                $next = (Get-ScheduledTaskInfo -TaskName $script:UpdateTaskName -ErrorAction Stop).NextRunTime
                if ($next -and $next.Year -gt 2000) { Write-Kv 'Next run' $next.ToString('g') }
            } catch { }
        } else {
            Write-Kv 'Mode' (L 'MANUAL - only when you start it (1)')
        }
        Write-Kv 'Automatic updates install' (Get-UpdateScopeText)
        $ex = @($u.ExcludeApps)
        Write-Kv 'Never updated automatically' $(if ($ex.Count) { Get-Truncated ($ex -join ', ') 60 } else { L '(none)' })
        $last = @(Get-UpdateHistoryRows | Where-Object { $_.Kind -eq 'Run' }) | Select-Object -Last 1
        if ($last) { Write-Kv 'Last run' (Get-UpdateRunText $last) }
        Write-Host ''
        Write-Option '1' 'Check for updates now (you choose what to install)'
        Write-Option '2' 'Mode: manual, notify me, or automatic'
        Write-Option '3' 'Schedule (every day or every week, day, time)'
        Write-Option '4' 'What automatic updates install'
        Write-Option '5' 'Apps never updated automatically'
        Write-Option '6' 'Update history'
        Write-Option '0' 'Back'
        switch (Read-Choice) {
            '1' { Invoke-UpdateRun -Mode 'Manual' | Out-Null; Wait-Key }
            '2' {
                Write-Host ''
                Write-Option '1' 'Manual - only when I start it'
                Write-Option '2' 'Notify me - check on schedule, tell me, install nothing'
                Write-Option '3' 'Automatic - install on schedule (safe updates only)'
                $pick = Read-Choice
                $map = @{ '1' = 'manual'; '2' = 'notify'; '3' = 'auto' }
                if ($map.ContainsKey($pick)) { Write-Host ''; Set-UpdateMode $map[$pick]; Wait-Key }
            }
            '3' {
                Write-Host ''
                Write-Option 'D' 'Every day'
                Write-Option 'W' 'Every week'
                $f = Read-Choice
                if ($f -eq 'D') { $u.Frequency = 'daily' }
                elseif ($f -eq 'W') {
                    $u.Frequency = 'weekly'
                    $days = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')
                    for ($i = 0; $i -lt 7; $i++) { Write-Option "$($i + 1)" (Get-DayName $days[$i]) }
                    $d = Read-Choice
                    if ($d -match '^[1-7]$') { $u.Day = $days[[int]$d - 1] }
                }
                $t = "$(Read-Host ('  ' + (L 'Time (24 h, like 12:00) [{0}]' $u.Time)))".Trim()
                if ($t -match '^(\d{1,2})[:hH.](\d{2})$' -and [int]$Matches[1] -le 23 -and [int]$Matches[2] -le 59) { $u.Time = '{0:00}:{1}' -f [int]$Matches[1], $Matches[2] }
                elseif ($t) { Write-Warn (L 'Not a valid time: {0}' $t) }
                if (Save-Settings) {
                    Write-Ok (L 'Schedule: {0}' (Get-UpdateScheduleText))
                    if ($task -and (Register-UpdateTask)) { Write-Ok 'Automatic updates now follow this schedule.' }
                }
                Start-Sleep -Seconds 2
            }
            '4' {
                $keys = [ordered]@{
                    Apps = (N 'Apps (winget)'); MajorVersions = (N 'Also new major versions of apps (can change how they work)')
                    Drivers = (N 'Drivers from Windows Update'); OptionalDrivers = (N 'Also optional drivers (not recommended)')
                    Notify = (N 'Notification after each automatic run')
                }
                $names = @($keys.Keys)
                while ($true) {
                    Write-Host ''
                    for ($i = 0; $i -lt $names.Count; $i++) {
                        $mark = if ($u[$names[$i]]) { '[x]' } else { '[ ]' }
                        Write-Option "$($i + 1)" ('{0} {1}' -f $mark, (L $keys[$names[$i]]))
                    }
                    $c = Read-Choice 'Number to switch on/off, Enter when done'
                    if (-not $c) { break }
                    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $names.Count) { $k = $names[[int]$c - 1]; $u[$k] = -not $u[$k] }
                }
                [void](Save-Settings)
            }
            '5' {
                while ($true) {
                    Write-Host ''
                    $ex = @($u.ExcludeApps)
                    if ($ex.Count -eq 0) { Write-Info '(none)' }
                    for ($i = 0; $i -lt $ex.Count; $i++) { Write-Option "$($i + 1)" $ex[$i] }
                    Write-Info 'Excluded apps still show up in 28 > 1, where you can update them yourself.'
                    $c = "$(Read-Host ('  ' + (L 'App Id to add (like Git.Git, * = any text), number to remove, R = defaults, Enter = done')))".Trim()
                    if (-not $c) { break }
                    if ($c -ieq 'R') { $u.ExcludeApps = [string[]]@((Get-DefaultSettings).Updates.ExcludeApps) }
                    elseif ($c -match '^\d+$') {
                        if ([int]$c -ge 1 -and [int]$c -le $ex.Count) { $drop = $ex[[int]$c - 1]; $u.ExcludeApps = [string[]]@($ex | Where-Object { $_ -ne $drop }) }
                    }
                    elseif (Test-AppIdPattern $c) { $u.ExcludeApps = [string[]]@(@($ex) + $c | Sort-Object -Unique) }
                    else { Write-Warn 'That does not look like a valid Id.' }
                    [void](Save-Settings)
                }
            }
            '6' { Show-UpdateHistory; Wait-Key }
            '0' { return }
        }
    }
}

# ==================================================================
#  ONE-CLICK
# ==================================================================
function New-YsoRestorePoint {
    param([switch]$Quiet)   # -Quiet: never offers to turn System Restore on (automatic runs)
    Write-Step 'Creating a System Restore point (your undo button)...'
    if ($script:DryRun) { return $true }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            $warn = $null
            Checkpoint-Computer -Description 'YSO' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable warn
            if ($warn) { Write-Info 'Windows allows one restore point per 24h - a recent one already exists, so you are covered.' }
            else { Write-Ok 'Restore point created.' }
            return $true
        } catch {
            $message = $_.Exception.Message
            if ($attempt -eq 1 -and -not $Quiet -and (Confirm-Action 'System Restore looks turned off. Turn it on for the system drive?' $true)) {
                try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop; continue } catch { $message = $_.Exception.Message }
            }
            Write-Warn (L 'No restore point created: {0}' $message)
            return $false
        }
    }
    return $false
}

function Get-RestorePointInfo {
    $r = [pscustomobject]@{ Available = $true; Points = @(); Used = [long]0; Max = [long]0 }
    if ($script:IsServer -or -not (Get-Command -Name 'Get-ComputerRestorePoint' -ErrorAction SilentlyContinue)) { $r.Available = $false; return $r }
    try { $r.Points = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object { [int]$_.SequenceNumber }) } catch { }
    try {
        foreach ($v in @(Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction Stop)) { $r.Used += [long]$v.UsedSpace; $r.Max += [long]$v.MaxSpace }
    } catch { }
    return $r
}

function Get-RestorePointDate($Point) {
    # CreationTime is a WMI date ("20261024015000.000000+060"), already in local time
    $m = [regex]::Match("$($Point.CreationTime)", '^(\d{14})')
    if ($m.Success) { return [datetime]::ParseExact($m.Groups[1].Value, 'yyyyMMddHHmmss', [System.Globalization.CultureInfo]::InvariantCulture) }
    try { return [datetime]$Point.CreationTime } catch { return $null }
}

function Remove-RestorePoint([int]$Sequence) {
    # The same Windows function Disk Cleanup uses ("all but the most recent restore point").
    if (-not ('YSO.SystemRestore' -as [type])) {
        Add-Type -Namespace 'YSO' -Name 'SystemRestore' -MemberDefinition '[DllImport("srclient.dll")] public static extern int SRRemoveRestorePoint(int index);'
    }
    return ([YSO.SystemRestore]::SRRemoveRestorePoint($Sequence) -eq 0)
}

function Remove-OldRestorePoints {
    # Keeps the newest restore point, removes the others. Returns the number removed.
    $info = Get-RestorePointInfo
    $old = @($info.Points | Select-Object -SkipLast 1)
    if ($old.Count -eq 0) { return 0 }
    $before = Get-FreeBytes
    $done = 0
    foreach ($p in $old) { try { if (Remove-RestorePoint ([int]$p.SequenceNumber)) { $done++ } } catch { } }
    $gain = [math]::Max([long]0, [long]((Get-FreeBytes) - $before))
    Add-Result -Category 'Old restore points' -Files -1 -Bytes $gain -Skipped ($old.Count - $done)
    Write-Ok (L 'Old restore points: {0} removed, {1} freed' $done (Format-Size $gain))
    return $done
}

function Show-RestorePoints {
    while ($true) {
        Clear-Host
        Write-Section 'RESTORE POINTS'
        $info = Get-RestorePointInfo
        if (-not $info.Available) { Write-Warn 'System Restore is not available on this Windows.'; Wait-Key; return }
        Write-Info 'A restore point takes Windows, its settings and your programs back to an earlier state. Your documents are not touched.'
        $used = Format-Size $info.Used
        if ($info.Max -gt 0) { $used += '  (' + (L 'Windows may use up to {0}' (Format-Size $info.Max)) + ')' }
        Write-Kv 'Space used' $used
        Write-Host ''
        $points = @($info.Points)
        if ($points.Count -eq 0) { Write-Info 'No restore point yet.' }
        for ($i = $points.Count - 1; $i -ge 0; $i--) {
            $d = Get-RestorePointDate $points[$i]
            $when = if ($d) { $d.ToString('yyyy-MM-dd HH:mm') } else { '?' }
            $tag = if ($i -eq $points.Count - 1) { L '(newest)' } else { '' }
            Write-Host ('   {0}  ' -f $when) -NoNewline -ForegroundColor DarkGray
            Write-Host ((Get-Truncated "$($points[$i].Description)" 50).PadRight(51)) -NoNewline
            Write-Host $tag -ForegroundColor Green
        }
        Write-Host ''
        Write-Option '1' 'Create a restore point now'
        if ($points.Count -gt 1) { Write-Option '2' (L 'Delete the {0} older one(s), keep the newest' ($points.Count - 1)) }
        Write-Option '3' 'System Protection settings (on/off, maximum size)'
        Write-Option '0' 'Back'
        switch (Read-Choice) {
            '1' { Write-Host ''; [void](New-YsoRestorePoint); Wait-Key }
            '2' {
                if ($points.Count -lt 2) { break }
                Write-Host ''
                if ($script:DryRun) { Write-Info 'Analyze-only mode: nothing was changed.'; Wait-Key; break }
                if (Confirm-Action (L 'Delete {0} restore point(s)? Only the newest stays - you cannot go back further than it.' ($points.Count - 1)) $false) {
                    $script:Results.Clear()
                    [void](Remove-OldRestorePoints)
                    Save-History (N 'Manual')
                    $script:Results.Clear()
                }
                Wait-Key
            }
            '3' { Start-Process -FilePath 'SystemPropertiesProtection.exe' -ErrorAction SilentlyContinue }
            '0' { return }
            default { return }
        }
    }
}

function Invoke-Analysis {
    param([switch]$PassThru)
    Write-Step 'Analyzing - nothing will be deleted...'
    $previous = $script:DryRun
    $script:DryRun = $true
    $copy = @()
    try {
        $steps = @(
            @('A: temporary files', (N 'Temporary files'), { Clear-TempFiles }),
            @('A: browser caches', (N 'Browser caches'), { Clear-BrowserCaches -NoPrompt }),
            @('A: system junk', (N 'System junk'), { Clear-SystemJunk }),
            @('A: Windows Update cache', (N 'Windows Update cache'), { Clear-UpdateCache }),
            @('A: GPU shader caches', (N 'GPU shader caches'), { Clear-ShaderCaches }),
            @('A: developer & app caches', (N 'Developer & app caches'), { Clear-DevAppCaches -NoPrompt }),
            @('A: site offline caches', (N 'Site offline caches'), { Clear-SiteOfflineCaches }),
            @('A: Recycle Bin', (N 'Recycle Bin'), { Clear-YsoRecycleBin }),
            @('A: old driver versions', (N 'Old driver versions'), { Measure-OldDrivers })
        )
        Invoke-Plan -Activity (L 'Analyze') -Steps $steps
        Show-Summary
        $copy = @($script:Results.ToArray())
    } finally {
        $script:DryRun = $previous
        $script:Results.Clear()
    }
    Write-Info ''
    Write-Info 'Deep clean (8) usually frees more on top of this - it cannot be measured in advance.'
    if (Test-PendingReboot) { Write-Warn 'Windows is waiting for a restart: restart before cleaning, or the Windows Update cache and the component store stay.' }
    Invoke-Step 'A: more space' { Show-MoreSpace }
    if ($PassThru) { return $copy }
}

function Measure-OldDrivers {
    # Analyze (A): size of the old driver versions, removed only if you choose (option 8).
    $old = @(Find-OldDrivers)
    if ($old.Count -eq 0) { return }
    $sum = [long](@($old | Measure-Object -Property Bytes -Sum).Sum)
    Add-Result -Category 'Old driver versions' -Files -1 -Bytes $sum -Skipped 0
    Write-Info (L '{0,-30} {1,12} only if you choose (option 8)' (L 'Old driver versions') (Format-Size $sum))
}

function Invoke-FullMaintenance {
    # F. -Plan: the choices made in the window, so nothing is asked here.
    param([hashtable]$Plan)
    if (-not $Plan) { $Plan = Read-MaintenancePlan }
    if (-not $Plan) { return }
    Invoke-MaintenancePlan $Plan
}

function Get-MaintenanceContext {
    # What F has to know before it starts: open browsers and apps, a pending restart, the Recycle Bin.
    return [pscustomobject]@{
        Browsers      = @(Get-Process -Name $script:BrowserProcs -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
        Apps          = @(Get-Process -Name $script:SafeToCloseApps -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
        PendingReboot = [bool](Test-PendingReboot)
        RecycleBin    = [long](Get-RecycleBinBytes)
    }
}

function Read-MaintenancePlan {
    # The questions of F in the console, all asked up front. Returns the plan, or $null to cancel.
    Write-Section 'FULL MAINTENANCE'
    Write-Info 'Restore point > temp > browsers > site offline copies > system junk > dev & app caches > GPU caches > update cache > (Recycle Bin) > DNS > deep clean > (updates) > drives'
    Write-Info 'Answer a few questions, then you can walk away.'
    Write-Host ''
    if (Test-PendingReboot) {
        Write-Warn 'Windows is waiting for a restart (updates). Until then, the Windows Update cache and the component store cannot be cleaned - on a PC that was never cleaned, that is often the biggest part.'
        Write-Info 'Best: Restart (not Shut down), then run F again.'
        if (-not (Confirm-Action 'Continue anyway?' $false)) { return $null }
        Write-Host ''
    }
    $p = @{}
    $p.Restore = Confirm-Action 'Create a restore point first? (recommended)' $true
    $openBrowsers = @(Get-Process -Name $script:BrowserProcs -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
    $openApps = @(Get-Process -Name $script:SafeToCloseApps -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)

    # Complete clean = everything that is safe (the default). Only what cannot be undone is asked separately.
    Write-Host ''
    Write-Info 'Complete clean (recommended - frees the most):'
    $items = @()
    if ($openBrowsers.Count -gt 0) { $items += (L 'closes {0} (your tabs come back when you reopen it)' ($openBrowsers -join ', ')) }
    if ($openApps.Count -gt 0) { $items += (L 'closes {0} (nothing is lost)' ($openApps -join ', ')) }
    $items += @((L 'offline copies kept by websites (you stay logged in)'), (L 'GPU shader caches (games may stutter briefly the first time)'),
                (L 'deep clean: Windows Disk Cleanup + component store (adds 10-30 min)'))
    foreach ($it in $items) { Write-Info ('  - ' + $it) }
    $complete = Confirm-Action 'Complete clean?' $true
    if ($complete) {
        $p.CloseBrowsers = ($openBrowsers.Count -gt 0); $closeApps = ($openApps.Count -gt 0)
        $p.SiteCaches = $true; $p.Gpu = $true; $p.Deep = $true
    } else {
        $p.CloseBrowsers = $false; $closeApps = $false
        if ($openBrowsers.Count -gt 0) { $p.CloseBrowsers = Confirm-Action 'Browsers are open. Close them for a complete clean?' $false }
        if ($openApps.Count -gt 0) { $closeApps = Confirm-Action (L 'Also close {0} for a complete clean? (nothing is lost)' ($openApps -join ', ')) $false }
        $p.SiteCaches = Confirm-Action 'Also remove offline copies kept by websites? (you stay logged in)' $false
        $p.Gpu        = Confirm-Action 'Also clear GPU shader caches? (games may stutter briefly the first time)' $false
        $p.Deep       = Confirm-Action 'Include deep clean? (Disk Cleanup + component store, adds 10-30 min)' $false
    }
    $p.CloseApps = $(if ($closeApps) { [string[]]$openApps } else { [string[]]@() })
    $p.OldDrivers = $false
    if ($p.Deep) {
        Write-Info 'Looking for old driver versions...'
        $oldDrivers = @(Find-OldDrivers)
        if ($oldDrivers.Count -gt 0) {
            Write-Info (Get-OldDriversText $oldDrivers)
            $p.OldDrivers = Confirm-Action 'Also remove these old driver versions? You will not be able to go back to them.' $false
        }
    }
    $p.RecycleBin = $false
    $binBytes = Get-RecycleBinBytes
    if ($binBytes -gt 0) {
        $p.RecycleBin = Confirm-Action (L 'Also permanently empty the Recycle Bin ({0})?' (Format-Size $binBytes)) $false
    }
    $p.Updates  = Confirm-Action 'Also install app and driver updates? (like automatic updates: never open apps, adds 5-30 min)' $false
    $p.Optimize = Confirm-Action 'Optimize drives at the end? (TRIM / defrag)' $true
    Write-Host ''
    return $p
}

function Get-PlanFlag([hashtable]$Plan, [string]$Key, [bool]$Default) {
    if ($Plan.ContainsKey($Key)) { return [bool]$Plan[$Key] }
    return $Default
}

function Invoke-MaintenancePlan {
    # Runs F from a plan: Restore, Temp, Browsers, CloseBrowsers, SiteCaches, SystemJunk, CloseApps (names, or
    # $true = those open now), DevApps, Gpu, UpdateCache, RecycleBin, Dns, Deep, OldDrivers, Updates, Optimize.
    # Missing keys: the always-safe parts run, the others do not.
    param([hashtable]$Plan)
    $closeBrowsers = Get-PlanFlag $Plan 'CloseBrowsers' $false
    $closeApps = @()
    if ($Plan['CloseApps'] -is [bool]) {
        if ($Plan['CloseApps']) { $closeApps = @(Get-Process -Name $script:SafeToCloseApps -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) }
    } elseif ($Plan['CloseApps']) { $closeApps = @($Plan['CloseApps']) }
    $doDeep = Get-PlanFlag $Plan 'Deep' $false
    $doDrivers = Get-PlanFlag $Plan 'OldDrivers' $false

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $steps = @()
    if (Get-PlanFlag $Plan 'Restore' $false)     { $steps += , @('F: restore point', (N 'Restore point'), { [void](New-YsoRestorePoint) }) }
    if (Get-PlanFlag $Plan 'Temp' $true)         { $steps += , @('F: temporary files', (N 'Temporary files'), { Clear-TempFiles }) }
    if (Get-PlanFlag $Plan 'Browsers' $true)     { $steps += , @('F: browser caches', (N 'Browser caches'), { Clear-BrowserCaches -NoPrompt -CloseBrowsers:$closeBrowsers }) }
    if (Get-PlanFlag $Plan 'SiteCaches' $false)  { $steps += , @('F: site offline caches', (N 'Site offline caches'), { Clear-SiteOfflineCaches -Confirmed }) }
    if (Get-PlanFlag $Plan 'SystemJunk' $true)   { $steps += , @('F: system junk', (N 'System junk'), { Clear-SystemJunk }) }
    if ($closeApps.Count -gt 0)                  { $steps += , @('F: close apps', (N 'Closing apps'), { Close-Apps $closeApps }) }
    if (Get-PlanFlag $Plan 'DevApps' $true)      { $steps += , @('F: developer & app caches', (N 'Developer & app caches'), { Clear-DevAppCaches -NoPrompt }) }
    if (Get-PlanFlag $Plan 'Gpu' $false)         { $steps += , @('F: GPU shader caches', (N 'GPU shader caches'), { Clear-ShaderCaches }) }
    if (Get-PlanFlag $Plan 'UpdateCache' $true)  { $steps += , @('F: Windows Update cache', (N 'Windows Update cache'), { Clear-UpdateCache }) }
    if (Get-PlanFlag $Plan 'RecycleBin' $false)  { $steps += , @('F: Recycle Bin', (N 'Recycle Bin'), { Clear-YsoRecycleBin -Confirmed }) }
    if (Get-PlanFlag $Plan 'Dns' $true)          { $steps += , @('F: DNS cache', (N 'DNS cache'), { Clear-Dns }) }
    if ($doDeep) { $steps += , @('F: deep clean', (N 'Deep clean'), { Invoke-DeepClean -OldDrivers $(if ($doDrivers) { 'yes' } else { 'no' }) }) }
    elseif ($doDrivers) {
        $steps += , @('F: old driver versions', (N 'Old driver versions'), {
            $old = @(Find-OldDrivers)
            if ($old.Count -gt 0) { Remove-OldDriverPackages $old } else { Write-Ok 'No old driver versions.' }
        })
    }
    if (Get-PlanFlag $Plan 'Updates' $false)     { $steps += , @('F: updates', (N 'Updates'), { [void](Invoke-UpdateRun -Mode 'Full') }) }
    if (Get-PlanFlag $Plan 'Optimize' $false)    { $steps += , @('F: optimize drives', (N 'Optimize drives'), { Optimize-Drives }) }
    Invoke-Plan -Activity (L 'Full maintenance') -Steps $steps
    $timer.Stop()
    Write-Host ''
    Write-Ok (L 'Full maintenance finished in {0} min {1} s.' ([int][math]::Floor($timer.Elapsed.TotalMinutes)) $timer.Elapsed.Seconds)
    Invoke-Step 'F: more space' { Show-MoreSpace }
    if (Test-PendingReboot) { Write-Warn 'Restart the PC (Restart, not Shut down) to finish: Windows completes some cleanups and updates during the restart.' }
}

function Show-MoreSpace {
    # Big things YSO never removes in one go: they change how Windows works, or cannot be undone.
    $rows = @()
    $old = Join-Path $env:SystemDrive 'Windows.old'
    if (Test-Path -LiteralPath $old) { $rows += , @((N 'Previous Windows version (Windows.old)'), (L 'option 9')) }
    $hib = Get-Item -LiteralPath (Join-Path $env:SystemDrive 'hiberfil.sys') -Force -ErrorAction SilentlyContinue
    if ($hib -and $hib.Length -ge 1GB) { $rows += , @((L 'Hibernation file: {0}' (Format-Size $hib.Length)), (L 'option 10 can shrink it')) }
    $bin = Get-RecycleBinBytes
    if ($bin -ge 100MB) { $rows += , @((L 'Recycle Bin: {0}' (Format-Size $bin)), (L 'option 5')) }
    $shadow = [long]0
    try { foreach ($v in @(Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction Stop)) { $shadow += [long]$v.UsedSpace } } catch { }
    if ($shadow -ge 1GB) { $rows += , @((L 'Restore points: {0}' (Format-Size $shadow)), (L 'R: keep only the newest')) }
    if ($rows.Count -eq 0) { return }
    Write-Section 'MORE SPACE, IF YOU WANT IT'
    foreach ($r in $rows) {
        Write-Host ('  {0,-48} ' -f (L $r[0])) -NoNewline
        Write-Host $r[1] -ForegroundColor DarkGray
    }
    Write-Info 'Space finder (27) shows what else fills your disk (downloads, videos, games...).'
}

function Get-AutoCleanList {
    $on = @($script:AutoCleanNames.Keys | Where-Object { $script:Settings.AutoClean[$_] } | ForEach-Object { L $script:AutoCleanNames[$_] })
    if ($on.Count -eq 0) { return (L '(nothing)') }
    return ($on -join ', ')
}

function Set-AutoClean {
    $existing = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        $next = (Get-ScheduledTaskInfo -TaskName $script:TaskName -ErrorAction SilentlyContinue).NextRunTime
        Write-Ok (L 'Weekly auto-clean is ON. Next run: {0}' $next)
        Write-Info (L 'It cleans: {0} (change this in Settings, option O).' (Get-AutoCleanList))
        if (Confirm-Action 'Turn it off?' $false) {
            Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
            Remove-YsoCopyIfUnused
            Write-Ok 'Weekly auto-clean removed.'
        }
        return
    }
    if (-not $PSCommandPath) { Write-Warn 'Start YSO from its file to use this option.'; return }
    Write-Info 'Runs every Sunday at 03:00 (or at the next startup if the PC was off), silently, only when plugged in.'
    Write-Info (L 'It cleans: {0} (change this in Settings, option O).' (Get-AutoCleanList))
    Write-Info 'It never closes your apps and never empties the Recycle Bin.'
    if (-not (Confirm-Action 'Turn on weekly auto-clean?' $true)) { return }
    if (Register-AutoCleanTask) { Write-Ok 'Weekly auto-clean is ON. Results go to the logs (L) and the history (H).' }
}

function Register-AutoCleanTask {
    # Runs as SYSTEM every Sunday at 03:00, so it runs the protected copy in Program Files.
    $target = Install-YsoCopy
    if (-not $target) { Write-Warn 'Start YSO from its file to use this option.'; return $false }
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`" -Auto"
    $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '03:00'
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    try {
        Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Principal $principal -Description 'YSO - Your System Optimizer - weekly safe cleanup' -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Warn (L 'Could not create the scheduled task: {0}' $_.Exception.Message)
        return $false
    }
}

function Show-Settings {
    while ($true) {
        Clear-Host
        Write-Section 'SETTINGS'
        $current = if ($script:Lang -eq 'fr') { "Français" } else { 'English' }
        $langText = switch ($script:Settings.Language) {
            'en'    { 'English' }
            'fr'    { "Français" }
            default { L 'Automatic ({0})' $current }
        }
        Write-Kv 'Language' $langText
        Write-Kv 'Keep temp files newer than' (L '{0} h' $script:Settings.TempMinAgeHours)
        Write-Kv 'Keep logs and dumps newer than' (L '{0} days' $script:Settings.LogMinAgeDays)
        Write-Kv 'Weekly auto-clean cleans' (Get-AutoCleanList)
        $ex = @($script:Settings.ExcludeFolders)
        Write-Kv 'Never touch' $(if ($ex.Count) { $ex -join '; ' } else { L '(none)' })
        Write-Kv 'New versions of YSO' $(if ($script:Settings.CheckForUpdates) { L 'checked on GitHub when YSO opens' } else { L 'not checked' })
        Write-Kv 'Settings file' $script:SettingsPath 'DarkGray'
        if ($script:SettingsError) { Write-Warn 'settings.json has an error, so defaults are in use. Fix it (6) or reset it (7).' }
        Write-Host ''
        Write-Option '1' 'Language / Langue'
        Write-Option '2' 'Choose what weekly auto-clean cleans'
        Write-Option '3' 'Change age limits'
        Write-Option '4' 'Add a folder to never touch'
        Write-Option '5' 'Remove a folder from that list'
        Write-Option '6' 'Edit the settings file in Notepad'
        Write-Option '7' 'Reset to defaults'
        Write-Option '8' $(if ($script:Settings.CheckForUpdates) { N 'Stop checking for new versions of YSO' } else { N 'Check for new versions of YSO' })
        Write-Option '0' 'Back'
        switch (Read-Choice) {
            '1' {
                Write-Host ''
                Write-Option 'E' 'English (default)'
                Write-Option 'F' "Français"
                Write-Option 'A' 'Automatic (same as Windows) / Automatique (comme Windows)'
                $pick = Read-Choice
                $map = @{ E = 'en'; F = 'fr'; A = 'auto' }
                if ($map.ContainsKey($pick)) {
                    $script:Settings.Language = $map[$pick]
                    $script:Lang = Resolve-Language $map[$pick]
                    [void](Save-Settings)
                }
            }
            '2' {
                $keys = @($script:AutoCleanNames.Keys)
                while ($true) {
                    Write-Host ''
                    for ($i = 0; $i -lt $keys.Count; $i++) {
                        $mark = if ($script:Settings.AutoClean[$keys[$i]]) { '[x]' } else { '[ ]' }
                        Write-Option "$($i + 1)" ('{0} {1}' -f $mark, (L $script:AutoCleanNames[$keys[$i]]))
                    }
                    $c = Read-Choice 'Number to switch on/off, Enter when done'
                    if (-not $c) { break }
                    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $keys.Count) {
                        $k = $keys[[int]$c - 1]
                        $script:Settings.AutoClean[$k] = -not $script:Settings.AutoClean[$k]
                    }
                }
                [void](Save-Settings)
            }
            '3' {
                $n = 0
                $h = Read-Host ('  ' + (L 'Keep temp files newer than how many hours? (1-720) [{0}]' $script:Settings.TempMinAgeHours))
                if ([int]::TryParse("$h", [ref]$n) -and $n -ge 1 -and $n -le 720) { $script:Settings.TempMinAgeHours = $n }
                $d = Read-Host ('  ' + (L 'Keep logs and dumps newer than how many days? (1-365) [{0}]' $script:Settings.LogMinAgeDays))
                if ([int]::TryParse("$d", [ref]$n) -and $n -ge 1 -and $n -le 365) { $script:Settings.LogMinAgeDays = $n }
                [void](Save-Settings)
            }
            '4' {
                $p = "$(Read-Host ('  ' + (L 'Folder to never touch (full path)')))".Trim().Trim('"')
                if ($p -and (Test-Path -LiteralPath $p -PathType Container)) {
                    $full = (Get-Item -LiteralPath $p -Force).FullName.TrimEnd('\')
                    $script:Settings.ExcludeFolders = [string[]]@(@($script:Settings.ExcludeFolders) + $full | Sort-Object -Unique)
                    if (Save-Settings) { Write-Ok (L 'Added: {0}' $full) }
                } elseif ($p) { Write-Warn (L 'Folder not found: {0}' $p) }
                Start-Sleep -Seconds 2
            }
            '5' {
                $ex = @($script:Settings.ExcludeFolders)
                if ($ex.Count -eq 0) { Write-Info 'The list is empty.'; Start-Sleep -Seconds 2; break }
                for ($i = 0; $i -lt $ex.Count; $i++) { Write-Option "$($i + 1)" $ex[$i] }
                $c = Read-Choice 'Number to remove, Enter to cancel'
                if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $ex.Count) {
                    $drop = $ex[[int]$c - 1]
                    $script:Settings.ExcludeFolders = [string[]]@($ex | Where-Object { $_ -ne $drop })
                    [void](Save-Settings)
                }
            }
            '6' {
                if (-not (Test-Path -LiteralPath $script:SettingsPath)) { [void](Save-Settings) }
                Write-Info 'Close Notepad to apply your changes.'
                Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$($script:SettingsPath)`"" -Wait
                Import-Settings
            }
            '7' {
                if (Confirm-Action 'Reset all settings to defaults?' $false) {
                    $script:Settings = Get-DefaultSettings
                    $script:SettingsError = $false
                    $script:Lang = Resolve-Language $script:Settings.Language
                    [void](Save-Settings)
                }
            }
            '8' {
                $script:Settings.CheckForUpdates = -not $script:Settings.CheckForUpdates
                Remove-Item -LiteralPath $script:UpdateCheckPath -Force -ErrorAction SilentlyContinue
                [void](Save-Settings)
            }
            '0' { return }
        }
    }
}

# ==================================================================
#  SELF-TEST & PROBLEM REPORTS  (T, P)
# ==================================================================
function Result-Ok([string]$Detail = '')      { return [pscustomobject]@{ __Check = 'OK'; Detail = $Detail } }
function Result-Info([string]$Detail = '')    { return [pscustomobject]@{ __Check = 'INFO'; Detail = $Detail } }
function Result-Missing([string]$Detail = '') { return [pscustomobject]@{ __Check = 'MISSING'; Detail = $Detail } }
function Result-Broken([string]$Detail = '')  { return [pscustomobject]@{ __Check = 'BROKEN'; Detail = $Detail } }

function Add-Check {
    param([string]$Area, [string]$Name, [string]$Status, [string]$Detail = '')
    $Detail = ("$Detail" -replace '\s*[\r\n]+\s*', ' ').Trim()
    $script:Checks.Add([pscustomobject]@{ Area = $Area; Name = $Name; Status = $Status; Detail = $Detail })
    $label = switch ($Status) { 'OK' { N 'OK' } 'INFO' { N 'INFO' } 'MISSING' { N 'MISSING' } default { N 'BROKEN' } }
    $color = switch ($Status) { 'OK' { 'Green' } 'INFO' { 'Gray' } 'MISSING' { 'Yellow' } default { 'Red' } }
    Write-Host ('  {0,-9}' -f (L $label)) -NoNewline -ForegroundColor $color
    Write-Host ((Get-Truncated (L $Name) 42).PadRight(44)) -NoNewline
    Write-Host (Get-Truncated $Detail 60) -ForegroundColor DarkGray
}

function Test-Check {
    # Runs one check. A check returns Result-Ok/Info/Missing/Broken; an unexpected error counts as BROKEN.
    param([string]$Area, [string]$Name, [scriptblock]$Test)
    try {
        $res = @(& $Test) | Where-Object { $null -ne $_ -and $_.PSObject.Properties['__Check'] } | Select-Object -Last 1
        if (-not $res) { $res = Result-Ok }
        Add-Check $Area $Name $res.__Check $res.Detail
    } catch {
        Write-YsoError -Context ('self-test: ' + $Name) -ErrorRecord $_
        Add-Check $Area $Name 'BROKEN' $_.Exception.Message
    }
}

function Get-MissingCommands([string[]]$Names) {
    return @($Names | Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) })
}

function Test-ExeExists([string]$Name) {
    return [bool](Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Test-Engine {
    # Runs the real deletion engine on this PC's disk, inside its own test folder only.
    $root = Join-Path $env:TEMP ('YsoSelfTest_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $keep = Join-Path $root 'keep-me'
    $work = Join-Path $root 'work'
    $link = Join-Path $work 'link-to-keep-me'
    $savedExclude = $script:Settings.ExcludeFolders
    $savedDry = $script:DryRun
    $name1 = N 'Removes old files, keeps recent ones'
    $name2 = N 'Files in use are skipped'
    $name3 = N 'Folder links are never followed'
    $name4 = N 'Files deeper than 260 characters'
    try {
        New-Item -ItemType Directory -Path $keep -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work 'sub\deep') -Force | Out-Null
        $old = (Get-Date).AddDays(-10)
        $made = @{
            precious = (Join-Path $keep 'precious.txt')
            oldFile  = (Join-Path $work 'old.tmp')
            newFile  = (Join-Path $work 'new.tmp')
            deepFile = (Join-Path $work 'sub\deep\old2.tmp')
            readOnly = (Join-Path $work 'readonly.tmp')
            locked   = (Join-Path $work 'locked.tmp')
        }
        foreach ($k in @($made.Keys)) {
            [System.IO.File]::WriteAllBytes($made[$k], (New-Object byte[] 2048))
            if ($k -ne 'newFile') { (Get-Item -LiteralPath $made[$k]).LastWriteTime = $old }
        }
        (Get-Item -LiteralPath $made.readOnly).IsReadOnly = $true
        $linkMade = $true
        try { New-Item -ItemType Junction -Path $link -Target $keep -ErrorAction Stop | Out-Null } catch { $linkMade = $false }
        if ($linkMade) {
            $made_link = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
            $linkMade = ($made_link -and ($made_link.Attributes -band [System.IO.FileAttributes]::ReparsePoint))
        }
        foreach ($d in @((Join-Path $work 'sub\deep'), (Join-Path $work 'sub'))) { (Get-Item -LiteralPath $d).LastWriteTime = $old }

        $script:Settings.ExcludeFolders = [string[]]@()
        $script:DryRun = $false
        $lock = [System.IO.File]::Open($made.locked, 'Open', 'Read', 'None')
        try {
            $r = Invoke-Purge -Category 'Self-test' -Targets @(@{ Path = (Esc $work); Days = 1 }) -Quiet
        } finally { $lock.Dispose() }

        $problems = @()
        foreach ($k in @('oldFile', 'deepFile', 'readOnly')) {
            if (Test-Path -LiteralPath $made[$k]) { $problems += (L 'old file not removed: {0}' ([System.IO.Path]::GetFileName($made[$k]))) }
        }
        if (-not (Test-Path -LiteralPath $made.newFile)) { $problems += (L 'a recent file was removed') }
        if (Test-Path -LiteralPath (Join-Path $work 'sub')) { $problems += (L 'empty folders were left behind') }
        if ($problems.Count -eq 0) { Add-Check 'Engine' $name1 'OK' (L '{0} files removed' $r.Files) }
        else { Add-Check 'Engine' $name1 'BROKEN' ($problems -join '; ') }

        if ((Test-Path -LiteralPath $made.locked) -and $r.Skipped -ge 1) { Add-Check 'Engine' $name2 'OK' }
        else { Add-Check 'Engine' $name2 'BROKEN' (L 'a file in use was not handled as expected') }

        if (-not $linkMade) { Add-Check 'Engine' $name3 'INFO' (L 'could not create a test link here') }
        elseif ((Test-Path -LiteralPath $made.precious) -and (Test-Path -LiteralPath $link)) { Add-Check 'Engine' $name3 'OK' }
        else { Add-Check 'Engine' $name3 'BROKEN' (L 'a file behind a folder link was touched') }

        # A file deeper than 260 characters (deep caches, node projects): Windows PowerShell needs \\?\ for it.
        $deepRoot = Join-Path $root 'long'
        $p = $deepRoot
        for ($i = 0; $i -lt 6; $i++) { $p = [System.IO.Path]::Combine($p, ('d' * 45) + $i) }
        $deepFile = [System.IO.Path]::Combine($p, 'old-deep.tmp')
        $made4 = $false
        try {
            [void][System.IO.Directory]::CreateDirectory((Get-LongPath $p -Always))
            [System.IO.File]::WriteAllBytes((Get-LongPath $deepFile -Always), (New-Object byte[] 1024))
            [System.IO.File]::SetLastWriteTime((Get-LongPath $deepFile -Always), $old)
            $made4 = $true
        } catch { Add-Check 'Engine' $name4 'MISSING' (L 'this Windows cannot create such paths: {0}' $_.Exception.Message) }
        if ($made4) {
            $r4 = Invoke-Purge -Category 'Self-test' -Targets @(@{ Path = (Esc $deepRoot); Days = 1 }) -Quiet
            if ([System.IO.File]::Exists((Get-LongPath $deepFile -Always))) { Add-Check 'Engine' $name4 'BROKEN' (L 'a file {0} characters deep was not removed' $deepFile.Length) }
            else { Add-Check 'Engine' $name4 'OK' (L '{0} characters' $deepFile.Length) }
        }
    } catch {
        Write-YsoError -Context 'self-test: engine' -ErrorRecord $_
        Add-Check 'Engine' $name1 'BROKEN' $_.Exception.Message
    } finally {
        $script:Settings.ExcludeFolders = $savedExclude
        $script:DryRun = $savedDry
        try { if (Test-Path -LiteralPath $link) { [System.IO.Directory]::Delete($link, $false) } } catch { }
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        try { if ([System.IO.Directory]::Exists((Get-LongPath $root -Always))) { [System.IO.Directory]::Delete((Get-LongPath $root -Always), $true) } } catch { }
    }
}

function Get-AppDataRoots {
    # Data folders of the apps YSO knows. The self-test looks inside them for big folders YSO does not clean.
    $roots = @()
    foreach ($p in $script:Profiles) {
        $L = Join-Path $p 'AppData\Local'
        $R = Join-Path $p 'AppData\Roaming'
        foreach ($r in @(
            @('Chrome', "$L\Google\Chrome\User Data"), @('Edge', "$L\Microsoft\Edge\User Data"),
            @('Brave', "$L\BraveSoftware\Brave-Browser\User Data"), @('Vivaldi', "$L\Vivaldi\User Data"),
            @('Opera', "$L\Opera Software"), @('Opera', "$R\Opera Software"), @('Firefox', "$L\Mozilla\Firefox\Profiles"),
            @('Spotify', "$L\Spotify"), @('Spotify', "$R\Spotify"), @('Steam', "$L\Steam"), @('Discord', "$R\discord"),
            @('VS Code', "$R\Code"), @('Teams', "$L\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"), @('OneDrive', "$L\Microsoft\OneDrive")
        )) { $roots += [pscustomobject]@{ App = $r[0]; Path = $r[1] } }
        foreach ($pkg in @(Get-ChildItem -LiteralPath (Join-Path $L 'Packages') -Directory -Filter 'SpotifyAB.SpotifyMusic_*' -ErrorAction SilentlyContinue)) {
            $roots += [pscustomobject]@{ App = 'Spotify'; Path = $pkg.FullName }
        }
    }
    $steam = @(Get-SteamRoots)
    if ($steam.Count -gt 0) {
        foreach ($sub in @('appcache', 'logs', 'dumps')) { $roots += [pscustomobject]@{ App = 'Steam'; Path = (Join-Path $steam[0] $sub) } }
    }
    return @($roots | Where-Object { Test-Path -LiteralPath $_.Path -PathType Container })
}

function Get-UncoveredFolders {
    # Big folders inside known apps that YSO's cleaning does not reach. Most are normal (site data,
    # extensions, settings, offline downloads); the list shows where a missed cache would be.
    param([long]$MinBytes = 20MB, [int]$PerRoot = 5)
    $sep = [char[]]@('\', '/')
    $covered = @(@(Get-BrowserCacheTargets) + @(Get-AppCacheTargets) + @(Get-SiteOfflineCacheTargets) | ForEach-Object {
        Resolve-Path -Path $_.Path -ErrorAction SilentlyContinue | ForEach-Object { $_.ProviderPath.TrimEnd($sep) }
    } | Sort-Object -Unique)
    $rows = @()
    foreach ($r in Get-AppDataRoots) {
        $root = (Get-Item -LiteralPath $r.Path -Force).FullName.TrimEnd($sep)
        $scan = Get-FolderSizes -Root $root -BigFileMin ([long]::MaxValue)
        $cands = @()
        foreach ($path in @($scan.Total.Keys)) {
            $full = (ConvertFrom-LongPath "$path").TrimEnd($sep)
            if ($full -eq $root) { continue }
            $size = [long]$scan.Total[$path]
            if ($size -lt $MinBytes) { continue }
            $rel = $full.Substring($root.Length).TrimStart($sep)
            if (@($rel.Split($sep)).Count -gt 3) { continue }
            $skip = $false
            foreach ($c in $covered) {
                # inside a folder YSO cleans, or holding one: either way not a "missed" folder
                if ($full -ieq $c -or $full.StartsWith($c + '\', 'OrdinalIgnoreCase') -or $full.StartsWith($c + '/', 'OrdinalIgnoreCase') -or
                    $c.StartsWith($full + '\', 'OrdinalIgnoreCase') -or $c.StartsWith($full + '/', 'OrdinalIgnoreCase')) { $skip = $true; break }
            }
            if (-not $skip) { $cands += [pscustomobject]@{ App = $r.App; Root = $root; Path = $full; Rel = $rel; Size = $size } }
        }
        # Keep the most precise folder: drop a parent when one of its listed children holds most of its size.
        $cands = @($cands | Sort-Object Size -Descending)
        $kept = @(foreach ($c in $cands) {
            $child = $cands | Where-Object { ($_.Path.StartsWith($c.Path + '\', 'OrdinalIgnoreCase') -or $_.Path.StartsWith($c.Path + '/', 'OrdinalIgnoreCase')) -and $_.Size -ge 0.7 * $c.Size } | Select-Object -First 1
            if (-not $child) { $c }
        })
        $rows += @($kept | Select-Object -First $PerRoot)
    }
    return @($rows | Sort-Object Size -Descending)
}

function Get-FriendlyPath([string]$Path) {
    # C:\Users\name\AppData\Local\... -> %LOCALAPPDATA%\... (shorter, and no user name)
    $norm = $Path.Replace('/', '\')
    foreach ($p in $script:Profiles) {
        foreach ($pair in @(@("$p\AppData\Local", '%LOCALAPPDATA%'), @("$p\AppData\Roaming", '%APPDATA%'))) {
            $base = $pair[0].Replace('/', '\')
            if ($norm.StartsWith($base, 'OrdinalIgnoreCase')) { return $pair[1] + $norm.Substring($base.Length) }
        }
    }
    return $Path
}

function Invoke-SelfTest {
    $script:Checks.Clear()
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Section 'SELF-TEST'
    Write-Info 'Checks every feature on this PC. Nothing on your PC is changed: it only uses its own test folder.'

    Write-Section 'THIS PC'
    try {
        Write-Kv 'YSO' ('v{0}  ({1})' -f $script:Version, $PSCommandPath)
        Write-Kv 'Windows' $script:OsText
        Write-Kv 'PowerShell' ('{0} ({1})' -f $PSVersionTable.PSVersion, $ExecutionContext.SessionState.LanguageMode)
        $culture = '?'
        try { $culture = (Get-UICulture).Name } catch { }
        Write-Kv 'Display language' $culture
        $device = if ($script:IsServer) { L 'server' } elseif (Test-IsLaptop) { L 'laptop' } else { L 'desktop' }
        Write-Kv 'Device' $device
        Write-Kv 'User profiles' $script:Profiles.Count
    } catch { Write-YsoError -Context 'self-test: this PC' -ErrorRecord $_ }

    Write-Section 'CLEANING ENGINE'
    Test-Engine

    Write-Section 'YSO FILES'
    Test-Check 'Files' 'Settings and logs folder' {
        $probe = Join-Path $script:DataDir ('write-test_{0}.tmp' -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        Set-Content -LiteralPath $probe -Value 'ok' -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
        if ($script:SettingsError) { Result-Broken (L 'settings.json has an error') } else { Result-Ok $script:DataDir }
    }
    Test-Check 'Files' 'Settings folder only changed by administrators' {
        if ([Environment]::OSVersion.Platform -ne 'Win32NT') { return (Result-Info 'not Windows') }
        if (Test-UsersCanWrite $script:DataDir) { Result-Broken (L 'standard users can change files in {0}' $script:DataDir) } else { Result-Ok }
    }
    Test-Check 'Files' 'Session log' {
        if ($script:TranscriptOn) { Result-Ok } else { Result-Broken (L 'not recording') }
    }
    Test-Check 'Files' 'Errors recorded' {
        $n = 0; $last = ''
        if (Test-Path -LiteralPath $script:ErrorLogPath) {
            $heads = @(Select-String -LiteralPath $script:ErrorLogPath -Pattern '^==== ' -ErrorAction SilentlyContinue)
            $n = $heads.Count
            if ($n -gt 0) { $last = ($heads[-1].Line -split '\|')[0].Replace('====', '').Trim() }
        }
        if ($n -eq 0) { Result-Ok '0' } else { Result-Info (L '{0} (last: {1}) - send them with P' $n $last) }
    }

    Write-Section 'CLEAN (1-10)'
    Test-Check 'Clean' 'Fixed drives (all cleaning options)' {
        $v = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter })
        if ($v.Count -eq 0) { Result-Broken (L 'no drives found') }
        else { Result-Ok (($v | ForEach-Object { "$($_.DriveLetter):" }) -join ' ') }
    }
    Test-Check 'Clean' 'Browsers found (2)' {
        $known = @(
            @('Chrome', 'AppData\Local\Google\Chrome\User Data'), @('Edge', 'AppData\Local\Microsoft\Edge\User Data'),
            @('Firefox', 'AppData\Local\Mozilla\Firefox\Profiles'), @('Brave', 'AppData\Local\BraveSoftware\Brave-Browser\User Data'),
            @('Opera', 'AppData\Local\Opera Software'), @('Vivaldi', 'AppData\Local\Vivaldi\User Data')
        )
        $found = @()
        foreach ($p in $script:Profiles) {
            foreach ($b in $known) { if (Test-Path -LiteralPath (Join-Path $p $b[1])) { $found += $b[0] } }
        }
        $found = @($found | Sort-Object -Unique)
        if ($found.Count -gt 0) { Result-Ok ($found -join ', ') } else { Result-Info (L 'no supported browser found') }
    }
    Test-Check 'Clean' 'Windows Update cache (4)' {
        $svc = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        if (-not $svc) { return (Result-Broken (L 'Windows Update service not found')) }
        if (Test-Path -LiteralPath (Join-Path $env:WINDIR 'SoftwareDistribution\Download')) {
            if ("$($svc.Status)" -eq 'Running') { Result-Ok (L 'service running') } else { Result-Ok (L 'service stopped - normal, it starts when needed') }
        }
        else { Result-Info (L 'download folder not created yet') }
    }
    Test-Check 'Clean' 'Delivery Optimization cache (4)' {
        if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) { Result-Ok }
        else { Result-Missing (L 'not on this Windows version - that part is skipped') }
    }
    Test-Check 'Clean' 'Updates downloaded, not installed yet (4)' {
        # the question asked before the Windows Update cache is cleaned (no internet needed)
        $searcher = (New-UpdateSession).CreateUpdateSearcher()
        $searcher.Online = $false
        $found = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $n = 0
        for ($i = 0; $i -lt $found.Updates.Count; $i++) { if ($found.Updates.Item($i).IsDownloaded) { $n++ } }
        Result-Ok (L '{0} waiting: the cache is kept while there are any' $n)
    }
    Test-Check 'Clean' 'Recycle Bin (5)' {
        if (-not (Get-Command -Name 'Clear-RecycleBin' -ErrorAction SilentlyContinue)) { return (Result-Broken (L 'missing: {0}' 'Clear-RecycleBin')) }
        Result-Ok (Format-Size (Get-RecycleBinBytes))
    }
    Test-Check 'Clean' 'Disk Cleanup (8, 9)' {
        if (-not (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\cleanmgr.exe'))) { return (Result-Missing (L 'not installed on this Windows')) }
        $keys = @(Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches' -ErrorAction Stop | ForEach-Object { $_.PSChildName })
        $n = @($script:SafeCleanupHandlers | Where-Object { $keys -contains $_ }).Count
        Result-Ok (L '{0} of {1} safe categories available' $n $script:SafeCleanupHandlers.Count)
    }
    Test-Check 'Clean' 'Hibernation file (10)' {
        if (-not (Test-ExeExists 'powercfg.exe')) { return (Result-Broken (L 'missing: {0}' 'powercfg.exe')) }
        $hib = Get-Item -LiteralPath (Join-Path $env:SystemDrive 'hiberfil.sys') -Force -ErrorAction SilentlyContinue
        $state = if ($hib) { Format-Size $hib.Length } else { L 'hibernation is off' }
        if ($script:Build -lt 10240) { Result-Missing (L 'choosing the size needs Windows 10') } else { Result-Ok $state }
    }

    Write-Section 'NETWORK (11-14)'
    Test-Check 'Network' 'Network tools (11-14)' {
        $m = Get-MissingCommands @('Get-NetRoute', 'Get-NetAdapter', 'Get-NetIPInterface', 'Resolve-DnsName', 'Set-DnsClientServerAddress', 'Clear-DnsClientCache')
        if ($m.Count -gt 0) { Result-Broken (L 'missing: {0}' ($m -join ', ')) } else { Result-Ok }
    }
    Test-Check 'Network' 'Internet connection (11)' {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $route) { return (Result-Info (L 'offline - the network tests will not work')) }
        $ping = Measure-Ping '1.1.1.1' 2
        if ($null -eq $ping.Avg) { Result-Info (L 'connected, but ping is blocked or the internet is down') }
        else { Result-Ok (L '{0:N0} ms' $ping.Avg) }
    }
    Test-Check 'Network' 'Wi-Fi signal (11)' {
        $wifi = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq 'Up' -and ("$($_.PhysicalMediaType)" -match '802\.11' -or "$($_.InterfaceDescription)" -match 'Wi-?Fi|Wireless|WLAN|802\.11') })
        if ($wifi.Count -eq 0) { return (Result-Info (L 'no Wi-Fi connection in use')) }
        $sig = @(netsh.exe wlan show interfaces 2>$null) | Select-String -Pattern ':\s*(\d{1,3})\s?%' | Select-Object -First 1
        if ($sig) { Result-Ok ('{0}%' -f $sig.Matches[0].Groups[1].Value) }
        else { Result-Info (L 'unavailable (Windows may need Location turned on)') }
    }

    Write-Section 'OPTIMIZE (15-18)'
    Test-Check 'Optimize' 'Drive optimization (15)' {
        $m = Get-MissingCommands @('Optimize-Volume', 'Get-PhysicalDisk', 'Get-Partition')
        if ($m.Count -gt 0) { return (Result-Broken (L 'missing: {0}' ($m -join ', '))) }
        Result-Ok ((@(Get-PhysicalDisk -ErrorAction Stop) | ForEach-Object { "$($_.MediaType)" }) -join ', ')
    }
    Test-Check 'Optimize' 'Power plans (16)' {
        $list = @(powercfg.exe /list 2>$null)
        if ($LASTEXITCODE -ne 0) { return (Result-Broken (L 'powercfg failed (code {0})' $LASTEXITCODE)) }
        $n = @($list | Where-Object { $_ -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-' }).Count
        if ($script:Build -lt 17134) { Result-Missing (L '{0} plans; Ultimate Performance needs Windows 10 version 1803 or later' $n) }
        else { Result-Ok (L '{0} plan(s) available' $n) }
    }
    Test-Check 'Optimize' 'Startup programs (17)' {
        $all = @(Get-StartupEntries -Fast)
        $on = @($all | Where-Object { $_.Enabled }).Count
        Result-Ok (L '{0} start with Windows, {1} switched off.' $on ($all.Count - $on))
    }
    Test-Check 'Optimize' 'Boot records (18)' {
        $n = @(Get-EventsSafe @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 50).Count
        if ($script:LastEventError) { return (Result-Missing (L 'Windows cannot read its boot records here: {0}' $script:LastEventError)) }
        $dps = Get-Service -Name 'DPS' -ErrorAction SilentlyContinue
        if ($n -gt 0) { Result-Ok (L '{0} boots recorded' $n) }
        elseif ($dps -and "$($dps.Status)" -ne 'Running') { Result-Info (L 'the Diagnostic Policy Service is off, so boots are not recorded') }
        else { Result-Info (L 'no boot recorded yet - restart once') }
    }

    Write-Section 'DIAGNOSE & REPAIR (19-26)'
    Test-Check 'Diagnose' 'Disk health data (19)' {
        $rel = @(Get-PhysicalDisk -ErrorAction Stop | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue)
        if (@($rel | Where-Object { $null -ne $_.Wear -or $_.Temperature -gt 0 }).Count -gt 0) { Result-Ok }
        else { Result-Info (L 'your drives do not report wear or temperature') }
    }
    Test-Check 'Diagnose' 'Battery data (19)' {
        if (-not (Test-IsLaptop)) { return (Result-Info (L 'no battery')) }
        $bh = Get-BatteryHealth
        if ($bh) {
            $text = L 'health {0} %' $bh.Reported
            if ($null -ne $bh.Cycles) { $text += ', ' + (L '{0} charge cycles' $bh.Cycles) }
            return (Result-Ok $text)
        }
        Result-Info (L 'the battery does not report its health')
    }
    Test-Check 'Diagnose' 'Event logs (20)' {
        [void](Get-WinEvent -LogName 'System' -MaxEvents 1 -ErrorAction Stop)
        Result-Ok
    }
    Test-Check 'Diagnose' 'Microsoft Defender (21)' {
        try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { return (Result-Info (L 'not active (another antivirus may be in charge)')) }
        Result-Ok (L 'real-time protection {0}' (Format-OnOff $mp.RealTimeProtectionEnabled))
    }
    Test-Check 'Diagnose' 'Firewall, Secure Boot and TPM (21)' {
        $parts = @()
        try {
            $on = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { [int]$_.Enabled -ne 0 }).Count
            $parts += (L 'firewall on for {0} of 3 networks' $on)
        } catch { $parts += (L 'firewall status unknown') }
        try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop; $parts += (L 'Secure Boot {0}' (Format-OnOff $sb)) } catch { $parts += (L 'legacy BIOS') }
        try { $tpm = Get-Tpm -ErrorAction Stop; $parts += $(if ($tpm.TpmPresent) { 'TPM' } else { L 'no TPM' }) } catch { }
        Result-Ok ($parts -join ', ')
    }
    Test-Check 'Diagnose' 'Signature checking (22)' {
        $sig = Get-AuthenticodeSignature -LiteralPath (Join-Path $env:WINDIR 'explorer.exe') -ErrorAction Stop
        if ("$($sig.Status)" -eq 'Valid') { Result-Ok } else { Result-Broken (L 'explorer.exe was reported as {0}' "$($sig.Status)") }
    }
    Test-Check 'Diagnose' 'Services and scheduled tasks (22)' {
        $m = Get-MissingCommands @('Get-ScheduledTask')
        if ($m.Count -gt 0) { return (Result-Broken (L 'missing: {0}' ($m -join ', '))) }
        $services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
        $tasks = @(Get-ScheduledTask -ErrorAction Stop).Count
        $ev = $services | Where-Object { $_.Name -eq 'EventLog' } | Select-Object -First 1
        if ($ev) {
            $exe = Resolve-ExePath $ev.PathName
            if (-not (Test-Path -LiteralPath $exe)) { return (Result-Broken (L 'could not read this command line: {0}' $ev.PathName)) }
        }
        Result-Ok (L '{0} services, {1} tasks' $services.Count $tasks)
    }
    Test-Check 'Diagnose' 'Device list (23)' {
        $all = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)
        $bad = @($all | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 -and $_.ConfigManagerErrorCode -ne 45 }).Count
        Result-Ok (L '{0} devices, {1} with problems' $all.Count $bad)
    }
    Test-Check 'Diagnose' 'Hardware rescan (23)' {
        if ($script:Build -ge 19041) { Result-Ok } else { Result-Missing (L 'needs Windows 10 version 2004 or later') }
    }
    Test-Check 'Diagnose' 'Drive error scan (24)' {
        $m = @(Get-MissingCommands @('Repair-Volume'))
        if (-not (Test-ExeExists 'fsutil.exe')) { $m += 'fsutil.exe' }
        if ($m.Count -gt 0) { Result-Broken (L 'missing: {0}' ($m -join ', ')) } else { Result-Ok }
    }
    Test-Check 'Diagnose' 'Memory test (25)' {
        if (Test-ExeExists 'mdsched.exe') { Result-Ok } else { Result-Missing (L 'not available on this Windows') }
    }
    Test-Check 'Diagnose' 'System repair tools (8, 26)' {
        $m = @(@('dism.exe', 'sfc.exe') | Where-Object { -not (Test-ExeExists $_) })
        if ($m.Count -gt 0) { Result-Broken (L 'missing: {0}' ($m -join ', ')) } else { Result-Ok }
    }

    Write-Section 'SPACE & UPDATES (27-28)'
    Test-Check 'Space' 'Space finder (27)' {
        $t = [System.Diagnostics.Stopwatch]::StartNew()
        $scan = Get-FolderSizes -Root (Join-Path $env:WINDIR 'Web')
        $t.Stop()
        Result-Ok (L '{0} measured in {1:N0} ms' (Format-Size $scan.Total[$scan.Root]) $t.ElapsedMilliseconds)
    }
    Test-Check 'Clean' 'Other app caches (7)' {
        $t = @(Get-DetectedAppCacheTargets)
        if ($t.Count -eq 0) { Result-Ok (L '(none)') } else { Result-Ok ($script:DetectedApps -join ', ') }
    }
    Test-Check 'Clean' 'Old driver versions (8)' {
        if (-not (Get-Command -Name 'Get-WindowsDriver' -ErrorAction SilentlyContinue)) { return (Result-Missing (L 'not available on this Windows')) }
        $old = @(Get-OldDriverPackages)
        if ($old.Count -eq 0) { Result-Ok '0' } else { Result-Ok (Get-OldDriversText $old) }
    }
    Test-Check 'Diagnose' 'Windows Update status (19)' {
        $wu = Get-WindowsUpdateStatus
        if ($wu.Disabled) { return (Result-Info (L 'turned off on this PC (its service is disabled)')) }
        Result-Ok (L 'last update installed {0}' (Format-DaysAgo $wu.LastInstall))
    }
    Test-Check 'Diagnose' 'PC health at a glance (19)' {
        $items = @(Get-HealthItems)
        if ($items.Count -lt 3) { return (Result-Broken (L 'only {0} checks could run' $items.Count)) }
        Result-Ok (($items | ForEach-Object { '{0} {1}' -f $_.Level, $_.Name }) -join ', ')
    }
    Test-Check 'Updates' 'App updates with winget (28)' {
        $exe = Get-WingetPath
        if (-not $exe) {
            if ($script:Build -lt 17763) { return (Result-Missing (L 'needs Windows 10 version 1809 or later')) }
            return (Result-Missing (L 'App Installer is not installed'))
        }
        $v = Get-WingetVersion
        if (-not $v) { Result-Broken (L 'winget did not answer') } else { Result-Ok "v$v" }
    }
    Test-Check 'Updates' 'Driver updates with Windows Update (28)' {
        $svc = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        if (-not $svc) { return (Result-Missing (L 'Windows Update service not found')) }
        if ("$($svc.StartType)" -eq 'Disabled') { return (Result-Info (L 'Windows Update is turned off on this PC (its service is disabled)')) }
        $session = New-UpdateSession
        [void]$session.CreateUpdateSearcher()
        Result-Ok
    }
    Test-Check 'Updates' 'Automatic updates (28)' {
        $task = Get-ScheduledTask -TaskName $script:UpdateTaskName -ErrorAction SilentlyContinue
        if (-not $task) { return (Result-Ok (L 'MANUAL')) }
        $copy = Join-Path $env:ProgramFiles 'YSO\YSO.ps1'
        if (-not (Test-Path -LiteralPath $copy)) { return (Result-Broken (L 'on, but its copy of YSO is missing - switch to manual and back (28 > 2)')) }
        $info = Get-ScheduledTaskInfo -TaskName $script:UpdateTaskName -ErrorAction SilentlyContinue
        $ran = ($info -and $info.LastRunTime -and $info.LastRunTime.Year -gt 2000)
        $text = if ($ran) { L 'last run {0}, result {1}' $info.LastRunTime.ToString('g') $info.LastTaskResult } else { L 'not run yet' }
        # result 1 = some updates could not be installed (shown in 28 > 6), not a problem with YSO
        if ($ran -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 1) { Result-Broken $text } else { Result-Ok ((Get-UpdateModeText (Get-UpdateMode)) + ', ' + $text) }
    }

    Write-Section 'ONE-CLICK'
    Test-Check 'One-click' 'System Restore (R, F)' {
        if ($script:IsServer -or -not (Get-Command -Name 'Checkpoint-Computer' -ErrorAction SilentlyContinue)) {
            return (Result-Missing (L 'not available on this Windows'))
        }
        $info = Get-RestorePointInfo
        if ($info.Points.Count -gt 0) { Result-Ok ((L '{0} restore points' $info.Points.Count) + ', ' + (Format-Size $info.Used)) }
        else { Result-Info (L 'none yet - R turns System Restore on if needed') }
    }
    Test-Check 'One-click' 'Weekly auto-clean (S)' {
        $m = Get-MissingCommands @('Register-ScheduledTask', 'New-ScheduledTaskTrigger', 'Get-ScheduledTaskInfo')
        if ($m.Count -gt 0) { return (Result-Broken (L 'missing: {0}' ($m -join ', '))) }
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if (-not $task) { return (Result-Ok (Format-OnOff $false)) }
        $copy = Join-Path $env:ProgramFiles 'YSO\YSO.ps1'
        if (-not (Test-Path -LiteralPath $copy)) { return (Result-Broken (L 'on, but its copy of YSO is missing - turn it off and on again (S)')) }
        $info = Get-ScheduledTaskInfo -TaskName $script:TaskName -ErrorAction SilentlyContinue
        $ran = ($info -and $info.LastRunTime -and $info.LastRunTime.Year -gt 2000)
        $text = if ($ran) { L 'last run {0}, result {1}' $info.LastRunTime.ToString('g') $info.LastTaskResult } else { L 'not run yet' }
        if ($PSCommandPath -and (Get-FileHash -LiteralPath $copy).Hash -ne (Get-FileHash -LiteralPath $PSCommandPath).Hash) {
            $text += ' - ' + (L 'uses an older copy: turn it off and on again (S)')
        }
        if ($ran -and $info.LastTaskResult -ne 0) { Result-Broken $text } else { Result-Ok ((Format-OnOff $true) + ', ' + $text) }
    }

    Write-Section 'BIG APP FOLDERS YSO DOES NOT CLEAN (20 MB or more)'
    $script:Uncovered = @()
    try { $script:Uncovered = @(Get-UncoveredFolders) }
    catch { Write-YsoError -Context 'self-test: coverage' -ErrorRecord $_ }
    if ($script:Uncovered.Count -eq 0) { Write-Ok 'None: every big folder in these apps is a cache YSO cleans.' }
    else {
        foreach ($u in $script:Uncovered) {
            Write-Host ('  {0,-9}{1,10}  ' -f $u.App, (Format-Size $u.Size)) -NoNewline
            Write-Host (Get-ShortPath (Get-FriendlyPath $u.Path) 92) -ForegroundColor Gray
        }
        Write-Info 'Usually normal (site data, extensions, settings, offline downloads). If a name looks like a cache, send the report (P).'
    }

    $analysis = @()
    Write-Section 'ANALYZE (nothing is deleted)'
    try { $analysis = @(Invoke-Analysis -PassThru) }
    catch {
        Write-YsoError -Context 'self-test: analyze' -ErrorRecord $_
        Add-Check 'Clean' 'Analyze (A)' 'BROKEN' $_.Exception.Message
    }

    $timer.Stop()
    $counts = @{}
    foreach ($st in @('OK', 'INFO', 'MISSING', 'BROKEN')) { $counts[$st] = @($script:Checks | Where-Object { $_.Status -eq $st }).Count }
    $script:LastSelfTestBroken = $counts['BROKEN']
    Write-Section 'SELF-TEST RESULT'
    $color = if ($counts['BROKEN'] -gt 0) { 'Red' } elseif ($counts['MISSING'] -gt 0) { 'Yellow' } else { 'Green' }
    Write-Host ('  ' + (L '{0} OK, {1} info, {2} missing, {3} broken' $counts['OK'] $counts['INFO'] $counts['MISSING'] $counts['BROKEN'])) -ForegroundColor $color
    if ($counts['BROKEN'] -gt 0) { Write-Bad 'Broken items are bugs in YSO or problems on this PC. Please send a report (P).' }
    if ($counts['MISSING'] -gt 0) { Write-Info 'Missing items are features this Windows does not have: those options are skipped or limited.' }
    if ($counts['BROKEN'] -eq 0 -and $counts['MISSING'] -eq 0) { Write-Ok 'Everything YSO needs works on this PC.' }
    $path = Save-SelfTestReport -Analysis $analysis -Elapsed $timer.Elapsed -Counts $counts
    if ($path) { Write-Info (L 'Report saved: {0}' $path) }
}

function Save-SelfTestReport {
    # Written in English on purpose, so reports from any PC read the same.
    param($Analysis, [timespan]$Elapsed, [hashtable]$Counts)
    try {
        New-Item -ItemType Directory -Path $script:ReportDir -Force | Out-Null
        $path = Join-Path $script:ReportDir ('selftest_{0:yyyyMMdd_HHmmss}.txt' -f (Get-Date))
        $culture = '?'
        try { $culture = (Get-UICulture).Name } catch { }
        $device = if ($script:IsServer) { 'server' } elseif (Test-IsLaptop) { 'laptop' } else { 'desktop' }
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('YSO self-test report')
        $lines.Add(('YSO        : {0}' -f $script:Version))
        $lines.Add(('Date       : {0:yyyy-MM-dd HH:mm}' -f (Get-Date)))
        $lines.Add(('Windows    : {0}' -f $script:OsText))
        $lines.Add(('PowerShell : {0} ({1})' -f $PSVersionTable.PSVersion, $ExecutionContext.SessionState.LanguageMode))
        $lines.Add(('Language   : {0} (interface {1})' -f $culture, $script:Lang))
        $lines.Add(('Device     : {0}, {1} user profile(s)' -f $device, $script:Profiles.Count))
        $lines.Add(('Duration   : {0:N0} s' -f $Elapsed.TotalSeconds))
        $lines.Add(('Result     : {0} OK, {1} INFO, {2} MISSING, {3} BROKEN' -f $Counts['OK'], $Counts['INFO'], $Counts['MISSING'], $Counts['BROKEN']))
        $lines.Add('')
        $fmt = '{0,-8} {1,-10} {2,-42} {3}'
        $lines.Add(($fmt -f 'STATUS', 'AREA', 'CHECK', 'DETAIL'))
        foreach ($x in $script:Checks) { $lines.Add(($fmt -f $x.Status, $x.Area, $x.Name, $x.Detail)) }
        $lines.Add('')
        $lines.Add('APP FOLDERS NOT CLEANED (20 MB or more)')
        foreach ($u in @($script:Uncovered)) { $lines.Add(('{0,-9} {1,14} bytes  {2}' -f $u.App, $u.Size, (Get-FriendlyPath $u.Path))) }
        if (@($script:Uncovered).Count -eq 0) { $lines.Add('(none)') }
        if (@($Analysis).Count -gt 0) {
            $lines.Add('')
            $lines.Add('ANALYZE (nothing deleted)')
            foreach ($a in $Analysis) {
                $files = if ($a.Files -lt 0) { '-' } else { "$($a.Files)" }
                $lines.Add(('{0,-32} {1,10} files {2,16} bytes' -f $a.Category, $files, $a.Bytes))
            }
        }
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Get-ChildItem -LiteralPath $script:ReportDir -Filter 'selftest_*.txt' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 | Remove-Item -Force -ErrorAction SilentlyContinue
        return $path
    } catch {
        Write-YsoError -Context 'self-test: save report' -ErrorRecord $_
        Write-Warn (L 'Could not save the report: {0}' $_.Exception.Message)
        return $null
    }
}

function Read-SharedText([string]$Path) {
    # Reads a file even while it is still open for writing (like the current session log).
    $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = New-Object System.IO.StreamReader($fs, $true)
        return $reader.ReadToEnd()
    } finally { $fs.Dispose() }
}

function New-ProblemReport {
    Write-Section 'REPORT A PROBLEM'
    Write-Info 'This makes one zip file you can send (email, WhatsApp, GitHub...). Nothing is sent automatically.'
    Write-Host ''
    $latest = Get-ChildItem -LiteralPath $script:ReportDir -Filter 'selftest_*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not ($latest -and $latest.LastWriteTime -gt (Get-Date).AddHours(-24))) {
        if (Confirm-Action 'Run the self-test first? (recommended, about a minute)' $true) {
            Invoke-SelfTest
            $latest = Get-ChildItem -LiteralPath $script:ReportDir -Filter 'selftest_*.txt' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Write-Host ''
        }
    }
    $what = "$(Read-Host ('  ' + (L 'What went wrong? (one line, optional - press Enter to skip)')))".Trim()

    $stamp = '{0:yyyyMMdd_HHmmss}' -f (Get-Date)
    $stage = Join-Path $env:TEMP ('YSO-report_' + $stamp)
    $files = @()
    if ($latest) { $files += $latest.FullName }
    foreach ($f in @($script:ErrorLogPath, ($script:ErrorLogPath -replace '\.log$', '.old.log'), $script:SettingsPath, $script:HistoryPath)) {
        if (Test-Path -LiteralPath $f) { $files += $f }
    }
    $files += @(Get-ChildItem -LiteralPath $script:LogDir -Filter 'yso_*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { $_.FullName })

    $zip = $null
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $readme = @(
            'YSO problem report',
            ('YSO {0} - {1:yyyy-MM-dd HH:mm}' -f $script:Version, (Get-Date)),
            ('Windows: ' + $script:OsText),
            ('Errors recorded this session: ' + $script:ErrorCount),
            ('What went wrong: ' + $(if ($what) { $what } else { '(not described)' })),
            '',
            'Files:'
        ) + @($files | ForEach-Object { '  ' + [System.IO.Path]::GetFileName($_) })
        Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Value (Protect-Text ($readme -join "`r`n")) -Encoding UTF8
        foreach ($f in $files) {
            try { $text = Read-SharedText $f } catch { continue }
            Set-Content -LiteralPath (Join-Path $stage ([System.IO.Path]::GetFileName($f))) -Value (Protect-Text $text) -Encoding UTF8
        }
        $desktop = [Environment]::GetFolderPath('Desktop')
        if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) {
            New-Item -ItemType Directory -Path $script:ReportDir -Force | Out-Null
            $desktop = $script:ReportDir
        }
        $zip = Join-Path $desktop ('YSO-report_' + $stamp + '.zip')
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Ok (L 'Report ready: {0}' $zip)
    Write-Info 'Removed from it: user names, the PC name, private IP addresses and the Wi-Fi name.'
    Write-Info 'It still shows which programs and settings this PC has - open it and check before sending.'
    if (Confirm-Action 'Show it in Explorer?' $true) { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $zip) }
}

# ==================================================================
#  Menu
# ==================================================================
function M([string]$Key, [string]$Text) { return , @($Key, $Text) }

function Invoke-MenuOption {
    # Runs one option the same way for the console menu and the window: an error is saved instead of
    # crashing, what was freed is summed up and kept in the history, and $script:LastRun tells the window
    # what happened. -Plan: F with the choices made in the window (nothing is asked).
    param([string]$Choice, [hashtable]$Plan)
    $script:Results.Clear()
    $freeBefore = Get-FreeBytes
    $status = 'done'
    try {
        switch ($Choice) {
            '1'  { Clear-TempFiles }
            '2'  { Clear-BrowserCaches }
            '3'  { Clear-SystemJunk }
            '4'  { Clear-UpdateCache }
            '5'  { Clear-YsoRecycleBin }
            '6'  { Clear-ShaderCaches }
            '7'  { Clear-DevAppCaches }
            '8'  { if (Confirm-Action 'Deep clean takes 10-30 minutes. Start?' $true) { Invoke-DeepClean } }
            '9'  { Remove-WindowsOld }
            '10' { Set-Hibernation }
            '11' { Test-NetworkQuality }
            '12' { Set-DnsServers }
            '13' { Clear-Dns }
            '14' { Reset-NetworkStack }
            '15' { Optimize-Drives }
            '16' { Set-YsoPowerPlan }
            '17' { Show-StartupApps }
            '18' { Show-BootTimes }
            '19' { Show-HealthReport }
            '20' { Show-RecentProblems }
            '21' { Show-SecurityCheck }
            '22' { Show-Audit }
            '23' { Show-DriverProblems }
            '24' { Test-Drives }
            '25' { Start-MemoryTest }
            '26' { Invoke-SystemRepair }
            '27' { Show-SpaceFinder }
            '28' { Show-UpdatesMenu }
            'A'  { Invoke-Analysis }
            'F'  { Invoke-FullMaintenance -Plan $Plan }
            'R'  { Show-RestorePoints }
            'S'  { Set-AutoClean }
            'H'  { Show-History }
            'T'  { Invoke-SelfTest }
            'P'  { New-ProblemReport }
            'O'  { Show-Settings }
            default { $status = 'unknown' }
        }
    } catch {
        if (Test-StopError $_) {
            $status = 'stopped'
            Write-Host ''
            Write-Warn 'Stopped at your request. What was already cleaned stays cleaned.'
        } else {
            $status = 'failed'
            Write-YsoError -Context ('option ' + $Choice) -ErrorRecord $_
            Show-OptionError $_
        }
    }
    $results = @($script:Results.ToArray())
    if ($results.Count -gt 0) {
        Show-Summary -FreeBefore $freeBefore
        Save-History (N 'Manual')
    }
    $script:LastRun = [pscustomobject]@{
        Choice = $Choice; Status = $status; Results = $results; DryRun = [bool]$script:DryRun
        FreeBefore = $freeBefore; FreeAfter = $(if ($results.Count -gt 0) { Get-FreeBytes } else { $freeBefore })
    }
}

function Write-MenuCell($Cell, [int]$Width) {
    if ($null -eq $Cell -or -not $Cell[1]) {
        if ($Width -gt 0) { Write-Host (' ' * $Width) -NoNewline }
        return
    }
    if ($Cell[0] -eq '#') {
        $t = '  [ ' + (L $Cell[1]) + ' ]'
        if ($Width -gt 0) { $t = $t.PadRight($Width) }
        Write-Host $t -NoNewline -ForegroundColor Cyan
        return
    }
    $k = '   {0,-4}' -f $Cell[0]
    $t = L $Cell[1]
    if ($Width -gt 0) {
        $max = $Width - $k.Length - 1
        if ($t.Length -gt $max) { $t = $t.Substring(0, $max - 3) + '...' }
        $t = $t.PadRight($Width - $k.Length)
    }
    Write-Host $k -NoNewline -ForegroundColor Green
    Write-Host $t -NoNewline
}

function Write-MenuGrid([object[]]$Cells, [int]$Columns, [int]$CellWidth) {
    for ($i = 0; $i -lt $Cells.Count; $i += $Columns) {
        for ($j = 0; $j -lt $Columns -and ($i + $j) -lt $Cells.Count; $j++) { Write-MenuCell $Cells[$i + $j] $CellWidth }
        Write-Host ''
    }
}

function Show-SimpleMenu {
    # The essentials and the health of the PC. M shows every option.
    param([int]$Width = 0)
    Clear-Host
    $bar = '=' * 76
    $updState = switch (Get-UpdateMode) { 'auto' { L 'AUTO' } 'notify' { L 'NOTIFY' } default { L 'MANUAL' } }
    Write-Host ''
    Write-Host "  $bar" -ForegroundColor DarkGreen
    Write-Host '        Y S O   -   Y O U R   S Y S T E M   O P T I M I Z E R' -ForegroundColor Green
    Write-Host ('        v{0}   |   {1}' -f $script:Version, (L 'safe  -  measured  -  logged')) -ForegroundColor DarkGreen
    Write-Host "  $bar" -ForegroundColor DarkGreen
    if ($script:DryRun) { Write-Host ('   ' + (L 'ANALYZE-ONLY MODE: nothing will be deleted.')) -ForegroundColor Yellow }
    if ($script:ErrorCount -gt 0) { Write-Host ('   ' + (L '{0} problem(s) recorded - use P to send a report.' $script:ErrorCount)) -ForegroundColor Yellow }
    Write-Host ''
    Write-Host ('  [ ' + (L 'YOUR PC') + ' ]') -ForegroundColor Cyan
    if (-not $script:HealthCache) { Write-Host ('      ' + (L 'Checking your PC...')) -ForegroundColor DarkGray }
    Show-HealthDashboard @(Get-HealthItemsCached)
    Write-Host ''
    Write-Host ('  [ ' + (L 'WHAT DO YOU WANT TO DO?') + ' ]') -ForegroundColor Cyan
    foreach ($c in @(
            (M 'A'  'Analyze: what can be freed (deletes nothing)'),
            (M 'F'  'Clean everything (full maintenance)'),
            (M '28' ((L 'Updates: apps & drivers') + " [$updState]")),
            (M '17' 'Startup programs'),
            (M '19' 'PC health report (details)'),
            (M 'R'  'Restore points'))) {
        Write-MenuCell $c 0; Write-Host ''
    }
    Write-Host ''
    Write-MenuGrid -Cells @((M 'M' 'All options'), (M 'T' 'Self-test'), (M 'O' 'Settings / Langue'),
                            (M 'P' 'Report a problem'), (M 'H' 'Cleanup history'), (M 'Q' 'Quit')) -Columns 2 -CellWidth 38
    Write-Host "  $bar" -ForegroundColor DarkGreen
}

function Show-Menu {
    param([int]$Width = 0, [string]$Mode = '')   # Width 0 = the console width; Mode '' = from Settings
    if (-not $Mode) { $Mode = $script:Settings.MenuMode }
    if ($Mode -eq 'simple') { Show-SimpleMenu -Width $Width; return }
    Clear-Host
    if ($Width -le 0) {
        $Width = 120
        try { $w = $Host.UI.RawUI.WindowSize.Width; if ($w -gt 0) { $Width = $w } } catch { }
    }
    $wide = ($Width -ge 116)
    $bar  = '=' * $(if ($wide) { 110 } else { 72 })
    $autoState = if (Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue) { L 'ON' } else { L 'OFF' }
    $updState = switch (Get-UpdateMode) { 'auto' { L 'AUTO' } 'notify' { L 'NOTIFY' } default { L 'MANUAL' } }

    Write-Host ''
    Write-Host "  $bar" -ForegroundColor DarkGreen
    Write-Host '        Y S O   -   Y O U R   S Y S T E M   O P T I M I Z E R' -ForegroundColor Green
    Write-Host ('        v{0}   |   {1}' -f $script:Version, (L 'safe  -  measured  -  logged')) -ForegroundColor DarkGreen
    Write-Host "  $bar" -ForegroundColor DarkGreen
    $status = '   ' + (L 'Free space: {0}   |   Uptime: {1}   |   User profiles: {2}' (Get-FreeSpaceText) (Get-UptimeText) $script:Profiles.Count)
    $cut = $status.IndexOf('|')
    if ($status.Length -gt ($Width - 2) -and $cut -gt 0) {
        # Narrow window: free space on its own line, the rest below.
        Write-Host $status.Substring(0, $cut).TrimEnd() -ForegroundColor Gray
        Write-Host ('   ' + $status.Substring($cut + 1).Trim()) -ForegroundColor Gray
    } else {
        Write-Host $status -ForegroundColor Gray
    }
    if ($script:DryRun) { Write-Host ('   ' + (L 'ANALYZE-ONLY MODE: nothing will be deleted.')) -ForegroundColor Yellow }
    if (-not $script:IsServer -and $script:Build -lt 19041) {
        Write-Host ('   ' + (L 'Older Windows: some options are limited - run T to see which.')) -ForegroundColor Yellow
    }
    if ($script:ErrorCount -gt 0) {
        Write-Host ('   ' + (L '{0} problem(s) recorded - use P to send a report.' $script:ErrorCount)) -ForegroundColor Yellow
    }
    Write-Host ''

    $left = @(
        (M '#'  'CLEAN'),
        (M '1'  'Temporary files'),
        (M '2'  'Browser caches'),
        (M '3'  'System junk (reports, dumps, old logs)'),
        (M '4'  'Windows Update cache'),
        (M '5'  'Recycle Bin'),
        (M '6'  'GPU shader caches'),
        (M '7'  'Developer & app caches'),
        (M '8'  'Deep clean (Disk Cleanup)'),
        (M '9'  'Old Windows version (Windows.old)'),
        (M '10' 'Hibernation file'),
        (M ''   ''),
        (M '#'  'NETWORK'),
        (M '11' 'Network check (speed, DNS, Wi-Fi)'),
        (M '12' 'Change DNS servers'),
        (M '13' 'Flush DNS cache'),
        (M '14' 'Full network reset')
    )
    $right = @(
        (M '#'  'OPTIMIZE'),
        (M '15' 'Optimize drives (TRIM / defrag)'),
        (M '16' 'Power plan'),
        (M '17' 'Startup programs'),
        (M '18' 'Boot time analyzer'),
        (M ''   ''),
        (M '#'  'DIAGNOSE & REPAIR'),
        (M '19' 'System health report'),
        (M '20' 'Crashes & errors'),
        (M '21' 'Security check & Defender scan'),
        (M '22' 'What runs automatically? (audit)'),
        (M '23' 'Driver problems'),
        (M '24' 'Check drives for errors'),
        (M '25' 'Memory test'),
        (M '26' 'Repair Windows files (DISM + SFC)'),
        (M ''   ''),
        (M '#'  'SPACE & UPDATES'),
        (M '27' 'Space finder (what fills my disk?)'),
        (M '28' ((L 'Updates: apps & drivers') + " [$updState]"))
    )
    $bottom = @(
        (M 'A' 'Analyze (deletes nothing)'),
        (M 'F' 'Full maintenance'),
        (M 'R' 'Restore points'),
        (M 'S' ((L 'Weekly auto-clean') + " [$autoState]")),
        (M 'H' 'Cleanup history'),
        (M 'T' 'Self-test (check everything)'),
        (M 'P' 'Report a problem'),
        (M 'O' 'Settings / Langue'),
        (M 'L' 'Logs folder'),
        (M 'M' 'Simple menu'),
        (M 'Q' 'Quit')
    )
    if ($wide) {
        $rows = [math]::Max($left.Count, $right.Count)
        for ($i = 0; $i -lt $rows; $i++) {
            $lc = if ($i -lt $left.Count) { $left[$i] } else { $null }
            $rc = if ($i -lt $right.Count) { $right[$i] } else { $null }
            Write-MenuCell $lc 56
            Write-MenuCell $rc 56
            Write-Host ''
        }
        Write-Host ''
        Write-Host ('  [ ' + (L 'ONE-CLICK') + ' ]') -ForegroundColor Cyan
        Write-MenuGrid -Cells $bottom -Columns 3 -CellWidth 37
    } else {
        foreach ($c in ($left + $right)) { Write-MenuCell $c 0; Write-Host '' }
        Write-Host ''
        Write-Host ('  [ ' + (L 'ONE-CLICK') + ' ]') -ForegroundColor Cyan
        foreach ($c in $bottom) { Write-MenuCell $c 0; Write-Host '' }
    }
    Write-Host "  $bar" -ForegroundColor DarkGreen
}

# ==================================================================
#  Window (WPF)
#  The engine above runs in a second PowerShell (a runspace), so the window stays usable.
#  What it writes (Write-Host), asks (Read-Host, Confirm-Action) and measures (progress)
#  comes back through a shared queue that the window reads 15 times a second: every option
#  of the console works in the window this way, and the main ones have their own page.
# ==================================================================
function Get-YsoXaml {
    # The window's layout. A text between double square brackets is replaced by its translation.
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="YSO - Your System Optimizer" Width="1180" Height="760" MinWidth="960" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#0F1412" Foreground="#E9EFEC"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="44" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <SolidColorBrush x:Key="Bg" Color="#0F1412"/>
    <SolidColorBrush x:Key="Side" Color="#0A0E0C"/>
    <SolidColorBrush x:Key="Card" Color="#161D1A"/>
    <SolidColorBrush x:Key="Card2" Color="#1D2622"/>
    <SolidColorBrush x:Key="Hover" Color="#25302B"/>
    <SolidColorBrush x:Key="Line" Color="#2C3833"/>
    <SolidColorBrush x:Key="Text" Color="#E9EFEC"/>
    <SolidColorBrush x:Key="Text2" Color="#A3AFA9"/>
    <SolidColorBrush x:Key="Text3" Color="#85918B"/>
    <SolidColorBrush x:Key="Accent" Color="#4CAF7D"/>
    <SolidColorBrush x:Key="AccentHover" Color="#5DBE8C"/>
    <SolidColorBrush x:Key="AccentSoft" Color="#16291F"/>
    <SolidColorBrush x:Key="AccentLine" Color="#2C5640"/>
    <SolidColorBrush x:Key="OnAccent" Color="#06160E"/>
    <SolidColorBrush x:Key="Good" Color="#4CAF7D"/>
    <SolidColorBrush x:Key="GoodSoft" Color="#16291F"/>
    <SolidColorBrush x:Key="Warn" Color="#D9A441"/>
    <SolidColorBrush x:Key="WarnSoft" Color="#2E2614"/>
    <SolidColorBrush x:Key="Bad" Color="#E07070"/>
    <SolidColorBrush x:Key="BadSoft" Color="#331C1C"/>
    <SolidColorBrush x:Key="Info" Color="#7AA7D9"/>
    <SolidColorBrush x:Key="InfoSoft" Color="#1A2533"/>

    <Style x:Key="Icon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="TextOptions.TextFormattingMode" Value="Ideal"/>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock">
      <Setter Property="FontSize" Value="28"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="TextOptions.TextFormattingMode" Value="Ideal"/>
    </Style>
    <Style x:Key="H2" TargetType="TextBlock">
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="Foreground" Value="{StaticResource Text2}"/>
      <Setter Property="Margin" Value="0,6,0,0"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{StaticResource Card2}"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="Padding" Value="10,6"/>
    </Style>

    <Style TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Background" Value="{StaticResource Card2}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="Padding" Value="18,9"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.8"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Text}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource Hover}"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="AccentBtn" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="{StaticResource OnAccent}"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource AccentHover}"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Link" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Accent}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="3" Padding="6,4"><ContentPresenter VerticalAlignment="Center"/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{StaticResource AccentHover}"/></Trigger>
        <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Chrome" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text2}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="Transparent" BorderThickness="1"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource Hover}"/><Setter Property="Foreground" Value="{StaticResource Text}"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="ChromeClose" TargetType="Button" BasedOn="{StaticResource Chrome}">
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#C42B1C"/><Setter Property="Foreground" Value="White"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Tile" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="20,18">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TileAccent" TargetType="Button" BasedOn="{StaticResource Tile}">
      <Setter Property="Background" Value="{StaticResource AccentSoft}"/>
      <Setter Property="BorderBrush" Value="{StaticResource AccentLine}"/>
    </Style>
    <Style x:Key="ToolBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Width" Value="338"/>
      <Setter Property="Margin" Value="0,0,12,12"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{StaticResource Card}" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="4" Padding="12,11">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/><Setter TargetName="Bd" Property="Background" Value="{StaticResource Card2}"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="OptionBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="MaxWidth" Value="760"/>
      <Setter Property="MinWidth" Value="380"/>
      <Setter Property="HorizontalAlignment" Value="Left"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{StaticResource Card}" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="4" Padding="8,7">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/><Setter TargetName="Bd" Property="Background" Value="{StaticResource Card2}"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/><Setter Property="Cursor" Value="Arrow"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Text2}"/>
      <Setter Property="Margin" Value="12,1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="GroupName" Value="Nav"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="4" Height="40" Padding="12,0">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{StaticResource Card}"/><Setter Property="Foreground" Value="{StaticResource Text}"/></Trigger>
              <Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="Background" Value="{StaticResource Card2}"/><Setter Property="Foreground" Value="{StaticResource Text}"/><Setter Property="FontWeight" Value="SemiBold"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Background="Transparent">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Border x:Name="Box" Width="20" Height="20" CornerRadius="2" BorderThickness="1.5" BorderBrush="{StaticResource Text3}" Background="Transparent" VerticalAlignment="Center">
                <TextBlock x:Name="Tick" Text="&#xE73E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="{StaticResource OnAccent}"
                           HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Grid.Column="1" Margin="14,0,0,0" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Text}"/><Setter TargetName="Box" Property="BorderThickness" Value="2"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="6"/>
      <Setter Property="Foreground" Value="{StaticResource Accent}"/>
      <Setter Property="Background" Value="{StaticResource Card2}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid x:Name="TemplateRoot" ClipToBounds="True">
              <Border Background="{TemplateBinding Background}" CornerRadius="1"/>
              <Border x:Name="PART_Track"/>
              <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="1" HorizontalAlignment="Left"/>
              <Border x:Name="Runner" Width="140" Background="{TemplateBinding Foreground}" CornerRadius="1" HorizontalAlignment="Left" Visibility="Collapsed">
                <Border.RenderTransform><TranslateTransform X="-140"/></Border.RenderTransform>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsIndeterminate" Value="True">
                <Setter TargetName="PART_Indicator" Property="Visibility" Value="Collapsed"/>
                <Setter TargetName="Runner" Property="Visibility" Value="Visible"/>
                <Trigger.EnterActions>
                  <BeginStoryboard x:Name="RunnerMove">
                    <Storyboard RepeatBehavior="Forever">
                      <DoubleAnimation Storyboard.TargetName="Runner" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)"
                                       From="-140" To="1000" Duration="0:0:1.8"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.EnterActions>
                <Trigger.ExitActions><StopStoryboard BeginStoryboardName="RunnerMove"/></Trigger.ExitActions>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Border Background="#33413B" CornerRadius="2" Margin="2"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="MinWidth" Value="0"/>
          <Setter Property="Height" Value="10"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Track x:Name="PART_Track">
                  <Track.Thumb>
                    <Thumb>
                      <Thumb.Template>
                        <ControlTemplate TargetType="Thumb"><Border Background="#33413B" CornerRadius="2" Margin="2"/></ControlTemplate>
                      </Thumb.Template>
                    </Thumb>
                  </Track.Thumb>
                </Track>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource Bg}"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="CaretBrush" Value="{StaticResource Text}"/>
      <Setter Property="SelectionBrush" Value="{StaticResource Accent}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3">
              <ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border x:Name="RootBorder" Background="{StaticResource Bg}">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="252"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Sidebar -->
      <Border Background="{StaticResource Side}" BorderBrush="{StaticResource Line}" BorderThickness="0,0,1,0">
        <DockPanel LastChildFill="True">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="22,20,0,26">
            <Image x:Name="Logo" Width="36" Height="36" RenderOptions.BitmapScalingMode="HighQuality" AutomationProperties.Name="YSO"/>
            <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
              <TextBlock Text="YSO" FontSize="19" FontWeight="Bold" Foreground="{StaticResource Text}"/>
              <TextBlock Text="Your System Optimizer" FontSize="11" Foreground="{StaticResource Text3}"/>
            </StackPanel>
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Margin="0,0,0,16">
            <Button x:Name="UpdateBtn" Style="{StaticResource AccentBtn}" Margin="12,0,12,12" Padding="12,8" Visibility="Collapsed" HorizontalContentAlignment="Left">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE896;" Style="{StaticResource Icon}" FontSize="14" Margin="0,0,10,0"/>
                <TextBlock x:Name="UpdateText" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
            </Button>
            <RadioButton x:Name="NavSettings" Style="{StaticResource Nav}">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE713;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[Settings]]"/></StackPanel>
            </RadioButton>
            <TextBlock x:Name="VersionText" Margin="26,12,0,0" FontSize="11" Foreground="{StaticResource Text3}"/>
          </StackPanel>
          <StackPanel>
            <RadioButton x:Name="NavHome" Style="{StaticResource Nav}" IsChecked="True">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE80F;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[Home]]"/></StackPanel>
            </RadioButton>
            <RadioButton x:Name="NavClean" Style="{StaticResource Nav}">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE74D;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[Clean]]"/></StackPanel>
            </RadioButton>
            <RadioButton x:Name="NavUpdates" Style="{StaticResource Nav}">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE895;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[Updates]]"/></StackPanel>
            </RadioButton>
            <RadioButton x:Name="NavStartup" Style="{StaticResource Nav}">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE7E8;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[Startup programs]]"/></StackPanel>
            </RadioButton>
            <RadioButton x:Name="NavHealth" Style="{StaticResource Nav}">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE95E;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[Health report]]"/></StackPanel>
            </RadioButton>
            <RadioButton x:Name="NavRestore" Style="{StaticResource Nav}">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE777;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[Restore points]]"/></StackPanel>
            </RadioButton>
            <RadioButton x:Name="NavTools" Style="{StaticResource Nav}">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE90F;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[All tools]]"/></StackPanel>
            </RadioButton>
            <RadioButton x:Name="NavHistory" Style="{StaticResource Nav}">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE81C;" Style="{StaticResource Icon}" FontSize="16" Width="30" HorizontalAlignment="Left"/><TextBlock Text="[[History]]"/></StackPanel>
            </RadioButton>
          </StackPanel>
        </DockPanel>
      </Border>

      <!-- Main area -->
      <Grid Grid.Column="1">
        <Grid.RowDefinitions>
          <RowDefinition Height="44"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel Orientation="Horizontal" Margin="40,10,0,0" VerticalAlignment="Top" HorizontalAlignment="Left">
          <Button x:Name="BusyPill" Visibility="Collapsed" WindowChrome.IsHitTestVisibleInChrome="True" Padding="12,4" Background="{StaticResource AccentSoft}" BorderBrush="{StaticResource AccentLine}">
            <StackPanel Orientation="Horizontal">
              <Ellipse Width="8" Height="8" Fill="{StaticResource Accent}" VerticalAlignment="Center"/>
              <TextBlock x:Name="BusyText" Margin="8,0,0,0" FontWeight="Normal" Foreground="{StaticResource Text}" MaxWidth="460" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
          </Button>
          <Border x:Name="ModeBadge" Visibility="Collapsed" Margin="10,0,0,0" Padding="10,4" CornerRadius="3" Background="{StaticResource WarnSoft}">
            <TextBlock Text="[[ANALYZE-ONLY MODE: nothing will be deleted.]]" Foreground="{StaticResource Warn}" FontSize="12"/>
          </Border>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
          <Button x:Name="BtnMin" Style="{StaticResource Chrome}" Content="&#xE921;" AutomationProperties.Name="[[Minimize]]" ToolTip="[[Minimize]]"/>
          <Button x:Name="BtnMax" Style="{StaticResource Chrome}" Content="&#xE922;" AutomationProperties.Name="[[Maximize]]" ToolTip="[[Maximize]]"/>
          <Button x:Name="BtnClose" Style="{StaticResource ChromeClose}" Content="&#xE8BB;" AutomationProperties.Name="[[Close]]" ToolTip="[[Close]]"/>
        </StackPanel>

        <Grid Grid.Row="1">
          <!-- HOME -->
          <ScrollViewer x:Name="PageHome" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel Margin="40,6,40,34">
              <TextBlock Text="[[Your PC]]" Style="{StaticResource H1}"/>
              <TextBlock x:Name="HomeSub" Style="{StaticResource Sub}" Text="[[Checking your PC...]]"/>
              <Grid Margin="0,26,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="16"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Button x:Name="HomeAnalyze" Style="{StaticResource Tile}">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Border Width="48" Height="48" CornerRadius="4" Background="{StaticResource Card2}">
                      <TextBlock Text="&#xE721;" Style="{StaticResource Icon}" FontSize="22" Foreground="{StaticResource Accent}"/>
                    </Border>
                    <StackPanel Grid.Column="1" Margin="16,0,0,0" VerticalAlignment="Center">
                      <TextBlock Text="[[Analyze]]" FontSize="17" FontWeight="SemiBold"/>
                      <TextBlock Text="[[See what can be freed. Deletes nothing.]]" Foreground="{StaticResource Text2}" Margin="0,3,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                  </Grid>
                </Button>
                <Button x:Name="HomeClean" Grid.Column="2" Style="{StaticResource TileAccent}">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Border Width="48" Height="48" CornerRadius="4" Background="{StaticResource Accent}">
                      <TextBlock Text="&#xE74D;" Style="{StaticResource Icon}" FontSize="22" Foreground="{StaticResource OnAccent}"/>
                    </Border>
                    <StackPanel Grid.Column="1" Margin="16,0,0,0" VerticalAlignment="Center">
                      <TextBlock Text="[[Clean everything]]" FontSize="17" FontWeight="SemiBold"/>
                      <TextBlock Text="[[Full maintenance, with a restore point first.]]" Foreground="{StaticResource Text2}" Margin="0,3,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                  </Grid>
                </Button>
              </Grid>
              <Grid Margin="0,34,0,12">
                <TextBlock Text="[[PC health]]" Style="{StaticResource H2}" VerticalAlignment="Center"/>
                <Button x:Name="HomeRefresh" Style="{StaticResource Link}" HorizontalAlignment="Right" Content="[[Check again]]"/>
              </Grid>
              <UniformGrid x:Name="HealthGrid" Columns="2" Margin="0,0,-12,0"/>
            </StackPanel>
          </ScrollViewer>

          <!-- CLEAN -->
          <Grid x:Name="PageClean" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <StackPanel Margin="40,6,40,16">
              <TextBlock Text="[[Clean]]" Style="{StaticResource H1}"/>
              <TextBlock Text="[[Choose what to clean. Analyze first to see how much each part frees - it deletes nothing.]]" Style="{StaticResource Sub}"/>
              <Border x:Name="CleanWarn" Visibility="Collapsed" Margin="0,14,0,0" Padding="14,10" CornerRadius="4" Background="{StaticResource WarnSoft}">
                <TextBlock x:Name="CleanWarnText" TextWrapping="Wrap" Foreground="{StaticResource Warn}"/>
              </Border>
            </StackPanel>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
              <StackPanel Margin="40,0,40,18">
                <StackPanel x:Name="CleanList"/>
                <TextBlock Text="[[Options]]" Style="{StaticResource H2}" Margin="0,18,0,10"/>
                <StackPanel x:Name="CleanOptions"/>
              </StackPanel>
            </ScrollViewer>
            <Border Grid.Row="2" Background="{StaticResource Side}" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0" Padding="40,14">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel VerticalAlignment="Center">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock x:Name="CleanTotal" Text="-" FontSize="22" FontWeight="SemiBold" Foreground="{StaticResource Accent}"/>
                    <TextBlock x:Name="CleanTotalLabel" Text="[[Analyze to see how much you can free]]" Margin="10,0,0,3" VerticalAlignment="Bottom" Foreground="{StaticResource Text2}"/>
                  </StackPanel>
                  <ProgressBar x:Name="CleanBar" Margin="0,8,0,0" Visibility="Collapsed" Maximum="100"/>
                  <TextBlock x:Name="CleanStatus" Margin="0,6,0,0" Foreground="{StaticResource Text3}" FontSize="12" Visibility="Collapsed" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="20,0,0,0">
                  <Button x:Name="CleanDetails" Style="{StaticResource Link}" Content="[[Details]]" Margin="0,0,12,0" Visibility="Collapsed"/>
                  <Button x:Name="CleanAnalyze" Content="[[Analyze]]" Margin="0,0,10,0"/>
                  <Button x:Name="CleanRun" Style="{StaticResource AccentBtn}" Content="[[Clean selected]]"/>
                </StackPanel>
              </Grid>
            </Border>
          </Grid>

          <!-- RUN: any option, with its text, questions and progress -->
          <Grid x:Name="PageRun" Visibility="Collapsed" Margin="40,6,40,20">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <StackPanel>
              <TextBlock x:Name="RunTitle" Style="{StaticResource H1}" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="RunState" Style="{StaticResource Sub}"/>
            </StackPanel>
            <StackPanel x:Name="RunProgress" Grid.Row="1" Margin="0,16,0,0">
              <TextBlock x:Name="RunStep" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
              <ProgressBar x:Name="RunBar0" Margin="0,8,0,0" Maximum="100"/>
              <TextBlock x:Name="RunStatus" Margin="0,10,0,0" Foreground="{StaticResource Text3}" FontSize="12" TextTrimming="CharacterEllipsis"/>
              <ProgressBar x:Name="RunBar1" Margin="0,6,0,0" Height="4" Maximum="100"/>
            </StackPanel>
            <Border x:Name="RunResult" Grid.Row="2" Visibility="Collapsed" Margin="0,16,0,0" Padding="20,16" CornerRadius="4" Background="{StaticResource AccentSoft}" BorderBrush="{StaticResource AccentLine}" BorderThickness="1">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="RunResultIcon" Text="&#xE73E;" Style="{StaticResource Icon}" FontSize="26" Foreground="{StaticResource Accent}"/>
                <StackPanel Grid.Column="1" Margin="18,0,0,0">
                  <TextBlock x:Name="RunResultBig" FontSize="22" FontWeight="SemiBold"/>
                  <TextBlock x:Name="RunResultText" Foreground="{StaticResource Text2}" Margin="0,4,0,0" TextWrapping="Wrap"/>
                </StackPanel>
              </Grid>
            </Border>
            <Border Grid.Row="3" Margin="0,16,0,0" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,1">
              <ScrollViewer x:Name="RunScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
                <StackPanel x:Name="RunDoc" Margin="0,8,14,12"/>
              </ScrollViewer>
            </Border>
            <Border x:Name="RunAsk" Grid.Row="4" Visibility="Collapsed" Margin="0,12,0,0" Padding="16,12" CornerRadius="4" Background="{StaticResource Card2}" BorderBrush="{StaticResource Accent}" BorderThickness="1">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock x:Name="RunAskText" TextWrapping="Wrap" FontWeight="SemiBold"/>
                  <TextBox x:Name="RunAskBox" Margin="0,8,0,0" FontSize="13" AutomationProperties.Name="[[Your answer]]"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Bottom" Margin="14,0,0,0">
                  <Button x:Name="RunAskNo" Content="[[No]]" Margin="0,0,8,0"/>
                  <Button x:Name="RunAskYes" Content="[[Yes]]"/>
                  <Button x:Name="RunAskOk" Style="{StaticResource AccentBtn}" Content="[[OK]]"/>
                  <Button x:Name="RunAskContinue" Style="{StaticResource AccentBtn}" Content="[[Continue]]"/>
                </StackPanel>
              </Grid>
            </Border>
            <Grid Grid.Row="5" Margin="0,14,0,0">
              <StackPanel Orientation="Horizontal" Margin="0,0,220,0" VerticalAlignment="Center">
                <Button x:Name="RunCopy" Style="{StaticResource Link}" Content="[[Copy the text]]" Margin="-6,0,12,0"/>
                <TextBlock x:Name="RunHint" VerticalAlignment="Center" Foreground="{StaticResource Text3}" FontSize="12" TextWrapping="Wrap"/>
              </StackPanel>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="RunStop" Content="[[Stop]]" Margin="0,0,10,0"/>
                <Button x:Name="RunBack" Content="[[Back]]"/>
              </StackPanel>
            </Grid>
          </Grid>

          <!-- ALL TOOLS -->
          <ScrollViewer x:Name="PageTools" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel Margin="40,6,40,34">
              <TextBlock Text="[[All tools]]" Style="{StaticResource H1}"/>
              <TextBlock Text="[[Every option of YSO. Each one explains what it does and asks before changing anything.]]" Style="{StaticResource Sub}"/>
              <StackPanel x:Name="ToolsPanel" Margin="0,12,0,0"/>
            </StackPanel>
          </ScrollViewer>
        </Grid>
      </Grid>

      <!-- Dialog -->
      <Grid x:Name="Overlay" Grid.ColumnSpan="2" Background="#B0000000" Visibility="Collapsed">
        <Border Background="{StaticResource Card}" CornerRadius="6" BorderBrush="{StaticResource Line}" BorderThickness="1" Width="540" Padding="28,26" HorizontalAlignment="Center" VerticalAlignment="Center">
          <StackPanel>
            <TextBlock x:Name="DlgTitle" FontSize="19" FontWeight="SemiBold" TextWrapping="Wrap"/>
            <TextBlock x:Name="DlgText" Margin="0,12,0,0" Foreground="{StaticResource Text2}" TextWrapping="Wrap" LineHeight="21"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,26,0,0">
              <Button x:Name="DlgNo" Margin="0,0,10,0"/>
              <Button x:Name="DlgYes" Style="{StaticResource AccentBtn}"/>
            </StackPanel>
          </StackPanel>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
}

# ------------------------------------------------------------------
#  The engine's side: runs in the window's second PowerShell
# ------------------------------------------------------------------
function New-GuiShared {
    # What the window and its second PowerShell share. Thread-safe on both sides.
    return [hashtable]::Synchronized(@{
        Queue    = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Answers  = New-Object 'System.Collections.Concurrent.BlockingCollection[object]'
        Progress = [hashtable]::Synchronized(@{})
        Stop     = $false
    })
}

function ConvertTo-HostText($Object, $Separator = ' ') {
    # What Write-Host would print for these arguments.
    if ($null -eq $Object) { return '' }
    $parts = foreach ($o in @($Object)) {
        if ($o -is [System.Collections.IEnumerable] -and $o -isnot [string]) { (@($o) | ForEach-Object { "$_" }) -join "$Separator" }
        else { "$o" }
    }
    return (@($parts) -join "$Separator")
}

function Send-GuiText([string]$Text, [string]$Color, [bool]$NoNewline) {
    $script:GuiShared.Queue.Enqueue([object[]]@('text', $Text, $Color, $NoNewline))
}

function Request-GuiAnswer([string]$Kind, [string]$Prompt, $Default = $null) {
    # Asks the window (Kind: text, yesno, continue) and waits for the answer. Stop ends the wait.
    $s = $script:GuiShared
    $a = $null
    while ($s.Answers.TryTake([ref]$a)) { }   # an answer left over from before is never used
    $s.Queue.Enqueue([object[]]@('ask', $Kind, $Prompt, $Default))
    while (-not $s.Answers.TryTake([ref]$a, 250)) { Assert-NotStopped }
    return $a
}

function Enable-GuiAdapters($Shared) {
    # Only in the window's second PowerShell: what YSO writes, asks and measures goes to the window
    # instead of a console. The console versions are untouched everywhere else.
    $script:GuiShared  = $Shared
    $script:StopSignal = $Shared
    $script:ProgressHandler = {
        param($Activity, $Status, $Percent, $Completed, $Id)
        if ($Completed) { $script:GuiShared.Progress.Remove($Id) }
        else { $script:GuiShared.Progress[$Id] = [object[]]@("$Activity", "$Status", [int]$Percent) }
    }
    function global:Write-Host {
        param([Parameter(Position = 0, ValueFromRemainingArguments = $true)][object]$Object,
              [switch]$NoNewline, [object]$Separator = ' ', [object]$ForegroundColor, [object]$BackgroundColor)
        Send-GuiText (ConvertTo-HostText $Object $Separator) "$ForegroundColor" ([bool]$NoNewline)
    }
    function global:Read-Host {
        param([Parameter(Position = 0)][object]$Prompt, [switch]$AsSecureString)
        return "$(Request-GuiAnswer 'text' ("$Prompt".Trim()))"
    }
    function global:Clear-Host { $script:GuiShared.Queue.Enqueue([object[]]@('clear')) }
    function global:Confirm-Action {
        param([string]$Question, [bool]$Default = $false)
        return [bool](Request-GuiAnswer 'yesno' (L $Question) $Default)
    }
    function global:Wait-Key { [void](Request-GuiAnswer 'continue' '') }
    # YSO's own helpers become parts of a document (headings, lines, values, choices)
    function global:Write-Section([string]$Title) { $script:GuiShared.Queue.Enqueue([object[]]@('section', (L $Title))) }
    function global:Write-Kv { param([string]$Key, $Value, [string]$Color = 'Gray') $script:GuiShared.Queue.Enqueue([object[]]@('kv', (L $Key), "$Value", "$Color")) }
    function global:Write-Step([string]$Text) { $script:GuiShared.Queue.Enqueue([object[]]@('line', 'step', (L $Text))) }
    function global:Write-Ok([string]$Text) { $script:GuiShared.Queue.Enqueue([object[]]@('line', 'ok', (L $Text))) }
    function global:Write-Warn([string]$Text) { $script:GuiShared.Queue.Enqueue([object[]]@('line', 'warn', (L $Text))) }
    function global:Write-Bad([string]$Text) { $script:GuiShared.Queue.Enqueue([object[]]@('line', 'bad', (L $Text))) }
    function global:Write-Info([string]$Text) { $script:GuiShared.Queue.Enqueue([object[]]@('line', 'info', (L $Text))) }
    function global:Write-Option([string]$Key, [string]$Text) { $script:GuiShared.Queue.Enqueue([object[]]@('option', $Key, (L $Text))) }
    function global:Show-HealthDashboard([object[]]$Items) {
        foreach ($i in $Items) { $script:GuiShared.Queue.Enqueue([object[]]@('health', "$($i.Level)", (L $i.Name), "$($i.Text)", "$($i.Action)")) }
    }
}

# ------------------------------------------------------------------
#  The window's side: jobs for the second PowerShell
# ------------------------------------------------------------------
function Start-GuiWorker([string]$ScriptPath, $Shared, [bool]$DryRunMode) {
    # The second PowerShell loads YSO itself (-Engine), then sends what it writes and asks to the window.
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'          # like the console: Windows Update and Shell objects expect it
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $script:GuiWorker = $rs
    Add-GuiJob -Name 'start' -Arguments @($ScriptPath, $Shared, $DryRunMode) `
        -Script 'param($YsoGuiPath, $YsoGuiShared, $YsoGuiDryRun) . $YsoGuiPath -Engine -DryRun:$YsoGuiDryRun; Enable-GuiAdapters $YsoGuiShared; if (Get-Command -Name Invoke-MenuOption -ErrorAction SilentlyContinue) { ''ready'' }' `
        -OnDone {
            param($Out, $Err, $FirstError)
            if (@($Out) -notcontains 'ready') {
                $why = $(if ($Err) { $Err } elseif ($FirstError) { $FirstError } else { L 'unknown error' })
                Set-GuiEngineFailed $why
            }
        }
}

function Add-GuiJob {
    # Jobs run one after the other. -Output: what the job writes is shown on the Run page.
    param([string]$Name, [string]$Script, [object[]]$Arguments = @(), [scriptblock]$OnDone, [switch]$Output, [string]$Title = '')
    $script:GuiJobs.Enqueue(@{ Name = $Name; Script = $Script; Arguments = $Arguments; OnDone = $OnDone; Output = [bool]$Output; Title = $Title })
}

function Start-NextGuiJob {
    $job = $script:GuiJobs.Dequeue()
    $s = $script:GuiShared
    $s.Stop = $false
    $s.Progress.Clear()
    $ps = [powershell]::Create()
    $ps.Runspace = $script:GuiWorker
    [void]$ps.AddScript($job.Script)
    foreach ($a in $job.Arguments) { [void]$ps.AddArgument($a) }
    $job.PS = $ps
    $job.Clock = [System.Diagnostics.Stopwatch]::StartNew()
    $job.Handle = $ps.BeginInvoke()
    $script:GuiCurrent = $job
    if ($job.Output) { Write-Host ''; Write-Host ('==== ' + $job.Title) }   # into this session's log
    Update-GuiBusy
}

function Complete-GuiJob {
    $job = $script:GuiCurrent
    $out = @()
    $err = ''
    $first = ''
    try { $out = @($job.PS.EndInvoke($job.Handle)) } catch { $err = $_.Exception.Message }
    if ($job.PS.Streams.Error.Count -gt 0) { $first = "$($job.PS.Streams.Error[0])" }
    try { $job.PS.Dispose() } catch { }
    $script:GuiCurrent = $null
    $script:GuiShared.Progress.Clear()
    if ($job.Output) { Hide-GuiAsk }
    if ($job.OnDone) { Invoke-GuiSafe ('after ' + $job.Name) { & $job.OnDone $out $err $first } }
    Update-GuiBusy
    if ($script:GuiCloseWhenIdle -and -not $script:GuiCurrent) { $script:GuiWindow.Close() }
}

function Test-GuiBusy {
    # An option is running (or waiting to start): the window does not start a second one.
    if ($script:GuiCurrent -and $script:GuiCurrent.Output) { return $true }
    foreach ($j in @($script:GuiJobs.ToArray())) { if ($j.Output) { return $true } }
    return $false
}

function Get-GuiBusyTitle {
    if ($script:GuiCurrent -and $script:GuiCurrent.Output) { return $script:GuiCurrent.Title }
    foreach ($j in @($script:GuiJobs.ToArray())) { if ($j.Output) { return $j.Title } }
    return ''
}

function Read-GuiMessages($Shared, [int]$Max = 400) {
    # What the second PowerShell sent since the last look (at most $Max messages at a time).
    $list = New-Object System.Collections.Generic.List[object]
    $m = $null
    while ($list.Count -lt $Max -and $Shared.Queue.TryDequeue([ref]$m)) { $list.Add($m) }
    return , $list
}

function Invoke-GuiTick {
    # 15 times a second: show what the job wrote and asked, its progress, and start the next job.
    $job = $script:GuiCurrent
    $msgs = Read-GuiMessages $script:GuiShared
    foreach ($m in $msgs) {
        switch ($m[0]) {
            'clear' { if ($job -and $job.Output) { Clear-GuiOutput } }
            'ask'   { Show-GuiAsk $m[1] $m[2] $m[3] }
            default {
                # this session's log keeps the text too (the console is hidden)
                if ($m[0] -eq 'text') { Write-Host $m[1] -NoNewline:([bool]$m[3]) } else { Write-Host (@($m | Select-Object -Skip 1) -join ' | ') }
                if ($job -and $job.Output) { Add-GuiDocMessage $m }
            }
        }
    }
    if ($msgs.Count -gt 0) { Update-GuiOutputView }
    if ($job) {
        Update-GuiProgress
        if ($job.Handle.IsCompleted -and $script:GuiShared.Queue.IsEmpty) { Complete-GuiJob }
    }
    if (-not $script:GuiCurrent -and $script:GuiJobs.Count -gt 0) { Start-NextGuiJob }
    if ($script:GuiSnapSteps) { Invoke-GuiSnapshotStep }
}

function Invoke-GuiSafe([string]$Context, [scriptblock]$Block) {
    # Event handlers: an error is saved and shown, the window stays open.
    try { & $Block }
    catch {
        $script:GuiErrors++
        if ($script:GuiErrors -le 20) { Write-YsoError -Context ('window: ' + $Context) -ErrorRecord $_ }
        if ($script:Ui -and $script:Ui.RunHint) { $script:Ui.RunHint.Text = (L 'Something went wrong in the window: {0}' $_.Exception.Message) }
    }
}

# ------------------------------------------------------------------
#  Building blocks
# ------------------------------------------------------------------
function Get-GuiBrush([string]$Name) {
    # A colour of the theme, or the colour a console colour name stands for.
    if (-not $script:GuiBrushes) { $script:GuiBrushes = @{} }
    if ($script:GuiBrushes.ContainsKey($Name)) { return $script:GuiBrushes[$Name] }
    $console = @{
        ''          = '#C9D2CD'; 'Gray' = '#C9D2CD'; 'White' = '#E9EFEC'; 'DarkGray' = '#85918B'
        'Green'     = '#4CAF7D'; 'DarkGreen' = '#4CAF7D'; 'Cyan' = '#E9EFEC'; 'DarkCyan' = '#A3AFA9'
        'Yellow'    = '#D9A441'; 'DarkYellow' = '#D9A441'; 'Red' = '#E07070'; 'DarkRed' = '#E07070'
        'Magenta'   = '#C9A0D9'; 'DarkMagenta' = '#C9A0D9'; 'Blue' = '#7AA7D9'; 'DarkBlue' = '#7AA7D9'; 'Black' = '#0F1412'
    }
    $brush = $null
    if ($console.ContainsKey($Name)) {
        $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($console[$Name]))
        $brush.Freeze()
    } elseif ($script:GuiWindow) {
        $brush = $script:GuiWindow.TryFindResource($Name)
    }
    if (-not $brush) { $brush = Get-GuiBrush '' }
    $script:GuiBrushes[$Name] = $brush
    return $brush
}

function New-GuiThickness([string]$Text) {
    # "left,top,right,bottom", "horizontal,vertical" or "all", read the same on every Windows: WPF's own
    # converter reads "0,2,0,0" as 0.2 where the comma is the decimal separator (French Windows...).
    $n = @($Text -split ',' | ForEach-Object { [double]::Parse($_.Trim(), [System.Globalization.CultureInfo]::InvariantCulture) })
    switch ($n.Count) {
        1 { return (New-Object System.Windows.Thickness $n[0]) }
        2 { return (New-Object System.Windows.Thickness $n[0], $n[1], $n[0], $n[1]) }
        4 { return (New-Object System.Windows.Thickness $n[0], $n[1], $n[2], $n[3]) }
        default { throw "Not a thickness: $Text" }
    }
}

function New-GuiColumn([string]$Width) {
    # A grid column: 'Auto', '*' or a number of pixels.
    $c = New-Object System.Windows.Controls.ColumnDefinition
    if ($Width -eq 'Auto') { $c.Width = [System.Windows.GridLength]::Auto }
    elseif ($Width -eq '*') { $c.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star) }
    else { $c.Width = New-Object System.Windows.GridLength ([double]::Parse($Width, [System.Globalization.CultureInfo]::InvariantCulture)) }
    return $c
}

function New-GuiText {
    param([string]$Text, [double]$Size = 13, [string]$Brush = 'Text', [string]$Weight = 'Normal', [switch]$Wrap, [string]$Margin = '0')
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = $Size
    $t.Foreground = Get-GuiBrush $Brush
    $t.FontWeight = [System.Windows.FontWeights]::$Weight
    $t.Margin = New-GuiThickness $Margin
    if ($Wrap) { $t.TextWrapping = 'Wrap' } else { $t.TextTrimming = 'CharacterEllipsis' }
    return $t
}

function New-GuiIcon([string]$Glyph, [double]$Size = 16, [string]$Brush = 'Text') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Glyph
    $t.Style = $script:GuiWindow.FindResource('Icon')
    $t.FontSize = $Size
    $t.Foreground = Get-GuiBrush $Brush
    return $t
}

function New-YsoLogo([int]$Pixels = 64) {
    # The YSO mark: a green square with a white Y. Drawn, so it needs no image file.
    $v = New-Object System.Windows.Media.DrawingVisual
    $dc = $v.RenderOpen()
    $s = [double]$Pixels
    $fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#3E9B6C'))
    $dc.DrawRoundedRectangle($fill, $null, (New-Object System.Windows.Rect 0, 0, $s, $s), ($s * 0.12), ($s * 0.12))
    $pen = New-Object System.Windows.Media.Pen ([System.Windows.Media.Brushes]::White), ($s * 0.12)
    $pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'
    $mid = New-Object System.Windows.Point ($s * 0.5), ($s * 0.53)
    $dc.DrawLine($pen, (New-Object System.Windows.Point ($s * 0.29), ($s * 0.27)), $mid)
    $dc.DrawLine($pen, (New-Object System.Windows.Point ($s * 0.71), ($s * 0.27)), $mid)
    $dc.DrawLine($pen, $mid, (New-Object System.Windows.Point ($s * 0.5), ($s * 0.76)))
    $dc.Close()
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $Pixels, $Pixels, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($v)
    $bmp.Freeze()
    return $bmp
}

function Save-YsoIcon([string]$Path) {
    # An .ico file for the shortcuts and Installed apps: PNG images inside (Windows Vista and later read them).
    $sizes = @(256, 64, 48, 32, 16)
    $pngs = foreach ($n in $sizes) {
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create((New-YsoLogo $n)))
        $ms = New-Object System.IO.MemoryStream
        $enc.Save($ms)
        , $ms.ToArray()
    }
    $fs = [System.IO.File]::Create($Path)
    try {
        $w = New-Object System.IO.BinaryWriter $fs
        $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $px = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
            $w.Write([byte]$px); $w.Write([byte]$px); $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32)
            $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
            $offset += $pngs[$i].Length
        }
        foreach ($p in $pngs) { $w.Write([byte[]]$p) }
        $w.Flush()
    } finally { $fs.Close() }
}

function Initialize-YsoNative {
    if ('YSO.Native' -as [type]) { return $true }
    try {
        Add-Type -Namespace 'YSO' -Name 'Native' -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
'@
        return $true
    } catch { return $false }
}

function Show-ConsoleWindow([switch]$Hide) {
    # The window hides the console it was started from; the console menu shows it again.
    if (-not (Initialize-YsoNative)) { return }
    try {
        $h = [YSO.Native]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][YSO.Native]::ShowWindow($h, $(if ($Hide) { 0 } else { 5 })) }
    } catch { }
}

function Test-ConsoleVisible {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { return $true }
    if (-not (Initialize-YsoNative)) { return $true }
    try {
        $h = [YSO.Native]::GetConsoleWindow()
        return ($h -ne [IntPtr]::Zero -and [YSO.Native]::IsWindowVisible($h))
    } catch { return $true }
}

function Start-YsoConsole {
    # The console menu in a new window (the window itself may have been started without a console).
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Console')
    if ($script:DryRun) { $a += '-DryRun' }
    Start-Process -FilePath $ps -ArgumentList $a
}

# ------------------------------------------------------------------
#  Pages
# ------------------------------------------------------------------
function Get-GuiCleanItems {
    # The Clean page. Cats: the results of Analyze (A) that belong to each line.
    return @(
        @{ Key = 'Temp';        Name = (N 'Temporary files');        On = $true;  Cats = @('Temporary files')
           Desc = (N 'Temporary folders of every user and of Windows. Recent files are kept.') }
        @{ Key = 'Browsers';    Name = (N 'Browser caches');         On = $true;  Cats = @('Browser caches')
           Desc = (N 'Chrome, Edge, Brave, Vivaldi, Opera, Firefox. Passwords, cookies, history and tabs stay.') }
        @{ Key = 'SiteCaches';  Name = (N 'Site offline caches');    On = $true;  Cats = @('Site offline caches')
           Desc = (N 'Offline copies kept by websites and web apps. You stay logged in.') }
        @{ Key = 'SystemJunk';  Name = (N 'System junk');            On = $true;  Cats = @('System junk')
           Desc = (N 'Error reports, crash dumps, old logs and the thumbnail cache.') }
        @{ Key = 'DevApps';     Name = (N 'Developer & app caches');  On = $true;  Cats = @('Developer & app caches', 'Other app caches')
           Desc = (N 'npm, pip, VS Code, Discord, Teams, Spotify, Steam... and every app built on Chromium.') }
        @{ Key = 'Gpu';         Name = (N 'GPU shader caches');      On = $true;  Cats = @('GPU shader caches')
           Desc = (N 'Rebuilt by the graphics driver: games may stutter briefly the first time.') }
        @{ Key = 'UpdateCache'; Name = (N 'Windows Update cache');   On = $true;  Cats = @('Windows Update cache', 'Delivery Optimization')
           Desc = (N 'Updates that are already installed, and the Delivery Optimization cache.') }
        @{ Key = 'Deep';        Name = (N 'Deep clean');             On = $true;  Cats = @()
           Desc = (N 'Windows Disk Cleanup and the component store. Adds 10-30 minutes.') }
        @{ Key = 'OldDrivers';  Name = (N 'Old driver versions');    On = $false; Cats = @('Old driver versions')
           Desc = (N 'Older copies of your drivers. You will not be able to go back to them.') }
        @{ Key = 'RecycleBin';  Name = (N 'Recycle Bin');            On = $false; Cats = @('Recycle Bin')
           Desc = (N 'Permanently deletes what is in the Recycle Bin.') }
    )
}

function Get-GuiCleanOptions {
    return @(
        @{ Key = 'Restore';   On = $true;  Name = (N 'Create a restore point first (recommended)') }
        @{ Key = 'CloseApps'; On = $true;  Name = (N 'Close open browsers and apps that keep files in use (tabs come back, nothing is lost)') }
        @{ Key = 'Optimize';  On = $true;  Name = (N 'Optimize drives at the end (TRIM / defrag)') }
        @{ Key = 'Updates';   On = $false; Name = (N 'Also install app and driver updates (adds 5-30 min)') }
    )
}

function Get-GuiCleanPlan([switch]$Defaults) {
    # The plan F runs, from the Clean page (or its defaults: Clean everything on Home).
    $plan = @{ Dns = $true }
    foreach ($i in (Get-GuiCleanItems)) {
        $plan[$i.Key] = $(if ($Defaults) { $i.On } else { [bool]$script:GuiCleanRows[$i.Key].Check.IsChecked })
    }
    foreach ($o in (Get-GuiCleanOptions)) {
        $plan[$o.Key] = $(if ($Defaults) { $o.On } else { [bool]$script:GuiCleanRows[$o.Key].Check.IsChecked })
    }
    $plan.CloseBrowsers = $plan.CloseApps
    return $plan
}

function Get-GuiToolGroups {
    return @(
        @{ Title = (N 'CLEAN'); Items = @((M '1' 'Temporary files'), (M '2' 'Browser caches'), (M '3' 'System junk (reports, dumps, old logs)'),
            (M '4' 'Windows Update cache'), (M '5' 'Recycle Bin'), (M '6' 'GPU shader caches'), (M '7' 'Developer & app caches'),
            (M '8' 'Deep clean (Disk Cleanup)'), (M '9' 'Old Windows version (Windows.old)'), (M '10' 'Hibernation file')) }
        @{ Title = (N 'NETWORK'); Items = @((M '11' 'Network check (speed, DNS, Wi-Fi)'), (M '12' 'Change DNS servers'), (M '13' 'Flush DNS cache'), (M '14' 'Full network reset')) }
        @{ Title = (N 'OPTIMIZE'); Items = @((M '15' 'Optimize drives (TRIM / defrag)'), (M '16' 'Power plan'), (M '17' 'Startup programs'), (M '18' 'Boot time analyzer')) }
        @{ Title = (N 'DIAGNOSE & REPAIR'); Items = @((M '19' 'System health report'), (M '20' 'Crashes & errors'), (M '21' 'Security check & Defender scan'),
            (M '22' 'What runs automatically? (audit)'), (M '23' 'Driver problems'), (M '24' 'Check drives for errors'), (M '25' 'Memory test'), (M '26' 'Repair Windows files (DISM + SFC)')) }
        @{ Title = (N 'SPACE & UPDATES'); Items = @((M '27' 'Space finder (what fills my disk?)'), (M '28' 'Updates: apps & drivers')) }
        @{ Title = (N 'ONE-CLICK'); Items = @((M 'A' 'Analyze (deletes nothing)'), (M 'F' 'Full maintenance'), (M 'R' 'Restore points'), (M 'S' 'Weekly auto-clean'),
            (M 'H' 'Cleanup history'), (M 'T' 'Self-test (check everything)'), (M 'P' 'Report a problem'), (M 'O' 'Settings / Langue'),
            (M 'L' 'Logs folder')) }
    )
}

function Get-GuiOptionTitle([string]$Key) {
    foreach ($g in (Get-GuiToolGroups)) { foreach ($i in $g.Items) { if ($i[0] -eq $Key) { return (L $i[1]) } } }
    return $Key
}

function Show-GuiPage([string]$Name, [string]$Key = '') {
    # $Key: the option shown on the Run page, so the menu on the left shows where you are.
    foreach ($p in @('Home', 'Clean', 'Run', 'Tools')) {
        $script:Ui["Page$p"].Visibility = $(if ($p -eq $Name) { 'Visible' } else { 'Collapsed' })
    }
    $script:GuiPage = $Name
    $nav = @{ Home = 'NavHome'; Clean = 'NavClean'; Tools = 'NavTools' }
    $byKey = @{ '28' = 'NavUpdates'; '17' = 'NavStartup'; '19' = 'NavHealth'; 'R' = 'NavRestore'; 'H' = 'NavHistory'; 'O' = 'NavSettings'; 'A' = 'NavClean'; 'F' = 'NavClean' }
    if ($Name -eq 'Run') {
        if (-not $Key) { $Key = $script:GuiRunKey }
        $item = $(if ($byKey.ContainsKey($Key)) { $byKey[$Key] } else { 'NavTools' })
        $script:Ui[$item].IsChecked = $true
    } elseif ($nav.ContainsKey($Name)) { $script:Ui[$nav[$Name]].IsChecked = $true }
    Update-GuiBusy
}

function Update-GuiBusy {
    # The green pill at the top: a job is running and its page is not the one shown.
    $ui = $script:Ui
    if (-not $ui) { return }
    $busy = Test-GuiBusy
    $onItsPage = ($script:GuiPage -eq 'Run' -or ($script:GuiPage -eq 'Clean' -and $script:GuiCurrent -and $script:GuiCurrent.Name -eq 'analysis'))
    $ui.BusyPill.Visibility = $(if ($busy -and -not $onItsPage) { 'Visible' } else { 'Collapsed' })
    if ($busy) { $ui.BusyText.Text = Get-GuiBusyTitle }
    $ui.HomeAnalyze.IsEnabled = -not $busy
    $ui.HomeClean.IsEnabled = -not $busy
    $ui.CleanAnalyze.IsEnabled = -not $busy
    $ui.CleanRun.IsEnabled = -not $busy
}

function Show-GuiDialog {
    # A question inside the window. -OnYes runs when the accent button is clicked.
    param([string]$Title, [string]$Text, [string]$Yes = (L 'OK'), [string]$No = '', [scriptblock]$OnYes)
    $ui = $script:Ui
    $ui.DlgTitle.Text = $Title
    $ui.DlgText.Text = $Text
    $ui.DlgYes.Content = $Yes
    $ui.DlgNo.Content = $No
    $ui.DlgNo.Visibility = $(if ($No) { 'Visible' } else { 'Collapsed' })
    $script:GuiDialogYes = $OnYes
    $ui.Overlay.Visibility = 'Visible'
    [void]$ui.DlgYes.Focus()
}

function Close-GuiDialog([bool]$Yes) {
    $script:Ui.Overlay.Visibility = 'Collapsed'
    $action = $script:GuiDialogYes
    $script:GuiDialogYes = $null
    if ($Yes -and $action) { & $action }
}

function Show-GuiBusyMessage {
    Show-GuiDialog -Title (L 'YSO is busy') -Text (L 'Wait until "{0}" is finished, or stop it first.' (Get-GuiBusyTitle)) -Yes (L 'Show it') -No (L 'Close') -OnYes { Show-GuiPage 'Run' }
}

# --- Home ---
function Update-GuiHealth($Data) {
    $ui = $script:Ui
    $ui.HealthGrid.Children.Clear()
    if (-not $Data) { return }
    $ui.HomeSub.Text = ('{0}' -f $Data.Os) + "`n" + (L 'Free space: {0}' $Data.Free)
    $look = @{
        Good = @('Good', 'GoodSoft', [string][char]0xE73E); Warn = @('Warn', 'WarnSoft', [string][char]0xE7BA)
        Bad  = @('Bad', 'BadSoft', [string][char]0xE711);   Info = @('Info', 'InfoSoft', [string][char]0xE946)
    }
    foreach ($i in @($Data.Items)) {
        $l = $look["$($i.Level)"]; if (-not $l) { $l = $look['Info'] }
        $card = New-Object System.Windows.Controls.Border
        $card.Background = Get-GuiBrush 'Card'
        $card.BorderBrush = Get-GuiBrush 'Line'
        $card.BorderThickness = 1
        $card.CornerRadius = 4
        $card.Padding = New-GuiThickness '16,14'
        $card.Margin = New-GuiThickness '0,0,12,12'
        $g = New-Object System.Windows.Controls.Grid
        foreach ($w in @('Auto', '*', 'Auto')) { $g.ColumnDefinitions.Add((New-GuiColumn $w)) }
        $dot = New-Object System.Windows.Controls.Border
        $dot.Width = 32; $dot.Height = 32; $dot.CornerRadius = 4
        $dot.Background = Get-GuiBrush $l[1]
        $dot.VerticalAlignment = 'Top'
        $dot.Child = New-GuiIcon $l[2] 15 $l[0]
        $g.Children.Add($dot) | Out-Null
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = New-GuiThickness '14,0,8,0'
        $sp.VerticalAlignment = 'Center'
        $sp.Children.Add((New-GuiText (L $i.Name) 13.5 'Text' 'SemiBold')) | Out-Null
        $sp.Children.Add((New-GuiText "$($i.Text)" 12.5 'Text2' -Wrap -Margin '0,3,0,0')) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($sp, 1)
        $g.Children.Add($sp) | Out-Null
        if ($i.Action) {
            $b = New-Object System.Windows.Controls.Button
            $b.Style = $script:GuiWindow.FindResource('Link')
            $b.Content = Get-GuiActionText "$($i.Action)"
            $b.Tag = "$($i.Action)"
            $b.VerticalAlignment = 'Center'
            $b.Add_Click({ param($s, $e) Invoke-GuiSafe 'health action' { Invoke-GuiAction "$($s.Tag)" } })
            [System.Windows.Controls.Grid]::SetColumn($b, 2)
            $g.Children.Add($b) | Out-Null
        }
        $card.Child = $g
        $ui.HealthGrid.Children.Add($card) | Out-Null
    }
}

function Get-GuiActionText([string]$Key) {
    switch ($Key) {
        'A' { return (L 'Analyze') }
        'F' { return (L 'Clean') }
        '19' { return (L 'Details') }
        '21' { return (L 'Check') }
        default { return (L 'Open') }
    }
}

function Invoke-GuiAction([string]$Key) {
    # A key of the console menu, from a button: some have their own page, the others run on the Run page.
    switch ($Key) {
        'A' { Show-GuiPage 'Clean'; Start-GuiAnalysis }
        'F' { Show-GuiPage 'Clean' }
        'L' { Start-Process explorer.exe -ArgumentList "`"$($script:LogDir)`"" }
        default { Start-GuiOption $Key }
    }
}

function New-GuiSkeleton([double]$Width, [double]$Height = 10, [string]$Margin = '0') {
    # A grey placeholder where a value will appear (static: nothing moves).
    $b = New-Object System.Windows.Controls.Border
    $b.Width = $Width; $b.Height = $Height
    $b.CornerRadius = 2
    $b.Background = Get-GuiBrush 'Card2'
    $b.HorizontalAlignment = 'Left'
    $b.Margin = New-GuiThickness $Margin
    return $b
}

function Show-GuiHealthSkeleton {
    # While the PC is checked: the cards in grey, so the page keeps its shape.
    $grid = $script:Ui.HealthGrid
    if ($grid.Children.Count -gt 0) { return }   # the previous result stays until the new one is there
    for ($i = 0; $i -lt 6; $i++) {
        $card = New-Object System.Windows.Controls.Border
        $card.Background = Get-GuiBrush 'Card'
        $card.BorderBrush = Get-GuiBrush 'Line'
        $card.BorderThickness = 1
        $card.CornerRadius = 4
        $card.Padding = New-GuiThickness '16,14'
        $card.Margin = New-GuiThickness '0,0,12,12'
        $g = New-Object System.Windows.Controls.Grid
        $g.ColumnDefinitions.Add((New-GuiColumn 'Auto')); $g.ColumnDefinitions.Add((New-GuiColumn '*'))
        $g.Children.Add((New-GuiSkeleton 32 32)) | Out-Null
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = New-GuiThickness '14,2,0,0'
        $sp.Children.Add((New-GuiSkeleton (90 + 15 * ($i % 3)) 12)) | Out-Null
        $sp.Children.Add((New-GuiSkeleton (150 + 20 * (($i + 1) % 3)) 10 '0,8,0,0')) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($sp, 1)
        $g.Children.Add($sp) | Out-Null
        $card.Child = $g
        $grid.Children.Add($card) | Out-Null
    }
}

function Start-GuiHealth {
    Show-GuiHealthSkeleton
    Add-GuiJob -Name 'health' -Script '$script:HealthCache = $null; [pscustomobject]@{ Items = @(Get-HealthItems); Os = $script:OsText; Free = (Get-FreeSpaceText) }' -OnDone {
        param($Out, $Err)
        Update-GuiHealth $(if ($Out.Count -gt 0) { $Out[-1] } else { $null })
    }
}

# --- Clean ---
function Initialize-GuiClean {
    $ui = $script:Ui
    $script:GuiCleanRows = @{}
    foreach ($i in (Get-GuiCleanItems)) {
        $row = New-Object System.Windows.Controls.Border
        $row.Background = Get-GuiBrush 'Card'
        $row.BorderBrush = Get-GuiBrush 'Line'
        $row.BorderThickness = 1
        $row.CornerRadius = 4
        $row.Padding = New-GuiThickness '16,12'
        $row.Margin = New-GuiThickness '0,0,0,8'
        $g = New-Object System.Windows.Controls.Grid
        $g.ColumnDefinitions.Add((New-GuiColumn '*')); $g.ColumnDefinitions.Add((New-GuiColumn 'Auto'))
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked = $i.On
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Children.Add((New-GuiText (L $i.Name) 14 'Text' 'SemiBold')) | Out-Null
        $sp.Children.Add((New-GuiText (L $i.Desc) 12.5 'Text2' -Wrap -Margin '0,2,0,0')) | Out-Null
        $cb.Content = $sp
        $cb.Add_Click({ Invoke-GuiSafe 'clean total' { Update-GuiCleanTotal } })
        $g.Children.Add($cb) | Out-Null
        $size = New-GuiText '' 14 'Text2' 'SemiBold' -Margin '16,0,0,0'
        $size.VerticalAlignment = 'Center'
        $size.MinWidth = 90
        $size.TextAlignment = 'Right'
        [System.Windows.Controls.Grid]::SetColumn($size, 1)
        $g.Children.Add($size) | Out-Null
        $sk = New-GuiSkeleton 64 12
        $sk.HorizontalAlignment = 'Right'
        $sk.VerticalAlignment = 'Center'
        $sk.Visibility = 'Collapsed'
        [System.Windows.Controls.Grid]::SetColumn($sk, 1)
        $g.Children.Add($sk) | Out-Null
        $row.Child = $g
        $ui.CleanList.Children.Add($row) | Out-Null
        $script:GuiCleanRows[$i.Key] = @{ Check = $cb; Size = $size; Skeleton = $sk; Cats = $i.Cats; Bytes = [long]-1 }
    }
    foreach ($o in (Get-GuiCleanOptions)) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked = $o.On
        $t = New-GuiText (L $o.Name) 13 'Text' -Wrap
        $cb.Content = $t
        $cb.Margin = New-GuiThickness '2,0,0,12'
        $ui.CleanOptions.Children.Add($cb) | Out-Null
        $script:GuiCleanRows[$o.Key] = @{ Check = $cb; Label = $t }
    }
    $script:GuiCleanRows['Deep'].Size.Text = (L 'measured when it runs')
    $script:GuiCleanRows['Deep'].Size.FontWeight = 'Normal'
    $script:GuiCleanRows['Deep'].Size.FontSize = 12
}

function Update-GuiCleanTotal {
    $sum = [long]0; $known = $false
    foreach ($i in (Get-GuiCleanItems)) {
        $r = $script:GuiCleanRows[$i.Key]
        if ($r.Bytes -ge 0) { $known = $true; if ($r.Check.IsChecked) { $sum += $r.Bytes } }
    }
    if ($known) {
        $script:Ui.CleanTotal.Text = Format-Size $sum
        $script:Ui.CleanTotalLabel.Text = (L 'can be freed with what is ticked')
    }
}

function Start-GuiAnalysis {
    if (Test-GuiBusy) { Show-GuiBusyMessage; return }
    $ui = $script:Ui
    $ui.CleanBar.Visibility = 'Visible'
    $ui.CleanBar.Value = 0
    $ui.CleanStatus.Visibility = 'Visible'
    $ui.CleanStatus.Text = (L 'Analyzing - nothing will be deleted...')
    $ui.CleanTotal.Visibility = 'Collapsed'
    $ui.CleanTotalLabel.Text = (L 'Analyzing - nothing will be deleted...')
    foreach ($i in (Get-GuiCleanItems)) {
        if ($i.Key -eq 'Deep') { continue }
        $script:GuiCleanRows[$i.Key].Size.Text = ''
        $script:GuiCleanRows[$i.Key].Skeleton.Visibility = 'Visible'
    }
    Reset-GuiRun (L 'Analyze')
    $script:GuiRunKey = 'A'
    Add-GuiJob -Name 'analysis' -Output -Title (L 'Analyze') -Script '[pscustomobject]@{ Results = @(Invoke-Analysis -PassThru); Context = (Get-MaintenanceContext) }' -OnDone {
        param($Out, $Err)
        Complete-GuiAnalysis $(if ($Out.Count -gt 0) { $Out[-1] } else { $null }) $Err
    }
    Update-GuiBusy
}

function Complete-GuiAnalysis($Data, [string]$Err) {
    $ui = $script:Ui
    $ui.CleanBar.Visibility = 'Collapsed'
    $ui.CleanDetails.Visibility = 'Visible'
    $ui.CleanTotal.Visibility = 'Visible'
    $ui.CleanTotalLabel.Text = (L 'Analyze to see how much you can free')
    foreach ($r in $script:GuiCleanRows.Values) { if ($r.Skeleton) { $r.Skeleton.Visibility = 'Collapsed' } }
    Set-GuiRunFinished $(if ($Err) { 'failed' } else { 'done' })
    if (-not $Data) {
        $ui.CleanStatus.Text = (L 'The analysis did not finish: {0}' $Err)
        return
    }
    $ui.CleanStatus.Visibility = 'Collapsed'
    $byCat = @{}
    foreach ($r in @($Data.Results)) { $byCat["$($r.Category)"] = [long]$byCat["$($r.Category)"] + [long]$r.Bytes }
    foreach ($i in (Get-GuiCleanItems)) {
        if ($i.Key -eq 'Deep') { continue }
        $row = $script:GuiCleanRows[$i.Key]
        $sum = [long]0
        foreach ($c in $i.Cats) { if ($byCat.ContainsKey($c)) { $sum += $byCat[$c] } }
        if ($i.Key -eq 'RecycleBin' -and $Data.Context) { $sum = [long]$Data.Context.RecycleBin }
        $row.Bytes = $sum
        $row.Size.Text = $(if ($sum -gt 0) { Format-Size $sum } else { L 'nothing' })
        $row.Size.Foreground = Get-GuiBrush $(if ($sum -ge 100MB) { 'Accent' } else { 'Text2' })
    }
    Update-GuiCleanContext $Data.Context
    Update-GuiCleanTotal
}

function Update-GuiCleanContext($Context) {
    if (-not $Context) { return }
    $ui = $script:Ui
    $open = @(@($Context.Browsers) + @($Context.Apps) | Where-Object { $_ })
    $row = $script:GuiCleanRows['CloseApps']
    if ($open.Count -gt 0) { $row.Label.Text = (L 'Close {0} first, so their files can be cleaned (tabs come back, nothing is lost)' ($open -join ', ')) }
    else { $opt = (Get-GuiCleanOptions)[1]; $row.Label.Text = (L $opt.Name) }
    if ($Context.PendingReboot) {
        $ui.CleanWarn.Visibility = 'Visible'
        $ui.CleanWarnText.Text = (L 'Windows is waiting for a restart (updates). Until then, the Windows Update cache and the component store cannot be cleaned. Best: Restart (not Shut down) first.')
    } else { $ui.CleanWarn.Visibility = 'Collapsed' }
}

function Start-GuiClean([switch]$Everything) {
    if (Test-GuiBusy) { Show-GuiBusyMessage; return }
    $plan = Get-GuiCleanPlan -Defaults:$Everything
    $picked = @(Get-GuiCleanItems | Where-Object { $plan[$_.Key] } | ForEach-Object { L $_.Name })
    if ($picked.Count -eq 0) {
        Show-GuiDialog -Title (L 'Nothing is ticked') -Text (L 'Tick at least one line to clean.')
        return
    }
    $lines = @()
    $lines += (L 'YSO cleans: {0}.' ($picked -join ', '))
    if ($plan.Restore) { $lines += (L 'A restore point is created first.') }
    if (-not $plan.RecycleBin) { $lines += (L 'The Recycle Bin is kept.') }
    if ($plan.CloseApps) { $lines += (L 'Open browsers and apps that keep files in use are closed: tabs come back, nothing is lost.') }
    if ($plan.Deep) { $lines += (L 'With deep clean, it takes 15 to 40 minutes. You can keep using the PC.') }
    $title = $(if ($Everything) { L 'Clean everything?' } else { L 'Clean what is ticked?' })
    $script:GuiPendingPlan = $plan
    $script:GuiPendingTitle = $(if ($Everything) { L 'Full maintenance' } else { L 'Cleaning' })
    Show-GuiDialog -Title $title -Text ($lines -join "`n`n") -Yes (L 'Start') -No (L 'Cancel') -OnYes {
        Start-GuiOption 'F' $script:GuiPendingTitle $script:GuiPendingPlan
    }
}

# --- Run page: any option, with the text it writes and the questions it asks ---
function Reset-GuiRun([string]$Title) {
    $ui = $script:Ui
    $ui.RunTitle.Text = $Title
    $ui.RunState.Text = (L 'Working...')
    $ui.RunStep.Text = ''
    $ui.RunStatus.Text = ''
    $ui.RunBar0.Value = 0; $ui.RunBar0.IsIndeterminate = $true
    $ui.RunBar1.Value = 0; $ui.RunBar1.Visibility = 'Hidden'
    $ui.RunProgress.Visibility = 'Visible'
    $ui.RunResult.Visibility = 'Collapsed'
    $ui.RunStop.Visibility = 'Visible'
    $ui.RunStop.IsEnabled = $true
    $ui.RunBack.Visibility = 'Collapsed'
    $ui.RunHint.Text = ''
    Clear-GuiOutput
    Hide-GuiAsk
}

function Start-GuiOption([string]$Key, [string]$Title = '', [hashtable]$Plan = $null) {
    if (Test-GuiBusy) { Show-GuiBusyMessage; return }
    if (-not $Title) { $Title = Get-GuiOptionTitle $Key }
    Reset-GuiRun $Title
    $script:GuiRunKey = $Key
    Show-GuiPage 'Run' $Key
    Add-GuiJob -Name ('option ' + $Key) -Output -Title $Title -Arguments @($Key, $Plan) `
        -Script 'param($YsoGuiKey, $YsoGuiPlan) Invoke-MenuOption -Choice $YsoGuiKey -Plan $YsoGuiPlan 2>&1 | Out-String -Stream -Width 112 | ForEach-Object { Write-Host $_ }; [pscustomobject]@{ Run = $script:LastRun; Lang = $script:Lang }' `
        -OnDone { param($Out, $Err) Complete-GuiRun $(if ($Out.Count -gt 0) { $Out[-1] } else { $null }) $Err }
    Update-GuiBusy
}

function Set-GuiRunFinished([string]$Status) {
    $ui = $script:Ui
    $ui.RunProgress.Visibility = 'Collapsed'
    $ui.RunStop.Visibility = 'Collapsed'
    $ui.RunBack.Visibility = 'Visible'
    $ui.RunState.Text = switch ($Status) {
        'stopped' { L 'Stopped.' }
        'failed'  { L 'Something went wrong. The details were saved: use Report a problem (P) to send them.' }
        default   { L 'Finished.' }
    }
}

function Complete-GuiRun($Data, [string]$Err) {
    $ui = $script:Ui
    $run = $(if ($Data) { $Data.Run } else { $null })
    $status = $(if ($Err -or -not $run) { 'failed' } else { "$($run.Status)" })
    Set-GuiRunFinished $status
    if ($Err) { Add-GuiDocMessage ([object[]]@('line', 'bad', (L 'Error: {0}' $Err))); Update-GuiOutputView }
    if ($run -and @($run.Results).Count -gt 0) {
        $total = [long](@($run.Results) | Measure-Object -Property Bytes -Sum).Sum
        $ui.RunResult.Visibility = 'Visible'
        if ($run.DryRun) {
            $ui.RunResultBig.Text = (L '{0} can be freed' (Format-Size $total))
            $ui.RunResultText.Text = (L 'Analyze-only mode: nothing was deleted.')
        } else {
            $ui.RunResultBig.Text = (L '{0} freed' (Format-Size $total))
            $top = @($run.Results | Where-Object { $_.Bytes -gt 0 } | Sort-Object Bytes -Descending | Select-Object -First 4 |
                ForEach-Object { '{0} {1}' -f (L $_.Category), (Format-Size $_.Bytes) })
            $text = (L 'Free disk space: {0} -> {1}' (Format-Size $run.FreeBefore) (Format-Size $run.FreeAfter))
            if ($top.Count -gt 0) { $text += "`n" + ($top -join '   |   ') }
            $ui.RunResultText.Text = $text
        }
    }
    if ($status -ne 'stopped') { Start-GuiHealth }
    if ($Data -and $Data.Lang -and $Data.Lang -ne $script:Lang) {
        # The language was changed in Settings: the window is built again in that language.
        $script:GuiResult = 'reload'
        $script:GuiWindow.Close()
    }
}

function Stop-GuiJob {
    if (-not (Test-GuiBusy)) { return }
    $script:GuiShared.Stop = $true
    $script:Ui.RunStop.IsEnabled = $false
    $script:Ui.RunState.Text = (L 'Stopping... (a Windows tool that is running finishes first)')
    Hide-GuiAsk
}

function Clear-GuiOutput {
    # The text of the running option, as a document: headings, lines, values, and its choices as buttons.
    if ($script:Ui) { $script:Ui.RunDoc.Children.Clear() }
    $script:GuiLine = New-Object System.Collections.Generic.List[object]
    $script:GuiDocText = New-Object System.Text.StringBuilder
    $script:GuiOptions = New-Object System.Collections.Generic.List[object]
}

function Add-GuiBlock($Element) {
    $doc = $script:Ui.RunDoc
    $doc.Children.Add($Element) | Out-Null
    if ($doc.Children.Count -gt 3000) { $doc.Children.RemoveRange(0, 1000) }   # very long outputs: the end stays
}

function Add-GuiSpacer {
    $doc = $script:Ui.RunDoc
    if ($doc.Children.Count -eq 0) { return }
    $last = $doc.Children[$doc.Children.Count - 1]
    if ($last.Tag -eq 'spacer') { return }
    $b = New-Object System.Windows.Controls.Border
    $b.Height = 8
    $b.Tag = 'spacer'
    Add-GuiBlock $b
}

function Complete-GuiRawLine {
    # Text written in pieces (Write-Host -NoNewline) becomes one line. Columns lined up with spaces
    # (tables) keep a fixed-width font so they stay lined up; everything else uses the window's font.
    $runs = @($script:GuiLine.ToArray())
    $script:GuiLine.Clear()
    $plain = (@($runs | ForEach-Object { $_[0] }) -join '')
    [void]$script:GuiDocText.AppendLine($plain.TrimEnd())
    if (-not $plain.Trim()) { Add-GuiSpacer; return }
    $aligned = ($plain.Trim() -match '\S {3,}\S')
    $indent = $plain.Length - $plain.TrimStart().Length
    $cut = $(if ($aligned) { [math]::Min(2, $indent) } else { $indent })
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Margin = New-GuiThickness '0,1,0,1'
    if ($aligned) {
        $tb.FontFamily = New-Object System.Windows.Media.FontFamily 'Consolas'
        $tb.FontSize = 12.5
        $tb.TextWrapping = 'NoWrap'
        $tb.TextTrimming = 'CharacterEllipsis'
    } else {
        $tb.FontSize = 13
        $tb.TextWrapping = 'Wrap'
    }
    foreach ($r in $runs) {
        $t = [string]$r[0]
        if ($cut -gt 0) { $n = [math]::Min($cut, $t.Length - $t.TrimStart().Length); $t = $t.Substring($n); $cut -= $n }
        if (-not $t) { continue }
        $run = New-Object System.Windows.Documents.Run $t
        $run.Foreground = Get-GuiBrush ([string]$r[1])
        $tb.Inlines.Add($run)
    }
    Add-GuiBlock $tb
}

function Add-GuiDocMessage($m) {
    # One message of the running option: text, section, kv, line, option, health.
    if ($m[0] -ne 'text' -and $script:GuiLine.Count -gt 0) { Complete-GuiRawLine }
    switch ($m[0]) {
        'text' {
            $script:GuiLine.Add(@([string]$m[1], [string]$m[2]))
            if (-not $m[3]) { Complete-GuiRawLine }
        }
        'section' {
            [void]$script:GuiDocText.AppendLine('').AppendLine([string]$m[1])
            Add-GuiBlock (New-GuiText ([string]$m[1]) 12 'Text2' 'SemiBold' -Margin '0,16,0,6')
        }
        'kv' {
            [void]$script:GuiDocText.AppendLine(('{0}: {1}' -f ([string]$m[1]).TrimEnd(':', ' '), $m[2]))
            $g = New-Object System.Windows.Controls.Grid
            $g.Margin = New-GuiThickness '0,2,0,2'
            $g.ColumnDefinitions.Add((New-GuiColumn '240')); $g.ColumnDefinitions.Add((New-GuiColumn '*'))
            $g.Children.Add((New-GuiText ([string]$m[1]) 13 'Text2' -Wrap)) | Out-Null
            $color = [string]$m[3]
            $v = New-GuiText ([string]$m[2]) 13 $(if ($color -and $color -ne 'Gray') { $color } else { 'Text' }) -Wrap -Margin '12,0,0,0'
            [System.Windows.Controls.Grid]::SetColumn($v, 1)
            $g.Children.Add($v) | Out-Null
            Add-GuiBlock $g
        }
        'line' {
            $text = ([string]$m[2]).Trim()
            [void]$script:GuiDocText.AppendLine($text)
            if (-not $text) { Add-GuiSpacer; return }
            switch ([string]$m[1]) {
                'step' { Add-GuiBlock (New-GuiText $text 13.5 'Text' 'SemiBold' -Wrap -Margin '0,10,0,3') }
                'ok'   { Add-GuiBlock (New-GuiText $text 13 'Good' -Wrap -Margin '0,1,0,1') }
                'info' { Add-GuiBlock (New-GuiText $text 13 'Text2' -Wrap -Margin '0,1,0,1') }
                default {
                    # warnings and problems: an icon too, so the meaning does not rest on the colour alone
                    $brush = $(if ($m[1] -eq 'bad') { 'Bad' } else { 'Warn' })
                    $sp = New-Object System.Windows.Controls.DockPanel
                    $sp.Margin = New-GuiThickness '0,3,0,3'
                    $icon = New-GuiIcon $(if ($m[1] -eq 'bad') { [string][char]0xEA39 } else { [string][char]0xE7BA }) 13 $brush
                    $icon.VerticalAlignment = 'Top'
                    $icon.Margin = New-GuiThickness '0,2,8,0'
                    $sp.Children.Add($icon) | Out-Null
                    $sp.Children.Add((New-GuiText $text 13 $brush -Wrap)) | Out-Null
                    Add-GuiBlock $sp
                }
            }
        }
        'option' {
            [void]$script:GuiDocText.AppendLine(('  {0}  {1}' -f $m[1], $m[2]))
            $b = New-Object System.Windows.Controls.Button
            $b.Style = $script:GuiWindow.FindResource('OptionBtn')
            $b.Tag = [string]$m[1]
            $g = New-Object System.Windows.Controls.Grid
            $g.ColumnDefinitions.Add((New-GuiColumn 'Auto')); $g.ColumnDefinitions.Add((New-GuiColumn '*'))
            $badge = New-Object System.Windows.Controls.Border
            $badge.Background = Get-GuiBrush 'AccentSoft'
            $badge.CornerRadius = 3
            $badge.MinWidth = 30; $badge.Height = 24
            $badge.Padding = New-GuiThickness '6,0'
            $k = New-GuiText ([string]$m[1]) 12.5 'Accent' 'Bold'
            $k.HorizontalAlignment = 'Center'; $k.VerticalAlignment = 'Center'
            $badge.Child = $k
            $g.Children.Add($badge) | Out-Null
            $t = New-GuiText ([string]$m[2]) 13 'Text' -Wrap -Margin '12,0,8,0'
            $t.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($t, 1)
            $g.Children.Add($t) | Out-Null
            $b.Content = $g
            $b.Add_Click({ param($s, $e) Invoke-GuiSafe 'choice' { if ($script:GuiAskKind -eq 'text' -and (Test-GuiAsking)) { Send-GuiAnswer "$($s.Tag)" } } })
            $script:GuiOptions.Add($b)
            Add-GuiBlock $b
        }
        'health' {
            [void]$script:GuiDocText.AppendLine(('{0}: {1}' -f ([string]$m[2]).TrimEnd(':', ' '), $m[3]))
            $look = @{ Good = @('Good', [string][char]0xE73E); Warn = @('Warn', [string][char]0xE7BA); Bad = @('Bad', [string][char]0xEA39); Info = @('Info', [string][char]0xE946) }
            $l = $look[[string]$m[1]]; if (-not $l) { $l = $look['Info'] }
            $g = New-Object System.Windows.Controls.Grid
            $g.Margin = New-GuiThickness '0,3,0,3'
            $g.ColumnDefinitions.Add((New-GuiColumn '28')); $g.ColumnDefinitions.Add((New-GuiColumn '212')); $g.ColumnDefinitions.Add((New-GuiColumn '*'))
            $g.Children.Add((New-GuiIcon $l[1] 13 $l[0])) | Out-Null
            $n = New-GuiText ([string]$m[2]) 13 'Text' 'SemiBold'
            [System.Windows.Controls.Grid]::SetColumn($n, 1)
            $g.Children.Add($n) | Out-Null
            $v = New-GuiText ([string]$m[3]) 13 'Text2' -Wrap
            [System.Windows.Controls.Grid]::SetColumn($v, 2)
            $g.Children.Add($v) | Out-Null
            Add-GuiBlock $g
        }
    }
}

function Add-GuiOutput([string]$Text, [string]$Color, [bool]$NoNewline) {
    Add-GuiDocMessage ([object[]]@('text', $Text, $Color, $NoNewline))
}

function Update-GuiOutputView {
    if ($script:Ui) { $script:Ui.RunScroll.ScrollToEnd() }
}

function Copy-GuiOutput {
    $text = $script:GuiDocText.ToString().Trim()
    if ($text) { [System.Windows.Clipboard]::SetText($text); $script:Ui.RunHint.Text = (L 'Copied.') }
}

function Show-GuiAsk([string]$Kind, [string]$Prompt, $Default) {
    # A question of the running option, under its text: a text box, Yes / No, or Continue.
    $ui = $script:Ui
    if ($script:GuiPage -ne 'Run') { Show-GuiPage 'Run' }
    $script:GuiAskKind = $Kind
    $script:GuiAskDefault = $Default
    $ui.RunAsk.Visibility = 'Visible'
    $ui.RunAskBox.Visibility = $(if ($Kind -eq 'text') { 'Visible' } else { 'Collapsed' })
    $ui.RunAskOk.Visibility = $(if ($Kind -eq 'text') { 'Visible' } else { 'Collapsed' })
    $ui.RunAskYes.Visibility = $(if ($Kind -eq 'yesno') { 'Visible' } else { 'Collapsed' })
    $ui.RunAskNo.Visibility = $(if ($Kind -eq 'yesno') { 'Visible' } else { 'Collapsed' })
    $ui.RunAskContinue.Visibility = $(if ($Kind -eq 'continue') { 'Visible' } else { 'Collapsed' })
    $text = ($Prompt -replace '^\[\?\]\s*', '').Trim()
    if ($Kind -eq 'continue') { $text = (L 'Read the result above, then continue.') }
    if ($Kind -eq 'text' -and $script:GuiOptions.Count -gt 0) { $text = (L 'Choose an option above, or type it here.') }
    if ($Kind -eq 'text' -and -not $text) { $text = (L 'Your answer') }
    $ui.RunAskText.Text = $text
    $ui.RunProgress.Visibility = 'Collapsed'
    $ui.RunState.Text = (L 'Your answer is needed below.')
    if ($Kind -eq 'yesno') {
        # the answer you get by just pressing Enter is the green one
        $accent = $script:GuiWindow.FindResource('AccentBtn')
        $plain = $script:GuiWindow.FindResource([System.Windows.Controls.Button])
        $ui.RunAskYes.Style = $(if ($Default) { $accent } else { $plain })
        $ui.RunAskNo.Style = $(if ($Default) { $plain } else { $accent })
        $ui.RunAskNo.Margin = New-GuiThickness '0,0,8,0'
        if ($Default) { [void]$ui.RunAskYes.Focus() } else { [void]$ui.RunAskNo.Focus() }
    } elseif ($Kind -eq 'text') {
        $ui.RunAskBox.Text = ''
        [void]$ui.RunAskBox.Focus()
    } else { [void]$ui.RunAskContinue.Focus() }
}

function Hide-GuiAsk { if ($script:Ui) { $script:Ui.RunAsk.Visibility = 'Collapsed' } }

function Test-GuiAsking { return [bool]($script:Ui -and $script:Ui.RunAsk.Visibility -eq 'Visible') }

function Send-GuiAnswer($Value) {
    if ($script:Ui.RunAsk.Visibility -ne 'Visible') { return }
    Hide-GuiAsk
    foreach ($b in $script:GuiOptions) { $b.IsEnabled = $false }   # those choices were for this question
    $script:GuiOptions.Clear()
    if ($script:GuiAskKind -eq 'text' -and "$Value") { Add-GuiDocMessage ([object[]]@('line', 'info', (L 'Your answer: {0}' "$Value"))); Update-GuiOutputView }
    $script:GuiShared.Answers.Add($Value)
}

function Update-GuiProgress {
    # Progress of the running job: id 0 = the steps of F or A, id 1 = the current step.
    $ui = $script:Ui
    if (Test-GuiAsking) { return }   # waiting for your answer: no progress to show
    $snap = @{}
    $prog = $script:GuiShared.Progress
    [System.Threading.Monitor]::Enter($prog.SyncRoot)
    try { foreach ($k in @($prog.Keys)) { $snap[$k] = $prog[$k] } } finally { [System.Threading.Monitor]::Exit($prog.SyncRoot) }
    $plan = $snap[0]; $step = $snap[1]
    if ($script:GuiCurrent.Output -and $script:GuiCurrent.Name -ne 'analysis') { $ui.RunProgress.Visibility = 'Visible' }
    if ($plan) {
        $ui.RunStep.Text = $plan[1]
        $ui.RunBar0.IsIndeterminate = $false
        $ui.RunBar0.Value = [math]::Max(0, $plan[2])
    } elseif ($step) {
        $ui.RunStep.Text = $step[0]
        $ui.RunBar0.IsIndeterminate = ($step[2] -lt 0)
        if ($step[2] -ge 0) { $ui.RunBar0.Value = $step[2] }
    }
    if ($plan -and $step) {
        $ui.RunBar1.Visibility = 'Visible'
        $ui.RunStatus.Text = ('{0}  {1}' -f $step[0], $step[1]).Trim()
        if ($step[2] -ge 0) { $ui.RunBar1.Value = $step[2] }
    } elseif ($step) {
        $ui.RunStatus.Text = $step[1]
        $ui.RunBar1.Visibility = 'Hidden'
    } else {
        $ui.RunStatus.Text = ''
        $ui.RunBar1.Visibility = 'Hidden'
    }
    $elapsed = $script:GuiCurrent.Clock.Elapsed
    if ($script:GuiCurrent.Output) {
        $ui.RunState.Text = (L 'Working... {0} min {1:00} s' ([int][math]::Floor($elapsed.TotalMinutes)) $elapsed.Seconds)
        if ($script:GuiShared.Stop) { $ui.RunState.Text = (L 'Stopping... (a Windows tool that is running finishes first)') }
    }
    if ($script:GuiCurrent.Name -eq 'analysis') {
        $ui.CleanBar.Value = $ui.RunBar0.Value
        $ui.CleanStatus.Text = $(if ($plan) { $plan[1] } else { L 'Analyzing - nothing will be deleted...' })
    }
    if ($script:GuiPage -ne 'Run' -and $script:GuiCurrent.Output) {
        $ui.BusyText.Text = $(if ($plan) { '{0} - {1}' -f $script:GuiCurrent.Title, $plan[1] } else { $script:GuiCurrent.Title })
    }
}

function Set-GuiEngineFailed([string]$Err) {
    $ui = $script:Ui
    $ui.HealthGrid.Children.Clear()
    $ui.HomeSub.Text = (L 'YSO could not start its engine: {0}' $Err)
    Write-YsoError -Context 'window: start the engine' -ErrorRecord (New-Object System.Management.Automation.ErrorRecord ((New-Object System.Exception $Err)), 'engine', 'NotSpecified', $null)
    Show-GuiDialog -Title (L 'YSO could not start') -Text (L 'The window opened, but the part that does the work did not start: {0}' $Err) -Yes (L 'Open the console') -No (L 'Close') -OnYes {
        Start-YsoConsole
        $script:GuiResult = 'closed'
        $script:GuiWindow.Close()
    }
}

# --- New version of YSO ---
function Start-GuiUpdateCheck {
    Add-GuiJob -Name 'version-check' -Script 'Get-YsoUpdateOffer' -OnDone {
        param($Out, $Err)
        Set-GuiUpdateOffer (@($Out | Where-Object { $_ -and $_.PSObject.Properties['Version'] }) | Select-Object -Last 1)
    }
}

function Set-GuiUpdateOffer($Release) {
    $script:GuiRelease = $Release
    $ui = $script:Ui
    if ($Release) {
        $ui.UpdateText.Text = $(if ($Release.PSObject.Properties['Build']) { L 'Install the fixes for YSO {0}' $Release.Version } else { L 'Update to YSO {0}' $Release.Version })
        $ui.UpdateBtn.ToolTip = (L 'A new version of YSO is published on GitHub.')
        $ui.UpdateBtn.Visibility = 'Visible'
    } else { $ui.UpdateBtn.Visibility = 'Collapsed' }
}

function Show-GuiUpdateDialog {
    $r = $script:GuiRelease
    if (-not $r) { return }
    if (Test-GuiBusy) { Show-GuiBusyMessage; return }
    $notes = $r.Notes
    if ($notes.Length -gt 700) { $notes = $notes.Substring(0, 700).TrimEnd() + ' ...' }
    $parts = @($(if ($r.PSObject.Properties['Build']) { L 'A corrected build of YSO {0} is published (same version, with fixes).' $r.Version } else { L 'Installed: {0}. New: {1}.' $script:Version $r.Version }))
    if ($notes) { $parts += $notes }
    $parts += (L 'YSO downloads it from GitHub, checks its SHA-256 checksum, then replaces itself. Your settings and history stay.')
    Show-GuiDialog -Title (L 'YSO {0} is available' $r.Version) -Text ($parts -join "`n`n") -Yes (L 'Update now') -No (L 'Later') -OnYes { Start-GuiSelfUpdate }
}

function Start-GuiSelfUpdate {
    $title = L 'Update YSO'
    Reset-GuiRun $title
    $script:GuiRunKey = 'U'
    Show-GuiPage 'Run' 'U'
    Add-GuiJob -Name 'self-update' -Output -Title $title -Arguments @($script:GuiRelease, $PSCommandPath) `
        -Script 'param($YsoGuiRelease, $YsoGuiTarget) Invoke-YsoSelfUpdate $YsoGuiRelease $YsoGuiTarget' `
        -OnDone { param($Out, $Err) Complete-GuiSelfUpdate $(if ($Out.Count -gt 0) { $Out[-1] } else { $null }) $Err }
    Update-GuiBusy
}

function Complete-GuiSelfUpdate($Data, [string]$Err) {
    $ok = [bool]($Data -and $Data.Updated)
    Set-GuiRunFinished $(if ($ok) { 'done' } else { 'failed' })
    if (-not $ok) { return }
    $v = $script:GuiRelease.Version
    Set-GuiUpdateOffer $null
    Show-GuiDialog -Title (L 'YSO {0} is installed' $v) -Text (L 'Restart YSO to use the new version.') -Yes (L 'Restart YSO') -No (L 'Later') -OnYes {
        $script:GuiResult = 'restart'
        $script:GuiWindow.Close()
    }
}

function Start-YsoAgain {
    # Opens YSO again (after an update), hidden from the start like the shortcut: no console window.
    $env:YSO_RESTART = '1'
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    if ($script:DryRun) { $a += '-DryRun' }
    try { Start-Process -FilePath $ps -ArgumentList $a -WindowStyle Hidden } finally { Remove-Item -LiteralPath 'env:YSO_RESTART' -ErrorAction SilentlyContinue }
}

# --- All tools ---
function Initialize-GuiTools {
    $panel = $script:Ui.ToolsPanel
    foreach ($grp in (Get-GuiToolGroups)) {
        $panel.Children.Add((New-GuiText (L $grp.Title) 12 'Text3' 'SemiBold' -Margin '2,18,0,10')) | Out-Null
        $wrap = New-Object System.Windows.Controls.WrapPanel
        foreach ($it in $grp.Items) {
            $b = New-Object System.Windows.Controls.Button
            $b.Style = $script:GuiWindow.FindResource('ToolBtn')
            $b.Tag = $it[0]
            $g = New-Object System.Windows.Controls.Grid
            $g.ColumnDefinitions.Add((New-GuiColumn 'Auto')); $g.ColumnDefinitions.Add((New-GuiColumn '*'))
            $badge = New-Object System.Windows.Controls.Border
            $badge.Background = Get-GuiBrush 'AccentSoft'
            $badge.CornerRadius = 3
            $badge.MinWidth = 34; $badge.Height = 28
            $badge.Padding = New-GuiThickness '6,0'
            $k = New-GuiText $it[0] 12.5 'Accent' 'Bold'
            $k.HorizontalAlignment = 'Center'; $k.VerticalAlignment = 'Center'
            $badge.Child = $k
            $g.Children.Add($badge) | Out-Null
            $t = New-GuiText (L $it[1]) 13 'Text' -Margin '12,0,0,0'
            $t.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($t, 1)
            $g.Children.Add($t) | Out-Null
            $b.Content = $g
            $b.ToolTip = L $it[1]
            $b.Add_Click({ param($s, $e) Invoke-GuiSafe 'tool' { Invoke-GuiAction "$($s.Tag)" } })
            $wrap.Children.Add($b) | Out-Null
        }
        $panel.Children.Add($wrap) | Out-Null
    }
}

# ------------------------------------------------------------------
#  The window
# ------------------------------------------------------------------
function ConvertTo-GuiXaml([string]$Xaml) {
    # Texts between double square brackets -> the text in the chosen language, escaped for XML.
    $out = New-Object System.Text.StringBuilder
    $last = 0
    foreach ($m in [regex]::Matches($Xaml, '\[\[(.+?)\]\]')) {
        [void]$out.Append($Xaml, $last, $m.Index - $last)
        [void]$out.Append([System.Security.SecurityElement]::Escape((L $m.Groups[1].Value)))
        $last = $m.Index + $m.Length
    }
    [void]$out.Append($Xaml.Substring($last))
    return $out.ToString()
}

function Start-YsoWindow([string]$Snapshot = '') {
    # Opens the window. Returns 'closed', 'unavailable' (no window on this PC: the console menu is used),
    # or for -Snapshot 'snapshot-failed'.
    try {
        if ([Environment]::OSVersion.Platform -ne 'Win32NT') { return 'unavailable' }
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
        if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'The window needs a single-threaded (STA) PowerShell.' }
    } catch {
        Write-YsoError -Context 'open the window' -ErrorRecord $_
        $script:GuiFailure = $_.Exception.Message
        return 'unavailable'
    }
    $mutex = $null
    if (-not $Snapshot) {
        $created = $false
        try { $mutex = [System.Threading.Mutex]::new($true, 'Global\YSO-Window', [ref]$created) } catch { $created = $true }
        if (-not $created -and $env:YSO_RESTART) {
            # restarted after an update: the previous window is closing
            try { $created = $mutex.WaitOne(20000) } catch [System.Threading.AbandonedMutexException] { $created = $true }
        }
        Remove-Item -LiteralPath 'env:YSO_RESTART' -ErrorAction SilentlyContinue
        if (-not $created) {
            [void][System.Windows.MessageBox]::Show((L 'YSO is already open.'), 'YSO', 'OK', 'Information')
            return 'closed'
        }
    }
    try {
        if (Initialize-YsoNative) { try { [void][YSO.Native]::SetCurrentProcessExplicitAppUserModelID('YSO.YourSystemOptimizer') } catch { } }
        do {
            $how = Show-YsoWindow -Snapshot $Snapshot
            if ($how -eq 'reload') { Import-Settings }   # the language changed: build the window again
        } while ($how -eq 'reload')
        if ($how -eq 'restart') { Start-YsoAgain; return 'closed' }   # after an update: the new version opens
        return $how
    } catch {
        Write-YsoError -Context 'the window' -ErrorRecord $_
        $script:GuiFailure = $_.Exception.Message
        if ($Snapshot) { return 'snapshot-failed' }
        return 'unavailable'
    } finally {
        if ($mutex) { try { $mutex.ReleaseMutex() } catch { }; $mutex.Dispose() }
    }
}

function Show-YsoWindow([string]$Snapshot = '') {
    $script:GuiResult = 'closed'
    $script:GuiErrors = 0
    $script:GuiBrushes = $null
    $script:GuiCurrent = $null
    $script:GuiJobs = New-Object System.Collections.Queue
    $script:GuiCloseWhenIdle = $false
    $script:GuiShared = New-GuiShared
    $script:GuiPage = 'Home'

    $window = [System.Windows.Markup.XamlReader]::Parse((ConvertTo-GuiXaml (Get-YsoXaml)))
    $script:GuiWindow = $window
    $ui = @{}
    foreach ($name in @('RootBorder', 'Logo', 'VersionText', 'UpdateBtn', 'UpdateText', 'NavHome', 'NavClean', 'NavUpdates', 'NavStartup', 'NavHealth', 'NavRestore', 'NavTools',
                        'NavHistory', 'NavSettings', 'BusyPill', 'BusyText', 'ModeBadge', 'BtnMin', 'BtnMax', 'BtnClose',
                        'PageHome', 'HomeSub', 'HomeAnalyze', 'HomeClean', 'HomeRefresh', 'HealthGrid',
                        'PageClean', 'CleanWarn', 'CleanWarnText', 'CleanList', 'CleanOptions', 'CleanTotal', 'CleanTotalLabel', 'CleanBar',
                        'CleanStatus', 'CleanDetails', 'CleanAnalyze', 'CleanRun',
                        'PageRun', 'RunTitle', 'RunState', 'RunProgress', 'RunStep', 'RunBar0', 'RunStatus', 'RunBar1', 'RunResult',
                        'RunResultIcon', 'RunResultBig', 'RunResultText', 'RunScroll', 'RunDoc', 'RunCopy', 'RunAsk', 'RunAskText', 'RunAskBox', 'RunAskNo', 'RunAskYes',
                        'RunAskOk', 'RunAskContinue', 'RunHint', 'RunStop', 'RunBack',
                        'PageTools', 'ToolsPanel', 'Overlay', 'DlgTitle', 'DlgText', 'DlgNo', 'DlgYes')) {
        $ui[$name] = $window.FindName($name)
        if (-not $ui[$name]) { throw "The window has no element named $name." }
    }
    $script:Ui = $ui

    $logo = New-YsoLogo 72
    $ui.Logo.Source = $logo
    $window.Icon = New-YsoLogo 64
    $ui.VersionText.Text = ('YSO {0}' -f $script:Version)
    if ($script:DryRun) { $ui.ModeBadge.Visibility = 'Visible' }
    Clear-GuiOutput
    Initialize-GuiClean
    Initialize-GuiTools

    # Title bar
    $ui.BtnMin.Add_Click({ $script:GuiWindow.WindowState = 'Minimized' })
    $ui.BtnMax.Add_Click({ $w = $script:GuiWindow; $w.WindowState = $(if ($w.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) })
    $ui.BtnClose.Add_Click({ $script:GuiWindow.Close() })
    $window.Add_StateChanged({
        # a maximized window without a frame goes 7 pixels past the screen edges
        $max = ($script:GuiWindow.WindowState -eq 'Maximized')
        $script:Ui.RootBorder.Margin = New-GuiThickness $(if ($max) { '7' } else { '0' })
        $script:Ui.BtnMax.Content = $(if ($max) { [string][char]0xE923 } else { [string][char]0xE922 })
    })
    $ui.BusyPill.Add_Click({ Show-GuiPage 'Run' })
    $ui.UpdateBtn.Add_Click({ Invoke-GuiSafe 'update' { Show-GuiUpdateDialog } })

    # Navigation
    $ui.NavHome.Add_Click({ Show-GuiPage 'Home' })
    $ui.NavClean.Add_Click({ Show-GuiPage 'Clean' })
    $ui.NavTools.Add_Click({ Show-GuiPage 'Tools' })
    foreach ($pair in @(@('NavUpdates', '28'), @('NavStartup', '17'), @('NavHealth', '19'), @('NavRestore', 'R'), @('NavHistory', 'H'), @('NavSettings', 'O'))) {
        $ui[$pair[0]].Tag = $pair[1]
        $ui[$pair[0]].Add_Click({ param($s, $e) Invoke-GuiSafe 'menu' { Start-GuiOption "$($s.Tag)" } })
    }

    # Home
    $ui.HomeAnalyze.Add_Click({ Invoke-GuiSafe 'analyze' { Show-GuiPage 'Clean'; Start-GuiAnalysis } })
    $ui.HomeClean.Add_Click({ Invoke-GuiSafe 'clean everything' { Start-GuiClean -Everything } })
    $ui.HomeRefresh.Add_Click({ Invoke-GuiSafe 'health' { if (-not $script:GuiCurrent -or $script:GuiCurrent.Name -ne 'health') { Start-GuiHealth } } })

    # Clean
    $ui.CleanAnalyze.Add_Click({ Invoke-GuiSafe 'analyze' { Start-GuiAnalysis } })
    $ui.CleanRun.Add_Click({ Invoke-GuiSafe 'clean' { Start-GuiClean } })
    $ui.CleanDetails.Add_Click({ Show-GuiPage 'Run' })

    # Run page
    $ui.RunStop.Add_Click({ Invoke-GuiSafe 'stop' { Stop-GuiJob } })
    $ui.RunBack.Add_Click({ Show-GuiPage $(if ($script:Ui.RunTitle.Text -eq (L 'Analyze')) { 'Clean' } else { 'Home' }) })
    $ui.RunAskYes.Add_Click({ Send-GuiAnswer $true })
    $ui.RunAskNo.Add_Click({ Send-GuiAnswer $false })
    $ui.RunAskContinue.Add_Click({ Send-GuiAnswer '' })
    $ui.RunAskOk.Add_Click({ Send-GuiAnswer $script:Ui.RunAskBox.Text })
    $ui.RunCopy.Add_Click({ Invoke-GuiSafe 'copy' { Copy-GuiOutput } })
    $ui.RunAskBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Send-GuiAnswer $script:Ui.RunAskBox.Text; $e.Handled = $true } })

    # Dialog
    $ui.DlgYes.Add_Click({ Invoke-GuiSafe 'dialog' { Close-GuiDialog $true } })
    $ui.DlgNo.Add_Click({ Close-GuiDialog $false })
    $window.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq 'Escape' -and $script:Ui.Overlay.Visibility -eq 'Visible') { Close-GuiDialog $false; $e.Handled = $true }
    })

    # Closing while a job runs: ask, stop it, then close
    $window.Add_Closing({
        param($s, $e)
        if ($script:GuiResult -eq 'reload' -or $script:GuiCloseWhenIdle -or -not (Test-GuiBusy)) { return }
        $e.Cancel = $true
        Show-GuiDialog -Title (L 'A task is still running') -Text (L '"{0}" is not finished. Stop it and close YSO?' (Get-GuiBusyTitle)) -Yes (L 'Stop and close') -No (L 'Keep running') -OnYes {
            $script:GuiCloseWhenIdle = $true
            Stop-GuiJob
        }
    })

    # The second PowerShell, then the health of the PC
    Start-GuiWorker -ScriptPath $PSCommandPath -Shared $script:GuiShared -DryRunMode ([bool]$script:DryRun)
    Start-GuiHealth
    Start-GuiUpdateCheck
    if ($Snapshot) { Initialize-GuiSnapshot $Snapshot }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(66)
    $timer.Add_Tick({ Invoke-GuiSafe 'tick' { Invoke-GuiTick } })
    # The console YSO was started from is hidden while the window is open (and shown again after).
    $script:GuiHidConsole = $false
    if (-not $Snapshot -and (Test-ConsoleVisible) -and [Environment]::OSVersion.Platform -eq 'Win32NT') { $script:GuiHidConsole = $true }
    $window.Add_Loaded({ if ($script:GuiHidConsole) { Show-ConsoleWindow -Hide } })
    $timer.Start()
    try {
        [void]$window.ShowDialog()
    } finally {
        $timer.Stop()
        Stop-GuiWorker
        if ($script:GuiHidConsole) { Show-ConsoleWindow }
    }
    if ($Snapshot -and $script:GuiSnapFailed) { return 'snapshot-failed' }
    return $script:GuiResult
}

function Stop-GuiWorker {
    # Never waits: a job still running is asked to stop, and the process ends right after the window.
    $script:GuiShared.Stop = $true
    if ($script:GuiCurrent) {
        try { [void]$script:GuiCurrent.PS.BeginStop($null, $null) } catch { }
        $script:GuiCurrent = $null
    } elseif ($script:GuiWorker) {
        try { $script:GuiWorker.Dispose() } catch { }
    }
    $script:GuiWorker = $null
}

# ------------------------------------------------------------------
#  Snapshots: every page drawn into PNG files (automated tests on real Windows)
# ------------------------------------------------------------------
function Save-GuiPng([string]$Name) {
    $w = $script:GuiWindow
    $w.UpdateLayout()
    $root = $w.Content
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$root.ActualWidth), ([int]$root.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($root)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [System.IO.File]::Create((Join-Path $script:GuiSnapDir ($Name + '.png')))
    try { $enc.Save($fs) } finally { $fs.Close() }
}

function Initialize-GuiSnapshot([string]$Dir) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $script:GuiSnapDir = $Dir
    $script:GuiSnapFailed = $false
    $script:GuiSnapClock = [System.Diagnostics.Stopwatch]::StartNew()
    $script:GuiSnapWait = $null
    # each step returns $true when it is done; the next one starts at the following tick
    $script:GuiSnapSteps = New-Object System.Collections.Queue
    foreach ($s in @(
        { -not $script:GuiCurrent -and $script:GuiJobs.Count -eq 0 },                       # the engine and the health check are done
        { Save-GuiPng '1-home'; $true },
        { Show-GuiPage 'Tools'; $true },
        { Save-GuiPng '2-tools'; $true },
        { Show-GuiPage 'Clean'; Start-GuiAnalysis; $true },
        { $script:Ui.CleanBar.Value -gt 0 -or -not $script:GuiCurrent },
        { Save-GuiPng '3-clean-analyzing'; $true },
        { -not $script:GuiCurrent -and $script:GuiJobs.Count -eq 0 },
        { Save-GuiPng '4-clean-analyzed'; $true },
        { Show-GuiPage 'Run'; $true },
        { Save-GuiPng '5-analysis-details'; $true },
        { Start-GuiOption 'H'; $true },
        { -not $script:GuiCurrent -and $script:GuiJobs.Count -eq 0 },
        { Save-GuiPng '6-history'; $true },
        { Start-GuiOption 'R'; $true },
        { $script:Ui.RunAsk.Visibility -eq 'Visible' -or -not $script:GuiCurrent },
        { Save-GuiPng '7-question'; $true },
        { if ($script:GuiCurrent) { Send-GuiAnswer '0' }; $true },
        { -not $script:GuiCurrent -and $script:GuiJobs.Count -eq 0 },
        { Show-GuiPage 'Home'; Start-GuiClean -Everything; $true },
        { Save-GuiPng '8-dialog'; Close-GuiDialog $false; $true },
        { $script:GuiWindow.Close(); $true }
    )) { $script:GuiSnapSteps.Enqueue($s) }
}

function Invoke-GuiSnapshotStep {
    if ($script:GuiSnapClock.Elapsed.TotalMinutes -gt 8) {
        $script:GuiSnapFailed = $true
        Write-YsoError -Context 'window snapshot' -ErrorRecord (New-Object System.Management.Automation.ErrorRecord ((New-Object System.TimeoutException 'The snapshot took more than 8 minutes.')), 'snapshot', 'OperationTimeout', $null)
        $script:GuiSnapSteps = $null
        $script:GuiWindow.Close()
        return
    }
    if ($script:GuiSnapSteps.Count -eq 0) { $script:GuiSnapSteps = $null; return }
    $done = $false
    $step = $script:GuiSnapSteps.Peek()
    try { $done = [bool](& $step) }
    catch {
        $script:GuiSnapFailed = $true
        Write-YsoError -Context 'window snapshot' -ErrorRecord $_
        $done = $true
    }
    if ($done -and $script:GuiSnapSteps) { [void]$script:GuiSnapSteps.Dequeue() }
}

# ==================================================================
#  Install & uninstall: YSO like any program (Program Files, Start menu,
#  Desktop, Installed apps). install.ps1 downloads YSO and runs -Install.
# ==================================================================
function Test-YsoInstalled { return [bool](Test-Path -LiteralPath $script:UninstallKey) }

function Get-YsoShortcutPaths {
    $start = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\YSO.lnk'
    $desktop = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'YSO.lnk'
    return @($start, $desktop)
}

function Test-HeadlessConsole {
    # "conhost --headless" starts a program with no console window at all - not even for a moment.
    # Windows 10 1809 and later; older versions show a console window that hides itself instead.
    # Checked by what it does (it writes a file), not by its exit code: conhost does not pass that on.
    $flag = Join-Path ([System.IO.Path]::GetTempPath()) ('yso-headless-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
        if (-not (Test-Path -LiteralPath $conhost)) { return $false }
        $p = Start-Process -FilePath $conhost -ArgumentList '--headless', 'cmd.exe', '/c', "echo ok>`"$flag`"" -PassThru -WindowStyle Hidden -ErrorAction Stop
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $flag) -and $clock.ElapsedMilliseconds -lt 15000) { Start-Sleep -Milliseconds 200 }
        if (-not $p.HasExited) { try { [void]$p.WaitForExit(3000) } catch { } }
        return (Test-Path -LiteralPath $flag)
    } catch { return $false }
    finally { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
}

function Get-YsoLaunchCommand([string]$Target, [bool]$Headless) {
    # What the shortcuts start: the window, without a console window.
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Target`""
    if ($Headless) { return [pscustomobject]@{ File = (Join-Path $env:WINDIR 'System32\conhost.exe'); Arguments = "--headless `"$ps`" $psArgs" } }
    return [pscustomobject]@{ File = $ps; Arguments = $psArgs }
}

function New-YsoShortcut([string]$Path, $Command, [string]$Icon) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = $Command.File
    $lnk.Arguments = $Command.Arguments
    $lnk.WorkingDirectory = $script:InstallDir
    $lnk.Description = 'YSO - Your System Optimizer'
    $lnk.WindowStyle = 7   # minimized: if a console shows up at all, it is not in the way
    if ($Icon -and (Test-Path -LiteralPath $Icon)) { $lnk.IconLocation = "$Icon,0" }
    $lnk.Save()
}

function Install-Yso {
    Write-Section 'INSTALL YSO'
    if (-not $PSCommandPath) { Write-Bad 'Start YSO from its file to install it.'; return $false }
    try {
        $target = Install-YsoCopy
        Write-Ok (L 'Copied to {0}' $target)
        $icon = Join-Path $script:InstallDir 'YSO.ico'
        try {
            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
            Save-YsoIcon $icon
        } catch { $icon = '' }
        $command = Get-YsoLaunchCommand $target (Test-HeadlessConsole)
        foreach ($lnk in (Get-YsoShortcutPaths)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $lnk) -Force | Out-Null
            New-YsoShortcut $lnk $command $icon
        }
        Write-Ok 'Shortcuts created: Start menu and Desktop.'
        $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $size = [int]([math]::Ceiling((Get-Item -LiteralPath $target).Length / 1KB))
        New-Item -Path $script:UninstallKey -Force | Out-Null
        $values = [ordered]@{
            DisplayName     = 'YSO - Your System Optimizer'
            DisplayVersion  = $script:Version
            Publisher       = 'YSO (open source)'
            InstallLocation = $script:InstallDir
            UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$target`" -Uninstall"
            URLInfoAbout    = $script:ProjectUrl
            HelpLink        = $script:ProjectUrl + '/issues'
            InstallDate     = (Get-Date -Format 'yyyyMMdd')
        }
        if ($icon) { $values.DisplayIcon = $icon }
        foreach ($k in $values.Keys) { Set-ItemProperty -Path $script:UninstallKey -Name $k -Value $values[$k] }
        foreach ($k in @('NoModify', 'NoRepair')) { New-ItemProperty -Path $script:UninstallKey -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
        New-ItemProperty -Path $script:UninstallKey -Name 'EstimatedSize' -Value $size -PropertyType DWord -Force | Out-Null
        Write-Ok 'YSO is installed: Start menu, Desktop, and Settings > Apps > Installed apps (to uninstall it).'
        return $true
    } catch {
        Write-YsoError -Context 'install' -ErrorRecord $_
        Write-Bad (L 'The installation failed: {0}' $_.Exception.Message)
        return $false
    }
}

function Start-YsoInstalled {
    # Opens the installed YSO, like its shortcut does (hidden from the start: no console window).
    if ($env:YSO_UNATTENDED) { return }
    try {
        $c = Get-YsoLaunchCommand (Join-Path $script:InstallDir 'YSO.ps1') $false
        Start-Process -FilePath $c.File -ArgumentList $c.Arguments -WindowStyle Hidden
    } catch { }
}

function Confirm-Box([string]$Question, [bool]$Default) {
    # Yes / No in a Windows message box when possible (Uninstall may start without a console).
    # YSO_UNATTENDED (automated tests): the default answer, nothing is shown.
    if ($env:YSO_UNATTENDED) { return $Default }
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        $r = [System.Windows.MessageBox]::Show((L $Question), 'YSO', 'YesNo', 'Question', $(if ($Default) { 'Yes' } else { 'No' }))
        return ("$r" -eq 'Yes')
    } catch { return (Confirm-Action $Question $Default) }
}

function Uninstall-Yso {
    Write-Section 'UNINSTALL YSO'
    if (-not (Confirm-Box 'Uninstall YSO? Its weekly cleanup and automatic updates stop too.' $true)) { Write-Info 'Nothing was changed.'; return $false }
    try {
        foreach ($t in @($script:TaskName, $script:UpdateTaskName)) {
            if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }
        }
        foreach ($lnk in (Get-YsoShortcutPaths)) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue }
        Remove-Item -Path $script:UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
        $keep = Confirm-Box (L 'Keep the history, logs and settings of YSO ({0})? They are useful if you install it again.' $script:DataDir) $true
        try { Stop-Transcript | Out-Null } catch { }
        if (-not $keep) { Remove-Item -LiteralPath $script:DataDir -Recurse -Force -ErrorAction SilentlyContinue }
        # This file is in the folder removed below: PowerShell already read it, so it can go.
        Remove-Item -LiteralPath $script:InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        try {
            if ($env:YSO_UNATTENDED) { throw 'no message box' }
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            [void][System.Windows.MessageBox]::Show((L 'YSO was uninstalled.'), 'YSO', 'OK', 'Information')
        } catch { Write-Ok 'YSO was uninstalled.' }
        return $true
    } catch {
        Write-YsoError -Context 'uninstall' -ErrorRecord $_
        Write-Bad (L 'Uninstalling failed: {0}' $_.Exception.Message)
        return $false
    }
}

# ==================================================================
#  New versions of YSO: published as GitHub Releases (by the CI, when the version changes on main).
#  The window asks GitHub once an hour at most; the update is downloaded, checked against its
#  SHA-256 file, read by PowerShell, and only then replaces YSO.
# ==================================================================
function Enable-Tls12 {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Get-YsoWebBytes([string]$Url, [int]$MaxBytes = 5MB) {
    # HTTPS only, from GitHub only, and never more than $MaxBytes.
    if ($Url -notmatch '^https://(api\.github\.com|github\.com|objects\.githubusercontent\.com|release-assets\.githubusercontent\.com)/') { throw "Refused address: $Url" }
    Enable-Tls12
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = "YSO/$($script:Version)"
    $req.Accept = 'application/octet-stream, application/vnd.github+json'
    $req.Timeout = 30000
    $req.AllowAutoRedirect = $true
    $resp = $req.GetResponse()
    try {
        if ($resp.ResponseUri.Scheme -ne 'https') { throw 'The download was redirected outside HTTPS.' }
        $in = $resp.GetResponseStream()
        $ms = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 65536
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $ms.Write($buf, 0, $n)
            if ($ms.Length -gt $MaxBytes) { throw 'The download is larger than expected.' }
        }
        return , $ms.ToArray()
    } finally { $resp.Close() }
}

function ConvertFrom-YsoRelease($Release) {
    # Keeps only what YSO needs from GitHub's answer, after checking it: a version tag, the two files
    # (YSO.ps1 and its SHA-256) on this project's release page, and the notes as plain text.
    if (-not $Release -or $Release.draft -or $Release.prerelease) { return $null }
    $m = [regex]::Match("$($Release.tag_name)", '^v?(\d{1,4}(\.\d{1,4}){1,3})$')
    if (-not $m.Success) { return $null }
    $prefix = "https://github.com/$($script:ReleaseRepo)/releases/download/"
    $file = @(@($Release.assets) | Where-Object { "$($_.name)" -eq 'YSO.ps1' -and "$($_.browser_download_url)".StartsWith($prefix) }) | Select-Object -First 1
    $sum = @(@($Release.assets) | Where-Object { "$($_.name)" -eq 'YSO.ps1.sha256' -and "$($_.browser_download_url)".StartsWith($prefix) }) | Select-Object -First 1
    if (-not $file -or -not $sum -or [long]$file.size -gt 5MB) { return $null }
    $notes = ("$($Release.body)" -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '' -replace '\r', '').Trim()
    if ($notes.Length -gt 1500) { $notes = $notes.Substring(0, 1500).TrimEnd() + ' ...' }
    $page = "$($Release.html_url)"
    if (-not $page.StartsWith("https://github.com/$($script:ReleaseRepo)/releases/")) { $page = $script:ProjectUrl + '/releases' }
    return [pscustomobject]@{
        Version = [version]$m.Groups[1].Value; Tag = "$($Release.tag_name)"; Notes = $notes; Page = $page
        Url = "$($file.browser_download_url)"; SumUrl = "$($sum.browser_download_url)"
    }
}

function Get-YsoFileHash {
    # SHA-256 of this YSO.ps1, to tell a corrected build of the same version from this one.
    try { if ($script:SelfPath -and (Test-Path -LiteralPath $script:SelfPath)) { return (Get-FileHash -LiteralPath $script:SelfPath -Algorithm SHA256).Hash.ToLowerInvariant() } } catch { }
    return ''
}

function Get-YsoUpdateOffer([switch]$Force) {
    # The YSO to offer, or $null: a newer version, or a corrected build of this version (its file
    # differs from this one). Asks GitHub at most once an hour; the answer is kept meanwhile.
    if (-not $script:Settings.CheckForUpdates -and -not $Force) { return $null }
    $release = $null
    $sum = ''
    $fresh = $false
    if (-not $Force -and (Test-Path -LiteralPath $script:UpdateCheckPath)) {
        try {
            $c = Get-Content -LiteralPath $script:UpdateCheckPath -Raw | ConvertFrom-Json
            $when = [datetime]::ParseExact("$($c.Checked)", 'yyyyMMddHHmmss', [System.Globalization.CultureInfo]::InvariantCulture)   # no dashes: PowerShell 7 would turn it into a date
            if (((Get-Date) - $when).TotalMinutes -lt 60 -and ((Get-Date) - $when).TotalMinutes -ge 0) {
                $fresh = $true
                if ($c.Release) { $release = ConvertFrom-YsoRelease $c.Release }
                if ("$($c.Sum)" -match '^[0-9a-f]{64}$') { $sum = "$($c.Sum)" }
            }
        } catch { }
    }
    if (-not $fresh) {
        $raw = $null
        try {
            $bytes = Get-YsoWebBytes "https://api.github.com/repos/$($script:ReleaseRepo)/releases/latest" 2MB
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
        } catch {
            # no internet, GitHub down, or no release yet: nothing to offer, YSO works as usual
            if ("$($_.Exception.Message)" -notmatch '404') { return $null }
        }
        $release = ConvertFrom-YsoRelease $raw
        if ($release -and $release.Version -eq [version]$script:Version) {
            # same version: the SHA-256 of the published file tells whether it is another build
            try { $sum = [regex]::Match([System.Text.Encoding]::ASCII.GetString((Get-YsoWebBytes $release.SumUrl 4KB)), '\b[0-9a-fA-F]{64}\b').Value.ToLowerInvariant() } catch { $sum = '' }
        }
        try {
            New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
            $keep = $null
            if ($release) {
                $keep = [ordered]@{ tag_name = $release.Tag; body = $release.Notes; html_url = $release.Page; draft = $false; prerelease = $false
                    assets = @([ordered]@{ name = 'YSO.ps1'; browser_download_url = $release.Url; size = 0 }, [ordered]@{ name = 'YSO.ps1.sha256'; browser_download_url = $release.SumUrl; size = 0 }) }
            }
            [ordered]@{ Checked = (Get-Date).ToString('yyyyMMddHHmmss', [System.Globalization.CultureInfo]::InvariantCulture); Release = $keep; Sum = $sum } |
                ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:UpdateCheckPath -Encoding UTF8
        } catch { }
    }
    if (-not $release) { return $null }
    if ($release.Version -gt [version]$script:Version) { return $release }
    if ($release.Version -eq [version]$script:Version -and $sum) {
        $own = Get-YsoFileHash
        if ($own -and $own -ne $sum) {
            $release | Add-Member -NotePropertyName Build -NotePropertyValue $true -Force
            return $release
        }
    }
    return $null
}

function Test-YsoScriptText([string]$Text, [version]$Version) {
    # A complete YSO of that version: PowerShell reads it without errors, and it can update itself.
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)
    if (@($errors).Count -gt 0) { return $false }
    $m = [regex]::Match($Text, "\`$script:Version\s*=\s*'([\d\.]+)'")
    if (-not $m.Success -or [version]$m.Groups[1].Value -ne $Version) { return $false }
    return ($Text -match '\$script:ReleaseRepo\s*=' -and $Text -match 'function Install-YsoUpdate\s*\{')
}

function Invoke-YsoSelfUpdate($Release, [string]$Target) {
    # The window's Update button: Install-YsoUpdate, with any error saved and shown.
    $ok = $false
    try { $ok = Install-YsoUpdate -Release $Release -Target $Target }
    catch {
        Write-YsoError -Context 'update YSO' -ErrorRecord $_
        Write-Bad (L 'The update failed: {0}' $_.Exception.Message)
    }
    return [pscustomobject]@{ Updated = [bool]$ok }
}

function Install-YsoUpdate {
    # Replaces $Target with the YSO of $Release. Returns $true when done; anything wrong leaves YSO as it was.
    param($Release, [string]$Target)
    Write-Step (L 'Downloading YSO {0} from GitHub...' $Release.Version)
    $bytes = Get-YsoWebBytes $Release.Url 5MB
    $sumText = [System.Text.Encoding]::ASCII.GetString((Get-YsoWebBytes $Release.SumUrl 4KB))
    $expected = [regex]::Match($sumText, '\b[0-9a-fA-F]{64}\b').Value.ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $actual = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    if (-not $expected -or $expected -ne $actual) {
        Write-Bad 'The download does not match its SHA-256 checksum: nothing was changed.'
        return $false
    }
    Write-Ok (L 'Checksum verified (SHA-256 {0}...).' $actual.Substring(0, 16))
    $text = (New-Object System.Text.UTF8Encoding($false)).GetString($bytes).TrimStart([char]0xFEFF)
    if (-not (Test-YsoScriptText $text $Release.Version)) {
        Write-Bad 'The downloaded file is not a complete YSO of that version: nothing was changed.'
        return $false
    }
    $new = $Target + '.new'
    $old = $Target + '.old'
    [System.IO.File]::WriteAllBytes($new, $bytes)
    try {
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
        [System.IO.File]::Replace($new, $Target, $old)
    } catch {
        Remove-Item -LiteralPath $new -Force -ErrorAction SilentlyContinue
        throw
    }
    Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
    # the copy used by scheduled tasks (when YSO runs from another place)
    Update-YsoCopy -Source $Target
    if (Test-YsoInstalled) { try { Set-ItemProperty -Path $script:UninstallKey -Name 'DisplayVersion' -Value "$($Release.Version)" } catch { } }
    Remove-Item -LiteralPath $script:UpdateCheckPath -Force -ErrorAction SilentlyContinue
    Write-Ok (L 'YSO {0} is installed.' $Release.Version)
    return $true
}

# ==================================================================
#  French interface
# ==================================================================
function Get-FrenchStrings {
    # One line per text:  English ==> French.  Case matters ("SUMMARY" is a heading,
    # "Summary" would be something else), so lookups are exact.
    $pairs = @'
(newest) ==> (le plus récent)
(not signed) ==> (non signé)
+{0:N1} s at boot ==> +{0:N1} s au démarrage
- can break some VPN or proxy software until it is reconfigured ==> - peut perturber certains VPN ou proxys jusqu'à leur reconfiguration
- erases manually set (static) IP / DNS settings ==> - efface les réglages IP / DNS saisis à la main (statiques)
- needs a restart to finish ==> - nécessite un redémarrage pour se terminer
- use Restart (not Shut down) once in a while ==> - utilisez Redémarrer (pas Arrêter) de temps en temps
(files directly in this folder) ==> (fichiers placés directement dans ce dossier)
(none) ==> (aucun)
(nothing) ==> (rien)
(Windows {0:N1} s + desktop {1:N1} s) ==> (Windows {0:N1} s + bureau {1:N1} s)
[number] open folder   [B] back   [F] biggest files   [E] show in Explorer   [Q] done ==> [numéro] ouvrir le dossier   [B] retour   [F] plus gros fichiers   [E] voir dans l'Explorateur   [Q] terminer
[Y/n] ==> [O/n]
[y/N] ==> [o/N]
a component it needs is missing ==> un composant nécessaire est absent
a drive reports a failure - back up your files now ==> un disque signale une panne - sauvegardez vos fichiers maintenant
a drive reports a warning ==> un disque signale un avertissement
a file {0} characters deep was not removed ==> un fichier à {0} caractères de profondeur n'a pas été supprimé
A restore point takes Windows, its settings and your programs back to an earlier state. Your documents are not touched. ==> Un point de restauration ramène Windows, ses réglages et vos programmes à un état antérieur. Vos documents ne sont pas touchés.
access denied ==> accès refusé
all drivers ==> tous les pilotes
All options ==> Toutes les options
Also install app and driver updates? (like automatic updates: never open apps, adds 5-30 min) ==> Installer aussi les mises à jour d'applis et de pilotes ? (comme en automatique : jamais les applis ouvertes, 5 à 30 min de plus)
Also new major versions of apps (can change how they work) ==> Aussi les nouvelles versions majeures d'applis (peuvent changer leur fonctionnement)
ALSO NEWER, BUT NOT UPDATED BY YSO ==> AUSSI PLUS RÉCENTES, MAIS PAS MISES À JOUR PAR YSO
Also optional drivers (not recommended) ==> Aussi les pilotes facultatifs (déconseillé)
Also remove these old driver versions? You will not be able to go back to them. ==> Supprimer aussi ces anciennes versions de pilotes ? Vous ne pourrez plus y revenir.
Analyze ==> Analyse
Analyze: what can be freed (deletes nothing) ==> Analyser : ce qui peut être libéré (ne supprime rien)
another installation is running - try again later ==> une autre installation est en cours - réessayez plus tard
App Id to add (like Git.Git, * = any text), number to remove, R = defaults, Enter = done ==> Id d'appli à ajouter (comme Git.Git, * = n'importe quel texte), numéro pour retirer, R = par défaut, Entrée = terminé
App updates ==> Mises à jour d'applis
APP UPDATES (winget) ==> MISES À JOUR D'APPLIS (winget)
apps ==> applis
Apps (winget) ==> Applis (winget)
Apps from the Microsoft Store manage their own startup: S opens Windows Settings. ==> Les applis du Microsoft Store gèrent leur propre démarrage : S ouvre les Paramètres Windows.
Apps never updated automatically ==> Applis jamais mises à jour automatiquement
AT A GLANCE ==> EN UN COUP D'ŒIL
AUTO ==> AUTO
AUTOMATIC ==> AUTOMATIQUE
Automatic - install on schedule (safe updates only) ==> Automatique - installer selon le planning (mises à jour sûres seulement)
Automatic updates (28) ==> Mises à jour automatiques (28)
Automatic updates install ==> Installé automatiquement
Automatic updates now follow this schedule. ==> Les mises à jour automatiques suivent maintenant ce planning.
Battery ==> Batterie
Best: Restart (not Shut down), then run F again. ==> Le mieux : Redémarrer (pas Arrêter), puis relancer F.
BIOS and some drivers for this PC come from {0}: use {1}. YSO never updates the BIOS. ==> Le BIOS et certains pilotes de ce PC viennent de {0} : utilisez {1}. YSO ne met jamais le BIOS à jour.
blocked by your organization ==> bloqué par votre organisation
cancelled ==> annulé
Check for updates now (you choose what to install) ==> Chercher les mises à jour maintenant (vous choisissez quoi installer)
Check only: nothing was installed ({0} update(s) would be). ==> Vérification seule : rien n'a été installé ({0} mise(s) à jour à installer).
Checking your PC... ==> Vérification de votre PC...
Clean everything (full maintenance) ==> Tout nettoyer (entretien complet)
Cleaning ==> Nettoyage
closes {0} (nothing is lost) ==> ferme {0} (rien n'est perdu)
closes {0} (your tabs come back when you reopen it) ==> ferme {0} (vos onglets reviennent à la réouverture)
Closing apps ==> Fermeture des applis
Complete clean (recommended - frees the most): ==> Nettoyage complet (recommandé - libère le plus) :
Complete clean? ==> Nettoyage complet ?
Component store ==> Magasin de composants
Continue? ==> Continuer ?
could not be identified (its name is cut off in winget) ==> impossible à identifier (son nom est coupé dans winget)
Could not change it: {0} ==> Impossible de le modifier : {0}
could not read the list printed by winget ==> impossible de lire la liste affichée par winget
Create a restore point before installing drivers? (recommended) ==> Créer un point de restauration avant d'installer les pilotes ? (recommandé)
Create a restore point now ==> Créer un point de restauration maintenant
deep clean: Windows Disk Cleanup + component store (adds 10-30 min) ==> nettoyage approfondi : Nettoyage de disque Windows + magasin de composants (10 à 30 min de plus)
Delete the {0} older one(s), keep the newest ==> Supprimer les {0} plus ancien(s), garder le plus récent
Delete {0} restore point(s)? Only the newest stays - you cannot go back further than it. ==> Supprimer {0} point(s) de restauration ? Seul le plus récent reste - impossible de revenir plus loin.
Disk health ==> Santé du disque
Disk space ==> Espace disque
DNS cache ==> Cache DNS
Downloading and installing {0} driver(s) with Windows Update... ==> Téléchargement et installation de {0} pilote(s) avec Windows Update...
Driver updates ==> Mises à jour de pilotes
DRIVER UPDATES (Windows Update) ==> MISES À JOUR DE PILOTES (Windows Update)
Driver updates with Windows Update (28) ==> Pilotes avec Windows Update (28)
driver {0} ({1}) ==> pilote {0} ({1})
Drivers from Windows Update ==> Pilotes de Windows Update
error {0} ==> erreur {0}
Every day ==> Tous les jours
every day at {0} ==> tous les jours à {0}
Every week ==> Toutes les semaines
every {0} at {1} ==> chaque {0} à {1}
everyone ==> tous
Everything is up to date. ==> Tout est à jour.
Excluded apps still show up in 28 > 1, where you can update them yourself. ==> Les applis exclues apparaissent quand même dans 28 > 1, où vous pouvez les mettre à jour vous-même.
Files deeper than 260 characters ==> Fichiers à plus de 260 caractères de profondeur
GPU shader caches (games may stutter briefly the first time) ==> caches de shaders GPU (les jeux peuvent saccader brièvement la première fois)
healthy ==> en bonne santé
healthy (wear {0} %) ==> en bonne santé (usure {0} %)
Hibernation file: {0} ==> Fichier de mise en veille prolongée : {0}
Ignored: {0} ==> Ignoré : {0}
installed ==> installée
installed - restart the PC to finish ==> installée - redémarrez le PC pour terminer
Installing - this can take a while. Your PC will not be restarted. ==> Installation - cela peut prendre un moment. Votre PC ne sera pas redémarré.
It never restarts the PC: when an update needs a restart, a notification tells you. ==> Elles ne redémarrent jamais le PC : quand une mise à jour demande un redémarrage, une notification vous prévient.
It only checks: a notification tells you when updates are available. Nothing is installed until you choose (28 > 1). ==> Il vérifie seulement : une notification vous prévient quand des mises à jour sont disponibles. Rien n'est installé tant que vous ne choisissez pas (28 > 1).
It updates: {0}. Never: apps you excluded, apps that are open at that moment. ==> Elles installent : {0}. Jamais : les applis que vous avez exclues, ni celles ouvertes à ce moment-là.
its installer cannot update it - update it from the app itself ==> son installateur ne peut pas la mettre à jour - faites-le depuis l'appli elle-même
Last check ==> Dernière vérification
last cleanup {0} ==> dernier nettoyage {0}
Last run ==> Dernière exécution
Last update installed ==> Dernière mise à jour
last update installed {0} ==> dernière mise à jour installée {0}
last {0} ==> dernier : {0}
Looking for app updates (winget)... ==> Recherche des mises à jour d'applis (winget)...
Looking for driver updates (Windows Update - can take a few minutes)... ==> Recherche des mises à jour de pilotes (Windows Update - peut prendre quelques minutes)...
Looking for old driver versions... ==> Recherche des anciennes versions de pilotes...
Looking for other app caches ==> Recherche des caches d'autres applis
MANUAL ==> MANUEL
manual - never checked with YSO ==> manuel - jamais vérifiées avec YSO
Manual - only when I start it ==> Manuel - seulement quand je le lance
MANUAL - only when you start it (1) ==> MANUEL - seulement quand vous le lancez (1)
manual, last check {0} ==> manuel, dernière vérification {0}
Manual: updates are checked and installed only when you start them (28 > 1). ==> Manuel : les mises à jour ne sont vérifiées et installées que quand vous les lancez (28 > 1).
Microsoft Defender on ==> Microsoft Defender activé
Microsoft Defender on, definitions {0} days old ==> Microsoft Defender activé, définitions vieilles de {0} jours
Mode ==> Mode
Mode: manual, notify me, or automatic ==> Mode : manuel, me prévenir, ou automatique
MORE SPACE, IF YOU WANT IT ==> ENCORE DE LA PLACE, SI VOUS LE SOUHAITEZ
never cleaned with YSO ==> jamais nettoyé avec YSO
no antivirus is protecting this PC ==> aucun antivirus ne protège ce PC
No old driver versions to remove. ==> Aucune ancienne version de pilote à supprimer.
No restore point yet. ==> Aucun point de restauration pour l'instant.
not restarted for {0} days - Restart (not Shut down) once in a while ==> pas redémarré depuis {0} jours - utilisez Redémarrer (pas Arrêter) de temps en temps
Notify ==> Prévenir
NOTIFY ==> PRÉVENIR
Notify me - check on schedule, tell me, install nothing ==> Me prévenir - vérifier selon le planning, me prévenir, ne rien installer
NOTIFY ONLY ==> PRÉVENIR SEULEMENT
Notify only: nothing was installed ({0} update(s) available). ==> Prévenir seulement : rien n'a été installé ({0} mise(s) à jour disponible(s)).
Number = switch on/off, S = Windows Settings, Enter = back ==> Numéro = activer/désactiver, S = Paramètres Windows, Entrée = retour
Old driver versions ==> Anciennes versions de pilotes
Old driver versions (8) ==> Anciennes versions de pilotes (8)
Old driver versions: {0} removed, {1} freed ==> Anciennes versions de pilotes : {0} supprimées, {1} libérés
Old restore points ==> Anciens points de restauration
Old restore points: {0} removed, {1} freed ==> Anciens points de restauration : {0} supprimés, {1} libérés
only {0} checks could run ==> seulement {0} vérifications ont pu tourner
Open Settings > Windows Update and check for updates. App and driver updates: option 28. ==> Ouvrez Paramètres > Windows Update et recherchez les mises à jour. Applis et pilotes : option 28.
Optimize drives ==> Optimiser les disques
OTHER ==> AUTRE
Other app caches ==> Caches d'autres applis
Other app caches (7) ==> Caches d'autres applis (7)
Other apps built on Chromium (found by their cache layout): {0} ==> Autres applis basées sur Chromium (repérées par leurs caches) : {0}
PC health at a glance (19) ==> Santé du PC en un coup d'œil (19)
PC health report (details) ==> Bilan de santé du PC (détails)
R: keep only the newest ==> R : garder seulement le plus récent
Reading what Windows Update recorded (no download)... ==> Lecture de ce que Windows Update a enregistré (sans téléchargement)...
Remove them? You will not be able to go back to these driver versions. ==> Les supprimer ? Vous ne pourrez plus revenir à ces versions de pilotes.
Removing {0} old driver version(s)... ==> Suppression de {0} ancienne(s) version(s) de pilotes...
Restart ==> Redémarrage
restart to finish ==> redémarrez pour terminer
Restore points ==> Points de restauration
RESTORE POINTS ==> POINTS DE RESTAURATION
Security ==> Sécurité
Simple menu ==> Menu simple
Space used ==> Espace utilisé
step {0} of {1}: {2} ==> étape {0} sur {1} : {2}
Switch to {0}? ==> Passer en {0} ?
Switching one off only stops it starting by itself: it stays installed, and you can switch it back on here, in Task Manager or in Settings. ==> Désactiver un programme l'empêche seulement de démarrer tout seul : il reste installé, et vous pouvez le réactiver ici, dans le Gestionnaire des tâches ou dans les Paramètres.
System Protection settings (on/off, maximum size) ==> Réglages de Protection du système (activer/désactiver, taille maximale)
System Restore is not available on this Windows. ==> La Restauration du système n'est pas disponible sur ce Windows.
The arrow shows the option that helps. ==> La flèche indique l'option qui aide.
this Windows cannot create such paths: {0} ==> ce Windows ne peut pas créer de tels chemins : {0}
today ==> aujourd'hui
turned off on this PC ==> désactivé sur ce PC
turned off on this PC (its service is disabled) ==> désactivé sur ce PC (son service est désactivé)
unknown ==> inconnu
Updates: {0}. Results: Updates (28) > 6. ==> Mises à jour : {0}. Résultats : Mises à jour (28) > 6.
Waiting to install ==> En attente d'installation
weekly auto-clean on ==> nettoyage auto hebdomadaire activé
WHAT DO YOU WANT TO DO? ==> QUE VOULEZ-VOUS FAIRE ?
Windows Disk Cleanup ==> Nettoyage de disque Windows
Windows may use up to {0} ==> Windows peut utiliser jusqu'à {0}
Windows search and Start ==> Recherche et menu Démarrer de Windows
Windows Update ==> Windows Update
WINDOWS UPDATE ==> WINDOWS UPDATE
Windows Update status (19) ==> État de Windows Update (19)
Windows widgets ==> Widgets Windows
working for {0} min {1:00} s ==> en cours depuis {0} min {1:00} s
worn ({0} %) - keep backups up to date ==> usé ({0} %) - gardez vos sauvegardes à jour
yesterday ==> hier
you ==> vous
YOUR PC ==> VOTRE PC
YSO is already installing updates (automatic updates may be running). Try again in a few minutes. ==> YSO installe déjà des mises à jour (les mises à jour automatiques sont peut-être en cours). Réessayez dans quelques minutes.
Never updated automatically ==> Jamais mis à jour auto
new major version ==> nouvelle version majeure
New major version: it can change how the app works - pick it yourself when you are ready. ==> Nouvelle version majeure : elle peut changer le fonctionnement de l'appli - choisissez-la vous-même quand vous êtes prêt.
new major versions ==> nouvelles versions majeures
New major versions (like 7.x -> 8.x) are left for you to install in 28 > 1. ==> Les nouvelles versions majeures (comme 7.x -> 8.x) restent à installer vous-même dans 28 > 1.
Newer graphics drivers come from {0} - Windows Update often has older ones. ==> Les pilotes graphiques récents viennent de {0} - Windows Update en a souvent de plus anciens.
Next run ==> Prochaine exécution
no connection to Windows Update ==> pas de connexion à Windows Update
no internet connection ==> pas de connexion internet
no update applies to this version ==> aucune mise à jour ne s'applique à cette version
Not a valid time: {0} ==> Heure invalide : {0}
not automatic ==> pas en auto
not installed ==> non installée
not installed: the app was open ==> non installée : l'appli était ouverte
Nothing yet: runs of option 28 and automatic updates show up here. ==> Rien pour l'instant : les passages de l'option 28 et des mises à jour automatiques s'affichent ici.
Notification after each automatic run ==> Notification après chaque passage automatique
offline copies kept by websites (you stay logged in) ==> copies hors ligne gardées par les sites (vous restez connecté)
on, but its copy of YSO is missing - switch to manual and back (28 > 2) ==> activé, mais sa copie d'YSO a disparu - repassez en manuel puis en automatique (28 > 2)
open now ==> ouverte
Open now: {0}. Their installers may close them - save your work first. ==> Ouvertes en ce moment : {0}. Leurs installateurs peuvent les fermer - enregistrez votre travail avant.
option 10 can shrink it ==> l'option 10 peut le réduire
option 5 ==> option 5
option 9 ==> option 9
optional ==> facultatif
Optional drivers: Microsoft advises installing them only if that device has a problem. ==> Pilotes facultatifs : Microsoft conseille de ne les installer que si l'appareil concerné a un problème.
recommended ==> recommandé
recommended drivers ==> pilotes recommandés
Recommended: {0} ==> Recommandées : {0}
Recycle Bin: {0} ==> Corbeille : {0}
Restart the PC (Restart, not Shut down) to finish: Windows completes some cleanups and updates during the restart. ==> Redémarrez le PC (Redémarrer, pas Arrêter) pour terminer : Windows achève certains nettoyages et mises à jour pendant le redémarrage.
restart the PC to finish ==> redémarrez le PC pour terminer
Restart the PC to finish some updates (YSO never restarts it by itself). ==> Redémarrez le PC pour terminer certaines mises à jour (YSO ne le redémarre jamais tout seul).
restart the PC, then try again ==> redémarrez le PC, puis réessayez
Restart to finish. ==> Redémarrez pour terminer.
Restore point > temp > browsers > site offline copies > system junk > dev & app caches > GPU caches > update cache > (Recycle Bin) > DNS > deep clean > (updates) > drives ==> Point de restauration > temp > navigateurs > copies hors ligne > fichiers inutiles > caches dév. et applis > caches GPU > mises à jour > (Corbeille) > DNS > nettoyage approfondi > (mises à jour d'applis et pilotes) > disques
Restore points: {0} ==> Points de restauration : {0}
Runs {0} (or at the next startup if the PC was off), while you are logged on, only when plugged in. ==> S'exécute {0} (ou au prochain démarrage si le PC était éteint), quand vous êtes connecté, seulement sur secteur.
Schedule (every day or every week, day, time) ==> Planning (tous les jours ou toutes les semaines, jour, heure)
Schedule: {0} ==> Planning : {0}
skipped - the app was open ==> ignorée - l'appli était ouverte
SPACE & UPDATES ==> ESPACE & MISES À JOUR
SPACE & UPDATES (27-28) ==> ESPACE & MISES À JOUR (27-28)
Space finder (27) shows what else fills your disk (downloads, videos, games...). ==> L'explorateur d'espace (27) montre ce qui remplit encore votre disque (téléchargements, vidéos, jeux...).
the app is open - close it and try again ==> l'appli est ouverte - fermez-la et réessayez
the disk is full ==> le disque est plein
These apps update themselves or need their own updater (winget does not update them automatically). ==> Ces applis se mettent à jour elles-mêmes ou ont leur propre outil (winget ne les met pas à jour automatiquement).
Time (24 h, like 12:00) [{0}] ==> Heure (24 h, comme 12:00) [{0}]
UPDATE HISTORY ==> HISTORIQUE DES MISES À JOUR
Update history ==> Historique des mises à jour
Updates ==> Mises à jour
UPDATES - apps and drivers ==> MISES À JOUR - applis et pilotes
Updates are waiting for a restart: the Windows Update download cache is kept. Restart, then run this again. ==> Des mises à jour attendent un redémarrage : le cache de téléchargement de Windows Update est gardé. Redémarrez, puis relancez.
Updates: apps & drivers ==> Mises à jour : applis & pilotes
Updating {0} ({1} -> {2})... ==> Mise à jour de {0} ({1} -> {2})...
What automatic updates install ==> Ce que les mises à jour auto installent
Windows finishes part of this cleanup during the next restart: more space shows up then. ==> Windows termine une partie de ce nettoyage au prochain redémarrage : de la place se libère encore à ce moment-là.
Windows is waiting for a restart (updates). Until then, the Windows Update cache and the component store cannot be cleaned - on a PC that was never cleaned, that is often the biggest part. ==> Windows attend un redémarrage (mises à jour). D'ici là, le cache de Windows Update et le magasin de composants ne peuvent pas être nettoyés - sur un PC jamais nettoyé, c'est souvent la plus grosse partie.
Windows is waiting for a restart: restart before cleaning, or the Windows Update cache and the component store stay. ==> Windows attend un redémarrage : redémarrez avant de nettoyer, sinon le cache de Windows Update et le magasin de composants restent.
Windows is waiting for a restart: the component store (old Windows Update files) can only be cleaned after it. Restart, then run this again. ==> Windows attend un redémarrage : le magasin de composants (anciens fichiers de Windows Update) ne peut être nettoyé qu'après. Redémarrez, puis relancez.
Windows Update error {0} ==> erreur Windows Update {0}
Windows Update is installing something right now: its download cache is kept. Try again later. ==> Windows Update installe quelque chose en ce moment : son cache de téléchargement est gardé. Réessayez plus tard.
Windows Update is turned off on this PC (its service is disabled) ==> Windows Update est désactivé sur ce PC (son service est désactivé)
winget (App Installer) is not installed ==> winget (Programme d'installation d'application) n'est pas installé
winget failed ({0}) ==> échec de winget ({0})
{0,-30} {1,12} in the bin (only deleted if you confirm) ==> {0,-30} {1,12} dans la corbeille (supprimés seulement si vous confirmez)
{0,-30} {1,12} only if you choose (option 8) ==> {0,-30} {1,12} seulement si vous le choisissez (option 8)
{0,-30} {1,12} reclaimable  ({2:N0} files) ==> {0,-30} {1,12} récupérables  ({2:N0} fichiers)
{0:N0} files are in use and were skipped (normal). ==> {0:N0} fichiers sont en cours d'utilisation et ont été ignorés (normal).
{0:N0} files in {1:N0} folders ==> {0:N0} fichiers dans {1:N0} dossiers
{0:N0} files, {1} ==> {0:N0} fichiers, {1}
{0:N0} folders ==> {0:N0} dossiers
{0:N0} ms ==> {0:N0} ms
{0:N0} ms average, {1:N0} ms worst, {2}% lost ==> {0:N0} ms en moyenne, {1:N0} ms au pire, {2} % perdus
{0:N1} s ({1}) ==> {0:N1} s ({1})
{0}  (includes holding the power button) ==> {0}  (y compris les appuis longs sur le bouton d'alimentation)
{0} % of its original capacity ==> {0} % de sa capacité d'origine
{0} ({1} days ago) ==> {0} (il y a {1} jours)
{0} ({1}): {2} found, {3} installed, {4} not installed ==> {0} ({1}) : {2} trouvée(s), {3} installée(s), {4} non installée(s)
{0} characters ==> {0} caractères
{0} could not be installed - see Updates (28). ==> {0} non installée(s) - voir Mises à jour (28).
{0} could not be removed (Windows still needs them) - normal. ==> {0} n'ont pas pu être supprimés (Windows en a encore besoin) - normal.
{0} crash(es) ==> {0} plantage(s)
{0} day(s) ago ==> il y a {0} jour(s)
{0} day(s) old ==> datent de {0} jour(s)
{0} days ==> {0} jours
{0} days ago ==> il y a {0} jours
{0} device(s) are disabled on purpose (not a problem): {1} ==> {0} périphérique(s) désactivé(s) volontairement (pas un problème) : {1}
{0} disk ==> Disque {0}
{0} free of {1} ({2} % free) ==> {0} libres sur {1} ({2} % libres)
{0} h ==> {0} h
{0} in {1} cleanups (since {2}) ==> {0} en {1} nettoyages (depuis le {2})
{0} installed, {1} not installed ==> {0} installée(s), {1} non installée(s)
{0} is part of Windows. Switch it off anyway? ==> {0} fait partie de Windows. Le désactiver quand même ?
{0} of {1} in use ({2} %) ==> {0} utilisés sur {1} ({2} %)
{0} old version(s), {1} ({2}) ==> {0} ancienne(s) version(s), {1} ({2})
{0} on ==> {0} activé
{0} plan is now active. ==> Le mode {0} est maintenant actif.
{0} skipped because the app was open. ==> {0} ignorée(s) car l'appli était ouverte.
{0} start with Windows ==> {0} démarrent avec Windows
{0} start with Windows, {1} switched off. ==> {0} démarrent avec Windows, {1} désactivés.
{0} uncorrected read errors ==> {0} erreurs de lecture non corrigées
{0} update(s) ==> {0} mise(s) à jour
{0} update(s) available ({1} app(s), {2} driver(s)). Open YSO > Updates (28) to install them. ==> {0} mise(s) à jour disponible(s) ({1} appli(s), {2} pilote(s)). Ouvrez YSO > Mises à jour (28) pour les installer.
{0} update(s) installed. ==> {0} mise(s) à jour installée(s).
{0} used of {1} ==> {0} utilisés sur {1}
{0} will no longer start with Windows. ==> {0} ne démarrera plus avec Windows.
{0} will start with Windows again. ==> {0} démarrera de nouveau avec Windows.
{0}: {1:N0} files removed, {2} freed ==> {0} : {1:N0} fichiers supprimés, {2} libérés
{0}: DNS restored ==> {0} : DNS restauré
{0}: no errors found. ==> {0}: aucune erreur trouvée.
{0}: now using {1} ==> {0} : utilise maintenant {1}
{0}: optimized. ==> {0}: optimisé.
{0}: repaired. ==> {0}: réparé.
{0}: scan failed - {1} ==> {0}: échec de l'analyse - {1}
+{0:N1} s, {1} time(s) ==> +{0:N1} s, {1} fois
A faster DNS ({0}) could make websites start loading sooner - see option 12. ==> Un DNS plus rapide ({0}) pourrait accélérer le chargement des sites - voir l'option 12.
A few errors are normal on every PC. Look for ones that repeat or match when problems happen. ==> Quelques erreurs sont normales sur tout PC. Cherchez celles qui se répètent ou qui coïncident avec vos problèmes.
A full network reset fixes broken connections, but it also: ==> Une réinitialisation réseau complète répare les connexions, mais elle :
Adapter ==> Carte réseau
Add a folder to never touch ==> Ajouter un dossier à ne jamais toucher
Added: {0} ==> Ajouté : {0}
All devices are working normally. ==> Tous les périphériques fonctionnent normalement.
Also permanently empty the Recycle Bin ({0})? ==> Vider aussi définitivement la Corbeille ({0}) ?
Analyze (deletes nothing) ==> Analyser (ne supprime rien)
Analyze-only mode: nothing was changed. ==> Mode analyse seule : rien n'a été modifié.
ANALYZE-ONLY MODE: nothing will be deleted. ==> MODE ANALYSE SEULE : rien ne sera supprimé.
Analyzing - nothing will be deleted... ==> Analyse en cours - rien ne sera supprimé...
Answer a few questions, then you can walk away. ==> Répondez à quelques questions, puis vous pouvez vous absenter.
App ==> Appli
App crashes ==> Plantages d'applis
App freezes ==> Blocages d'applis
APPS THAT CRASH THE MOST ==> APPLIS QUI PLANTENT LE PLUS
Apps: switch them off in Startup programs (17). Drivers and services: update or uninstall the program they belong to. ==> Applis : désactivez-les dans Programmes au démarrage (17). Pilotes et services : mettez à jour ou désinstallez le programme concerné.
Auto ==> Auto
Automatic ({0}) ==> Automatique ({0})
Automatic (same as Windows) / Automatique (comme Windows) ==> Automatique (comme Windows) / Automatic (same as Windows)
Automatic (what your network provides) ==> Automatique (fourni par votre réseau)
Average boot ==> Démarrage moyen
Back ==> Retour
Balanced ==> Utilisation normale
Balanced (Windows default - best for laptops) ==> Utilisation normale (défaut de Windows - idéal pour les portables)
BATTERY ==> BATTERIE
being removed ==> en cours de suppression
BIGGEST FILES ==> PLUS GROS FICHIERS
blocked: known compatibility problem ==> bloqué : problème de compatibilité connu
blocks known malicious sites ==> bloque les sites malveillants connus
Blue screens ==> Écrans bleus
Blue screens: run Memory test (25) and Driver problems (23). ==> Écrans bleus : lancez Test de mémoire (25) et Problèmes de pilotes (23).
Boot time analyzer ==> Analyse du temps de démarrage
Browser caches ==> Caches des navigateurs
Browser caches - Chrome, Edge, Brave, Vivaldi, Opera, Firefox (every profile) ==> Caches des navigateurs - Chrome, Edge, Brave, Vivaldi, Opera, Firefox (tous les profils)
Browsers are open. Close them for a complete clean? ==> Des navigateurs sont ouverts. Les fermer pour un nettoyage complet ?
BY CATEGORY ==> PAR CATÉGORIE
BY MONTH ==> PAR MOIS
Can take 10-30 minutes. Downloads, Recycle Bin and Windows.old are never included. ==> Peut prendre 10 à 30 minutes. Téléchargements, Corbeille et Windows.old ne sont jamais inclus.
Cancelled. ==> Annulé.
cannot start ==> ne peut pas démarrer
Category ==> Catégorie
Change age limits ==> Modifier les limites d'âge
Change DNS servers ==> Changer de serveurs DNS
Charge ==> Charge
Check drives for errors ==> Vérifier les disques
Checking devices and drivers (read-only)... ==> Vérification des périphériques et pilotes (lecture seule)...
Checking your security settings (read-only)... ==> Vérification de vos réglages de sécurité (lecture seule)...
Checks and repairs Windows system files. Takes 15-45 minutes; DISM needs internet. ==> Vérifie et répare les fichiers système de Windows. Dure 15 à 45 minutes ; DISM a besoin d'Internet.
Choose what weekly auto-clean cleans ==> Choisir ce que nettoie le nettoyage hebdomadaire
CLEAN ==> NETTOYER
Cleaning the component store (superseded Windows Update files)... ==> Nettoyage du magasin de composants (anciens fichiers de Windows Update)...
CLEANUP HISTORY ==> HISTORIQUE DES NETTOYAGES
Cleanup history ==> Historique des nettoyages
Close Notepad to apply your changes. ==> Fermez le Bloc-notes pour appliquer vos modifications.
Close them now for a complete clean? (tabs are restored on reopen) ==> Les fermer maintenant pour un nettoyage complet ? (les onglets reviennent à la réouverture)
Closing browsers... ==> Fermeture des navigateurs...
code {0} ==> code {0}
Collecting startup entries, services and scheduled tasks, and checking their digital signatures... ==> Collecte des programmes de démarrage, services et tâches planifiées, et vérification de leurs signatures numériques...
Collecting system health (read-only)... ==> Collecte de l'état du système (lecture seule)...
configuration is damaged ==> configuration endommagée
CONNECTION ==> CONNEXION
Could not create the scheduled task: {0} ==> Impossible de créer la tâche planifiée : {0}
Could not pause Windows Update: {0} ==> Impossible de mettre Windows Update en pause : {0}
Could not save settings: {0} ==> Impossible d'enregistrer les paramètres : {0}
CPU load ==> Charge du processeur
Crashes & errors ==> Plantages et erreurs
Create a detailed battery report (opens in your browser)? ==> Créer un rapport détaillé de la batterie (s'ouvre dans votre navigateur) ?
Create a restore point first? (recommended) ==> Créer d'abord un point de restauration ? (recommandé)
Created ==> Créé le
Creating a System Restore point (your undo button)... ==> Création d'un point de restauration système (votre bouton « annuler »)...
Current ==> Actuel
Deep clean ==> Nettoyage approfondi
Deep clean - Windows Disk Cleanup (safe categories only) + component store ==> Nettoyage approfondi - Nettoyage de disque Windows (catégories sûres uniquement) + magasin de composants
Deep clean (8) usually frees more on top of this - it cannot be measured in advance. ==> Le nettoyage approfondi (8) libère souvent davantage - impossible à mesurer à l'avance.
Deep clean (Disk Cleanup) ==> Nettoyage approfondi (Nettoyage de disque)
Deep clean freed {0} ==> Le nettoyage approfondi a libéré {0}
Deep clean takes 10-30 minutes. Start? ==> Le nettoyage approfondi dure 10 à 30 minutes. Lancer ?
Defender ==> Defender
Defender found {0} threat(s). Open Windows Security to review them. ==> Defender a trouvé {0} menace(s). Ouvrez Sécurité Windows pour les examiner.
Defender found nothing in these files. ==> Defender n'a rien trouvé dans ces fichiers.
Defender real-time ==> Defender temps réel
Delivery Optimization ==> Optimisation de la distribution
Delivery Optimization cache: {0} freed ==> Cache d'Optimisation de la distribution : {0} libérés
Developer & app caches ==> Caches développeur et applis
Developer & app caches - npm, pip, NuGet, Yarn, Gradle, VS Code, Discord, Teams, Spotify, Steam, Epic, OneDrive logs ==> Caches développeur et applis - npm, pip, NuGet, Yarn, Gradle, VS Code, Discord, Teams, Spotify, Steam, Epic, journaux OneDrive
DEVICES WITH PROBLEMS ==> PÉRIPHÉRIQUES EN ERREUR
DIAGNOSE & REPAIR ==> DIAGNOSTIC ET RÉPARATION
disabled in the firmware ==> désactivé dans le micrologiciel
Disk Cleanup is not available on this Windows build - skipping that part. ==> Le Nettoyage de disque n'existe pas sur cette version de Windows - étape ignorée.
Disk Cleanup is not available on this Windows build. ==> Le Nettoyage de disque n'existe pas sur cette version de Windows.
DISM finished without problems. ==> DISM s'est terminé sans problème.
DISM returned code {0}. Details: {1} ==> DISM a renvoyé le code {0}. Détails : {1}
DNS cache flushed. ==> Cache DNS vidé.
DNS SERVERS ==> SERVEURS DNS
DNS servers ==> Serveurs DNS
DNS SPEED (time to look up a website) ==> VITESSE DNS (temps pour trouver un site)
Domain network ==> Réseau de domaine
Done. Free space changed by {0}{1}. ==> Terminé. Espace libre modifié de {0}{1}.
Drive {0}: ==> Disque {0}:
Drive letter or folder to scan [{0}] ==> Lettre de disque ou dossier à analyser [{0}]
Driver ==> Pilote
driver failed to start ==> le pilote n'a pas démarré
driver may be corrupted ==> pilote peut-être endommagé
driver missing or corrupted ==> pilote manquant ou endommagé
Driver problems ==> Problèmes de pilotes
driver service is disabled ==> service du pilote désactivé
driver signature cannot be verified ==> signature du pilote invérifiable
drivers need to be reinstalled ==> pilotes à réinstaller
drivers not installed ==> pilotes non installés
Edit the settings file in Notepad ==> Modifier le fichier de paramètres dans le Bloc-notes
Encryption of {0} ==> Chiffrement de {0}
English (default) ==> English (par défaut)
Everything looks healthy. ==> Tout semble en bon état.
excellent ==> excellent
fair - expect slowdowns ==> moyen - ralentissements possibles
fast ==> rapide
Fast Startup ==> Démarrage rapide
fast, privacy-focused ==> rapide, axé sur la confidentialité
fast, very reliable ==> rapide, très fiable
file is missing (leftover entry) ==> fichier introuvable (entrée orpheline)
Files ==> Fichiers
Firewall: {0} ==> Pare-feu : {0}
Flush DNS cache ==> Vider le cache DNS
Flushing DNS cache ==> Vidage du cache DNS
Folder not found: {0} ==> Dossier introuvable : {0}
Folder to never touch (full path) ==> Dossier à ne jamais toucher (chemin complet)
Français ==> Français
Free disk space ({0}): {1}  ->  {2} ==> Espace disque libre ({0}) : {1}  ->  {2}
Free space: {0}   |   Uptime: {1}   |   User profiles: {2} ==> Espace libre : {0}   |   Allumé depuis : {1}   |   Profils : {2}
Freed in total ==> Libéré au total
Full (Windows default) ==> Complet (défaut de Windows)
Full list (Microsoft items included) saved to: {0} ==> Liste complète (éléments Microsoft inclus) enregistrée dans : {0}
FULL MAINTENANCE ==> ENTRETIEN COMPLET
Full maintenance ==> Entretien complet
Full maintenance finished in {0} min {1} s. ==> Entretien complet terminé en {0} min {1} s.
Full network reset ==> Réinitialisation réseau complète
Full security details: option 21. Crash details: option 20. ==> Détails de sécurité : option 21. Détails des plantages : option 20.
Games rebuild these on next launch (first load may stutter briefly). ==> Les jeux les reconstruisent au prochain lancement (le premier chargement peut saccader un peu).
Going back to the previous version is no longer possible, so this is just leftover files. ==> Le retour à la version précédente n'est plus possible : ce ne sont que des restes.
good ==> bon
GPU shader caches ==> Caches de shaders GPU
GPU shader caches - DirectX, NVIDIA, AMD, Intel, Steam ==> Caches de shaders GPU - DirectX, NVIDIA, AMD, Intel, Steam
Hardware rescanned. Run this check again to see if anything changed. ==> Matériel réanalysé. Relancez cette vérification pour voir si quelque chose a changé.
Health ==> Santé
hiberfil.sys ==> hiberfil.sys
Hibernation file ==> Fichier de veille prolongée
HIBERNATION FILE ==> FICHIER DE VEILLE PROLONGÉE
High Performance ==> Performances élevées
If SFC repaired files, restart your PC. Details: {0} ==> Si SFC a réparé des fichiers, redémarrez le PC. Détails : {0}
Include deep clean? (Disk Cleanup + component store, adds 10-30 min) ==> Inclure le nettoyage approfondi ? (Nettoyage de disque + magasin de composants, 10 à 30 min de plus)
Internet (Cloudflare) ==> Internet (Cloudflare)
Internet (Google) ==> Internet (Google)
Internet latency is high. This usually comes from your provider or a busy network, not from this PC. ==> La latence Internet est élevée. Cela vient en général de votre fournisseur ou d'un réseau chargé, pas de ce PC.
IP address ==> Adresse IP
It cleans: {0} (change this in Settings, option O). ==> Il nettoie : {0} (modifiable dans Paramètres, option O).
It never closes your apps and never empties the Recycle Bin. ==> Il ne ferme jamais vos applis et ne vide jamais la Corbeille.
It runs after a restart, before Windows loads, and takes 10-30 minutes. Save your work first. ==> Il s'exécute après un redémarrage, avant le chargement de Windows, et dure 10 à 30 minutes. Enregistrez votre travail avant.
Items checked ==> Éléments vérifiés
Keep logs and dumps newer than ==> Garder journaux et vidages de moins de
Keep logs and dumps newer than how many days? (1-365) [{0}] ==> Garder les journaux et vidages de moins de combien de jours ? (1-365) [{0}]
Keep temp files newer than ==> Garder les fichiers temp. de moins de
Keep temp files newer than how many hours? (1-720) [{0}] ==> Garder les fichiers temporaires de moins de combien d'heures ? (1-720) [{0}]
Kept. ==> Conservé.
Language ==> Langue
Language / Langue ==> Langue / Language
Laptop detected: Hibernate saves your work when the battery runs out - Reduced or Full is safer. ==> Portable détecté : la veille prolongée sauve votre travail quand la batterie est vide - Réduit ou Complet est plus sûr.
Laptop detected: performance plans mean more heat, more fan noise and less battery. ==> Portable détecté : les modes performance chauffent plus, font plus de bruit et vident la batterie plus vite.
LAST 10 CLEANUPS ==> 10 DERNIERS NETTOYAGES
LAST 30 DAYS ==> 30 DERNIERS JOURS
LAST BOOTS ==> DERNIERS DÉMARRAGES
Last quick scan ==> Dernière analyse rapide
Last test ==> Dernier test
Last Windows update ==> Dernière mise à jour Windows
LATENCY (lower is better) ==> LATENCE (plus bas = mieux)
Link speed ==> Vitesse du lien
Logs folder ==> Dossier des journaux
Look for driver updates (Windows Update > Optional updates) ==> Chercher des mises à jour de pilotes (Windows Update > Mises à jour facultatives)
Look up names you do not recognize. To remove one, uninstall its program (Settings > Apps). ==> Renseignez-vous sur les noms inconnus. Pour en retirer un, désinstallez son programme (Paramètres > Applications).
Manual ==> Manuel
Measuring... ==> Mesure en cours...
Memory ==> Mémoire
Memory test ==> Test de mémoire
MEMORY TEST ==> TEST DE MÉMOIRE
Microsoft (not listed) ==> Microsoft (non listés)
MICROSOFT DEFENDER ==> MICROSOFT DEFENDER
Microsoft Defender is not active on this PC. ==> Microsoft Defender n'est pas actif sur ce PC.
Most useful after a driver update or when you see graphics glitches. ==> Surtout utile après une mise à jour de pilote ou en cas de bugs graphiques.
needs a restart ==> redémarrage nécessaire
NETWORK ==> RÉSEAU
Network check (speed, DNS, Wi-Fi) ==> Test réseau (vitesse, DNS, Wi-Fi)
Network stack reset. ==> Pile réseau réinitialisée.
never ==> jamais
Never touch ==> Ne jamais toucher
no ==> non
no answer ==> pas de réponse
No cleanups recorded yet. Run any cleaning option and it will show up here. ==> Aucun nettoyage enregistré. Lancez une option de nettoyage et elle apparaîtra ici.
No connected network adapter found. ==> Aucune carte réseau connectée trouvée.
No files of 50 MB or more were found. ==> Aucun fichier de 50 Mo ou plus trouvé.
No memory test has been run on this PC yet. ==> Aucun test de mémoire n'a encore été fait sur ce PC.
No program has noticeably slowed down your boots recently. ==> Aucun programme n'a nettement ralenti vos démarrages récemment.
no reply ==> pas de réponse
No restore point created: {0} ==> Aucun point de restauration créé : {0}
No route to the internet - this PC seems to be offline. ==> Aucune route vers Internet - ce PC semble hors ligne.
No startup entries found. ==> Aucun programme au démarrage trouvé.
No subfolders here. ==> Aucun sous-dossier ici.
normal ==> normal
not active (another antivirus may be in charge) ==> inactif (un autre antivirus est peut-être en place)
not configured correctly ==> mal configuré
not enough free resources ==> ressources libres insuffisantes
not found ==> introuvable
ONE-CLICK ==> EN UN CLIC
not present (hibernation is off) ==> absent (veille prolongée désactivée)
not present or drivers missing ==> absent ou pilotes manquants
not signed ==> non signé
Not signed does not mean malware - many small or open-source tools are unsigned. ==> Non signé ne veut pas dire malveillant - beaucoup de petits outils et de logiciels libres ne sont pas signés.
not supported (legacy BIOS) ==> non pris en charge (BIOS ancien)
not working properly ==> ne fonctionne pas correctement
Nothing is deleted here. Type a number to show that file in Explorer, then decide yourself. ==> Rien n'est supprimé ici. Tapez un numéro pour afficher le fichier dans l'Explorateur, puis décidez vous-même.
Number to remove, Enter to cancel ==> Numéro à retirer, Entrée pour annuler
Number to switch on/off, Enter when done ==> Numéro à activer/désactiver, Entrée pour terminer
Number, or Enter to go back ==> Numéro, ou Entrée pour revenir
OFF ==> DÉSACTIVÉ
OFF - files are readable if the PC is stolen ==> DÉSACTIVÉ - fichiers lisibles si le PC est volé
Off (frees the most space) ==> Désactivé (libère le plus de place)
Off: frees all of it, but turns off Hibernate and Fast Startup (cold boots get a bit slower). ==> Désactivé : libère tout, mais coupe la veille prolongée et le démarrage rapide (démarrages à froid un peu plus lents).
Old Windows version (Windows.old) ==> Ancienne version de Windows (Windows.old)
ON ==> ACTIVÉ
ON (BitLocker) ==> ACTIVÉ (BitLocker)
Only caches and old logs: projects, installed packages, settings, logins and game files are not touched. ==> Uniquement des caches et de vieux journaux : projets, paquets installés, réglages, connexions et fichiers de jeux ne sont pas touchés.
Only full boots are measured: Restart, or Shut down when Fast Startup is off. ==> Seuls les démarrages complets sont mesurés : Redémarrer, ou Arrêter quand le démarrage rapide est désactivé.
Open browsers: {0} - files they are using will be skipped. ==> Navigateurs ouverts : {0} - les fichiers qu'ils utilisent seront ignorés.
Open Device Manager ==> Ouvrir le Gestionnaire de périphériques
Open Power settings now? ==> Ouvrir les paramètres d'alimentation maintenant ?
Open Reliability Monitor (a timeline of problems)? ==> Ouvrir le Moniteur de fiabilité (chronologie des problèmes) ?
Open Windows Memory Diagnostic now? (you then choose: restart now, or at next start) ==> Ouvrir le Diagnostic de mémoire Windows maintenant ? (vous choisirez ensuite : redémarrer maintenant, ou au prochain démarrage)
Open Windows Security ==> Ouvrir Sécurité Windows
OPTIMIZE ==> OPTIMISER
Optimize drives (TRIM / defrag) ==> Optimiser les disques (TRIM / défrag.)
Optimize drives at the end? (TRIM / defrag) ==> Optimiser les disques à la fin ? (TRIM / défrag.)
Optimizing drives - Windows picks TRIM for SSDs and defrag for hard drives ==> Optimisation des disques - Windows choisit TRIM pour les SSD et la défragmentation pour les disques durs
OTHER THIRD-PARTY ITEMS ==> AUTRES ÉLÉMENTS TIERS
Part of Windows.old is still there. Restart and run this again. ==> Une partie de Windows.old est encore là. Redémarrez puis relancez cette option.
Passwords, cookies, history, bookmarks and open tabs are NOT touched. ==> Mots de passe, cookies, historique, favoris et onglets ouverts ne sont PAS touchés.
Permanently delete {0} from the Recycle Bin? This cannot be undone. ==> Supprimer définitivement {0} de la Corbeille ? C'est irréversible.
POWER PLAN ==> MODE D'ALIMENTATION
Power plan ==> Mode d'alimentation
present and ready ==> présente et prête
present, not ready ==> présente, pas prête
Press Enter to return to the menu ==> Appuyez sur Entrée pour revenir au menu
Previous Windows version (Windows.old) ==> Version précédente de Windows (Windows.old)
Private network ==> Réseau privé
problem code {0} ==> code de problème {0}
Processor ==> Processeur
PROGRAMS THAT START WITH WINDOWS ==> PROGRAMMES QUI DÉMARRENT AVEC WINDOWS
Public network ==> Réseau public
Quick scan finished: no threats found. ==> Analyse rapide terminée : aucune menace trouvée.
Quit ==> Quitter
Reading the boot records Windows keeps (read-only)... ==> Lecture des relevés de démarrage de Windows (lecture seule)...
Reading the Windows event logs (read-only - nothing is cleared)... ==> Lecture des journaux d'événements Windows (lecture seule - rien n'est effacé)...
Real-time protection ==> Protection en temps réel
Recycle Bin ==> Corbeille
Recycle Bin (all drives) ==> Corbeille (tous les disques)
Recycle Bin emptied: {0} freed ==> Corbeille vidée : {0} libérés
Recycle Bin is already empty. ==> La Corbeille est déjà vide.
Recycle Bin kept. ==> Corbeille conservée.
Reduced (good choice for desktops) ==> Réduit (bon choix pour les PC fixes)
Reduced: keeps Fast Startup, drops Hibernate - the file shrinks to about half. ==> Réduit : garde le démarrage rapide, retire la veille prolongée - le fichier diminue d'environ moitié.
Refusing to touch protected path: {0} ==> Refus de toucher un chemin protégé : {0}
Remove a folder from that list ==> Retirer un dossier de cette liste
Remove Windows.old now? ==> Supprimer Windows.old maintenant ?
Removing Windows.old takes that option away for good. ==> Supprimer Windows.old retire définitivement cette possibilité.
Repair {0}: at the next restart? ==> Réparer {0}: au prochain redémarrage ?
Repair {0}: now? (the drive may be unavailable for a moment) ==> Réparer {0}: maintenant ? (le disque peut être indisponible un instant)
Repair scheduled. Restart when convenient - it runs before Windows starts. ==> Réparation planifiée. Redémarrez quand vous voulez - elle s'exécute avant le démarrage de Windows.
Repair Windows files (DISM + SFC) ==> Réparer les fichiers Windows (DISM + SFC)
Rescan hardware ==> Réanalyser le matériel
Reset all settings to defaults? ==> Rétablir tous les paramètres par défaut ?
Reset the network stack now? ==> Réinitialiser la pile réseau maintenant ?
Reset to defaults ==> Rétablir les valeurs par défaut
Restart now? ==> Redémarrer maintenant ?
Restart pending ==> Redémarrage en attente
Restart your PC to finish. ==> Redémarrez le PC pour terminer.
Restore my previous DNS settings ==> Restaurer mes anciens réglages DNS
Restore point ==> Point de restauration
Restore point created. ==> Point de restauration créé.
Result ==> Résultat
Router (gateway) ==> Routeur (passerelle)
Run a quick scan (5-15 minutes) ==> Lancer une analyse rapide (5 à 15 minutes)
Running Disk Cleanup (previous Windows installations)... ==> Nettoyage de disque en cours (installations précédentes de Windows)...
Running Disk Cleanup... ==> Nettoyage de disque en cours...
runs a script or command ==> exécute un script ou une commande
Runs every Sunday at 03:00 (or at the next startup if the PC was off), silently, only when plugged in. ==> S'exécute chaque dimanche à 3 h (ou au démarrage suivant si le PC était éteint), en silence, seulement sur secteur.
runs from a user folder ==> s'exécute depuis un dossier utilisateur
safe  -  measured  -  logged ==> sûr  -  mesuré  -  journalisé
Scan the {0} flagged file(s) with Microsoft Defender now? ==> Analyser maintenant le(s) {0} fichier(s) signalé(s) avec Microsoft Defender ?
Scanning ==> Analyse
Scanning - a full drive can take a minute or two. Nothing is changed. ==> Analyse en cours - un disque entier peut prendre une ou deux minutes. Rien n'est modifié.
Scanning {0} ==> Analyse de {0}
Scanning drives for file-system errors (online - you can keep working)... ==> Recherche d'erreurs du système de fichiers (en ligne - vous pouvez continuer à travailler)...
Scanning... you can keep using the PC. ==> Analyse en cours... vous pouvez continuer à utiliser le PC.
Secure Boot ==> Démarrage sécurisé
Security check & Defender scan ==> Sécurité et analyse Defender
Service ==> Service
SETTINGS ==> PARAMÈTRES
Settings / Langue ==> Paramètres / Language
Settings file ==> Fichier de paramètres
settings.json has an error, so defaults are in use. Fix it (6) or reset it (7). ==> settings.json contient une erreur : les valeurs par défaut sont utilisées. Corrigez-le (6) ou réinitialisez-le (7).
settings.json has an error, so defaults are in use. Fix it in Settings (O). ==> settings.json contient une erreur : les valeurs par défaut sont utilisées. Corrigez-le dans Paramètres (O).
signature cannot be checked ==> signature impossible à vérifier
signature does not match the file ==> la signature ne correspond pas au fichier
signature not trusted ==> signature non approuvée
Size ==> Taille
Size (approx.) ==> Taille (env.)
slow ==> lent
SPACE FINDER ==> EXPLORATEUR D'ESPACE
SPACE FINDER - {0} ==> EXPLORATEUR D'ESPACE - {0}
Space finder (what fills my disk?) ==> Explorateur d'espace (qui remplit le disque ?)
Start YSO from its file to use this option. ==> Lancez YSO depuis son fichier pour utiliser cette option.
Start now? ==> Lancer maintenant ?
Startup ==> Démarrage
Startup programs ==> Programmes au démarrage
Static IP detected on: {0} ==> IP statique détectée sur : {0}
STATUS ==> ÉTAT
Step 1/2 - DISM: repairing the Windows component store... ==> Étape 1/2 - DISM : réparation du magasin de composants Windows...
Step 2/2 - SFC: verifying protected system files... ==> Étape 2/2 - SFC : vérification des fichiers système protégés...
Still open: {0} - files they are using will be skipped. Close them for a complete clean. ==> Encore ouverts : {0} - les fichiers qu'ils utilisent seront ignorés. Fermez-les pour un nettoyage complet.
stopped by Windows after reporting problems ==> arrêté par Windows après avoir signalé des problèmes
STORAGE ==> STOCKAGE
SUMMARY ==> RÉSUMÉ
SYSTEM ==> SYSTÈME
System errors (7 days) ==> Erreurs système (7 jours)
System health report ==> Rapport de santé du système
System junk ==> Fichiers système inutiles
System junk - error reports, crash dumps, logs older than {0} days, thumbnail cache ==> Fichiers système inutiles - rapports d'erreurs, vidages, journaux de plus de {0} jours, cache des miniatures
System junk (reports, dumps, old logs) ==> Fichiers inutiles (rapports, vidages, journaux)
System Restore looks turned off. Turn it on for the system drive? ==> La Restauration du système semble désactivée. L'activer pour le disque système ?
Tamper protection ==> Protection anti-falsification
Task ==> Tâche
Temporary files ==> Fichiers temporaires
Temporary files - every user profile + Windows (files older than {0} h) ==> Fichiers temporaires - tous les profils + Windows (fichiers de plus de {0} h)
Testing your connection (about 20 seconds, nothing is changed)... ==> Test de votre connexion (environ 20 secondes, rien n'est modifié)...
That does not look like a valid Id. ==> Cet Id ne semble pas valide.
The internet servers did not answer. Your provider may be down, or ping is blocked on this network. ==> Les serveurs Internet n'ont pas répondu. Votre fournisseur est peut-être en panne, ou le ping est bloqué sur ce réseau.
The link between this PC and your router is weak or losing packets - on Wi-Fi, move closer, use 5 GHz, or try a cable. ==> Le lien entre ce PC et votre routeur est faible ou perd des paquets - en Wi-Fi, rapprochez-vous, passez en 5 GHz ou essayez un câble.
The list is empty. ==> La liste est vide.
The result shows as a notification after Windows starts again (and here, next time). ==> Le résultat s'affiche en notification au redémarrage de Windows (et ici, la prochaine fois).
There is no Windows.old folder - nothing to remove. ==> Il n'y a pas de dossier Windows.old - rien à supprimer.
Third-party, signed ==> Tiers, signés
This PC only offers the Balanced plan (normal on Modern Standby laptops). ==> Ce PC ne propose que le mode Utilisation normale (normal sur les portables à veille moderne).
This takes 10-60 seconds. Nothing is changed. ==> Cela prend 10 à 60 secondes. Rien n'est modifié.
Threats found (30 days) ==> Menaces trouvées (30 jours)
Tip: run Network check (11) first to see which one is fastest for you. ==> Astuce : lancez d'abord le Test réseau (11) pour voir lequel est le plus rapide chez vous.
TOP ERROR SOURCES (last 7 days) ==> PRINCIPALES SOURCES D'ERREURS (7 derniers jours)
TOP MEMORY USERS ==> PLUS GROS CONSOMMATEURS DE MÉMOIRE
TOTAL ==> TOTAL
Total {0}  -  {1:N0} files scanned, {2:N0} protected folders skipped ==> Total {0}  -  {1:N0} fichiers analysés, {2:N0} dossiers protégés ignorés
TPM security chip ==> Puce de sécurité TPM
Turn it off? ==> Le désactiver ?
Turn on weekly auto-clean? ==> Activer le nettoyage automatique hebdomadaire ?
Ultimate is not available here - High Performance is now active instead. ==> Performances optimales est indisponible ici - Performances élevées est activé à la place.
Ultimate Performance ==> Performances optimales
Ultimate Performance (desktops - maximum responsiveness) ==> Performances optimales (PC fixes - réactivité maximale)
unavailable (Windows may need Location turned on) ==> indisponible (Windows a peut-être besoin de la localisation activée)
Unexpected shutdowns ==> Arrêts inattendus
Update virus definitions ==> Mettre à jour les définitions de virus
Updating... ==> Mise à jour...
Uptime ==> Allumé depuis
Use Settings > System > Power > Power mode > Best performance instead. ==> Utilisez plutôt Paramètres > Système > Alimentation > Mode d'alimentation > Meilleures performances.
User Account Control ==> Contrôle de compte d'utilisateur
VERDICT ==> VERDICT
very slow ==> très lent
Virus definitions ==> Définitions de virus
Virus definitions are up to date. ==> Les définitions de virus sont à jour.
weak - move closer to the router ==> faible - rapprochez-vous du routeur
wear {0} % ==> usure {0} %
Weekly auto-clean ==> Nettoyage auto
Weekly auto-clean cleans ==> Le nettoyage hebdo nettoie
Weekly auto-clean is ON. Next run: {0} ==> Nettoyage automatique hebdomadaire ACTIVÉ. Prochaine exécution : {0}
Weekly auto-clean is ON. Results go to the logs (L) and the history (H). ==> Nettoyage automatique hebdomadaire ACTIVÉ. Résultats dans les journaux (L) et l'historique (H).
Weekly auto-clean removed. ==> Nettoyage automatique hebdomadaire supprimé.
What runs automatically? (audit) ==> Qu'est-ce qui se lance tout seul ? (audit)
WHAT SLOWED BOOTS DOWN (last 90 days) ==> CE QUI A RALENTI LES DÉMARRAGES (90 derniers jours)
Wi-Fi network ==> Réseau Wi-Fi
Wi-Fi signal ==> Signal Wi-Fi
WINDOWS ==> WINDOWS
Windows ==> Windows
Some event logs could not be read, so these numbers may be too low: {0} ==> Certains journaux d'événements sont illisibles, ces chiffres peuvent donc être trop bas : {0}
could not be read ==> illisible
Windows allows one restore point per 24h - a recent one already exists, so you are covered. ==> Windows n'autorise qu'un point de restauration par 24 h - un point récent existe déjà, vous êtes couvert.
Windows cannot read its boot records here: {0} ==> Windows ne peut pas lire ses relevés de démarrage ici : {0}
Windows has no boot records yet (the Diagnostic Policy Service may be off, or the PC has not restarted recently). ==> Windows n'a encore aucun relevé de démarrage (le Service de stratégie de diagnostic est peut-être arrêté, ou le PC n'a pas redémarré récemment).
Windows keeps this file for Hibernate and Fast Startup. ==> Windows garde ce fichier pour la veille prolongée et le démarrage rapide.
Windows Memory Diagnostic checks your RAM for faults - a common cause of blue screens and random crashes. ==> Le Diagnostic de mémoire Windows teste votre RAM - une cause fréquente d'écrans bleus et de plantages aléatoires.
Windows Update cache ==> Cache de Windows Update
Windows Update download cache + Delivery Optimization cache ==> Cache des téléchargements Windows Update + cache d'Optimisation de la distribution
Windows.old ==> Windows.old
Windows.old removed: {0} freed ==> Windows.old supprimé : {0} libérés
WORTH A LOOK ==> À VÉRIFIER
Worth a look ==> À vérifier
YES - restart to finish installing updates ==> OUI - redémarrez pour finir d'installer les mises à jour
You can go back at any time with option 4 on this screen. ==> Vous pouvez revenir en arrière à tout moment avec l'option 4 de cet écran.
You can still go back to your previous Windows version until {0}. ==> Vous pouvez encore revenir à votre version précédente de Windows jusqu'au {0}.
Your DNS ({0}) ==> Votre DNS ({0})
Your previous network settings were saved to: {0} ==> Vos anciens réglages réseau ont été enregistrés dans : {0}
Your router ==> Votre routeur
Also close {0} for a complete clean? (nothing is lost) ==> Fermer aussi {0} pour un nettoyage complet ? (rien n'est perdu)
Also clear GPU shader caches? (games may stutter briefly the first time) ==> Vider aussi les caches GPU ? (les jeux peuvent saccader un peu la première fois)
Open: {0} - files they are using would be skipped. ==> Ouverts : {0} - les fichiers qu'ils utilisent seraient ignorés.
Close them now for a complete clean? (nothing is lost, reopen them afterwards) ==> Les fermer maintenant pour un nettoyage complet ? (rien n'est perdu, rouvrez-les ensuite)
Closing... ==> Fermeture...
Site offline caches ==> Caches hors ligne des sites
{0,-30} {1,12} only if you choose (option 2) ==> {0,-30} {1,12} seulement si vous le choisissez (option 2)
Websites also keep {0} of offline copies - they can only be removed with the browsers closed. ==> Les sites gardent aussi {0} de copies hors ligne - on ne peut les supprimer que navigateurs fermés.
Websites and web apps also keep {0} of offline copies (Service Workers). ==> Les sites et applis web gardent aussi {0} de copies hors ligne (Service Workers).
Removing them does not log you out, but web apps lose what they saved for offline use. ==> Les supprimer ne vous déconnecte pas, mais les applis web perdent ce qu'elles avaient gardé pour le hors-ligne.
Remove them too? ==> Les supprimer aussi ?
Offline copies kept by websites (Service Workers) ==> Copies hors ligne gardées par les sites (Service Workers)
Also remove offline copies kept by websites? (you stay logged in) ==> Supprimer aussi les copies hors ligne des sites ? (vous restez connecté)
VS Code: also removes the saved data of projects not opened for 60 days (rebuilt if you open them again). ==> VS Code : supprime aussi les données des projets non ouverts depuis 60 jours (recréées si vous les rouvrez).
YSO ==> YSO
BIG APP FOLDERS YSO DOES NOT CLEAN (20 MB or more) ==> GROS DOSSIERS D'APPLIS QU'YSO NE NETTOIE PAS (20 Mo ou plus)
None: every big folder in these apps is a cache YSO cleans. ==> Aucun : tous les gros dossiers de ces applis sont des caches qu'YSO nettoie.
Usually normal (site data, extensions, settings, offline downloads). If a name looks like a cache, send the report (P). ==> En général normal (données de sites, extensions, réglages, téléchargements hors ligne). Si un nom ressemble à un cache, envoyez le rapport (P).
The change in free space differs from what YSO removed: other programs were writing or freeing space at the same time. ==> La variation d'espace libre diffère de ce qu'YSO a supprimé : d'autres programmes écrivaient ou libéraient de l'espace en même temps.
Choose ==> Votre choix
(event id {0}) ==> (événement n° {0})
Secure Boot {0} ==> démarrage sécurisé {0}
ANALYSIS - space you can reclaim (nothing was deleted) ==> ANALYSE - espace récupérable (rien n'a été supprimé)
Charge cycles ==> Cycles de charge
not reported by this battery ==> non indiquée par cette batterie
{0} charge cycles ==> {0} cycles de charge
service running ==> service en marche
service stopped - normal, it starts when needed ==> service arrêté - normal, il démarre si besoin
{0} (last: {1}) - send them with P ==> {0} (dernière : {1}) - envoyez-les avec P
{0} boots recorded ==> {0} démarrages enregistrés
{0} devices, {1} with problems ==> {0} périphériques, {1} en erreur
{0} files removed ==> {0} fichiers supprimés
{0} measured in {1:N0} ms ==> {0} mesurés en {1:N0} ms
{0} of {1} safe categories available ==> {0} catégories sûres sur {1} disponibles
{0} OK, {1} info, {2} missing, {3} broken ==> {0} OK, {1} info, {2} absents, {3} en erreur
{0} plan(s) available ==> {0} mode(s) disponible(s)
{0} plans; Ultimate Performance needs Windows 10 version 1803 or later ==> {0} modes ; Performances optimales demande Windows 10 version 1803 ou plus
{0} problem(s) recorded - use P to send a report. ==> {0} problème(s) enregistré(s) - utilisez P pour envoyer un rapport.
{0} restore points ==> {0} points de restauration
{0} services, {1} tasks ==> {0} services, {1} tâches
a file behind a folder link was touched ==> un fichier derrière un lien de dossier a été touché
a file in use was not handled as expected ==> un fichier en cours d'utilisation n'a pas été géré comme prévu
a recent file was removed ==> un fichier récent a été supprimé
Analyze (A) ==> Analyse (A)
ANALYZE (nothing is deleted) ==> ANALYSE (rien n'est supprimé)
App Installer is not installed ==> le Programme d'installation d'application n'est pas installé
App updates with winget (28) ==> Mises à jour d'applis via winget (28)
Battery data (19) ==> Données de la batterie (19)
Boot records (18) ==> Relevés de démarrage (18)
BROKEN ==> ERREUR
Broken items are bugs in YSO or problems on this PC. Please send a report (P). ==> Les éléments en erreur sont des bugs d'YSO ou des problèmes de ce PC. Envoyez un rapport (P), s'il vous plaît.
Browsers found (2) ==> Navigateurs trouvés (2)
Checks every feature on this PC. Nothing on your PC is changed: it only uses its own test folder. ==> Vérifie chaque fonction sur ce PC. Rien n'est modifié sur votre PC : il utilise seulement son propre dossier de test.
choosing the size needs Windows 10 ==> le choix de la taille demande Windows 10
CLEAN (1-10) ==> NETTOYER (1-10)
CLEANING ENGINE ==> MOTEUR DE NETTOYAGE
connected, but ping is blocked or the internet is down ==> connecté, mais le ping est bloqué ou Internet est coupé
Continue anyway? ==> Continuer quand même ?
could not create a test link here ==> impossible de créer un lien de test ici
could not read this command line: {0} ==> impossible de lire cette ligne de commande : {0}
Could not save the report: {0} ==> Impossible d'enregistrer le rapport : {0}
Delivery Optimization cache (4) ==> Cache d'Optimisation distribution (4)
desktop ==> PC fixe
Device ==> Appareil
Device list (23) ==> Liste des périphériques (23)
DIAGNOSE & REPAIR (19-26) ==> DIAGNOSTIC ET RÉPARATION (19-26)
Disk Cleanup (8, 9) ==> Nettoyage de disque (8, 9)
Disk health data (19) ==> Santé des disques (19)
Display language ==> Langue de Windows
download folder not created yet ==> dossier de téléchargement pas encore créé
Drive error scan (24) ==> Recherche d'erreurs disque (24)
Drive optimization (15) ==> Optimisation des disques (15)
empty folders were left behind ==> des dossiers vides sont restés
Error: {0} ==> Erreur : {0}
Errors recorded ==> Erreurs enregistrées
Event logs (20) ==> Journaux d'événements (20)
Everything YSO needs works on this PC. ==> Tout ce dont YSO a besoin fonctionne sur ce PC.
explorer.exe was reported as {0} ==> explorer.exe est signalé comme {0}
Files in use are skipped ==> Les fichiers utilisés sont ignorés
firewall on for {0} of 3 networks ==> pare-feu actif sur {0} réseaux sur 3
firewall status unknown ==> état du pare-feu inconnu
Firewall, Secure Boot and TPM (21) ==> Pare-feu, démarrage sécurisé et TPM (21)
Fixed drives (all cleaning options) ==> Disques internes (tous les nettoyages)
Folder links are never followed ==> Les liens de dossier ne sont jamais suivis
Hardware rescan (23) ==> Réanalyse du matériel (23)
health {0} % ==> santé {0} %
Hibernation file (10) ==> Fichier de veille prolongée (10)
hibernation is off ==> veille prolongée désactivée
INFO ==> INFO
Internet connection (11) ==> Connexion Internet (11)
It still shows which programs and settings this PC has - open it and check before sending. ==> Il montre encore quels programmes et réglages ce PC possède - ouvrez-le et vérifiez avant de l'envoyer.
laptop ==> portable
last run {0}, result {1} ==> dernière exécution {0}, résultat {1}
legacy BIOS ==> BIOS ancien
Memory test (25) ==> Test de mémoire (25)
Microsoft Defender (21) ==> Microsoft Defender (21)
MISSING ==> ABSENT
Missing items are features this Windows does not have: those options are skipped or limited. ==> Les éléments absents sont des fonctions que ce Windows n'a pas : ces options sont ignorées ou limitées.
missing: {0} ==> manquant : {0}
needs Windows 10 version 1809 or later ==> demande Windows 10 version 1809 ou plus
needs Windows 10 version 2004 or later ==> demande Windows 10 version 2004 ou plus
YSO FILES ==> FICHIERS D'YSO
YSO is made for Windows 10 and 11. This PC runs an older Windows, so many options will not work. ==> YSO est conçu pour Windows 10 et 11. Ce PC a un Windows plus ancien : beaucoup d'options ne fonctionneront pas.
YSO stopped because of an unexpected error. The details were saved. ==> YSO s'est arrêté à cause d'une erreur inattendue. Les détails ont été enregistrés.
NETWORK (11-14) ==> RÉSEAU (11-14)
Network tools (11-14) ==> Outils réseau (11-14)
no battery ==> pas de batterie
no boot recorded yet - restart once ==> aucun démarrage enregistré - redémarrez une fois
no drives found ==> aucun disque trouvé
none yet - R turns System Restore on if needed ==> aucun pour l'instant - R active la Restauration si besoin
no supported browser found ==> aucun navigateur pris en charge trouvé
no TPM ==> pas de TPM
no Wi-Fi connection in use ==> pas de connexion Wi-Fi utilisée
not available on this Windows ==> indisponible sur ce Windows
not installed on this Windows ==> non installé sur ce Windows
not on this Windows version - that part is skipped ==> absent de cette version de Windows - cette partie est ignorée
not recording ==> n'enregistre pas
not run yet ==> pas encore exécuté
offline - the network tests will not work ==> hors ligne - les tests réseau ne fonctionneront pas
OK ==> OK
old file not removed: {0} ==> ancien fichier non supprimé : {0}
Older Windows: some options are limited - run T to see which. ==> Windows ancien : certaines options sont limitées - lancez T pour voir.
on, but its copy of YSO is missing - turn it off and on again (S) ==> activé, mais sa copie d'YSO a disparu - désactivez-le puis réactivez-le (S)
OPTIMIZE (15-18) ==> OPTIMISER (15-18)
Power plans (16) ==> Modes d'alimentation (16)
powercfg failed (code {0}) ==> échec de powercfg (code {0})
PowerShell ==> PowerShell
Press Enter to close ==> Appuyez sur Entrée pour fermer
real-time protection {0} ==> protection en temps réel {0}
Recycle Bin (5) ==> Corbeille (5)
Removed from it: user names, the PC name, private IP addresses and the Wi-Fi name. ==> Retirés du rapport : noms d'utilisateur, nom du PC, adresses IP privées et nom du Wi-Fi.
Removes old files, keeps recent ones ==> Supprime l'ancien, garde le récent
Report a problem ==> Signaler un problème
REPORT A PROBLEM ==> SIGNALER UN PROBLÈME
Report ready: {0} ==> Rapport prêt : {0}
Report saved: {0} ==> Rapport enregistré : {0}
Rescanning from here needs Windows 10 version 2004 or later. In Device Manager, use Action > Scan for hardware changes. ==> La réanalyse depuis YSO demande Windows 10 version 2004 ou plus. Dans le Gestionnaire de périphériques, utilisez Action > Rechercher les modifications sur le matériel.
Run the self-test first? (recommended, about a minute) ==> Lancer d'abord l'autotest ? (recommandé, environ une minute)
Self-test ==> Autotest
SELF-TEST ==> AUTOTEST
Self-test (check everything) ==> Autotest (tout vérifier)
SELF-TEST RESULT ==> RÉSULTAT DE L'AUTOTEST
server ==> serveur
Services and scheduled tasks (22) ==> Services et tâches planifiées (22)
Session log ==> Journal de session
Settings and logs folder ==> Dossier des paramètres et journaux
settings.json has an error ==> settings.json contient une erreur
Show it in Explorer? ==> L'afficher dans l'Explorateur ?
Signature checking (22) ==> Vérification des signatures (22)
Something went wrong in this option, so it stopped. The details were saved. ==> Un problème est survenu dans cette option, elle s'est donc arrêtée. Les détails ont été enregistrés.
Space finder (27) ==> Explorateur d'espace (27)
Start YSO again and use P (Report a problem) to send them. ==> Relancez YSO et utilisez P (Signaler un problème) pour les envoyer.
Startup programs (17) ==> Programmes au démarrage (17)
System repair tools (8, 26) ==> Outils de réparation système (8, 26)
System Restore (R, F) ==> Restauration du système (R, F)
the battery does not report its health ==> la batterie n'indique pas sa santé
the Diagnostic Policy Service is off, so boots are not recorded ==> le Service de stratégie de diagnostic est arrêté : les démarrages ne sont pas enregistrés
The rescan failed (code {0}). In Device Manager, use Action > Scan for hardware changes. ==> La réanalyse a échoué (code {0}). Dans le Gestionnaire de périphériques, utilisez Action > Rechercher les modifications sur le matériel.
This makes one zip file you can send (email, WhatsApp, GitHub...). Nothing is sent automatically. ==> Crée un seul fichier zip à envoyer (e-mail, WhatsApp, GitHub...). Rien n'est envoyé automatiquement.
THIS PC ==> CE PC
This step failed and was skipped: {0} ==> Cette étape a échoué et a été ignorée : {0}
Use P (Report a problem) to send them - it helps fix YSO. ==> Utilisez P (Signaler un problème) pour les envoyer - cela aide à corriger YSO.
User profiles ==> Profils utilisateur
uses an older copy: turn it off and on again (S) ==> utilise une ancienne copie : désactivez-le puis réactivez-le (S)
Weekly auto-clean (S) ==> Nettoyage automatique (S)
What went wrong? (one line, optional - press Enter to skip) ==> Quel est le problème ? (une ligne, facultatif - Entrée pour passer)
Wi-Fi signal (11) ==> Signal Wi-Fi (11)
Windows Update cache (4) ==> Cache de Windows Update (4)
Windows Update service not found ==> service Windows Update introuvable
winget did not answer ==> winget n'a pas répondu
your drives do not report wear or temperature ==> vos disques n'indiquent ni usure ni température
{0}: {1} free of {2} ({3:N0} %) ==> {0} : {1} libres sur {2} ({3:N0} %)
"{0}" is not finished. Stop it and close YSO? ==> « {0} » n'est pas terminé. L'arrêter et fermer YSO ?
{0} can be freed ==> {0} peuvent être libérés
{0} freed ==> {0} libérés
{0} keeps running in the background and finishes by itself. ==> {0} continue en arrière-plan et se termine tout seul.
A restore point is created first. ==> Un point de restauration est créé d'abord.
A task is still running ==> Une tâche est en cours
All tools ==> Tous les outils
Also install app and driver updates (adds 5-30 min) ==> Installer aussi les mises à jour des applis et pilotes (5 à 30 min de plus)
Analyze to see how much you can free ==> Lancez l'analyse pour voir ce que vous pouvez libérer
Analyze-only mode: nothing was deleted. ==> Mode analyse seule : rien n'a été supprimé.
can be freed with what is ticked ==> libérables avec ce qui est coché
Cancel ==> Annuler
Check ==> Vérifier
Check again ==> Vérifier à nouveau
Choose what to clean. Analyze first to see how much each part frees - it deletes nothing. ==> Choisissez ce qu'il faut nettoyer. Lancez d'abord l'analyse pour voir ce que chaque partie libère - elle ne supprime rien.
Chrome, Edge, Brave, Vivaldi, Opera, Firefox. Passwords, cookies, history and tabs stay. ==> Chrome, Edge, Brave, Vivaldi, Opera, Firefox. Mots de passe, cookies, historique et onglets sont conservés.
Clean ==> Nettoyer
Clean everything ==> Tout nettoyer
Clean everything? ==> Tout nettoyer ?
Clean selected ==> Nettoyer la sélection
Clean what is ticked? ==> Nettoyer ce qui est coché ?
Close ==> Fermer
Close {0} first, so their files can be cleaned (tabs come back, nothing is lost) ==> Fermer {0} d'abord, pour pouvoir nettoyer leurs fichiers (les onglets reviennent, rien n'est perdu)
Close open browsers and apps that keep files in use (tabs come back, nothing is lost) ==> Fermer les navigateurs et applis ouverts qui bloquent des fichiers (les onglets reviennent, rien n'est perdu)
Continue ==> Continuer
Copied to {0} ==> Copié dans {0}
Create a restore point first (recommended) ==> Créer d'abord un point de restauration (recommandé)
Details ==> Détails
Error reports, crash dumps, old logs and the thumbnail cache. ==> Rapports d'erreurs, vidages après plantage, anciens journaux et cache des miniatures.
Every option of YSO. Each one explains what it does and asks before changing anything. ==> Toutes les options de YSO. Chacune explique ce qu'elle fait et demande avant de modifier quoi que ce soit.
Finished. ==> Terminé.
Free disk space: {0} -> {1} ==> Espace libre : {0} -> {1}
Free space: {0} ==> Espace libre : {0}
Full maintenance, with a restore point first. ==> Entretien complet, avec un point de restauration d'abord.
Health report ==> Rapport de santé
History ==> Historique
Home ==> Accueil
INSTALL YSO ==> INSTALLER YSO
Keep running ==> Continuer la tâche
Keep the history, logs and settings of YSO ({0})? They are useful if you install it again. ==> Garder l'historique, les journaux et les réglages de YSO ({0}) ? Ils serviront si vous le réinstallez.
measured when it runs ==> mesuré pendant le nettoyage
No ==> Non
No old driver versions. ==> Aucune ancienne version de pilote.
nothing ==> rien
Nothing is ticked ==> Rien n'est coché
Nothing was changed. ==> Rien n'a été modifié.
npm, pip, VS Code, Discord, Teams, Spotify, Steam... and every app built on Chromium. ==> npm, pip, VS Code, Discord, Teams, Spotify, Steam... et toutes les applis basées sur Chromium.
Offline copies kept by websites and web apps. You stay logged in. ==> Copies hors ligne gardées par les sites et les applis web. Vous restez connecté.
Older copies of your drivers. You will not be able to go back to them. ==> Copies plus anciennes de vos pilotes. Vous ne pourrez plus y revenir.
Open ==> Ouvrir
Open browsers and apps that keep files in use are closed: tabs come back, nothing is lost. ==> Les navigateurs et applis ouverts qui bloquent des fichiers sont fermés : les onglets reviennent, rien n'est perdu.
Open the console ==> Ouvrir la console
Optimize drives at the end (TRIM / defrag) ==> Optimiser les disques à la fin (TRIM / défragmentation)
Options ==> Options
PC health ==> Santé du PC
Permanently deletes what is in the Recycle Bin. ==> Supprime définitivement le contenu de la Corbeille.
Read the result above, then continue. ==> Lisez le résultat ci-dessus, puis continuez.
Rebuilt by the graphics driver: games may stutter briefly the first time. ==> Reconstruits par le pilote graphique : les jeux peuvent saccader un peu la première fois.
See what can be freed. Deletes nothing. ==> Voir ce qui peut être libéré. Ne supprime rien.
Settings ==> Paramètres
Shortcuts created: Start menu and Desktop. ==> Raccourcis créés : menu Démarrer et Bureau.
Show it ==> Afficher
Something went wrong in the window: {0} ==> Un problème est survenu dans la fenêtre : {0}
Something went wrong. The details were saved: use Report a problem (P) to send them. ==> Un problème est survenu. Les détails ont été enregistrés : utilisez Signaler un problème (P) pour les envoyer.
Start ==> Démarrer
Start YSO from its file to install it. ==> Lancez YSO depuis son fichier pour l'installer.
Stop ==> Arrêter
Stop and close ==> Arrêter et fermer
Stopped at your request. ==> Arrêté à votre demande.
Stopped at your request. What was already cleaned stays cleaned. ==> Arrêté à votre demande. Ce qui a déjà été nettoyé le reste.
Stopped. ==> Arrêté.
Stopping... (a Windows tool that is running finishes first) ==> Arrêt en cours... (un outil Windows en cours se termine d'abord)
Temporary folders of every user and of Windows. Recent files are kept. ==> Dossiers temporaires de chaque utilisateur et de Windows. Les fichiers récents sont gardés.
The analysis did not finish: {0} ==> L'analyse ne s'est pas terminée : {0}
The installation failed: {0} ==> L'installation a échoué : {0}
The Recycle Bin is kept. ==> La Corbeille est conservée.
The window opened, but the part that does the work did not start: {0} ==> La fenêtre s'est ouverte, mais la partie qui fait le travail n'a pas démarré : {0}
Tick at least one line to clean. ==> Cochez au moins une ligne à nettoyer.
UNINSTALL YSO ==> DÉSINSTALLER YSO
Uninstall YSO? Its weekly cleanup and automatic updates stop too. ==> Désinstaller YSO ? Son nettoyage hebdomadaire et ses mises à jour automatiques s'arrêtent aussi.
Uninstalling failed: {0} ==> La désinstallation a échoué : {0}
unknown error ==> erreur inconnue
Updates that are already installed, and the Delivery Optimization cache. ==> Mises à jour déjà installées, et le cache de l'Optimisation de la distribution.
Wait until "{0}" is finished, or stop it first. ==> Attendez que « {0} » soit terminé, ou arrêtez-le d'abord.
Windows Disk Cleanup and the component store. Adds 10-30 minutes. ==> Nettoyage de disque de Windows et magasin des composants. 10 à 30 minutes de plus.
Windows is waiting for a restart (updates). Until then, the Windows Update cache and the component store cannot be cleaned. Best: Restart (not Shut down) first. ==> Windows attend un redémarrage (mises à jour). D'ici là, le cache de Windows Update et le magasin des composants ne peuvent pas être nettoyés. Le mieux : Redémarrer (pas Arrêter) d'abord.
With deep clean, it takes 15 to 40 minutes. You can keep using the PC. ==> Avec le nettoyage approfondi, cela prend 15 à 40 minutes. Vous pouvez continuer à utiliser le PC.
Working... ==> En cours...
Working... {0} min {1:00} s ==> En cours... {0} min {1:00} s
Yes ==> Oui
Your answer ==> Votre réponse
Your PC ==> Votre PC
YSO cleans: {0}. ==> YSO nettoie : {0}.
YSO could not start ==> YSO n'a pas pu démarrer
YSO could not start its engine: {0} ==> YSO n'a pas pu démarrer son moteur : {0}
YSO is already open. ==> YSO est déjà ouvert.
YSO is busy ==> YSO est occupé
YSO is installed: Start menu, Desktop, and Settings > Apps > Installed apps (to uninstall it). ==> YSO est installé : menu Démarrer, Bureau, et Paramètres > Applications > Applications installées (pour le désinstaller).
YSO was uninstalled. ==> YSO a été désinstallé.
Your answer is needed below. ==> Votre réponse est attendue ci-dessous.
{0} waiting: the cache is kept while there are any ==> {0} en attente : le cache est gardé tant qu'il y en a
Updates downloaded, not installed yet (4) ==> Mises à jour téléchargées, pas encore installées (4)
(and {0} more) ==> (et {0} autre(s))
Windows Update has downloaded updates it has not installed yet ({0}): its download cache is kept, or Windows would download them again. Install them (Settings > Windows Update), then clean again. ==> Windows Update a téléchargé des mises à jour qu'il n'a pas encore installées ({0}) : son cache de téléchargement est gardé, sinon Windows les retéléchargerait. Installez-les (Paramètres > Windows Update), puis nettoyez à nouveau.
Updates are waiting for a restart: the Windows Update download cache would be kept. ==> Des mises à jour attendent un redémarrage : le cache de téléchargement de Windows Update serait gardé.
Windows Settings ==> Paramètres Windows
Windows taskbar and notifications ==> Barre des tâches et notifications de Windows
Windows Get Help ==> Obtenir de l'aide (Windows)
Photos ==> Photos
{0}: the new version uses another installer than the installed one, so it cannot be updated in place. ==> {0} : la nouvelle version utilise un autre installateur que la version installée, elle ne peut donc pas être mise à jour directement.
A battery used this much cannot hold more than when it was new: its charge gauge is off, so its real wear is not known. ==> Une batterie aussi utilisée ne peut pas contenir plus que neuve : sa jauge de charge est faussée, son usure réelle n'est donc pas connue.
A corrected build of YSO {0} is published (same version, with fixes). ==> Une version corrigée de YSO {0} est publiée (même version, avec des corrections).
as good as new (it reports {0} %) ==> comme neuve (elle indique {0} %)
FIRMWARE (NOT INSTALLED BY YSO) ==> MICROLOGICIELS (NON INSTALLÉS PAR YSO)
Firmware updates change the BIOS or the built-in software of a device. YSO leaves them to Windows Update (Settings > Windows Update) or to your PC maker's app. ==> Les mises à jour de micrologiciel modifient le BIOS ou le logiciel intégré d'un appareil. YSO les laisse à Windows Update (Paramètres > Windows Update) ou à l'appli du fabricant de votre PC.
Install all of them (new major versions too) ==> Tout installer (nouvelles versions majeures comprises)
Install the fixes for YSO {0} ==> Installer les corrections de YSO {0}
Install the recommended ones ==> Installer celles recommandées
Or type numbers (e.g. 1,3 or 2-4), Enter = nothing ==> Ou tapez des numéros (ex. 1,3 ou 2-4), Entrée = rien
Reinstall {0}? YSO removes the installed version, then installs {1}. Most apps keep your data, but some forget their settings. ==> Réinstaller {0} ? YSO désinstalle la version installée, puis installe la {1}. La plupart des applis gardent vos données, mais certaines oublient leurs réglages.
removed, but the new version did not install: install it from its website ==> désinstallée, mais la nouvelle version ne s'est pas installée : installez-la depuis son site
reports {0} % after {1} charge cycles: its charge gauge needs a reset ==> indique {0} % après {1} cycles de charge : sa jauge de charge doit être réinitialisée
the download failed ==> le téléchargement a échoué
the installed version could not be removed ==> la version installée n'a pas pu être désinstallée
the new version uses another installer than the installed one ==> la nouvelle version utilise un autre installateur que la version installée
To reset the gauge: use the battery gauge reset of your PC maker's app (Lenovo Vantage has one), or charge to 100 %, let the PC run on battery down to about 5 % in one go, then charge to 100 % again. ==> Pour réinitialiser la jauge : utilisez la réinitialisation de jauge de batterie de l'appli du fabricant (Lenovo Vantage en a une), ou chargez à 100 %, laissez le PC sur batterie jusqu'à environ 5 % d'une traite, puis rechargez à 100 %.
Windows Update could not install it ==> Windows Update n'a pas pu l'installer
A new version of YSO is published on GitHub. ==> Une nouvelle version de YSO est publiée sur GitHub.
checked on GitHub when YSO opens ==> vérifiées sur GitHub à l'ouverture de YSO
Check for new versions of YSO ==> Vérifier les nouvelles versions de YSO
Checksum verified (SHA-256 {0}...). ==> Somme de contrôle vérifiée (SHA-256 {0}...).
Choose an option above, or type it here. ==> Choisissez une option ci-dessus, ou tapez-la ici.
Copied. ==> Copié.
Copy the text ==> Copier le texte
Downloading YSO {0} from GitHub... ==> Téléchargement de YSO {0} depuis GitHub...
Installed: {0}. New: {1}. ==> Installée : {0}. Nouvelle : {1}.
Later ==> Plus tard
Maximize ==> Agrandir
Minimize ==> Réduire
New versions of YSO ==> Nouvelles versions de YSO
not checked ==> non vérifiées
Restart YSO ==> Redémarrer YSO
Restart YSO to use the new version. ==> Redémarrez YSO pour utiliser la nouvelle version.
Settings folder only changed by administrators ==> Dossier des réglages modifiable seulement par les administrateurs
standard users can change files in {0} ==> les utilisateurs standard peuvent modifier les fichiers de {0}
Stop checking for new versions of YSO ==> Ne plus vérifier les nouvelles versions de YSO
The download does not match its SHA-256 checksum: nothing was changed. ==> Le téléchargement ne correspond pas à sa somme SHA-256 : rien n'a été modifié.
The downloaded file is not a complete YSO of that version: nothing was changed. ==> Le fichier téléchargé n'est pas un YSO complet de cette version : rien n'a été modifié.
The update failed: {0} ==> La mise à jour a échoué : {0}
Update now ==> Mettre à jour
Update to YSO {0} ==> Passer à YSO {0}
Update YSO ==> Mettre à jour YSO
Your answer: {0} ==> Votre réponse : {0}
YSO {0} is available ==> YSO {0} est disponible
YSO {0} is installed ==> YSO {0} est installé
YSO {0} is installed. ==> YSO {0} est installé.
YSO downloads it from GitHub, checks its SHA-256 checksum, then replaces itself. Your settings and history stay. ==> YSO la télécharge depuis GitHub, vérifie sa somme SHA-256, puis se remplace. Vos réglages et votre historique sont conservés.
The YSO window could not open, so YSO opens its console menu instead. The details were saved: use P (Report a problem) to send them. ==> La fenêtre de YSO n'a pas pu s'ouvrir : YSO ouvre son menu console à la place. Les détails ont été enregistrés : utilisez P (Signaler un problème) pour les envoyer.
'@
    $h = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    foreach ($line in ($pairs -split "`r?`n")) {
        $i = $line.IndexOf(' ==> ')
        if ($i -gt 0) { $h[$line.Substring(0, $i)] = $line.Substring($i + 5).TrimEnd() }
    }
    return $h
}

# ==================================================================
#  Start
# ==================================================================
try {
    if ($Engine) {
        # The window's second PowerShell (see Start-GuiWorker): YSO's functions and settings, nothing else.
        $script:FR = Get-FrenchStrings
        Import-Settings
        $script:OsText = Get-OsText
        $script:Profiles = @(Get-ProfilePaths)
        return
    }
    Protect-YsoDataDir
    try { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null } catch { }
    Get-ChildItem -LiteralPath $script:LogDir -Filter 'yso_*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip 30 |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $script:FR = Get-FrenchStrings
    Import-Settings
    $script:OsText = Get-OsText

    if (-not (Test-Unattended) -and $script:OsMajor -lt 10) {
        Write-Host ''
        Write-Warn 'YSO is made for Windows 10 and 11. This PC runs an older Windows, so many options will not work.'
        if (-not (Confirm-Action 'Continue anyway?' $false)) { exit 3 }
    }

    $logFile = Join-Path $script:LogDir ('yso_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))
    try { Start-Transcript -Path $logFile -Force | Out-Null; $script:TranscriptOn = $true } catch { }
    $script:Profiles = @(Get-ProfilePaths)
    try { $Host.UI.RawUI.WindowTitle = "YSO - Your System Optimizer v$($script:Version)" } catch { }

    if ($Install -or $Uninstall) {
        $done = if ($Install) { Install-Yso } else { Uninstall-Yso }
        try { Stop-Transcript | Out-Null } catch { }
        if ($Install -and $done) { Start-YsoInstalled }
        if ($done) { exit 0 }
        exit 1
    }

    if ($Auto) {
        Write-Host ('YSO auto-clean - {0:yyyy-MM-dd HH:mm} - {1}' -f (Get-Date), $script:OsText)
        $freeBefore = Get-FreeBytes
        $ac = $script:Settings.AutoClean
        if ($ac.TempFiles)     { Invoke-Step 'auto: temporary files' { Clear-TempFiles } }
        if ($ac.BrowserCaches) { Invoke-Step 'auto: browser caches' { Clear-BrowserCaches -NoPrompt } }
        if ($ac.SystemJunk)    { Invoke-Step 'auto: system junk' { Clear-SystemJunk } }
        if ($ac.UpdateCache)   { Invoke-Step 'auto: Windows Update cache' { Clear-UpdateCache } }
        if ($ac.ShaderCaches)  { Invoke-Step 'auto: GPU shader caches' { Clear-ShaderCaches } }
        if ($ac.DevAppCaches)  { Invoke-Step 'auto: developer & app caches' { Clear-DevAppCaches -NoPrompt } }
        if ($ac.SiteOfflineCaches) { Invoke-Step 'auto: site offline caches' { Clear-SiteOfflineCaches -Confirmed } }
        Show-Summary -FreeBefore $freeBefore
        Save-History (N 'Auto')
        try { Stop-Transcript | Out-Null } catch { }
        if ($script:ErrorCount -gt 0) { exit 1 }
        exit 0
    }

    if ($AutoUpdate) {
        Write-Host ('YSO automatic updates - {0:yyyy-MM-dd HH:mm} - {1}' -f (Get-Date), $script:OsText)
        $script:UpdateSummary = $null
        Invoke-Step 'auto: updates' { $script:UpdateSummary = Invoke-UpdateRun -Mode 'Auto' }
        try { Stop-Transcript | Out-Null } catch { }
        if ($script:ErrorCount -gt 0 -or ($script:UpdateSummary -and $script:UpdateSummary.NotInstalled -gt 0)) { exit 1 }
        exit 0
    }

    if ($SelfTest) {
        Invoke-SelfTest
        try { Stop-Transcript | Out-Null } catch { }
        exit ([int]$script:LastSelfTestBroken)
    }

    if ($script:SettingsError) { Write-Warn 'settings.json has an error, so defaults are in use. Fix it in Settings (O).'; Start-Sleep -Seconds 2 }
    Update-YsoCopy

    # The window, unless the console was asked for (or the window cannot open on this PC).
    if (-not $Console) {
        $how = Start-YsoWindow -Snapshot $Snapshot
        if ($how -ne 'unavailable' -or $Snapshot) {
            try { Stop-Transcript | Out-Null } catch { }
            # [Environment]::Exit: a job the window asked to stop must not keep this process alive
            [Environment]::Exit($(if ($how -eq 'closed') { 0 } else { 1 }))
        }
        # No window on this PC: the console menu, in a console you can see - and why, when it was an error.
        if ($script:GuiFailure) {
            $why = L 'The YSO window could not open, so YSO opens its console menu instead. The details were saved: use P (Report a problem) to send them.'
            try { [void][System.Windows.MessageBox]::Show(($why + "`n`n" + $script:GuiFailure), 'YSO', 'OK', 'Warning') } catch { Write-Warn $why }
        }
        if (-not (Test-ConsoleVisible)) { Start-YsoConsole; try { Stop-Transcript | Out-Null } catch { }; exit 0 }
    }

    :main while ($true) {
        Show-Menu
        $choice = "$(Read-Host '  root@yso:~#')".Trim().ToUpper()
        if ($choice -eq 'Q') { break main }
        if ($choice -eq 'M') {
            $script:Settings.MenuMode = $(if ($script:Settings.MenuMode -eq 'simple') { 'advanced' } else { 'simple' })
            [void](Save-Settings)
            continue main
        }
        if ($choice -eq 'L') { Start-Process explorer.exe -ArgumentList "`"$($script:LogDir)`""; continue main }
        if ($script:MenuKeys -notcontains $choice) { continue main }
        $script:HealthCache = $null
        Write-Host ''
        Invoke-MenuOption $choice
        # Options with their own menu (17, 28, R, O) come back here directly - unless something went wrong.
        if (@('17', '28', 'R', 'O') -contains $choice -and $script:LastRun.Status -eq 'done') { continue main }
        Wait-Key
    }
} catch {
    Write-YsoError -Context 'YSO (outside an option)' -ErrorRecord $_
    Write-Host ''
    Write-Bad 'YSO stopped because of an unexpected error. The details were saved.'
    Write-Info (L 'Error: {0}' $_.Exception.Message)
    Write-Info 'Start YSO again and use P (Report a problem) to send them.'
    try { Stop-Transcript | Out-Null } catch { }
    if (-not $Auto -and -not $SelfTest) { [void](Read-Host ('  ' + (L 'Press Enter to close'))) }
    exit 1
}
try { Stop-Transcript | Out-Null } catch { }
exit 0
