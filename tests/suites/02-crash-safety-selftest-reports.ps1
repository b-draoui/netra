param([string]$ScriptPath, [string]$Sandbox, [string]$Pwsh, [string]$Child)
$ErrorActionPreference = 'Stop'
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force $Sandbox | Out-Null
$log = "$Sandbox/ProgramData/YSO/errors.log"

function Run-Child([string]$Mode) {
    $out = & $Pwsh -NoProfile -File $Child -ScriptPath $ScriptPath -Sandbox $Sandbox -Mode $Mode 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out -replace '\x1b\[[0-9;]*m', '') }
}

Write-Host "`n===== A CRASHING OPTION DOES NOT CLOSE YSO =====" -ForegroundColor White
$r = Run-Child 'option-crash'
Check ($r.Code -eq 0) "YSO kept running and quit normally (exit code $($r.Code))"
Check ($r.Out -match 'Something went wrong in this option') 'the user is told what happened'
Check ($r.Out -match 'boom from option 1') 'the error message is shown'
Check ($r.Out -notmatch 'NOT REACHED') 'YSO ended through its own exit'
$text = Get-Content -LiteralPath $log -Raw
Check ($text -match '\| option 1 \|' -and $text -match 'boom from option 1') 'errors.log records the option and the error'
Check ($text -match 'Clear-TempFiles') 'errors.log includes where it happened (stack trace)'

Write-Host "`n===== A CRASH OUTSIDE AN OPTION IS EXPLAINED =====" -ForegroundColor White
$r = Run-Child 'outside-crash'
Check ($r.Code -eq 1) "exit code 1, so the launcher shows its message too (got $($r.Code))"
Check ($r.Out -match 'YSO stopped because of an unexpected error') 'the user is told what happened'
Check ((Get-Content -LiteralPath $log -Raw) -match 'outside an option') 'errors.log records it'

Write-Host "`n===== WEEKLY AUTO-CLEAN SURVIVES A FAILING STEP =====" -ForegroundColor White
$t = "$Sandbox/Users/Alex/AppData/Local/Temp"; New-Item -ItemType Directory -Force $t | Out-Null
[IO.File]::WriteAllBytes("$t/old-for-auto.tmp", (New-Object byte[] 5000)); (Get-Item "$t/old-for-auto.tmp").LastWriteTime = (Get-Date).AddDays(-3)
$r = Run-Child 'auto'
Check ($r.Code -eq 1) "exit code 1, so Task Scheduler shows the run had a problem (got $($r.Code))"
Check ($r.Out -match 'This step failed and was skipped: boom from browser caches') 'the failing step is reported'
Check ($r.Out -match 'System junk: \d+ files removed') 'the steps after it still ran'
Check ((Get-Content -LiteralPath $log -Raw) -match 'auto: browser caches') 'errors.log records the step'
Check (Test-Path "$Sandbox/ProgramData/YSO/history.csv") 'history was still saved'

Write-Host "`n===== SELF-TEST (-SelfTest switch) =====" -ForegroundColor White
$r = Run-Child 'selftest'
$report = Get-ChildItem "$Sandbox/ProgramData/YSO/Reports" -Filter 'selftest_*.txt' | Sort-Object LastWriteTime | Select-Object -Last 1
Check ($null -ne $report) 'a report file was written'
$rep = Get-Content -LiteralPath $report.FullName
$rows = @($rep | Where-Object { $_ -match '^(OK|INFO|MISSING|BROKEN) ' })
$broken = @($rows | Where-Object { $_ -match '^BROKEN ' }).Count
Check ($rows.Count -ge 35) "the report lists every check ($($rows.Count) rows)"
Check ($r.Code -eq $broken) "exit code = number of broken checks ($($r.Code) = $broken)"
Check (@($rep | Where-Object { $_ -match '^Result     : ' }).Count -eq 1) 'the report has a summary line'
Check (@($rep | Where-Object { $_ -match '^OK .*Removes old files, keeps recent ones' }).Count -eq 1) 'the deletion engine test passed on this disk'
Check ($rep -contains 'ANALYZE (nothing deleted)') 'the report includes the Analyze results'
Check (@(Get-ChildItem "$Sandbox/tmp" -Filter 'YsoSelfTest_*' -ErrorAction SilentlyContinue).Count -eq 0) 'the test folder was removed afterwards'
Write-Host "`n----- report from this Linux test machine -----" -ForegroundColor DarkGray
$rep | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
Write-Host "----- (BROKEN/MISSING rows here are Windows-only features that cannot exist on Linux) -----`n" -ForegroundColor DarkGray

