# schema.ps1 -- Phase 2 Dataverse schema definition for the Quality Management app.
#
# Scope: the TEST RESULT journey only. Quality order creation is deferred to a later
# upgrade (Phase 1 proved it is not possible over OData), so reference-data caches that
# only serve the creation screens are deliberately out of scope.
#
# Design notes:
#  - Choice values are stored as INTEGERS mirroring F&O's own option set values, not as
#    Dataverse option sets. The Web API returns F&O enums as integers, so this keeps
#    parity and avoids a translation layer. See phase1/output/OPTION-SETS.md.
#  - Cache tables are written only by the sync flow and read by the app.
#  - Draft tables are written by the app, including offline.
#  - The outbox is the single durable record of intent for every write to F&O.
#
# ASCII-only per project standard.

$script:Prefix   = 'cog'
$script:Solution = 'QualityManagementApp'

# ---------------------------------------------------------------- table definitions
$script:Tables = @(

  @{ Schema='cog_QualityOrder'; Display='Quality Order (cache)'; Plural='Quality Orders (cache)'
     Description='Cached mirror of F&O quality order headers. Written by the sync flow, read by the app. Offline-capable.'
     PrimaryName='cog_Name'; PrimaryLabel='Quality order'
     Attributes=@(
       @{t='String'; s='cog_QualityOrderNumber'; l='Quality order number'; max=20; req='ApplicationRequired'}
       @{t='String'; s='cog_Company';            l='Company';             max=4;  req='ApplicationRequired'}
       @{t='String'; s='cog_ItemNumber';         l='Item number';         max=20}
       @{t='String'; s='cog_ProductName';        l='Product name';        max=100}
       @{t='String'; s='cog_TestGroupId';        l='Test group';          max=20}
       @{t='Int';    s='cog_ReferenceType';      l='Reference type'}
       @{t='Decimal';s='cog_InventoryQuantity';  l='Quantity'}
       @{t='String'; s='cog_SiteId';             l='Site';                max=20}
       @{t='String'; s='cog_WarehouseId';        l='Warehouse';           max=20}
       @{t='String'; s='cog_BatchNumber';        l='Batch number';        max=20}
       @{t='Int';    s='cog_Status';             l='Status'}
       @{t='DateTime';s='cog_SynchronizedOn';    l='Synchronized on'}
     )}

  @{ Schema='cog_QualityTestLine'; Display='Quality Test Line (cache)'; Plural='Quality Test Lines (cache)'
     Description='Cached test lines including tolerance bounds, so the app can compute a live verdict offline.'
     PrimaryName='cog_Name'; PrimaryLabel='Test line'
     Attributes=@(
       @{t='String'; s='cog_QualityOrderNumber'; l='Quality order number'; max=20; req='ApplicationRequired'}
       @{t='String'; s='cog_TestId';             l='Test';                 max=30; req='ApplicationRequired'}
       @{t='Int';    s='cog_TestSequence';       l='Sequence'}
       @{t='String'; s='cog_Company';            l='Company';              max=4}
       @{t='Decimal';s='cog_LowerLimit';         l='Lower limit'}
       @{t='Decimal';s='cog_UpperLimit';         l='Upper limit'}
       @{t='Decimal';s='cog_StandardValue';      l='Target value'}
       @{t='String'; s='cog_TestInstrumentId';   l='Instrument';           max=30}
       @{t='String'; s='cog_TestUnitId';         l='Unit';                 max=10}
       @{t='String'; s='cog_VariableId';         l='Outcome variable';     max=30}
       @{t='Int';    s='cog_CurrentResult';      l='Current result'}
       @{t='String'; s='cog_CurrentValue';       l='Current value';        max=50}
       @{t='DateTime';s='cog_SynchronizedOn';    l='Synchronized on'}
     )}

  @{ Schema='cog_TestOutcome'; Display='Test Outcome (cache)'; Plural='Test Outcomes (cache)'
     Description='Cached qualitative outcome options for tests that are judged rather than measured.'
     PrimaryName='cog_Name'; PrimaryLabel='Outcome'
     Attributes=@(
       @{t='String'; s='cog_VariableId';  l='Outcome variable'; max=30; req='ApplicationRequired'}
       @{t='String'; s='cog_OutcomeId';   l='Outcome';          max=30; req='ApplicationRequired'}
       @{t='String'; s='cog_Company';     l='Company';          max=4}
       @{t='String'; s='cog_Description'; l='Description';      max=100}
       @{t='Int';    s='cog_ImpliedResult'; l='Implied result'}
       @{t='DateTime';s='cog_SynchronizedOn'; l='Synchronized on'}
     )}

  @{ Schema='cog_ResultSheet'; Display='Result Sheet (draft)'; Plural='Result Sheets (draft)'
     Description='An inspector working sheet for one quality order. Created and edited offline; submitted via the outbox.'
     PrimaryName='cog_Name'; PrimaryLabel='Result sheet'
     Attributes=@(
       @{t='String'; s='cog_QualityOrderNumber'; l='Quality order number'; max=20; req='ApplicationRequired'}
       @{t='String'; s='cog_Company';            l='Company';              max=4}
       @{t='Int';    s='cog_SheetStatus';        l='Sheet status'}
       @{t='String'; s='cog_CorrelationId';      l='Correlation id';       max=50}
       @{t='Int';    s='cog_Verdict';            l='Computed verdict'}
       @{t='DateTime';s='cog_StartedOn';         l='Started on'}
       @{t='DateTime';s='cog_CompletedOn';       l='Completed on'}
     )}

  @{ Schema='cog_ResultEntry'; Display='Result Entry (draft)'; Plural='Result Entries (draft)'
     Description='One entered test result on a result sheet, with an optional photo. Offline-capable.'
     PrimaryName='cog_Name'; PrimaryLabel='Result entry'
     Attributes=@(
       @{t='String'; s='cog_TestId';          l='Test';             max=30; req='ApplicationRequired'}
       @{t='Int';    s='cog_TestSequence';    l='Sequence'}
       @{t='String'; s='cog_EnteredValue';    l='Entered value';    max=50}
       @{t='String'; s='cog_OutcomeId';       l='Outcome';          max=30}
       @{t='Int';    s='cog_ComputedVerdict'; l='Computed verdict'}
       @{t='DateTime';s='cog_EnteredOn';      l='Entered on'}
       @{t='File';   s='cog_Photo';           l='Photo'}
     )}

  @{ Schema='cog_Outbox'; Display='Outbox'; Plural='Outbox'
     Description='Durable queue of writes destined for F&O. The single record of intent; carries the correlation id used for idempotency.'
     PrimaryName='cog_Name'; PrimaryLabel='Outbox item'
     Attributes=@(
       @{t='Int';    s='cog_OperationType'; l='Operation type'}
       @{t='String'; s='cog_CorrelationId'; l='Correlation id'; max=50; req='ApplicationRequired'}
       @{t='String'; s='cog_Company';       l='Company';        max=4}
       @{t='Memo';   s='cog_Payload';       l='Payload';        max=100000}
       @{t='Int';    s='cog_OutboxStatus';  l='Status'}
       @{t='Int';    s='cog_Attempts';      l='Attempts'}
       @{t='Memo';   s='cog_LastError';     l='Last error';     max=4000}
       @{t='Memo';   s='cog_FnoResponse';   l='F&O response';   max=100000}
       @{t='DateTime';s='cog_QueuedOn';     l='Queued on'}
       @{t='DateTime';s='cog_ProcessedOn';  l='Processed on'}
     )}
)

