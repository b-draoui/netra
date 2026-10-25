param([string]$ScriptPath)
$script:fail = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ } }
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$script:FR = Get-FrenchStrings; $script:Lang = 'fr'; $script:DryRun = $false
$script:Results = New-Object System.Collections.Generic.List[object]
# Your real runs: before, after, what YSO removed
$cases = @(
    @{ Name = 'option 1'; Before = 123.39GB; After = 123.28GB; Removed = 156KB;  ExpectNote = $true },
    @{ Name = 'option 2'; Before = 123.28GB; After = 129.16GB; Removed = 2.01GB; ExpectNote = $true },
    @{ Name = 'option 3'; Before = 129.64GB; After = 133.30GB; Removed = 3.71GB; ExpectNote = $false },
    @{ Name = 'option 4'; Before = 133.30GB; After = 134.92GB; Removed = 1.62GB; ExpectNote = $false }
)
foreach ($c in $cases) {
    $script:Results.Clear(); Add-Result -Category 'Temporary files' -Files 1 -Bytes ([long]$c.Removed) -Skipped 0
    $script:FakeAfter = [long]$c.After
    function Get-FreeBytes { $script:FakeAfter }
    $out = (Show-Summary -FreeBefore ([long]$c.Before) 6>&1 | Out-String)
    $note = $out -match "d'autres programmes"
    Check ($note -eq $c.ExpectNote) ("{0}: explanation shown = {1} (expected {2})" -f $c.Name, $note, $c.ExpectNote)
}
# the Delivery Optimization cmdlet's own messages are hidden
function Delete-DeliveryOptimizationCache { param([switch]$Force) Write-Host 'Deleting...'; Write-Host 'Successfully deleted Delivery Optimization cache'; 'some output' }
$body = ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Clear-UpdateCache' }, $false)[0]).Extent.Text
$line = ($body -split "`n" | Where-Object { $_ -match 'Delete-DeliveryOptimizationCache -Force' }).Trim()
$captured = (& ([scriptblock]::Create($line)) 6>&1 *>&1 | Out-String)
Check (-not $captured.Contains('Deleting') -and -not $captured.Contains('Successfully')) "the cmdlet's English messages no longer show"
Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
