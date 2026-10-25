param([string]$ScriptPath, [string]$Sandbox, [string]$Pwsh, [string]$Child)
# The PC health screen, progress bars (and the hook a graphical interface will use),
# the simple menu and the full menu.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force "$Sandbox/tmp" | Out-Null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
$defs = @{}
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $defs[$fn.Name] = $fn.Extent.Text; Invoke-Expression $fn.Extent.Text }
function Restore-Real([string]$Name) { Invoke-Expression $defs[$Name] }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $env:SystemDrive = 'C:'
$DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
Import-Settings
New-Item -ItemType Directory -Force $script:DataDir | Out-Null

Write-Host "`n===== PC HEALTH =====" -ForegroundColor White
function Get-FixedVolumes { @([pscustomobject]@{ DriveLetter = 'C'; Size = 500GB; SizeRemaining = 40GB }) }
function Get-PhysicalDisk { param($ErrorAction) if ($script:DiskBroken) { throw 'no storage module' } @([pscustomobject]@{ HealthStatus = 'Healthy'; MediaType = 'SSD' }) }
function Get-StorageReliabilityCounter { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { [pscustomobject]@{ Wear = 85 } } }
function Test-IsLaptop { $true }
function Get-BatteryHealth { [pscustomobject]@{ Percent = 59; Cycles = $null } }
function Get-WindowsUpdateStatus { [pscustomobject]@{ Disabled = $false; LastInstall = (Get-Date).AddDays(-100); LastCheck = $null; Pending = $null; RestartPending = $true } }
function Get-MpComputerStatus { param($ErrorAction) [pscustomobject]@{ RealTimeProtectionEnabled = $true; AntivirusSignatureAge = 2 } }
function Get-StartupEntries { param([switch]$Fast) $script:FastAsked = [bool]$Fast; 1..14 | ForEach-Object { [pscustomobject]@{ Enabled = $true } }; [pscustomobject]@{ Enabled = $false } }
function Get-ScheduledTask { param($TaskName, $ErrorAction) }
function Get-CimInstance { param($ClassName, $Namespace, $ErrorAction) if ($ClassName -eq 'Win32_OperatingSystem') { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddDays(-20) } } else { throw 'no CIM' } }
[pscustomobject]@{ Run = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd HH:mm:ss.fff'); Mode = 'Manual'; Category = 'Temporary files'; Files = 3; Bytes = 1000 } |
    Export-Csv -LiteralPath $script:HistoryPath -NoTypeInformation
$items = @(Get-HealthItems)
$h = @{}; foreach ($i in $items) { $h[$i.Name] = $i }
$items | ForEach-Object { Write-Host ('      {0,-5} {1,-18} {2}  {3}' -f $_.Level, $_.Name, $_.Text, $_.Action) -ForegroundColor DarkGray }
Check ($h['Disk space'].Level -eq 'Warn' -and $h['Disk space'].Text -match '^C: 40[.,]00 GB free of 500[.,]00 GB \(8 %\)$' -and $h['Disk space'].Action -eq 'F') 'disk space 8 % free: orange, F helps'
Check ($h['Disk health'].Level -eq 'Warn' -and $h['Disk health'].Text -match 'worn \(85 %\)') 'a worn SSD (85 %): orange'
Check ($h['Battery'].Level -eq 'Bad' -and $h['Battery'].Action -eq '19') 'a battery at 59 %: red'
Check ($h['Windows Update'].Level -eq 'Bad' -and $h['Windows Update'].Text -match '100 days ago - restart to finish') 'no update for 100 days, restart pending: red'
Check ($h['Security'].Level -eq 'Good' -and $h['Security'].Text -eq 'Microsoft Defender on') 'Defender on: green'
Check ($h['Startup programs'].Level -eq 'Warn' -and $h['Startup programs'].Text -eq '14 start with Windows' -and $h['Startup programs'].Action -eq '17' -and $script:FastAsked) '14 startup programs: orange, 17 helps (counted without signature checks)'
Check ($h['Cleaning'].Level -eq 'Good' -and $h['Cleaning'].Text -eq 'last cleanup 3 days ago') 'cleaned 3 days ago: green'
Check ($h['App updates'].Level -eq 'Info' -and $h['App updates'].Action -eq '28') 'updates manual and never checked: information, 28 helps'
Check ($h['Restart'].Level -eq 'Warn' -and $h['Restart'].Text -match '20 days') 'not restarted for 20 days: orange'
$script:DiskBroken = $true
$items2 = @(Get-HealthItems)
Check (@($items2 | Where-Object { $_.Name -eq 'Disk health' }).Count -eq 0 -and $items2.Count -eq ($items.Count - 1)) 'a check that fails disappears, the others stay'
$script:DiskBroken = $false
function Get-MpComputerStatus { param($ErrorAction) throw 'Defender is off' }
function Get-CimInstance { param($ClassName, $Namespace, $ErrorAction) if ($ClassName -eq 'AntiVirusProduct') { [pscustomobject]@{ displayName = 'Bitdefender'; productState = 266240 }; [pscustomobject]@{ displayName = 'Windows Defender'; productState = 393472 } } elseif ($ClassName -eq 'Win32_OperatingSystem') { [pscustomobject]@{ LastBootUpTime = (Get-Date) } } else { throw 'no CIM' } }
$s = @(Get-HealthItems) | Where-Object { $_.Name -eq 'Security' }
Check ($s.Level -eq 'Good' -and $s.Text -eq 'Bitdefender on') 'another antivirus that is on: green (the one that is off is not named)'
function Get-CimInstance { param($ClassName, $Namespace, $ErrorAction) if ($ClassName -eq 'AntiVirusProduct') { @() } elseif ($ClassName -eq 'Win32_OperatingSystem') { [pscustomobject]@{ LastBootUpTime = (Get-Date) } } else { throw 'no CIM' } }
$s = @(Get-HealthItems) | Where-Object { $_.Name -eq 'Security' }
Check ($s.Level -eq 'Bad' -and $s.Action -eq '21') 'no antivirus at all: red, 21 helps'
$script:Lang = 'fr'
$out = (Show-HealthDashboard $items 6>&1 | Out-String)
$script:Lang = 'en'
Check ($out -match '!!' -and $out -match 'XX' -and $out -match ' OK ' -and $out -match 'Espace disque' -and $out -match 'Batterie' -and $out -match '-> 19') 'shown with OK / !! / XX and the option that helps (French)'
$script:Count = 0
function Get-HealthItems { $script:Count++; @(New-HealthItem 'Disk space' 'Good' 'x') }
$script:HealthCache = $null
[void](Get-HealthItemsCached); [void](Get-HealthItemsCached)
Check ($script:Count -eq 1) 'measured once, then kept for the menu'
$script:HealthCache = $null; [void](Get-HealthItemsCached)
Check ($script:Count -eq 2) 'measured again after an option ran'

Write-Host "`n===== PROGRESS =====" -ForegroundColor White
$script:Progress = New-Object System.Collections.Generic.List[object]
$script:ProgressHandler = { param($Activity, $Status, $Percent, $Completed, $Id) $script:Progress.Add([pscustomobject]@{ A = $Activity; S = $Status; P = $Percent; C = $Completed; Id = $Id }) }
$dir = "$Sandbox/many"
New-Item -ItemType Directory -Force $dir | Out-Null
1..300 | ForEach-Object { [IO.File]::WriteAllBytes("$dir/f$_.tmp", (New-Object byte[] 10)) }
[void](Invoke-Purge -Category 'Temporary files' -Targets @(@{ Path = (Esc $dir) }) -Quiet)
$mine = @($script:Progress | Where-Object { $_.A -eq 'Temporary files' })
Check ($mine.Count -ge 12 -and $mine.Count -le 20 -and $mine[-1].C -and ($mine | Where-Object { -not $_.C } | Select-Object -Last 1).P -eq 100) "the deletion engine reports its progress every 25 files (a graphical interface just sets one handler) - $($mine.Count) updates for 300 files"
$script:Progress.Clear()
Invoke-Plan -Activity 'Full maintenance' -Steps @(@('t: one', 'Temporary files', { }), @('t: two', 'Browser caches', { throw 'boom' }), @('t: three', 'System junk', { })) 6>$null
$plan = @($script:Progress | Where-Object { $_.Id -eq 0 })
Check ($plan.Count -eq 4 -and $plan[1].S -eq 'step 2 of 3: Browser caches' -and $plan[2].P -eq 67 -and $plan[-1].C) 'F and A show "step 2 of 3: Browser caches" with a percentage'
Check ($script:ErrorCount -ge 1) 'a failing step is saved and the next ones still run'
$script:Progress.Clear()
$fake = [pscustomobject]@{ N = 0 }
$fake | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $this.N++; return ($this.N -ge 3) }
Wait-ProcessWithProgress $fake 'Component store'
Check (@($script:Progress | Where-Object { $_.A -eq 'Component store' -and $_.S -like 'working for 0 min*' }).Count -eq 2 -and $script:Progress[-1].C) 'Windows tools without a percentage show the time spent'
$script:ProgressHandler = $null
$Auto = $true
Write-YsoProgress -Activity 'x' -Status 'y' -Force
$Auto = $false
Check ($true) 'scheduled tasks (no window) skip progress bars quietly'

