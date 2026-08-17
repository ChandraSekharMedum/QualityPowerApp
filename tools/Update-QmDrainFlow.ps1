# Update-QmDrainFlow.ps1
# cog_QM_DrainOutbox -- writes queued results to F&O.
#
#   trigger : an outbox row is created OR updated to Queued
#   1 Claim                      status -> Submitting
#   2 Scope Process_the_submission
#       Parse payload
#       For each line: resolve the target row, then update it in F&O
#   3 Confirm                    status -> Confirmed          (scope succeeded)
#   X Flag                       status -> Needs attention    (scope failed)
#
# WHY A SCOPE
# The failure handler used to hang off the Foreach. If ParseJson failed first -- which it
# did on a payload carrying ResultValue as a string -- nothing caught it. The row stayed at
# Submitting with no error recorded and no way to notice, which is the worst failure mode a
# queue can have. Wrapping the work in a Scope gives one handler that catches any failure
# inside it.
#
# Follows the deactivate -> patch clientdata -> reactivate cycle.
# ASCII-only per project standard.

param(
    [string]$FlowName    = 'cog_QM_DrainOutbox',
    [string]$ConnRefName = 'cog_QMConnRef_Dataverse'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')

$fx = Invoke-Dv -Path "workflows?`$select=workflowid,statecode,statuscode&`$filter=name eq '$FlowName'"
if (@($fx.value).Count -eq 0) { throw "$FlowName not found. Run New-QmDrainFlow.ps1 first." }
$flowId = $fx.value[0].workflowid
Write-Output "Flow $FlowName  id=$flowId  state=$($fx.value[0].statecode)/$($fx.value[0].statuscode)"

$dvHost = [ordered]@{
    connectionName          = $ConnRefName
    connectionReferenceName = $ConnRefName
    apiId                   = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
}

# Types are deliberately permissive. The app sends numbers via Value(), but hand-built and
# older payloads send strings, and a mismatch fails ParseJson.
$payloadSchema = [ordered]@{
    type       = 'object'
    properties = [ordered]@{
        Operation     = @{ type = @('string','null') }
        CorrelationId = @{ type = @('string','null') }
        Company       = @{ type = 'string' }
        TargetEntity  = @{ type = @('string','null') }
        Lines         = [ordered]@{
            type  = 'array'
            items = [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    TargetRecordId     = @{ type = @('string','null') }
                    QualityOrderNumber = @{ type = @('string','null') }
                    TestId             = @{ type = 'string' }
                    TestSequence       = @{ type = @('integer','string') }
                    ResultValue        = @{ type = @('number','string') }
                    TestResult         = @{ type = @('integer','string','null') }
                }
            }
        }
    }
}

$resolveFilter = "@concat('mserp_qualityordernumber eq ''', " +
                 "items('Apply_to_each_line')?['QualityOrderNumber']" +
                 ", ''' and mserp_qualitytestid eq ''', " +
                 "items('Apply_to_each_line')?['TestId']" +
                 ", ''' and mserp_qualityordersequencenumber eq ', string(" +
                 "items('Apply_to_each_line')?['TestSequence']" +
                 "), ' and mserp_dataareaid eq ''', " +
                 "body('Parse_payload')?['Company']" + ", '''')"

$recordId = "@if(not(empty(items('Apply_to_each_line')?['TargetRecordId']))" +
            ", items('Apply_to_each_line')?['TargetRecordId']" +
            ", first(outputs('Resolve_target_row')?['body/value'])?['mserp_inventqualityorderlineresultentityid'])"

