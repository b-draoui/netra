param([string]$ScriptPath, [string]$Sandbox)
# The window. WPF itself only exists on Windows (the CI draws every page there); this suite
# checks everything around it on any OS: the layout file, the texts, and the second PowerShell that
# does the work - what it writes, asks and measures, and how Stop ends it.
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force "$Sandbox/tmp" | Out-Null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
$funcText = New-Object System.Text.StringBuilder
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    Invoke-Expression $fn.Extent.Text
    [void]$funcText.AppendLine($fn.Extent.Text)
}
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $env:SystemDrive = 'C:'
$DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
Import-Settings
New-Item -ItemType Directory -Force $script:DataDir | Out-Null

Write-Host "`n===== THE LAYOUT (XAML) =====" -ForegroundColor White
$xamlText = Get-YsoXaml
$names = @{}
foreach ($lang in 'en', 'fr') {
    $script:Lang = $lang
    $x = ConvertTo-GuiXaml $xamlText
    $doc = $null
    try { $doc = [xml]$x } catch { Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkGray }
    Check ($null -ne $doc) "the layout is valid XML once translated ($lang)"
    Check ($x -notmatch '\[\[') "every text of the layout is replaced ($lang)"
}
$script:Lang = 'en'
$doc = [xml](ConvertTo-GuiXaml $xamlText)
$ns = New-Object System.Xml.XmlNamespaceManager $doc.NameTable
$ns.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
$all = @($doc.SelectNodes('//*[@x:Name]', $ns) | ForEach-Object { $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml') })
$dupes = @($all | Group-Object | Where-Object { $_.Count -gt 1 -and $_.Name -notin @('Bd', 'Box', 'Tick', 'Mark', 'PART_Track', 'PART_Indicator', 'TemplateRoot', 'Runner', 'RunnerMove') })
Check ($dupes.Count -eq 0) "element names are unique ($($dupes.Name -join ', '))"
$show = ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Show-YsoWindow' }, $false)[0]).Extent.Text
$wanted = @([regex]::Match($show, "foreach \(\`$name in @\(([^)]*)\)\)").Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim() } | Where-Object { $_ })
$missing = @($wanted | Where-Object { $all -notcontains $_ })
Check ($wanted.Count -ge 60 -and $missing.Count -eq 0) "every element the code uses is in the layout ($($wanted.Count) used; missing: $($missing -join ', '))"
$keys = @($doc.SelectNodes('//*[@x:Key]', $ns) | ForEach-Object { $_.GetAttribute('Key', 'http://schemas.microsoft.com/winfx/2006/xaml') })
$refs = @([regex]::Matches($xamlText, '\{StaticResource ([A-Za-z0-9]+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$badRefs = @($refs | Where-Object { $keys -notcontains $_ })
Check ($badRefs.Count -eq 0) "every {StaticResource} of the layout exists ($($refs.Count) used; unknown: $($badRefs -join ', '))"
$codeRes = @([regex]::Matches($src, "FindResource\('([A-Za-z0-9]+)'\)|Get-GuiBrush '([A-Za-z0-9]+)'|New-GuiText [^|\r\n]*? '(Text|Text2|Text3|Accent)'") | ForEach-Object { ($_.Groups[1].Value + $_.Groups[2].Value + $_.Groups[3].Value) } | Sort-Object -Unique)
$consoleColors = @('Gray', 'White', 'DarkGray', 'Green', 'DarkGreen', 'Cyan', 'DarkCyan', 'Yellow', 'DarkYellow', 'Red', 'DarkRed', 'Magenta', 'DarkMagenta', 'Blue', 'DarkBlue', 'Black')
$badCode = @($codeRes | Where-Object { $_ -and $keys -notcontains $_ -and $consoleColors -notcontains $_ })
Check ($codeRes.Count -ge 8 -and $badCode.Count -eq 0) "every colour and style the code asks for exists ($($codeRes.Count) used; unknown: $($badCode -join ', '))"
$levels = [regex]::Match($src, 'Good = @\(''Good'', ''GoodSoft''[^\r\n]+\r?\n[^\r\n]+').Value
Check ($keys -contains 'GoodSoft' -and $keys -contains 'WarnSoft' -and $keys -contains 'BadSoft' -and $keys -contains 'InfoSoft' -and $levels -match 'InfoSoft') 'green / orange / red / blue for the health cards'
$icons = @([regex]::Matches($xamlText, '&#x(E[0-9A-F]{3});') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Check ($icons.Count -ge 10) "icons come from the Windows icon font ($($icons.Count) different)"

Write-Host "`n===== THE SAME ON EVERY WINDOWS LANGUAGE =====" -ForegroundColor White
# WPF's converters read "0,2,0,0" with the comma of the Windows language: on a French Windows that is 0.2
# and the window did not open. Sizes are built by YSO itself, the same everywhere.
$gui = $src.Substring($src.IndexOf('#  Window (WPF)'))
$gui = $gui.Substring(0, $gui.IndexOf('#  Install & uninstall'))
$risky = @([regex]::Matches($gui, "(ThicknessConverter|GridLengthConverter|CornerRadiusConverter|LengthConverter)|\.(Margin|Padding|PagePadding|BorderThickness|CornerRadius|Width|Height) = ['`"]") | ForEach-Object { $_.Value })
Check ($risky.Count -eq 0) "no size is read from text by WPF ($($risky -join ', '))"
if (-not ('System.Windows.Thickness' -as [type])) {
    # WPF exists only on Windows: a stand-in with the same constructors, to run YSO's own function here.
    Add-Type -TypeDefinition 'namespace System.Windows { public struct Thickness { public double Left, Top, Right, Bottom; public Thickness(double a) { Left = Top = Right = Bottom = a; } public Thickness(double l, double t, double r, double b) { Left = l; Top = t; Right = r; Bottom = b; } } }'
}
$before = [System.Threading.Thread]::CurrentThread.CurrentCulture
$got = @()
try {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new('fr-FR')
    foreach ($m in @('0,2,0,0', '16,14', '7', '12.5,3')) { $th = New-GuiThickness $m; $got += [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}/{1}/{2}/{3}', $th.Left, $th.Top, $th.Right, $th.Bottom) }
} finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $before }
$want = @('0/2/0/0', '16/14/16/14', '7/7/7/7', '12.5/3/12.5/3')
Check (($got -join ' ') -eq ($want -join ' ')) "margins are read the same on a French Windows ($($got -join ' '))"

Write-Host "`n===== PAGES AND THE MENU =====" -ForegroundColor White
$tools = @(Get-GuiToolGroups | ForEach-Object { $_.Items } | ForEach-Object { $_[0] })
$notInTools = @($script:MenuKeys | Where-Object { $tools -notcontains $_ })
Check ($notInTools.Count -eq 0 -and $tools -contains 'L' -and $tools -notcontains 'C') "All tools lists every option, plus the logs folder ($($tools.Count) buttons)"
Check ((Get-GuiOptionTitle '27') -eq 'Space finder (what fills my disk?)' -and (Get-GuiOptionTitle 'F') -eq 'Full maintenance') 'a page title is the name of the option'
$script:Lang = 'fr'
Check ((Get-GuiOptionTitle 'F') -eq 'Entretien complet') 'in French too'
$script:Lang = 'en'
$analysisCats = @('Temporary files', 'Browser caches', 'System junk', 'Windows Update cache', 'GPU shader caches', 'Developer & app caches', 'Other app caches', 'Site offline caches', 'Recycle Bin', 'Old driver versions', 'Delivery Optimization')
$rowCats = @(Get-GuiCleanItems | ForEach-Object { $_.Cats })
Check (@($analysisCats | Where-Object { $rowCats -notcontains $_ }).Count -eq 0) 'every result of Analyze has its line on the Clean page'
$items = @(Get-GuiCleanItems)
Check (@($items | Where-Object { -not $_.On }).Key -join ',' -eq 'OldDrivers,RecycleBin') 'only what cannot be undone is unticked at first: old drivers, Recycle Bin'

Write-Host "`n===== CLEAN EVERYTHING = F WITH ENTER EVERYWHERE =====" -ForegroundColor White
$script:Ran = New-Object System.Collections.Generic.List[string]
foreach ($n in 'New-YsoRestorePoint', 'Clear-TempFiles', 'Clear-SystemJunk', 'Clear-DevAppCaches', 'Clear-ShaderCaches', 'Clear-UpdateCache', 'Clear-YsoRecycleBin', 'Clear-Dns', 'Optimize-Drives', 'Clear-SiteOfflineCaches', 'Remove-OldDriverPackages') {
    Invoke-Expression "function $n { `$script:Ran.Add('$n') }"
}
function Invoke-DeepClean { param([string]$OldDrivers) $script:Ran.Add("Invoke-DeepClean($OldDrivers)") }
function Close-Apps { param([string[]]$Names) $script:Ran.Add("Close-Apps($($Names -join '+'))") }
function Clear-BrowserCaches { param([switch]$NoPrompt, [switch]$CloseBrowsers) $script:Ran.Add("Clear-BrowserCaches(close=$CloseBrowsers)") }
function Invoke-UpdateRun { param([string]$Mode) $script:Ran.Add("Invoke-UpdateRun($Mode)") }
function Find-OldDrivers { @([pscustomobject]@{ Inf = 'oem1.inf'; Bytes = 1GB; Provider = 'NVIDIA' }) }
function Get-RecycleBinBytes { 5MB }
function Test-PendingReboot { $false }
function Get-Process { param($Name, $ErrorAction) @([pscustomobject]@{ ProcessName = 'brave' }, [pscustomobject]@{ ProcessName = 'Spotify' }) | Where-Object { @($Name) -contains $_.ProcessName } }
function Show-MoreSpace { }
$script:Questions = New-Object System.Collections.Generic.List[string]
function Confirm-Action { param($Question, $Default) $script:Questions.Add($Question); $Default }
Invoke-FullMaintenance 6>$null
$console = @($script:Ran)
$script:Ran.Clear(); $script:Questions.Clear()
$plan = Get-GuiCleanPlan -Defaults
Invoke-FullMaintenance -Plan $plan 6>$null
$window = @($script:Ran)
Write-Host ('      console F with Enter: ' + ($console -join ' > ')) -ForegroundColor DarkGray
Write-Host ('      Clean everything:     ' + ($window -join ' > ')) -ForegroundColor DarkGray
Check (($console -join '|') -eq ($window -join '|')) 'Clean everything in the window runs exactly what F does when you press Enter at every question'
Check ($script:Questions.Count -eq 0) 'and asks nothing (the window showed what it does first)'
$script:Ran.Clear()
$plan = @{ Temp = $true; Browsers = $false; SystemJunk = $false; DevApps = $false; UpdateCache = $false; Dns = $false; OldDrivers = $true; Deep = $false; RecycleBin = $true; CloseApps = $false; CloseBrowsers = $false }
Invoke-FullMaintenance -Plan $plan 6>$null
Check ((@($script:Ran) -join ',') -eq 'Clear-TempFiles,Clear-YsoRecycleBin,Remove-OldDriverPackages') "only what is ticked runs; old drivers without deep clean too ($(@($script:Ran) -join ', '))"
foreach ($n in 'New-YsoRestorePoint', 'Clear-TempFiles', 'Clear-SystemJunk', 'Clear-DevAppCaches', 'Clear-ShaderCaches', 'Clear-UpdateCache', 'Clear-YsoRecycleBin', 'Clear-Dns', 'Optimize-Drives', 'Clear-SiteOfflineCaches', 'Remove-OldDriverPackages',
                 'Invoke-DeepClean', 'Close-Apps', 'Clear-BrowserCaches', 'Invoke-UpdateRun', 'Find-OldDrivers', 'Get-RecycleBinBytes', 'Test-PendingReboot', 'Get-Process', 'Show-MoreSpace', 'Confirm-Action') {
    Remove-Item -LiteralPath "function:$n" -ErrorAction SilentlyContinue
    if ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $n }, $false).Count) {
        Invoke-Expression ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $n }, $false)[0].Extent.Text)
    }
}

