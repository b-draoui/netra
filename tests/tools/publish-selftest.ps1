# Shows the result of YSO's self-test on the GitHub Actions run page, so nobody has to download the report:
#   BROKEN checks          -> errors
#   MISSING checks         -> warnings
#   entries in errors.log  -> warnings (with the line and the first steps of the stack)
#   the whole report       -> the job summary
# Runs in Windows PowerShell 5.1 (CI) and PowerShell 7 (local tests).
param(
    [string]$DataDir = (Join-Path "$env:ProgramData" 'YSO'),
    [string]$Title = 'Self-test',
    [int]$MaxErrorEntries = 5
)

function Format-Message([string]$Text) {
    # Workflow command escaping (message part)
    return $Text.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
}
function Format-Property([string]$Text) {
    # Workflow command escaping (title=... part)
    return (Format-Message $Text).Replace(':', '%3A').Replace(',', '%2C')
}

$reportDir = Join-Path $DataDir 'Reports'
$report = Get-ChildItem -LiteralPath $reportDir -Filter 'selftest_*.txt' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $report) {
    "::error title=$(Format-Property $Title)::$(Format-Message "No self-test report was written in $reportDir")"
    exit 0
}
$lines = @(Get-Content -LiteralPath $report.FullName -Encoding UTF8)

# Report rows: STATUS (8) AREA (10) CHECK (42) DETAIL
foreach ($line in $lines) {
    if ($line -match '^(BROKEN|MISSING)\s+(\S+)\s+(.+?)(?:\s{2,}(.*))?$') {
        $level = if ($Matches[1] -eq 'BROKEN') { 'error' } else { 'warning' }
        $text = '{0} / {1}' -f $Matches[2], $Matches[3].Trim()
        if ($Matches[4]) { $text += ' - ' + $Matches[4].Trim() }
        "::$level title=$(Format-Property ($Title + ' ' + $Matches[1]))::$(Format-Message $text)"
    }
}

# Every check, OK ones included, as notices (GitHub keeps each annotation short, so in parts).
$rows = @($lines | Where-Object { $_ -match '^(OK|INFO|MISSING|BROKEN)\s' } | ForEach-Object { ($_ -replace '\s{2,}', '  ').TrimEnd() })
$part = New-Object System.Collections.Generic.List[string]
$parts = New-Object System.Collections.Generic.List[string]
foreach ($r in $rows) {
    if ($part.Count -gt 0 -and (($part -join "`n").Length + $r.Length) -gt 3500) { $parts.Add(($part -join "`n")); $part.Clear() }
    $part.Add($r)
}
if ($part.Count -gt 0) { $parts.Add(($part -join "`n")) }
for ($i = 0; $i -lt $parts.Count; $i++) {
    "::notice title=$(Format-Property ('{0} - all checks ({1}/{2})' -f $Title, ($i + 1), $parts.Count))::$(Format-Message $parts[$i])"
}

# errors.log: one block per error, starting with "==== date | context | ..."
$errorLog = Join-Path $DataDir 'errors.log'
if (Test-Path -LiteralPath $errorLog) {
    $blocks = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($l in @(Get-Content -LiteralPath $errorLog -Encoding UTF8)) {
        if ($l.StartsWith('==== ')) {
            $current = New-Object System.Collections.Generic.List[string]
            $blocks.Add($current)
        }
        if ($null -ne $current -and $l.Trim()) { $current.Add($l) }
    }
    foreach ($b in @($blocks | Select-Object -Last $MaxErrorEntries)) {
        $context = (($b[0] -split '\|')[1]).Trim()
        $keep = @($b | Where-Object { $_ -match '^(Message|Line)\s*:' })
        $stack = @($b | Where-Object { $_ -match '^\s{2}\S' } | Select-Object -First 3 | ForEach-Object { $_.Trim() })
        $text = (@($keep) + @($stack)) -join "`n"
        "::warning title=$(Format-Property ('errors.log - ' + $context))::$(Format-Message $text)"
    }
    if ($blocks.Count -gt $MaxErrorEntries) {
        "::warning title=errors.log::$(Format-Message ('{0} more error(s) in errors.log (see the artifact)' -f ($blocks.Count - $MaxErrorEntries)))"
    }
}

if ($env:GITHUB_STEP_SUMMARY) {
    $summary = @(('### ' + $Title), '', '```text') + $lines + @('```', '')
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding UTF8
}
exit 0
