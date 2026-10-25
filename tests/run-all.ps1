<#
.SYNOPSIS
    Runs every YSO test and prints a summary. Exit code 0 = everything passed.

.DESCRIPTION
    Written for PowerShell 7 (pwsh). The suites use stand-ins for Windows-only commands,
    so they run on Linux too - that is how GitHub runs them. Real Windows is covered
    separately by the self-test job in .github/workflows/tests.yml.

    Nothing outside a temporary folder is touched.

.EXAMPLE
    pwsh ./tests/run-all.ps1
#>
param([string]$ScriptPath = (Join-Path $PSScriptRoot '..' 'YSO.ps1'))

$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
$pwsh  = (Get-Process -Id $PID).Path
$work  = Join-Path ([System.IO.Path]::GetTempPath()) ('yso-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$tools = Join-Path $PSScriptRoot 'tools'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$results = New-Object System.Collections.Generic.List[object]

function Add-Line([string]$Name, [int]$Passed, [string[]]$Failures, [string]$Note = '') {
    $results.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Failures = @($Failures | Where-Object { $_ }); Note = $Note })
    $mark = if (@($Failures | Where-Object { $_ }).Count -eq 0) { 'PASS' } else { 'FAIL' }
    $color = if ($mark -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host ('{0}  {1,-40} {2,4} checks  {3}' -f $mark, $Name, $Passed, $Note) -ForegroundColor $color
    foreach ($f in @($Failures | Where-Object { $_ })) { Write-Host "      $f" -ForegroundColor Red }
}

function Invoke-Pwsh([string[]]$Arguments) {
    $out = & $pwsh -NoProfile @Arguments 2>&1 | Out-String
    return ($out -replace '\x1b\[[0-9;]*m', '')
}

Write-Host "YSO tests - $ScriptPath`n"

# 1. Syntax, and nothing that would break Windows PowerShell 5.1
$out = Invoke-Pwsh @('-File', (Join-Path $tools 'check-syntax.ps1'), '-Path', $ScriptPath)
$fail = @()
if ($out -notmatch 'Parse OK') { $fail += 'syntax errors: ' + ($out -split "`n" | Where-Object { $_ -match 'PARSE ERROR' } | Select-Object -First 3) -join ' | ' }
if ($out -notmatch 'PS7-only tokens: none') { $fail += 'uses syntax that Windows PowerShell 5.1 does not understand' }
if ($out -notmatch 'Calls to undefined helpers: none') { $fail += 'calls a helper that does not exist' }
Add-Line 'Syntax (PowerShell 5.1 compatible)' $(if ($fail.Count) { 0 } else { 3 }) $fail

# 2. Every text on screen has its French translation, with the same {0} placeholders
$keys = Join-Path $work 'strings.txt'
[void](Invoke-Pwsh @('-File', (Join-Path $tools 'extract-strings.ps1'), '-Path', $ScriptPath, '-OutFile', $keys))
$out = Invoke-Pwsh @('-File', (Join-Path $tools 'check-translations.ps1'), '-ScriptPath', $ScriptPath, '-KeysFile', $keys)
$fail = @()
foreach ($kind in 'missing', 'unused') {
    $m = [regex]::Match($out, "(?m)^$($kind): (.*)$")
    if ($m.Success -and $m.Groups[1].Value.Trim()) { $fail += "$kind translations: " + $m.Groups[1].Value.Trim() }
}
if ($out -notmatch 'placeholder mismatches: 0') { $fail += 'a translation has different {0} placeholders' }
$m = [regex]::Match($out, '(?m)^duplicated: (.*)$')
if ($m.Success -and $m.Groups[1].Value.Trim()) { $fail += 'translated twice: ' + $m.Groups[1].Value.Trim() }
$count = [regex]::Match($out, 'strings in code: (\d+)').Groups[1].Value
Add-Line 'French translation complete' $(if ($fail.Count) { 0 } else { 3 }) $fail "($count texts)"

# 2b. Nothing secret in the repository (tokens, private keys, passwords in files)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$out = Invoke-Pwsh @('-File', (Join-Path $tools 'check-secrets.ps1'), '-Root', $repoRoot)
$fail = @($out -split "`n" | Where-Object { $_ -match ' in .+ line \d+' } | ForEach-Object { $_.Trim() })
if ($out -notmatch 'Secrets found: 0' -and $fail.Count -eq 0) { $fail = @('the secret scan did not finish') }
Add-Line 'No secrets in the repository' $(if ($fail.Count) { 0 } else { 1 }) $fail

# 3. The test suites
$suites = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'suites') -Filter '*.ps1' | Sort-Object Name)
foreach ($s in $suites) {
    $sandbox = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($s.Name))
    $args = @('-File', $s.FullName, '-ScriptPath', $ScriptPath)
    $params = (Get-Command -Name $s.FullName).Parameters.Keys
    if ($params -contains 'Sandbox') { $args += @('-Sandbox', $sandbox) }
    if ($params -contains 'Pwsh')    { $args += @('-Pwsh', $pwsh) }
    if ($params -contains 'Child')   { $args += @('-Child', (Join-Path $PSScriptRoot 'helpers' 'run-yso-start.ps1')) }
    $out = Invoke-Pwsh $args
    $passed = ([regex]::Matches($out, '(?m)^ok ')).Count
    $fail = @([regex]::Matches($out, '(?m)^FAIL (.*)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
    if ($out -notmatch 'RESULT: ALL CHECKS PASSED' -and $fail.Count -eq 0) {
        $fail = @('the suite stopped before the end: ' + (($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '))
    }
    Add-Line ([IO.Path]::GetFileNameWithoutExtension($s.Name)) $passed $fail
}

# 4. Restricted PowerShell: YSO must explain the problem and stop (exit code 3), in the chosen language
$pd = Join-Path $work 'programdata'
New-Item -ItemType Directory -Path (Join-Path $pd 'YSO') -Force | Out-Null
$restricted = '$ExecutionContext.SessionState.LanguageMode = "ConstrainedLanguage"; & ''' + $ScriptPath.Replace("'", "''") + '''; "EXIT CODE: $LASTEXITCODE"'
$fail = @()
$saved = $env:ProgramData
try {
    $env:ProgramData = $pd
    $out = ('' | & $pwsh -NoProfile -Command $restricted 2>&1 | Out-String) -replace '\x1b\[[0-9;]*m', ''
    if ($out -notmatch 'restricted mode' -or $out -notmatch 'EXIT CODE: 3') { $fail += 'English message or exit code 3 missing' }
    Set-Content -LiteralPath (Join-Path $pd 'YSO' 'settings.json') -Value '{ "Language": "fr" }'
    $out = ('' | & $pwsh -NoProfile -Command $restricted 2>&1 | Out-String) -replace '\x1b\[[0-9;]*m', ''
    if ($out -notmatch 'mode restreint' -or $out -notmatch 'EXIT CODE: 3') { $fail += 'French message (language chosen in Settings) missing' }
} finally { $env:ProgramData = $saved }
Add-Line 'Restricted PowerShell is explained' $(if ($fail.Count) { 0 } else { 2 }) $fail

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
$totalPassed = ($results | Measure-Object -Property Passed -Sum).Sum
$failedGroups = @($results | Where-Object { $_.Failures.Count -gt 0 })
Write-Host ''
if ($failedGroups.Count -eq 0) {
    Write-Host "ALL TESTS PASSED - $totalPassed checks in $($results.Count) groups" -ForegroundColor Green
    exit 0
}
Write-Host "$($failedGroups.Count) GROUP(S) FAILED - see the FAIL lines above" -ForegroundColor Red
exit 1