Write-Host "`n===== WHAT WRITE-HOST PRINTS =====" -ForegroundColor White
Check ((ConvertTo-HostText $null) -eq '' -and (ConvertTo-HostText @('a')) -eq 'a' -and (ConvertTo-HostText @('a', 'b')) -eq 'a b') 'one text, several texts, nothing'
Check ((ConvertTo-HostText @(, @(1, 2, 3)) '-') -eq '1-2-3' -and (ConvertTo-HostText @(5)) -eq '5') 'a list is joined like Write-Host does'

Write-Host "`n===== THE SECOND POWERSHELL =====" -ForegroundColor White
# Like the window: a runspace with YSO's functions and settings, then the adapters.
$shared = New-GuiShared
$rs = [runspacefactory]::CreateRunspace()
$rs.Open()
$boot = [powershell]::Create(); $boot.Runspace = $rs
[void]$boot.AddScript('param($F, $St, $Sh) Invoke-Expression $F; $DryRun = $false; $Auto = $false; Invoke-Expression $St; $script:FR = Get-FrenchStrings; Import-Settings; Enable-GuiAdapters $Sh; ''ready''')
[void]$boot.AddArgument($funcText.ToString()); [void]$boot.AddArgument($stateText); [void]$boot.AddArgument($shared)
$bootOut = @($boot.Invoke())
Check ($bootOut -contains 'ready' -and $boot.Streams.Error.Count -eq 0) "it starts with YSO's functions and settings $(if ($boot.Streams.Error.Count) { $boot.Streams.Error[0] })"
$boot.Dispose()
Check ((Get-Command Write-Host).CommandType -eq 'Cmdlet' -and (Get-Command Read-Host).CommandType -eq 'Cmdlet') 'the console versions are untouched outside it'

