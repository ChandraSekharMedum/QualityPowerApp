# Test-GeneratedEntities.ps1
# Phase 1, task 3: confirm each generated virtual table exists, returns data,
# and record its field shape as a build reference.
#
# Virtual table logical name convention (confirmed against the environment):
#   mserp_<lowercased mserp_physicalname>
#
# ASCII-only per project standard.

param(
    [int]$SampleRows = 3,
    [switch]$IncludeAlreadyGenerated
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'dvlib.ps1')
. (Join-Path $here 'entity-targets.ps1')

$outDir = Join-Path (Split-Path -Parent $here) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

# Entities already generated before Phase 1 -- included for completeness of the reference.
$preExisting = @(
    'InventQualityOrderHeaderEntity','InventQualityOrderLineResultEntity',
    'INVENTNONCONFORMANCETABLEENTITY','POWERAPPSINVENTQUARANTINEORDERENTITY',
    'POWERAPPITEMBATCHTRACINGENTITY','VendVendorV2Entity'
)

$names = $script:EntityTargets | ForEach-Object { $_.Name }
if ($IncludeAlreadyGenerated) { $names = @($preExisting) + $names }

Write-Output "Verifying $($names.Count) virtual tables..."
Write-Output ""

$report = New-Object System.Collections.Generic.List[object]
$shapes = [ordered]@{}

foreach ($n in $names) {
    $logical = 'mserp_' + $n.ToLowerInvariant()
    # OData entity set name is the logical name pluralised by the provider.
    $set     = $logical + 's'

    $row = [ordered]@{
        Entity      = $n
        LogicalName = $logical
        Exists      = $false
        Queryable   = $false
        RowsSampled = 0
        FieldCount  = 0
        Companies   = ''
        Note        = ''
    }

    # Does the table exist in metadata?
    $md = Invoke-Dv -Path "EntityDefinitions(LogicalName='$logical')?`$select=LogicalName,EntitySetName,IsValidForAdvancedFind"
    if ($md.PSObject.Properties.Name -contains 'Ok') {
        $row.Note = "metadata missing (status $($md.Status)) - generation may still be in flight"
        $report.Add([pscustomobject]$row); continue
    }
    $row.Exists = $true
    if ($md.EntitySetName) { $set = $md.EntitySetName }

    # Can it be queried, and does it return data?
    $q = Invoke-Dv -Path "$set`?`$top=$SampleRows"
    if ($q.PSObject.Properties.Name -contains 'Ok') {
        $row.Note = "query failed: $($q.Status) $(($q.Detail -replace '\s+',' ').Substring(0,[Math]::Min(180,$q.Detail.Length)))"
        $report.Add([pscustomobject]$row); continue
    }

    $row.Queryable   = $true
    $row.RowsSampled = @($q.value).Count

    if ($row.RowsSampled -gt 0) {
        $fields = $q.value[0].PSObject.Properties.Name |
                  Where-Object { $_ -notlike '@odata*' } | Sort-Object
        $row.FieldCount = $fields.Count
        $shapes[$logical] = $fields

        $co = $q.value | ForEach-Object { $_.mserp_dataareaid } |
              Where-Object { $_ } | Select-Object -Unique
        $row.Companies = ($co -join ',')
    } else {
        $row.Note = 'table exists and queries OK but returned no rows'
    }

    $report.Add([pscustomobject]$row)
    Write-Output ("  {0,-52} {1,-9} {2,3} rows {3,4} fields {4}" -f `
        $n.Substring(0,[Math]::Min(52,$n.Length)),
        $(if($row.Queryable){'OK'}else{'FAIL'}),
        $row.RowsSampled, $row.FieldCount, $row.Note)
}

Write-Output ""
Write-Output "Exists    : $(($report | Where-Object Exists).Count) / $($report.Count)"
Write-Output "Queryable : $(($report | Where-Object Queryable).Count) / $($report.Count)"
Write-Output "With data : $(($report | Where-Object {$_.RowsSampled -gt 0}).Count) / $($report.Count)"

$report | ConvertTo-Json -Depth 4 | Out-File (Join-Path $outDir 'entity-verification.json') -Encoding utf8
$shapes | ConvertTo-Json -Depth 4 | Out-File (Join-Path $outDir 'entity-field-shapes.json') -Encoding utf8

# Human-readable field reference for the build team
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Phase 1 - Virtual table field reference")
[void]$md.AppendLine("")
[void]$md.AppendLine("Generated from live queries against cus-con-sandbox.")
[void]$md.AppendLine("")
foreach ($k in $shapes.Keys) {
    [void]$md.AppendLine("## ``$k``")
    [void]$md.AppendLine("")
    [void]$md.AppendLine('`' + ($shapes[$k] -join '`, `') + '`')
    [void]$md.AppendLine("")
}
$md.ToString() | Out-File (Join-Path $outDir 'FIELD-REFERENCE.md') -Encoding utf8

Write-Output ""
Write-Output "Written: entity-verification.json, entity-field-shapes.json, FIELD-REFERENCE.md"
