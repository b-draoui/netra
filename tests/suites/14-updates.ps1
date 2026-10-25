param([string]$ScriptPath, [string]$Sandbox, [string]$Pwsh, [string]$Child)
# Updates (28): reading winget's tables in any language, choosing what to install, automatic mode,
# Windows Update drivers, the scheduled task and the settings. winget, Windows Update and Task
# Scheduler are replaced by stand-ins; the real ones are exercised on real Windows by the CI job.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force "$Sandbox/tmp", "$Sandbox/ProgramFiles" | Out-Null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $env:ProgramFiles = "$Sandbox/ProgramFiles"
$DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
Import-Settings
$E = [string][char]0x2026   # the "…" winget puts at the end of shortened names

function Get-Row([string[]]$Cells, [int[]]$Widths) {
    # A table row padded like winget pads it
    $out = ''
    for ($i = 0; $i -lt $Cells.Count; $i++) { $out += if ($i -lt $Cells.Count - 1) { $Cells[$i].PadRight($Widths[$i]) } else { $Cells[$i] } }
    return $out
}
$w = @(35, 32, 15, 15, 6)
$english = @(
    "   - `r   \ `r   | `r   / `r",
    ('  ' + ([string][char]0x2588 * 20) + ([string][char]0x2592 * 10) + '  1.20 MB / 4.00 MB'),
    (Get-Row @('Name', 'Id', 'Version', 'Available', 'Source') $w),
    ('-' * 103),
    (Get-Row @('Git', 'Git.Git', '2.43.0', '2.47.1', 'winget') $w),
    (Get-Row @('Microsoft Visual Studio Code', 'Microsoft.VisualStudioCode', '1.95.0', '1.96.2', 'winget') $w),
    (Get-Row @('Node.js 20.11.0', 'OpenJS.NodeJS.LTS', '20.11.0', '22.12.0', 'winget') $w),
    (Get-Row @("Microsoft Visual Studio Commun$E", "Microsoft.VisualStudio.2022.Co$E", '17.11.5', '17.12.3', 'winget') $w),
    (Get-Row @('7-Zip 23.01 (x64)', '7zip.7zip', '< 24.08', '24.09', 'winget') $w),
    '5 upgrades available.',
    '',
    '1 package(s) have version numbers that cannot be determined. Use --include-unknown to see all results.',
    'The following packages have an upgrade available, but require explicit targeting for upgrade:',
    (Get-Row @('Name', 'Id', 'Version', 'Available', 'Source') @(8, 22, 9, 10, 6)),
    ('-' * 55),
    (Get-Row @('Zotero', 'DigitalScholar.Zotero', '6.0.30', '7.0.11', 'winget') @(8, 22, 9, 10, 6))
)

Write-Host "`n===== READING WINGET'S LIST =====" -ForegroundColor White
$rows = @(ConvertFrom-WingetTable $english)
$normal = @($rows | Where-Object { $_.Table -eq 'Normal' })
Check ($normal.Count -eq 5) "5 normal updates read, spinner and progress bar ignored ($($normal.Count))"
$git = $normal | Where-Object { $_.Id -eq 'Git.Git' }
Check ($git -and $git.Name -eq 'Git' -and $git.Version -eq '2.43.0' -and $git.Available -eq '2.47.1') 'name, id, installed and new version'
Check (@($normal | Where-Object { $_.Name -eq 'Microsoft Visual Studio Code' }).Count -eq 1) 'names with spaces'
Check (@($normal | Where-Object { $_.Id -eq '7zip.7zip' -and $_.Version -eq '< 24.08' }).Count -eq 1) 'a "< 24.08" version stays whole'
Check (@($normal | Where-Object { $_.Id -eq "Microsoft.VisualStudio.2022.Co$E" }).Count -eq 1) 'a shortened Id is kept with its "…" (resolved later)'
$special = @($rows | Where-Object { $_.Table -eq 'Special' })
Check ($special.Count -eq 1 -and $special[0].Id -eq 'DigitalScholar.Zotero') 'apps that need explicit targeting are kept apart'
Check (@($rows | Where-Object { $_.Name -match 'upgrades available|package\(s\)' }).Count -eq 0) 'footer lines are not read as apps'

$wf = @(28, 24, 10, 11, 6)
$french = @(
    "`e[2K`r   - `r",
    (Get-Row @('Nom', 'ID', 'Version', 'Disponible', 'Source') $wf),
    ('-' * 79),
    (Get-Row @('Mozilla Firefox (x64 fr)', 'Mozilla.Firefox.fr', '131.0.3', '132.0', 'winget') $wf),
    (Get-Row @('Éditeur Démo Pro', 'Demo.EditeurPro', '1.0', '1.1', 'winget') $wf),
    '2 mises à niveau disponibles.'
)
$rows = @(ConvertFrom-WingetTable $french)
Check ($rows.Count -eq 2 -and $rows[0].Id -eq 'Mozilla.Firefox.fr' -and $rows[1].Name -eq 'Éditeur Démo Pro' -and $rows[1].Available -eq '1.1') 'French headers and accented names'

# Wide characters (Chinese, Japanese...) take two screen cells: winget pads less, so the columns shift.
$wide = (Get-Row @('Chinese App', 'Vendor.App', '< 1.0', '2.0', 'winget') @(20, 18, 10, 10, 6)).Remove(14, 4)
$rows = @(ConvertFrom-WingetTable @((Get-Row @('Name', 'Id', 'Version', 'Available', 'Source') @(20, 18, 10, 10, 6)), ('-' * 64), $wide))
Check ($rows.Count -eq 1 -and $rows[0].Name -eq 'Chinese App' -and $rows[0].Id -eq 'Vendor.App' -and $rows[0].Version -eq '< 1.0' -and $rows[0].Available -eq '2.0') 'a shifted row is read from the right instead'
$rows = @(ConvertFrom-WingetTable @((Get-Row @('Name', 'Id', 'Version', 'Available') @(10, 12, 9, 9)), ('-' * 40), (Get-Row @('Tool', 'Acme.Tool', '1.0', '1.2') @(10, 12, 9, 9))))
Check ($rows.Count -eq 1 -and $rows[0].Id -eq 'Acme.Tool' -and $rows[0].Available -eq '1.2') 'a table without the Source column'
Check (@(ConvertFrom-WingetTable @('No installed package found matching input criteria.')).Count -eq 0) '"no update" output gives an empty list'
$onlySpecial = @(
    'The following packages have an upgrade available, but require explicit targeting for upgrade:',
    (Get-Row @('Name', 'Id', 'Version', 'Available', 'Source') @(8, 22, 9, 10, 6)), ('-' * 55),
    (Get-Row @('Zotero', 'DigitalScholar.Zotero', '6.0.30', '7.0.11', 'winget') @(8, 22, 9, 10, 6)))
