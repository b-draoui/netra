param([string]$ScriptPath, [string]$Sandbox)
# New versions of YSO: what is read from GitHub's answer, when GitHub is asked, and how an update is
# checked (SHA-256, PowerShell can read it, right version) before it replaces YSO.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force "$Sandbox/tmp" | Out-Null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $env:ProgramFiles = "$Sandbox/ProgramFiles"
$DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
Import-Settings
New-Item -ItemType Directory -Force $script:DataDir | Out-Null
$rel = 'https://github.com/b-draoui/yso/releases/download/v1.2/'
function New-Release([string]$Tag = 'v1.2', [string]$Prefix = $rel, [long]$Size = 600KB, [switch]$NoSum, [string]$Body = 'Faster cleaning.') {
    $assets = @([pscustomobject]@{ name = 'YSO.ps1'; browser_download_url = $Prefix + 'YSO.ps1'; size = $Size })
    if (-not $NoSum) { $assets += [pscustomobject]@{ name = 'YSO.ps1.sha256'; browser_download_url = $Prefix + 'YSO.ps1.sha256'; size = 80 } }
    return [pscustomobject]@{ tag_name = $Tag; draft = $false; prerelease = $false; body = $Body; html_url = 'https://github.com/b-draoui/yso/releases/tag/' + $Tag; assets = $assets }
}

Write-Host "`n===== WHAT IS READ FROM GITHUB =====" -ForegroundColor White
$r = ConvertFrom-YsoRelease (New-Release)
Check ($r -and $r.Version -eq [version]'1.2' -and $r.Url -eq ($rel + 'YSO.ps1') -and $r.SumUrl -eq ($rel + 'YSO.ps1.sha256') -and $r.Notes -eq 'Faster cleaning.') 'a release: its version, its two files and its notes'
Check ($null -eq (ConvertFrom-YsoRelease (New-Release -Tag 'latest'))) 'a tag that is not a version is ignored'
$d = New-Release; $d.draft = $true
$p = New-Release; $p.prerelease = $true
Check ($null -eq (ConvertFrom-YsoRelease $d) -and $null -eq (ConvertFrom-YsoRelease $p)) 'drafts and test versions (pre-releases) are never offered'
Check ($null -eq (ConvertFrom-YsoRelease (New-Release -Prefix 'https://example.com/b-draoui/yso/releases/download/v1.2/'))) 'files anywhere else than this project on GitHub are refused'
Check ($null -eq (ConvertFrom-YsoRelease (New-Release -Prefix 'https://github.com/someone-else/yso/releases/download/v1.2/'))) 'files from another GitHub project are refused'
Check ($null -eq (ConvertFrom-YsoRelease (New-Release -NoSum))) 'a release without its SHA-256 file is not offered (it could not be checked)'
Check ($null -eq (ConvertFrom-YsoRelease (New-Release -Size 6MB))) 'a file larger than 5 MB is refused'
$r = ConvertFrom-YsoRelease (New-Release -Body ("a`u{0007}b`r`n" + ('x' * 3000)))
Check ($r.Notes.StartsWith("ab`n") -and $r.Notes.Length -le 1510) 'notes: control characters removed, length limited'
$h = New-Release; $h.html_url = 'https://evil.example/phish'
Check ((ConvertFrom-YsoRelease $h).Page -eq 'https://github.com/b-draoui/yso/releases') 'the release page link always points to this project'
$refused = 0
foreach ($u in @('http://github.com/b-draoui/yso/x', 'https://example.com/YSO.ps1', 'file:///C:/Windows/win.ini', 'https://github.com.evil.example/x')) {
    try { [void](Get-YsoWebBytes $u) } catch { if ($_.Exception.Message -match 'Refused address') { $refused++ } }
}
Check ($refused -eq 4) 'downloads: HTTPS and GitHub only (http, other sites, local files and look-alike names refused)'

