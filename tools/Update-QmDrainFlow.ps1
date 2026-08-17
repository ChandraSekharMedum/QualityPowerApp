# Update-QmDrainFlow.ps1
# Phase 2: upgrade cog_QM_DrainOutbox from a claim-only stub to the real drain.
#
#   trigger : cog_outbox row created
#   1 Claim         -> status Submitting, attempts 1
#   2 Parse payload -> the JSON the app queued
#   3 For each line -> update the F&O result line through its virtual table
#   4 Confirm       -> status Confirmed, stamp processed time
#
# The payload carries the target record id, so no lookup is needed at drain time -- the
# app already has the line in context when the inspector submits.
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

$payloadSchema = [ordered]@{
    type       = 'object'
    properties = [ordered]@{
        Operation     = @{ type = 'string' }
        CorrelationId = @{ type = 'string' }
        Company       = @{ type = 'string' }
        TargetEntity  = @{ type = 'string' }
        Lines         = [ordered]@{
            type  = 'array'
            items = [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    TargetRecordId = @{ type = 'string' }
                    TestId         = @{ type = 'string' }
                    TestSequence   = @{ type = 'integer' }
                    ResultValue    = @{ type = 'number' }
                    TestResult     = @{ type = 'integer' }
                }
            }
        }
    }
}

$definition = [ordered]@{
    '$schema'      = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
    contentVersion = '1.0.0.0'
    parameters     = [ordered]@{
        "`$connections"    = [ordered]@{ defaultValue = @{}; type = 'Object' }
        "`$authentication" = [ordered]@{ defaultValue = @{}; type = 'SecureObject' }
    }
    triggers = [ordered]@{
        When_an_outbox_row_is_created = [ordered]@{
            type   = 'OpenApiConnectionWebhook'
            inputs = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'SubscribeWebhookTrigger' })
                parameters = [ordered]@{
                    'subscriptionRequest/message'    = 1
                    'subscriptionRequest/entityname' = 'cog_outbox'
                    'subscriptionRequest/scope'      = 4
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
                    'item/cog_attempts'     = 1
                }
            }
        }

        Parse_payload = [ordered]@{
            runAfter = [ordered]@{ Claim_the_outbox_row = @('Succeeded') }
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
                Update_the_F_and_O_result_line = [ordered]@{
                    runAfter = [ordered]@{}
                    type     = 'OpenApiConnection'
                    inputs   = [ordered]@{
                        host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                        # GOTCHA: entityName must be a LITERAL, not an expression. With a
                        # dynamic value the connector cannot resolve the entity schema and
                        # validation fails with "UpdateRecord is missing required property
                        # 'item'". TargetEntity stays in the payload for traceability only.
                        parameters = [ordered]@{
                            entityName                = 'mserp_inventqualityorderlineresultentities'
                            recordId                  = "@items('Apply_to_each_line')?['TargetRecordId']"
                            # Only the measured value is written. F&O derives the Pass/Fail
                            # verdict from it against the test tolerance -- proven in Phase 1
                            # (value 20 inside limits 10-30 flipped Fail to Pass unprompted).
                            # The connector does not expose mserp_testresult as a writable
                            # parameter in any case.
                            'item/mserp_resultvalue'  = "@items('Apply_to_each_line')?['ResultValue']"
                        }
                    }
                }
            }
        }

        Confirm_the_outbox_row = [ordered]@{
            runAfter = [ordered]@{ Apply_to_each_line = @('Succeeded') }
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                parameters = [ordered]@{
                    entityName              = 'cog_outboxes'
                    recordId                = "@triggerOutputs()?['body/cog_outboxid']"
                    'item/cog_outboxstatus' = 4
                    'item/cog_processedon'  = "@utcNow()"
                }
            }
        }

        Flag_needs_attention = [ordered]@{
            runAfter = [ordered]@{ Apply_to_each_line = @('Failed','TimedOut') }
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                parameters = [ordered]@{
                    entityName              = 'cog_outboxes'
                    recordId                = "@triggerOutputs()?['body/cog_outboxid']"
                    'item/cog_outboxstatus' = 5
                    'item/cog_lasterror'    = "@string(result('Apply_to_each_line'))"
                    'item/cog_processedon'  = "@utcNow()"
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
if ($r.PSObject.Properties.Name -contains 'Ok') { Write-Output "   warn: $($r.Status)" } else { Write-Output "   ok" }
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
