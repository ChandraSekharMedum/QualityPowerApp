# New-QmItemCache.ps1
# cog_Item -- the item lookup the Create NC screen needs.
#
# Source: POWERAPPSINVENTTABLEINVENTORYENTITY (mserp_powerappsinventtableinventoryentities),
# which exposes mserp_itemid / mserp_itemname / mserp_company. No item master virtual table is
# generated in this environment -- InventTableEntity and EcoResReleasedProductV2Entity both 404
# -- so this is the only item source available without generating another entity.
#
# Only companies that appear in the quality order cache are synced. That is 306 of the 3022 rows
# in F&O (usmf 210, usp2 48, uspi 48) and it keeps the picker responsive. A new company shows up
# automatically once it has a cached quality order.
#
# NAMING: the item column is cog_ItemNumber, not cog_ItemId. Dataverse auto-creates
# <tablename>id as the GUID primary key, so cog_ItemId on a table called cog_Item collides with
# it -- the string column is silently not created and inserts fail with "Cannot convert the
# literal ... to Edm.Guid". Same trap as cog_ProblemTypeCode.
#
# ASCII-only per project standard.

param(
    [switch]$SchemaOnly
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')
$solHeader = @{ 'MSCRM.SolutionUniqueName' = 'QualityManagementApp' }

function New-Label([string]$t) {
    @{ '@odata.type'='Microsoft.Dynamics.CRM.Label'
       LocalizedLabels=@(@{ '@odata.type'='Microsoft.Dynamics.CRM.LocalizedLabel'; Label=$t; LanguageCode=1033 }) }
}

$schema     = 'cog_Item'
$logical    = 'cog_item'
$attributes = @(
    @{t='String';   s='cog_ItemNumber';      l='Item number';     max=40;  req='ApplicationRequired'}
    @{t='String';   s='cog_ItemName';        l='Product name';    max=100}
    @{t='String';   s='cog_Company';         l='Company';         max=4;   req='ApplicationRequired'}
    @{t='DateTime'; s='cog_SynchronizedOn';  l='Synchronized on'}
)

# ---------------------------------------------------------------- table
Write-Output "=== Table ==="
$md = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')?`$select=LogicalName"
if (-not ($md.PSObject.Properties.Name -contains 'Ok')) {
    Write-Output "  $schema EXISTS"
} else {
    $body = @{
        '@odata.type'         = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName            = $schema
        DisplayName           = New-Label 'Item (cache)'
        DisplayCollectionName = New-Label 'Items (cache)'
        Description           = New-Label 'Cached F&O items for the non-conformance item lookup. Sourced from POWERAPPSINVENTTABLEINVENTORYENTITY; no item master virtual table is generated in this environment.'
        OwnershipType         = 'UserOwned'
        HasActivities         = $false
        HasNotes              = $false
        IsActivity            = $false
        PrimaryNameAttribute  = 'cog_name'
        Attributes            = @(@{
            '@odata.type'='Microsoft.Dynamics.CRM.StringAttributeMetadata'
            SchemaName='cog_Name'; MaxLength=200; IsPrimaryName=$true
            RequiredLevel=@{Value='ApplicationRequired'}; DisplayName=(New-Label 'Name')
        })
    }
    $r = Invoke-Dv -Method POST -Path 'EntityDefinitions' -Body $body -ExtraHeaders $solHeader
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Detail }
        throw "$schema create failed: $(($m -split "`n")[0])"
    }
    Write-Output "  $schema CREATED"
}

Write-Output ""
Write-Output "=== Attributes ==="
$have = @{}
$ex = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')/Attributes?`$select=LogicalName"
if (-not ($ex.PSObject.Properties.Name -contains 'Ok')) { foreach ($a in $ex.value) { $have[$a.LogicalName]=$true } }
$add=0; $skip=0
foreach ($a in $attributes) {
    if ($have.ContainsKey($a.s.ToLowerInvariant())) { $skip++; continue }
    $req = if ($a.req) { $a.req } else { 'None' }
    $b = @{ SchemaName=$a.s; DisplayName=(New-Label $a.l); RequiredLevel=@{Value=$req} }
    switch ($a.t) {
        'String'   { $b['@odata.type']='Microsoft.Dynamics.CRM.StringAttributeMetadata'; $b['MaxLength']=$a.max; $b['FormatName']=@{Value='Text'} }
        'DateTime' { $b['@odata.type']='Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'; $b['Format']='DateAndTime'; $b['DateTimeBehavior']=@{Value='UserLocal'} }
    }
    # Attribute creation intermittently returns "An unexpected error occurred" when metadata
    # operations overlap. It is transient -- retry rather than leaving the column missing, which
    # would silently break every filter that uses it.
    $r = $null
    for ($k = 1; $k -le 4; $k++) {
        $r = Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$logical')/Attributes" -Body $b -ExtraHeaders $solHeader
        if (-not ($r.PSObject.Properties.Name -contains 'Ok')) { break }
        Write-Output ("    {0} attempt {1} failed, retrying" -f $a.s, $k)
        Start-Sleep -Seconds 10
    }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
        throw "$schema.$($a.s) could not be created: $(($m -split "`n")[0])"
    }
    $add++
}
Write-Output ("  added {0}  existing {1}" -f $add,$skip)

$null = Invoke-Dv -Method POST -Path 'PublishAllXml' -Body @{}
Write-Output "  published"
if ($SchemaOnly) { return }

# ---------------------------------------------------------------- populate
Write-Output ""
Write-Output "=== Companies to sync ==="
$companies = @((Invoke-Dv -Path "cog_qualityorders?`$select=cog_company&`$top=1000").value.cog_company | Sort-Object -Unique)
Write-Output ("  {0}" -f ($companies -join ', '))

$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$src = Invoke-Dv -Path "mserp_powerappsinventtableinventoryentities?`$select=mserp_itemid,mserp_itemname,mserp_company&`$top=5000"
if ($src.PSObject.Properties.Name -contains 'Ok') { throw "Could not read items: $($src.Status)" }
$wanted = @($src.value | Where-Object { $companies -contains $_.mserp_company -and $_.mserp_itemid })
Write-Output ("  source rows in scope: {0} of {1}" -f $wanted.Count, @($src.value).Count)

Write-Output ""
Write-Output "=== Caching ==="
$new=0; $exist=0; $fail=0
foreach ($x in $wanted) {
    $f = "cog_itemnumber eq '$($x.mserp_itemid)' and cog_company eq '$($x.mserp_company)'"
    $q = Invoke-Dv -Path "cog_items?`$select=cog_itemnumber&`$filter=$f&`$top=1"
    if ($q.PSObject.Properties.Name -contains 'Ok') { Write-Warning "lookup failed [$($x.mserp_company)/$($x.mserp_itemid)]"; $fail++; continue }
    if (@($q.value).Count -gt 0) { $exist++; continue }
    $r = Invoke-Dv -Method POST -Path 'cog_items' -Body @{
        cog_name           = "$($x.mserp_company) | $($x.mserp_itemid)"
        cog_itemnumber     = $x.mserp_itemid
        cog_itemname       = $x.mserp_itemname
        cog_company        = $x.mserp_company
        cog_synchronizedon = $now }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
        Write-Warning "create failed [$($x.mserp_company)/$($x.mserp_itemid)]: $(($m -split "`n")[0])"
        $fail++
    } else { $new++ }
}
Write-Output ("  {0} new, {1} existing, {2} failed" -f $new,$exist,$fail)

Write-Output ""
Write-Output ("=== Total cached: {0} ===" -f @((Invoke-Dv -Path "cog_items?`$select=cog_itemnumber&`$top=2000").value).Count)
