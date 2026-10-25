param([string]$ScriptPath, [string]$Sandbox)
# Caches of apps found by their layout, old driver versions, restore points, long paths and the
# settings file.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force "$Sandbox/tmp" | Out-Null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
$defs = @{}
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $defs[$fn.Name] = $fn.Extent.Text; Invoke-Expression $fn.Extent.Text }
function Restore-Real([string]$Name) { Invoke-Expression $defs[$Name] }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $env:ProgramFiles = "$Sandbox/ProgramFiles"; $env:SystemDrive = "$Sandbox/C"
$DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
Import-Settings
$script:Profiles = @("$Sandbox/Users/Alex")
$L = "$Sandbox/Users/Alex/AppData/Local"; $R = "$Sandbox/Users/Alex/AppData/Roaming"
function New-F([string]$Path, [long]$Bytes = 1KB) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    $fs = [IO.File]::Create($Path); $fs.SetLength($Bytes); $fs.Dispose()
}
function Get-FreeBytes { 500GB - [long](@(Get-ChildItem -LiteralPath $Sandbox -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) }
function Get-Rel([string]$p) { $p.Replace('\', '/').Replace(($Sandbox.Replace('\', '/') + '/'), '') }

Write-Host "`n===== CACHES OF OTHER APPS, FOUND BY THEIR LAYOUT =====" -ForegroundColor White
# Slack (Electron): caches + things that must stay
New-F "$R/Slack/Cache/Cache_Data/f_000001" 300MB
New-F "$R/Slack/Code Cache/js/index" 50MB
New-F "$R/Slack/GPUCache/index" 1MB; New-F "$R/Slack/GPUCache/data_0" 9MB
New-F "$R/Slack/Local Storage/leveldb/000003.log" 2MB
New-F "$R/Slack/IndexedDB/https_app.slack.com_0.indexeddb.leveldb/000005.ldb" 40MB
New-F "$R/Slack/Preferences" 1KB
New-F "$R/Slack/Partitions/workspace1/Cache/Cache_Data/f_2" 20MB
New-F "$R/Slack/Partitions/workspace1/Preferences" 1KB
# WhatsApp (WebView2, Microsoft Store)
$wa = "$L/Packages/5319275A.WhatsAppDesktop_cv1g1gvanyjgm/LocalState/EBWebView"
New-F "$wa/Default/Cache/Cache_Data/f_1" 200MB; New-F "$wa/Default/Preferences" 1KB
New-F "$wa/ShaderCache/index" 1KB; New-F "$wa/ShaderCache/data_1" 5MB; New-F "$wa/Local State" 1KB
New-F "$L/Packages/5319275A.WhatsAppDesktop_cv1g1gvanyjgm/LocalState/shared/transfers/photo.jpg" 3MB   # your photos: kept
# Folders that only LOOK like caches
New-F "$R/SomeGame/Cache/savegame.dat" 30MB; New-F "$R/SomeGame/Preferences" 1KB            # "Cache" without Chromium's layout
New-F "$R/Notes/Cache/Cache_Data/f" 10MB                                                         # Chromium layout, but no sign of a browser profile
New-F "$R/Project/node_modules/some-electron/Cache/Cache_Data/f" 10MB; New-F "$R/Project/node_modules/some-electron/Preferences" 1KB
New-F "$L/a/b/c/d/e/f/g/h/DeepApp/Cache/Cache_Data/f" 10MB; New-F "$L/a/b/c/d/e/f/g/h/DeepApp/Preferences" 1KB
# Known apps (cleaned by name already): not found a second time
New-F "$R/discord/Cache/Cache_Data/f" 30MB; New-F "$R/discord/Local Storage/x" 1KB
New-Item -ItemType SymbolicLink -Path "$R/LinkToSlack" -Target "$R/Slack" | Out-Null

$t = @(Get-DetectedAppCacheTargets)
$paths = @($t | ForEach-Object { Get-Rel $_.Path } | Sort-Object)
$paths | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
Check ($paths -contains 'Users/Alex/AppData/Roaming/Slack/Cache' -and $paths -contains 'Users/Alex/AppData/Roaming/Slack/Code Cache' -and $paths -contains 'Users/Alex/AppData/Roaming/Slack/GPUCache') 'Slack: its three caches'
Check ($paths -contains 'Users/Alex/AppData/Roaming/Slack/Partitions/workspace1/Cache') 'Slack: the cache of each workspace too'
Check (@($paths | Where-Object { $_ -like '*WhatsAppDesktop*/EBWebView/Default/Cache' -or $_ -like '*WhatsAppDesktop*/EBWebView/ShaderCache' }).Count -eq 2) 'WhatsApp (Microsoft Store, WebView2): its caches'
Check (@($paths | Where-Object { $_ -match 'Local Storage|IndexedDB|transfers|Preferences' }).Count -eq 0) 'logins, messages, photos and settings are never targets'
Check (@($paths | Where-Object { $_ -match 'SomeGame|Notes|node_modules|DeepApp' }).Count -eq 0) 'folders that only look like caches are left alone (no Chromium layout, no profile, projects, too deep)'
Check (@($paths | Where-Object { $_ -match 'discord|LinkToSlack' }).Count -eq 0) 'apps already cleaned by name and folder links are not counted twice'
Check ((@($script:DetectedApps) -join ',') -eq 'Slack,WhatsApp') "named after their folder: $($script:DetectedApps -join ', ')"
Check ((Get-AppNameFromPath "$L/Packages/MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy/LocalState/EBWebView" $L) -eq 'Windows widgets' -and (Get-AppNameFromPath "$L/Packages/Some.Vendor.CoolApp_abc/LocalCache" $L) -eq 'CoolApp') 'Windows parts get a readable name (seen on real Windows 11: Start and widgets)'

$script:Results.Clear()
$script:DryRun = $true; Clear-DevAppCaches -NoPrompt 6>$null; $script:DryRun = $false
$analysis = ($script:Results | Where-Object { $_.Category -eq 'Other app caches' }).Bytes
$script:Results.Clear()
$out = (Clear-DevAppCaches -NoPrompt 6>&1 | Out-String)
$cleaned = ($script:Results | Where-Object { $_.Category -eq 'Other app caches' }).Bytes
Check ($cleaned -eq (300MB + 50MB + 10MB + 20MB + 200MB + 5MB + 1KB) -and $analysis -eq $cleaned) ('option 7 removes {0} more, exactly what A announced' -f (Format-Size $cleaned))
Check ($out -match 'found by their cache layout\): Slack, WhatsApp') 'and says which apps'
Check ((Test-Path "$R/Slack/Local Storage/leveldb/000003.log") -and (Test-Path "$R/Slack/IndexedDB") -and (Test-Path "$R/SomeGame/Cache/savegame.dat") -and (Test-Path "$L/Packages/5319275A.WhatsAppDesktop_cv1g1gvanyjgm/LocalState/shared/transfers/photo.jpg")) 'everything else is still there'

Write-Host "`n===== OLD DRIVER VERSIONS =====" -ForegroundColor White
$repo = "$Sandbox/C/Windows/System32/DriverStore/FileRepository"
function New-Pkg([string]$Oem, [string]$Inf, [string]$Provider, [string]$Class, [string]$Version, [long]$Bytes) {
    $dir = "$repo/$Inf" + '_amd64_' + $Oem
    New-F "$dir/$Inf" 10KB; New-F "$dir/payload.bin" $Bytes
    return [pscustomobject]@{ Driver = "$Oem.inf"; OriginalFileName = "$dir/$Inf"; ProviderName = $Provider; ClassName = $Class; Version = $Version; Date = (Get-Date) }
}
$script:Store = @(
    (New-Pkg 'oem7'  'nvlt.inf' 'NVIDIA' 'Display' '31.0.15.4601' 900MB),
    (New-Pkg 'oem10' 'nvlt.inf' 'NVIDIA' 'Display' '31.0.15.5222' 950MB),
    (New-Pkg 'oem12' 'nvlt.inf' 'NVIDIA' 'Display' '32.0.15.6094' 1000MB),          # newest, in use
    (New-Pkg 'oem3'  'rtkaud.inf' 'Realtek' 'MEDIA' '6.0.9600.1' 50MB),             # only version
    (New-Pkg 'oem20' 'wifi.inf' 'Intel' 'Net' '5.0' 30MB),                          # newest, not in use (kept: newest)
    (New-Pkg 'oem21' 'wifi.inf' 'Intel' 'Net' '4.0' 30MB),                          # older but in use (kept)
    (New-Pkg 'oem22' 'wifi.inf' 'Intel' 'Net' '3.0' 30MB),                          # old and unused
    (New-Pkg 'oem30' 'nvlt.inf' 'Other Corp' 'Display' '1.0' 5MB),                 # same file name, other maker: its own group
    [pscustomobject]@{ Driver = 'prnms001.inf'; OriginalFileName = "$repo/prnms001.inf_amd64_x/prnms001.inf"; ProviderName = 'Microsoft'; ClassName = 'Printer'; Version = '10.0'; Date = (Get-Date) })
function Get-WindowsDriver { param([switch]$Online, $ErrorAction) if ($script:DismBroken) { throw 'DISM is not available' } $script:Store }
function Get-CimInstance { param($ClassName, $Namespace, $ErrorAction) if ($ClassName -eq 'Win32_PnPSignedDriver') { @('oem12.inf', 'oem3.inf', 'oem21.inf') | ForEach-Object { [pscustomobject]@{ InfName = $_ } } } else { throw 'no CIM' } }
$old = @(Get-OldDriverPackages)
Check ((@($old | ForEach-Object { $_.Inf } | Sort-Object) -join ',') -eq 'oem10.inf,oem22.inf,oem7.inf') "old and unused only: $(@($old | ForEach-Object { $_.Inf }) -join ', ')"
Check (($old | Where-Object { $_.Inf -eq 'oem7.inf' }).Bytes -eq (900MB + 10KB) -and ($old | Where-Object { $_.Inf -eq 'oem7.inf' }).Newest -eq '32.0.15.6094') 'with its size and the version that replaces it'
$script:DismBroken = $true
Check (@(Find-OldDrivers).Count -eq 0) 'when Windows cannot list its drivers, nothing is offered'
$script:DismBroken = $false
$script:Pnp = New-Object System.Collections.Generic.List[string]
function pnputil.exe {
    $script:Pnp.Add(($args -join ' '))
    $inf = $args[1]
    if ($inf -eq 'oem22.inf') { $global:LASTEXITCODE = 1; return 'Failed to delete driver package: One or more devices are presently installed using the specified INF.' }
    $pkg = $script:Store | Where-Object { $_.Driver -eq $inf }
    Remove-Item -LiteralPath (Split-Path $pkg.OriginalFileName) -Recurse -Force
    $global:LASTEXITCODE = 0
}
$script:Results.Clear()
$out = (Remove-OldDriverPackages $old 6>&1 | Out-String)
Check (($script:Pnp | Sort-Object) -join '|' -eq '/delete-driver oem10.inf|/delete-driver oem22.inf|/delete-driver oem7.inf') 'removed one by one with pnputil, never with /force'
$res = $script:Results | Where-Object { $_.Category -eq 'Old driver versions' }
Check ($res.Bytes -eq (900MB + 950MB + 20KB) -and $res.Skipped -eq 1) ('{0} freed, measured on the disk; the one Windows refused is counted apart' -f (Format-Size $res.Bytes))
Check ($out -match '1 could not be removed \(Windows still needs them\)') 'and explained'
Check ((Test-Path "$repo/nvlt.inf_amd64_oem12") -and (Test-Path "$repo/rtkaud.inf_amd64_oem3") -and (Test-Path "$repo/wifi.inf_amd64_oem21")) 'the drivers in use are still there'
function Invoke-CleanMgr { $true } function Start-Process { } function Test-PendingReboot { $false }
$script:Asked = @()
function Find-OldDrivers { @([pscustomobject]@{ Inf = 'oem99.inf'; Provider = 'NVIDIA'; Version = '1'; Bytes = 1GB }) }
function Remove-OldDriverPackages($Packages) { $script:Asked += 'removed' }
function Confirm-Action { param($Question, $Default) $script:Asked += $Question; $false }
$script:Results.Clear(); Invoke-DeepClean 6>$null
Check ($script:Asked[0] -like 'Remove them?*' -and $script:Asked -notcontains 'removed') 'option 8 asks (default No) and keeps them when you say no'
$script:Asked = @(); Invoke-DeepClean -OldDrivers 'yes' 6>$null
Check ($script:Asked -contains 'removed' -and @($script:Asked | Where-Object { $_ -like 'Remove them?*' }).Count -eq 0) 'F already asked: removed without asking again'
$script:Asked = @(); function Find-OldDrivers { $script:Asked += 'searched'; @() }
Invoke-DeepClean -OldDrivers 'no' 6>$null
Check ($script:Asked -notcontains 'searched') 'answered no in F: not even searched'
Restore-Real 'Find-OldDrivers'; Restore-Real 'Remove-OldDriverPackages'; Restore-Real 'Confirm-Action'
Remove-Item function:Get-CimInstance

Write-Host "`n===== RESTORE POINTS (R) =====" -ForegroundColor White
function Get-ComputerRestorePoint { param($ErrorAction) $script:Points }
$script:Points = @(
    [pscustomobject]@{ SequenceNumber = 41; CreationTime = '20260901093000.000000-000'; Description = 'Windows Update' },
    [pscustomobject]@{ SequenceNumber = 45; CreationTime = '20261024015000.000000-000'; Description = 'YSO' },
    [pscustomobject]@{ SequenceNumber = 43; CreationTime = '20261001120000.000000-000'; Description = 'Installed NVIDIA driver' })
$script:Used = 9GB
function Get-CimInstance { param($ClassName, $Namespace, $ErrorAction) if ($ClassName -eq 'Win32_ShadowStorage') { [pscustomobject]@{ UsedSpace = $script:Used; MaxSpace = 24GB } } else { throw 'no CIM' } }
$script:Removed = New-Object System.Collections.Generic.List[int]
function Remove-RestorePoint([int]$Sequence) { $script:Removed.Add($Sequence); $true }
$info = Get-RestorePointInfo
Check ($info.Available -and $info.Points.Count -eq 3 -and $info.Points[-1].SequenceNumber -eq 45 -and $info.Used -eq 9GB) 'listed oldest to newest, with the space they use'
$script:Results.Clear()
$n = Remove-OldRestorePoints 6>$null
Check ($n -eq 2 -and (($script:Removed | Sort-Object) -join ',') -eq '41,43') 'all removed except the newest one'
$script:IsServer = $true
Check (-not (Get-RestorePointInfo).Available) 'Windows Server: not available, said so'
$script:IsServer = $false
$script:Lang = 'fr'
$script:Answers = New-Object System.Collections.Queue; $script:Answers.Enqueue('0')
function Read-Host { param($Prompt) if ($script:Answers.Count -gt 0) { $script:Answers.Dequeue() } else { '' } }
function Clear-Host { }
$out = (Show-RestorePoints 6>&1 | Out-String)
$script:Lang = 'en'
Check ($out -match 'POINTS DE RESTAURATION' -and $out -match '2026-10-24 01:50\s+YSO\s+\(le plus récent\)' -and $out -match 'Supprimer les 2 plus ancien') 'the screen (in French): newest marked, choice to delete the 2 older ones'

Write-Host "`n===== PATHS LONGER THAN 260 CHARACTERS =====" -ForegroundColor White
$long = 'C:\' + (('x' * 50 + '\') * 5)
Check ((Get-LongPath 'C:\Users\Alex\AppData') -eq 'C:\Users\Alex\AppData') 'short paths stay as they are'
Check ((Get-LongPath $long) -eq ('\\?\' + $long) -and (ConvertFrom-LongPath (Get-LongPath $long)) -eq $long) 'long ones get \\?\ (and lose it again for display)'
Check ((Get-LongPath ('\\server\share\' + 'y' * 240)) -like '\\?\UNC\server\share\yyy*') 'network paths too (\\?\UNC\)'
Check ((Get-LongPath 'C:\short' -Always) -eq '\\?\C:\short' -and (Get-LongPath ('\\?\C:\' + 'z' * 250)) -eq ('\\?\C:\' + 'z' * 250)) '-Always, and never twice'
$deep = "$Sandbox/deep"; $p = $deep; for ($i = 0; $i -lt 6; $i++) { $p = Join-Path $p (('d' * 45) + $i) }
New-F "$p/old.tmp" 2KB; (Get-Item "$p/old.tmp").LastWriteTime = (Get-Date).AddDays(-30)
$r = Invoke-Purge -Category 'Test' -Targets @(@{ Path = (Esc $deep); Days = 1 }) -Quiet
Check (-not (Test-Path "$p/old.tmp") -and $r.Files -eq 1) ("a file {0} characters deep is removed (real Windows: checked by the self-test)" -f "$p/old.tmp".Length)
$script:Checks.Clear()
Test-Engine 6>$null
$c = $script:Checks | Where-Object { $_.Name -eq 'Files deeper than 260 characters' }
Check ($c -and $c.Status -eq 'OK') "the self-test checks it too: $($c.Status) $($c.Detail)"

Write-Host "`n===== SETTINGS FILE =====" -ForegroundColor White
if (Test-Path $script:DataDir) { Remove-Item $script:DataDir -Recurse -Force }
New-Item -ItemType Directory -Force $script:DataDir | Out-Null
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Language": "fr", "TempMinAgeHours": 48, "LogMinAgeDays": 9999, "MenuMode": "advanced" }'
Import-Settings
Check ($script:Settings.Language -eq 'fr' -and $script:Settings.TempMinAgeHours -eq 48 -and $script:Settings.MenuMode -eq 'advanced') 'saved settings are read back'
Check ($script:Settings.LogMinAgeDays -eq (Get-DefaultSettings).LogMinAgeDays) 'a value out of range is ignored (the default stays)'
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Language": "fr", '
Import-Settings
Check ($script:SettingsError -and $script:Settings.Language -eq (Get-DefaultSettings).Language) 'a damaged file: defaults are used, and YSO says so'
Remove-Item -LiteralPath $script:SettingsPath -Force; Import-Settings
Check ($script:Settings.MenuMode -eq 'simple' -and -not $script:SettingsError) 'a new user starts with the defaults'
$script:Lang = 'en'

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
