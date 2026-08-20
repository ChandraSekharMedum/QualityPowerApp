# New-QmOrderDrainFlow.ps1
# cog_QM_DrainQualityOrder -- creates quality orders in F&O from queued outbox rows.
#
#   trigger : an outbox row is created
#   0 Exit unless status = Queued AND operationtype = 4 (CreateQualityOrder)
#   1 Claim
#   2 Duplicate check on cog_correlationid
#   3 Scope: parse payload, create the quality order header in F&O
#   4 Confirm / Flag
#
# Operation types in use: 1 result, 2 non-conformance, 3 attachment, 4 quality order.
# Separate flow per type, same reason as the NC drain: the Dataverse trigger cannot filter
# on operationtype reliably in this environment, so every flow fires on every outbox row
# and exits early for rows that are not its own.
#
# ---------------------------------------------------------------------------------------
# THE FIELD SET IS NOT ARBITRARY. It replicates what the working demo app's QOPurchScreen
# sends, which the business confirmed as the intended behaviour. See
# docs/QUALITY-ORDER-CREATION.md section 4. The two easy-to-miss ones:
#
#   mserp_publicaccountrelation  = the VENDOR from the PO header ('Account selection').
#   mserp_inventdimensionid      = "AllBlank" ('Dimension number').
#
# Adding those two moved three of five test items off the Owner error entirely, so they
# are load-bearing, not decoration.
#
# mserp_qualityordernumber is deliberately NOT sent. F&O assigns it from number sequence
# Inve_172 and rejects a supplied one outright.
#
# mserp_referenceinventorylotid is mandatory. Without it F&O rejects with "'<n>' in field
# 'Reference number' is not found in the related table 'Purchase order lines'".
#
# Product dimensions are sent only when the source line actually carries them. An item with
# product dimensions is rejected without them; an item without them is rejected if sent
# blanks. The payload carries whatever the PO line had and coalesce keeps blanks out.
# ---------------------------------------------------------------------------------------
#
# KNOWN ENVIRONMENT BLOCKER: in cus-con-sandbox the Owner inventory dimension is inactive
# while items' storage dimension groups include it, so most creates will land in status 5
# (needs attention) with "Owner is inactive and may consequently not be specified". That is
# an F&O configuration matter, not an app defect -- this flow surfaces the rejection in
# QMQueue rather than hiding it. See docs/QUALITY-ORDER-CREATION.md section 6.
#
# ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$FlowName     = 'cog_QM_DrainQualityOrder',
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
        Operation       = @{ type = @('string','null') }
        CorrelationId   = @{ type = @('string','null') }
        # The cache row the user picked. Carried purely so a rejection can un-hide the line
        # again -- the app marks it inspected optimistically on queue to stop double-booking.
        POLineId        = @{ type = @('string','null') }
        Company         = @{ type = 'string' }
        ReferenceType   = @{ type = @('integer','string') }
        InventRefId     = @{ type = 'string' }
        ReferenceLotId  = @{ type = 'string' }
        ItemNumber      = @{ type = 'string' }
        ProductName     = @{ type = @('string','null') }
        SiteId          = @{ type = @('string','null') }
        WarehouseId     = @{ type = @('string','null') }
        InventoryStatus = @{ type = @('string','null') }
        AccountRelation = @{ type = @('string','null') }
        TestGroupId     = @{ type = 'string' }
        Quantity        = @{ type = @('number','string','null') }
        ConfigurationId = @{ type = @('string','null') }
        ColorId         = @{ type = @('string','null') }
        SizeId          = @{ type = @('string','null') }
        StyleId         = @{ type = @('string','null') }
    }
}

function P([string]$f) { return "body('Parse_payload')?[" + "'" + $f + "'" + "]" }

# The failure text the queue screen shows the user.
#
# It must be built from result('Process_the_submission'), NOT from
# outputs('Create_the_quality_order'). Flag_needs_attention is a SIBLING of the scope, and
# Logic Apps forbids referencing an action nested inside a scope from outside it. Doing so
# does not fail loudly: Dataverse still reports the flow 1/2 Activated, but Power Automate
# refuses to register the trigger, so the flow silently never fires and outbox rows sit at
# Queued with attempts=0. Cost an hour on 2026-08-20 -- see docs/QUALITY-ORDER-CREATION.md.
#
# result() returns the array of action results, so take the create out of it. Use last():
# the scope runs Parse_payload then Create_the_quality_order, so the create is the final
# entry, and it is the one that failed. That keeps the F&O rejection at the FRONT of the
# 3900-char cap; the raw scope result leads with the echoed payload and the HTTP headers and
# pushes the actual reason off the end.
#
# Do NOT reach for where() or filter() here. Neither exists in the workflow definition
# language -- only first/last/take/skip/union and friends. An unknown function SAVES without
# complaint and the trigger arms normally, then the action fails at runtime and the outbox
# row strands at Sending (status 3) forever, since the row is claimed but never resolved.
$errBody = ("coalesce(last(result('Process_the_submission'))?['outputs']?['body']," +
            " result('Process_the_submission'))")
