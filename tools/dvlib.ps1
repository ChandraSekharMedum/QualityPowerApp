# dvlib.ps1 -- Dataverse Web API helper for Phase 1 probes.
# Dot-source this:  . .\dvlib.ps1
#
# Handles this tenant's Conditional Access behaviour: access tokens are revoked
# within ~15-20 minutes, so every call checks remaining lifetime and silently
# re-mints via 'pac org who' (which refreshes the MSAL cache using the stored
# refresh token) before proceeding. A 401 triggers one forced re-mint and retry.
#
# ASCII-only per project standard.

$script:DvOrgUrl   = 'https://operations-cus-con-sandbox.crm.dynamics.com'
$script:DvApi      = "$script:DvOrgUrl/api/data/v9.2"
$script:DvToken    = $null
$script:DvTokenExp = [datetime]::MinValue
$script:ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-DvCacheEntries {
    $cachePath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerAppsCli\tokencache_msalv3.dat'
    if (-not (Test-Path $cachePath)) { throw "MSAL cache not found: $cachePath" }
    Add-Type -AssemblyName System.Security
    $enc   = [System.IO.File]::ReadAllBytes($cachePath)
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
                $enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    $cache = [System.Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
    $epoch = [datetime]'1970-01-01T00:00:00Z'
    foreach ($n in $cache.AccessToken.PSObject.Properties.Name) {
        $e = $cache.AccessToken.$n
        [pscustomobject]@{
            Target     = $e.target
            ExpiresUtc = $epoch.AddSeconds([int64]$e.expires_on)
            Secret     = $e.secret
        }
    }
}

function Update-DvToken {
    param([switch]$Force)

    $now = (Get-Date).ToUniversalTime()
    if (-not $Force -and $script:DvToken -and ($script:DvTokenExp - $now).TotalSeconds -gt 120) {
        return
    }

    # Refresh the MSAL cache silently. 'pac org who' performs a token refresh
    # using the stored refresh token -- no interactive prompt.
    & pac org who *> $null

    $match = Get-DvCacheEntries |
        Where-Object { $_.Target -like '*operations-cus-con-sandbox.crm.dynamics.com*' } |
        Sort-Object ExpiresUtc -Descending | Select-Object -First 1

    if (-not $match) { throw "No Dataverse token in cache after refresh. Run 'pac auth create' interactively." }

    $script:DvToken    = $match.Secret
    $script:DvTokenExp = $match.ExpiresUtc
    Write-Verbose ("Token refreshed, expires {0}Z ({1}s)" -f $match.ExpiresUtc, [int]($match.ExpiresUtc - $now).TotalSeconds)
}

function Invoke-Dv {
    <#
      .SYNOPSIS Call the Dataverse Web API with automatic token re-mint and 401 retry.
      .EXAMPLE  Invoke-Dv -Path 'WhoAmI'
      .EXAMPLE  Invoke-Dv -Method POST -Path 'mserp_x' -Body $obj -Prefer 'return=representation'
    #>
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [string]$Prefer,
        [hashtable]$ExtraHeaders,
        [switch]$Raw
    )

    Update-DvToken

    $uri = if ($Path -match '^https?://') { $Path } else { "$script:DvApi/$Path" }

    $attempt = 0
    while ($true) {
        $attempt++
        $headers = @{
            'Authorization'    = "Bearer $script:DvToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }
        if ($Prefer)       { $headers['Prefer'] = $Prefer }
        if ($ExtraHeaders) { foreach ($k in $ExtraHeaders.Keys) { $headers[$k] = $ExtraHeaders[$k] } }

        $params = @{
            Uri         = $uri
            Method      = $Method
            Headers     = $headers
            ContentType = 'application/json; charset=utf-8'
            ErrorAction = 'Stop'
            UseBasicParsing = $true
        }
        if ($null -ne $Body) {
            $params['Body'] = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 12 -Compress }
        }

        try {
            $resp = Invoke-WebRequest @params
            if ($Raw) { return $resp }
            if ($resp.Content) { return ($resp.Content | ConvertFrom-Json) }
            return $resp
        }
        catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}

            if ($status -eq 401 -and $attempt -eq 1) {
                Write-Verbose "401 -- forcing token re-mint and retrying once."
                Update-DvToken -Force
                continue
            }

            $detail = ''
            try {
                $s = $_.Exception.Response.GetResponseStream()
                $s.Position = 0
                $detail = (New-Object System.IO.StreamReader($s)).ReadToEnd()
            } catch {}

            $err = [pscustomobject]@{
                Ok      = $false
                Status  = $status
                Message = $_.Exception.Message
                Detail  = $detail
            }
            return $err
        }
    }
}

function Test-DvConnection {
    $r = Invoke-Dv -Path 'WhoAmI'
    if ($r.PSObject.Properties.Name -contains 'UserId') {
        Write-Output "OK  WhoAmI -> UserId $($r.UserId)  OrgId $($r.OrganizationId)"
        return $true
    }
    Write-Output "FAIL $($r.Status) $($r.Message)"
    Write-Output $r.Detail
    return $false
}
