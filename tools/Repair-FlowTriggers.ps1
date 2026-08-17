# Repair-FlowTriggers.ps1
# Re-arm the Dataverse-triggered flows in the solution.
#
# WHY THIS EXISTS
# A solution import reports "the original workflow definition has been deactivated and
# replaced" and leaves the flow reading statecode=1 / statuscode=2 -- apparently active.
# The underlying Dataverse webhook registration, however, is gone. The flow then silently
# never fires: rows sit in the outbox at Queued with attempts=0 and no error, because
# nothing ever picked them up.
#
# Observed 2026-08-17: cog_QM_DrainOutbox showed 1/2 and ACTIVE, but neither a row create
# nor a row update triggered it. A deactivate/reactivate cycle fixed it immediately.
#
# A statecode check is NOT sufficient to prove a flow is working. Run this after EVERY
# solution import, and prove it with a real round trip rather than a status read.
#
# ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'dvlib.ps1')

Write-Output "=== Re-arming flows in $SolutionName ==="

$sol = Invoke-Dv -Path "solutions?`$select=solutionid&`$filter=uniquename eq '$SolutionName'"
if (@($sol.value).Count -eq 0) { throw "Solution $SolutionName not found." }

$sc = Invoke-Dv -Path "solutioncomponents?`$select=objectid&`$filter=_solutionid_value eq $($sol.value[0].solutionid) and componenttype eq 29"
if (@($sc.value).Count -eq 0) { Write-Output "  no cloud flows in the solution"; return }

foreach ($c in $sc.value) {
    $w = Invoke-Dv -Path "workflows($($c.objectid))?`$select=name,statecode,statuscode"
    if ($w.PSObject.Properties.Name -contains 'Ok') { continue }

    if ($WhatIf) {
        Write-Output ("  {0,-26} {1}/{2}  would re-arm" -f $w.name, $w.statecode, $w.statuscode)
        continue
    }

    # Deactivate then reactivate. This is what actually re-registers the webhook; setting
    # statecode to the value it already holds does nothing.
    $null = Invoke-Dv -Method PATCH -Path "workflows($($c.objectid))" -Body @{ statecode = 0; statuscode = 1 }
    Start-Sleep -Seconds 4

    $ok = $false
    for ($i = 1; $i -le 3; $i++) {
        $r = Invoke-Dv -Method PATCH -Path "workflows($($c.objectid))" -Body @{ statecode = 1; statuscode = 2 }
        if ($r.PSObject.Properties.Name -contains 'Ok') { Start-Sleep -Seconds 4 } else { $ok = $true; break }
    }

    $after = Invoke-Dv -Path "workflows($($c.objectid))?`$select=statecode,statuscode"
    Write-Output ("  {0,-26} {1}/{2}  {3}" -f $w.name, $after.statecode, $after.statuscode,
                  $(if ($ok) { 're-armed' } else { 'REACTIVATION FAILED' }))
}

Write-Output ""
Write-Output "Re-armed. Verify with a real round trip -- queue an outbox row and watch it"
Write-Output "reach Confirmed. A statecode of 1/2 alone does not prove the trigger fires."