Check (@(ConvertFrom-WingetTable $onlySpecial | Where-Object { $_.Table -eq 'Normal' }).Count -eq 0) 'a first table that follows the "explicit targeting" sentence is not a normal one'

Write-Host "`n===== ASKING WINGET (stand-in) =====" -ForegroundColor White
$script:WingetCalls = New-Object System.Collections.Generic.List[string]
$script:WingetAnswer = @{ Code = 0; Lines = $english }
$script:FakeVersion = 'v1.9.25200'
$script:ExportIds = @('Git.Git', 'Microsoft.VisualStudio.2022.Community', 'Microsoft.VisualStudioCode')
function Get-WingetPath { return 'C:\fake\winget.exe' }
function Invoke-Winget([string[]]$Arguments) {
    $script:WingetCalls.Add(($Arguments -join ' '))
    if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ Code = 0; Lines = @($script:FakeVersion) } }
    if ($Arguments[0] -eq 'export') {
        $file = $Arguments[[array]::IndexOf($Arguments, '--output') + 1]
        $pk = @($script:ExportIds | ForEach-Object { @{ PackageIdentifier = $_ } })
        @{ Sources = @(@{ Packages = $pk; SourceDetails = @{ Name = 'winget' } }) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file
        return [pscustomobject]@{ Code = 0; Lines = @() }
    }
    return [pscustomobject]$script:WingetAnswer
}
$r = Get-AppUpdates
Check ($r.Ok -and $r.Apps.Count -eq 5 -and $r.Others.Count -eq 1) "found 5 updates and 1 app winget does not update by itself"
Check (@($r.Apps | Where-Object { $_.Id -eq 'Microsoft.VisualStudio.2022.Community' }).Count -eq 1) 'the shortened Id was completed with "winget export"'
$list = @($script:WingetCalls | Where-Object { $_ -like 'upgrade*' })[0]
Check ($list -match '--source winget' -and $list -match '--accept-source-agreements' -and $list -match '--disable-interactivity') "winget is asked without prompts: $list"
Check (@(Get-ChildItem "$Sandbox/tmp" -Filter 'yso-winget_*').Count -eq 0) 'the export file is deleted afterwards'
$script:ExportIds = @('Microsoft.VisualStudio.2022.Community', 'Microsoft.VisualStudio.2022.Comm.Preview', 'Git.Git')
$r = Get-AppUpdates
$vs = @($r.Others | Where-Object { $_.Id -like 'Microsoft.VisualStudio.2022.Co*' })
Check ($r.Apps.Count -eq 4 -and $vs.Count -eq 1 -and $vs[0].Note -match 'could not be identified') 'an Id that matches two apps is not guessed: it is left out'
$script:WingetVersionRead = $false; $script:FakeVersion = 'v1.3.2691'; $script:WingetCalls.Clear()
[void](Get-AppUpdates)
Check (@($script:WingetCalls | Where-Object { $_ -like 'upgrade*' })[0] -notmatch 'disable-interactivity') 'winget older than 1.4 is not given an argument it does not know'
$script:WingetVersionRead = $false; $script:FakeVersion = 'v1.9.25200'
$script:WingetAnswer = @{ Code = -1978335212; Lines = @('No installed package found matching input criteria.') }   # 0x8A150014
$r = Get-AppUpdates
Check ($r.Ok -and $r.Apps.Count -eq 0) 'no update available = OK with an empty list'
$script:WingetAnswer = @{ Code = -1978335230; Lines = @('Failed in attempting to update the source: winget') }       # 0x8A150002
$r = Get-AppUpdates
Check (-not $r.Ok -and (L $r.Reason $r.ReasonArg) -eq 'winget failed (0x8A150002)') "a winget failure is reported with its code: $(L $r.Reason $r.ReasonArg)"
$script:WingetAnswer = @{ Code = 0; Lines = @('Nom Id', ('-' * 30), 'something winget never printed before') }
$r = Get-AppUpdates
Check (-not $r.Ok -and $r.ParseFailed) 'a table YSO cannot read is reported as a problem, not as "up to date"'
function Get-WingetPath { return $null }
$script:Build = 22631
$r = Get-AppUpdates
Check (-not $r.Ok -and $r.Reason -eq 'winget (App Installer) is not installed') 'no winget: explained'

Write-Host "`n===== INSTALLING ONE APP =====" -ForegroundColor White
function Get-WingetPath { return 'C:\fake\winget.exe' }
$item = [pscustomobject]@{ Kind = 'App'; Name = 'Git'; Id = 'Git.Git'; From = '2.43.0'; To = '2.47.1' }
foreach ($case in @(@(0, 'Updated'), @(-1978334967, 'Restart'), @(-1978335189, 'NotApplicable'), @(-1978334975, 'InUse'), @(-1978334969, 'Failed'))) {
    $script:WingetAnswer = @{ Code = $case[0]; Lines = @() }
    $res = Install-AppUpdate $item
    Check ($res.Status -eq $case[1]) ("winget code {0} = {1}" -f $res.Code, $res.Status)
}
$last = $script:WingetCalls[$script:WingetCalls.Count - 1]
Check ($last -match '^upgrade --id Git.Git --exact --source winget --silent --accept-package-agreements --accept-source-agreements') "one app at a time, by exact Id, silently: $last"
Check ((Get-UpdateMessage '0x8A150107') -eq 'no internet connection' -and (Get-UpdateMessage '0x12345678') -eq '') 'known codes are explained, unknown ones are shown as numbers'

