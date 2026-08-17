# New-QmNcDrainFlow.ps1
# cog_QM_DrainNonConformance -- creates non-conformances in F&O from queued outbox rows.
#
#   trigger : an outbox row is created
#   0 Exit unless status = Queued AND operationtype = 2 (PostNonConformance)
#   1 Claim
#   2 Duplicate check on cog_correlationid
#   3 Scope: parse payload, create the NC in F&O
#   4 Confirm / Flag
#
# Separate from cog_QM_DrainOutbox deliberately. The trigger cannot filter on
# operationtype -- filterexpression proved unreliable in this environment -- so both flows
# fire on every outbox row and exit early for the ones that are not theirs. Keeping them
# apart means each has debuggable clientdata and an NC failure cannot stop results draining.
#
# Writes to the BASE entity mserp_inventnonconformancetableentities. The app-optimised
# POWERAPPSINVENTNONCONFORMATIONENTITY returns 0x80048d02 on POST and also lacks custaccount.
#
# ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$FlowName     = 'cog_QM_DrainNonConformance',
    [string]$ConnRefName  = 'cog_QMConnRef_Dataverse'
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

$payloadSchema = [ordered]@{
    type       = 'object'
    properties = [ordered]@{
        Operation        = @{ type = @('string','null') }
        CorrelationId    = @{ type = @('string','null') }
        Company          = @{ type = 'string' }
        NonConformanceId = @{ type = 'string' }
        Type             = @{ type = @('integer','string') }
        ProblemTypeId    = @{ type = 'string' }
        ItemId           = @{ type = 'string' }
        NcDate           = @{ type = @('string','null') }
        DefectQty        = @{ type = @('number','string','null') }
        Rush             = @{ type = @('integer','string','null') }
        VendAccount      = @{ type = @('string','null') }
        CustAccount      = @{ type = @('string','null') }
        RefId            = @{ type = @('string','null') }
    }
}

