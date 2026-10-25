param([string]$ScriptPath, [string]$Sandbox)
$script:fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "ok   $what" } else { Write-Host "FAIL $what" -ForegroundColor Red; $script:fail++ }
}
if (Test-Path $Sandbox) { Remove-Item $Sandbox -Recurse -Force }
New-Item -ItemType Directory -Force "$Sandbox/tmp" | Out-Null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state')); $stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$env:ProgramData = "$Sandbox/ProgramData"; $env:TEMP = "$Sandbox/tmp"; $DryRun = $false; $Auto = $false
Invoke-Expression $stateText
$script:FR = Get-FrenchStrings

Write-Host "`n===== FRENCH UNITS AND HEADINGS =====" -ForegroundColor White
$script:Lang = 'fr'
Check ((Format-Size 1.5MB) -match '^1[,.]5 Mo$') "1.5 MB in French: $(Format-Size 1.5MB)"
Check ((Format-Size (11.43 * 1GB)) -match '^11[,.]43 Go$') "11.43 GB in French: $(Format-Size (11.43 * 1GB))"
Check ((Format-Size 74KB) -eq '74 Ko' -and (Format-Size 12) -eq '12 o') 'Ko and o'
$script:Results.Clear(); Add-Result -Category 'Temporary files' -Files 1 -Bytes 100 -Skipped 0
$script:DryRun = $true
$out = (Show-Summary 6>&1 | Out-String)
$script:DryRun = $false
Check ($out -match "ANALYSE - espace récupérable") 'the Analyze summary heading is now French'
Check ($out -notmatch 'space you can reclaim') 'no English left in it'
$script:Lang = 'en'
Check ((Format-Size 1.5MB) -match '^1[,.]5 MB$') "English units unchanged: $(Format-Size 1.5MB)"

Write-Host "`n===== BATTERY HEALTH FALLBACK (Windows battery report) =====" -ForegroundColor White
function Get-CimInstance { throw 'WMI battery classes not available on this laptop' }
$script:BatteryXml = @'
<?xml version="1.0" encoding="utf-8"?>
<BatteryReport xmlns="http://schemas.microsoft.com/battery/2012">
  <Batteries>
    <Battery>
      <Id>Primary</Id>
      <Manufacturer>SMP</Manufacturer>
      <Chemistry>LION</Chemistry>
      <DesignCapacity>56000</DesignCapacity>
      <FullChargeCapacity>48720</FullChargeCapacity>
      <CycleCount>312</CycleCount>
    </Battery>
  </Batteries>
</BatteryReport>
'@
function powercfg.exe { $i = [array]::IndexOf($args, '/output'); Set-Content -LiteralPath $args[$i + 1] -Value $script:BatteryXml -Encoding UTF8 }
$bh = Get-BatteryHealth
Check ($null -ne $bh -and $bh.Percent -eq 87) "health read from the battery report: $($bh.Percent) % (48720 / 56000)"
Check ($bh.Cycles -eq 312) "charge cycles: $($bh.Cycles)"
Check (@(Get-ChildItem "$Sandbox/tmp" -Filter 'yso-battery_*').Count -eq 0) 'the temporary report file is deleted'
$script:BatteryXml = $script:BatteryXml.Replace('</Battery>', "</Battery><Battery><DesignCapacity>20000</DesignCapacity><FullChargeCapacity>18000</FullChargeCapacity><CycleCount>40</CycleCount></Battery>")
$bh = Get-BatteryHealth
Check ($bh.Percent -eq 88) "two batteries are added together: $($bh.Percent) % (66720 / 76000)"
$script:BatteryXml = '<?xml version="1.0"?><BatteryReport xmlns="http://schemas.microsoft.com/battery/2012"><Batteries><Battery><DesignCapacity></DesignCapacity><FullChargeCapacity>0</FullChargeCapacity></Battery></Batteries></BatteryReport>'
Check ($null -eq (Get-BatteryHealth)) 'a battery that reports nothing gives "not reported", not a wrong number'
function powercfg.exe { }
Check ($null -eq (Get-BatteryHealth)) 'no report at all also gives "not reported"'
$savedXml = $script:BatteryXml
$script:BatteryXml = '<?xml version="1.0"?><BatteryReport xmlns="http://schemas.microsoft.com/battery/2012"><Batteries><Battery><DesignCapacity>70000</DesignCapacity><FullChargeCapacity>41300</FullChargeCapacity><CycleCount>0</CycleCount></Battery></Batteries></BatteryReport>'
function powercfg.exe { $i = [array]::IndexOf($args, '/output'); Set-Content -LiteralPath $args[$i + 1] -Value $script:BatteryXml -Encoding UTF8 }
$bh = Get-BatteryHealth
Check ($bh.Percent -eq 59 -and $null -eq $bh.Cycles) "your battery: health $($bh.Percent) %, a cycle count of 0 is treated as not reported"
$script:BatteryXml = $savedXml; function powercfg.exe { }
function Test-IsLaptop { $true }
$script:BatteryXml = $script:BatteryXml -replace '<DesignCapacity></DesignCapacity><FullChargeCapacity>0', '<DesignCapacity>50000</DesignCapacity><FullChargeCapacity>40000'
function powercfg.exe { $i = [array]::IndexOf($args, '/output'); Set-Content -LiteralPath $args[$i + 1] -Value $script:BatteryXml -Encoding UTF8 }
$script:Checks.Clear(); $script:Lang = 'fr'
Test-Check 'Diagnose' 'Battery data (19)' {
    if (-not (Test-IsLaptop)) { return (Result-Info (L 'no battery')) }
    $bh = Get-BatteryHealth
    if ($bh) { $text = L 'health {0} %' $bh.Percent; if ($null -ne $bh.Cycles) { $text += ', ' + (L '{0} charge cycles' $bh.Cycles) }; return (Result-Ok $text) }
    Result-Info (L 'the battery does not report its health')
} 6>$null
$script:Lang = 'en'
Check ($script:Checks[0].Status -eq 'OK' -and $script:Checks[0].Detail -eq 'santé 80 %') "self-test battery line: $($script:Checks[0].Status) $($script:Checks[0].Detail)"
Remove-Item function:Get-CimInstance, function:powercfg.exe

Write-Host "`n===== WARM-UP PING IS NOT COUNTED =====" -ForegroundColor White
$r = Measure-Ping '127.0.0.1' 3
Check ($null -ne $r -and $r.Loss -ge 0 -and $r.Loss -le 100) "Measure-Ping still works (avg $($r.Avg) ms, loss $($r.Loss) %)"
$body = ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Measure-Ping' }, $false)[0]).Extent.Text
Check ($body.IndexOf('[void]$ping.Send($Target, 1500)') -lt $body.IndexOf('for ($i = 0')) 'the warm-up ping happens before the counted ones'

Write-Host ("`nRESULT: {0}" -f $(if ($script:fail) { "$($script:fail) FAILURE(S)" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