Write-Host "`n===== WHAT IS UPDATED AUTOMATICALLY =====" -ForegroundColor White
Check ((Test-MajorUpgrade '7.0.45' '9.0.2') -and (Test-MajorUpgrade '155.0.4283.62' '156.0.4314.42') -and (Test-MajorUpgrade 'Unknown' '1.0')) 'major versions: 7 -> 9, 155 -> 156, and a version without a number'
Check (-not (Test-MajorUpgrade '2.43.0' '2.47.1') -and -not (Test-MajorUpgrade 'py314_26.9.3-0' 'py314_26.9.4-0') -and -not (Test-MajorUpgrade '< 24.08' '24.09') -and -not (Test-MajorUpgrade '8.0.46' '8.4.9')) 'not major: 2.43 -> 2.47, conda builds, "< 24.08" -> 24.09, 8.0 -> 8.4'
$mongo = [pscustomobject]@{ Kind = 'App'; Excluded = $false; InUse = $false; Optional = $false; Major = $true }
Check (-not (Test-RecommendedUpdate $mongo 'Manual') -and -not (Test-RecommendedUpdate $mongo 'Auto')) 'a new major version is never picked for you'
Check ((Test-UpdateExcluded 'Microsoft.AppInstaller')) 'App Installer (winget itself) is excluded by default'
Check ((Test-UpdateExcluded 'OpenJS.NodeJS.LTS') -and (Test-UpdateExcluded 'OpenJS.NodeJS') -and (Test-UpdateExcluded 'microsoft.visualstudio.2022.community')) 'Node.js and Visual Studio are excluded by default (any case)'
Check (-not (Test-UpdateExcluded 'Microsoft.VisualStudioCode') -and -not (Test-UpdateExcluded 'Git.Git')) 'VS Code and Git are not'
$app = [pscustomobject]@{ Kind = 'App'; Excluded = $false; InUse = $true; Optional = $false }
Check ((Test-RecommendedUpdate $app 'Manual') -and -not (Test-RecommendedUpdate $app 'Auto') -and -not (Test-RecommendedUpdate $app 'Full')) 'an open app: offered when you choose, skipped automatically'
$opt = [pscustomobject]@{ Kind = 'Driver'; Excluded = $false; InUse = $false; Optional = $true }
Check (-not (Test-RecommendedUpdate $opt 'Manual') -and -not (Test-RecommendedUpdate $opt 'Auto')) 'optional drivers are never recommended by default'
$script:Settings.Updates.OptionalDrivers = $true
Check ((Test-RecommendedUpdate $opt 'Auto') -and -not (Test-RecommendedUpdate $opt 'Manual')) 'unless turned on for automatic updates'
$script:Settings.Updates.OptionalDrivers = $false