# ---------------- in-process tests: load functions and state like the child does
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errs)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:WINDIR = "$Sandbox/Windows"; $env:TEMP = "$Sandbox/tmp"
$env:USERPROFILE = "$Sandbox/Users/Alex"; $env:USERNAME = 'Alex'; $env:COMPUTERNAME = 'DESKTOP-AB12CD'
$DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings
Import-Settings
$script:Profiles = @("$Sandbox/Users/Alex", "$Sandbox/Users/Sam")
$ErrorActionPreference = 'Continue'

Write-Host "`n===== PRIVACY: WHAT IS REMOVED FROM A REPORT =====" -ForegroundColor White
$sample = @"
Username: DESKTOP-AB12CD\Alex
Host Application: powershell.exe -File $Sandbox/Users/Alex/Downloads/YSO.ps1
Other user: $Sandbox/Users/Sam/AppData/Local/Temp
  IP address                    192.168.1.23
  Router (gateway)              192.168.1.1
  DNS servers                   1.1.1.1, 10.0.0.53, 100.64.1.2, 172.20.3.4
  Wi-Fi network                 MyHomeWiFi-5G
  Réseau Wi-Fi                  Maison Alex
Windows 11 Pro 23H2 (build 10.0.22631.4391), PowerShell 5.1.22621.4391
Alexandria stays, ALEX-PC stays only partly
Last line ends with an address 10.1.2.3.
"@
$clean = Protect-Text $sample
$clean -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
Check ($clean -notmatch 'Alex\b' -and $clean -notmatch 'Sam') 'user names removed (both profiles)'
Check ($clean -notmatch 'DESKTOP-AB12CD') 'PC name removed'
Check ($clean -notmatch '192\.168|10\.0\.0\.53|100\.64\.1\.2|172\.20\.3\.4|10\.1\.2\.3') 'private IP addresses removed (also at the end of a sentence)'
Check ($clean -match '1\.1\.1\.1') 'public DNS address kept (useful for diagnosis)'
Check ($clean -match '10\.0\.22631\.4391' -and $clean -match '5\.1\.22621\.4391') 'version numbers kept'
Check ($clean -notmatch 'MyHomeWiFi|Maison') 'Wi-Fi name removed (English and French lines)'
Check ($clean -match 'Alexandria') 'words that merely contain the name are kept'

Write-Host "`n===== QUIET ENGINE CALL =====" -ForegroundColor White
$q = "$Sandbox/quiet"; New-Item -ItemType Directory -Force $q | Out-Null
[IO.File]::WriteAllBytes("$q/a.tmp", (New-Object byte[] 1000)); (Get-Item "$q/a.tmp").LastWriteTime = (Get-Date).AddDays(-5)
$script:Results.Clear()
$o = Invoke-Purge -Category 'Self-test' -Targets @(@{ Path = (Esc $q); Days = 1 }) -Quiet 6>&1
$obj = @($o | Where-Object { $_ -is [pscustomobject] })[0]
Check ($obj.Files -eq 1 -and $obj.Bytes -eq 1000) 'returns what it removed'
Check ($script:Results.Count -eq 0) 'does not add a line to the summary'
Check (@($o | Where-Object { $_ -isnot [pscustomobject] }).Count -eq 0) 'prints nothing'

Write-Host "`n===== ERROR LOG ROTATION =====" -ForegroundColor White
[IO.File]::WriteAllBytes($script:ErrorLogPath, (New-Object byte[] (1MB + 10)))
try { throw 'rotation test' } catch { Write-YsoError -Context 'test' -ErrorRecord $_ }
Check (Test-Path ($script:ErrorLogPath -replace '\.log$', '.old.log')) 'a log over 1 MB is moved to errors.old.log'
Check ((Get-Item $script:ErrorLogPath).Length -lt 10KB) 'a fresh errors.log is started'

