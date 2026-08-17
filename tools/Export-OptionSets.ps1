# Export-OptionSets.ps1
# Phase 1: the Dataverse Web API returns virtual-entity enum columns as option-set
# integers, not the labels FetchXML shows. Every flow and screen that filters or
# writes an enum needs these mappings, so extract them once as a build artefact.
# ASCII-only per project standard.

param(
    [string[]]$Entities = @(
        'mserp_inventqualityorderheaderentity',
        'mserp_inventqualityorderlineresultentity',
        'mserp_inventnonconformancetableentity',
        'mserp_inventqualityorderlineentitypowerapp',
        'mserp_inventqualitytestgroupentity'
    )
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'dvlib.ps1')

$outDir = Join-Path (Split-Path -Parent $here) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$all = [ordered]@{}
$md  = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Phase 1 - Option set reference")
[void]$md.AppendLine("")
[void]$md.AppendLine("The Dataverse Web API returns these columns as integers. FetchXML returns labels.")
[void]$md.AppendLine("Any flow or Power Fx formula that filters or writes one of these must use the integer.")
[void]$md.AppendLine("")

foreach ($e in $Entities) {
    Write-Output "=== $e ==="
    $path = "EntityDefinitions(LogicalName='$e')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata" +
            "?`$select=LogicalName&`$expand=OptionSet(`$select=Options,Name)"
    $r = Invoke-Dv -Path $path

    if ($r.PSObject.Properties.Name -contains 'Ok') {
        Write-Output "  FAILED $($r.Status)"
        continue
    }
    if (-not $r.value -or $r.value.Count -eq 0) {
        Write-Output "  no picklist attributes"
        continue
    }

    $entMap = [ordered]@{}
    [void]$md.AppendLine("## ``$e``")
    [void]$md.AppendLine("")

    foreach ($a in ($r.value | Sort-Object LogicalName)) {
        if (-not $a.OptionSet -or -not $a.OptionSet.Options) { continue }
        $opts = [ordered]@{}
        foreach ($o in $a.OptionSet.Options) {
            $label = $null
            if ($o.Label -and $o.Label.UserLocalizedLabel) { $label = $o.Label.UserLocalizedLabel.Label }
            elseif ($o.Label -and $o.Label.LocalizedLabels -and $o.Label.LocalizedLabels.Count -gt 0) {
                $label = $o.Label.LocalizedLabels[0].Label
            }
            $opts["$($o.Value)"] = $label
        }
        if ($opts.Count -eq 0) { continue }

        $entMap[$a.LogicalName] = $opts
        Write-Output ("  {0,-52} {1} options" -f $a.LogicalName, $opts.Count)

        [void]$md.AppendLine("### ``$($a.LogicalName)``")
        [void]$md.AppendLine("")
        [void]$md.AppendLine("| Value | Label |")
        [void]$md.AppendLine("|---|---|")
        foreach ($k in $opts.Keys) {
            [void]$md.AppendLine("| ``$k`` | $($opts[$k]) |")
        }
        [void]$md.AppendLine("")
    }
    $all[$e] = $entMap
}

$all | ConvertTo-Json -Depth 8 | Out-File (Join-Path $outDir 'option-sets.json') -Encoding utf8
$md.ToString() | Out-File (Join-Path $outDir 'OPTION-SETS.md') -Encoding utf8

Write-Output ""
Write-Output "Written: option-sets.json, OPTION-SETS.md"
