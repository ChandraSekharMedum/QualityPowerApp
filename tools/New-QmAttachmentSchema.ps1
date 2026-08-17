# New-QmAttachmentSchema.ps1
# cog_Attachment -- photos captured against a quality order test result, held locally until the
# outbox drains them into F&O.
#
# WHY THE PAYLOAD IS A TEXT COLUMN, NOT A FILE OR IMAGE COLUMN
#
# The F&O target (POWERAPPFILESAVINGENTITY.mserp_imagevarchar) takes base64 TEXT. Storing the
# photo as a Dataverse file column would mean the flow has to download the binary and re-encode
# it, adding a failure point for no gain. A text column also survives offline cleanly, which
# file columns do not reliably do -- and D-02 requires capture to work offline.
#
# THE SIZE CAP IS EXACT AND IT IS THE DESIGN CONSTRAINT
#
# Probed 2026-08-17: F&O accepts 1,048,576 base64 characters and rejects 1 more with
# "The length of the 'mserp_imagevarchar' attribute ... exceeded the maximum allowed length".
# That is 1 MiB of base64, so roughly 786 KB of image. Dataverse memo columns cap at exactly the
# same 1,048,576, so cog_Base64 is sized to match and the app checks the length before queuing
# rather than letting F&O reject it after the inspector has walked away.
#
# STAGED ROWS DISAPPEAR ONCE F&O PROCESSES THEM, so the staging entity is not a source of truth
# for "what is attached". That is why this table keeps its own record.
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

$schema  = 'cog_Attachment'
$logical = 'cog_attachment'

# Status mirrors cog_outboxstatus so the two never need translating:
#   1 Draft  2 Queued  3 Submitting  4 Confirmed  5 Needs attention  6 Duplicate
$attributes = @(
    @{t='String';   s='cog_QualityOrderNumber'; l='Quality order';   max=20;  req='ApplicationRequired'}
    @{t='String';   s='cog_Company';            l='Company';         max=4;   req='ApplicationRequired'}
    @{t='String';   s='cog_TestId';             l='Test';            max=60}
    @{t='Int';      s='cog_TestSequence';       l='Test sequence'}
    @{t='Int';      s='cog_LineNum';            l='Line number'}
    @{t='String';   s='cog_FileName';           l='File name';       max=100}
    @{t='Memo';     s='cog_Base64';             l='Image (base64)';  max=1048576}
    @{t='Int';      s='cog_SizeChars';          l='Base64 length'}
    @{t='String';   s='cog_CorrelationId';      l='Correlation id';  max=50}
    @{t='Int';      s='cog_AttachStatus';       l='Status'}
    @{t='DateTime'; s='cog_CapturedOn';         l='Captured on'}
)

Write-Output "=== Table ==="
$md = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')?`$select=LogicalName"
if (-not ($md.PSObject.Properties.Name -contains 'Ok')) {
    Write-Output "  $schema EXISTS"
} else {
    $body = @{
        '@odata.type'         = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName            = $schema
        DisplayName           = New-Label 'Attachment (draft)'
        DisplayCollectionName = New-Label 'Attachments (draft)'
        Description           = New-Label 'Photos captured against a quality order test result. Held here until the outbox drains them into POWERAPPFILESAVINGENTITY. Base64 is capped at 1048576 characters to match what F&O accepts.'
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
    $r = $null
    for ($k = 1; $k -le 4; $k++) {
        $r = Invoke-Dv -Method POST -Path 'EntityDefinitions' -Body $body -ExtraHeaders $solHeader
        if (-not ($r.PSObject.Properties.Name -contains 'Ok')) { break }
        Write-Output "    create attempt $k failed, retrying"
        Start-Sleep -Seconds 12
    }
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
        # No IsValidForAdvancedFind here -- it is a BooleanManagedProperty (an object), not a
        # primitive, and passing false gets "A 'PrimitiveValue' node with non-null value was found
        # ... a 'StartObject' node was expected".
        'Memo'     { $b['@odata.type']='Microsoft.Dynamics.CRM.MemoAttributeMetadata'; $b['MaxLength']=$a.max; $b['Format']='Text' }
        'Int'      { $b['@odata.type']='Microsoft.Dynamics.CRM.IntegerAttributeMetadata'; $b['MinValue']=-2147483648; $b['MaxValue']=2147483647; $b['Format']='None' }
        'DateTime' { $b['@odata.type']='Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'; $b['Format']='DateAndTime'; $b['DateTimeBehavior']=@{Value='UserLocal'} }
    }
    # Metadata writes intermittently return "An unexpected error occurred" when operations
    # overlap. Retry -- a missing column silently breaks whatever reads it.
    $r = $null
    for ($k = 1; $k -le 4; $k++) {
        $r = Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$logical')/Attributes" -Body $b -ExtraHeaders $solHeader
        if (-not ($r.PSObject.Properties.Name -contains 'Ok')) { break }
        Write-Output ("    {0} attempt {1} failed, retrying" -f $a.s,$k)
        Start-Sleep -Seconds 12
    }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
        throw "$schema.$($a.s) could not be created: $(($m -split "`n")[0])"
    }
    $add++
}
Write-Output ("  added {0}  existing {1}" -f $add,$skip)

$null = Invoke-Dv -Method POST -Path 'PublishAllXml' -Body @{}
Write-Output ""
Write-Output "published"
Write-Output ""
Write-Output "Add 'Attachments (draft)' as an app data source in Studio -- that step is Studio-only."
