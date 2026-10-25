param([string]$ScriptPath, [string]$Sandbox)
$script:fail = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ } }
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings; $script:Lang = 'fr'; $script:Settings = Get-DefaultSettings; $script:Profiles = @("$Sandbox/Users/Alex")
function Get-SteamRoots { @() }
function Get-Process { param($Name, $ErrorAction) @([pscustomobject]@{ ProcessName = 'Spotify' }, [pscustomobject]@{ ProcessName = 'Code' }) }
$script:Closed = $null; function Close-Apps([string[]]$Names) { $script:Closed = $Names }
foreach ($answer in $true, $false) {
    $script:Closed = $null; $script:Ans = $answer
    function Confirm-Action { param($Question, $Default) $script:Asked = $Question; $script:Ans }
    $out = (Clear-DevAppCaches 6>&1 | Out-String)
    if ($answer) {
        Check ($script:Asked -match 'nothing is lost' -and (L $script:Asked) -match 'rien n.est perdu') 'Spotify open: YSO offers to close it'
        Check ($script:Closed -contains 'Spotify' -and $script:Closed -notcontains 'Code') "answer YES: closes only Spotify ($($script:Closed -join ', ')), never VS Code"
        Check ($out -match 'Encore ouverts : Code') 'VS Code is only warned about (unsaved work)'
    } else {
        Check ($null -eq $script:Closed) 'answer NO: nothing is closed'
    }
}
Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
