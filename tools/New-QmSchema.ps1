# New-QmSchema.ps1
# Phase 2, task 11: create the Dataverse tables defined in schema.ps1.
#
# Idempotent -- skips tables, attributes and relationships that already exist.
# -WhatIf lists what would be created without touching the environment.
#
# ASCII-only per project standard.

param(
    [switch]$WhatIf,
    [switch]$SkipRelationships
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')
. (Join-Path $here 'schema.ps1')

$outDir = Join-Path (Split-Path -Parent $here) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$solHeader = @{ 'MSCRM.SolutionUniqueName' = $script:Solution }

function New-Label([string]$text) {
    @{ '@odata.type' = 'Microsoft.Dynamics.CRM.Label'
       LocalizedLabels = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = $text; LanguageCode = 1033 }) }
}

function New-AttributeBody($a) {
    $req = if ($a.req) { $a.req } else { 'None' }
    $base = @{
        SchemaName    = $a.s
        DisplayName   = New-Label $a.l
        RequiredLevel = @{ Value = $req }
    }
    switch ($a.t) {
        'String'   { $base['@odata.type'] = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
                     $base['MaxLength']   = $a.max
                     $base['FormatName']  = @{ Value = 'Text' } }
        'Memo'     { $base['@odata.type'] = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
                     $base['MaxLength']   = $a.max }
        'Int'      { $base['@odata.type'] = 'Microsoft.Dynamics.CRM.IntegerAttributeMetadata'
                     $base['MinValue']    = -2147483648; $base['MaxValue'] = 2147483647
                     $base['Format']      = 'None' }
        'Decimal'  { $base['@odata.type'] = 'Microsoft.Dynamics.CRM.DecimalAttributeMetadata'
                     $base['MinValue']    = -100000000000; $base['MaxValue'] = 100000000000
                     $base['Precision']   = 4 }
        'DateTime' { $base['@odata.type'] = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
                     $base['Format']      = 'DateAndTime'
                     $base['DateTimeBehavior'] = @{ Value = 'UserLocal' } }
        'File'     { $base['@odata.type'] = 'Microsoft.Dynamics.CRM.FileAttributeMetadata'
                     $base['MaxSizeInKB'] = 10240 }
        default    { throw "Unknown attribute type '$($a.t)'" }
    }
    return $base
}

# ------------------------------------------------------------------ 1. tables
Write-Output "=== Tables ==="
$created = New-Object System.Collections.Generic.List[object]

foreach ($t in $script:Tables) {
    $logical = $t.Schema.ToLowerInvariant()
    $exists  = $false
    $md = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')?`$select=LogicalName"
    if (-not ($md.PSObject.Properties.Name -contains 'Ok')) { $exists = $true }

    if ($exists) { Write-Output ("  {0,-24} EXISTS" -f $t.Schema); continue }
    if ($WhatIf) { Write-Output ("  {0,-24} would create ({1} attributes)" -f $t.Schema, $t.Attributes.Count); continue }

    # The primary name attribute must be supplied inline at creation time.
    $primary = @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        SchemaName    = $t.PrimaryName
        MaxLength     = 200
        IsPrimaryName = $true
        RequiredLevel = @{ Value = 'ApplicationRequired' }
        DisplayName   = New-Label $t.PrimaryLabel
    }

    $body = @{
        '@odata.type'          = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName             = $t.Schema
        DisplayName            = New-Label $t.Display
        DisplayCollectionName  = New-Label $t.Plural
        Description            = New-Label $t.Description
        OwnershipType          = 'UserOwned'
        HasActivities          = $false
        HasNotes               = $false
        IsActivity             = $false
        PrimaryNameAttribute   = $t.PrimaryName.ToLowerInvariant()
        Attributes             = @($primary)
    }

    $r = Invoke-Dv -Method POST -Path 'EntityDefinitions' -Body $body -ExtraHeaders $solHeader
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Detail }
        Write-Output ("  {0,-24} FAILED: {1}" -f $t.Schema, (($m -split "`n")[0]))
        continue
    }
    Write-Output ("  {0,-24} CREATED" -f $t.Schema)
    $created.Add($t.Schema)
}

