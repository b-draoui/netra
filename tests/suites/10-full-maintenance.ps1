param([string]$ScriptPath, [string]$Sandbox)
$script:fail = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ } }
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings; $script:Lang = 'fr'
# Every step is replaced by a recorder: this test checks what F asks and what it runs, in which order.
$script:Ran = New-Object System.Collections.Generic.List[string]
foreach ($n in 'New-YsoRestorePoint','Clear-TempFiles','Clear-SystemJunk','Clear-DevAppCaches','Clear-ShaderCaches','Clear-UpdateCache','Clear-YsoRecycleBin','Clear-Dns','Invoke-DeepClean','Optimize-Drives','Close-Apps','Clear-SiteOfflineCaches') {
    Invoke-Expression "function $n { `$script:Ran.Add('$n') }"
}
function Clear-BrowserCaches { param([switch]$NoPrompt, [switch]$CloseBrowsers) $script:Ran.Add("Clear-BrowserCaches(close=$CloseBrowsers)") }
function Invoke-UpdateRun { param([string]$Mode) $script:Ran.Add("Invoke-UpdateRun($Mode)") }
function Get-RecycleBinBytes { 5MB }
function Get-Process { param($Name, $ErrorAction) @([pscustomobject]@{ ProcessName = 'brave' }, [pscustomobject]@{ ProcessName = 'Spotify' }) | Where-Object { @($Name) -contains $_.ProcessName } }
foreach ($all in $true, $false) {
    $script:Ran.Clear(); $script:Questions = New-Object System.Collections.Generic.List[string]
    $script:All = $all
    function Confirm-Action { param($Question, $Default) $script:Questions.Add($Question); $script:All }
    Invoke-FullMaintenance 6>$null
    if ($all) {
        Write-Host ('      questions: ' + $script:Questions.Count + ' | steps: ' + ($script:Ran -join ' > ')) -ForegroundColor DarkGray
        Check ($script:Questions.Count -eq 5 -and $script:Questions -contains 'Complete clean?') "all questions up front, only 5 with a complete clean ($($script:Questions.Count))"
        Check ($script:Ran -contains 'Close-Apps' -and $script:Ran.IndexOf('Close-Apps') -lt $script:Ran.IndexOf('Clear-DevAppCaches')) 'Spotify is closed before the app caches are cleaned'
        Check ($script:Ran -contains 'Clear-ShaderCaches' -and $script:Ran -contains 'Clear-SiteOfflineCaches') 'GPU caches and site offline copies included'
        Check ($script:Ran -contains 'Clear-BrowserCaches(close=True)') 'browsers are closed first'
        Check ($script:Ran.Count -eq 14) "everything runs: $($script:Ran.Count) steps"
        Check ($script:Ran -contains 'Invoke-UpdateRun(Full)' -and $script:Ran.IndexOf('Invoke-UpdateRun(Full)') -eq $script:Ran.IndexOf('Optimize-Drives') - 1) 'updates run in their F mode, just before the drives are optimized'
    } else {
        Check ($script:Questions.Count -eq 10) "answering No to the complete clean asks about each part ($($script:Questions.Count) questions)"
        Check (@($script:Ran) -join ',' -eq 'Clear-TempFiles,Clear-BrowserCaches(close=False),Clear-SystemJunk,Clear-DevAppCaches,Clear-UpdateCache,Clear-Dns') "all NO: only the always-safe steps run ($($script:Ran -join ', '))"
    }
}
Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