$script:GuiWorker = $rs
$script:GuiShared = $shared
$script:GuiJobs = New-Object System.Collections.Queue
$script:GuiCurrent = $null
$script:Ui = $null
function Invoke-WorkerJob {
    # Runs one job like the window does; answers its questions from $Answers; can press Stop after $StopAfterMs.
    param([string]$Script, [object[]]$Arguments = @(), [object[]]$Answers = @(), [int]$StopAfterMs = -1, [int]$TimeoutMs = 20000)
    $r = @{ Out = @(); Err = ''; First = ''; Messages = New-Object System.Collections.Generic.List[object]; Progress = New-Object System.Collections.Generic.List[object] }
    Add-GuiJob -Name 'test' -Output -Title 'test' -Script $Script -Arguments $Arguments -OnDone { param($Out, $Err, $First) $r.Out = $Out; $r.Err = $Err; $r.First = $First }
    Start-NextGuiJob 6>$null
    $queue = New-Object System.Collections.Queue; foreach ($a in $Answers) { $queue.Enqueue($a) }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($script:GuiCurrent) {
        foreach ($m in (Read-GuiMessages $shared)) {
            $r.Messages.Add($m)
            if ($m[0] -eq 'ask' -and $queue.Count -gt 0) { $shared.Answers.Add($queue.Dequeue()) }
        }
        foreach ($k in @($shared.Progress.Keys)) { $r.Progress.Add(@($k) + @($shared.Progress[$k])) }
        if ($StopAfterMs -ge 0 -and $clock.ElapsedMilliseconds -ge $StopAfterMs) { $shared.Stop = $true }
        if ($script:GuiCurrent.Handle.IsCompleted -and $shared.Queue.IsEmpty) { Complete-GuiJob 6>$null }
        elseif ($clock.ElapsedMilliseconds -gt $TimeoutMs) { $r.Err = 'TIMEOUT'; [void]$script:GuiCurrent.PS.BeginStop($null, $null); $script:GuiCurrent = $null }
        else { Start-Sleep -Milliseconds 20 }
    }
    return $r
}

