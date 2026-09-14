# Flows: `BD_GetBatch` + `BD_UpdateBatchDisposition`

Two small flows for batch disposition (manual §4.4). **Instant cloud flows**, **Power Apps (V2)**.

> ✅ **Confirmed against live metadata.** Entity set = **`PowerAppInventBatches`** (EntityType
> `PowerAppInventBatch`), key **`dataAreaId,itemId,inventBatchId`** (keys are **lowercase**),
> disposition field = **`PdsDispositionCode`**. A plain PATCH sets it — no bound action. New codes
> come from `PowerAppsPdsDispositionMasters`. See `docs/FnO-Data-Model.md` §E.

---

## `BD_GetBatch` — read the current disposition code

### Inputs
| # | Name | Type |
|---|------|------|
| 1 | `company` | Text |
| 2 | `item` | Text |
| 3 | `batch` | Text |

### Actions
1. **List rows** (`GetItems`) or `InvokeHttp` GET:
   ```
   GET /data/PowerAppInventBatches?cross-company=true
       &$filter=dataAreaId eq '@{triggerBody()['text']}'
               and itemId eq '@{triggerBody()['text_1']}'
               and inventBatchId eq '@{triggerBody()['text_2']}'
       &$select=itemId,inventBatchId,PdsDispositionCode
   ```
2. **Condition** — `length(value) > 0`:
   - true → **Respond**: `ok=true`, `number = first(...)?['PdsDispositionCode']`,
     `message = "Batch found"`.
   - false → **Respond**: `ok=false`, `number=""`,
     `message = "Batch not found for that item"`.

> The app reads the current code from `gLookup.number` (see `scrBDScan`), reusing the standard
> envelope's `number` field to carry the code.

---

## `BD_UpdateBatchDisposition` — set a new disposition code

### Inputs
| # | Name | Type |
|---|------|------|
| 1 | `company` | Text |
| 2 | `item` | Text |
| 3 | `batch` | Text |
| 4 | `newCode` | Text |

### Actions
1. **Scope** → **Update a row** (`PatchItem`) or `InvokeHttp` PATCH:
   ```
   key:  PowerAppInventBatches(dataAreaId='@{triggerBody()['text']}',itemId='@{triggerBody()['text_1']}',inventBatchId='@{triggerBody()['text_2']}')
   cross-company: true
   item: { "PdsDispositionCode": "@{triggerBody()['text_3']}" }
   ```
2. **Respond** — success: `ok=true`, `number = batch`,
   `message = concat('Disposition set to ', triggerBody()['text_3'])`.
3. **Catch** (Scope failed): `ok=false`, `number = batch`,
   `message = 'Could not update disposition. Check permissions / code validity.'`.

## Test
In the Power Apps **mobile** app, scan an item + batch, pick a new code, Confirm. Verify the batch
disposition changed in F&O (**Inventory management → Inquiries and reports → Batches**), and that
availability reflects the new code.
