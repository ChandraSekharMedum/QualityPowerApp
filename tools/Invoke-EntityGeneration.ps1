# Invoke-EntityGeneration.ps1
# Phase 1, task 2: switch on the F&O virtual entities the app needs.
#
# Generation is a PATCH of mserp_hasbeengenerated = true on the catalogue row.
# The provider then creates the mserp_<physicalname> table asynchronously, so
# this script generates in small batches and reports; verification is separate
# (Test-GeneratedEntities.ps1).
#
# -WhatIf lists what would change without touching the environment.
# ASCII-only per project standard.

param(
    [switch]$WhatIf,
    [int]$BatchSize = 5,
    [int]$PauseSeconds = 20
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'dvlib.ps1')
. (Join-Path $here 'entity-targets.ps1')

$outDir = Join-Path (Split-Path -Parent $here) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

Write-Output "Resolving $($script:EntityTargets.Count) target entities against the catalogue..."

$resolved = New-Object System.Collections.Generic.List[object]

foreach ($t in $script:EntityTargets) {
    $name = $t.Name
    $esc  = $name.Replace("'", "''")
    $q = "mserp_financeandoperationsentities?`$select=mserp_physicalname,mserp_hasbeengenerated,mserp_changetrackingenabled&`$filter=mserp_physicalname eq '$esc'"
    $r = Invoke-Dv -Path $q

    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $resolved.Add([pscustomobject]@{
            Name=$name; Area=$t.Area; Why=$t.Why; Id=$null
            Found=$false; AlreadyGenerated=$false; Status="LOOKUP FAILED $($r.Status)"
        })
        continue
    }

    if (-not $r.value -or $r.value.Count -eq 0) {
        $resolved.Add([pscustomobject]@{
            Name=$name; Area=$t.Area; Why=$t.Why; Id=$null
            Found=$false; AlreadyGenerated=$false; Status='NOT IN CATALOGUE'
        })
        continue
    }

    $row = $r.value[0]
    $resolved.Add([pscustomobject]@{
        Name             = $row.mserp_physicalname
        Area             = $t.Area
        Why              = $t.Why
        Id               = $row.mserp_financeandoperationsentityid
        Found            = $true
        AlreadyGenerated = [bool]$row.mserp_hasbeengenerated
        Status           = if ($row.mserp_hasbeengenerated) { 'ALREADY GENERATED' } else { 'TO GENERATE' }
    })
}

$resolved | Select-Object Name, Area, Status | Format-Table -AutoSize | Out-String | Write-Output

$missing = $resolved | Where-Object { -not $_.Found }
$todo    = $resolved | Where-Object { $_.Found -and -not $_.AlreadyGenerated }
$already = $resolved | Where-Object { $_.AlreadyGenerated }

Write-Output ""
Write-Output "Resolved : $($resolved.Count)"
Write-Output "  already generated : $($already.Count)"
Write-Output "  to generate       : $($todo.Count)"
Write-Output "  not in catalogue  : $($missing.Count)"

$resolved | ConvertTo-Json -Depth 4 | Out-File (Join-Path $outDir 'entity-resolution.json') -Encoding utf8

if ($WhatIf) {
    Write-Output ""
    Write-Output "-WhatIf specified. No changes made."
    return
}

if ($todo.Count -eq 0) { Write-Output "Nothing to generate."; return }

Write-Output ""
Write-Output "Generating in batches of $BatchSize with ${PauseSeconds}s between batches..."

$results = New-Object System.Collections.Generic.List[object]
$i = 0

foreach ($e in $todo) {
    $i++
    $body = @{ mserp_hasbeengenerated = $true }
    $r = Invoke-Dv -Method PATCH -Path "mserp_financeandoperationsentities($($e.Id))" -Body $body

    $ok = -not ($r.PSObject.Properties.Name -contains 'Ok')
    $results.Add([pscustomobject]@{
        Name    = $e.Name
        Area    = $e.Area
        Ok      = $ok
        Status  = if ($ok) { 'PATCHED' } else { "FAILED $($r.Status)" }
        Detail  = if ($ok) { '' } else { $r.Detail }
    })
    Write-Output ("  [{0,2}/{1}] {2,-58} {3}" -f $i, $todo.Count, $e.Name, $(if($ok){'PATCHED'}else{"FAILED $($r.Status)"}))

    if ($i % $BatchSize -eq 0 -and $i -lt $todo.Count) {
        Write-Output "  -- pausing ${PauseSeconds}s to let the provider catch up --"
        Start-Sleep -Seconds $PauseSeconds
    }
}

$results | ConvertTo-Json -Depth 4 | Out-File (Join-Path $outDir 'entity-generation.json') -Encoding utf8

Write-Output ""
Write-Output "Patched OK : $(($results | Where-Object Ok).Count)"
Write-Output "Failed     : $(($results | Where-Object {-not $_.Ok}).Count)"
Write-Output ""
Write-Output "Table creation is asynchronous. Run Test-GeneratedEntities.ps1 in a few minutes to verify."