$definition = [ordered]@{
    '$schema'      = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
    contentVersion = '1.0.0.0'
    parameters     = [ordered]@{
        "`$connections"    = [ordered]@{ defaultValue = @{}; type = 'Object' }
        "`$authentication" = [ordered]@{ defaultValue = @{}; type = 'SecureObject' }
    }
    triggers = [ordered]@{
        When_an_outbox_row_is_queued = [ordered]@{
            type   = 'OpenApiConnectionWebhook'
            inputs = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'SubscribeWebhookTrigger' })
                parameters = [ordered]@{
                    # message 3 = Create OR Update. Create alone meant the Retry button, which
                    # only sets status back to Queued, never fired the flow.
                    # The filter makes Update safe: the flow's own writes set 3 then 4, neither
                    # matches, so it cannot re-trigger itself. Only a row at 2 fires it.
                    'subscriptionRequest/message'          = 3
                    'subscriptionRequest/entityname'       = 'cog_outbox'
                    'subscriptionRequest/scope'            = 4
                    'subscriptionRequest/filterexpression' = 'cog_outboxstatus eq 2'
                }
            }
        }
    }
    actions = [ordered]@{

        Claim_the_outbox_row = [ordered]@{
            runAfter = [ordered]@{}
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                parameters = [ordered]@{
                    entityName              = 'cog_outboxes'
                    recordId                = "@triggerOutputs()?['body/cog_outboxid']"
                    'item/cog_outboxstatus' = 3
                    'item/cog_attempts'     = "@add(coalesce(triggerOutputs()?['body/cog_attempts'], 0), 1)"
                }
            }
        }

        Process_the_submission = [ordered]@{
            runAfter = [ordered]@{ Claim_the_outbox_row = @('Succeeded') }
            type     = 'Scope'
            actions  = [ordered]@{

                Parse_payload = [ordered]@{
                    runAfter = [ordered]@{}
                    type     = 'ParseJson'
                    inputs   = [ordered]@{
                        content = "@triggerOutputs()?['body/cog_payload']"
                        schema  = $payloadSchema
                    }
                }

                Apply_to_each_line = [ordered]@{
                    runAfter = [ordered]@{ Parse_payload = @('Succeeded') }
                    type     = 'Foreach'
                    foreach  = "@body('Parse_payload')?['Lines']"
                    actions  = [ordered]@{

                        # The app supplies TargetRecordId from its cache, but a client holding
                        # a pre-sync copy sends it empty -- how QO 000219 failed with
                        # "resolved string values ... may not be null or empty: 'recordId'".
                        # Resolving here means correctness never depends on client freshness.
                        Resolve_target_row = [ordered]@{
                            runAfter = [ordered]@{}
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                                parameters = [ordered]@{
                                    entityName = 'mserp_inventqualityorderlineresultentities'
                                    '$select'  = 'mserp_inventqualityorderlineresultentityid'
                                    '$filter'  = $resolveFilter
                                    '$top'     = 1
                                }
                            }
                        }

                        Update_the_F_and_O_result_line = [ordered]@{
                            runAfter = [ordered]@{ Resolve_target_row = @('Succeeded') }
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                                # GOTCHA: entityName must be a LITERAL. A dynamic value stops
                                # the connector resolving the entity schema and validation
                                # fails with "UpdateRecord is missing required property 'item'".
                                parameters = [ordered]@{
                                    entityName               = 'mserp_inventqualityorderlineresultentities'
                                    recordId                 = $recordId
                                    # Only the measured value is written. F&O derives the
                                    # Pass/Fail verdict from it against the tolerance, proven
                                    # in Phase 1. The connector does not expose
                                    # mserp_testresult as writable in any case.
                                    'item/mserp_resultvalue' = "@float(items('Apply_to_each_line')?['ResultValue'])"
                                }
                            }
                        }
                    }
                }
            }
        }

        Confirm_the_outbox_row = [ordered]@{
            runAfter = [ordered]@{ Process_the_submission = @('Succeeded') }
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                parameters = [ordered]@{
                    entityName              = 'cog_outboxes'
                    recordId                = "@triggerOutputs()?['body/cog_outboxid']"
                    'item/cog_outboxstatus' = 4
                    'item/cog_processedon'  = '@utcNow()'
                    'item/cog_lasterror'    = ''
                }
            }
        }

        Flag_needs_attention = [ordered]@{
            runAfter = [ordered]@{ Process_the_submission = @('Failed','TimedOut','Skipped') }
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                parameters = [ordered]@{
                    entityName              = 'cog_outboxes'
                    recordId                = "@triggerOutputs()?['body/cog_outboxid']"
                    'item/cog_outboxstatus' = 5
                    'item/cog_processedon'  = '@utcNow()'
                    'item/cog_lasterror'    = "@substring(string(result('Process_the_submission')), 0, min(3900, length(string(result('Process_the_submission')))))"
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
        displayName = 'QM - Drain Outbox'
    }
}
$cdJson = $clientData | ConvertTo-Json -Depth 60 -Compress
Write-Output "clientdata length: $($cdJson.Length)"

Write-Output ""
Write-Output "1. deactivate"
$r = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ statecode = 0; statuscode = 1 }
Write-Output $(if ($r.PSObject.Properties.Name -contains 'Ok') { "   warn: $($r.Status)" } else { '   ok' })
Start-Sleep -Seconds 3

Write-Output "2. patch clientdata"
$r = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ clientdata = $cdJson }
if ($r.PSObject.Properties.Name -contains 'Ok') {
    $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Detail }
    Write-Output "   FAILED: $(($m -split "`n")[0])"
    throw "clientdata patch failed"
}
Write-Output "   ok"
Start-Sleep -Seconds 3

Write-Output "3. reactivate"
for ($i=1; $i -le 3; $i++) {
    $r = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ statecode = 1; statuscode = 2 }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Status }
        Write-Output "   attempt $i failed: $(($m -split "`n")[0])"
        Start-Sleep -Seconds 4
    } else { Write-Output "   ACTIVATED"; break }
}

$final = Invoke-Dv -Path "workflows($flowId)?`$select=name,statecode,statuscode"
Write-Output ""
Write-Output ("RESULT: {0}  statecode={1} statuscode={2}" -f $final.name, $final.statecode, $final.statuscode)