$r = Invoke-WorkerJob 'Write-Host ''plain''; Write-Host ''[+] done'' -ForegroundColor Green; Write-Host ''a'' -NoNewline; Write-Host ''b''; Write-Ok ''Restore point created.''; Clear-Host'
$t = @($r.Messages | Where-Object { $_[0] -eq 'text' })
Check ($t.Count -eq 4 -and $t[0][1] -eq 'plain' -and $t[1][2] -eq 'Green' -and $t[2][3] -eq $true -and $t[3][3] -eq $false) 'what YSO writes reaches the window, with its colour and line breaks'
Check (@($r.Messages | Where-Object { $_[0] -eq 'clear' }).Count -eq 1) 'clearing the screen clears the panel'
$ok = @($r.Messages | Where-Object { $_[0] -eq 'line' })
Check ($ok.Count -eq 1 -and $ok[0][1] -eq 'ok' -and $ok[0][2] -eq 'Restore point created.') "YSO's own helpers become parts of a document (Write-Ok: a line marked ok)"
$r = Invoke-WorkerJob 'Write-Section ''SETTINGS''; Write-Kv ''Language'' ''English''; Write-Option ''1'' ''Language / Langue''; Write-Warn ''Careful''; Show-HealthDashboard @((New-HealthItem ''Battery'' ''Bad'' ''59 %'' ''19''))'
$k = @($r.Messages | ForEach-Object { $_[0] }) -join ','
Check ($k -eq 'section,kv,option,line,health') "headings, values, choices, warnings and health lines arrive as such ($k)"
$opt = @($r.Messages | Where-Object { $_[0] -eq 'option' })[0]
Check ($opt[1] -eq '1' -and $opt[2] -eq 'Language / Langue') 'a choice keeps its key, so clicking it answers the question'

