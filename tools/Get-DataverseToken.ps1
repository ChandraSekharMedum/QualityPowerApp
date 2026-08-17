# Get-DataverseToken.ps1
# Extracts a Dataverse access token from the pac CLI MSAL token cache.
# The cache is DPAPI-encrypted under the current user, so this only works
# when run as the same Windows account that ran 'pac auth create'.
#
# Usage:  $tok = & .\Get-DataverseToken.ps1 -ResourceMatch 'crm.dynamics.com'
# ASCII-only per project standard.

param(
    [string]$ResourceMatch = 'crm.dynamics.com',
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'

$cachePath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerAppsCli\tokencache_msalv3.dat'
if (-not (Test-Path $cachePath)) {
    throw "MSAL token cache not found at $cachePath. Run 'pac org who' first."
}

Add-Type -AssemblyName System.Security

$encrypted = [System.IO.File]::ReadAllBytes($cachePath)
try {
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
} catch {
    throw "DPAPI unprotect failed. The cache belongs to a different Windows user. $($_.Exception.Message)"
}

$json = [System.Text.Encoding]::UTF8.GetString($plain)
$cache = $json | ConvertFrom-Json

if (-not $cache.AccessToken) {
    throw "No AccessToken section in the MSAL cache."
}

$epoch = [datetime]'1970-01-01T00:00:00Z'
$now   = (Get-Date).ToUniversalTime()

$entries = foreach ($name in $cache.AccessToken.PSObject.Properties.Name) {
    $e = $cache.AccessToken.$name
    $expUtc = $epoch.AddSeconds([int64]$e.expires_on)
    [pscustomobject]@{
        Target       = $e.target
        ClientId     = $e.client_id
        ExpiresUtc   = $expUtc
        SecondsLeft  = [int]($expUtc - $now).TotalSeconds
        Secret       = $e.secret
    }
}

if ($ListOnly) {
    $entries | Sort-Object SecondsLeft -Descending |
        Select-Object Target, ClientId, ExpiresUtc, SecondsLeft | Format-Table -AutoSize
    return
}

$match = $entries |
    Where-Object { $_.Target -like "*$ResourceMatch*" -and $_.SecondsLeft -gt 60 } |
    Sort-Object SecondsLeft -Descending |
    Select-Object -First 1

if (-not $match) {
    $avail = ($entries | ForEach-Object { "$($_.Target) [$($_.SecondsLeft)s]" }) -join "`n  "
    throw "No live token matching '$ResourceMatch'. Available:`n  $avail"
}

Write-Verbose "Token for $($match.Target), $($match.SecondsLeft)s remaining"
return $match.Secret