$errExpr = "@substring(string($errBody), 0, min(3900, length(string($errBody))))"

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

        # Not ours unless it is a queued quality order create.
        Exit_unless_a_queued_order = [ordered]@{
            runAfter   = [ordered]@{}
            type       = 'If'
            expression = [ordered]@{
                or = @(
                    [ordered]@{ not = [ordered]@{ equals = @("@triggerOutputs()?['body/cog_outboxstatus']", 2) } },
                    [ordered]@{ not = [ordered]@{ equals = @("@triggerOutputs()?['body/cog_operationtype']", 4) } }
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
            runAfter = [ordered]@{ Exit_unless_a_queued_order = @('Succeeded') }
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

                        Create_the_quality_order = [ordered]@{
                            runAfter = [ordered]@{ Parse_payload = @('Succeeded') }
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'CreateRecord' })
                                # entityName must be a LITERAL -- a dynamic value stops the
                                # connector resolving the schema and item/* fails validation.
                                parameters = [ordered]@{
                                    entityName                          = 'mserp_inventqualityorderheaderentities'
                                    # No mserp_qualityordernumber: F&O assigns from Inve_172.
                                    'item/mserp_referencetype'          = ('@int(' + (P 'ReferenceType') + ')')
                                    'item/mserp_inventrefid'            = ('@' + (P 'InventRefId'))
                                    'item/mserp_referenceinventorylotid'= ('@' + (P 'ReferenceLotId'))
                                    'item/mserp_itemnumber'             = ('@' + (P 'ItemNumber'))
                                    'item/mserp_productname'            = ('@coalesce(' + (P 'ProductName') + ", '')")
                                    'item/mserp_inventorysiteid'        = ('@coalesce(' + (P 'SiteId') + ", '')")
                                    'item/mserp_warehouseid'            = ('@coalesce(' + (P 'WarehouseId') + ", '')")
                                    'item/mserp_inventorystatusid'      = ('@coalesce(' + (P 'InventoryStatus') + ", '')")
                                    # The vendor, from the PO header. Load-bearing -- see header.
                                    'item/mserp_publicaccountrelation'  = ('@coalesce(' + (P 'AccountRelation') + ", '')")
                                    'item/mserp_qualitytestgroupid'     = ('@' + (P 'TestGroupId'))
                                    'item/mserp_inventoryquantity'      = ('@float(coalesce(' + (P 'Quantity') + ', 0))')
                                    # "AllBlank" is F&O's blank inventory-dimension record id.
                                    'item/mserp_inventdimensionid'      = 'AllBlank'
                                    'item/mserp_productconfigurationid' = ('@coalesce(' + (P 'ConfigurationId') + ", '')")
                                    'item/mserp_productcolorid'         = ('@coalesce(' + (P 'ColorId') + ", '')")
                                    'item/mserp_productsizeid'          = ('@coalesce(' + (P 'SizeId') + ", '')")
                                    'item/mserp_productstyleid'         = ('@coalesce(' + (P 'StyleId') + ", '')")
                                    'item/mserp_dataareaid'             = ('@' + (P 'Company'))
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
                            # The assigned order number, so the app can show it instead of "pending".
                            'item/cog_fnoresponse'  = "@string(body('Create_the_quality_order'))"
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
                            'item/cog_lasterror'    = $errExpr
                        }
                    }
                }

                # The app hides a line the moment it is queued, so two inspectors cannot book
                # the same lot. When F&O refuses the create, that hiding is wrong -- the line
                # is still inspectable. Put it back rather than waiting for the next sync to
                # notice, which could be hours and looks to the user like the line vanished.
                Release_the_line_again = [ordered]@{
                    runAfter = [ordered]@{ Flag_needs_attention = @('Succeeded') }
                    type     = 'If'
                    expression = [ordered]@{
                        not = [ordered]@{
                            equals = @("@coalesce(body('Parse_payload')?['POLineId'], '')", '')
                        }
                    }
                    actions = [ordered]@{
                        Unhide_the_po_line = [ordered]@{
                            runAfter = [ordered]@{}
                            type     = 'OpenApiConnection'
                            inputs   = [ordered]@{
                                host       = ($dvHost + [ordered]@{ operationId = 'UpdateRecord' })
                                parameters = [ordered]@{
                                    entityName                   = 'cog_polines'
                                    recordId                     = "@body('Parse_payload')?['POLineId']"
                                    'item/cog_hasqualityorder'   = 0
                                }
                            }
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
        displayName = 'QM - Drain Quality Order'
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
    $wf = @{ name=$FlowName; description='Creates quality orders in F&O from queued outbox rows (operationtype 4).'
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
