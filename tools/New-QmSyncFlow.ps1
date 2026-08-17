# New-QmSyncFlow.ps1
# Phase 2, task 12: the scheduled cache sync flow.
#
#   trigger : recurrence
#   1 List quality orders from the F&O virtual table
#   2 For each -> look for a cached row
#       found     -> update it
#       not found -> create it
#
# Carries the same field mapping as Sync-QmCache.ps1, which is already proven against real
# data. Starts with quality order headers only; test lines are added once the recurrence
# trigger is confirmed to arm, the same way the drain flow was built up.
#
# OPEN QUESTION this flow answers: Dataverse webhook triggers self-arm without the PA
# /start call. Whether a Recurrence trigger does the same is unknown -- api.flow.microsoft.com
# is unreachable from here, so if it does not arm, that is a finding rather than a fix.
#
# ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$FlowName     = 'cog_QM_SyncCache',
    [string]$ConnRefName  = 'cog_QMConnRef_Dataverse',
    [int]$IntervalMinutes = 15,
    [int]$MaxRows         = 200
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')
$solHeader = @{ 'MSCRM.SolutionUniqueName' = $SolutionName }

$cr = Invoke-Dv -Path "connectionreferences?`$select=connectionreferenceid&`$filter=connectionreferencelogicalname eq '$ConnRefName'"
if (@($cr.value).Count -eq 0) { throw "$ConnRefName not found. Run New-QmDrainFlow.ps1 first." }
Write-Output "Using connection reference $ConnRefName"

$dvHost = [ordered]@{
    connectionName          = $ConnRefName
    connectionReferenceName = $ConnRefName
    apiId                   = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
}