Write-Host "`n===== WHEN GITHUB IS ASKED =====" -ForegroundColor White
$script:Calls = 0
$script:Answer = (New-Release | ConvertTo-Json -Depth 5)
function Get-YsoWebBytes([string]$Url, [int]$MaxBytes = 5MB) { $script:Calls++; if ($script:Answer -eq 'OFFLINE') { throw 'The remote name could not be resolved' } if ($script:Answer -eq '404') { throw 'The remote server returned an error: (404) Not Found.' } return , [System.Text.Encoding]::UTF8.GetBytes($script:Answer) }
$o = Get-YsoUpdateOffer
Check ($o -and $o.Version -eq [version]'1.2' -and $script:Calls -eq 1) 'YSO 1.0 is offered 1.2'
$o = Get-YsoUpdateOffer
Check ($o -and $script:Calls -eq 1) 'asked again within the hour: the answer kept is used (GitHub is not asked again)'
$c = Get-Content -LiteralPath $script:UpdateCheckPath -Raw | ConvertFrom-Json
$c.Checked = (Get-Date).AddMinutes(-61).ToString('yyyyMMddHHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
$c | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:UpdateCheckPath
[void](Get-YsoUpdateOffer)
Check ($script:Calls -eq 2) 'after an hour, GitHub is asked again'
Remove-Item -LiteralPath $script:UpdateCheckPath
$script:Answer = (New-Release -Tag 'v1.0' | ConvertTo-Json -Depth 5)
Check ($null -eq (Get-YsoUpdateOffer)) 'the same version: nothing offered'
Remove-Item -LiteralPath $script:UpdateCheckPath
$script:Answer = 'OFFLINE'
Check ($null -eq (Get-YsoUpdateOffer) -and -not (Test-Path $script:UpdateCheckPath)) 'no internet: nothing offered, asked again next time'
$script:Answer = '404'
Check ($null -eq (Get-YsoUpdateOffer) -and (Test-Path $script:UpdateCheckPath)) 'nothing published yet: nothing offered (and not asked again for an hour)'
Remove-Item -LiteralPath $script:UpdateCheckPath
$script:Settings.CheckForUpdates = $false
$before = $script:Calls
$script:Answer = (New-Release | ConvertTo-Json -Depth 5)
Check ($null -eq (Get-YsoUpdateOffer) -and $script:Calls -eq $before) 'turned off in Settings: GitHub is never asked'
$script:Settings.CheckForUpdates = $true
Set-Content -LiteralPath $script:SettingsPath -Value '{ "CheckForUpdates": false }'
Import-Settings
Check ($script:Settings.CheckForUpdates -eq $false) 'the choice is saved in the settings file'
Import-Settings
Remove-Item -LiteralPath $script:SettingsPath; Import-Settings
Check ($script:Settings.CheckForUpdates -eq $true) 'on by default'

Write-Host "`n===== INSTALLING A NEW VERSION =====" -ForegroundColor White
$target = "$Sandbox/ProgramFiles/YSO/YSO.ps1"
New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
function New-YsoText([string]$Version = '1.2', [switch]$Broken) {
    $t = "`$script:Version       = '$Version'`r`n`$script:ReleaseRepo   = 'b-draoui/yso'`r`nfunction Install-YsoUpdate { 'new' }`r`n"
    if ($Broken) { $t += "function Oops {`r`n" }
    return $t
}
function Get-Sha([byte[]]$b) { $s = [System.Security.Cryptography.SHA256]::Create(); try { ([BitConverter]::ToString($s.ComputeHash($b)) -replace '-', '').ToLowerInvariant() } finally { $s.Dispose() } }
function Set-Download([string]$Text, [string]$Sum = '') {
    $script:File = [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($Text))
    $script:Sum = $(if ($Sum) { $Sum } else { Get-Sha $script:File }) + '  YSO.ps1'
}
function Get-YsoWebBytes([string]$Url, [int]$MaxBytes = 5MB) {
    if ($Url.EndsWith('.sha256')) { return , [System.Text.Encoding]::ASCII.GetBytes($script:Sum) }
    return , $script:File
}
$script:CopyUpdated = $null
function Update-YsoCopy([string]$Source) { $script:CopyUpdated = $Source }
function Test-YsoInstalled { $false }
$release = ConvertFrom-YsoRelease (New-Release)
function Reset-Target { Set-Content -LiteralPath $target -Value "`$script:Version       = '1.0'" -NoNewline }

Reset-Target; Set-Download (New-YsoText)
$ok = Install-YsoUpdate -Release $release -Target $target 6>$null
Check ($ok -and [System.IO.File]::ReadAllBytes($target).Length -eq $script:File.Length -and (Get-Content $target -Raw) -match "'1.2'") 'checked and installed: YSO is replaced by the new version'
Check (-not (Test-Path "$target.new") -and -not (Test-Path "$target.old")) 'no temporary files left'
Check ($script:CopyUpdated -eq $target) 'the copy used by scheduled tasks follows'
Reset-Target; Set-Download (New-YsoText) ('0' * 64)
$out = (Install-YsoUpdate -Release $release -Target $target 6>&1 | Out-String)
Check ((Get-Content $target -Raw) -match "'1.0'" -and $out -match 'SHA-256') 'a download that does not match its SHA-256: refused, YSO unchanged'
Reset-Target; Set-Download (New-YsoText -Version '1.3')
Check (-not (Install-YsoUpdate -Release $release -Target $target 6>$null) -and (Get-Content $target -Raw) -match "'1.0'") 'a file of another version than announced: refused'
Reset-Target; Set-Download (New-YsoText -Broken)
Check (-not (Install-YsoUpdate -Release $release -Target $target 6>$null) -and (Get-Content $target -Raw) -match "'1.0'") 'a file PowerShell cannot read (cut or damaged): refused'
Reset-Target; Set-Download "Write-Host 'hello'`r`n`$script:Version = '1.2'"
Check (-not (Install-YsoUpdate -Release $release -Target $target 6>$null)) 'a file that is not YSO: refused'
$real = Get-Content -LiteralPath $ScriptPath -Raw
Check (Test-YsoScriptText $real ([version]$script:Version)) "this YSO.ps1 would be accepted as an update to $($script:Version)"

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
