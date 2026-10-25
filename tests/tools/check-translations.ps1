param([string]$ScriptPath, [string]$KeysFile)
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
$fn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in 'Get-FrenchStrings','L' }, $false)
foreach ($f in $fn) { Invoke-Expression $f.Extent.Text }
$fr = Get-FrenchStrings
$fnText = ($fn | Where-Object { $_.Name -eq 'Get-FrenchStrings' }).Extent.Text
$dups = @(($fnText -split "`r?`n") | Where-Object { $_ -match ' ==> ' } | ForEach-Object { $_.Substring(0, $_.IndexOf(' ==> ')) } | Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$keys = Get-Content $KeysFile -Encoding utf8 | Where-Object { $_ }
$missing = @($keys | Where-Object { -not $fr.ContainsKey($_) })
$unused  = @($fr.Keys | Where-Object { $keys -cnotcontains $_ })
$rx = '\{\d+(?:,-?\d+)?(?::[^}]+)?\}'
$bad = @($fr.Keys | Where-Object { (([regex]::Matches($_, $rx) | ForEach-Object Value | Sort-Object) -join '|') -ne (([regex]::Matches($fr[$_], $rx) | ForEach-Object Value | Sort-Object) -join '|') })
"translations loaded from script: $($fr.Count) | strings in code: $($keys.Count)"
"missing: $($missing -join ' ; ')"
"unused: $($unused -join ' ; ')"
"placeholder mismatches: $($bad.Count)"
"duplicated: $($dups -join ' ; ')"
