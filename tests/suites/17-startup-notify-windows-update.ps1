param([string]$ScriptPath, [string]$Sandbox)
# Switching startup programs on and off (exactly like Task Manager), the "notify me" mode
# of updates, and the state of Windows Update.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force "$Sandbox/tmp", "$Sandbox/Startup" | Out-Null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
$defs = @{}
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $defs[$fn.Name] = $fn.Extent.Text; Invoke-Expression $fn.Extent.Text }
function Restore-Real([string]$Name) { Invoke-Expression $defs[$Name] }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $env:ProgramFiles = "$Sandbox/ProgramFiles"
$DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
Import-Settings
New-Item -ItemType Directory -Force $script:DataDir | Out-Null
function Clear-Host { } function Start-Sleep { }
$script:Answers = New-Object System.Collections.Queue
function Read-Host { param($Prompt) if ($script:Answers.Count -gt 0) { $script:Answers.Dequeue() } else { '' } }

Write-Host "`n===== STARTUP PROGRAMS: ON / OFF LIKE TASK MANAGER =====" -ForegroundColor White
# A fake registry: Run keys (name -> command) and StartupApproved keys (name -> bytes)
$script:Reg = @{
    'HKCU:\Run' = [ordered]@{ OneDrive = '"C:\Users\Alex\AppData\Local\Microsoft\OneDrive\OneDrive.exe" /background'; Spotify = 'C:\Users\Alex\AppData\Roaming\Spotify\Spotify.exe /minimized' }
    'HKLM:\Run' = [ordered]@{ SecurityHealth = '%windir%\system32\SecurityHealthSystray.exe'; RtkAudio = '"C:\Program Files\Realtek\Audio\RtkAudUService64.exe" -background' }
}
$script:Approved = @{
    'HKCU:\Approved\Run' = @{ Spotify = [byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8) }
    'HKLM:\Approved\Run' = @{ RtkAudio = [byte[]](7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); SecurityHealth = [byte[]](6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
    'HKCU:\Approved\StartupFolder' = @{}
}
function Get-StartupSources { @(
    @{ Type = 'Run'; Path = 'HKCU:\Run'; Approved = 'HKCU:\Approved\Run'; Scope = 'you' },
    @{ Type = 'Run'; Path = 'HKLM:\Run'; Approved = 'HKLM:\Approved\Run'; Scope = 'everyone' },
    @{ Type = 'Folder'; Path = "$Sandbox/Startup"; Approved = 'HKCU:\Approved\StartupFolder'; Scope = 'you' }) }
function Get-RunValues([string]$Key) { $script:Reg[$Key] }
function Get-ApprovedBytes([string]$Key, [string]$Name) { $h = $script:Approved[$Key]; if ($h -and $h.ContainsKey($Name)) { return , $h[$Name] } return $null }
function Set-ApprovedBytes([string]$Key, [string]$Name, [byte[]]$Bytes) { if (-not $script:Approved[$Key]) { $script:Approved[$Key] = @{} }; $script:Approved[$Key][$Name] = $Bytes }
function Get-ShortcutTarget([string]$Path) { 'C:\Program Files\Notes\notes.exe' }
$script:SigCalls = 0
function Get-SignerInfo([string]$Path) {
    $script:SigCalls++
    if ($Path -match 'SecurityHealth') { return [pscustomobject]@{ Status = 'Valid'; Signer = 'Microsoft Windows Publisher' } }
    if ($Path -match 'OneDrive') { return [pscustomobject]@{ Status = 'Valid'; Signer = 'Microsoft Corporation' } }
    if ($Path -match 'Spotify') { return [pscustomobject]@{ Status = 'Valid'; Signer = 'Spotify AB' } }
    return [pscustomobject]@{ Status = 'NotSigned'; Signer = '' }
}
New-Item -ItemType File -Force "$Sandbox/Startup/Notes.lnk" | Out-Null
New-Item -ItemType File -Force "$Sandbox/Startup/desktop.ini" | Out-Null
$e = @(Get-StartupEntries)
$byName = @{}; foreach ($x in $e) { $byName[$x.Name] = $x }
Check ($e.Count -eq 5 -and -not $byName.ContainsKey('desktop')) "5 entries from the Run keys and the Startup folder ($($e.Count))"
Check ($byName['OneDrive'].Enabled -and -not $byName['Spotify'].Enabled -and -not $byName['RtkAudio'].Enabled -and $byName['SecurityHealth'].Enabled -and $byName['Notes'].Enabled) 'on/off read like Task Manager: 02/06 = on, 03/07 = off, nothing = on'
Check ($byName['SecurityHealth'].IsWindows -and -not $byName['OneDrive'].IsWindows -and $byName['Notes'].Command -eq 'C:\Program Files\Notes\notes.exe') 'Windows parts recognised; shortcuts followed to their program'
$script:SigCalls = 0; [void](Get-StartupEntries -Fast)
Check ($script:SigCalls -eq 0) 'counting them (health screen) skips the slow signature checks'
$before = Get-Date
Set-StartupEntryState $byName['OneDrive'] $false
$b = $script:Approved['HKCU:\Approved\Run']['OneDrive']
$when = [datetime]::FromFileTimeUtc([BitConverter]::ToInt64($b, 4)).ToLocalTime()
Check ($b.Length -eq 12 -and $b[0] -eq 3 -and $b[1] -eq 0 -and [math]::Abs(($when - $before).TotalSeconds) -lt 60) 'off = 03 00 00 00 + the time, exactly what Task Manager writes'
Set-StartupEntryState $byName['Spotify'] $true
Check ((@($script:Approved['HKCU:\Approved\Run']['Spotify']) -join ',') -eq '2,0,0,0,0,0,0,0,0,0,0,0') 'on = 02 and zeros'
Check ($script:Reg['HKCU:\Run'].Contains('OneDrive')) 'switching off never deletes the entry'
$log = @(Import-Csv -LiteralPath (Join-Path $script:DataDir 'startup-changes.csv'))
Check ($log.Count -eq 2 -and $log[0].Name -eq 'OneDrive' -and $log[0].State -eq 'off') 'every change is written down (startup-changes.csv)'
function Get-BootSlowApps { @{ 'rtkaudservice64.exe' = 0; 'spotify.exe' = 4.2 } }
$script:Asked = @()
function Confirm-Action { param($Question, $Default) $script:Asked += $Question; $false }
$script:Lang = 'fr'
$list = @(Get-StartupEntries | Sort-Object @{ Expression = { -not $_.Enabled } }, Name)
$sec = [array]::IndexOf(@($list | ForEach-Object { $_.Name }), 'SecurityHealth') + 1
foreach ($a in @("$sec", '')) { $script:Answers.Enqueue($a) }
$out = (Show-StartupApps 6>&1 | Out-String)
$script:Lang = 'en'
Check ($script:Asked.Count -eq 1 -and $script:Asked[0] -like '*fait partie de Windows*' -and (Get-ApprovedBytes 'HKLM:\Approved\Run' 'SecurityHealth')[0] -eq 6) 'a part of Windows asks first, and stays on when you say no'
Check ($out -match 'PROGRAMMES QUI DÉMARRENT AVEC WINDOWS' -and $out -match 'Spotify AB' -and $out -match '\+4[,.]2 s au démarrage' -and $out -match '\(non signé\)') 'the list (French): publisher, unsigned ones, what slows the boot'
Restore-Real 'Confirm-Action'

Write-Host "`n===== UPDATES: NOTIFY ME =====" -ForegroundColor White
$script:Calls = New-Object System.Collections.Generic.List[string]
$script:AppList = @([pscustomobject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.43.0'; Available = '2.47.1'; Table = 'Normal'; Note = '' })
function Get-AppUpdates { [pscustomobject]@{ Ok = $true; Reason = ''; ReasonArg = ''; Apps = $script:AppList; Others = @(); Raw = @(); ParseFailed = $false } }
function Get-AppsInUse($Items) { @() }
function Get-DriverUpdates { [pscustomobject]@{ Ok = $true; Reason = ''; ReasonArg = ''; Drivers = @([pscustomobject]@{ Kind = 'Driver'; Name = 'Intel - Display'; Id = 'd1'; From = ''; To = '2026-09-01'; Class = 'Display'; Optional = $false; Excluded = $false; InUse = $false; Major = $false; Update = $null }) } }
function Install-AppUpdate($Item) { $script:Calls.Add("install $($Item.Id)"); New-UpdateResult $Item 'Updated' '0x00000000' }
function Install-DriverUpdates($Drivers) { foreach ($x in $Drivers) { $script:Calls.Add("driver $($x.Id)") } }
function New-YsoRestorePoint { param([switch]$Quiet) $script:Calls.Add('restore point'); $true }
function Show-Toast($Title, $Text) { $script:Calls.Add("toast $Text") }
$script:Settings.Updates.Mode = 'notify'
$AutoUpdate = $true
[void](Invoke-UpdateRun -Mode 'Auto' 6>$null)
Check (@($script:Calls | Where-Object { $_ -like 'install*' -or $_ -like 'driver*' -or $_ -like 'restore*' }).Count -eq 0) 'notify only: nothing installed, no restore point'
Check (@($script:Calls | Where-Object { $_ -like 'toast 2 update(s) available (1 app(s), 1 driver(s))*' }).Count -eq 1) 'one notification with what is available'
$script:Calls.Clear(); [void](Invoke-UpdateRun -Mode 'Auto' 6>$null)
Check (@($script:Calls | Where-Object { $_ -like 'toast*' }).Count -eq 0) 'the same updates the next day: no second notification'
$script:AppList += [pscustomobject]@{ Name = 'Zoom'; Id = 'Zoom.Zoom'; Version = '6.1'; Available = '6.2'; Table = 'Normal'; Note = '' }
$script:Calls.Clear(); [void](Invoke-UpdateRun -Mode 'Auto' 6>$null)
Check (@($script:Calls | Where-Object { $_ -like 'toast 3 update(s)*' }).Count -eq 1) 'a new update: notified again'
$runs = @(Get-UpdateHistoryRows | Where-Object { $_.Kind -eq 'Run' })
Check ($runs.Count -eq 3 -and $runs[-1].Mode -eq 'Notify' -and $runs[-1].Found -eq '3') 'each check is in the history (mode Notify)'
$script:Settings.Updates.Mode = 'auto'
$script:Calls.Clear(); [void](Invoke-UpdateRun -Mode 'Auto' 6>$null)
$AutoUpdate = $false
Check ($script:Calls -contains 'install Git.Git' -and $script:Calls -contains 'driver d1') 'automatic mode installs again'
$script:Tasks = New-Object System.Collections.Generic.List[string]
function Get-ScheduledTask { param($TaskName, $ErrorAction) if ($script:Tasks -contains $TaskName) { [pscustomobject]@{ TaskName = $TaskName } } }
function Register-UpdateTask { if ($script:Tasks -notcontains $script:UpdateTaskName) { $script:Tasks.Add($script:UpdateTaskName) }; $true }
function Unregister-ScheduledTask { param($TaskName, [switch]$Confirm, $ErrorAction) [void]$script:Tasks.Remove($TaskName) }
function Confirm-Action { param($Question, $Default) $true }
Set-UpdateMode 'notify' 6>$null
Check ((Get-UpdateMode) -eq 'notify' -and $script:Tasks -contains 'YSO Auto Updates' -and $script:Settings.Updates.Mode -eq 'notify') 'notify me: the task runs on schedule, the mode is saved'
Set-UpdateMode 'auto' 6>$null
Check ((Get-UpdateMode) -eq 'auto') 'automatic'
Set-UpdateMode 'manual' 6>$null
Check ((Get-UpdateMode) -eq 'manual' -and $script:Tasks.Count -eq 0) 'manual: no task left'
$script:Tasks.Add('YSO Auto Updates'); $script:Settings.Updates.Mode = 'manual'
Check ((Get-UpdateMode) -eq 'auto') 'a task made before the mode was saved counts as automatic'
$script:Settings.Updates.Mode = 'notify'
function Get-Volume { }
$out = (Show-Menu -Width 120 -Mode 'advanced' 6>&1 | Out-String)
Check ($out -match '28\s+Updates: apps & drivers \[NOTIFY\]') 'the menu shows [NOTIFY]'
Restore-Real 'Confirm-Action'

Write-Host "`n===== WINDOWS UPDATE STATUS =====" -ForegroundColor White
function New-Hist($Date, $Op, $Code) { [pscustomobject]@{ Date = $Date; Operation = $Op; ResultCode = $Code; Title = 'KB' } }
$script:Hist = @((New-Hist ([datetime]'2026-10-20T08:00:00Z') 1 4), (New-Hist ([datetime]'2026-10-14T08:00:00Z') 1 2), (New-Hist ([datetime]'2026-10-22T08:00:00Z') 2 2), (New-Hist ([datetime]'2026-09-10T08:00:00Z') 1 3))
function New-UpdateSession {
    $s = [pscustomobject]@{}
    $s | Add-Member -MemberType ScriptMethod -Name CreateUpdateSearcher -Value {
        $q = [pscustomobject]@{ Online = $true }
        $q | Add-Member -MemberType ScriptMethod -Name GetTotalHistoryCount -Value { $script:Hist.Count }
        $q | Add-Member -MemberType ScriptMethod -Name QueryHistory -Value { param($a, $b)
            $c = [pscustomobject]@{ L = $script:Hist }
            $c | Add-Member -MemberType ScriptProperty -Name Count -Value { $this.L.Count }
            $c | Add-Member -MemberType ScriptMethod -Name Item -Value { param($i) $this.L[$i] }
            $c }
        $q | Add-Member -MemberType ScriptMethod -Name Search -Value { param($c) $script:SearchedOnline = $this.Online; [pscustomobject]@{ Updates = [pscustomobject]@{ Count = 3 } } }
        $q }
    return $s
}
function Get-Service { param($Name, $ErrorAction) [pscustomobject]@{ Status = 'Running'; StartType = $script:WuStart } }
$script:WuStart = 'Manual'
function Test-PendingReboot { $true }
$st = Get-WindowsUpdateStatus -Pending
Check ($st.LastInstall.ToUniversalTime().Date -eq [datetime]'2026-10-14' -and -not $st.Disabled) 'last update = the last successful install (not a failed one, not an uninstall)'
Check ($st.Pending -eq 3 -and $script:SearchedOnline -eq $false -and $st.RestartPending) 'waiting updates counted from what Windows already knows (no download), restart pending seen'
$script:WuStart = 'Disabled'
Check ((Get-WindowsUpdateStatus).Disabled) 'a disabled Windows Update is seen'
$script:Hist = @()
function Get-HotFix { param($ErrorAction) @([pscustomobject]@{ InstalledOn = [datetime]'2026-08-01' }, [pscustomobject]@{ InstalledOn = [datetime]'2026-10-01' }) }
Check ((Get-WindowsUpdateStatus).LastInstall -eq [datetime]'2026-10-01') 'no history: the installed hotfixes are used instead'
Check ((Format-DaysAgo (Get-Date)) -eq 'today' -and (Format-DaysAgo (Get-Date).AddDays(-1)) -eq 'yesterday' -and (Format-DaysAgo (Get-Date).AddDays(-12)) -eq '12 days ago' -and (Format-DaysAgo $null) -eq 'unknown') 'today / yesterday / 12 days ago / unknown'
$script:Lang = 'fr'
Check ((Format-DaysAgo (Get-Date).AddDays(-12)) -eq 'il y a 12 jours') 'il y a 12 jours'
$script:Lang = 'en'

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
