param([string]$Path)
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { $errors | ForEach-Object { "PARSE ERROR line $($_.Extent.StartLineNumber): $($_.Message)" } } else { "Parse OK: $Path" }
$funcs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name
"Functions defined: $($funcs.Count)"
# every command call that targets one of OUR functions must exist
$calls = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique
$ours = $calls | Where-Object { $_ -match '^(Write-(Step|Ok|Warn|Info|Section|Kv|MenuItem)|Confirm-Action|Wait-Key|Format-Size|Esc|Get-(FreeBytes|UptimeText|ProfilePaths|Tree|RecycleBinBytes)|Test-(PendingReboot|ProtectedPath|Drives)|Add-Result|Show-|Invoke-|Clear-(TempFiles|BrowserCaches|SystemJunk|UpdateCache|YSORecycleBin|ShaderCaches|Dns)|Close-Browsers|Reset-NetworkStack|Optimize-Drives|Set-(YSOPowerPlan|AutoClean)|New-YsoRestorePoint)$' }
$missing = $ours | Where-Object { $_ -notin $funcs }
"Calls to undefined helpers: $(if ($missing) { $missing -join ', ' } else { 'none' })"
# PS7-only syntax that would break Windows PowerShell 5.1
$bad = $tokens | Where-Object { $_.Kind -in 'QuestionQuestion','QuestionQuestionEquals','QuestionDot','QuestionLBracket','AndAnd','OrOr' -or ($_.Kind -eq 'QuestionMark') }
"PS7-only tokens: $(if ($bad) { ($bad | ForEach-Object { "$($_.Kind)@$($_.Extent.StartLineNumber)" }) -join ', ' } else { 'none' })"
