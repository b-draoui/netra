param([string]$ScriptPath, [string]$Sandbox)
$ErrorActionPreference = 'Stop'
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errs)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
# Windows-only commands, stubbed for Linux
function Get-Volume { }
function Get-ScheduledTask { }
function Test-PendingReboot { $false }
$Auto = $false
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}

# ---------- fake PC ----------
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
$old = (Get-Date).AddDays(-30)
function New-F([string]$rel, [bool]$isOld = $true, [int]$kb = 4, [datetime]$when = $old) {
    $p = Join-Path $Sandbox $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
    [IO.File]::WriteAllBytes($p, (New-Object byte[] ($kb * 1KB)))
    if ($isOld) { (Get-Item -LiteralPath $p).LastWriteTime = $when }
}
$prof = 'Users/Alex [test] x'
$L = "$prof/AppData/Local"; $R = "$prof/AppData/Roaming"
New-F "$L/Temp/old1.tmp"; New-F "$L/Temp/new1.tmp" $false
New-F "$L/Temp/thirty_hours.tmp" $true 4 ((Get-Date).AddHours(-30))
New-F "$L/Temp/oldsub/deep/old2.tmp"
New-F 'Precious/important.docx'
New-Item -ItemType SymbolicLink -Path "$Sandbox/$L/Temp/link_to_precious" -Target "$Sandbox/Precious" | Out-Null
New-F "$L/Google/Chrome/User Data/Default/Cache/Cache_Data/f_000001" $false 100
New-F "$L/Google/Chrome/User Data/Profile 1/Cache/Cache_Data/f_keep" $false 10     # will be excluded by setting
New-F "$L/Google/Chrome/User Data/Default/Cookies" $false
New-F "$L/Mozilla/Firefox/Profiles/ab12.default-release/cache2/entries/XYZ" $false 200
New-F "$L/Mozilla/Firefox/Profiles/ab12.default-release/places.sqlite" $false
New-F "$L/Microsoft/Windows/Explorer/thumbcache_1024.db"
New-F "$L/Microsoft/Windows/Explorer/iconcache_16.db"
New-F "$L/CrashDumps/app.exe.1234.dmp" $false
# developer & app caches (+ things right next to them that must survive)
New-F "$L/npm-cache/_cacache/content-v2/sha512/aa/bb" $false 50
New-F "$R/npm/node_modules/typescript/package.json" $false          # global packages: keep
New-F "$L/pip/Cache/http-v2/a/b" $false 30
New-F "$L/NuGet/v3-cache/x/pkg.dat" $false 20
New-F "$prof/.nuget/packages/newtonsoft.json/13.0.1/lib.dll" $false 40   # installed packages: keep
New-F "$prof/.gradle/caches/build-cache-1/abc" $false 10
New-F "$prof/.gradle/caches/modules-2/files-2.1/dep.jar" $false 10        # dependencies: keep
New-F "$prof/.gradle/daemon/8.5/daemon-1.out.log" $false
New-F "$prof/.gradle/daemon/8.5/registry.bin" $false                      # keep (not a log)
New-F "$R/Code/Cache/Cache_Data/x" $false 10
New-F "$R/Code/CachedData/abc123/chrome/js/y" $false 10
New-F "$R/Code/User/settings.json" $false                                 # keep
New-F "$R/discord/Cache/Cache_Data/d" $false 10
New-F "$R/discord/Local Storage/leveldb/000003.log" $false                # login: keep
New-F "$L/Packages/MSTeams_8wekyb3d8bbwe/LocalCache/Microsoft/MSTeams/EBWebView/Default/Cache/Cache_Data/t" $false 10
New-F "$L/Packages/MSTeams_8wekyb3d8bbwe/LocalCache/Microsoft/MSTeams/EBWebView/Default/Cookies" $false   # keep
New-F "$L/Spotify/Data/a1/b2.file" $false 30
New-F "$L/EpicGamesLauncher/Saved/webcache_4147/c" $false 10
New-F "$L/EpicGamesLauncher/Saved/Config/Windows/GameUserSettings.ini" $false   # keep
New-F "$L/D3DSCache/x/y.bin"
# fake Windows + ProgramData
New-F 'Windows/Temp/oldwin.tmp'
New-F 'Windows/Logs/CBS/CBS.log' $false
New-F 'Windows/Logs/CBS/CbsPersist_old.cab'
New-F 'Windows/Prefetch/APP.EXE-1234.pf'
New-F 'Windows/SoftwareDistribution/Download/upd/pkg.cab' $true 300
New-F 'ProgramData/Microsoft/Windows/WER/ReportArchive/r1/Report.wer'
(Get-Item -LiteralPath "$Sandbox/$L/Temp/oldsub/deep").LastWriteTime = $old
(Get-Item -LiteralPath "$Sandbox/$L/Temp/oldsub").LastWriteTime = $old

