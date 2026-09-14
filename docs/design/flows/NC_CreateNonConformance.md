# Flow: `NC_CreateNonConformance`

Creates a non‑conformance order for one of 6 sources, with an optional image attachment.
**Instant cloud flow**, **Power Apps (V2)** trigger.

> ✅ **Confirmed against live metadata.** Target = **`AppsInventNonConformations`** (EntityType
> `AppsInventNonConformation`), key `dataAreaId,InventNonConformanceID`. It carries the
> `Description` the manual requires. ⚠ It has `VendAccount` but **no `CustAccount`/`ItemId`** — for
> Customer/Service NCs it resolves those from `InventRefId`+`InventTransIdRef`; **verify on a live
> customer NC**, and if it doesn't resolve, switch that path to `NonConformanceTables` (has
> `CustAccount` but no `Description`). See `docs/FnO-Data-Model.md` §D.

## Trigger inputs (exact order)

| # | Name | Type | Example |
|---|------|------|---------|
| 1 | `company` | Text | `usmf` |
| 2 | `ncType` | Text | `Customer` |
| 3 | `dateIso` | Text | `2026-07-13T00:00:00Z` |
| 4 | `problemType` | Text | `PT-DAMAGE` |
| 5 | `account` | Text | `US-004` (blank when N/A) |
| 6 | `refNo` | Text | `000123` |
| 7 | `refLot` | Text | `LOT-000001` (blank when N/A) |
| 8 | `item` | Text | `D0001` |
| 9 | `dimsJson` | Text | `{"InventSiteId":"1","InventLocationId":"13","InventBatchId":""}` |
| 10 | `description` | Text | free text |
| 11 | `attachName` | Text | `nc.jpg` (or blank) |
| 12 | `attachB64` | Text | data URL (or blank) |

## Actions

### 1. Parse `dimsJson`
**Parse JSON** — Content = `triggerBody()['text_8']`. Schema = `{InventSiteId, InventLocationId, InventBatchId}`.

### 2. Map `ncType` → `InventNonConformanceType` enum label
**Compose `NCType`** — the app sends `Internal/Customer/Vendor/Service/Production/CoProduct`:
```
@{if(equals(triggerBody()['text_1'],'Customer'),'Cust',
   if(equals(triggerBody()['text_1'],'Vendor'),'Vend',
   if(equals(triggerBody()['text_1'],'CoProduct'),'PmfProdCoBy',
   triggerBody()['text_1'])))}      // Internal/Service/Production pass through
```

### 3. Scope: `Create NC`  (`PostItem` on `AppsInventNonConformations`)
```
table: AppsInventNonConformations
cross-company: true
item:
{
  "dataAreaId": "@{triggerBody()['text']}",
  "InventNonConformanceType": "@{outputs('NCType')}",
  "NonConformanceDate": "@{triggerBody()['text_2']}",       // full ISO from the app
  "InventTestProblemTypeId": "@{triggerBody()['text_3']}",  // problemType
  "InventRefId": "@{triggerBody()['text_5']}",              // refNo (SO/PO/Prod/Batch/QO)
  "InventTransIdRef": "@{triggerBody()['text_6']}",         // refLot / inventory-transaction ref
  "VendAccount": "@{if(equals(triggerBody()['text_1'],'Vendor'), triggerBody()['text_4'], '')}",
  "Description": "@{triggerBody()['text_9']}"
}
```
> For **Customer/Service**, the customer arrives in `account` (text_4) but this entity has no
> `CustAccount` — F&O should resolve the customer from `InventRefId` (the sales order). **Verify**;
> if it doesn't, POST to `NonConformanceTables` instead with `CustAccount = triggerBody()['text_4']`,
> `ItemId = triggerBody()['text_7']`, and move the description to an attachment/note.
> HTTP‑with‑Entra‑ID fallback: same fields as a `concat()` **string** body (see `QO_CreateQualityOrder.md`).

### 4. Capture NC number
`body('Create_NC')?['InventNonConformanceID']` (or Parse JSON on the HTTP body / read the `Location`
header).

### 5. Optional attachment
Same as `TR_SubmitTestResult` §4 — split on `base64,`, post to `DocuRefEntity`/Dataverse
referencing the NC number.

### 6. Respond
- Success: `ok=true`, `number = <InventNonConformanceID>`, `message = "Non-conformance created"`.
- Catch: `ok=false`, `message =` F&O error (see `QO_CreateQualityOrder.md` §5 pattern).

## Test
Create a Customer NC in the app with a problem type, sales order, description, and photo. Confirm
the NC in F&O (**Inventory management → Quality management → Non conformances**).
