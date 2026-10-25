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
function Get-Process { }; function Write-Progress { }
$prof = "$Sandbox/Users/Alex"; $script:Profiles = @($prof); $L = "$prof/AppData/Local"; $R = "$prof/AppData/Roaming"
function New-F([string]$path, [int]$kb = 4, [int]$daysOld = 0) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllBytes($path, (New-Object byte[] ($kb * 1KB)))
    if ($daysOld) { (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-$daysOld) }
}
# --- Steam: a games library whose path sorts BEFORE the install folder
$steamMain = "$Sandbox/Program Files (x86)/Steam"; $steamLib = "$Sandbox/Games/SteamLibrary"
New-F "$steamMain/steam.exe"; New-Item -ItemType Directory -Force "$steamLib/steamapps" | Out-Null
New-F "$steamMain/steamapps/libraryfolders.vdf"
Set-Content "$steamMain/steamapps/libraryfolders.vdf" ("""libraryfolders""`n{`n ""0"" { ""path"" ""$steamLib"" }`n ""1"" { ""path"" ""$steamMain"" }`n}")
function Get-ItemProperty { param($Path, $Name) if ("$Path" -like '*WOW6432Node*') { [pscustomobject]@{ InstallPath = $steamMain } } }
$roots = @(Get-SteamRoots)
Check ($roots[0] -eq $steamMain) "Steam install folder comes first even when a library sorts before it (got: $($roots[0]))"
Check ($roots.Count -eq 2) 'the library is still listed, once'

# --- Opera One layout (profile in a Default subfolder, in Roaming and Local)
$gone = @("$R/Opera Software/Opera Stable/Default/Code Cache/js/a", "$R/Opera Software/Opera Stable/Default/GPUCache/b",
          "$L/Opera Software/Opera Stable/Default/Cache/Cache_Data/c", "$steamMain/dumps/crash.dmp", "$steamMain/logs/old.txt")
$keep = @("$R/Opera Software/Opera Stable/Default/Cookies", "$R/Opera Software/Opera Stable/Default/Local Storage/leveldb/1.log",
          "$steamMain/logs/today.txt", "$steamLib/steamapps/common/Game/game.pak")
foreach ($f in $gone) { New-F $f 4 $(if ($f -like '*old.txt') { 30 } else { 0 }) }
foreach ($f in $keep) { New-F $f }
$script:DryRun = $false
Clear-BrowserCaches -NoPrompt 6>$null; Clear-DevAppCaches -NoPrompt 6>$null
foreach ($f in $gone) { Check (-not (Test-Path -LiteralPath $f)) ("removed  " + $f.Replace("$Sandbox/", '')) }
foreach ($f in $keep) { Check (Test-Path -LiteralPath $f) ("kept     " + $f.Replace("$Sandbox/", '')) }

# --- Coverage: big folders inside known apps that YSO does not clean
New-F "$L/Spotify/Storage/f1/music.file" 25000                                   # a cache YSO doesn't know (yet)
New-F "$L/Spotify/Data/x.file" 2000                                              # known cache
New-F "$L/BraveSoftware/Brave-Browser/User Data/Default/Service Worker/CacheStorage/a/big" 30000   # site data
New-F "$L/BraveSoftware/Brave-Browser/User Data/Default/Cache/Cache_Data/f" 40000                   # known cache: must not be listed
New-F "$L/Microsoft/Edge/User Data/Snapshots/138.0/Default/History" 22000        # something unexpected
New-F "$L/Microsoft/Edge/User Data/Default/Extensions/abc/1.0/x.js" 1000         # small: not listed
$u = @(Get-UncoveredFolders)
$u | ForEach-Object { Write-Host ("      {0,-8} {1,10:N0} KB  {2}" -f $_.App, ($_.Size / 1KB), (Get-FriendlyPath $_.Path)) -ForegroundColor DarkGray }
Check (@($u | Where-Object { ($_.Rel -replace '/', '\') -like 'Storage*' -and $_.App -eq 'Spotify' }).Count -eq 1) 'finds Spotify\Storage (the folder to look at)'
Check (@($u | Where-Object { $_.Rel -like '*Service Worker*' }).Count -eq 0) 'Brave offline copies are no longer listed (since v3.4 YSO offers to clean them)'
Check (@($u | Where-Object { $_.Rel -like 'Snapshots*' -and $_.App -eq 'Edge' }).Count -eq 1) 'finds Edge Snapshots'
Check (@($u | Where-Object { $_.Path -like '*Cache_Data*' -or $_.Path -like '*Brave-Browser*User Data*Default' -or ($_.App -eq 'Spotify' -and $_.Rel -eq 'Data') }).Count -eq 0) 'does not list caches YSO already cleans, nor folders that contain them'
Check (@($u | Where-Object { $_.Path -like '*Extensions*' }).Count -eq 0) 'ignores small folders'
Check ((Get-FriendlyPath "$L/Spotify/Storage") -eq '%LOCALAPPDATA%\Spotify\Storage') "short path: $(Get-FriendlyPath "$L/Spotify/Storage")"

# --- 32-bit Windows: no ProgramFiles(x86), no Steam in the registry
function Get-ItemProperty { }
$saved = ${env:ProgramFiles(x86)}; ${env:ProgramFiles(x86)} = $null; $env:ProgramFiles = $null
$script:fail2 = $false
try { $r32 = @(Get-SteamRoots) } catch { $script:fail2 = $true }
Check (-not $script:fail2 -and $r32.Count -eq 0) '32-bit Windows without Steam: no error, nothing found'
Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
