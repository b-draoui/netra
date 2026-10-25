param([string]$ScriptPath, [string]$Sandbox)
$script:fail = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ } }
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings; $script:Lang = 'fr'; $script:Settings = Get-DefaultSettings
$prof = "$Sandbox/Users/Alex"; $script:Profiles = @($prof); $L = "$prof/AppData/Local"; $R = "$prof/AppData/Roaming"
$steam = "$Sandbox/Program Files (x86)/Steam"; function Get-SteamRoots { @($steam) }; function Write-Progress { }
$script:Running = @(); function Get-Process { param($Name, $ErrorAction) $script:Running }
$script:Answers = New-Object System.Collections.Queue
function Confirm-Action { param($Question, $Default) if ($script:Answers.Count) { $script:Answers.Dequeue() } else { $Default } }
function New-F([string]$path, [int]$kb = 4, [int]$daysOld = 0) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllBytes($path, (New-Object byte[] ($kb * 1KB)))
    if ($daysOld) { (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-$daysOld) }
}
$B = "$L/BraveSoftware/Brave-Browser/User Data"; $E = "$L/Microsoft/Edge/User Data"; $O = "$R/Opera Software/Opera Stable"
$SP = "$L/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0"; $C = "$R/Code"; $OD = "$L/Microsoft/OneDrive"
$gone = @("$B/component_crx_cache/a.crx", "$B/Crashpad/reports/r.dmp", "$E/component_crx_cache/b.crx", "$O/component_crx_cache/c.crx",
          "$SP/LocalCache/Spotify/Browser/Cache/Cache_Data/f", "$SP/LocalCache/Spotify/component_crx_cache/d.crx", "$C/Crashpad/reports/r.dmp",
          "$C/User/workspaceStorage/old123/state.vscdb", "$OD/EBWebView/Default/Cache/Cache_Data/e", "$steam/appcache/librarycache/123.jpg")
$keep = @("$B/Default/IndexedDB/https_www.messenger.com_0.indexeddb.blob/1/a", "$B/Default/Cookies", "$B/Default/Extensions/x/1.0/m.js",
          "$B/Default/Service Worker/Database/MANIFEST", "$O/Default/Extensions/y/1.0/m.js", "$O/Safe Browsing/db",
          "$E/ProvenanceData/2025.10.7.5/p", "$E/Default/Extensions/ndcileolkflehcjpmjnfbnaibdcgglog/1.0/x",
          "$SP/LocalCache/Spotify/Browser/Cookies", "$SP/LocalCache/Spotify/Browser/Local Storage/leveldb/1.log", "$SP/LocalCache/Spotify/WidevineCdm/w.dll",
          "$SP/LocalCache/Spotify/WasmTtsEngine/t.wasm", "$SP/LocalState/Spotify/Users/u-user/offline.bnk",
          "$C/User/workspaceStorage/active456/state.vscdb", "$C/User/workspaceStorage/active456/old-but-in-use.json", "$C/User/globalStorage/g.json",
          "$OD/ListSync/Common/settings/db", "$OD/settings/Personal/global.ini")
$offline = @("$B/Default/Service Worker/CacheStorage/abc/big", "$B/Default/Service Worker/ScriptCache/s", "$O/Default/Service Worker/CacheStorage/def/big")
foreach ($f in $gone) { New-F $f 4 $(if ($f -like '*old123*') { 90 } else { 0 }) }
foreach ($f in $keep) { New-F $f 4 $(if ($f -like '*old-but-in-use*') { 200 } else { 0 }) }
New-F $offline[0] 40000; New-F $offline[1] 4; New-F $offline[2] 30000   # about 70 MB, above the 50 MB threshold

Write-Host "`n===== ANALYZE (A) =====" -ForegroundColor White
$script:DryRun = $true; $script:Results.Clear()
$out = (& { Clear-BrowserCaches -NoPrompt; Clear-DevAppCaches -NoPrompt; Clear-SiteOfflineCaches } 6>&1 | Out-String)
$site = $script:Results | Where-Object Category -eq 'Site offline caches'
Check ($site.Files -eq 3) "site offline caches measured: $($site.Files) files, $([math]::Round($site.Bytes / 1MB)) MB"
Check ($out -match 'seulement si vous le choisissez \(option 2\)') 'and clearly marked "only if you choose"'
Check (@(Get-ChildItem -LiteralPath $Sandbox -Recurse -File).Count -eq ($gone.Count + $keep.Count + $offline.Count)) 'nothing deleted'

