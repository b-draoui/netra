# Looks for things that must never be in a public repository: access tokens, private keys, passwords
# written in files. Prints one line per finding, then "Secrets found: N".
param([string]$Root)
$patterns = [ordered]@{
    'GitHub token'        = '\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{40,}\b'
    'AWS access key'      = '\bAKIA[0-9A-Z]{16}\b'
    'Google API key'      = '\bAIza[0-9A-Za-z\-_]{35}\b'
    'Slack token'         = '\bxox[abprs]-[0-9A-Za-z-]{10,}\b'
    'Private key'         = '-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY'
    'Azure storage key'   = '\bAccountKey=[A-Za-z0-9+/=]{40,}'
    'Password in a file'  = '(?i)\b(password|passwd|pwd)\s*[:=]\s*[''"][^''"\s]{6,}[''"]'
}
$found = 0
$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Length -lt 5MB -and $_.Extension -notin '.png', '.ico', '.jpg' }
foreach ($f in $files) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    foreach ($k in $patterns.Keys) {
        foreach ($m in [regex]::Matches($text, $patterns[$k])) {
            # this file describes the patterns themselves
            if ($f.Name -eq 'check-secrets.ps1') { continue }
            $line = ($text.Substring(0, $m.Index) -split "`n").Count
            "$k in $($f.FullName.Substring($Root.Length).TrimStart('\', '/')) line $line"
            $found++
        }
    }
}
"Secrets found: $found"
