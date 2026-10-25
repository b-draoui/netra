param([string]$ScriptPath, [string]$Sandbox)
$script:fail = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ } }
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
$script:Culture = 'fr'
function Get-UICulture { [pscustomobject]@{ TwoLetterISOLanguageName = $script:Culture; Name = "$script:Culture-XX" } }
New-Item -ItemType Directory -Force $script:DataDir | Out-Null

Import-Settings
Check ($script:Lang -eq 'en') "new install on a French Windows: English ($($script:Lang))"
Check ((L 'Settings / Langue') -eq 'Settings / Langue') 'the English menu still shows "Settings / Langue", so French speakers find it'
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Language": "fr" }' -Encoding utf8; Import-Settings
Check ($script:Lang -eq 'fr') "French chosen in Settings: French ($($script:Lang))"
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Language": "auto" }' -Encoding utf8; Import-Settings
Check ($script:Lang -eq 'fr') "Automatic on a French Windows: French ($($script:Lang))"
$script:Culture = 'ar'; Import-Settings
Check ($script:Lang -eq 'en') "Automatic on an Arabic Windows: English ($($script:Lang))"
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Language": "en" }' -Encoding utf8; $script:Culture = 'fr'; Import-Settings
Check ($script:Lang -eq 'en') "English chosen on a French Windows: English ($($script:Lang))"
Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