Write-Host "`n===== REPORT A PROBLEM (P) =====" -ForegroundColor White
$fake = Join-Path $script:LogDir 'yso_29990101_000000.log'
Set-Content -LiteralPath $fake -Value $sample -Encoding UTF8
(Get-Item $fake).LastWriteTime = (Get-Date).AddMinutes(5)
$script:Answers = New-Object System.Collections.Queue; $script:Answers.Enqueue('the cleaner froze on option 22')
function Read-Host { param($Prompt) if ($script:Answers.Count -gt 0) { return $script:Answers.Dequeue() } return '' }
function Confirm-Action { param($Question, $Default) return $false }
$before = @(Get-ChildItem $env:TEMP -Filter 'YSO-report_*' -ErrorAction SilentlyContinue).Count
New-ProblemReport
$zip = @(Get-ChildItem -Path $script:ReportDir, ([Environment]::GetFolderPath('Desktop')) -Filter 'YSO-report_*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)[-1]
Check ($null -ne $zip) "zip created ($($zip.FullName))"
$out = "$Sandbox/unzipped"; Expand-Archive -LiteralPath $zip.FullName -DestinationPath $out -Force
$names = @(Get-ChildItem $out | ForEach-Object Name)
Write-Host ('      contents: ' + ($names -join ', ')) -ForegroundColor DarkGray
Check ($names -contains 'README.txt' -and $names -contains 'errors.log' -and @($names | Where-Object { $_ -like 'selftest_*' }).Count -eq 1) 'contains the README, errors.log and the self-test report'
Check (@($names | Where-Object { $_ -like 'yso_*.log' }).Count -ge 1) 'contains the session logs'
Check ((Get-Content "$out/README.txt" -Raw) -match 'the cleaner froze on option 22') 'the description is in the README'
$all = (Get-ChildItem $out -File | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
Check ($all -notmatch 'Alex\b' -and $all -notmatch 'DESKTOP-AB12CD' -and $all -notmatch '192\.168\.1\.23' -and $all -notmatch 'MyHomeWiFi') 'no personal details in any file of the zip'
Check (@(Get-ChildItem $env:TEMP -Filter 'YSO-report_*' -Directory -ErrorAction SilentlyContinue).Count -eq 0) 'temporary staging folder removed'

Write-Host "`n===== MENU KEYS ARE ALL WIRED =====" -ForegroundColor White
$menuFn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Show-Menu' }, $false)[0]
$menuKeys = @([regex]::Matches($menuFn.Extent.Text, "\(M '([0-9A-Z]+)'") | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne '' })
# Options run through Invoke-MenuOption (the console and the window); M, L and Q are handled by the menu loop.
$optFn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Invoke-MenuOption' }, $false)[0].Extent.Text
$sw = $optFn.Substring($optFn.IndexOf('switch ($Choice)'))
$startText = $src.Substring($src.IndexOf("#  Start`n"))
$caseKeys = @(@([regex]::Matches($sw.Substring(0, $sw.IndexOf('default {')), "(?m)^\s+'([0-9A-Z]+)'\s+\{") | ForEach-Object { $_.Groups[1].Value }) +
              @([regex]::Matches($startText, "if \(\`$choice -eq '([A-Z])'\)") | ForEach-Object { $_.Groups[1].Value }))
$noCase = @($menuKeys | Where-Object { $caseKeys -notcontains $_ })
$noMenu = @($caseKeys | Where-Object { $menuKeys -notcontains $_ })
Check ($noCase.Count -eq 0) "every menu entry has an action ($($menuKeys.Count) entries)$(if ($noCase) { ' missing: ' + ($noCase -join ',') })"
Check ($noMenu.Count -eq 0) "every action is in the menu$(if ($noMenu) { ' hidden: ' + ($noMenu -join ',') })"

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