Write-Host "`n===== WHICH APPS ARE OPEN =====" -ForegroundColor White
$env:WINDIR = 'C:\Windows'; $env:LOCALAPPDATA = 'C:\Users\Alex\AppData\Local'; $env:APPDATA = 'C:\Users\Alex\AppData\Roaming'; $env:USERPROFILE = 'C:\Users\Alex'
$savedPF = $env:ProgramFiles; $env:ProgramFiles = 'C:\Program Files'
function Get-RunningExePaths { @('C:\Users\Alex\AppData\Local\Discord\app-1.0.9035\Discord.exe', 'C:\Program Files\VideoLAN\VLC\vlc.exe', 'C:\Windows\System32\svchost.exe', 'C:\Program Files\Common Files\Shared\helper.exe') }
function Get-UninstallEntries { @(
    [pscustomobject]@{ DisplayName = 'Discord'; InstallLocation = 'C:\Users\Alex\AppData\Local\Discord'; DisplayIcon = $null; UninstallString = $null },
    [pscustomobject]@{ DisplayName = 'VLC media player'; InstallLocation = ''; DisplayIcon = 'C:\Program Files\VideoLAN\VLC\vlc.exe,0'; UninstallString = '"C:\Program Files\VideoLAN\VLC\uninstall.exe"' },
    [pscustomobject]@{ DisplayName = 'Git'; InstallLocation = 'C:\Program Files\Git\'; DisplayIcon = 'C:\Program Files\Git\mingw64\share\git\git-for-windows.ico'; UninstallString = $null },
    [pscustomobject]@{ DisplayName = 'Some MSI App'; InstallLocation = ''; DisplayIcon = $null; UninstallString = 'MsiExec.exe /X{12345678-1234-1234-1234-123456789012}' },
    [pscustomobject]@{ DisplayName = 'Shared Thing'; InstallLocation = 'C:\Program Files\Common Files'; DisplayIcon = $null; UninstallString = $null }
) }
$items = @(
    [pscustomobject]@{ Name = 'Discord'; Id = 'Discord.Discord' }, [pscustomobject]@{ Name = "VLC media pla$E"; Id = 'VideoLAN.VLC' },
    [pscustomobject]@{ Name = 'Git'; Id = 'Git.Git' }, [pscustomobject]@{ Name = 'Some MSI App'; Id = 'Some.Msi' },
    [pscustomobject]@{ Name = 'Shared Thing'; Id = 'Shared.Thing' }, [pscustomobject]@{ Name = 'Unknown App'; Id = 'Nobody.Knows' })
$open = @(Get-AppsInUse $items)
Check ($open -contains 'Discord.Discord') 'Discord is open (runs from its install folder)'
Check ($open -contains 'VideoLAN.VLC') 'VLC is open (found from its icon path, shortened name)'
Check ($open -notcontains 'Git.Git' -and $open -notcontains 'Nobody.Knows') 'Git is not running; an unknown app counts as not open'
Check ($open -notcontains 'Some.Msi' -and $open -notcontains 'Shared.Thing') 'shared folders (Windows, Common Files) say nothing about an app'
$env:ProgramFiles = $savedPF

Write-Host "`n===== DRIVERS FROM WINDOWS UPDATE (stand-in) =====" -ForegroundColor White
function New-FakeUpdate([string]$Title, [string]$Class, [bool]$Optional, [bool]$Eula = $true) {
    $u = [pscustomobject]@{ Title = $Title; DriverClass = $Class; BrowseOnly = $Optional; DriverVerDate = [datetime]'2026-09-01'
                            Identity = [pscustomobject]@{ UpdateID = [guid]::NewGuid().ToString() }; EulaAccepted = $Eula; Accepted = $false; IsDownloaded = $false }
    $u | Add-Member -MemberType ScriptMethod -Name AcceptEula -Value { $this.Accepted = $true; $this.EulaAccepted = $true }
    return $u
}
function New-FakeCollection([object[]]$Items) {
    $c = [pscustomobject]@{ List = (New-Object System.Collections.ArrayList) }
    foreach ($i in $Items) { [void]$c.List.Add($i) }
    $c | Add-Member -MemberType ScriptProperty -Name Count -Value { $this.List.Count }
    $c | Add-Member -MemberType ScriptMethod -Name Item -Value { param($i) $this.List[$i] }
    $c | Add-Member -MemberType ScriptMethod -Name Add -Value { param($x) $this.List.Add($x) }
    return $c
}
$script:FakeUpdates = @((New-FakeUpdate 'Intel Corporation - Display - 31.0.101.5186' 'Display' $false), (New-FakeUpdate 'Realtek - Audio - 6.0.9600.1' 'MEDIA' $true $false),
                       (New-FakeUpdate 'Lenovo Ltd. - Firmware - 1.38.0.0' 'Firmware' $false))
$script:SearchError = $null
function New-UpdateSession {
    $s = [pscustomobject]@{}
    $s | Add-Member -MemberType ScriptMethod -Name CreateUpdateSearcher -Value {
        $q = [pscustomobject]@{}
        $q | Add-Member -MemberType ScriptMethod -Name Search -Value { param($c) $script:Criteria = $c; if ($script:SearchError) { throw $script:SearchError }; [pscustomobject]@{ Updates = (New-FakeCollection $script:FakeUpdates) } }
        $q
    }
    $s | Add-Member -MemberType ScriptMethod -Name CreateUpdateDownloader -Value {
        $d = [pscustomobject]@{ Updates = $null }
        $d | Add-Member -MemberType ScriptMethod -Name Download -Value {
            if ($script:DownloadError -and $this.Updates.Item(0).Title -like $script:DownloadError[0]) { throw $script:DownloadError[1] }
            $script:Downloaded += $this.Updates.Count
            $r = [pscustomobject]@{ ResultCode = 2 }
            $r | Add-Member -MemberType ScriptMethod -Name GetUpdateResult -Value { param($n) [pscustomobject]@{ HResult = 0 } }
            $r
        }
        $d
    }
    $s | Add-Member -MemberType ScriptMethod -Name CreateUpdateInstaller -Value {
        $i = [pscustomobject]@{ Updates = $null; ForceQuiet = $false }
        $i | Add-Member -MemberType ScriptMethod -Name Install -Value {
            $script:Installed += $this.Updates.Count
            $one = $script:InstallResults[$script:InstallCall]
            $script:InstallCall++
            $r = [pscustomobject]@{ RebootRequired = $false; One = $one }
            $r | Add-Member -MemberType ScriptMethod -Name GetUpdateResult -Value { param($n) $this.One }
            $r
        }
        $i
    }
    return $s
}
function New-UpdateCollection { return (New-FakeCollection @()) }
function Get-Service { param($Name, $ErrorAction) [pscustomobject]@{ Status = 'Stopped'; StartType = $script:WuStart } }
$script:WuStart = 'Manual'
$d = Get-DriverUpdates
Check ($d.Ok -and $d.Drivers.Count -eq 2) 'two drivers found'
Check (@($d.Firmware).Count -eq 1 -and $d.Firmware[0].Name -match 'Firmware' -and @($d.Drivers | Where-Object { $_.Name -match 'Firmware' }).Count -eq 0) 'firmware (BIOS) updates are listed apart and never installed'
Check ($script:Criteria -eq "IsInstalled=0 and Type='Driver' and IsHidden=0") 'only drivers that are not installed and not hidden'
Check (-not $d.Drivers[0].Optional -and $d.Drivers[1].Optional -and $d.Drivers[0].Class -eq 'Display' -and $d.Drivers[0].To -eq '2026-09-01') 'recommended vs optional, class and date'
$script:WuStart = 'Disabled'
$d = Get-DriverUpdates
Check (-not $d.Ok -and $d.Reason -match 'turned off') 'Windows Update turned off: explained, nothing searched'
$script:WuStart = 'Manual'
$script:SearchError = New-Object System.Runtime.InteropServices.COMException('offline', -2145107924)   # 0x8024402C
$d = Get-DriverUpdates
Check (-not $d.Ok -and $d.Reason -eq 'no connection to Windows Update') "no connection: explained ($($d.Reason))"
$script:SearchError = New-Object System.Runtime.InteropServices.COMException('odd', -2145124318)        # 0x80240022
$d = Get-DriverUpdates
Check (-not $d.Ok -and (L $d.Reason $d.ReasonArg) -eq 'Windows Update error 0x80240022') "other errors show their code: $(L $d.Reason $d.ReasonArg)"
$script:SearchError = $null
$d = Get-DriverUpdates
$okResult = [pscustomobject]@{ ResultCode = 2; HResult = 0; RebootRequired = $false }
$rebootResult = [pscustomobject]@{ ResultCode = 2; HResult = 0; RebootRequired = $true }
$script:InstallResults = @($okResult, $rebootResult)
$script:Downloaded = 0; $script:Installed = 0; $script:InstallCall = 0
$res = @(Install-DriverUpdates $d.Drivers)
Check ($res.Count -eq 2 -and $res[0].Status -eq 'Updated' -and $res[1].Status -eq 'Restart') 'installed; the one that needs a restart says so'
Check ($script:Downloaded -eq 2 -and $script:Installed -eq 2) 'both were downloaded, then installed'
Check ($d.Drivers[1].Update.Accepted -and -not $d.Drivers[0].Update.Accepted) 'the licence is accepted only where Windows Update asks for it'
$script:InstallResults = @([pscustomobject]@{ ResultCode = 4; HResult = -2145124330; RebootRequired = $false }, $okResult)   # 0x80240016
$script:InstallCall = 0
$res = @(Install-DriverUpdates $d.Drivers)
Check ($res[0].Status -eq 'Failed' -and $res[0].Code -eq '0x80240016' -and $res[1].Status -eq 'Updated') 'a failed driver keeps its error code, the other one still installs'
$script:DownloadError = @('Intel*', (New-Object System.Runtime.InteropServices.COMException('denied', -2145124284)))   # 0x80240044
$script:InstallResults = @($okResult); $script:InstallCall = 0
$res = @(Install-DriverUpdates $d.Drivers)
Check ($res[0].Status -eq 'Failed' -and $res[0].Code -eq '0x80240044' -and $res[0].Detail -match '^download: ' -and $res[1].Status -eq 'Updated') "an error while downloading one driver: its real code and message, and the next one still installs ($($res[0].Code) $($res[0].Detail))"
$script:DownloadError = $null
$gone = [pscustomobject]@{ Kind = 'Driver'; Name = 'Gone driver'; Id = 'x'; From = ''; To = ''; Update = $null }
$res = @(Install-DriverUpdates @($gone))
Check ($res[0].Status -eq 'Failed' -and $res[0].Detail -match 'no longer offers') 'an update Windows Update no longer has: said in words, not a bare code'
$out = (Write-UpdateResult $res[0] 6>&1 | Out-String)
Check ($out -match 'Gone driver: error 0x[0-9A-F]{8} \(prepare: ') "the reason is shown next to the code: $($out.Trim())"
Check ((Format-HexCode -2145124284) -eq '0x80240044' -and (Format-HexCode 2149843012) -eq '0x80240044' -and (Format-HexCode 0) -eq '0x00000000') 'error codes read the same whether Windows gives them signed or not'

Write-Host "`n===== AN APP WHOSE NEW VERSION USES ANOTHER INSTALLER =====" -ForegroundColor White
$script:Winget = New-Object System.Collections.Generic.List[string]
function Invoke-Winget([string[]]$Arguments) {
    $script:Winget.Add($Arguments[0])
    switch ($Arguments[0]) {
        'upgrade'   { return [pscustomobject]@{ Code = -1978335090; Lines = @() } }   # 0x8A15008E
        'uninstall' { return [pscustomobject]@{ Code = 0; Lines = @() } }
        'install'   { return [pscustomobject]@{ Code = 0; Lines = @() } }
    }
}
function Get-WingetQuietArgs { @() }
$pp = [pscustomobject]@{ Kind = 'App'; Name = 'Proton Pass'; Id = 'Proton.ProtonPass'; From = '1.37.0'; To = '1.42.0'; InUse = $false }
$script:Asked = @()
function Confirm-Action { param($Question, $Default) $script:Asked += $Question; $true }
$res = @(Install-ChosenUpdates @($pp) 'Manual' 6>$null)
Check ($script:Asked.Count -eq 1 -and $script:Asked[0] -match '^Reinstall Proton Pass\?' -and ($script:Winget -join ',') -eq 'upgrade,uninstall,install' -and $res[0].Status -eq 'Updated') "0x8A15008E: YSO offers to reinstall it, then removes the old version and installs the new one ($($script:Winget -join ', '))"
$script:Winget.Clear(); $script:Asked = @()
function Confirm-Action { param($Question, $Default) $script:Asked += $Question; $false }
$res = @(Install-ChosenUpdates @($pp) 'Manual' 6>$null)
Check (($script:Winget -join ',') -eq 'upgrade' -and $res[0].Status -eq 'Failed' -and (Get-UpdateMessage $res[0].Code) -match 'another installer') 'answering No changes nothing, and the reason is said in words'
$script:Winget.Clear(); $script:Asked = @()
$res = @(Install-ChosenUpdates @($pp) 'Auto' 6>$null)
Check ($script:Asked.Count -eq 0 -and ($script:Winget -join ',') -eq 'upgrade') 'automatic updates never uninstall anything'
Remove-Item function:Invoke-Winget, function:Get-WingetQuietArgs, function:Confirm-Action
function Read-Host { param($Prompt) $script:Typed }
$script:Typed = 'T'
Check (((Read-UpdateSelection 5 @(2, 4) 6>$null) -join ',') -eq '1,2,3,4,5') 'T installs all of them'
$script:Typed = 'A'
Check (((Read-UpdateSelection 5 @(2, 4) 6>$null) -join ',') -eq '2,4') 'A installs the recommended ones'
Remove-Item function:Read-Host

Write-Host "`n===== AUTOMATIC RUN =====" -ForegroundColor White
$script:Calls = New-Object System.Collections.Generic.List[string]
function Get-AppUpdates {
    $script:Calls.Add('apps')
    $a = @(
        [pscustomobject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.43.0'; Available = '2.47.1'; Table = 'Normal'; Note = '' },
        [pscustomobject]@{ Name = 'Node.js'; Id = 'OpenJS.NodeJS.LTS'; Version = '20.11.0'; Available = '22.12.0'; Table = 'Normal'; Note = '' },
        [pscustomobject]@{ Name = 'Discord'; Id = 'Discord.Discord'; Version = '1.0.9034'; Available = '1.0.9035'; Table = 'Normal'; Note = '' },
        [pscustomobject]@{ Name = 'Zoom'; Id = 'Zoom.Zoom'; Version = '6.1'; Available = '6.2'; Table = 'Normal'; Note = '' },
        [pscustomobject]@{ Name = 'MongoDB 7.0.45'; Id = 'MongoDB.Server'; Version = '7.0.45'; Available = '9.0.2'; Table = 'Normal'; Note = '' })
    return [pscustomobject]@{ Ok = $true; Reason = ''; ReasonArg = ''; Apps = $a; Others = @(); Raw = @('raw line'); ParseFailed = $false }
}
function Get-AppsInUse($Items) { @('Discord.Discord') }
function Get-DriverUpdates {
    $script:Calls.Add('drivers')
    $dr = @(
        [pscustomobject]@{ Kind = 'Driver'; Name = 'Intel - Display'; Id = 'd1'; From = ''; To = '2026-09-01'; Class = 'Display'; Optional = $false; Excluded = $false; InUse = $false; Update = $null },
        [pscustomobject]@{ Kind = 'Driver'; Name = 'Realtek - Audio'; Id = 'd2'; From = ''; To = '2026-08-01'; Class = 'MEDIA'; Optional = $true; Excluded = $false; InUse = $false; Update = $null })
    return [pscustomobject]@{ Ok = $true; Reason = ''; ReasonArg = ''; Drivers = $dr }
}
function Install-AppUpdate($Item) { $script:Calls.Add("install $($Item.Id)"); New-UpdateResult $Item $(if ($Item.Id -eq 'Git.Git') { 'Updated' } else { 'Failed' }) '0x8A150107' }
function Install-DriverUpdates($Drivers) { foreach ($x in $Drivers) { $script:Calls.Add("driver $($x.Id)"); New-UpdateResult $x 'Restart' '0x00000000' } }
function New-YsoRestorePoint { param([switch]$Quiet) $script:Calls.Add("restore point quiet=$Quiet"); $true }
function Show-Toast($Title, $Text) { $script:Calls.Add("toast $Text") }
function Show-DriverSources { $script:Calls.Add('sources') }
$AutoUpdate = $true
$sum = Invoke-UpdateRun -Mode 'Auto' 6>$null
$AutoUpdate = $false
Write-Host ('      ' + ($script:Calls -join ' > ')) -ForegroundColor DarkGray
Check ($script:Calls -contains 'install Git.Git' -and $script:Calls -contains 'install Zoom.Zoom') 'Git and Zoom are updated (Zoom fails: no internet)'
Check ($script:Calls -notcontains 'install OpenJS.NodeJS.LTS') 'Node.js is not (excluded)'
Check ($script:Calls -notcontains 'install Discord.Discord') 'Discord is not (open right now)'
Check ($script:Calls -notcontains 'install MongoDB.Server') 'MongoDB 7 -> 9 is not (new major version)'
Check ($script:Calls -contains 'driver d1' -and $script:Calls -notcontains 'driver d2') 'the recommended driver is installed, the optional one is not'
Check ($script:Calls.IndexOf('restore point quiet=True') -ge 0 -and $script:Calls.IndexOf('restore point quiet=True') -lt $script:Calls.IndexOf('driver d1')) 'a restore point is made first, without turning System Restore on by itself'
Check ($script:Calls -notcontains 'sources') 'no questions, no extra screens'
$toast = @($script:Calls | Where-Object { $_ -like 'toast *' })
Check ($toast.Count -eq 1 -and $toast[0] -match '2 update\(s\) installed' -and $toast[0] -match '1 could not be installed' -and $toast[0] -match '1 skipped' -and $toast[0] -match 'Restart to finish') "a notification sums it up: $($toast[0])"
Check ($sum.Installed -eq 2 -and $sum.NotInstalled -eq 1 -and $sum.Restart) 'the summary counts (used for the exit code)'
$hist = @(Import-Csv -LiteralPath $script:UpdateHistoryPath)
$runRow = @($hist | Where-Object { $_.Kind -eq 'Run' })
Check ($runRow.Count -eq 1 -and $runRow[0].Mode -eq 'Auto' -and $runRow[0].Found -eq '7' -and $runRow[0].Installed -eq '2' -and $runRow[0].NotInstalled -eq '1') 'the history has the run with its counts'
Check (@($hist | Where-Object { $_.Id -eq 'Discord.Discord' -and $_.Status -eq 'Skipped' }).Count -eq 1) 'the skipped open app is in the history'
$rep = Get-ChildItem "$Sandbox/ProgramData/YSO/Reports" -Filter 'updates_*.txt' | Sort-Object LastWriteTime | Select-Object -Last 1
Check ($null -ne $rep -and (Get-Content $rep.FullName -Raw) -match 'App\s+Git \| Git.Git \| 2.43.0 -> 2.47.1\s+chosen') 'a report lists what was found and chosen'

$script:Calls.Clear(); $script:Settings.Updates.MajorVersions = $true
$AutoUpdate = $true; [void](Invoke-UpdateRun -Mode 'Auto' 6>$null); $AutoUpdate = $false
Check ($script:Calls -contains 'install MongoDB.Server' -and $script:Calls -notcontains 'install OpenJS.NodeJS.LTS') 'major versions allowed in Settings: MongoDB is updated (an excluded app still is not)'
$script:Settings.Updates.MajorVersions = $false

$script:Calls.Clear(); $script:Settings.Updates.Apps = $false
$AutoUpdate = $true; [void](Invoke-UpdateRun -Mode 'Auto' 6>$null); $AutoUpdate = $false
Check ($script:Calls -notcontains 'apps' -and $script:Calls -contains 'drivers') 'apps turned off in Settings: winget is not even asked'
$script:Settings.Updates.Apps = $true

$script:Calls.Clear(); $script:DryRun = $true
$AutoUpdate = $true; [void](Invoke-UpdateRun -Mode 'Auto' 6>$null); $AutoUpdate = $false
$script:DryRun = $false
Check (@($script:Calls | Where-Object { $_ -like 'install*' -or $_ -like 'driver d*' -or $_ -like 'restore*' -or $_ -like 'toast*' }).Count -eq 0) 'check-only mode (-DryRun) installs nothing'
$rep = Get-ChildItem "$Sandbox/ProgramData/YSO/Reports" -Filter 'updates_*.txt' | Sort-Object LastWriteTime | Select-Object -Last 1
Check ((Get-Content $rep.FullName -Raw) -match 'check only, nothing installed' -and (Get-Content $rep.FullName -Raw) -match 'WINGET OUTPUT') 'its report says so and keeps winget''s raw output for checking'

$script:Calls.Clear()
function Enter-UpdateLock { $false }
$sum = Invoke-UpdateRun -Mode 'Auto' 6>$null
Check ($sum.Busy -and $script:Calls.Count -eq 0) 'only one update run at a time'
Remove-Item function:Enter-UpdateLock
Invoke-Expression ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Enter-UpdateLock' }, $false)[0].Extent.Text)

Write-Host "`n===== CHOOSING (MANUAL) =====" -ForegroundColor White
$script:Answers = New-Object System.Collections.Queue
function Read-Host { param($Prompt) if ($script:Answers.Count -gt 0) { return $script:Answers.Dequeue() } return '' }
function Confirm-Action { param($Question, $Default) $script:Calls.Add("ask $Question"); return $true }
function Run-Manual([string[]]$Answers) {
    $script:Calls.Clear(); $script:Answers.Clear(); foreach ($a in $Answers) { $script:Answers.Enqueue($a) }
    [void](Invoke-UpdateRun -Mode 'Manual' 6>$null)
}
Run-Manual @('A')
Check ($script:Calls -contains 'install Git.Git' -and $script:Calls -contains 'install Discord.Discord' -and $script:Calls -contains 'install Zoom.Zoom' -and $script:Calls -notcontains 'install OpenJS.NodeJS.LTS' -and $script:Calls -notcontains 'install MongoDB.Server') 'A = recommended: Git, Zoom and Discord (open, after a warning), not Node.js (excluded) nor MongoDB (major)'
Check (@($script:Calls | Where-Object { $_ -like 'ask Open now*' -or $_ -like 'ask Continue*' }).Count -eq 1) 'you are warned that Discord is open'
Check ($script:Calls -contains 'driver d1' -and $script:Calls -notcontains 'driver d2' -and $script:Calls -contains 'restore point quiet=False') 'the recommended driver, after offering a restore point'
Run-Manual @('2,5,7')
Check ((@($script:Calls | Where-Object { $_ -like 'install*' -or $_ -like 'driver d*' }) -join ',') -eq 'install OpenJS.NodeJS.LTS,install MongoDB.Server,driver d2') 'numbers = exactly those (excluded apps, major versions and optional drivers are allowed when you pick them)'
$before = @(Import-Csv -LiteralPath $script:UpdateHistoryPath).Count
Run-Manual @('')
Check (@($script:Calls | Where-Object { $_ -like 'install*' -or $_ -like 'driver d*' }).Count -eq 0) 'Enter = nothing installed'
Check (@(Import-Csv -LiteralPath $script:UpdateHistoryPath).Count -eq $before) 'and nothing added to the history'
$script:Answers.Clear(); foreach ($a in @('3-1', '2, 9 x 5')) { $script:Answers.Enqueue($a) }
$p1 = @(Read-UpdateSelection 6 @(1)); $p2 = @(Read-UpdateSelection 6 @(1) 6>$null)
Check (($p1 -join ',') -eq '1,2,3' -and ($p2 -join ',') -eq '2,5') "ranges work both ways, wrong numbers are ignored ($($p1 -join ','); $($p2 -join ','))"

Write-Host "`n===== SETTINGS =====" -ForegroundColor White
$def = (Get-DefaultSettings).Updates
Check ($def.Frequency -eq 'weekly' -and $def.Day -eq 'Sunday' -and $def.Time -eq '12:00' -and $def.Apps -and $def.Drivers -and -not $def.OptionalDrivers -and $def.Notify) 'defaults: weekly, Sunday 12:00, apps + recommended drivers, notification'
New-Item -ItemType Directory -Force (Split-Path $script:SettingsPath) | Out-Null
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Language": "fr", "AutoClean": { "TempFiles": false } }'
Import-Settings
Check (-not $script:SettingsError -and $script:Settings.Updates.Time -eq '12:00' -and @($script:Settings.Updates.ExcludeApps).Count -eq 5 -and -not $script:Settings.Updates.MajorVersions) 'a settings file from 3.5 (no Updates part) gets the defaults'
Set-Content -LiteralPath $script:SettingsPath -Value '{ "Updates": { "Frequency": "DAILY", "Day": "friday", "Time": "7:00", "OptionalDrivers": "true", "Notify": 0, "MajorVersions": "1", "ExcludeApps": [] } }'
Import-Settings
$u = $script:Settings.Updates
Check ($u.Frequency -eq 'daily' -and $u.Day -eq 'Friday' -and $u.Time -eq '12:00' -and $u.OptionalDrivers -eq $true -and $u.Notify -eq $false -and $u.MajorVersions -eq $true) 'values are checked: day and case fixed, an invalid time ignored, "true" and 0 understood'
Check (@($u.ExcludeApps).Count -eq 0) 'an emptied exclusion list stays empty'
$u.ExcludeApps = [string[]]@('Only.One')
[void](Save-Settings)
Check ((Get-Content -LiteralPath $script:SettingsPath -Raw) -match '"ExcludeApps":\s*\[\s*"Only.One"\s*\]') 'a list of one is still saved as a list'
Import-Settings
Check (@($script:Settings.Updates.ExcludeApps) -join ',' -eq 'Only.One') 'and read back'
Remove-Item -LiteralPath $script:SettingsPath; Import-Settings

Write-Host "`n===== SCHEDULE AND TASK =====" -ForegroundColor White
$script:Lang = 'en'; $script:Settings.Updates.Day = 'Friday'; $script:Settings.Updates.Time = '07:30'
Check ((Get-UpdateScheduleText) -eq 'every Friday at 07:30') "English: $(Get-UpdateScheduleText)"
$script:Lang = 'fr'
Check ((Get-UpdateScheduleText) -eq 'chaque vendredi à 07:30') "French: $(Get-UpdateScheduleText)"
$script:Settings.Updates.Frequency = 'daily'
Check ((Get-UpdateScheduleText) -eq 'tous les jours à 07:30') "daily: $(Get-UpdateScheduleText)"
$script:Lang = 'en'
$script:Task = @{}
function New-ScheduledTaskTrigger { param([switch]$Daily, [switch]$Weekly, $DaysOfWeek, $At) $script:Task.Trigger = @{ Daily = [bool]$Daily; Weekly = [bool]$Weekly; Days = "$DaysOfWeek"; At = $At } }
function New-ScheduledTaskAction { param($Execute, $Argument) $script:Task.Action = "$Execute $Argument" }
function New-ScheduledTaskSettingsSet { param([switch]$StartWhenAvailable, [switch]$RunOnlyIfNetworkAvailable, [switch]$DontStopIfGoingOnBatteries, [switch]$AllowStartIfOnBatteries, $ExecutionTimeLimit)
    $script:Task.Settings = @{ Start = [bool]$StartWhenAvailable; Network = [bool]$RunOnlyIfNetworkAvailable; KeepOnBattery = [bool]$DontStopIfGoingOnBatteries; StartOnBattery = [bool]$AllowStartIfOnBatteries; Limit = $ExecutionTimeLimit } }
function New-ScheduledTaskPrincipal { param($UserId, $LogonType, $RunLevel) $script:Task.Principal = @{ User = $UserId; Logon = "$LogonType"; Level = "$RunLevel" } }
function Register-ScheduledTask { param($TaskName, $Action, $Trigger, $Settings, $Principal, $Description, [switch]$Force, $ErrorAction) $script:Task.Name = $TaskName }
function Get-CurrentUserName { 'DESKTOP-AB12CD\Alex' }
Set-Content -LiteralPath "$Sandbox/YSO.ps1" -Value "`$script:Version       = '1.0'"
function Install-YsoCopy { param([string]$Source) 'C:\Program Files\YSO\YSO.ps1' }
$ok = Register-UpdateTask
Check ($ok -and $script:Task.Name -eq 'YSO Auto Updates') 'the task is registered'
Check ($script:Task.Trigger.Daily -and $script:Task.Trigger.At.ToString('HH:mm') -eq '07:30') 'daily at 07:30'
$script:Settings.Updates.Frequency = 'weekly'; [void](Register-UpdateTask)
Check ($script:Task.Trigger.Weekly -and $script:Task.Trigger.Days -eq 'Friday') 'weekly on Friday'
Check ($script:Task.Action -match '-WindowStyle Hidden' -and $script:Task.Action -match '-File "C:\\Program Files\\YSO\\YSO.ps1" -AutoUpdate$') "runs the protected copy with -AutoUpdate, hidden"
Check ($script:Task.Principal.User -eq 'DESKTOP-AB12CD\Alex' -and $script:Task.Principal.Logon -eq 'Interactive' -and $script:Task.Principal.Level -eq 'Highest') 'as you (winget sees your apps), with admin rights, only while you are logged on'
Check ($script:Task.Settings.Start -and $script:Task.Settings.Network -and $script:Task.Settings.KeepOnBattery -and -not $script:Task.Settings.StartOnBattery -and $script:Task.Settings.Limit.TotalHours -eq 3) 'catches up after the PC was off, needs internet, starts only on mains power, never cut in the middle'
Remove-Item function:Install-YsoCopy
Invoke-Expression ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Install-YsoCopy' }, $false)[0].Extent.Text)

Write-Host "`n===== THE COPY USED BY SCHEDULED TASKS =====" -ForegroundColor White
$env:ProgramFiles = "$Sandbox/ProgramFiles"
$copyDir = Join-Path $env:ProgramFiles 'YSO'
$copy = Join-Path $copyDir 'YSO.ps1'
$target = Install-YsoCopy -Source "$Sandbox/YSO.ps1"
Check ($target -eq $copy -and (Test-Path $copy)) 'Install-YsoCopy puts YSO in Program Files'
$script:TasksPresent = @('YSO Auto Updates')
function Get-ScheduledTask { param($TaskName, $ErrorAction) if ($script:TasksPresent -contains $TaskName) { [pscustomobject]@{ TaskName = $TaskName } } }
Remove-YsoCopyIfUnused
Check (Test-Path $copy) 'turning auto-clean off keeps the copy while automatic updates use it'
$script:TasksPresent = @()
Remove-YsoCopyIfUnused
Check (-not (Test-Path $copyDir)) 'and removes it when no task uses it any more'
[void](Install-YsoCopy -Source "$Sandbox/YSO.ps1")
Set-Content -LiteralPath "$Sandbox/new.ps1" -Value "`$script:Version       = '1.0'`n# newer file"
Update-YsoCopy -Source "$Sandbox/new.ps1"
Check ((Get-Content $copy -Raw) -match 'newer file') 'starting a newer YSO refreshes the copy (no need to switch tasks off and on)'
Set-Content -LiteralPath $copy -Value "`$script:Version       = '9.0'`n`$script:ReleaseRepo   = 'b-draoui/yso'"
Update-YsoCopy -Source "$Sandbox/new.ps1"
Check ((Get-Content $copy -Raw) -match "'9.0'") 'an older YSO never replaces a newer copy'
Set-Content -LiteralPath $copy -Value "`$script:Version       = '5.0'"
Update-YsoCopy -Source "$Sandbox/new.ps1"
Check ((Get-Content $copy -Raw) -match 'newer file') 'a test build made before 1.0 (no update button) is replaced'
Remove-Item -LiteralPath $copyDir -Recurse -Force
Update-YsoCopy -Source "$Sandbox/new.ps1"
Check (-not (Test-Path $copyDir)) 'no copy yet (no task): nothing is created'

Write-Host "`n===== SCREENS =====" -ForegroundColor White
$script:Lang = 'fr'
$out = (Show-UpdateHistory 6>&1 | Out-String)
Check ($out -match 'HISTORIQUE DES MISES À JOUR' -and $out -match '\(Auto\) : 7 trouvée\(s\), 2 installée\(s\), 1 non installée\(s\)') 'history in French, with the counts of each run'
Check ($out -match 'Git 2.43.0 -> 2.47.1\s+installée' -and $out -match "ignorée - l'appli était ouverte" -and $out -match 'pas de connexion internet') 'each update with its result and the reason it failed'
$items = @(
    [pscustomobject]@{ Kind = 'App'; Name = 'Node.js'; Id = 'OpenJS.NodeJS.LTS'; From = '20.11.0'; To = '22.12.0'; Excluded = $true; InUse = $false; Optional = $false },
    [pscustomobject]@{ Kind = 'Driver'; Name = 'Realtek - Audio'; Id = 'd2'; From = ''; To = ''; Excluded = $false; InUse = $false; Optional = $true })
$out = (Show-UpdateList $items @([pscustomobject]@{ Name = 'Zotero'; Version = '6.0.30'; Available = '7.0.11' }) 6>&1 | Out-String)
Check ($out -match "MISES À JOUR D'APPLIS" -and $out -match 'pas en auto' -and $out -match 'facultatif' -and $out -match 'PAS MISES À JOUR PAR YSO') 'the list says what is not automatic, what is optional, and what YSO leaves alone'
$script:Lang = 'en'
function Get-ScheduledTask { param($TaskName, $ErrorAction) if ($TaskName -eq 'YSO Auto Updates') { [pscustomobject]@{ TaskName = $TaskName } } }
function Get-Volume { }
function Clear-Host { }
$out = (Show-Menu -Width 120 6>&1 | Out-String)
Check ($out -match '28\s+Updates: apps & drivers \[AUTO\]') 'the main menu shows whether updates are automatic'
Invoke-Expression ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Show-Toast' }, $false)[0].Extent.Text)
Check ((Show-Toast 'YSO' 'test') -eq $false) 'a notification that cannot be shown (not Windows) fails quietly'

Write-Host "`n===== -AutoUpdate SWITCH (YSO's real start-up code) =====" -ForegroundColor White
foreach ($m in @(@('autoupdate-check', 0), @('autoupdate-run', 1))) {
    $box = "$Sandbox/child-$($m[0])"
    $out = & $Pwsh -NoProfile -File $Child -ScriptPath $ScriptPath -Sandbox $box -Mode $m[0] 2>&1 | Out-String
    $code = $LASTEXITCODE
    $out = $out -replace '\x1b\[[0-9;]*m', ''
    if ($m[0] -eq 'autoupdate-check') {
        Check ($code -eq 0 -and $out -match 'YSO automatic updates' -and $out -match 'Check only: nothing was installed \(1 update\(s\) would be\)') "check only: exit code $code, nothing installed"
        Check (-not (Test-Path "$box/ProgramData/YSO/updates.csv") -and @(Get-ChildItem "$box/ProgramData/YSO/Reports" -Filter 'updates_*.txt').Count -eq 1) 'a report, no history'
    } else {
        Check ($code -eq 1 -and $out -match '0 installed, 1 not installed') "an update that fails makes the task end with code 1 (got $code), so Task Scheduler shows it"
    }
    Check ($out -notmatch 'NOT REACHED' -and $out -notmatch 'Press Enter') 'it ends by itself, without waiting for a key'
}

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