function P([string]$f) { return "body('Parse_payload')?[" + "'" + $f + "'" + "]" }

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

        # Not ours unless it is a queued non-conformance.
        Exit_unless_a_queued_NC = [ordered]@{
            runAfter   = [ordered]@{}
            type       = 'If'
            expression = [ordered]@{
                or = @(
                    [ordered]@{ not = [ordered]@{ equals = @("@triggerOutputs()?['body/cog_outboxstatus']", 2) } },
                    [ordered]@{ not = [ordered]@{ equals = @("@triggerOutputs()?['body/cog_operationtype']", 2) } }
                )
            }
            actions = [ordered]@{
                Stop = [ordered]@{
                    runAfter = [ordered]@{}
                    type     = 'Terminate'
                    inputs   = [ordered]@{ runStatus = 'Succeeded' }
                }
            }
        }

        Claim_the_outbox_row = [ordered]@{
            runAfter = [ordered]@{ Exit_unless_a_queued_NC = @('Succeeded') }
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

        Check_for_an_already_confirmed_twin = [ordered]@{
            runAfter = [ordered]@{ Claim_the_outbox_row = @('Succeeded') }
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                parameters = [ordered]@{
                    entityName = 'cog_outboxes'
                    '$select'  = 'cog_outboxid,cog_processedon'
                    '$filter'  = ("@concat('cog_correlationid eq ''', " +
                                  "triggerOutputs()?['body/cog_correlationid']" +
                                  ", ''' and cog_outboxstatus eq 4 and cog_outboxid ne ', " +
                                  "triggerOutputs()?['body/cog_outboxid']" + ")")
                    '$top'     = 1
                }
            }
        }

        Route_duplicate_or_process = [ordered]@{
            runAfter   = [ordered]@{ Check_for_an_already_confirmed_twin = @('Succeeded') }
            type       = 'If'
            expression = [ordered]@{
                greater = @("@length(outputs('Check_for_an_already_confirmed_twin')?['body/value'])", 0)
            }
            actions = [ordered]@{
                Mark_as_duplicate = [ordered]@{
                    runAfter = [ordered]@{}
                    type     = 'OpenApiConnection'
                    inputs   = [ordered]@{
                        host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                        parameters = [ordered]@{
                            entityName              = 'cog_outboxes'
                            recordId                = "@triggerOutputs()?['body/cog_outboxid']"
                            'item/cog_outboxstatus' = 6
                            'item/cog_processedon'  = '@utcNow()'
                            'item/cog_lasterror'    = ("@concat('Skipped: correlation ', " +
                                                       "triggerOutputs()?['body/cog_correlationid']" +
                                                       ", ' was already confirmed')")
                        }
                    }
                }
            }
            else = [ordered]@{ actions = [ordered]@{

                Process_the_submission = [ordered]@{
                    runAfter = [ordered]@{}
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

                        Create_the_non_conformance = [ordered]@{
                            runAfter = [ordered]@{ Parse_payload = @('Succeeded') }
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'CreateRecord' })
                                # entityName must be a LITERAL -- a dynamic value stops the
                                # connector resolving the schema and item/* fails validation.
                                parameters = [ordered]@{
                                    entityName                             = 'mserp_inventnonconformancetableentities'
                                    'item/mserp_inventnonconformanceid'    = ('@' + (P 'NonConformanceId'))
                                    'item/mserp_inventnonconformancetype'  = ('@int(' + (P 'Type') + ')')
                                    'item/mserp_inventtestproblemtypeid'   = ('@' + (P 'ProblemTypeId'))
                                    'item/mserp_itemid'                    = ('@' + (P 'ItemId'))
                                    'item/mserp_nonconformancedate'        = ('@' + (P 'NcDate'))
                                    'item/mserp_testdefectqty'             = ('@float(coalesce(' + (P 'DefectQty') + ', 0))')
                                    # No mserp_unitid. It reports IsValidForCreate = False and F&O
                                    # discards it silently on POST -- the unit is derived from the
                                    # item. The connector rejects it outright with
                                    # WorkflowOperationParametersExtraParameter, which is the
                                    # better error of the two.
                                    #
                                    # Rush is a picklist: 200000000 No / 200000001 Yes. Default No
                                    # rather than blank -- F&O rejects an empty enum.
                                    'item/mserp_rush'                      = ('@int(coalesce(' + (P 'Rush') + ', 200000000))')
                                    'item/mserp_vendaccount'               = ('@coalesce(' + (P 'VendAccount') + ", '')")
                                    'item/mserp_custaccount'               = ('@coalesce(' + (P 'CustAccount') + ", '')")
                                    'item/mserp_inventrefid'               = ('@coalesce(' + (P 'RefId') + ", '')")
                                    'item/mserp_dataareaid'                = ('@' + (P 'Company'))
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

            } }
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
        displayName = 'QM - Drain Non-Conformance'
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
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Detail }
        Write-Output "PATCH FAILED: $(($m -split "`n")[0])"; throw "patch failed"
    }
    Write-Output "  patched"
} else {
    $wf = @{ name=$FlowName; description='Creates non-conformances in F&O from queued outbox rows (operationtype 2).'
             category=5; primaryentity='none'; type=1; statecode=0; statuscode=1; clientdata=$cdJson }
    # 429 means a solution import is in flight; back off and retry rather than failing.
    $r = $null
    for ($k = 1; $k -le 5; $k++) {
        $r = Invoke-Dv -Method POST -Path 'workflows' -Body $wf -Prefer 'return=representation' -ExtraHeaders $solHeader
        if (-not ($r.PSObject.Properties.Name -contains 'Ok')) { break }
        # 429 = concurrent solution import; 500 with SQL 1205 = deadlock. Both transient.
        if ($r.Status -ne 429 -and $r.Status -ne 500) { break }
        Write-Output "  $($r.Status) transient -- backing off, attempt $k"
        Start-Sleep -Seconds 45
    }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Detail }
        Write-Output "CREATE FAILED $($r.Status): $(($m -split "`n")[0])"; throw "create failed"
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
        $m=''; try { $m=($r.Detail|ConvertFrom-Json).error.message } catch { $m=$r.Status }
        Write-Output "  attempt $i failed: $(($m -split "`n")[0])"; Start-Sleep -Seconds 4
    } else { Write-Output "  ACTIVATED"; break }
}
$final = Invoke-Dv -Path "workflows($flowId)?`$select=name,statecode,statuscode"
Write-Output ""
Write-Output ("RESULT: {0}  {1}/{2}" -f $final.name,$final.statecode,$final.statuscode)
