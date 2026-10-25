param([string]$ScriptPath, [string]$Sandbox)
# Event logs that cannot be read (seen on Windows Server 2022 and 2025, where Get-WinEvent throws
# "The parameter is incorrect" even with -ErrorAction SilentlyContinue) must never crash an option
# or turn the self-test red: the options say so, and the self-test reports it as MISSING.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force "$Sandbox/tmp" | Out-Null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
function Confirm-Action { return $false }

# Stand-ins for Get-WinEvent: an unreadable log, a log with no matching events, a log with events
function Use-UnreadableLog { Set-Item function:script:Get-WinEvent { throw 'The parameter is incorrect' } }
function Use-EmptyLog      { Set-Item function:script:Get-WinEvent { } }
function Use-LogWithEvents {
    Set-Item function:script:Get-WinEvent {
        param([hashtable]$FilterHashtable, [int]$MaxEvents, $ErrorAction)
        $script:LastQuery = @{ Filter = $FilterHashtable; MaxEvents = $MaxEvents; ErrorAction = $ErrorAction }
        1..3 | ForEach-Object { [pscustomobject]@{ Id = 100; TimeCreated = (Get-Date).AddDays(-$_); Message = 'event'; ProviderName = 'Test'; Properties = @([pscustomobject]@{ Value = 'app.exe' }) } }
    }
}

Write-Host "`n===== READING EVENT LOGS SAFELY =====" -ForegroundColor White
Use-UnreadableLog
$r = @(Get-EventsSafe @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 50)
Check ($r.Count -eq 0) 'an unreadable log gives no events instead of an error'
Check ($script:LastEventError -eq 'The parameter is incorrect') "and says why: '$($script:LastEventError)'"
Use-EmptyLog
$r = @(Get-EventsSafe @{ LogName = 'System'; Id = 41 })
Check ($r.Count -eq 0 -and $null -eq $script:LastEventError) 'a log with no matching events is not an error (and the previous error is cleared)'
Use-LogWithEvents
$r = @(Get-EventsSafe @{ LogName = 'System'; Id = 100 } -MaxEvents 10)
Check ($r.Count -eq 3 -and $null -eq $script:LastEventError) 'events are returned when the log can be read'
Check ($script:LastQuery.MaxEvents -eq 10 -and "$($script:LastQuery.ErrorAction)" -eq 'SilentlyContinue' -and $script:LastQuery.Filter.Id -eq 100) 'the filter, the limit and SilentlyContinue are passed on'
[void](Get-EventsSafe @{ LogName = 'System' })
Check ($script:LastQuery.MaxEvents -eq 0) 'no limit when none is asked'
$direct = @([regex]::Matches($src, 'Get-WinEvent\s+-FilterHashtable')).Count
Check ($direct -eq 0) "every filtered event-log read goes through Get-EventsSafe ($direct direct call(s) left)"

Write-Host "`n===== BOOT TIME ANALYZER (18) =====" -ForegroundColor White
Use-UnreadableLog
$out = ''
try { $out = (Show-BootTimes 6>&1 | Out-String); $crashed = $false } catch { $crashed = $true; $out = "$_" }
Check (-not $crashed) 'option 18 does not crash when the boot log cannot be read'
Check ($out -match 'cannot read its boot records here: The parameter is incorrect') 'it says the boot records cannot be read, and why'
Check ($out -notmatch 'no boot records yet') 'it does not wrongly say "restart first"'
$script:Lang = 'fr'
$out = (Show-BootTimes 6>&1 | Out-String)
$script:Lang = 'en'
Check ($out -match 'Windows ne peut pas lire ses relevés de démarrage ici : The parameter is incorrect') 'the same message in French'
Use-EmptyLog
$out = (Show-BootTimes 6>&1 | Out-String)
Check ($out -match 'no boot records yet') 'a readable but empty log still says there are no boot records yet'

Write-Host "`n===== SELF-TEST: BOOT RECORDS (18) =====" -ForegroundColor White
$selfTest = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Invoke-SelfTest' }, $true)
$bootCheck = $selfTest.Find({
    $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Test-Check' -and
    $args[0].CommandElements.Count -ge 3 -and "$($args[0].CommandElements[2].Value)" -eq 'Boot records (18)' }, $true)
Check ($null -ne $bootCheck) 'the self-test check was found in the script'
function Get-Service { [pscustomobject]@{ Status = 'Running' } }
foreach ($case in @(
        @{ Use = 'Use-UnreadableLog'; Status = 'MISSING'; Detail = 'cannot read its boot records here: The parameter is incorrect'; What = 'unreadable log (Windows Server) = MISSING, not BROKEN' },
        @{ Use = 'Use-EmptyLog';      Status = 'INFO';    Detail = 'restart once';    What = 'no boot yet = INFO' },
        @{ Use = 'Use-LogWithEvents'; Status = 'OK';      Detail = '3 boots recorded'; What = 'boots recorded = OK' })) {
    & $case.Use
    $script:Checks.Clear()
    Invoke-Expression $bootCheck.Extent.Text 6>$null
    $c = $script:Checks[0]
    Check ($c.Status -eq $case.Status -and $c.Detail -match [regex]::Escape($case.Detail)) "$($case.What): $($c.Status) $($c.Detail)"
}
Remove-Item function:Get-Service

Write-Host "`n===== CRASHES & ERRORS (20), MEMORY TEST (25) =====" -ForegroundColor White
Use-UnreadableLog
try { $out = (Show-RecentProblems 6>&1 | Out-String); $crashed = $false } catch { $crashed = $true; $out = "$_" }
Check (-not $crashed) 'option 20 does not crash when the event logs cannot be read'
Check ($out -match 'Some event logs could not be read, so these numbers may be too low: The parameter is incorrect') 'it warns that its counts may be too low'
Use-LogWithEvents
$out = (Show-RecentProblems 6>&1 | Out-String)
Check ($out -notmatch 'could not be read') 'no warning when the logs can be read'
Use-UnreadableLog
$script:DryRun = $true
try { $out = (Start-MemoryTest 6>&1 | Out-String); $crashed = $false } catch { $crashed = $true; $out = "$_" }
$script:DryRun = $false
Check (-not $crashed -and $out -match 'No memory test has been run') 'option 25 does not crash either'
Remove-Item function:script:Get-WinEvent

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
