param([string]$ScriptPath)
$script:fail = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ } }
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$script:FR = Get-FrenchStrings; $script:Lang = 'fr'; $script:DryRun = $false; $script:Version = '3.1.3'
$script:Results = New-Object System.Collections.Generic.List[object]; $script:Profiles = @('x'); $script:Build = 26200; $script:IsServer = $false; $script:ErrorCount = 0
# Your PC: C: with 142 Go free and a second internal drive D: (sizes here are an example)
function Get-Volume { @([pscustomobject]@{ DriveLetter = 'D'; DriveType = 'Fixed'; SizeRemaining = [long](3.2GB) },
                        [pscustomobject]@{ DriveLetter = 'C'; DriveType = 'Fixed'; SizeRemaining = [long](142.04GB) },
                        [pscustomobject]@{ DriveLetter = 'E'; DriveType = 'Removable'; SizeRemaining = [long](8GB) }) }
function Get-ScheduledTask { }; function Clear-Host { }; function Get-UptimeText { '0d 1h' }
Check ((Get-FreeSpaceText) -match '^C: 142[,.]04 Go, D: 3[,.]20 Go$') "drive by drive: $(Get-FreeSpaceText)"
Check ((Get-DriveLettersText) -eq 'C: + D:') "letters: $(Get-DriveLettersText) (USB stick E: not counted)"
Check ([math]::Round((Get-FreeBytes) / 1GB, 2) -eq 145.24) 'the total stays the sum of the internal drives (145,24 Go)'
$script:Results.Clear(); Add-Result -Category 'Deep clean' -Files -1 -Bytes ([long](6.33GB)) -Skipped 0
$out = (Show-Summary -FreeBefore ([long](138.92GB)) 6>&1 | Out-String)
Check ($out -match 'Espace disque libre \(C: \+ D:\) : 138[,.]92 Go') 'the summary says which drives it adds up'
$script:capture = $true; $script:sb = New-Object System.Text.StringBuilder
function Write-Host { param([Parameter(Position = 0)]$Object, [switch]$NoNewline, $ForegroundColor) [void]$script:sb.Append("$Object"); if (-not $NoNewline) { [void]$script:sb.Append("`n") } }
foreach ($w in 120, 80) {
    [void]$script:sb.Clear(); Show-Menu -Width $w; $t = $script:sb.ToString()
    $lines = $t -split "`n"
    $max = ($lines | Measure-Object -Property Length -Maximum).Maximum
    Check ($max -le $(if ($w -ge 116) { 116 } else { 80 })) "menu header fits at $w columns (widest $max)"
    Check ($t -match 'Espace libre : C: 142[,.]04 Go, D: 3[,.]20 Go') "header shows each drive at $w columns"
    Write-Host '' ; ($lines | Where-Object { $_ -match 'Espace libre|Allumé' }) | ForEach-Object { Microsoft.PowerShell.Utility\Write-Host "      $_" }
}
Remove-Item function:Write-Host
Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
