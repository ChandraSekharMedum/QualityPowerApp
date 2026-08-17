# New-QmSyncLinesFlow.ps1
# The scheduled test-line cache refresh.
#
#   trigger : recurrence
#   1 List test lines from the F&O virtual table (carries the tolerance bounds)
#   2 For each:
#       a find the cached line
#       b find the matching F&O result row to capture its id (the submit target)
#       c update or create
#
# Kept as a SEPARATE flow from cog_QM_SyncCache rather than bolted on: the clientdata stays
# debuggable, and a line-sync failure does not stop headers refreshing.
#
# The parent lookup (cog_QualityOrderId) is deliberately NOT populated here. The app filters
# lines by cog_qualityordernumber + cog_company, not by the relationship, so binding it would
# cost an extra lookup per row for no functional gain. Lines created by the script sync keep
# their lookup; lines created by this flow leave it empty.
#
# EXPRESSION GOTCHA: never build these with PowerShell string interpolation --
# "$var?['field']" parses as an index operation, drops the items(...) prefix, and the flow
# fails to activate with "expected token 'Identifier' and actual 'LeftSquareBracket'".
#
# ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$FlowName     = 'cog_QM_SyncTestLines',
    [string]$ConnRefName  = 'cog_QMConnRef_Dataverse',
    [int]$IntervalMinutes = 15,
    [int]$MaxRows         = 500
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')
$solHeader = @{ 'MSCRM.SolutionUniqueName' = $SolutionName }

$cr = Invoke-Dv -Path "connectionreferences?`$select=connectionreferenceid&`$filter=connectionreferencelogicalname eq '$ConnRefName'"
if (@($cr.value).Count -eq 0) { throw "$ConnRefName not found." }

$dvHost = [ordered]@{
    connectionName          = $ConnRefName
    connectionReferenceName = $ConnRefName
    apiId                   = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
}

function SrcRef([string]$f)    { return "@items('Apply_to_each_line')?[" + "'" + $f + "'" + "]" }
function SrcRefRaw([string]$f) { return "items('Apply_to_each_line')?[" + "'" + $f + "'" + "]" }

# Natural key filter: order + test + sequence + company
$lineFilter = "@concat('cog_qualityordernumber eq ''', " + (SrcRefRaw 'mserp_qualityorderid') +
              ", ''' and cog_testid eq ''', " + (SrcRefRaw 'mserp_testid') +
              ", ''' and cog_testsequence eq ', string(" + (SrcRefRaw 'mserp_testsequence') +
              "), ' and cog_company eq ''', " + (SrcRefRaw 'mserp_dataareaid') + ", '''')"

# The F&O result row that a submitted value is written to
$targetFilter = "@concat('mserp_qualityordernumber eq ''', " + (SrcRefRaw 'mserp_qualityorderid') +
                ", ''' and mserp_qualitytestid eq ''', " + (SrcRefRaw 'mserp_testid') +
                ", ''' and mserp_qualityordersequencenumber eq ', string(" + (SrcRefRaw 'mserp_testsequence') +
                "), ' and mserp_dataareaid eq ''', " + (SrcRefRaw 'mserp_dataareaid') + ", '''')"

$targetId = "@if(greater(length(outputs('Find_the_F_and_O_result_row')?['body/value']), 0), first(outputs('Find_the_F_and_O_result_row')?['body/value'])?['mserp_inventqualityorderlineresultentityid'], '')"

$mapping = [ordered]@{
    'item/cog_lowerlimit'       = (SrcRef 'mserp_lowerlimit')
    'item/cog_upperlimit'       = (SrcRef 'mserp_upperlimit')
    'item/cog_standardvalue'    = (SrcRef 'mserp_standardvalue')
    'item/cog_testinstrumentid' = (SrcRef 'mserp_testinstrumentid')
    'item/cog_testunitid'       = (SrcRef 'mserp_testunitid')
    'item/cog_variableid'       = (SrcRef 'mserp_variableid')
    'item/cog_currentresult'    = (SrcRef 'mserp_testresult')
    'item/cog_currentvalue'     = (SrcRef 'mserp_pdsorderlineresult')
    'item/cog_targetrecordid'   = $targetId
    'item/cog_synchronizedon'   = '@utcNow()'
}

$createMapping = [ordered]@{
    'item/cog_name'                = ("@concat(" + (SrcRefRaw 'mserp_qualityorderid') + ", ' | ', string(" + (SrcRefRaw 'mserp_testsequence') + "), ' | ', " + (SrcRefRaw 'mserp_testid') + ")")
    'item/cog_qualityordernumber'  = (SrcRef 'mserp_qualityorderid')
    'item/cog_testid'              = (SrcRef 'mserp_testid')
    'item/cog_testsequence'        = (SrcRef 'mserp_testsequence')
    'item/cog_company'             = (SrcRef 'mserp_dataareaid')
}
foreach ($k in $mapping.Keys) { $createMapping[$k] = $mapping[$k] }

$updateParams = [ordered]@{
    entityName = 'cog_qualitytestlines'
    recordId   = "@first(outputs('Find_the_cached_line')?['body/value'])?['cog_qualitytestlineid']"
}
foreach ($k in $mapping.Keys) { $updateParams[$k] = $mapping[$k] }

$createParams = [ordered]@{ entityName = 'cog_qualitytestlines' }
foreach ($k in $createMapping.Keys) { $createParams[$k] = $createMapping[$k] }

