# F&O Data Model — the OData contract this app depends on

All access is via F&O OData: `https://cus-con-sandbox.sandbox.operations.dynamics.com/data/<Entity>`.

> ✅ **Verified against this environment's live `$metadata` (2026‑07‑14).** The entity names, keys,
> fields, and enum values below were read directly from the F&O metadata of
> `cus-con-sandbox.sandbox.operations.dynamics.com`. This environment ships the purpose‑built
> **`PowerApp*` quality entities**, so no custom entity is required — the app inserts/patches these
> directly. Fields still marked *(verify)* are ones whose exact runtime behavior (e.g. which
> account field a lean entity resolves) should be confirmed with a live write.

Rules that apply to **every** call:
- Add **`?cross-company=true`** to every read and write.
- Send **`dataAreaId`** (lowercase legal‑entity code) in the body of every write.
- Field names are **case‑sensitive** exactly as below (note some keys are lowercase, e.g. `itemId`).
- Enum properties are sent as the **string member label** (e.g. `"ReferenceType": "Sales"`).
- A successful create returns **201** + a `Location` header containing the assigned key.

---

## 0. Enum reference (confirmed from metadata)

| Enum | Members (label used on the wire) |
|------|----------------------------------|
| **`InventTestReferenceType`** (QO source) | `Inventory`, `Sales`, `Purch`, `Production`, `Quarantine`, `RouteOpr`, `PmfProdCoBy` (co/by‑product), + `WHSInboundShipmentOrder`, `ITMGoodsInTransitOrder`, `QMSReturn`, `QMSTransfer` |
| **`InventNonConformanceType`** (NC type) | `Internal`, `Cust`, `Vend`, `Service`, `Production`, `PmfProdCoBy` |
| **`InventTestOutcomeStatus`** (test result) | `Fail`, `Pass` |
| **`InventTestOrderStatus`** (QO status) | `Open`, `Fail`, `Pass` |

### App source → enum mapping (use these exact labels in the flows)

| App QO source | `ReferenceType` | App NC type | `InventNonConformanceType` |
|---|---|---|---|
| Sales | `Sales` | Internal | `Internal` |
| Purchase | `Purch` | Customer | `Cust` |
| Inventory | `Inventory` | Vendor | `Vend` |
| Production | `Production` | Service | `Service` |
| Route Operation | `RouteOpr` | Production | `Production` |
| Co‑Product Production | `PmfProdCoBy` | Co‑product | `PmfProdCoBy` |
| Quarantine | `Quarantine` | | |

---

## A. Reference / lookup entities (R)

| Concept | Entity set | Key fields to `$select` |
|---|---|---|
| Customers | `CustomersV3` | `CustomerAccount`, `OrganizationName` |
| Vendors | `VendorsV2` | `VendorAccountNumber`, `VendorOrganizationName` |
| Released products (items) | `ReleasedProductsV2` | `ItemNumber`, `ProductName` |
| Sales order lines | `SalesOrderLines` | `SalesOrderNumber`, `ItemNumber`, `LineNumber`, `ShippingSiteId`, `ShippingWarehouseId` |
| Purchase order lines | `PurchaseOrderLinesV2` | `PurchaseOrderNumber`, `ItemNumber`, `LineNumber` |
| Production orders | `ProductionOrderHeaders` | `ProductionOrderNumber`, `ItemNumber` |
| Quarantine orders | **`PowerAppsInventQuarantineOrders`** | `QuarantineId`, `ItemId`, `InventorySiteId`, `WareHouseId`, `InventDimId` |
| **Test groups** | **`QualityTestGroups`** | `QualityTestGroupId`, `Description` |
| **Problem types** | **`PowerAppProblemTypeDatas`** | `ProblemTypeId`, `Description` |
| **Disposition codes** | **`PowerAppsPdsDispositionMasters`** | `DispositionCode`, `Description`, `Status` |
| **Batches** | **`PowerAppInventBatches`** | `itemId`, `inventBatchId`, `PdsDispositionCode` (keys are **lowercase**) |
| Warehouses | `Warehouses` | `WarehouseId`, `WarehouseName`, `SiteId` |
| Sites | `OperationalSites` | `SiteId`, `SiteName` |

