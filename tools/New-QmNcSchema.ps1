# New-QmNcSchema.ps1
# Cache tables the Create NC screen needs.
#
# The screen needs a problem-type picker and a vendor/customer account picker. Reading those
# straight from the mserp_ virtual tables would mean adding them as app data sources, which
# can only be done in Studio -- and would also make NC creation require connectivity, against
# D-02. Caching them in cog_ tables keeps the pattern consistent and offline-capable.
#
# Items do not need a new table: the NC screen sources them from cog_qualityorder, which is
# already cached, and an internal NC is raised against a quality order anyway.
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
  @{ Schema='cog_ProblemType'; Display='Problem Type (cache)'; Plural='Problem Types (cache)'
     Desc='Cached F&O non-conformance problem types. F&O restricts which are valid per NC type and exposes no mapping, so the app offers all and surfaces the rejection.'
     Attributes=@(
       @{t='String'; s='cog_ProblemTypeId'; l='Problem type'; max=30; req='ApplicationRequired'}
       @{t='String'; s='cog_Company';       l='Company';      max=4;  req='ApplicationRequired'}
       @{t='String'; s='cog_Description';   l='Description';  max=100}
       @{t='DateTime'; s='cog_SynchronizedOn'; l='Synchronized on'}
     )}
  @{ Schema='cog_Account'; Display='Account (cache)'; Plural='Accounts (cache)'
     Desc='Cached customer and vendor accounts for the non-conformance pickers.'
     Attributes=@(
       @{t='String'; s='cog_AccountNumber'; l='Account number'; max=20; req='ApplicationRequired'}
       @{t='String'; s='cog_AccountName';   l='Name';           max=100}
       @{t='Int';    s='cog_AccountKind';   l='Kind'}
       @{t='String'; s='cog_Company';       l='Company';        max=4;  req='ApplicationRequired'}
       @{t='DateTime'; s='cog_SynchronizedOn'; l='Synchronized on'}
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
            'DateTime' { $b['@odata.type']='Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'; $b['Format']='DateAndTime'; $b['DateTimeBehavior']=@{Value='UserLocal'} }
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

# ---------------------------------------------------------------- populate
Write-Output ""
Write-Output "=== Populating problem types ==="
$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$pt = Invoke-Dv -Path "mserp_inventproblemtypedataentities?`$select=mserp_problemtypeid,mserp_description,mserp_dataareaid&`$top=200"
$n=0
foreach ($p in $pt.value) {
    $f = "cog_problemtypeid eq '$($p.mserp_problemtypeid)' and cog_company eq '$($p.mserp_dataareaid)'"
    $ex = Invoke-Dv -Path "cog_problemtypes?`$select=cog_problemtypeid&`$filter=$f&`$top=1"
    if (@($ex.value).Count -gt 0) { continue }
    $body = @{ cog_name="$($p.mserp_dataareaid) | $($p.mserp_problemtypeid)"; cog_problemtypeid=$p.mserp_problemtypeid
               cog_company=$p.mserp_dataareaid; cog_description=$p.mserp_description; cog_synchronizedon=$now }
    $r = Invoke-Dv -Method POST -Path 'cog_problemtypes' -Body $body
    if (-not ($r.PSObject.Properties.Name -contains 'Ok')) { $n++ }
}
Write-Output "  $n problem types cached"

Write-Output ""
Write-Output "=== Populating accounts ==="
# Kind: 1 = customer, 2 = vendor
$c = Invoke-Dv -Path "mserp_powerappscusttableentities?`$select=mserp_customeraccount,mserp_organizationname,mserp_dataareaid&`$top=300"
$cn=0
if (-not ($c.PSObject.Properties.Name -contains 'Ok')) {
    foreach ($x in $c.value) {
        if (-not $x.mserp_customeraccount) { continue }
        $f = "cog_accountnumber eq '$($x.mserp_customeraccount)' and cog_company eq '$($x.mserp_dataareaid)' and cog_accountkind eq 1"
        if (@((Invoke-Dv -Path "cog_accounts?`$select=cog_accountnumber&`$filter=$f&`$top=1").value).Count -gt 0) { continue }
        $r = Invoke-Dv -Method POST -Path 'cog_accounts' -Body @{
            cog_name="$($x.mserp_dataareaid) | C | $($x.mserp_customeraccount)"; cog_accountnumber=$x.mserp_customeraccount
            cog_accountname=$x.mserp_organizationname; cog_accountkind=1; cog_company=$x.mserp_dataareaid; cog_synchronizedon=$now }
        if (-not ($r.PSObject.Properties.Name -contains 'Ok')) { $cn++ }
    }
} else { Write-Output "  customer read failed: $($c.Status)" }
Write-Output "  $cn customers cached"

$v = Invoke-Dv -Path "mserp_vendvendorv2entities?`$select=mserp_vendoraccountnumber,mserp_vendororganizationname,mserp_dataareaid&`$top=300"
$vn=0
if (-not ($v.PSObject.Properties.Name -contains 'Ok')) {
    foreach ($x in $v.value) {
        if (-not $x.mserp_vendoraccountnumber) { continue }
        $f = "cog_accountnumber eq '$($x.mserp_vendoraccountnumber)' and cog_company eq '$($x.mserp_dataareaid)' and cog_accountkind eq 2"
        if (@((Invoke-Dv -Path "cog_accounts?`$select=cog_accountnumber&`$filter=$f&`$top=1").value).Count -gt 0) { continue }
        $r = Invoke-Dv -Method POST -Path 'cog_accounts' -Body @{
            cog_name="$($x.mserp_dataareaid) | V | $($x.mserp_vendoraccountnumber)"; cog_accountnumber=$x.mserp_vendoraccountnumber
            cog_accountname=$x.mserp_vendororganizationname; cog_accountkind=2; cog_company=$x.mserp_dataareaid; cog_synchronizedon=$now }
        if (-not ($r.PSObject.Properties.Name -contains 'Ok')) { $vn++ }
    }
} else { Write-Output "  vendor read failed: $($v.Status)" }
Write-Output "  $vn vendors cached"
