# New-QmDrainFlow.ps1
# Phase 2, task 13: the outbox drain flow.
#
# Trigger : a row is created in cog_outbox
# Action  : claim it -- set status Submitting and stamp the attempt
#
# This is deliberately the minimum that proves the trigger fires and the flow can write
# back. The F&O write itself (parse payload -> update
# mserp_inventqualityorderlineresultentities per line) is added once the runtime is armed
# and the trigger is confirmed, because a multi-step flow that cannot be run is a poor
# thing to author blind.
#
# Uses the Dataverse connector throughout -- Phase 1 proved the F&O connector does not
# expose the quality entities, but the virtual tables are reachable through Dataverse.
#
# ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$FlowName     = 'cog_QM_DrainOutbox',
    [string]$ConnRefName  = 'cog_QMConnRef_Dataverse'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')
$solHeader = @{ 'MSCRM.SolutionUniqueName' = $SolutionName }

# ---------------------------------------------------------- 1. Dataverse connection ref
Write-Output "=== Dataverse connection reference ==="
$cr = Invoke-Dv -Path "connectionreferences?`$select=connectionreferenceid,connectionid&`$filter=connectionreferencelogicalname eq '$ConnRefName'"
if (@($cr.value).Count -gt 0) {
    Write-Output "  EXISTS $ConnRefName"
} else {
    # Find a Dataverse connection owned by the current user.
    $conns = & pac connection list 2>&1 | Select-String -Pattern 'shared_commondataserviceforapps'
    $connId = $null
    foreach ($line in $conns) {
        if ($line -match '^\s*(\S+)\s') { $connId = $Matches[1]; break }
    }
    if (-not $connId) { throw "No Dataverse connection found for the current user." }
    Write-Output "  using connection $connId"

    $body = @{
        connectionreferencelogicalname = $ConnRefName
        connectionreferencedisplayname = 'Quality Management - Dataverse'
        connectorid                    = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
        connectionid                   = $connId
    }
    $r = Invoke-Dv -Method POST -Path 'connectionreferences' -Body $body -Prefer 'return=representation' -ExtraHeaders $solHeader
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Detail }
        throw "Connection reference failed: $(($m -split "`n")[0])"
    }
    Write-Output "  CREATED $ConnRefName"
}

# ---------------------------------------------------------- 2. clientdata
Write-Output ""
Write-Output "=== Authoring clientdata ==="

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
                host = [ordered]@{
                    connectionName          = $ConnRefName
                    connectionReferenceName = $ConnRefName
                    operationId             = 'SubscribeWebhookTrigger'
                    apiId                   = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
                }
                parameters = [ordered]@{
                    'subscriptionRequest/message'     = 1          # Create
                    'subscriptionRequest/entityname'  = 'cog_outbox'
                    'subscriptionRequest/scope'       = 4          # Organization
                }
            }
        }
    }
    actions = [ordered]@{
        Claim_the_outbox_row = [ordered]@{
            runAfter = [ordered]@{}
            type     = 'OpenApiConnection'
            inputs   = [ordered]@{
                host = [ordered]@{
                    connectionName          = $ConnRefName
                    connectionReferenceName = $ConnRefName
                    operationId             = 'UpdateRecord'
                    apiId                   = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
                }
                parameters = [ordered]@{
                    entityName            = 'cog_outboxes'
                    recordId              = "@triggerOutputs()?['body/cog_outboxid']"
                    'item/cog_outboxstatus' = 3        # Submitting
                    'item/cog_attempts'     = 1
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
$cdJson = $clientData | ConvertTo-Json -Depth 40 -Compress
Write-Output "  clientdata length: $($cdJson.Length)"

# ---------------------------------------------------------- 3. flow row
Write-Output ""
Write-Output "=== Flow row ==="
$fx = Invoke-Dv -Path "workflows?`$select=workflowid,statecode,statuscode&`$filter=name eq '$FlowName'"
if (@($fx.value).Count -gt 0) {
    $flowId = $fx.value[0].workflowid
    Write-Output "  EXISTS id=$flowId"
} else {
    $wf = @{
        name          = $FlowName
        description   = 'Claims queued outbox rows. F&O write logic added once the runtime trigger is confirmed.'
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
        Write-Output "  CREATE FAILED $($r.Status)"
        Write-Output "  $(($m -split "`n")[0])"
        throw "Flow creation failed."
    }
    $flowId = $r.workflowid
    Write-Output "  CREATED id=$flowId"
}

# ---------------------------------------------------------- 4. activate
Write-Output ""
Write-Output "=== Activating ==="
for ($i=1; $i -le 3; $i++) {
    $r = Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ statecode = 1; statuscode = 2 }
    if ($r.PSObject.Properties.Name -contains 'Ok') {
        $m=''; try { $m = ($r.Detail | ConvertFrom-Json).error.message } catch { $m = $r.Status }
        Write-Output "  attempt $i failed: $(($m -split "`n")[0])"
        Start-Sleep -Seconds 4
    } else { Write-Output "  ACTIVATED on attempt $i"; break }
}

$final = Invoke-Dv -Path "workflows($flowId)?`$select=name,statecode,statuscode"
Write-Output ""
Write-Output ("RESULT: {0}  statecode={1} statuscode={2}" -f $final.name, $final.statecode, $final.statuscode)
Write-Output "Flow id: $flowId"