$env:WINDIR = "$Sandbox/Windows"; $env:ProgramData = "$Sandbox/ProgramData"; $env:SystemDrive = $null; $env:ProgramFiles = $null
$script:DataDir = "$Sandbox/ProgramData/YSO"; New-Item -ItemType Directory -Force $script:DataDir | Out-Null
$script:SettingsPath = "$script:DataDir/settings.json"; $script:HistoryPath = "$script:DataDir/history.csv"
$script:Profiles = @("$Sandbox/$prof")
$script:Results = New-Object System.Collections.Generic.List[object]
$script:BrowserProcs = @('chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi')
$script:AppProcs = @('Code', 'Discord', 'Teams', 'ms-teams', 'Spotify', 'steam', 'EpicGamesLauncher')
$script:ScriptHosts = @('powershell.exe', 'pwsh.exe', 'cmd.exe', 'wscript.exe', 'cscript.exe', 'mshta.exe', 'rundll32.exe', 'regsvr32.exe')
$script:SigCache = @{}
$script:FR = Get-FrenchStrings
$script:AutoCleanNames = [ordered]@{ TempFiles = 'Temporary files'; BrowserCaches = 'Browser caches'; SystemJunk = 'System junk'; UpdateCache = 'Windows Update cache'; ShaderCaches = 'GPU shader caches'; DevAppCaches = 'Developer & app caches' }

Write-Host "`n===== SETTINGS =====" -ForegroundColor White
Import-Settings
Check ($script:Settings.TempMinAgeHours -eq 24 -and -not $script:SettingsError) 'defaults load when no settings file exists'
$script:Settings.ExcludeFolders = [string[]]@("$Sandbox/$L/Google/Chrome/User Data/Profile 1")
$script:Settings.AutoClean.ShaderCaches = $true
$script:Settings.Language = 'en'
[void](Save-Settings)
Import-Settings
Check (@($script:Settings.ExcludeFolders).Count -eq 1 -and $script:Settings.ExcludeFolders[0] -like '*Profile 1') 'one excluded folder survives save + reload as a list'
Check ($script:Settings.AutoClean.ShaderCaches -eq $true -and $script:Settings.AutoClean.DevAppCaches -eq $false) 'auto-clean choices survive save + reload'
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Language": "fr", "TempMinAgeHours": ' -Encoding utf8
Import-Settings
Check ($script:SettingsError -and $script:Settings.TempMinAgeHours -eq 24) 'broken settings.json -> error flag + safe defaults'
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Language": "en", "TempMinAgeHours": 0, "LogMinAgeDays": 99999, "AutoClean": { "TempFiles": "false" } }' -Encoding utf8
Import-Settings
Check ($script:Settings.TempMinAgeHours -eq 24 -and $script:Settings.LogMinAgeDays -eq 14 -and $script:Settings.AutoClean.TempFiles -eq $false) 'out-of-range numbers rejected, "false" string read correctly'
$script:Settings = Get-DefaultSettings
$script:Settings.ExcludeFolders = [string[]]@("$Sandbox/$L/Google/Chrome/User Data/Profile 1")
$script:Lang = 'en'

Write-Host "`n===== ANALYZE (dry run) =====" -ForegroundColor White
$before = @(Get-ChildItem -LiteralPath $Sandbox -Recurse -File -Force).Count
$script:DryRun = $true
Clear-TempFiles; Clear-BrowserCaches -NoPrompt; Clear-SystemJunk; Clear-UpdateCache; Clear-ShaderCaches; Clear-DevAppCaches -NoPrompt
Show-Summary; $script:Results.Clear()
Check ($before -eq @(Get-ChildItem -LiteralPath $Sandbox -Recurse -File -Force).Count) "dry run deleted nothing ($before files intact)"