# ---------------------------------------------------------------- relationships
# Lookups are created after the tables exist.
$script:Relationships = @(
  @{ Name='cog_qualityorder_qualitytestline'; Referenced='cog_qualityorder'; Referencing='cog_qualitytestline'
     Lookup='cog_QualityOrderId'; LookupLabel='Quality order' }
  @{ Name='cog_qualityorder_resultsheet';     Referenced='cog_qualityorder'; Referencing='cog_resultsheet'
     Lookup='cog_QualityOrderId'; LookupLabel='Quality order' }
  @{ Name='cog_resultsheet_resultentry';      Referenced='cog_resultsheet';  Referencing='cog_resultentry'
     Lookup='cog_ResultSheetId'; LookupLabel='Result sheet' }
  @{ Name='cog_resultsheet_outbox';           Referenced='cog_resultsheet';  Referencing='cog_outbox'
     Lookup='cog_ResultSheetId'; LookupLabel='Result sheet' }
)

# ---------------------------------------------------------------- value conventions
# Documented here so flows and Power Fx agree. Mirrors F&O where applicable.
$script:Conventions = @{
  'cog_Status / cog_CurrentResult / cog_Verdict / cog_ComputedVerdict / cog_ImpliedResult' =
    'F&O values: 200000000 = Open or Fail, 200000001 = Fail or Pass, 200000002 = Pass. See phase1/output/OPTION-SETS.md'
  'cog_SheetStatus / cog_OutboxStatus' =
    '1 = Draft, 2 = Queued, 3 = Submitting, 4 = Confirmed, 5 = Needs attention'
  'cog_OperationType' =
    '1 = Post test results, 2 = Post attachment'
  'cog_ReferenceType' =
    'F&O reference type integer, e.g. 200000003 = Production. See phase1/output/OPTION-SETS.md'
}