$r = Invoke-WorkerJob '[pscustomobject]@{ A = (Confirm-Action ''Create a restore point first? (recommended)'' $true); B = (Read-Host ''  Choose''); C = (Confirm-Action ''Turn it off?'' $false) }' -Answers @($false, '12', $true)
$asks = @($r.Messages | Where-Object { $_[0] -eq 'ask' })
Check ($asks.Count -eq 3 -and $asks[0][1] -eq 'yesno' -and $asks[0][3] -eq $true -and $asks[1][1] -eq 'text' -and $asks[1][2] -eq 'Choose' -and $asks[2][3] -eq $false) 'questions reach the window: Yes / No with the answer Enter gives, and text'
Check ($r.Out[-1].A -eq $false -and $r.Out[-1].B -eq '12' -and $r.Out[-1].C -eq $true) 'and the answers come back to YSO'

$r = Invoke-WorkerJob '$script:Lang = ''fr''; Confirm-Action ''Turn it off?'' $false; $script:Lang = ''en''' -Answers @($false)
Check ((@($r.Messages | Where-Object { $_[0] -eq 'ask' })[0][2]) -eq 'Le désactiver ?') 'in French when French is chosen'

$r = Invoke-WorkerJob 'Wait-Key; ''after''' -Answers @('')
Check ((@($r.Messages | Where-Object { $_[0] -eq 'ask' })[0][1]) -eq 'continue' -and $r.Out[-1] -eq 'after') 'Press Enter becomes a Continue button'

$dir = "$Sandbox/many"
New-Item -ItemType Directory -Force $dir | Out-Null
1..200 | ForEach-Object { [IO.File]::WriteAllBytes("$dir/f$_.tmp", (New-Object byte[] 10)) }
$r = Invoke-WorkerJob 'param($D) $steps = @(, @(''t1'', ''Temporary files'', { [void](Invoke-Purge -Category ''Temporary files'' -Targets @(@{ Path = (Esc $D) }) -Quiet); Start-Sleep -Milliseconds 300 })); Invoke-Plan -Activity ''Full maintenance'' -Steps $steps; ''done''' -Arguments @($dir)
$p0 = @($r.Progress | Where-Object { $_[0] -eq 0 }); $p1 = @($r.Progress | Where-Object { $_[0] -eq 1 })
Check ($p0.Count -gt 0 -and $p0[0][2] -match 'step 1 of 1: Temporary files') "the steps of F reach the window's progress bar ($($p0.Count) looks)"
Check ($r.Out[-1] -eq 'done' -and @(Get-ChildItem $dir).Count -eq 0 -and $shared.Progress.Count -eq 0) 'the job finishes and its progress bars go away'