Write-Host "`n===== REAL RUN (in French) =====" -ForegroundColor White
$script:DryRun = $false; $script:Lang = 'fr'
function Stop-Service { } ; function Start-Service { } ; function Get-Service { }
Clear-TempFiles; Clear-BrowserCaches -NoPrompt; Clear-SystemJunk; Clear-ShaderCaches; Clear-DevAppCaches -NoPrompt
Invoke-Purge -Category 'Windows Update cache' -Targets @(@{ Path = "$(Esc $env:WINDIR)\SoftwareDistribution\Download" })
Show-Summary -FreeBefore 0
Save-History (N 'Manual')
$script:Lang = 'en'

Write-Host "`n===== CHECKS =====" -ForegroundColor White
$keep = @("$L/Temp/new1.tmp", "$L/Google/Chrome/User Data/Default/Cookies", "$L/Google/Chrome/User Data/Profile 1/Cache/Cache_Data/f_keep",
    "$L/Mozilla/Firefox/Profiles/ab12.default-release/places.sqlite", "$L/Microsoft/Windows/Explorer/iconcache_16.db", 'Precious/important.docx',
    "$R/npm/node_modules/typescript/package.json", "$prof/.nuget/packages/newtonsoft.json/13.0.1/lib.dll", "$prof/.gradle/caches/modules-2/files-2.1/dep.jar",
    "$prof/.gradle/daemon/8.5/registry.bin", "$R/Code/User/settings.json", "$R/discord/Local Storage/leveldb/000003.log",
    "$L/Packages/MSTeams_8wekyb3d8bbwe/LocalCache/Microsoft/MSTeams/EBWebView/Default/Cookies",
    "$L/EpicGamesLauncher/Saved/Config/Windows/GameUserSettings.ini", 'Windows/Logs/CBS/CBS.log', 'Windows/Prefetch/APP.EXE-1234.pf')
$gone = @("$L/Temp/old1.tmp", "$L/Temp/thirty_hours.tmp", "$L/Temp/oldsub/deep/old2.tmp", "$L/Google/Chrome/User Data/Default/Cache/Cache_Data/f_000001",
    "$L/Mozilla/Firefox/Profiles/ab12.default-release/cache2/entries/XYZ", "$L/Microsoft/Windows/Explorer/thumbcache_1024.db", "$L/CrashDumps/app.exe.1234.dmp",
    "$L/npm-cache/_cacache/content-v2/sha512/aa/bb", "$L/pip/Cache/http-v2/a/b", "$L/NuGet/v3-cache/x/pkg.dat", "$prof/.gradle/caches/build-cache-1/abc",
    "$prof/.gradle/daemon/8.5/daemon-1.out.log", "$R/Code/Cache/Cache_Data/x", "$R/Code/CachedData/abc123/chrome/js/y", "$R/discord/Cache/Cache_Data/d",
    "$L/Packages/MSTeams_8wekyb3d8bbwe/LocalCache/Microsoft/MSTeams/EBWebView/Default/Cache/Cache_Data/t", "$L/Spotify/Data/a1/b2.file",
    "$L/EpicGamesLauncher/Saved/webcache_4147/c", "$L/D3DSCache/x/y.bin", 'Windows/Temp/oldwin.tmp', 'Windows/Logs/CBS/CbsPersist_old.cab',
    'Windows/SoftwareDistribution/Download/upd/pkg.cab', 'ProgramData/Microsoft/Windows/WER/ReportArchive/r1/Report.wer')
foreach ($f in $keep) { Check (Test-Path -LiteralPath "$Sandbox/$f") "kept    $f" }
foreach ($f in $gone) { Check (-not (Test-Path -LiteralPath "$Sandbox/$f")) "removed $f" }
Check ([bool](Get-Item -LiteralPath "$Sandbox/$L/Temp/link_to_precious" -Force).LinkType) 'symlink untouched and not followed'