# GOTCHA: do NOT build these expressions with PowerShell string interpolation.
# "$srcItem?['field']" is parsed as an INDEX operation on $srcItem, which silently drops the
# items(...) prefix and produces concat(..., ['field'], ...) -- the flow then fails to
# activate with "expected token 'Identifier' and actual 'LeftSquareBracket'".
# Build them by concatenation instead.
function SrcRef([string]$field) {
    return "@items('Apply_to_each_order')?[" + "'" + $field + "'" + "]"
}
function SrcRefRaw([string]$field) {
    # same, without the leading @ -- for use inside a larger expression
    return "items('Apply_to_each_order')?[" + "'" + $field + "'" + "]"
}

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

        List_quality_orders_from_F_and_O = [ordered]@{
            runAfter = [ordered]@{}
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                parameters = [ordered]@{
                    entityName = 'mserp_inventqualityorderheaderentities'
                    '$select'  = 'mserp_qualityordernumber,mserp_dataareaid,mserp_itemnumber,mserp_productname,mserp_qualitytestgroupid,mserp_referencetype,mserp_inventoryquantity,mserp_inventorysiteid,mserp_warehouseid,mserp_itembatchnumber,mserp_qualityorderstatus'
                    '$top'     = $MaxRows
                }
            }
        }

        Apply_to_each_order = [ordered]@{
            runAfter = [ordered]@{ List_quality_orders_from_F_and_O = @('Succeeded') }
            type     = 'Foreach'
            foreach  = "@outputs('List_quality_orders_from_F_and_O')?['body/value']"
            runtimeConfiguration = [ordered]@{ concurrency = [ordered]@{ repetitions = 1 } }
            actions  = [ordered]@{

                Find_cached_order = [ordered]@{
                    runAfter = [ordered]@{}
                    type     = 'OpenApiConnection'
                    inputs   = [ordered]@{
                        host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                        parameters = [ordered]@{
                            entityName = 'cog_qualityorders'
                            '$select'  = 'cog_qualityorderid'
                            '$filter'  = ("@concat('cog_qualityordernumber eq ''', " + (SrcRefRaw 'mserp_qualityordernumber') + ", ''' and cog_company eq ''', " + (SrcRefRaw 'mserp_dataareaid') + ", '''')")
                            '$top'     = 1
                        }
                    }
                }

                Cached_row_exists = [ordered]@{
                    runAfter = [ordered]@{ Find_cached_order = @('Succeeded') }
                    type     = 'If'
                    expression = [ordered]@{
                        greater = @("@length(outputs('Find_cached_order')?['body/value'])", 0)
                    }
                    actions = [ordered]@{
                        Update_cached_order = [ordered]@{
                            runAfter = [ordered]@{}
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                                parameters = [ordered]@{
                                    entityName                   = 'cog_qualityorders'
                                    recordId                     = "@first(outputs('Find_cached_order')?['body/value'])?['cog_qualityorderid']"
                                    'item/cog_itemnumber'        = (SrcRef 'mserp_itemnumber')
                                    'item/cog_productname'       = (SrcRef 'mserp_productname')
                                    'item/cog_testgroupid'       = (SrcRef 'mserp_qualitytestgroupid')
                                    'item/cog_referencetype'     = (SrcRef 'mserp_referencetype')
                                    'item/cog_inventoryquantity' = (SrcRef 'mserp_inventoryquantity')
                                    'item/cog_siteid'            = (SrcRef 'mserp_inventorysiteid')
                                    'item/cog_warehouseid'       = (SrcRef 'mserp_warehouseid')
                                    'item/cog_batchnumber'       = (SrcRef 'mserp_itembatchnumber')
                                    'item/cog_status'            = (SrcRef 'mserp_qualityorderstatus')
                                    'item/cog_synchronizedon'    = '@utcNow()'
                                }
                            }
                        }
                    }
                    else = [ordered]@{
                        actions = [ordered]@{
                            Create_cached_order = [ordered]@{
                                runAfter = [ordered]@{}
                                type     = 'OpenApiConnection'
                                inputs   = [ordered]@{
                                    host       = ($dvHost + [ordered]@{ operationId = 'CreateRecord' })
                                    parameters = [ordered]@{
                                        entityName                     = 'cog_qualityorders'
                                        'item/cog_name'                = (SrcRef 'mserp_qualityordernumber')
                                        'item/cog_qualityordernumber'  = (SrcRef 'mserp_qualityordernumber')
                                        'item/cog_company'             = (SrcRef 'mserp_dataareaid')
                                        'item/cog_itemnumber'          = (SrcRef 'mserp_itemnumber')
                                        'item/cog_productname'         = (SrcRef 'mserp_productname')
                                        'item/cog_testgroupid'         = (SrcRef 'mserp_qualitytestgroupid')
                                        'item/cog_referencetype'       = (SrcRef 'mserp_referencetype')
                                        'item/cog_inventoryquantity'   = (SrcRef 'mserp_inventoryquantity')
                                        'item/cog_siteid'              = (SrcRef 'mserp_inventorysiteid')
                                        'item/cog_warehouseid'         = (SrcRef 'mserp_warehouseid')
                                        'item/cog_batchnumber'         = (SrcRef 'mserp_itembatchnumber')
                                        'item/cog_status'              = (SrcRef 'mserp_qualityorderstatus')
                                        'item/cog_synchronizedon'      = '@utcNow()'
                                    }
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
        displayName = 'QM - Sync Cache'
    }
}
$cdJson = $clientData | ConvertTo-Json -Depth 60 -Compress
Write-Output "clientdata length: $($cdJson.Length)"

$fx = Invoke-Dv -Path "workflows?`$select=workflowid&`$filter=name eq '$FlowName'"
if (@($fx.value).Count -gt 0) {
    $flowId = $fx.value[0].workflowid
    Write-Output "EXISTS $FlowName -- deactivating to patch"
    $null = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ statecode = 0; statuscode = 1 }
    Start-Sleep -Seconds 3
    $r = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ clientdata = $cdJson }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Detail }
        Write-Output "PATCH FAILED: $(($m -split "`n")[0])"; throw "clientdata patch failed"
    }
    Write-Output "  clientdata patched"
} else {
    $wf = @{
        name          = $FlowName
        description   = "Refreshes the cog_ cache from the F&O virtual entities every $IntervalMinutes minutes."
        category      = 5
        primaryentity = 'none'
        type          = 1
        statecode     = 0
        statuscode    = 1
        clientdata    = $cdJson
    }
    $r = Invoke-Dv -Method POST -Path 'workflows' -Body $wf -Prefer 'return=representation' -ExtraHeaders $solHeader
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Detail }
        Write-Output "CREATE FAILED $($r.Status)"; Write-Output "  $(($m -split "`n")[0])"; throw "Flow creation failed."
    }
    $flowId = $r.workflowid
    Write-Output "CREATED $FlowName  id=$flowId"
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
Write-Output ("RESULT: {0}  statecode={1} statuscode={2}" -f $final.name, $final.statecode, $final.statuscode)
Write-Output "Flow id: $flowId"
