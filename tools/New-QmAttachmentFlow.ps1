# New-QmAttachmentFlow.ps1
# cog_QM_DrainAttachment -- pushes captured photos into F&O from queued outbox rows.
#
#   trigger : an outbox row is created
#   0 Exit unless status = Queued AND operationtype = 3 (PostAttachment)
#   1 Claim
#   2 Duplicate check on cog_correlationid
#   3 Scope: parse payload, read the cog_attachment row, create the staged file in F&O,
#            mark the attachment row Confirmed
#   4 Confirm / Flag
#
# The outbox payload carries only the attachment ROW ID, not the image. A base64 photo is up to
# 1 MiB and stuffing that into cog_payload would make the queue unreadable and every flow run
# expensive to inspect. The flow fetches the image from cog_attachment instead.
#
# Target is POWERAPPFILESAVINGENTITY. Proven by probe 2026-08-18 (docs\ATTACHMENTS.md 2a):
#   mserp_formname must be EXACTLY 'Quality'. The field caps at 20 characters, which made
#     'InventQualityOrder' look fine -- F&O accepts it, consumes the row, and attaches nothing.
#   The row must identify a test line (TestId + TestSequence + LineNum) or F&O never processes it.
#   mserp_tablerefid is irrelevant; '0000' is what both apps send.
#   mserp_imagevarchar accepts exactly 1,048,576 base64 characters and rejects more.
#
# Separate flow from the results and NC drains for the same reason as those: the trigger cannot
# filter on operationtype, so all of them fire on every outbox row and exit early for the ones
# that are not theirs. Keeping them apart means one failure cannot stall the others.
#
# ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$FlowName     = 'cog_QM_DrainAttachment',
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
        Operation     = @{ type = @('string','null') }
        CorrelationId = @{ type = @('string','null') }
        Company       = @{ type = 'string' }
    }
}

