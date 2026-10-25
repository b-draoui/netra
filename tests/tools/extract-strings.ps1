param([string]$Path, [string]$OutFile)
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
$firstArg  = @('L','N','Write-Step','Write-Ok','Write-Warn','Write-Bad','Write-Info','Write-Section','Write-Kv','Read-Choice','Confirm-Action','Confirm-Box','Write-PingResult')
$secondArg = @('Write-Option','M','Add-Check','Test-Check')
$keys = [System.Collections.Generic.List[string]]::new()
$dynamic = [System.Collections.Generic.List[string]]::new()
foreach ($c in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    $name = $c.GetCommandName()
    if (-not $name) { continue }
    $pos = @(); $named = @{}
    $els = $c.CommandElements
    for ($i = 1; $i -lt $els.Count; $i++) {
        $e = $els[$i]
        if ($e -is [System.Management.Automation.Language.CommandParameterAst]) {
            if ($e.Argument) { $named[$e.ParameterName] = $e.Argument }
            elseif ($i + 1 -lt $els.Count -and $els[$i+1] -isnot [System.Management.Automation.Language.CommandParameterAst]) { $named[$e.ParameterName] = $els[$i+1]; $i++ }
            continue
        }
        $pos += $e
    }
    $targets = @()
    if ($firstArg -contains $name -and $pos.Count -ge 1) { $targets += $pos[0] }
    if ($secondArg -contains $name -and $pos.Count -ge 2) { $targets += $pos[1] }
    if (@('Invoke-Purge','Add-Result') -contains $name -and $named['Category']) { $targets += $named['Category'] }
    foreach ($t in $targets) {
        if ($t -is [System.Management.Automation.Language.StringConstantExpressionAst]) { if ($t.Value -and $t.Value -ne '#') { $keys.Add($t.Value) } }
        elseif ($t -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { $dynamic.Add("line $($t.Extent.StartLineNumber): $name $($t.Extent.Text)") }
    }
}
# Texts of the window's layout (XAML): [[Text]] is translated when the window is built.
$xaml = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-YsoXaml' }, $false)
foreach ($x in $xaml) { foreach ($m in [regex]::Matches($x.Extent.Text, '\[\[(.+?)\]\]')) { $keys.Add($m.Groups[1].Value) } }
$u = $keys | Sort-Object -Unique -CaseSensitive
$u | Set-Content -Path $OutFile -Encoding utf8
"Unique strings to translate: $($u.Count)"
"Interpolated strings passed to UI helpers (not translatable):"
$dynamic | Sort-Object -Unique
