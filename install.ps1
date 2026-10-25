# YSO - Your System Optimizer: installer
#
#   irm https://raw.githubusercontent.com/b-draoui/yso/main/install.ps1 | iex
#
# Paste that line into PowerShell or Terminal (right-click the Start button > Terminal).
# It downloads the latest release of YSO from GitHub, checks it against its SHA-256 file, then
# installs it like any program: Program Files, Start menu, Desktop, and Settings > Apps >
# Installed apps (to uninstall it). Files downloaded by PowerShell are not marked "downloaded
# from the Internet", so Windows does not show "Windows protected your PC".
#
# ASCII only on purpose (it is read straight from the web): French accents are HTML entities.
& {
    $ErrorActionPreference = 'Stop'
    $repo = 'b-draoui/yso'
    # YSO_REF = a branch, tag or commit to install instead of the latest release (for testing).
    $ref = "$env:YSO_REF"
    $fr = $false
    try { $fr = ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr') } catch { }
    function Say([string]$En, [string]$Fr, [string]$Color = 'Gray') {
        $t = $(if ($fr) { [System.Net.WebUtility]::HtmlDecode($Fr) } else { $En })
        Write-Host "  $t" -ForegroundColor $Color
    }
    function Get-Bytes([string]$Url) {
        if ($Url -notmatch '^https://(api\.github\.com|github\.com|raw\.githubusercontent\.com|objects\.githubusercontent\.com|release-assets\.githubusercontent\.com)/') { throw "Refused address: $Url" }
        $wc = New-Object System.Net.WebClient
        $wc.Headers['User-Agent'] = 'YSO-installer'
        try { return , $wc.DownloadData($Url) } finally { $wc.Dispose() }
    }
    function Get-Json([string]$Url) {
        return ([System.Text.Encoding]::UTF8.GetString((Get-Bytes $Url)) | ConvertFrom-Json)
    }

    Write-Host ''
    Write-Host '  YSO - Your System Optimizer' -ForegroundColor Green
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { Say 'YSO is made for Windows.' 'YSO est fait pour Windows.' 'Red'; return }
    $winps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $winps)) {
        Say 'Windows PowerShell 5.1 was not found on this PC, so YSO cannot run here.' 'Windows PowerShell 5.1 est introuvable sur ce PC : YSO ne peut pas y fonctionner.' 'Red'
        return
    }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('yso-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir 'YSO.ps1'
    try {
        Say 'Downloading YSO...' 'T&eacute;l&eacute;chargement de YSO...'
        $bytes = $null
        $checked = $false
        if (-not $ref) {
            # The latest release, and the SHA-256 published with it.
            try {
                $rel = Get-Json "https://api.github.com/repos/$repo/releases/latest"
                $prefix = "https://github.com/$repo/releases/download/"
                $a = @($rel.assets | Where-Object { $_.name -eq 'YSO.ps1' -and "$($_.browser_download_url)".StartsWith($prefix) }) | Select-Object -First 1
                $s = @($rel.assets | Where-Object { $_.name -eq 'YSO.ps1.sha256' -and "$($_.browser_download_url)".StartsWith($prefix) }) | Select-Object -First 1
                if ($a -and $s) {
                    $bytes = Get-Bytes $a.browser_download_url
                    $expected = [regex]::Match([System.Text.Encoding]::ASCII.GetString((Get-Bytes $s.browser_download_url)), '\b[0-9a-fA-F]{64}\b').Value.ToLowerInvariant()
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
                    $sha.Dispose()
                    if ($expected -ne $actual) {
                        Say 'The download does not match its SHA-256 checksum: nothing was installed. Try again later.' 'Le t&eacute;l&eacute;chargement ne correspond pas &agrave; sa somme SHA-256 : rien n''a &eacute;t&eacute; install&eacute;. R&eacute;essayez plus tard.' 'Red'
                        return
                    }
                    $checked = $true
                }
            } catch { $bytes = $null }
            if (-not $bytes) { $ref = 'main' }   # no release yet: the main branch
        }
        if (-not $bytes) {
            # A branch, tag or commit. GitHub keeps branch files in a cache for 5 minutes, so the exact
            # commit is asked first (if GitHub does not answer: the branch itself).
            $commit = $ref
            if ($ref -notmatch '^[0-9a-f]{40}$') {
                try {
                    $info = Get-Json "https://api.github.com/repos/$repo/commits/$ref"
                    if ("$($info.sha)" -match '^[0-9a-f]{40}$') { $commit = "$($info.sha)" }
                } catch { }
            }
            $bytes = Get-Bytes "https://raw.githubusercontent.com/$repo/$commit/YSO.ps1"
        }
        [IO.File]::WriteAllBytes($file, $bytes)

        # A cut or wrong download must never be installed.
        $text = [IO.File]::ReadAllText($file)
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errors)
        if (@($errors).Count -gt 0 -or $text -notmatch 'function Install-Yso\s*\{') {
            Say 'The download is incomplete or too old to be installed this way. Try again in a few minutes.' `
                'Le t&eacute;l&eacute;chargement est incomplet ou trop ancien pour s''installer ainsi. R&eacute;essayez dans quelques minutes.' 'Red'
            return
        }
        $version = [regex]::Match($text, "\`$script:Version\s*=\s*'([\d\.]+)'").Groups[1].Value
        $how = $(if ($checked) { ' (SHA-256 OK)' } else { '' })

        Say "YSO $version downloaded$how. Windows now asks for administrator rights..." "YSO $version t&eacute;l&eacute;charg&eacute;$how. Windows demande maintenant les droits administrateur..."
        $p = Start-Process -FilePath $winps -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$file`"", '-Install' -Verb RunAs -PassThru
        $p.WaitForExit()
        if ($p.ExitCode -eq 0) {
            Say 'Done: YSO opens now, and it is in the Start menu and on the Desktop.' 'Termin&eacute; : YSO s''ouvre, et il est dans le menu D&eacute;marrer et sur le Bureau.' 'Green'
        } else {
            Say "The installation did not finish (code $($p.ExitCode)). Details: C:\ProgramData\YSO\errors.log" "L'installation ne s'est pas termin&eacute;e (code $($p.ExitCode)). D&eacute;tails : C:\ProgramData\YSO\errors.log" 'Yellow'
        }
    } catch {
        if ($_.Exception.Message -match 'cancel|annul') {
            Say 'Administrator rights were declined: nothing was installed.' 'Droits administrateur refus&eacute;s : rien n''a &eacute;t&eacute; install&eacute;.' 'Yellow'
        } else {
            Say ('The installation failed: ' + $_.Exception.Message) ("L'installation a &eacute;chou&eacute; : " + [System.Net.WebUtility]::HtmlEncode($_.Exception.Message)) 'Red'
        }
    } finally {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ''
}