Write-Host "`n===== OPTION 2 - browser still open =====" -ForegroundColor White
$script:DryRun = $false; $script:Running = @([pscustomobject]@{ ProcessName = 'brave'; MainWindowHandle = [IntPtr]::Zero })
function Close-Browsers { }   # user says no to closing; brave keeps running
$script:Answers.Clear(); $script:Answers.Enqueue($false)
$out = (Clear-BrowserCaches 6>&1 | Out-String)
Check ($out -match 'navigateurs fermés') 'offline copies are not touched while a browser runs, and the user is told why'
Check (@($offline | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 3) 'all offline copies still there'

Write-Host "`n===== OPTION 2 - browsers closed, user answers NO =====" -ForegroundColor White
$script:Running = @(); $script:Answers.Clear(); $script:Answers.Enqueue($false)
$out = (Clear-BrowserCaches 6>&1 | Out-String)
Check ($out -match 'ne vous déconnecte pas') 'the question explains you stay logged in'
Check (@($offline | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 3) 'answer NO: offline copies kept'

Write-Host "`n===== OPTION 2 + 7 - browsers closed, user answers YES =====" -ForegroundColor White
$script:Answers.Clear(); $script:Answers.Enqueue($true)
[void](Clear-BrowserCaches 6>&1 | Out-String); [void](Clear-DevAppCaches -NoPrompt 6>&1 | Out-String)
foreach ($f in $offline) { Check (-not (Test-Path -LiteralPath $f)) ("removed  " + $f.Replace("$prof/", '')) }
foreach ($f in $gone) { Check (-not (Test-Path -LiteralPath $f)) ("removed  " + $f.Replace("$Sandbox/", '').Replace('Users/Alex/', '')) }
foreach ($f in $keep) { Check (Test-Path -LiteralPath $f) ("kept     " + $f.Replace("$Sandbox/", '').Replace('Users/Alex/', '')) }

Write-Host "`n===== SELF-TEST LIST AFTER CLEANING =====" -ForegroundColor White
New-F "$B/Default/IndexedDB/https_www.messenger.com_0.indexeddb.blob/1/big" 30000
New-F "$B/component_crx_cache/again.crx" 30000
New-F "$B/Default/Service Worker/CacheStorage/new/big" 30000
$u = @(Get-UncoveredFolders -MinBytes 20MB)
$u | ForEach-Object { Write-Host ("      {0,-8} {1,6:N0} MB  {2}" -f $_.App, ($_.Size / 1MB), (Get-FriendlyPath $_.Path)) -ForegroundColor DarkGray }
Check (@($u | Where-Object { $_.Path -like '*IndexedDB*' }).Count -eq 1) 'site data (IndexedDB) is still listed, for information'
Check (@($u | Where-Object { $_.Path -like '*component_crx_cache*' -or $_.Path -like '*CacheStorage*' }).Count -eq 0) 'component caches and offline copies are no longer listed: YSO handles them'

Write-Host "`n===== FULL MAINTENANCE AND AUTO-CLEAN WIRING =====" -ForegroundColor White
$fnText = { param($n) ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $n }, $false)[0]).Extent.Text }
$ask = & $fnText 'Read-MaintenancePlan'; $fm = & $fnText 'Invoke-MaintenancePlan'
Check ($ask -match "SiteCaches = Confirm-Action .* \`$false" -and $fm -match "if \(Get-PlanFlag \`$Plan 'SiteCaches' \`$false\)\s+\{ \`$steps \+=") 'F asks first (default NO), then runs it only if chosen (the window: only if ticked)'
Check ((Get-DefaultSettings).AutoClean.SiteOfflineCaches -eq $false) 'weekly auto-clean: off by default'
Check ($src -match 'if \(\$ac\.SiteOfflineCaches\) \{ Invoke-Step') 'weekly auto-clean runs it only when switched on in Settings'
Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
