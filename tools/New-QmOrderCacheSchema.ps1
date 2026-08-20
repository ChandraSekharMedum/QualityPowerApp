# New-QmOrderCacheSchema.ps1
# Cache table the Create Quality Order screen needs: purchase order lines.
#
# Why a cache and not the virtual entity directly:
#   Adding mserp_purchpurchaseorderlinev2entity as an app data source is a Studio-only step
#   AND would make order creation require connectivity, against D-02 (offline). Every other
#   picker in this app reads a cog_ cache, so this keeps the pattern.
#
# Column names below were read off the live entity metadata, not guessed. Two that matter:
#   mserp_linenumber is DECIMAL, not Integer -- an Int column here truncates silently.
#   The vendor is NOT on the line. It is mserp_ordervendoraccountnumber on the V2 HEADER,
#   and it matters: the demo app sends it as 'Account selection' and omitting it changes
#   which F&O rejection you get. See docs/QUALITY-ORDER-CREATION.md section 4.
#
# cog_HasQualityOrder is cached rather than computed in the app so the picker can hide or
# grey lots that already carry a quality order -- reusing one fails with
# "Cannot change dimensions because existing mark would conflict".
#
# NAMING GOTCHA (cost a failed run on cog_ProblemType): Dataverse auto-creates
# <tablename>id as the GUID primary key. A string column named cog_POLineId on a table
# called cog_POLine would collide with it and be silently skipped. Hence cog_LineNumber.
#
# ASCII-only per project standard.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')
$solHeader = @{ 'MSCRM.SolutionUniqueName' = 'QualityManagementApp' }

function New-Label([string]$t) {
    @{ '@odata.type'='Microsoft.Dynamics.CRM.Label'
       LocalizedLabels=@(@{ '@odata.type'='Microsoft.Dynamics.CRM.LocalizedLabel'; Label=$t; LanguageCode=1033 }) }
}

$tables = @(
  @{ Schema='cog_POLine'; Display='PO Line (cache)'; Plural='PO Lines (cache)'
     Desc='Cached F&O purchase order lines, the source for the Create Quality Order picker. Carries the reference inventory lot, the product dimensions and the order vendor -- the full field set F&O needs to accept a quality order create.'
     Attributes=@(
       @{t='String'; s='cog_PurchaseOrderNumber'; l='Purchase order';     max=20; req='ApplicationRequired'}
       @{t='Decimal';s='cog_LineNumber';          l='Line number'}
       @{t='String'; s='cog_Company';             l='Company';            max=4;  req='ApplicationRequired'}
       @{t='String'; s='cog_ItemNumber';          l='Item number';        max=20}
       @{t='String'; s='cog_ItemName';            l='Product name';       max=200}
       @{t='String'; s='cog_InventoryLotId';      l='Reference lot';      max=30}
       @{t='String'; s='cog_SiteId';              l='Site';               max=20}
       @{t='String'; s='cog_WarehouseId';         l='Warehouse';          max=20}
       @{t='String'; s='cog_InventoryStatusId';   l='Inventory status';   max=20}
       @{t='String'; s='cog_VendorAccount';       l='Vendor account';     max=20}
       @{t='String'; s='cog_ConfigurationId';     l='Configuration';      max=20}
       @{t='String'; s='cog_ColorId';             l='Color';              max=20}
       @{t='String'; s='cog_SizeId';              l='Size';               max=20}
       @{t='String'; s='cog_StyleId';             l='Style';              max=20}
       @{t='Decimal';s='cog_OrderedQuantity';     l='Ordered quantity'}
       @{t='Int';    s='cog_LineStatus';          l='Line status'}
       @{t='Int';    s='cog_HasQualityOrder';     l='Already inspected'}
       @{t='DateTime'; s='cog_SynchronizedOn';    l='Synchronized on'}
     )}
)

Write-Output "=== Tables ==="
foreach ($t in $tables) {
    $logical = $t.Schema.ToLowerInvariant()
    $md = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')?`$select=LogicalName"
    if (-not ($md.PSObject.Properties.Name -contains 'Ok')) { Write-Output ("  {0,-20} EXISTS" -f $t.Schema); continue }

    $body = @{
        '@odata.type'         = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName            = $t.Schema
        DisplayName           = New-Label $t.Display
        DisplayCollectionName = New-Label $t.Plural
        Description           = New-Label $t.Desc
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
        Write-Output ("  {0,-20} FAILED: {1}" -f $t.Schema, (($m -split "`n")[0]))
    } else { Write-Output ("  {0,-20} CREATED" -f $t.Schema) }
}

Write-Output ""
Write-Output "=== Attributes ==="
foreach ($t in $tables) {
    $logical = $t.Schema.ToLowerInvariant()
    $have = @{}
    $ex = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')/Attributes?`$select=LogicalName"
    if (-not ($ex.PSObject.Properties.Name -contains 'Ok')) { foreach ($a in $ex.value) { $have[$a.LogicalName]=$true } }

    $add=0; $skip=0
    foreach ($a in $t.Attributes) {
        if ($have.ContainsKey($a.s.ToLowerInvariant())) { $skip++; continue }
        $req = if ($a.req) { $a.req } else { 'None' }
        $b = @{ SchemaName=$a.s; DisplayName=(New-Label $a.l); RequiredLevel=@{Value=$req} }
        switch ($a.t) {
            'String'   { $b['@odata.type']='Microsoft.Dynamics.CRM.StringAttributeMetadata'; $b['MaxLength']=$a.max; $b['FormatName']=@{Value='Text'} }
            'Int'      { $b['@odata.type']='Microsoft.Dynamics.CRM.IntegerAttributeMetadata'; $b['MinValue']=-2147483648; $b['MaxValue']=2147483647; $b['Format']='None' }
            'Decimal'  { $b['@odata.type']='Microsoft.Dynamics.CRM.DecimalAttributeMetadata'; $b['MinValue']=-100000000000; $b['MaxValue']=100000000000; $b['Precision']=4 }
            'DateTime' { $b['@odata.type']='Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'; $b['Format']='DateAndTime'; $b['DateTimeBehavior']=@{Value='UserLocal'} }
            default    { throw "Unknown attribute type '$($a.t)'" }
        }
        $r = Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$logical')/Attributes" -Body $b -ExtraHeaders $solHeader
        if ($r.PSObject.Properties.Name -contains 'Ok') {
            $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
            Write-Output ("    {0}.{1} FAILED: {2}" -f $t.Schema,$a.s,(($m -split "`n")[0]))
        } else { $add++ }
    }
    Write-Output ("  {0,-20} added {1}  existing {2}" -f $t.Schema,$add,$skip)
}

$null = Invoke-Dv -Method POST -Path 'PublishAllXml' -Body @{}
Write-Output ""
Write-Output "published"
Write-Output ""
Write-Output "Next: tools\Sync-QmPoLineCache.ps1 to populate, then add 'PO Lines (cache)'"
Write-Output "as an app data source in Studio (Studio-only step)."
