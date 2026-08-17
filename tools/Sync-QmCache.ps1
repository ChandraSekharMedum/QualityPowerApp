# Sync-QmCache.ps1
# Phase 2: populate the cog_ cache tables from the F&O virtual entities.
#
# This is the logic the production sync flow will carry. Running it directly here proves
# the field mapping against real data and gives the app something to bind to, without
# depending on the Power Automate runtime (which cannot be armed from this environment).
#
# Idempotent: matches on the natural key and updates in place.
# ASCII-only per project standard.

param(
    [string]$Company = 'usmf',
    [int]$MaxOrders  = 25
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')

$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$stats = [ordered]@{ OrdersNew=0; OrdersUpd=0; LinesNew=0; LinesUpd=0; OutcomesNew=0; Failed=0 }

# NOTE: diagnostics inside this function MUST NOT use Write-Output -- in PowerShell that
# lands on the success stream and becomes part of the return value, which silently turns
# a failure into a truthy result. Use Write-Warning (stream 3), still captured by *>&1.
function Upsert-Row {
    param(
        [string]$Set,        # entity set name, e.g. cog_qualitytestlines
        [string]$IdProp,     # primary key property, e.g. cog_qualitytestlineid
        [string]$Filter,
        [hashtable]$Body,
        [string]$Label
    )

    $ex = Invoke-Dv -Path "$Set`?`$select=$IdProp&`$filter=$Filter&`$top=1"
    if ($ex.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($ex.Detail | ConvertFrom-Json).error.message } catch { $m = $ex.Status }
        Write-Warning "lookup failed [$Label]: $(($m -split "`n")[0])"
        $script:stats.Failed++
        return $null
    }

    if (@($ex.value).Count -gt 0) {
        $id = $ex.value[0].$IdProp
        $r = Invoke-Dv -Method PATCH -Path "$Set($id)" -Body $Body
        if ($r.PSObject.Properties.Name -contains 'Ok') {
            $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Status }
            Write-Warning "update failed [$Label]: $(($m -split "`n")[0])"
            $script:stats.Failed++
            return $null
        }
        return [pscustomobject]@{ Id = $id; New = $false }
    }

    $r = Invoke-Dv -Method POST -Path $Set -Body $Body -Prefer 'return=representation'
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Status }
        Write-Warning "create failed [$Label]: $(($m -split "`n")[0])"
        $script:stats.Failed++
        return $null
    }
    return [pscustomobject]@{ Id = $r.$IdProp; New = $true }
}

# -------------------------------------------------- 1. quality orders
Write-Output "=== Quality orders ($Company) ==="
$q = Invoke-Dv -Path ("mserp_inventqualityorderheaderentities?`$select=mserp_qualityordernumber,mserp_dataareaid," +
    "mserp_itemnumber,mserp_productname,mserp_qualitytestgroupid,mserp_referencetype,mserp_inventoryquantity," +
    "mserp_inventorysiteid,mserp_warehouseid,mserp_itembatchnumber,mserp_qualityorderstatus" +
    "&`$filter=mserp_dataareaid eq '$Company'&`$top=$MaxOrders")

if ($q.PSObject.Properties.Name -contains 'Ok') { throw "Could not read quality orders: $($q.Status)" }
Write-Output ("  source rows: {0}" -f @($q.value).Count)

$orderIds = @{}
foreach ($o in $q.value) {
    $num = $o.mserp_qualityordernumber
    $body = @{
        cog_name               = $num
        cog_qualityordernumber = $num
        cog_company            = $o.mserp_dataareaid
        cog_itemnumber         = $o.mserp_itemnumber
        cog_productname        = $o.mserp_productname
        cog_testgroupid        = $o.mserp_qualitytestgroupid
        cog_referencetype      = $o.mserp_referencetype
        cog_inventoryquantity  = $o.mserp_inventoryquantity
        cog_siteid             = $o.mserp_inventorysiteid
        cog_warehouseid        = $o.mserp_warehouseid
        cog_batchnumber        = $o.mserp_itembatchnumber
        cog_status             = $o.mserp_qualityorderstatus
        cog_synchronizedon     = $now
    }
    $res = Upsert-Row -Set 'cog_qualityorders' -IdProp 'cog_qualityorderid' -Filter "cog_qualityordernumber eq '$num' and cog_company eq '$($o.mserp_dataareaid)'" -Body $body -Label "QO $num"
    if ($res) {
        $orderIds["$($o.mserp_dataareaid)|$num"] = $res.Id
        if ($res.New) { $stats.OrdersNew++ } else { $stats.OrdersUpd++ }
    }
}
Write-Output ("  cached: {0} new, {1} updated" -f $stats.OrdersNew, $stats.OrdersUpd)

# -------------------------------------------------- 2. test lines with tolerances
Write-Output ""
Write-Output "=== Test lines (with tolerance bounds) ==="
$l = Invoke-Dv -Path ("mserp_powerappinventqolineentities?`$select=mserp_qualityorderid,mserp_testid,mserp_testsequence," +
    "mserp_dataareaid,mserp_lowerlimit,mserp_upperlimit,mserp_standardvalue,mserp_testinstrumentid," +
    "mserp_testunitid,mserp_variableid,mserp_testresult,mserp_pdsorderlineresult" +
    "&`$filter=mserp_dataareaid eq '$Company'&`$top=200")