if ($WhatIf) { Write-Output "`n-WhatIf specified. No changes made."; return }

# ------------------------------------------------------------------ 2. attributes
Write-Output ""
Write-Output "=== Attributes ==="
foreach ($t in $script:Tables) {
    $logical = $t.Schema.ToLowerInvariant()
    $have = @{}
    $ex = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')/Attributes?`$select=LogicalName"
    if (-not ($ex.PSObject.Properties.Name -contains 'Ok')) {
        foreach ($a in $ex.value) { $have[$a.LogicalName] = $true }
    }

    $add = 0; $skip = 0; $fail = 0
    foreach ($a in $t.Attributes) {
        if ($have.ContainsKey($a.s.ToLowerInvariant())) { $skip++; continue }
        $body = New-AttributeBody $a
        $r = Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$logical')/Attributes" -Body $body -ExtraHeaders $solHeader
        if ($r.PSObject.Properties.Name -contains 'Ok') {
            $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Status }
            Write-Output ("    {0}.{1} FAILED: {2}" -f $t.Schema, $a.s, (($m -split "`n")[0]))
            $fail++
        } else { $add++ }
    }
    Write-Output ("  {0,-24} added {1,2}  existing {2,2}  failed {3}" -f $t.Schema, $add, $skip, $fail)
}

# ------------------------------------------------------------------ 3. relationships
if (-not $SkipRelationships) {
    Write-Output ""
    Write-Output "=== Relationships ==="
    foreach ($rel in $script:Relationships) {
        $chk = Invoke-Dv -Path "RelationshipDefinitions(SchemaName='$($rel.Name)')?`$select=SchemaName"
        if (-not ($chk.PSObject.Properties.Name -contains 'Ok')) {
            Write-Output ("  {0,-38} EXISTS" -f $rel.Name); continue
        }

        $body = @{
            '@odata.type'        = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
            SchemaName           = $rel.Name
            ReferencedEntity     = $rel.Referenced
            ReferencingEntity    = $rel.Referencing
            CascadeConfiguration = @{ Assign='NoCascade'; Delete='RemoveLink'; Merge='NoCascade'
                                      Reparent='NoCascade'; Share='NoCascade'; Unshare='NoCascade' }
            Lookup = @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata'
                SchemaName    = $rel.Lookup
                DisplayName   = New-Label $rel.LookupLabel
                RequiredLevel = @{ Value = 'None' }
            }
            AssociatedMenuConfiguration = @{ Behavior='UseCollectionName'; Group='Details'; Order=10000 }
        }

        $r = Invoke-Dv -Method POST -Path 'RelationshipDefinitions' -Body $body -ExtraHeaders $solHeader
        if ($r.PSObject.Properties.Name -contains 'Ok') {
            $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Status }
            Write-Output ("  {0,-38} FAILED: {1}" -f $rel.Name, (($m -split "`n")[0]))
        } else { Write-Output ("  {0,-38} CREATED" -f $rel.Name) }
    }
}

# ------------------------------------------------------------------ 4. publish
Write-Output ""
Write-Output "=== Publishing customizations ==="
$p = Invoke-Dv -Method POST -Path 'PublishAllXml' -Body @{}
if ($p.PSObject.Properties.Name -contains 'Ok') { Write-Output "  publish returned $($p.Status)" } else { Write-Output "  published" }

# ------------------------------------------------------------------ 5. verify
Write-Output ""
Write-Output "=== Verification ==="
foreach ($t in $script:Tables) {
    $logical = $t.Schema.ToLowerInvariant()
    $md = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')?`$select=LogicalName,EntitySetName"
    if ($md.PSObject.Properties.Name -contains 'Ok') { Write-Output ("  {0,-24} MISSING" -f $t.Schema); continue }
    $at = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')/Attributes?`$select=LogicalName"
    $custom = @($at.value | Where-Object { $_.LogicalName -like 'cog_*' }).Count
    Write-Output ("  {0,-24} OK  set={1,-28} cog_ columns={2}" -f $t.Schema, $md.EntitySetName, $custom)
}
