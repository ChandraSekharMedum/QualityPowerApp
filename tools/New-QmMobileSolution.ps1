# New-QmMobileSolution.ps1
# Creates the QualityAPP_Mobile solution -- a SEPARATE solution from QualityManagementApp.
#
# WHY SEPARATE
#
# The mobile app is online-only, so it shares nothing with the tablet app: no cog_ tables, no
# flows, no connection references. Keeping it in its own solution means
#
#   * Export-Solution.ps1 and Publish-CanvasApp.ps1 keep working unchanged. Both take the FIRST
#     .msapp in a solution, which is correct as long as each solution holds exactly one canvas
#     app. Two apps in one solution would silently cross-wire them.
#   * a mobile publish cannot overwrite the parked tablet app, by construction rather than by a
#     guard.
#   * the two carry independent version histories.
#
# COMPONENTS
#
# Only the five F&O virtual entities the online app reads and writes. They are provider-generated
# and IsManaged=True, so adding them to an unmanaged solution can be refused by the platform --
# failures are reported per entity rather than aborting, exactly as New-QmSolution.ps1 does.
# Solution membership is not exclusive, so this does not remove them from anything else.
#
# The canvas app itself must be created in Studio; canvas apps cannot be created over the API.
#
# ASCII-only per project standard.

param(
    [string]$UniqueName          = 'QualityAPP_Mobile',
    [string]$FriendlyName        = 'Quality App Mobile',
    [string]$Version             = '0.1.0.0',
    [string]$PublisherUniqueName = 'ColumbusGlobal'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')

# The online design's five data sources. See docs\MOBILE-ONLINE-DESIGN.md.
$entities = @(
    @{ Logical='mserp_inventqualityorderheaderentity';        Role='order picker' }
    @{ Logical='mserp_powerappinventqolineentity';            Role='test lines: tolerances, unit, variableid' }
    @{ Logical='mserp_inventqualityorderlineresultentity';    Role='result rows (write target)' }
    @{ Logical='mserp_powerappsinventtestvariableoutcomeentity'; Role='outcome choices for option tests' }
    @{ Logical='mserp_powerappfilesavingentity';              Role='photo attachments (write target)' }
)

# ---------- publisher ----------
Write-Output "=== Publisher ==="
$p = Invoke-Dv -Path "publishers?`$select=uniquename,customizationprefix,publisherid&`$filter=uniquename eq '$PublisherUniqueName'"
if ($p.PSObject.Properties.Name -contains 'Ok' -or -not $p.value -or $p.value.Count -eq 0) {
    throw "Publisher '$PublisherUniqueName' not found."
}
$pub = $p.value[0]
Write-Output ("  {0}  prefix={1}" -f $pub.uniquename, $pub.customizationprefix)

# ---------- solution ----------
Write-Output ""
Write-Output "=== Solution ==="
$s = Invoke-Dv -Path "solutions?`$select=uniquename,friendlyname,version,solutionid&`$filter=uniquename eq '$UniqueName'"
if ($s.value -and $s.value.Count -gt 0) {
    $sol = $s.value[0]
    Write-Output ("  EXISTS   {0}  v{1}" -f $sol.uniquename, $sol.version)
} else {
    $body = @{
        uniquename               = $UniqueName
        friendlyname             = $FriendlyName
        version                  = $Version
        'publisherid@odata.bind' = "/publishers($($pub.publisherid))"
    }
    $r = Invoke-Dv -Method POST -Path 'solutions' -Body $body -Prefer 'return=representation'
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Detail }
        throw "Could not create solution: $(($m -split "`n")[0])"
    }
    $sol = $r
    Write-Output ("  CREATED  {0}  v{1}" -f $sol.uniquename, $sol.version)
}
Write-Output ("  id       {0}" -f $sol.solutionid)

# ---------- components ----------
Write-Output ""
Write-Output "=== Adding the five F&O virtual entities ==="
$added=0; $failed=0
foreach ($e in $entities) {
    $md = Invoke-Dv -Path "EntityDefinitions(LogicalName='$($e.Logical)')?`$select=LogicalName,MetadataId"
    if ($md.PSObject.Properties.Name -contains 'Ok') {
        Write-Output ("  {0,-52} METADATA MISSING" -f $e.Logical); $failed++; continue
    }
    $r = Invoke-Dv -Method POST -Path 'AddSolutionComponent' -Body @{
        ComponentId               = $md.MetadataId
        ComponentType             = 1
        SolutionUniqueName        = $UniqueName
        AddRequiredComponents     = $false
        DoNotIncludeSubcomponents = $true
    }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
        Write-Output ("  {0,-52} FAILED: {1}" -f $e.Logical,(($m -split "`n")[0])); $failed++
    } else {
        Write-Output ("  {0,-52} ADDED    ({1})" -f $e.Logical,$e.Role); $added++
    }
}
Write-Output ""
Write-Output ("  added {0}, failed {1}" -f $added,$failed)

# ---------- verify ----------
Write-Output ""
Write-Output "=== Components now in $UniqueName ==="
$sc = Invoke-Dv -Path "solutioncomponents?`$select=componenttype,objectid&`$filter=_solutionid_value eq $($sol.solutionid)&`$top=200"
if ($sc.value -and @($sc.value).Count -gt 0) {
    $sc.value | Group-Object componenttype | Sort-Object Name | ForEach-Object {
        Write-Output ("  componenttype {0,-5} x{1}" -f $_.Name,$_.Count) }
} else { Write-Output "  none" }

Write-Output ""
Write-Output "NEXT, IN STUDIO (canvas apps cannot be created over the API):"
Write-Output "  1. Create a new canvas app, PHONE layout, inside the $UniqueName solution."
Write-Output "  2. Add these five data sources:"
foreach ($e in $entities) { Write-Output ("       {0}" -f $e.Logical) }
Write-Output "  3. Save and publish, then tell me -- I will export before publishing anything."
