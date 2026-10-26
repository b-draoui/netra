param([string]$ScriptPath, [string]$Sandbox)
# Does F (full maintenance) remove as much as running the cleaning options one by one?
# A fake PC with junk in every category is cleaned again and again, in different ways, with YSO's
# real cleaning code; only Windows' own tools (Disk Cleanup, DISM, services, processes) are stand-ins.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:WINDIR = "$Sandbox/Windows"; $env:TEMP = "$Sandbox/tmp"; $env:SystemDrive = "$Sandbox/C"
$DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
Import-Settings
$script:Profiles = @("$Sandbox/Users/Alex")

# ---------- the fake PC ----------
$old = (Get-Date).AddDays(-40)
function New-F([string]$Rel, [long]$Bytes, [bool]$Old = $true) {
    $p = Join-Path $Sandbox $Rel
    New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
    $fs = [IO.File]::Create($p); $fs.SetLength($Bytes); $fs.Dispose()   # sparse: big sizes, no real disk use
    if ($Old) { (Get-Item -LiteralPath $p).LastWriteTime = $script:old }
}
function New-FakePC {
    if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
    $L = 'Users/Alex/AppData/Local'; $R = 'Users/Alex/AppData/Roaming'; $LL = 'Users/Alex/AppData/LocalLow'
    $brave = "$L/BraveSoftware/Brave-Browser/User Data"
    New-F "$L/Temp/old.tmp" 100KB; New-F 'Windows/Temp/setup.log' 50KB; New-F "$L/Temp/fresh.tmp" 10KB $false   # fresh = kept
    New-F "$brave/Default/Cache/Cache_Data/f_000001" 2GB $false
    New-F "$brave/Default/Code Cache/js/a" 300MB $false
    New-F "$L/Google/Chrome/User Data/Default/Cache/Cache_Data/f_1" 400MB $false
    New-F "$brave/Default/Service Worker/CacheStorage/abc/1" 3GB $false
    New-F "$brave/Default/Cookies" 1MB $false                                             # kept
    New-F 'ProgramData/Microsoft/Windows/WER/ReportArchive/r1/report.wer' 80MB
    New-F 'Windows/Logs/CBS/CbsPersist_old.log' 3GB
    New-F 'Windows/Minidump/old.dmp' 600MB
    New-F "$L/CrashDumps/app.exe.1.dmp" 40MB $false
    New-F "$L/Microsoft/Windows/Explorer/thumbcache_256.db" 30MB $false
    New-F 'Windows/SoftwareDistribution/Download/abc/windows11.0-kb1.cab' 1400MB
    New-F 'ProgramData/Microsoft/Windows/DeliveryOptimization/Cache/x' 240MB
    New-F "$L/D3DSCache/x/y.bin" 700MB $false; New-F "$LL/NVIDIA/PerDriverVersion/DXCache/z" 150MB $false
    New-F "$L/npm-cache/_cacache/content-v2/a" 900MB $false; New-F "$R/Code/Cache/Cache_Data/x" 200MB $false
    New-F "$L/Spotify/Data/a/b.file" 2GB $false; New-F "$R/discord/Cache/Cache_Data/d" 380MB $false
    New-F 'RecycleBin/old-photos.zip' 1500KB
    New-F 'Windows/cleanmgr-junk/setup-leftovers.bin' 2GB                                   # what Disk Cleanup removes
    New-F 'Windows/WinSxS/Backup/superseded.bin' 4GB                                        # what DISM removes
    New-F 'C/hiberfil.sys' 6GB $false                                                       # never removed by cleaning
    $script:Running = New-Object System.Collections.Generic.List[string]
    foreach ($p in @('brave', 'Spotify')) { $script:Running.Add($p) }
}