Write-Host "`n===== AGE LIMIT SETTING =====" -ForegroundColor White
New-F "$L/Temp/forty_hours.tmp" $true 4 ((Get-Date).AddHours(-40))
$script:Settings.TempMinAgeHours = 72; $script:Results.Clear(); Clear-TempFiles
Check (Test-Path -LiteralPath "$Sandbox/$L/Temp/forty_hours.tmp") 'with a 72 h limit, a 40 h old temp file is kept'
$script:Settings.TempMinAgeHours = 24; $script:Results.Clear(); Clear-TempFiles
Check (-not (Test-Path -LiteralPath "$Sandbox/$L/Temp/forty_hours.tmp")) 'with a 24 h limit, it is removed'
Save-History (N 'Auto')

Write-Host "`n===== HISTORY =====" -ForegroundColor White
$script:Lang = 'fr'; Show-History; $script:Lang = 'en'
$h = @(Import-Csv -LiteralPath $script:HistoryPath)
Check ($h.Count -ge 6 -and @($h | Group-Object Run).Count -eq 2) "history file has $($h.Count) rows from 2 runs"

Write-Host "`n===== SPACE FINDER =====" -ForegroundColor White
New-F 'Big/movie.mkv' $false 3000
New-F 'Big/sub/archive.zip' $false 1500
$scan = Get-FolderSizes -Root "$Sandbox" -BigFileMin 1MB
$real = (Get-ChildItem -LiteralPath $Sandbox -Recurse -File -Force | Where-Object { $_.FullName -notlike "*link_to_precious*" } | Measure-Object Length -Sum).Sum
Check ($scan.Total["$Sandbox"] -eq $real) "folder total ($($scan.Total["$Sandbox"]) bytes) equals real size, symlink not double-counted"
Check ($scan.Total["$Sandbox/Big"] -eq 4500KB) 'subfolder total adds nested folders'
Check (@($scan.Big | ForEach-Object Name) -contains 'movie.mkv' -and @($scan.Big).Count -eq 2) 'big-file list finds both large files'

Write-Host "`n===== COMMAND-LINE PARSING (audit) =====" -ForegroundColor White
$env:WINDIR = 'C:\Windows'
$cases = [ordered]@{
    '"C:\Program Files\Foo\foo.exe" --bar'                       = 'C:\Program Files\Foo\foo.exe'
    'C:\Program Files\Foo\foo.exe --bar'                         = 'C:\Program Files\Foo\foo.exe'
    '\SystemRoot\System32\drivers\x.sys'                         = 'C:\Windows\System32\drivers\x.sys'
    '\??\C:\Windows\x.sys'                                       = 'C:\Windows\x.sys'
    '%WINDIR%\system32\svchost.exe -k netsvcs -p'                = 'C:\Windows\system32\svchost.exe'
    'C:\Windows\System32\rundll32.exe shell32.dll,Control_RunDLL' = 'C:\Windows\System32\rundll32.exe'
    '"C:\Users\a\AppData\Local\x\up.exe"'                        = 'C:\Users\a\AppData\Local\x\up.exe'
}
foreach ($k in $cases.Keys) { $r = Resolve-ExePath $k; Check ($r -eq $cases[$k]) "$k  ->  $r" }