if ($l.PSObject.Properties.Name -contains 'Ok') { throw "Could not read test lines: $($l.Status)" }
Write-Output ("  source rows: {0}" -f @($l.value).Count)

# The tolerance-bearing entity (POWERAPPINVENTQOLINEENTITY) does not carry the id of the
# F&O result row that a submitted value is written to. Build a lookup from the base result
# entity so the app can queue a complete outbox payload without a drain-time lookup.
$targets = @{}
$tr = Invoke-Dv -Path ("mserp_inventqualityorderlineresultentities?`$select=mserp_inventqualityorderlineresultentityid," +
    "mserp_qualityordernumber,mserp_qualitytestid,mserp_qualityordersequencenumber,mserp_dataareaid" +
    "&`$filter=mserp_dataareaid eq '$Company'&`$top=500")
if ($tr.PSObject.Properties.Name -contains 'Ok') {
    Write-Warning "could not read result lines for target ids: $($tr.Status)"
} else {
    foreach ($t in $tr.value) {
        $k = "{0}|{1}|{2}|{3}" -f $t.mserp_dataareaid, $t.mserp_qualityordernumber, $t.mserp_qualitytestid, $t.mserp_qualityordersequencenumber
        $targets[$k] = $t.mserp_inventqualityorderlineresultentityid
    }
    Write-Output ("  target id lookup: {0} F&O result rows" -f $targets.Count)
}

foreach ($ln in $l.value) {
    $key = "$($ln.mserp_dataareaid)|$($ln.mserp_qualityorderid)"
    if (-not $orderIds.ContainsKey($key)) { continue }   # line for an order outside this sync window

    $name = "{0} | {1} | {2}" -f $ln.mserp_qualityorderid, $ln.mserp_testsequence, $ln.mserp_testid
    $body = @{
        cog_name                     = $name
        cog_qualityordernumber       = $ln.mserp_qualityorderid
        cog_testid                   = $ln.mserp_testid
        cog_testsequence             = $ln.mserp_testsequence
        cog_company                  = $ln.mserp_dataareaid
        cog_lowerlimit               = $ln.mserp_lowerlimit
        cog_upperlimit               = $ln.mserp_upperlimit
        cog_standardvalue            = $ln.mserp_standardvalue
        cog_testinstrumentid         = $ln.mserp_testinstrumentid
        cog_testunitid               = $ln.mserp_testunitid
        cog_variableid               = $ln.mserp_variableid
        cog_currentresult            = $ln.mserp_testresult
        cog_currentvalue             = $ln.mserp_pdsorderlineresult
        cog_targetrecordid           = $targets["$($ln.mserp_dataareaid)|$($ln.mserp_qualityorderid)|$($ln.mserp_testid)|$($ln.mserp_testsequence)"]
        cog_synchronizedon           = $now
        'cog_QualityOrderId@odata.bind' = "/cog_qualityorders($($orderIds[$key]))"
    }
    $filter = "cog_qualityordernumber eq '$($ln.mserp_qualityorderid)' and cog_testid eq '$($ln.mserp_testid)' and cog_testsequence eq $($ln.mserp_testsequence) and cog_company eq '$($ln.mserp_dataareaid)'"
    $res = Upsert-Row -Set 'cog_qualitytestlines' -IdProp 'cog_qualitytestlineid' -Filter $filter -Body $body -Label $name
    if ($res) { if ($res.New) { $stats.LinesNew++ } else { $stats.LinesUpd++ } }
}
Write-Output ("  cached: {0} new, {1} updated" -f $stats.LinesNew, $stats.LinesUpd)

# -------------------------------------------------- 3. qualitative outcomes
Write-Output ""
Write-Output "=== Test outcomes ==="
$o = Invoke-Dv -Path "mserp_inventqualitytestvariableoutcomeentities?`$filter=mserp_dataareaid eq '$Company'&`$top=100"
if ($o.PSObject.Properties.Name -contains 'Ok') {
    Write-Output "  could not read outcomes: $($o.Status)"
} else {
    Write-Output ("  source rows: {0}" -f @($o.value).Count)
    foreach ($x in $o.value) {
        $var = $x.mserp_qualitytestvariableid
        $out = $x.mserp_outcomeid
        if (-not $var -and -not $out) { continue }
        $body = @{
            cog_name           = "$var | $out"
            cog_variableid     = $var
            cog_outcomeid      = $out
            cog_company        = $x.mserp_dataareaid
            cog_description    = $x.mserp_outcomedescription
            cog_impliedresult  = $x.mserp_outcomestatus
            cog_synchronizedon = $now
        }
        $res = Upsert-Row -Set 'cog_testoutcomes' -IdProp 'cog_testoutcomeid' -Filter "cog_variableid eq '$var' and cog_outcomeid eq '$out' and cog_company eq '$($x.mserp_dataareaid)'" -Body $body -Label "$var|$out"
        if ($res -and $res.New) { $stats.OutcomesNew++ }
    }
    Write-Output ("  cached: {0} new" -f $stats.OutcomesNew)
}

Write-Output ""
Write-Output "=== Summary ==="
$stats.GetEnumerator() | ForEach-Object { Write-Output ("  {0,-12} {1}" -f $_.Key, $_.Value) }