$definition = [ordered]@{
    '$schema'      = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
    contentVersion = '1.0.0.0'
    parameters     = [ordered]@{
        "`$connections"    = [ordered]@{ defaultValue = @{}; type = 'Object' }
        "`$authentication" = [ordered]@{ defaultValue = @{}; type = 'SecureObject' }
    }
    triggers = [ordered]@{
        Every_15_minutes = [ordered]@{
            type       = 'Recurrence'
            recurrence = [ordered]@{ frequency = 'Minute'; interval = $IntervalMinutes }
        }
    }
    actions = [ordered]@{

        List_test_lines_from_F_and_O = [ordered]@{
            runAfter = [ordered]@{}
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                parameters = [ordered]@{
                    entityName = 'mserp_powerappinventqolineentities'
                    '$select'  = 'mserp_qualityorderid,mserp_testid,mserp_testsequence,mserp_dataareaid,mserp_lowerlimit,mserp_upperlimit,mserp_standardvalue,mserp_testinstrumentid,mserp_testunitid,mserp_variableid,mserp_testresult,mserp_pdsorderlineresult'
                    '$top'     = $MaxRows
                }
            }
        }

        Apply_to_each_line = [ordered]@{
            runAfter = [ordered]@{ List_test_lines_from_F_and_O = @('Succeeded') }
            type     = 'Foreach'
            foreach  = "@outputs('List_test_lines_from_F_and_O')?['body/value']"
            runtimeConfiguration = [ordered]@{ concurrency = [ordered]@{ repetitions = 1 } }
            actions  = [ordered]@{

                Find_the_cached_line = [ordered]@{
                    runAfter = [ordered]@{}
                    type     = 'OpenApiConnection'
                    inputs   = [ordered]@{
                        host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                        parameters = [ordered]@{
                            entityName = 'cog_qualitytestlines'
                            '$select'  = 'cog_qualitytestlineid'
                            '$filter'  = $lineFilter
                            '$top'     = 1
                        }
                    }
                }

                Find_the_F_and_O_result_row = [ordered]@{
                    runAfter = [ordered]@{ Find_the_cached_line = @('Succeeded') }
                    type     = 'OpenApiConnection'
                    inputs   = [ordered]@{
                        host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                        parameters = [ordered]@{
                            entityName = 'mserp_inventqualityorderlineresultentities'
                            '$select'  = 'mserp_inventqualityorderlineresultentityid'
                            '$filter'  = $targetFilter
                            '$top'     = 1
                        }
                    }
                }

                Cached_line_exists = [ordered]@{
                    runAfter = [ordered]@{ Find_the_F_and_O_result_row = @('Succeeded') }
                    type     = 'If'
                    expression = [ordered]@{
                        greater = @("@length(outputs('Find_the_cached_line')?['body/value'])", 0)
                    }
                    actions = [ordered]@{
                        Update_the_cached_line = [ordered]@{
                            runAfter = [ordered]@{}
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                                parameters = $updateParams
                            }
                        }
                    }
                    else = [ordered]@{
                        actions = [ordered]@{
                            Create_the_cached_line = [ordered]@{
                                runAfter = [ordered]@{}
                                type     = 'OpenApiConnection'
                                inputs   = [ordered]@{
                                    host       = ($dvHost + [ordered]@{ operationId = 'CreateRecord' })
                                    parameters = $createParams
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

$clientData = [ordered]@{
    schemaVersion = '1.0.0.0'
    properties    = [ordered]@{
        connectionReferences = [ordered]@{
            $ConnRefName = [ordered]@{
                runtimeSource = 'embedded'
                connection    = [ordered]@{ connectionReferenceLogicalName = $ConnRefName }
                api           = [ordered]@{ name = 'shared_commondataserviceforapps' }
            }
        }
        definition  = $definition
        displayName = 'QM - Sync Test Lines'
    }
}
$cdJson = $clientData | ConvertTo-Json -Depth 60 -Compress
Write-Output "clientdata length: $($cdJson.Length)"

$fx = Invoke-Dv -Path "workflows?`$select=workflowid&`$filter=name eq '$FlowName'"
if (@($fx.value).Count -gt 0) {
    $flowId = $fx.value[0].workflowid
    Write-Output "EXISTS -- deactivating to patch"
    $null = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ statecode = 0; statuscode = 1 }
    Start-Sleep -Seconds 3
    $r = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ clientdata = $cdJson }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Detail }
        Write-Output "PATCH FAILED: $(($m -split "`n")[0])"; throw "clientdata patch failed"
    }
    Write-Output "  patched"
} else {
    $wf = @{
        name = $FlowName; description = 'Refreshes cached test lines and their tolerance bounds from F&O.'
        category = 5; primaryentity = 'none'; type = 1; statecode = 0; statuscode = 1; clientdata = $cdJson
    }
    $r = Invoke-Dv -Method POST -Path 'workflows' -Body $wf -Prefer 'return=representation' -ExtraHeaders $solHeader
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Detail }
        Write-Output "CREATE FAILED $($r.Status): $(($m -split "`n")[0])"; throw "Flow creation failed."
    }
    $flowId = $r.workflowid
    Write-Output "CREATED id=$flowId"
}

Start-Sleep -Seconds 3
Write-Output ""
Write-Output "=== activating ==="
for ($i=1; $i -le 3; $i++) {
    $r = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ statecode = 1; statuscode = 2 }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Status }
        Write-Output "  attempt $i failed: $(($m -split "`n")[0])"
        Start-Sleep -Seconds 4
    } else { Write-Output "  ACTIVATED"; break }
}

$final = Invoke-Dv -Path "workflows($flowId)?`$select=name,statecode,statuscode"
Write-Output ""
Write-Output ("RESULT: {0}  {1}/{2}" -f $final.name, $final.statecode, $final.statuscode)