Write-Host "`n===== STOP =====" -ForegroundColor White
$r = Invoke-WorkerJob 'Invoke-MenuOption ''R''; $script:LastRun' -StopAfterMs 400
Check ($r.Out[-1].Status -eq 'stopped' -and $r.Err -ne 'TIMEOUT') 'Stop while YSO waits for an answer: the option ends'
Check (@($r.Messages | Where-Object { ($_ -join ' ') -match 'Stopped at your request' }).Count -eq 1) 'and says so'
$errorsBefore = $(if (Test-Path $script:ErrorLogPath) { @(Get-Content $script:ErrorLogPath | Where-Object { $_ -like '==== *' }).Count } else { 0 })
$job = @'
function Clear-TempFiles { for ($i = 0; $i -lt 400; $i++) { Write-YsoProgress -Activity 'Temporary files' -Percent ($i / 4); Start-Sleep -Milliseconds 25 } }
function Clear-SystemJunk { $script:JunkRan = $true }
$script:JunkRan = $false
Invoke-MenuOption 'F' -Plan @{ Temp = $true; Browsers = $false; SystemJunk = $true; DevApps = $false; UpdateCache = $false; Dns = $false }
[pscustomobject]@{ Run = $script:LastRun; JunkRan = $script:JunkRan }
'@
$r = Invoke-WorkerJob $job -StopAfterMs 600
$errorsAfter = $(if (Test-Path $script:ErrorLogPath) { @(Get-Content $script:ErrorLogPath | Where-Object { $_ -like '==== *' }).Count } else { 0 })
Check ($r.Out[-1].Run.Status -eq 'stopped' -and $r.Out[-1].JunkRan -eq $false) 'Stop in the middle of F: the next steps do not run'
Check ($errorsAfter -eq $errorsBefore) 'Stop is not an error: nothing in errors.log'
$shared.Stop = $false
$r = Invoke-WorkerJob 'function Clear-TempFiles { throw ''disk on fire'' }; Invoke-MenuOption ''1''; $script:LastRun'
Check ($r.Out[-1].Status -eq 'failed' -and @($r.Messages | Where-Object { ($_ -join ' ') -match 'disk on fire' }).Count -ge 1) 'an option that fails says so in the window, and the window goes on'
$r = Invoke-WorkerJob 'function Clear-TempFiles { Add-Result -Category ''Temporary files'' -Files 3 -Bytes 3MB -Skipped 0 }; function Get-FreeBytes { 10GB }; Invoke-MenuOption ''1''; $script:LastRun'
Check ($r.Out[-1].Status -eq 'done' -and @($r.Out[-1].Results).Count -eq 1 -and $r.Out[-1].Results[0].Bytes -eq 3MB) 'what an option freed comes back to the window (for its result card)'
Check (@($r.Messages | Where-Object { $_[0] -eq 'section' -and $_[1] -eq 'SUMMARY' }).Count -eq 1) 'with the same summary as the console'
$rs.Dispose()

Write-Host "`n===== INSTALL.PS1 =====" -ForegroundColor White
$installer = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $ScriptPath).Path) 'install.ps1'
$inst = Get-Content -LiteralPath $installer -Raw
$errs = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($inst, [ref]$null, [ref]$errs)
Check ($inst -and @($errs).Count -eq 0 -and $inst -notmatch '[^\x00-\x7F]') 'install.ps1 parses and is plain ASCII (it is read straight from the web)'
$guard = [regex]::Match($inst, "-notmatch '(function Install-Yso[^']*)'").Groups[1].Value
Check ($guard -and $src -match $guard -and "function Install-YsoCopy([string]`$Source = `$PSCommandPath) {" -notmatch $guard) 'it installs this YSO, and refuses an older one (4.0 only has Install-YsoCopy)'
Check ($src -match '\[switch\]\$Install\b' -and $src -match '\[switch\]\$Uninstall\b') 'YSO.ps1 accepts -Install and -Uninstall'

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' }))
