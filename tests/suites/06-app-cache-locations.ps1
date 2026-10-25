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
$script:FR = Get-FrenchStrings; $script:Lang = 'en'
$script:Settings = Get-DefaultSettings
function Get-SteamRoots { @() }; function Get-Process { }
$prof = "$Sandbox/Users/Alex"; $script:Profiles = @($prof)
$L = "$prof/AppData/Local"; $R = "$prof/AppData/Roaming"
function New-F([string]$path, [int]$daysOld = 0, [int]$kb = 4) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllBytes($path, (New-Object byte[] ($kb * 1KB)))
    if ($daysOld) { (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-$daysOld) }
}
$gone = @(
    "$R/Opera Software/Opera Stable/Code Cache/js/a", "$R/Opera Software/Opera Stable/GPUCache/data_0",
    "$R/Opera Software/Opera Stable/DawnGraphiteCache/x", "$R/Opera Software/Opera GX Stable/Code Cache/wasm/b",
    "$R/Opera Software/Opera Stable/_side_profiles/1234/Code Cache/js/c", "$L/Opera Software/Opera Stable/Cache/Cache_Data/f_1",
    "$L/BraveSoftware/Brave-Browser/User Data/Default/DawnWebGPUCache/d", "$L/BraveSoftware/Brave-Browser/User Data/Default/DawnGraphiteCache/e",
    "$L/BraveSoftware/Brave-Browser/User Data/GraphiteDawnCache/g", "$L/BraveSoftware/Brave-Browser/User Data/Default/Cache/Cache_Data/h",
    "$L/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Data/ab/song.file",
    "$L/Steam/htmlcache/Cache/Cache_Data/s", "$L/Steam/htmlcache/Code Cache/js/t",
    "$L/Microsoft/OneDrive/logs/Personal/SyncEngine-old.odl"
)
$keep = @(
    "$R/Opera Software/Opera Stable/Cookies", "$R/Opera Software/Opera Stable/Login Data",
    "$R/Opera Software/Opera Stable/Local Storage/leveldb/000003.log", "$R/Opera Software/Opera Stable/Service Worker/CacheStorage/abc/1",
    "$L/BraveSoftware/Brave-Browser/User Data/Default/Service Worker/ScriptCache/x", "$L/BraveSoftware/Brave-Browser/User Data/Default/Cookies",
    "$L/BraveSoftware/Brave-Browser/User Data/Default/IndexedDB/https_site/1", "$L/Steam/htmlcache/Cookies",
    "$L/Steam/htmlcache/Local Storage/leveldb/1.log", "$L/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalState/prefs",
    "$L/Microsoft/OneDrive/logs/Personal/SyncEngine-today.odl", "$L/Microsoft/OneDrive/settings/Personal/global.ini"
)
foreach ($f in $gone) { New-F $f $(if ($f -like '*OneDrive*') { 30 } else { 0 }) }
foreach ($f in $keep) { New-F $f }

Write-Host "`n===== ANALYZE FINDS THE NEW LOCATIONS (nothing deleted) =====" -ForegroundColor White
$script:DryRun = $true; $script:Results.Clear()
Clear-BrowserCaches -NoPrompt 6>$null; Clear-DevAppCaches -NoPrompt 6>$null
$b = $script:Results | Where-Object Category -eq 'Browser caches'; $d = $script:Results | Where-Object Category -eq 'Developer & app caches'
Check ($b.Files -eq 10) "browser caches: $($b.Files) files found (expected 10: Opera x6, Brave x4)"
Check ($d.Files -eq 4) "app caches: $($d.Files) files found (expected 4: Spotify Store, Steam x2, old OneDrive log)"
$allFiles = @(Get-ChildItem -LiteralPath $Sandbox -Recurse -File).Count
Check ($allFiles -eq ($gone.Count + $keep.Count)) 'analysis deleted nothing'

Write-Host "`n===== REAL CLEAN =====" -ForegroundColor White
$script:DryRun = $false; $script:Results.Clear()
Clear-BrowserCaches -NoPrompt 6>$null; Clear-DevAppCaches -NoPrompt 6>$null
foreach ($f in $gone) { Check (-not (Test-Path -LiteralPath $f)) ("removed  " + $f.Replace("$prof/", '')) }
foreach ($f in $keep) { Check (Test-Path -LiteralPath $f) ("kept     " + $f.Replace("$prof/", '')) }

Write-Host "`n===== SPACE FINDER ACCEPTS %APPDATA%-STYLE PATHS =====" -ForegroundColor White
$env:YSO_TEST_DIR = "$R/Opera Software"
$script:Answers = New-Object System.Collections.Queue; $script:Answers.Enqueue('%YSO_TEST_DIR%'); $script:Answers.Enqueue('Q')
function Read-Host { param($Prompt) if ($script:Answers.Count) { $script:Answers.Dequeue() } else { 'Q' } }
function Clear-Host { }; function Get-Volume { }
$out = (Show-SpaceFinder 6>&1 | Out-String)
Check ($out -notmatch 'Folder not found' -and $out -match 'Opera Stable') 'a path written as %YSO_TEST_DIR% is expanded and scanned'
Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
