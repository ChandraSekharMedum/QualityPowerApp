# Sync-QmPoLineCache.ps1
# Populate cog_POLine -- the picker source for the Create Quality Order screen.
#
# Three reads, joined in memory:
#   1. PurchPurchaseOrderHeaderV2Entity  -> mserp_ordervendoraccountnumber per PO.
#      The vendor is NOT on the line, and it is not optional: the demo app sends it as
#      'Account selection' and dropping it changes which F&O rejection you get.
#   2. InventQualityOrderHeaderEntity    -> the set of reference lots already carrying a
#      quality order. Reusing one fails with "Cannot change dimensions because existing
#      mark would conflict", so the picker needs to know before the user taps.
#   3. PurchPurchaseOrderLineV2Entity    -> the lines themselves.
#
# Lines with no mserp_inventorylotid are skipped. Without the lot F&O rejects the create
# with "'<n>' in field 'Reference number' is not found in the related table 'Purchase order
# lines'" -- so a line without one can never produce a quality order and has no business
# being in the picker.
#
# Re-runnable: existing rows are PATCHed, not duplicated.
#
# ASCII-only per project standard.

param(
    [string]$Company  = 'usmf',
    [int]$MaxLines    = 500,
    [int]$MaxHeaders  = 500,
    [int]$MaxOrders   = 500
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')

$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

function Fail([object]$r) { return ($r.PSObject.Properties.Name -contains 'Ok') }

# F&O product names are not length-bounded the way the cache column is. Two usmf lines
# exceeded 100 chars on the first run and were rejected outright, losing the whole row for
# the sake of a display string. Truncate rather than fail -- the name is for the picker,
# nothing downstream keys on it.
function Trunc([object]$s, [int]$n) {
    if ($null -eq $s) { return $null }
    $t = [string]$s
    if ($t.Length -le $n) { return $t }
    return $t.Substring(0, $n)
}

# -------------------------------------------------- 1. vendor per purchase order
Write-Output "=== PO headers ($Company) ==="
$h = Invoke-Dv -Path ("mserp_purchpurchaseorderheaderv2entities?`$select=mserp_purchaseordernumber," +
    "mserp_ordervendoraccountnumber,mserp_dataareaid" +
    "&`$filter=mserp_dataareaid eq '$Company'&`$top=$MaxHeaders")
if (Fail $h) { throw "Could not read PO headers: $($h.Status)" }

$vendorOf = @{}
foreach ($x in $h.value) {
    if ($x.mserp_purchaseordernumber) { $vendorOf[$x.mserp_purchaseordernumber] = $x.mserp_ordervendoraccountnumber }
}
Write-Output ("  headers: {0}, vendors mapped: {1}" -f @($h.value).Count, $vendorOf.Count)

# -------------------------------------------------- 2. lots already inspected
Write-Output ""
Write-Output "=== Existing quality orders ($Company) ==="
$q = Invoke-Dv -Path ("mserp_inventqualityorderheaderentities?`$select=mserp_qualityordernumber," +
    "mserp_referenceinventorylotid&`$filter=mserp_dataareaid eq '$Company'&`$top=$MaxOrders")
$usedLots = @{}
if (Fail $q) {
    Write-Warning "  could not read quality orders ($($q.Status)) -- every line will be flagged available"
} else {
    foreach ($x in $q.value) {
        if ($x.mserp_referenceinventorylotid) { $usedLots[$x.mserp_referenceinventorylotid] = $true }
    }
    Write-Output ("  quality orders: {0}, distinct lots already marked: {1}" -f @($q.value).Count, $usedLots.Count)
}

# -------------------------------------------------- 3. the lines
Write-Output ""
Write-Output "=== PO lines ($Company) ==="
$l = Invoke-Dv -Path ("mserp_purchpurchaseorderlinev2entities?`$select=mserp_purchaseordernumber,mserp_linenumber," +
    "mserp_dataareaid,mserp_itemnumber,mserp_itemname,mserp_inventorylotid,mserp_receivingsiteid," +
    "mserp_receivingwarehouseid,mserp_orderedinventorystatusid,mserp_productconfigurationid," +
    "mserp_productcolorid,mserp_productsizeid,mserp_productstyleid,mserp_orderedpurchasequantity," +
    "mserp_purchaseorderlinestatus" +
    "&`$filter=mserp_dataareaid eq '$Company'&`$top=$MaxLines")
if (Fail $l) { throw "Could not read PO lines: $($l.Status)" }
Write-Output ("  source rows: {0}" -f @($l.value).Count)

$new=0; $upd=0; $skipNoLot=0; $fail=0
foreach ($x in $l.value) {
    if (-not $x.mserp_inventorylotid) { $skipNoLot++; continue }

    $po   = $x.mserp_purchaseordernumber
    $line = $x.mserp_linenumber
    $co   = $x.mserp_dataareaid

    $body = @{
        cog_name                 = "$co | $po | $line"
        cog_purchaseordernumber  = $po
        cog_linenumber           = $line
        cog_company              = $co
        cog_itemnumber           = $x.mserp_itemnumber
        cog_itemname             = (Trunc $x.mserp_itemname 200)
        cog_inventorylotid       = $x.mserp_inventorylotid
        cog_siteid               = $x.mserp_receivingsiteid
        cog_warehouseid          = $x.mserp_receivingwarehouseid
        cog_inventorystatusid    = $x.mserp_orderedinventorystatusid
        cog_vendoraccount        = $vendorOf[$po]
        cog_configurationid      = $x.mserp_productconfigurationid
        cog_colorid              = $x.mserp_productcolorid
        cog_sizeid               = $x.mserp_productsizeid
        cog_styleid              = $x.mserp_productstyleid
        cog_orderedquantity      = $x.mserp_orderedpurchasequantity
        cog_linestatus           = $x.mserp_purchaseorderlinestatus
        cog_hasqualityorder      = $(if ($usedLots.ContainsKey($x.mserp_inventorylotid)) { 1 } else { 0 })
        cog_synchronizedon       = $now
    }

    $filter = "cog_purchaseordernumber eq '$po' and cog_linenumber eq $line and cog_company eq '$co'"
    $ex = Invoke-Dv -Path "cog_polines?`$select=cog_polineid&`$filter=$filter&`$top=1"
    if (Fail $ex) { Write-Warning "lookup failed [$po/$line]"; $fail++; continue }

    if (@($ex.value).Count -gt 0) {
        $id = $ex.value[0].cog_polineid
        $r = Invoke-Dv -Method PATCH -Path "cog_polines($id)" -Body $body
        if (Fail $r) {
            $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
            Write-Warning "update failed [$po/$line]: $(($m -split "`n")[0])"; $fail++
        } else { $upd++ }
    } else {
        $r = Invoke-Dv -Method POST -Path 'cog_polines' -Body $body
        if (Fail $r) {
            $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
            Write-Warning "create failed [$po/$line]: $(($m -split "`n")[0])"; $fail++
        } else { $new++ }
    }
}

Write-Output ""
Write-Output "=== Summary ==="
Write-Output ("  new         : {0}" -f $new)
Write-Output ("  updated     : {0}" -f $upd)
Write-Output ("  skipped     : {0}  (no reference lot -- cannot create a quality order)" -f $skipNoLot)
Write-Output ("  failed      : {0}" -f $fail)
Write-Output ("  already used: {0}  lots carry a quality order" -f $usedLots.Count)
