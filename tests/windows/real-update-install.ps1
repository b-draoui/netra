# Runs on GitHub's Windows machines (thrown away after the run): installs one small real update with
# Windows Update through YSO's own Install-DriverUpdates, twice - in this PowerShell, and in a second
# PowerShell (STA runspace) like the YSO window does. Shows what happened on the run page.
param([string]$Title = 'Real update install')
$ErrorActionPreference = 'Continue'
$yso = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'YSO.ps1'
function Note([string]$Level, [string]$Text) { "::$Level title=$Title::" + $Text.Replace('%', '%25').Replace("`r", '').Replace("`n", '%0A') }

$session = New-Object -ComObject 'Microsoft.Update.Session'
$searcher = $session.CreateUpdateSearcher()
try { $found = $searcher.Search("IsInstalled=0 and IsHidden=0") } catch { Note 'warning' ("search failed: " + $_.Exception.Message); exit 0 }
$cands = @()
for ($i = 0; $i -lt $found.Updates.Count; $i++) {
    $u = $found.Updates.Item($i)
    $cands += [pscustomobject]@{ Title = "$($u.Title)"; Size = [double]$u.MaxDownloadSize; Id = "$($u.Identity.UpdateID)" }
}
Note 'notice' ("updates offered: " + (($cands | ForEach-Object { '{0} ({1:N0} MB)' -f $_.Title, ($_.Size / 1MB) }) -join ' | '))
$pick = @($cands | Where-Object { $_.Title -match 'Security Intelligence|Definition Update|Defender' -and $_.Size -lt 400MB } | Sort-Object Size) | Select-Object -First 2
if ($pick.Count -eq 0) { $pick = @($cands | Where-Object { $_.Size -gt 0 -and $_.Size -lt 150MB -and $_.Title -notmatch 'Cumulative|Feature update' } | Sort-Object Size) | Select-Object -First 2 }
if ($pick.Count -eq 0) { Note 'notice' 'no small update to install on this machine'; exit 0 }

$job = {
    param($YsoPath, $Ids)
    . $YsoPath -Engine
    $s = New-UpdateSession
    $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
    $items = @()
    for ($i = 0; $i -lt $r.Updates.Count; $i++) {
        $u = $r.Updates.Item($i)
        if ($Ids -contains "$($u.Identity.UpdateID)") { $items += [pscustomobject]@{ Kind = 'Driver'; Name = "$($u.Title)"; Id = "$($u.Identity.UpdateID)"; From = ''; To = ''; Update = $u } }
    }
    @(Install-DriverUpdates $items | ForEach-Object { '{0}: {1} {2} {3}' -f $_.Name, $_.Status, $_.Code, $_.Detail })
    if (Test-Path $script:ErrorLogPath) { '--- errors.log (end) ---'; Get-Content $script:ErrorLogPath -Tail 25 }
}
# 1. in a second PowerShell, single-threaded (STA), like the YSO window
$ids = @($pick[0].Id)
$rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
$ps = [powershell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript($job.ToString()).AddArgument($yso).AddArgument($ids)
$out = @($ps.Invoke()) + @($ps.Streams.Error | ForEach-Object { "ERROR: $_" })
Note $(if (($out -join ' ') -match ': Failed ') { 'error' } else { 'notice' }) ("like the window (STA runspace): " + ($out -join "`n"))
$ps.Dispose(); $rs.Dispose()
# 2. in this PowerShell, like the console and the scheduled task
if ($pick.Count -gt 1) {
    $ids = @($pick[1].Id)
    $out = @(& $job $yso $ids 2>&1 | ForEach-Object { "$_" })
    Note $(if (($out -join ' ') -match ': Failed ') { 'error' } else { 'notice' }) ("in the console: " + ($out -join "`n"))
}
exit 0