Write-Host "`n===== AUDIT RISK RULES =====" -ForegroundColor White
$script:FakeSig = @{}
function Get-SignerInfo([string]$Path) { return $script:FakeSig[$Path] }
function Test-Rule($exe, $status, $signer, $kind, [bool]$msPath, [int]$expectLevel, [bool]$expectShown, [string]$what) {
    $script:FakeSig[$exe] = [pscustomobject]@{ Status = $status; Signer = $signer }
    $it = New-AuditItem -Kind $kind -Name 'x' -Command "`"$exe`"" -Exe $exe -MicrosoftPath $msPath
    $shown = (-not $it.IsMicrosoft -or $it.Level -gt 0)
    Check ($it.Level -eq $expectLevel -and $shown -eq $expectShown) "$what (level $($it.Level), flags: $($it.Flags -join '; '))"
}
Test-Rule 'C:\Users\a\AppData\Roaming\x\evil.exe' 'NotSigned' '' 'Startup' $false 2 $true 'unsigned + user folder = red'
Test-Rule 'C:\Program Files\Tool\tool.exe' 'NotSigned' '' 'Service' $false 1 $true 'unsigned in Program Files = yellow'
Test-Rule 'C:\Program Files\Big\app.exe' 'Valid' 'Big Corp Inc.' 'Service' $false 0 $true 'signed third party = listed, not flagged'
Test-Rule 'C:\Users\a\AppData\Local\Discord\Update.exe' 'Valid' 'Discord Inc.' 'Startup' $false 0 $true 'signed app in AppData = not flagged'
Test-Rule 'C:\Windows\System32\cmd.exe' 'Valid' 'Microsoft Windows' 'Startup' $false 1 $true 'cmd.exe launched at startup = yellow'
Test-Rule 'C:\Windows\System32\rundll32.exe' 'Valid' 'Microsoft Windows' 'Task' $true 0 $false 'Microsoft task using rundll32 = hidden'
Test-Rule 'C:\Windows\System32\svchost.exe' 'Valid' 'Microsoft Windows Publisher' 'Service' $false 0 $false 'Microsoft service = hidden'
Test-Rule 'C:\Program Files\X\patched.exe' 'HashMismatch' 'X' 'Service' $false 2 $true 'tampered signature = red'
Test-Rule 'C:\gone\old.exe' 'Missing' '' 'Task' $false 0 $true 'missing file = listed as leftover'

Write-Host "`n===== TRANSLATION =====" -ForegroundColor White
$script:Lang = 'fr'
Check ((L 'Temporary files') -eq 'Fichiers temporaires') 'simple text'
Check ((L '{0}: {1:N0} files removed, {2} freed' 'X' 1234 '5 MB') -like 'X : 1*234 fichiers supprimés, 5 MB libérés') 'text with values'
Check ((L '[Y/n]') -eq '[O/n]' -and (L '[y/N]') -eq '[o/N]') '[Y/n] and [y/N] both translated (exact case)'
Check ((L 'SYSTEM') -eq 'SYSTÈME' -and (L 'System') -eq 'System') 'heading translated, process name "System" left alone'
Check ((L 'unknown text') -eq 'unknown text') 'unknown text falls back to English'
$script:Lang = 'en'
Check ((L 'Temporary files') -eq 'Temporary files') 'English stays English'

Write-Host "`n===== MENU =====" -ForegroundColor White
$script:Version = '3.0'
$script:capture = $false
$script:sb = New-Object System.Text.StringBuilder
function Write-Host { param([Parameter(Position = 0)]$Object, [switch]$NoNewline, $ForegroundColor, $BackgroundColor)
    if ($script:capture) { [void]$script:sb.Append("$Object"); if (-not $NoNewline) { [void]$script:sb.Append("`n") }; return }
    $p = @{ Object = $Object; NoNewline = $NoNewline }
    if ($ForegroundColor) { $p.ForegroundColor = $ForegroundColor }
    Microsoft.PowerShell.Utility\Write-Host @p
}
function Clear-Host { }
function Get-MenuText([int]$w, [string]$lang) {
    [void]$script:sb.Clear(); $script:capture = $true; $script:Lang = $lang
    try { Show-Menu -Width $w -Mode 'advanced' } finally { $script:capture = $false; $script:Lang = 'en' }
    return $script:sb.ToString()
}
foreach ($case in @(@(120, 'fr'), @(120, 'en'), @(80, 'fr'))) {
    $text = Get-MenuText $case[0] $case[1]
    if ($case[0] -eq 120 -and $case[1] -eq 'fr') { $text }
    $max = ($text -split "`n" | Measure-Object -Property Length -Maximum).Maximum
    $limit = if ($case[0] -ge 116) { 116 } else { 80 }
    Check ($max -le $limit) "menu $($case[1]) at $($case[0]) columns: widest line $max chars (limit $limit)"
    Check (-not ($text -match '\.\.\.')) "menu $($case[1]) at $($case[0]) columns: no item cut short"
    Check (($text -split "`n" | Where-Object { $_ -match '^\s+(1|28|Q)\s' -or $_ -match '\s(15|27)\s{2}' }).Count -ge 1) "menu $($case[1]) at $($case[0]) columns: items present"
}

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
