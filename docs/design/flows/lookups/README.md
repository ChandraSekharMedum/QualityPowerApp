# Lookup (read) flows

Small **Power Apps (V2)** flows that feed the app's dropdowns. Each does one F&O `GetItems`/GET
and returns **one text output `items`** = a JSON string the app parses with `ParseJSON`.

Why return a JSON string (not native array)? The Power Apps (V2) trigger's response typing is
simplest with a single text field, and the app already parses these with `ParseJSON(...).items`.

## Standard shape (all lookups)

**Trigger inputs:** `company` (Text) + optional `search` (Text) for type‑ahead.

**Action — List rows (`GetItems`) / InvokeHttp GET:**
```
GET /data/<Entity>?cross-company=true
    &$select=<key fields>
    &$top=200
    &$filter=dataAreaId eq '@{triggerBody()['text']}'
            [ and startswith(<label field>,'@{triggerBody()['text_1']}') ]
```

**Action — Respond:** text output `items = string(body('List_rows')?['value'])`
(for `InvokeHttp`, `items = string(body('List_rows')?['body']?['value'])`).

## The flows to build

| Flow | Entity | `$select` | Search field |
|------|--------|-----------|--------------|
| `Lookup_Customers` | `CustomersV3` | `CustomerAccount,OrganizationName` | `OrganizationName` |
| `Lookup_Vendors` | `VendorsV2` | `VendorAccountNumber,VendorOrganizationName` | `VendorOrganizationName` |
| `Lookup_Items` | `ReleasedProductsV2` | `ItemNumber,ProductName` | `ProductName` |
| `Lookup_TestGroups` | `QualityTestGroups` ✅ | `QualityTestGroupId,Description` | `Description` |
| `Lookup_ProblemTypes` | `PowerAppProblemTypeDatas` ✅ | `ProblemTypeId,Description` | `Description` |
| `Lookup_DispositionCodes` | `PowerAppsPdsDispositionMasters` ✅ | `DispositionCode,Description` | `Description` |
| `Lookup_SalesOrders` | `SalesOrderLines` ✅ | `SalesOrderNumber,ItemNumber,LineNumber,ShippingSiteId,ShippingWarehouseId` | `SalesOrderNumber` (filter by customer) |
| `Lookup_PurchaseOrders` | `PurchaseOrderLinesV2` ✅ | `PurchaseOrderNumber,ItemNumber,LineNumber` | `PurchaseOrderNumber` (filter by vendor) |
| `Lookup_ProductionOrders` | `ProductionOrderHeaders` | `ProductionOrderNumber,ItemNumber` | `ProductionOrderNumber` |
| `Lookup_QuarantineOrders` | `PowerAppsInventQuarantineOrders` ✅ | `QuarantineId,ItemId,InventorySiteId,WareHouseId` | `QuarantineId` |
| `Lookup_Batches` | `PowerAppInventBatches` ✅ | `itemId,inventBatchId,PdsDispositionCode` | `inventBatchId` (filter by `itemId`) |
| `Lookup_RefLots` | `SalesOrderLines`/`PurchaseOrderLinesV2` | item + dims + `InventLotId` | filter by reference number |
| `Lookup_QualityOrders` | `QualityOrderHeaders` ✅ | `QualityOrderNumber,ReferenceType,ItemNumber,InventoryQuantity` | filter by item/`QualityOrderStatus eq 'Open'` |
| `Lookup_QOTestLines` | `InventQualityOrderLinesPowerApp` ✅ | `QualityOrderSequenceNumber,QualityTestId` | filter by `QualityOrderNumber` |
| `Lookup_Sites` / `Lookup_Warehouses` | `OperationalSites` / `Warehouses` | ids + names | — (Inventory QO) |

✅ = entity name verified against this environment's live `$metadata` (2026‑07‑14). `Lookup_QOTestLines`
returns the **`QualityOrderSequenceNumber`** each result write needs (part of the result key).

## Performance notes
- Small, static lists (test groups, problem types, disposition codes) are cached once in
  `App.OnStart` — those flows run at launch, not per keystroke.
- Large lists (customers, items, orders) pass `search` and cap `$top` so each keystroke returns a
  small page. Set the combo boxes' `IsSearchable = true` and call the flow in `OnChange`, or use
  `SearchText` in `Items` as shown in the screen specs.