# ---------- stand-ins for Windows ----------
function Get-FreeBytes { 500GB - [long](@(Get-ChildItem -LiteralPath $Sandbox -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) }
function Get-Process {
    param([string[]]$Name, $ErrorAction)
    foreach ($n in @($script:Running)) { if (@($Name) -contains $n) { [pscustomobject]@{ ProcessName = $n; MainWindowHandle = [IntPtr]::Zero } } }
}
function Stop-Process { param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$Force) process { [void]$script:Running.Remove($InputObject.ProcessName); $script:Log.Add("closed $($InputObject.ProcessName)") } }
function Start-Sleep { }
function Get-Service { param($Name, $ErrorAction) foreach ($n in @($Name)) { [pscustomobject]@{ Name = $n; Status = 'Running' } } }
function Stop-Service { param($Name, [switch]$Force, $ErrorAction) $script:Log.Add('paused Windows Update') }
function Start-Service { param($Name, $ErrorAction) }
function Test-PendingReboot { $script:Pending }
function Delete-DeliveryOptimizationCache { param([switch]$Force, $ErrorAction) Remove-Item -LiteralPath "$Sandbox/ProgramData/Microsoft/Windows/DeliveryOptimization" -Recurse -Force -ErrorAction SilentlyContinue }
function Invoke-CleanMgr { param($Handlers, $Id) Remove-Item -LiteralPath "$Sandbox/Windows/cleanmgr-junk" -Recurse -Force -ErrorAction SilentlyContinue; $script:Log.Add('Disk Cleanup'); $true }
function Start-Process { param($FilePath, $ArgumentList, [switch]$NoNewWindow, [switch]$Wait) if ($FilePath -eq 'dism.exe') { Remove-Item -LiteralPath "$Sandbox/Windows/WinSxS/Backup" -Recurse -Force -ErrorAction SilentlyContinue; $script:Log.Add('DISM') } }
function Get-RecycleBinBytes { [long](@(Get-ChildItem -LiteralPath "$Sandbox/RecycleBin" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) }
function Clear-RecycleBin { param([switch]$Force, $ErrorAction) Remove-Item -LiteralPath "$Sandbox/RecycleBin" -Recurse -Force }
function Clear-Dns { } function Optimize-Drives { } function Invoke-UpdateRun { param($Mode) }
function New-YsoRestorePoint { param([switch]$Quiet) $true }
function Get-CimInstance { throw 'no CIM here' }
$script:Pending = $false

function Get-Freed {
    # bytes per category from YSO's own results
    $h = [ordered]@{}
    foreach ($r in $script:Results) { if (-not $h.Contains($r.Category)) { $h[$r.Category] = [long]0 }; $h[$r.Category] += [long]$r.Bytes }
    return $h
}
function Get-Total($h) { [long](@($h.Values) | Measure-Object -Sum).Sum }
function Show-Freed([string]$Title, $h) {
    Write-Host ('      {0,-34} {1}' -f $Title, (Format-Size (Get-Total $h))) -ForegroundColor DarkGray
    foreach ($k in $h.Keys) { Write-Host ('        {0,-32} {1,12}' -f $k, (Format-Size $h[$k])) -ForegroundColor DarkGray }
}
function Run-Scenario([scriptblock]$Steps) {
    New-FakePC
    $script:Log = New-Object System.Collections.Generic.List[string]
    $script:Questions = New-Object System.Collections.Generic.List[string]
    $script:Results.Clear()
    $before = Get-FreeBytes
    & $Steps 6>$null | Out-Null
    $h = Get-Freed
    return [pscustomobject]@{ Freed = $h; Total = (Get-Total $h); Disk = ((Get-FreeBytes) - $before); Log = @($script:Log); Questions = @($script:Questions) }
}

Write-Host "`n===== ONE OPTION AT A TIME (like on your PC: 1, 2, 3, 4, 7, 6, 5, 8 - yes to every question) =====" -ForegroundColor White
function Confirm-Action { param($Question, $Default) $script:Questions.Add($Question); $true }
$oneByOne = Run-Scenario {
    Clear-TempFiles; Clear-BrowserCaches; Clear-SystemJunk; Clear-UpdateCache
    Clear-DevAppCaches; Clear-ShaderCaches; Clear-YsoRecycleBin; Invoke-DeepClean
}
Show-Freed 'options 1-8, one by one' $oneByOne.Freed
Check ($oneByOne.Log -contains 'closed brave' -and $oneByOne.Log -contains 'closed Spotify') 'options 2 and 7 offered to close Brave and Spotify'

Write-Host "`n===== F, PRESSING ENTER ON EVERY QUESTION =====" -ForegroundColor White
function Confirm-Action { param($Question, $Default) $script:Questions.Add($Question); $Default }
$fEnter = Run-Scenario { Invoke-FullMaintenance }
Show-Freed 'F + Enter everywhere' $fEnter.Freed
foreach ($k in $oneByOne.Freed.Keys) {
    if ($k -eq 'Recycle Bin') { continue }
    Check ($fEnter.Freed[$k] -eq $oneByOne.Freed[$k]) ("{0}: {1} (one by one: {2})" -f $k, (Format-Size $fEnter.Freed[$k]), (Format-Size $oneByOne.Freed[$k]))
}
Check (-not $fEnter.Freed.Contains('Recycle Bin') -and (Test-Path "$Sandbox/RecycleBin/old-photos.zip")) 'the Recycle Bin is the only thing kept (it is asked separately: it cannot be undone)'
Check ($fEnter.Log -contains 'closed brave' -and $fEnter.Log -contains 'closed Spotify' -and $fEnter.Log -contains 'Disk Cleanup' -and $fEnter.Log -contains 'DISM') 'Enter = complete clean: browsers and Spotify closed, deep clean done'
Check ($fEnter.Questions.Count -eq 5) "only 5 questions: restore point, complete clean, Recycle Bin, updates, drives ($($fEnter.Questions.Count))"
Check ((Test-Path "$Sandbox/Users/Alex/AppData/Local/BraveSoftware/Brave-Browser/User Data/Default/Cookies") -and (Test-Path "$Sandbox/Users/Alex/AppData/Local/Temp/fresh.tmp") -and (Test-Path "$Sandbox/C/hiberfil.sys")) 'cookies, recent temp files and the hibernation file are still there'

Write-Host "`n===== F BEFORE THIS FIX (Enter everywhere = quick clean) =====" -ForegroundColor White
function Confirm-Action { param($Question, $Default) $script:Questions.Add($Question); if ($Question -eq 'Complete clean?') { $false } else { $Default } }
$fQuick = Run-Scenario { Invoke-FullMaintenance }
Show-Freed 'F quick (No to the complete clean)' $fQuick.Freed
$missing = (Get-Total $oneByOne.Freed) - (Get-Total $fQuick.Freed)
Write-Host ('      missing compared with one by one: {0} ({1:N0} %)' -f (Format-Size $missing), (100 * $missing / (Get-Total $oneByOne.Freed))) -ForegroundColor Yellow
Check (-not $fQuick.Freed.Contains('Deep clean') -and -not $fQuick.Freed.Contains('GPU shader caches') -and -not $fQuick.Freed.Contains('Site offline caches')) 'that path still exists when you answer No: no deep clean, GPU caches or site offline copies'
Check ($fQuick.Log -notcontains 'closed brave') 'and the open browser is not closed'

Write-Host "`n===== F, YES TO EVERYTHING =====" -ForegroundColor White
function Confirm-Action { param($Question, $Default) $script:Questions.Add($Question); $true }
$fAll = Run-Scenario { Invoke-FullMaintenance }
$same = $true
foreach ($k in $oneByOne.Freed.Keys) { if ($fAll.Freed[$k] -ne $oneByOne.Freed[$k]) { $same = $false; Write-Host "      different: $k" -ForegroundColor Red } }
Check ($same -and $fAll.Freed.Count -eq $oneByOne.Freed.Count) ("F with yes everywhere = options 1-8 one by one, category by category ({0} = {1})" -f (Format-Size (Get-Total $fAll.Freed)), (Format-Size (Get-Total $oneByOne.Freed)))
Check ([math]::Abs($fAll.Disk - $oneByOne.Disk) -lt 1MB) ('and the same change in free space ({0})' -f (Format-Size $fAll.Disk))

Write-Host "`n===== A RESTART IS PENDING (common on PCs that are only shut down, never restarted) =====" -ForegroundColor White
$script:Pending = $true
function Confirm-Action { param($Question, $Default) $script:Questions.Add($Question); if ($Question -eq 'Continue anyway?') { $true } else { $Default } }
$pend = Run-Scenario { Invoke-FullMaintenance }
Show-Freed 'F with a restart pending' $pend.Freed
Check ($pend.Questions[0] -eq 'Continue anyway?') 'F says so first, and asks before going on'
Check (-not $pend.Freed.Contains('Windows Update cache') -and (Test-Path "$Sandbox/Windows/SoftwareDistribution/Download/abc/windows11.0-kb1.cab")) 'the Windows Update downloads are kept (updates waiting for the restart need them)'
Check ($pend.Freed['Delivery Optimization'] -eq 240MB) 'Delivery Optimization is still cleaned (it used to be skipped too)'
Check ($pend.Log -contains 'Disk Cleanup' -and $pend.Log -notcontains 'DISM') 'deep clean runs Disk Cleanup, and leaves the component store for after the restart'
function Confirm-Action { param($Question, $Default) $script:Questions.Add($Question); $Default }
$stop = Run-Scenario { Invoke-FullMaintenance }
Check ($stop.Questions.Count -eq 1 -and $stop.Total -eq 0) 'pressing Enter there stops F, so you can restart first'
$script:Pending = $false

Write-Host "`n===== AN UPDATE IS DOWNLOADED BUT NOT INSTALLED YET =====" -ForegroundColor White
# Seen on a real PC: 9 GB of a downloaded update were removed, then Windows downloaded them again.
function Get-DownloadedUpdates { @('2026-10 Cumulative Update for Windows 11 Version 25H2 for x64-based Systems (KB5070001)') }
New-FakePC
$script:Results.Clear()
$out = (Clear-UpdateCache 6>&1 | Out-String)
Check ((Test-Path "$Sandbox/Windows/SoftwareDistribution/Download/abc/windows11.0-kb1.cab") -and @($script:Results | Where-Object { $_.Category -eq 'Windows Update cache' }).Count -eq 0) 'its download cache is kept'
Check ($out -match 'has downloaded updates it has not installed yet \(2026-10 Cumulative Update' -and $out -match 'Settings > Windows Update') 'YSO says why, names the update, and what to do'
Check (@($script:Results | Where-Object { $_.Category -eq 'Delivery Optimization' }).Count -eq 1) 'Delivery Optimization is still cleaned'
$script:Results.Clear(); $script:DryRun = $true
$out = (Clear-UpdateCache 6>&1 | Out-String)
$script:DryRun = $false
Check (@($script:Results | Where-Object { $_.Category -eq 'Windows Update cache' }).Count -eq 0 -and $out -match 'not installed yet') 'Analyze does not count it as space you can free'
function Get-DownloadedUpdates { @() }
$script:Results.Clear()
[void](Clear-UpdateCache 6>&1 | Out-String)
Check (-not (Test-Path "$Sandbox/Windows/SoftwareDistribution/Download/abc/windows11.0-kb1.cab")) 'nothing waiting: the cache is cleaned as before'

Write-Host "`n===== WHAT CLEANING NEVER REMOVES IS SHOWN =====" -ForegroundColor White
New-FakePC
$script:Lang = 'fr'
$out = (Show-MoreSpace 6>&1 | Out-String)
$script:Lang = 'en'
Check ($out -match 'ENCORE DE LA PLACE' -and $out -match 'Fichier de mise en veille prolongée : 6[,.]00 Go' -and $out -match "l'option 10") "the hibernation file (6 GB here) and the option that shrinks it"
New-Item -ItemType Directory -Force "$Sandbox/C/Windows.old" | Out-Null
$out = (Show-MoreSpace 6>&1 | Out-String)
Check ($out -match 'Windows.old' -and $out -match 'option 9') 'Windows.old and option 9'

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
