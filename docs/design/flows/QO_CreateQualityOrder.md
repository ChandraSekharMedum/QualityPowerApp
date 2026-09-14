# Flow: `QO_CreateQualityOrder`

Creates a quality order in F&O for any of the 7 sources. **Instant cloud flow**, **Power Apps
(V2)** trigger.

> ✅ **Confirmed against live metadata.** Target entity set = **`QualityOrderHeaders`** (EntityType
> `QualityOrderHeader`), key `dataAreaId,QualityOrderNumber`. A plain insert creates the order — no
> custom entity or bound action needed. `ReferenceType` + the source‑specific reference field drive
> which kind of order is created (see `docs/FnO-Data-Model.md` §B and the enum map in §0).

## Trigger inputs (exact order — matches `btnSubmit.OnSelect`)

| # | Name | Type | Example |
|---|------|------|---------|
| 1 | `company` | Text | `usmf` |
| 2 | `source` | Text | `Sales` |
| 3 | `account` | Text | `US-004` (blank for Inventory/Production/…) |
| 4 | `refNo` | Text | `000123` |
| 5 | `operation` | Text | `` (Route Operation only) |
| 6 | `item` | Text | `D0001` |
| 7 | `refLot` | Text | `LOT-000001` |
| 8 | `testGroup` | Text | `TG-STD` |
| 9 | `qty` | Number | `10` |
| 10 | `dimsJson` | Text | `{"InventSiteId":"1","InventLocationId":"13",...}` |

## Actions

### 1. Parse `dimsJson`
**Data Operation → Parse JSON**. Content = `triggerBody()['text_9']` (the `dimsJson`). Schema =
the inventory‑dimensions object (Site/Location/WMSLocation/Batch/Status/Config/Color/Size/Style/LicensePlate).

### 1b. Map `source` → `ReferenceType` enum label
**Compose `RefType`** — the app sends `Sales/Purchase/Inventory/Production/RouteOperation/CoProduct/Quarantine`;
F&O wants the enum label:
```
@{if(equals(triggerBody()['text_1'],'Purchase'),'Purch',
   if(equals(triggerBody()['text_1'],'RouteOperation'),'RouteOpr',
   if(equals(triggerBody()['text_1'],'CoProduct'),'PmfProdCoBy',
   triggerBody()['text_1'])))}      // Sales/Inventory/Production/Quarantine pass through
```

### 2. Scope: `Create QO`  (`PostItem` on `QualityOrderHeaders`)
Inside a **Scope** (so we can catch failures). Set the **source‑specific reference field** by
`source`; common fields always. (Fin & Ops connector `PostItem`; HTTP‑with‑Entra‑ID fallback uses
the same fields as a `concat()` string body — see the pattern below.)
```
table: QualityOrderHeaders
cross-company: true
item:
{
  "dataAreaId": "@{triggerBody()['text']}",                 // company
  "ReferenceType": "@{outputs('RefType')}",                 // enum label
  "QualityTestGroupId": "@{triggerBody()['text_7']}",       // testGroup
  "ItemNumber": "@{triggerBody()['text_5']}",
  "InventoryQuantity": @{triggerBody()['number']},          // qty (numeric!)

  // --- source-specific reference (send only the relevant one) ---
  "SalesOrderNumber":      "@{if(equals(triggerBody()['text_1'],'Sales'),    triggerBody()['text_3'], '')}",
  "CustomerAccountNumber": "@{if(equals(triggerBody()['text_1'],'Sales'),    triggerBody()['text_2'], '')}",
  "PurchaseOrderNumber":   "@{if(equals(triggerBody()['text_1'],'Purchase'), triggerBody()['text_3'], '')}",
  "VendorAccountNumber":   "@{if(equals(triggerBody()['text_1'],'Purchase'), triggerBody()['text_2'], '')}",
  "ProductionOrderNumber": "@{if(or(equals(triggerBody()['text_1'],'Production'),equals(triggerBody()['text_1'],'RouteOperation'),equals(triggerBody()['text_1'],'CoProduct')), triggerBody()['text_3'], '')}",
  "RouteOperationId":      "@{if(equals(triggerBody()['text_1'],'RouteOperation'), triggerBody()['text_4'], '')}",
  "InventRefId":           "@{if(equals(triggerBody()['text_1'],'Quarantine'), triggerBody()['text_3'], '')}",

  // --- inventory dimensions (carried on the header; Inventory source fills these) ---
  "InventorySiteId":     "@{body('Parse_dimsJson')?['InventSiteId']}",
  "WarehouseId":         "@{body('Parse_dimsJson')?['InventLocationId']}",
  "WarehouseLocationId": "@{body('Parse_dimsJson')?['wMSLocationId']}",
  "InventoryStatusId":   "@{body('Parse_dimsJson')?['inventStatusId']}",
  "ProductConfigurationId": "@{body('Parse_dimsJson')?['configId']}",
  "ProductColorId":      "@{body('Parse_dimsJson')?['InventColorId']}",
  "ProductSizeId":       "@{body('Parse_dimsJson')?['InventSizeId']}",
  "ProductStyleId":      "@{body('Parse_dimsJson')?['InventStyleId']}",
  "LicensePlateNumber":  "@{body('Parse_dimsJson')?['licensePlateId']}",
  "ReferenceInventoryLotId": "@{triggerBody()['text_6']}"    // refLot
}
```
> `RouteOperation` also has `ProductionOrderRouteOperationNumber` (Int32) if you capture the
> operation number as an integer; add it when your route‑op lookup returns it.

For the **HTTP‑with‑Entra‑ID fallback**, POST the same fields to
`.../data/QualityOrderHeaders?cross-company=true` with `request/body` built as a `concat()`
**string** (numbers unquoted). See `docs/FnO-Data-Model.md` and the skill notes for the string‑body rule.

### 3. Capture the assigned number
- Connector `PostItem`: read `body('Create_QO')?['QualityOrderNumber']`.
- HTTP: **Parse JSON** on `body('Create_QO')?['body']`, then `?['QualityOrderNumber']`. (The
  assigned number is also in the `Location` response header.)

### 4. Respond — success (inside the Scope's happy path)
**Respond to a PowerApp or flow**: `ok = true`, `number = <QualityOrderNumber>`,
`message = "Quality order created"`.

### 5. Catch — failure
Add a parallel **Respond** with **Configure run after** = *Create QO / Scope* **has failed /
timed out**. Set `ok = false`, `number = ""`, `message =` a readable error, e.g.:
```
@{coalesce(
   body('Create_QO')?['body']?['error']?['message'],
   result('Create_QO')[0]?['error']?['message'],
   'Quality order creation failed. Check flow run history.')}
```

## Test
Run the flow with a known Sales order + test group. Confirm the quality order appears in F&O
(**Inventory management → Periodic → Quality management → Quality orders**), and the app shows the
returned number on `scrSuccess`.
