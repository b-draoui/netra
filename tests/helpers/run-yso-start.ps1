param([string]$ScriptPath, [string]$Sandbox, [string]$Mode)
# Loads YSO's functions and settings, replaces Windows-only commands with stubs,
# then runs YSO's real start-up + menu code (the "Start" section) in this process.
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errs)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { Invoke-Expression $fn.Extent.Text }
$src = (Get-Content -LiteralPath $ScriptPath -Raw).Replace("`r`n", "`n")   # works with Windows (CRLF) and Linux (LF) line endings
$stateText = $src.Substring($src.IndexOf('#  Settings & state'))
$stateText = $stateText.Substring(0, $stateText.IndexOf('#  UI helpers'))
$startText = $src.Substring($src.IndexOf("# ==================================================================`n#  Start`n"))

$env:ProgramData = "$Sandbox/ProgramData"; $env:WINDIR = "$Sandbox/Windows"; $env:TEMP = "$Sandbox/tmp"
$env:USERPROFILE = "$Sandbox/Users/Alex"; $env:USERNAME = 'Alex'; $env:COMPUTERNAME = 'DESKTOP-AB12CD'
$env:SystemDrive = "$Sandbox/C"; $env:ProgramFiles = "$Sandbox/ProgramFiles"; New-Item -ItemType Directory -Force "$Sandbox/C" | Out-Null
foreach ($d in @($env:TEMP, "$env:USERPROFILE/AppData/Local/Temp", "$env:WINDIR/Web")) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$DryRun = $false
Invoke-Expression $stateText
$script:Build = 22631; $script:OsMajor = 10

function Get-Volume { }
function Get-ScheduledTask { }
function Test-PendingReboot { $false }
function Clear-Host { }
function Get-ProfilePaths { @($env:USERPROFILE) }
$script:Answers = New-Object System.Collections.Queue
function Read-Host { param($Prompt) if ($script:Answers.Count -gt 0) { return $script:Answers.Dequeue() } return 'Q' }

$Auto = $false; $SelfTest = $false; $AutoUpdate = $false
function Get-WingetPath { 'C:\fake\winget.exe' }
function Get-Service { param($Name, $ErrorAction) [pscustomobject]@{ Status = 'Stopped'; StartType = 'Disabled' } }
function Invoke-Winget([string[]]$Arguments) {
    # a stand-in for winget: one app to update; installing it fails with "no internet" (0x8A150107)
    if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ Code = 0; Lines = @('v1.9.25200') } }
    if ($Arguments -contains '--id') { return [pscustomobject]@{ Code = -1978334969; Lines = @('Installer failed') } }
    $lines = @(('Name'.PadRight(12) + 'Id'.PadRight(12) + 'Version'.PadRight(10) + 'Available'.PadRight(11) + 'Source'), ('-' * 51),
               ('Git'.PadRight(12) + 'Git.Git'.PadRight(12) + '2.43.0'.PadRight(10) + '2.47.1'.PadRight(11) + 'winget'), '1 upgrades available.')
    return [pscustomobject]@{ Code = 0; Lines = $lines }
}
switch ($Mode) {
    'option-crash' {
        function Show-Menu { }
        function Clear-TempFiles { throw 'boom from option 1' }
        $script:Answers.Enqueue('1'); $script:Answers.Enqueue(''); $script:Answers.Enqueue('Q')
    }
    'outside-crash' {
        function Show-Menu { throw 'boom from the menu' }
    }
    'auto' {
        $Auto = $true
        function Clear-BrowserCaches { throw 'boom from browser caches' }
    }
    'selftest' { $SelfTest = $true }
    'autoupdate-check' { $AutoUpdate = $true; $script:DryRun = $true }
    'autoupdate-run' { $AutoUpdate = $true }
    'menu-switch' {
        # a new user: no settings yet -> simple menu; M -> full menu (saved); Q
        function Get-HealthItemsCached { @() }
        $script:Answers.Enqueue('M'); $script:Answers.Enqueue('Q')
    }
}
. ([scriptblock]::Create($startText))
'NOT REACHED'
