param([string]$ScriptPath, [string]$Sandbox, [string]$Pwsh)
# tests/tools/publish-selftest.ps1 turns the self-test report into annotations on the GitHub run page.
# If it misreads the report, a broken check on real Windows would go unnoticed.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
$tool = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/publish-selftest.ps1'
$data = Join-Path $Sandbox 'YSO'
New-Item -ItemType Directory -Force (Join-Path $data 'Reports') | Out-Null

# A report written by the real Save-SelfTestReport format: '{0,-8} {1,-10} {2,-42} {3}'
$fmt = '{0,-8} {1,-10} {2,-42} {3}'
$rows = @(
    ($fmt -f 'STATUS', 'AREA', 'CHECK', 'DETAIL'),
    ($fmt -f 'OK', 'Engine', 'Removes old files, keeps recent ones', '3 files removed'),
    ($fmt -f 'BROKEN', 'Optimize', 'Boot records (18)', 'The parameter is incorrect'),
    ($fmt -f 'MISSING', 'One-click', 'System Restore (R, F)', 'not available on this Windows'),
    ($fmt -f 'BROKEN', 'Engine', 'Folder links are never followed', ''),
    ($fmt -f 'INFO', 'Clean', 'Browsers found (2)', 'no supported browser found')
)
$report = @('YSO self-test report', 'Result     : 1 OK, 1 INFO, 1 MISSING, 2 BROKEN', '') + $rows
Set-Content -LiteralPath (Join-Path $data 'Reports/selftest_20261024_080000.txt') -Value $report -Encoding UTF8
Set-Content -LiteralPath (Join-Path $data 'Reports/selftest_20261023_080000.txt') -Value @(($fmt -f 'BROKEN', 'Old', 'An older report', 'must be ignored')) -Encoding UTF8
(Get-Item -LiteralPath (Join-Path $data 'Reports/selftest_20261023_080000.txt')).LastWriteTime = (Get-Date).AddDays(-1)
Set-Content -LiteralPath (Join-Path $data 'errors.log') -Encoding UTF8 -Value @(
    '==== 2026-10-24 08:00:01 | self-test: Boot records (18) | YSO 1.0 | Windows Server 2022 | PowerShell 5.1 | en',
    'Message : The parameter is incorrect (100%)',
    'Type    : System.Diagnostics.Eventing.Reader.EventLogException',
    'Command : Get-WinEvent',
    "Line    : 2781: `$n = @(Get-WinEvent ...).Count",
    'Stack   :',
    '  at <ScriptBlock>, C:\a\YSO.ps1: line 2781',
    '  at Test-Check, C:\a\YSO.ps1: line 2490',
    '  at Invoke-SelfTest, C:\a\YSO.ps1: line 2780',
    '  at <ScriptBlock>, C:\a\YSO.ps1: line 3900',
    ''
)
$summaryFile = Join-Path $Sandbox 'summary.md'
Set-Content -LiteralPath $summaryFile -Value '' -NoNewline
$env:GITHUB_STEP_SUMMARY = $summaryFile
$out = @(& $Pwsh -NoProfile -File $tool -DataDir $data -Title 'Self-test on windows-2022' 2>&1 | ForEach-Object { "$_" })
$code = $LASTEXITCODE

Write-Host "`n===== SELF-TEST REPORT ON THE GITHUB RUN PAGE =====" -ForegroundColor White
$errors = @($out | Where-Object { $_ -like '::error *' })
$warnings = @($out | Where-Object { $_ -like '::warning *' })
Check ($code -eq 0) 'the tool itself never fails the job (the self-test exit code does)'
Check ($errors.Count -eq 2) "each BROKEN check becomes an error ($($errors.Count))"
Check ($errors -contains '::error title=Self-test on windows-2022 BROKEN::Optimize / Boot records (18) - The parameter is incorrect') 'area, check and detail are all in the error'
Check ($errors -contains '::error title=Self-test on windows-2022 BROKEN::Engine / Folder links are never followed') 'a check without detail is read correctly'
Check (@($warnings | Where-Object { $_ -match 'MISSING::One-click / System Restore \(R, F\) - not available on this Windows$' }).Count -eq 1) 'each MISSING check becomes a warning'
Check (@($out | Where-Object { $_ -match '^::(error|warning)' -and $_ -match 'Browsers found|Removes old files|An older report' }).Count -eq 0) 'OK and INFO lines are not errors or warnings, older reports are left out'
$notes = @($out | Where-Object { $_ -like '::notice title=Self-test on windows-2022 - all checks*' })
Check ($notes.Count -eq 1 -and $notes[0] -match 'OK  Engine  Removes old files, keeps recent ones  3 files removed%0ABROKEN' -and $notes[0] -notmatch 'An older report') 'every check (OK ones too) is shown as a notice, one line each'
$logWarning = @($warnings | Where-Object { $_ -like '::warning title=errors.log - self-test%3A Boot records (18)::*' })
Check ($logWarning.Count -eq 1) 'the errors.log entry becomes a warning (":" escaped in the title)'
Check ($logWarning.Count -eq 1 -and $logWarning[0] -match 'incorrect \(100%25\)%0ALine    : 2781' -and $logWarning[0] -notmatch "`n") 'with its message and line on one escaped line (% and new lines)'
Check ($logWarning.Count -eq 1 -and $logWarning[0] -match 'line 2490' -and $logWarning[0] -notmatch 'line 3900') 'and only the first 3 steps of the stack'
$summary = Get-Content -LiteralPath $summaryFile -Raw
Check ($summary -match '(?m)^### Self-test on windows-2022\s*$' -and $summary -match '(?s)```text.*Boot records \(18\).*```') 'the full report goes in the job summary'

Remove-Item -LiteralPath (Join-Path $data 'Reports') -Recurse -Force
$out = @(& $Pwsh -NoProfile -File $tool -DataDir $data 2>&1 | ForEach-Object { "$_" })
Check (@($out | Where-Object { $_ -like '::error title=Self-test::No self-test report was written*' }).Count -eq 1) 'a missing report is an error, not silence'
Remove-Item env:GITHUB_STEP_SUMMARY

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
