# Sync-QmNcReference.ps1
# Populate the NC reference caches: problem types and customer/vendor accounts.
#
# Field names below were read off the live entities, not guessed. The first attempt guessed
# and failed:
#   POWERAPPSCUSTTABLEENTITY uses mserp_accountnum / mserp_name
#     (NOT mserp_customeraccount / mserp_organizationname)
#   VendVendorV2Entity uses mserp_vendoraccountnumber / mserp_vendororganizationname
#     (there is no mserp_vendorname)
#
# NAMING GOTCHA: the problem type code column is cog_ProblemTypeCode, not
# cog_ProblemTypeId. Dataverse auto-creates <tablename>id as the GUID primary key, so
# cog_ProblemTypeId on a table called cog_ProblemType collides with it -- the string column
# is silently not created and inserts fail with "Cannot convert the literal ... to Edm.Guid".
#
# ASCII-only per project standard.

param(
    [int]$MaxAccounts = 400
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')

$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$KIND_CUSTOMER = 1
$KIND_VENDOR   = 2

function Upsert([string]$set, [string]$filter, [hashtable]$body, [string]$label) {
    $ex = Invoke-Dv -Path "$set`?`$select=cog_name&`$filter=$filter&`$top=1"
    if ($ex.PSObject.Properties.Name -contains 'Ok') { Write-Warning "lookup failed [$label]"; return 'fail' }
    if (@($ex.value).Count -gt 0) { return 'exists' }
    $r = Invoke-Dv -Method POST -Path $set -Body $body
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
        Write-Warning "create failed [$label]: $(($m -split "`n")[0])"
        return 'fail'
    }
    return 'new'
}

# ------------------------------------------------------------ problem types
Write-Output "=== Problem types ==="
$pt = Invoke-Dv -Path "mserp_inventproblemtypedataentities?`$select=mserp_problemtypeid,mserp_description,mserp_dataareaid&`$top=300"
if ($pt.PSObject.Properties.Name -contains 'Ok') { throw "Could not read problem types: $($pt.Status)" }
Write-Output ("  source rows: {0}" -f @($pt.value).Count)
$new=0; $ex=0; $fail=0
foreach ($p in $pt.value) {
    if (-not $p.mserp_problemtypeid) { continue }
    $res = Upsert 'cog_problemtypes' `
        ("cog_problemtypecode eq '$($p.mserp_problemtypeid)' and cog_company eq '$($p.mserp_dataareaid)'") `
        @{ cog_name              = "$($p.mserp_dataareaid) | $($p.mserp_problemtypeid)"
           cog_problemtypecode   = $p.mserp_problemtypeid
           cog_company           = $p.mserp_dataareaid
           cog_description       = $p.mserp_description
           cog_synchronizedon    = $now } `
        "$($p.mserp_dataareaid)/$($p.mserp_problemtypeid)"
    switch ($res) { 'new' {$new++} 'exists' {$ex++} 'fail' {$fail++} }
}
Write-Output ("  cached: {0} new, {1} existing, {2} failed" -f $new,$ex,$fail)

# ------------------------------------------------------------ customers
Write-Output ""
Write-Output "=== Customers ==="
$c = Invoke-Dv -Path "mserp_powerappscusttableentities?`$select=mserp_accountnum,mserp_name,mserp_dataareaid&`$top=$MaxAccounts"
if ($c.PSObject.Properties.Name -contains 'Ok') { throw "Could not read customers: $($c.Status)" }
Write-Output ("  source rows: {0}" -f @($c.value).Count)
$new=0; $ex=0; $fail=0
foreach ($x in $c.value) {
    if (-not $x.mserp_accountnum) { continue }
    $res = Upsert 'cog_accounts' `
        ("cog_accountnumber eq '$($x.mserp_accountnum)' and cog_company eq '$($x.mserp_dataareaid)' and cog_accountkind eq $KIND_CUSTOMER") `
        @{ cog_name           = "$($x.mserp_dataareaid) | C | $($x.mserp_accountnum)"
           cog_accountnumber  = $x.mserp_accountnum
           cog_accountname    = $x.mserp_name
           cog_accountkind    = $KIND_CUSTOMER
           cog_company        = $x.mserp_dataareaid
           cog_synchronizedon = $now } `
        "$($x.mserp_dataareaid)/C/$($x.mserp_accountnum)"
    switch ($res) { 'new' {$new++} 'exists' {$ex++} 'fail' {$fail++} }
}
Write-Output ("  cached: {0} new, {1} existing, {2} failed" -f $new,$ex,$fail)

# ------------------------------------------------------------ vendors
Write-Output ""
Write-Output "=== Vendors ==="
$v = Invoke-Dv -Path "mserp_vendvendorv2entities?`$select=mserp_vendoraccountnumber,mserp_vendororganizationname,mserp_dataareaid&`$top=$MaxAccounts"
if ($v.PSObject.Properties.Name -contains 'Ok') { throw "Could not read vendors: $($v.Status)" }
Write-Output ("  source rows: {0}" -f @($v.value).Count)
$new=0; $ex=0; $fail=0
foreach ($x in $v.value) {
    if (-not $x.mserp_vendoraccountnumber) { continue }
    $res = Upsert 'cog_accounts' `
        ("cog_accountnumber eq '$($x.mserp_vendoraccountnumber)' and cog_company eq '$($x.mserp_dataareaid)' and cog_accountkind eq $KIND_VENDOR") `
        @{ cog_name           = "$($x.mserp_dataareaid) | V | $($x.mserp_vendoraccountnumber)"
           cog_accountnumber  = $x.mserp_vendoraccountnumber
           cog_accountname    = $x.mserp_vendororganizationname
           cog_accountkind    = $KIND_VENDOR
           cog_company        = $x.mserp_dataareaid
           cog_synchronizedon = $now } `
        "$($x.mserp_dataareaid)/V/$($x.mserp_vendoraccountnumber)"
    switch ($res) { 'new' {$new++} 'exists' {$ex++} 'fail' {$fail++} }
}
Write-Output ("  cached: {0} new, {1} existing, {2} failed" -f $new,$ex,$fail)

Write-Output ""
Write-Output "=== Totals ==="
Write-Output ("  problem types : {0}" -f @((Invoke-Dv -Path "cog_problemtypes?`$select=cog_name&`$top=500").value).Count)
Write-Output ("  accounts      : {0}" -f @((Invoke-Dv -Path "cog_accounts?`$select=cog_name&`$top=1000").value).Count)