Write-Host "`n===== SIMPLE MENU AND FULL MENU =====" -ForegroundColor White
$script:sb = New-Object System.Text.StringBuilder; $script:capture = $false
function Write-Host { param([Parameter(Position = 0)]$Object, [switch]$NoNewline, $ForegroundColor, $BackgroundColor)
    if ($script:capture) { [void]$script:sb.Append("$Object"); if (-not $NoNewline) { [void]$script:sb.Append("`n") }; return }
    Microsoft.PowerShell.Utility\Write-Host $Object -NoNewline:$NoNewline }
function Clear-Host { }
function Get-HealthItemsCached { @((New-HealthItem 'Disk space' 'Warn' 'C: 40.0 GB free of 500.0 GB (8 %)' 'F'), (New-HealthItem 'Battery' 'Bad' '59 % of its original capacity' '19'), (New-HealthItem 'Security' 'Good' 'Microsoft Defender on')) }
function Get-UpdateMode { 'auto' }
function Get-MenuText([string]$Mode, [string]$Lang, [int]$Width = 120) {
    [void]$script:sb.Clear(); $script:capture = $true; $script:Lang = $Lang
    try { Show-Menu -Width $Width -Mode $Mode } finally { $script:capture = $false; $script:Lang = 'en' }
    return $script:sb.ToString()
}
foreach ($lg in 'en', 'fr') {
    $t = Get-MenuText 'simple' $lg
    $max = ($t -split "`n" | Measure-Object -Property Length -Maximum).Maximum
    Check ($max -le 100) "simple menu ($lg): fits a small window (widest line $max)"
    if ($lg -eq 'en') {
        Check ($t -match 'YOUR PC' -and $t -match '\[ !! \] Disk space' -and $t -match '-> F') 'it starts with the health of the PC'
        Check ($t -match '\n\s+A\s+Analyze' -and $t -match '\n\s+F\s+Clean everything' -and $t -match '28\s+Updates: apps & drivers \[AUTO\]' -and $t -match '17\s+Startup programs' -and $t -match '19\s+PC health' -and $t -match '\n\s+R\s+Restore points') 'then the essentials, with the same keys as the full menu'
        Check ($t -match 'M\s+All options' -and $t -notmatch 'Temporary files') 'M shows all the options; the detailed options are not in the way'
    } else {
        Check ($t -match 'VOTRE PC' -and $t -match 'QUE VOULEZ-VOUS FAIRE' -and $t -match 'Toutes les options') 'in French too'
    }
}
$t = Get-MenuText 'advanced' 'en'
Check ($t -match 'M\s+Simple menu' -and $t -match 'R\s+Restore points' -and $t -match '17\s+Startup programs') 'the full menu has M (back to simple) and R = restore points'
Remove-Item function:Write-Host

Write-Host "`n===== M SWITCHES MENUS AND REMEMBERS (YSO's real start-up code) =====" -ForegroundColor White
$box = "$Sandbox/child-menu"
$out = & $Pwsh -NoProfile -File $Child -ScriptPath $ScriptPath -Sandbox $box -Mode 'menu-switch' 2>&1 | Out-String
$saved = Get-Content -LiteralPath "$box/ProgramData/YSO/settings.json" -Raw | ConvertFrom-Json
Check ($LASTEXITCODE -eq 0 -and $saved.MenuMode -eq 'advanced') "a new user starts simple, M switches to the full menu and it is saved (exit $LASTEXITCODE, saved: $($saved.MenuMode))"

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