**Read pattern:**
```http
GET /data/QualityTestGroups?cross-company=true&$select=QualityTestGroupId,Description&$top=500&$filter=dataAreaId eq 'usmf'
```

---

## B. Quality Order creation (W) — manual §4.1

**Entity set: `QualityOrderHeaders`** (EntityType `QualityOrderHeader`).
**Key:** `dataAreaId`, `QualityOrderNumber` (server‑assigned on insert).

Set `ReferenceType` to the enum label (§0) and populate the source‑specific reference field:

| App source | `ReferenceType` | Reference field(s) to set | Account field |
|---|---|---|---|
| Sales | `Sales` | `SalesOrderNumber` | `CustomerAccountNumber` |
| Purchase | `Purch` | `PurchaseOrderNumber` | `VendorAccountNumber` |
| Inventory | `Inventory` | (dims only) | — |
| Production | `Production` | `ProductionOrderNumber` | — |
| Route Operation | `RouteOpr` | `ProductionOrderNumber`, `ProductionOrderRouteOperationNumber` (Int32), `RouteOperationId` | — |
| Co‑Product | `PmfProdCoBy` | `ProductionOrderNumber` | — |
| Quarantine | `Quarantine` | `InventRefId` (quarantine order) | — |

**Common fields (all sources):** `QualityTestGroupId`, `ItemNumber`, `InventoryQuantity` (Decimal),
and inventory dimensions carried **directly on the header**:
`InventorySiteId`, `WarehouseId`, `WarehouseLocationId`, `ItemBatchNumber`, `InventoryStatusId`,
`LicensePlateNumber`, `ProductColorId`, `ProductSizeId`, `ProductStyleId`,
`ProductConfigurationId`, `ReferenceInventoryLotId` / `InventoryLotId`, `InventDimensionId`.
(No separate dimensions entity — this is simpler than a classic `InventDim` split.)

`QualityOrderStatus` is `InventTestOrderStatus` (`Open` on create). **Result:** flow returns
`{ ok, number: "<QualityOrderNumber>", message }`.

---

## C. Enter Test Results (W) — manual §4.2

Two entities: **read** the lines, **write** the results.

**Read the test lines — `InventQualityOrderLinesPowerApp`** (EntityType `InventQualityOrderLinePowerApp`).
**Key:** `dataAreaId`, `QualityOrderNumber`, `QualityOrderSequenceNumber` (Int32).
Useful fields: `QualityTestId`, `QualityTestOutcomeStatus` (`InventTestOutcomeStatus`),
`QualityTestResultValue`, `TestMeasurementUnitSymbol`, `DefaultQualitativeTestMeasurementOutcome`,
`StandardQuantitativeTestMeasurement`, lower/upper limit fields.

**Write the results — `QualityOrderLineResults`** (EntityType `QualityOrderLineResult`).
**Key:** `dataAreaId`, `QualityOrderNumber`, `QualityOrderSequenceNumber`, `QualityTestId`, `ResultLineNumber`.
Write: `TestResult` (`Pass`/`Fail` enum), `ResultInventoryQuantity` (Decimal), `ResultValue` (Decimal),
`QualityTestVariableOutcomeId` (for qualitative outcomes).

> The app grid must carry **`QualityOrderSequenceNumber`** per line (from the read), not just a test
> id — it's part of the result key. The `TR_SubmitTestResult` line contract includes it.

**Result:** `{ ok, number: "<QualityOrderNumber>", message }`.

---

## D. Create NC — Non‑conformance (W) — manual §4.3

Two candidate entities; **neither is a superset** — this is the one decision to confirm live:

**Primary (recommended): `AppsInventNonConformations`** (EntityType `AppsInventNonConformation`).
**Key:** `dataAreaId`, `InventNonConformanceID`. Fields:
`InventNonConformanceType` (enum §0), `NonConformanceDate` (DateTimeOffset, **full ISO**),
`Description`, `InventTestProblemTypeId`, `InventRefId` (source order), `InventTransIdRef`
(inventory transaction / lot ref), `VendAccount`, `InventTransType` (`InventTransType` enum),
`TestDefectQty`, `UnitId`.
→ Purpose‑built for the app; **has `Description` + problem type**. ⚠ **Has `VendAccount` but no
`CustAccount` and no `ItemId`/`InventDimId`** — for Customer/Service NCs it must resolve the
customer/item/dims from `InventRefId` + `InventTransIdRef`. **(verify with a live customer NC.)**

**Alternative: `NonConformanceTables`** (EntityType `NonConformanceTable`).
Has `CustAccount` **and** `VendAccount`, `ItemId`, `InventDimId`, `InventTestProblemTypeId`,
`InventNonConformanceType`, `InventRefId`, `InventTransIdRef`, `NonConformanceDate`, `TestDefectQty`,
`QuarantineZoneId` — but **no `Description` field**.

> **Recommendation:** use `AppsInventNonConformations` (matches the app's design + carries the
> description the manual requires). Confirm on a live Customer NC that account/item resolve from
> the references; if not, switch that path to `NonConformanceTables` and drop the description onto
> an attachment/note. Flagged in `Architecture.md` §5.

**Result:** `{ ok, number: "<InventNonConformanceID>", message }`.

---

## E. Manage Batch Disposition (W) — manual §4.4

**Entity set: `PowerAppInventBatches`** (EntityType `PowerAppInventBatch`).
**Key (lowercase!):** `dataAreaId`, `itemId`, `inventBatchId`. Disposition field: **`PdsDispositionCode`**.

- **Read current code:** `GET /data/PowerAppInventBatches?cross-company=true&$filter=dataAreaId eq 'usmf' and itemId eq 'D0001' and inventBatchId eq 'B-000045'&$select=itemId,inventBatchId,PdsDispositionCode`
- **Update:** `PATCH PowerAppInventBatches(dataAreaId='usmf',itemId='D0001',inventBatchId='B-000045')`
  body `{ "PdsDispositionCode": "AVAILABLE" }`.

Valid new codes come from `PowerAppsPdsDispositionMasters` (`DispositionCode`, `Description`).
No bound action needed — a plain PATCH sets it. **Result:** `{ ok, number: "<batch>", message }`.

---

## F. Attachments / images
App captures images (test‑result and NC screens) and sends `{ name, base64 }`. Store via:
1. **F&O document attachments (`DocuRefEntity`)** — keeps the image with the F&O record; the flow
   posts the base64 + a reference to the created record. **(verify `DocuRefEntity` is enabled.)**
2. **Dataverse file column** — a small row referencing the F&O number. Reliable fallback.

---

## G. Environment values (this environment)

| Value | Confirmed |
|---|---|
| F&O base URL | `https://cus-con-sandbox.sandbox.operations.dynamics.com` |
| Dataverse URL | `https://operations-cus-con-sandbox.crm.dynamics.com` |
| `dataAreaId` codes | ⏳ confirm the legal entities you'll write to (e.g. `usmf`) via a live read |
| QO create | `QualityOrderHeaders` ✅ |
| Test‑result submit | read `InventQualityOrderLinesPowerApp` → write `QualityOrderLineResults` ✅ |
| NC create | `AppsInventNonConformations` ✅ (customer‑resolution *verify*) |
| Batch | `PowerAppInventBatches` (`PdsDispositionCode`) ✅ |
| Attachment target | ⏳ choose `DocuRefEntity` vs Dataverse |