# Built by concatenation, never by PowerShell interpolation: "$x?['f']" is parsed as an index and
# silently drops the expression, which produced "expected token 'Identifier'" from the flow engine.
function P([string]$f) { return "body('Parse_payload')?[" + "'" + $f + "'" + "]" }
# The attachment row is found by CORRELATION ID, not by row id. Reading a Dataverse primary key
# back out of Patch() in Power Fx is awkward and version-sensitive; the correlation id is already
# on both rows because the idempotency design needs it there anyway.
function A([string]$f) { return "first(outputs('Read_the_attachment')?['body/value'])?[" + "'" + $f + "'" + "]" }

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

        Exit_unless_a_queued_attachment = [ordered]@{
            runAfter   = [ordered]@{}
            type       = 'If'
            expression = [ordered]@{
                or = @(
                    [ordered]@{ not = [ordered]@{ equals = @("@triggerOutputs()?['body/cog_outboxstatus']", 2) } },
                    [ordered]@{ not = [ordered]@{ equals = @("@triggerOutputs()?['body/cog_operationtype']", 3) } }
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
            runAfter = [ordered]@{ Exit_unless_a_queued_attachment = @('Succeeded') }
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

                Process_the_attachment = [ordered]@{
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

                        Read_the_attachment = [ordered]@{
                            runAfter = [ordered]@{ Parse_payload = @('Succeeded') }
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                                parameters = [ordered]@{
                                    entityName = 'cog_attachments'
                                    '$select'  = 'cog_attachmentid,cog_base64,cog_filename,cog_qualityordernumber,cog_testid,cog_testsequence,cog_linenum'
                                    '$filter'  = ("@concat('cog_correlationid eq ''', " +
                                                  "triggerOutputs()?['body/cog_correlationid']" +
                                                  ", '''')")
                                    '$top'     = 1
                                }
                            }
                        }

                        # No row means the app queued an outbox entry without its attachment, which
                        # must fail loudly rather than post an empty image to F&O.
                        Fail_if_no_attachment_row = [ordered]@{
                            runAfter   = [ordered]@{ Read_the_attachment = @('Succeeded') }
                            type       = 'If'
                            expression = [ordered]@{
                                equals = @("@length(outputs('Read_the_attachment')?['body/value'])", 0)
                            }
                            actions = [ordered]@{
                                No_attachment_found = [ordered]@{
                                    runAfter = [ordered]@{}
                                    type     = 'Terminate'
                                    inputs   = [ordered]@{
                                        runStatus = 'Failed'
                                        runError  = [ordered]@{
                                            code    = 'AttachmentMissing'
                                            message = 'No cog_attachment row carries this correlation id.'
                                        }
                                    }
                                }
                            }
                        }

                        # LineNum must be the REAL F&O result line number. Probed 2026-08-19:
                        # LineNum 1 is consumed and attached, LineNum 0 is never processed, even
                        # with a valid TestId and TestSequence. The offline cache does not carry a
                        # line number, so it is resolved here at drain time -- which is fine
                        # because the drain only runs when there is a connection anyway.
                        Read_the_result_line = [ordered]@{
                            runAfter = [ordered]@{ Fail_if_no_attachment_row = @('Succeeded') }
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'ListRecords' })
                                parameters = [ordered]@{
                                    entityName = 'mserp_inventqualityorderlineresultentities'
                                    '$select'  = 'mserp_resultlinenumber,mserp_qualityordersequencenumber'
                                    '$filter'  = ("@concat('mserp_dataareaid eq ''', " + (P 'Company') +
                                                  ", ''' and mserp_qualityordernumber eq ''', " +
                                                  (A 'cog_qualityordernumber') +
                                                  ", ''' and mserp_qualityordersequencenumber eq ', " +
                                                  "string(coalesce(" + (A 'cog_testsequence') + ", 0))" + ")")
                                    '$top'     = 1
                                }
                            }
                        }

                        Create_the_staged_file = [ordered]@{
                            runAfter = [ordered]@{ Read_the_result_line = @('Succeeded') }
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'CreateRecord' })
                                # entityName must be a LITERAL -- a dynamic value stops the
                                # connector resolving the schema and item/* fails validation.
                                parameters = [ordered]@{
                                    entityName                       = 'mserp_powerappfilesavingentities'
                                    'item/mserp_tablerefid'          = ('@' + (A 'cog_qualityordernumber'))
                                    'item/mserp_displayordernumber'  = ('@' + (A 'cog_qualityordernumber'))
                                    'item/mserp_testid'              = ('@coalesce(' + (A 'cog_testid') + ", '')")
                                    'item/mserp_testsequence'        = ('@int(coalesce(' + (A 'cog_testsequence') + ', 0))')
                                    'item/mserp_linenum'             = ('@float(coalesce(first(outputs(''Read_the_result_line'')?[''body/value''])?[''mserp_resultlinenumber''], 1))')
                                    'item/mserp_filename'            = ('@coalesce(' + (A 'cog_filename') + ", 'photo.jpg')")
                                    # 20 characters is the cap on this field.
                                    # PROVEN 2026-08-18: F&O only attaches the file when
                                    # FormName is exactly 'Quality'. With 'InventQualityOrder' it
                                    # accepts the row, consumes it within seconds, and attaches
                                    # nothing -- a silent no-op. See docs\ATTACHMENTS.md 2a.
                                    'item/mserp_formname'            = 'Quality'
                                    'item/mserp_imagevarchar'        = ('@' + (A 'cog_base64'))
                                    'item/mserp_dataareaid'          = ('@' + (P 'Company'))
                                }
                            }
                        }

                        Mark_the_attachment_confirmed = [ordered]@{
                            runAfter = [ordered]@{ Create_the_staged_file = @('Succeeded') }
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                                parameters = [ordered]@{
                                    entityName              = 'cog_attachments'
                                    recordId                = ('@' + (A 'cog_attachmentid'))
                                    'item/cog_attachstatus' = 4
                                }
                            }
                        }
                    }
                }

                Confirm_the_outbox_row = [ordered]@{
                    runAfter = [ordered]@{ Process_the_attachment = @('Succeeded') }
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

                # One handler on the whole Scope. Hanging it off individual actions is what let a
                # ParseJson failure strand a row at Submitting with no error recorded.
                Flag_needs_attention = [ordered]@{
                    runAfter = [ordered]@{ Process_the_attachment = @('Failed','TimedOut','Skipped') }
                    type     = 'OpenApiConnection'
                    inputs   = [ordered]@{
                        host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                        parameters = [ordered]@{
                            entityName              = 'cog_outboxes'
                            recordId                = "@triggerOutputs()?['body/cog_outboxid']"
                            'item/cog_outboxstatus' = 5
                            'item/cog_processedon'  = '@utcNow()'
                            'item/cog_lasterror'    = "@substring(string(result('Process_the_attachment')), 0, min(3900, length(string(result('Process_the_attachment')))))"
                        }
                    }
                }

                Flag_the_attachment_row = [ordered]@{
                    runAfter = [ordered]@{ Process_the_attachment = @('Failed','TimedOut','Skipped') }
                    type     = 'OpenApiConnection'
                    inputs   = [ordered]@{
                        host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                        parameters = [ordered]@{
                            entityName              = 'cog_attachments'
                            recordId                = ('@' + (A 'cog_attachmentid'))
                            'item/cog_attachstatus' = 5
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
        displayName = 'QM - Drain Attachment'
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
    $wf = @{ name=$FlowName; description='Pushes captured photos into F&O from queued outbox rows (operationtype 3).'
             category=5; primaryentity='none'; type=1; statecode=0; statuscode=1; clientdata=$cdJson }
    # 429 = a solution import is in flight; 500 with SQL 1205 = deadlock. Both transient.
    $r = $null
    for ($k = 1; $k -le 5; $k++) {
        $r = Invoke-Dv -Method POST -Path 'workflows' -Body $wf -Prefer 'return=representation' -ExtraHeaders $solHeader
        if (-not ($r.PSObject.Properties.Name -contains 'Ok')) { break }
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
