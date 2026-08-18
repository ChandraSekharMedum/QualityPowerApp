# Analysis: "Quality APP -New Icons (Test02)" (usdemo01)

**QM-P2-005 · 2026-08-18 · read-only analysis**

Downloaded `9d927652-ce06-4818-8c7d-0089e8d8eb0a` from `operations-usdemo01.crm.dynamics.com`
and unpacked it. 21 screens. Nothing in that environment was modified.

---

## 1. The fundamental difference: it uses the F&O connector, we use virtual entities

Every F&O data source in that app comes through **one connection**:

```
Fin & Ops Apps (Dynamics 365)  ->  /providers/microsoft.powerapps/apis/shared_dynamicsax
DatasetName: usdemo01.sandbox.operations.dynamics.com
```

Ours goes through **Dataverse virtual entities** (`mserp_*`) because `shared_dynamicsax` was not
usable in `cus-con-sandbox`. That single difference explains most of what they can do and we
could not — it is not that they found cleverer Power Fx.

They talk to F&O data entities by their real names: `QualityOrderHeaders`,
`PowerAppFileSavings`, `AppsInventNonConformations`, `PowerAppInventQOLines`,
`QualityOrderLineResults`, `PowerAppsPdsDispositionMasters`, plus sales, purchase and production
entities. `QualityOrderHeaders` is marked `IsWritable: true`.

---

## 2. Quality order creation — and the field we were missing

`QORouteScreen`, Submit:

```
Patch(QualityOrderHeaders, Defaults(QualityOrderHeaders), {
    'Quality order':  txtRouteQualityOrder.Text,
    'Item number':    txtRouteItemNo.Text,
    Site:             lblRouteSiteValue.Text,
    'Warehouse (WarehouseId)': lblRouteWarehouseValue.Text,
    Quantity:         Value(txtRouteQuantity.Text),
    'Inventory status':        lblRouteInventoryStatusValue.Text,
    'Reference lot':           lblRouteLotIdValue.Text,
    'Route number':            lblRORouteIdValue.Text,
    'Oper. No.':               Value(lblROOprNoValue.Text),
    Operation:                 lblROOprNameValue.Text,
    Company:                   "usmf",
    'Test group':              lblRouteTestGroupIdValue.Text,
    'Reference type (ReferenceType)': lblRouteRefTypeValue.Text,
    'Reference number':        lblRouteRefValue.Text,
    'Product name':            txtRouteProdName.Text,
    'Dimension number':        "AllBlank"          <-- InventDimensionId
})
```

**`'Dimension number': "AllBlank"` is the interesting line.** It maps to `InventDimensionId`.
Our Phase 1 conclusion was that quality order creation fails on an **Owner dimension** problem.
This app supplies a literal inventory dimension id of `AllBlank` and does **not** set `Owner`
at all.

### This is testable in our environment

`mserp_inventqualityorderheaderentities` **exists in `cus-con-sandbox`** (79 attributes), and
every field the demo writes reports `IsValidForCreate = True`, including:

| Field | Create |
|---|---|
| `mserp_inventdimensionid` | True |
| `mserp_inventoryownerid` | True |
| `mserp_qualityordernumber`, `mserp_itemnumber`, `mserp_inventorysiteid`, `mserp_warehouseid` | True |
| `mserp_inventoryquantity`, `mserp_inventorystatusid`, `mserp_referenceinventorylotid` | True |
| `mserp_qualitytestgroupid`, `mserp_referencetype`, `mserp_inventrefid`, `mserp_productname` | True |

### PROBED 2026-08-18 — quality order creation WORKS, and the diagnosis was wrong

Three creates succeeded against `mserp_inventqualityorderheaderentities` in `cus-con-sandbox`:

```
ARM A  no Dimension number            -> CREATED QO 000274
ARM B  Dimension number = "AllBlank"  -> CREATED QO 000276
ARM C  Dimension number = "000605"    -> CREATED QO 000278
```

**Arm A succeeded without any dimension number at all**, so `AllBlank` was not the missing
ingredient either. The real blockers were two ordinary things:

1. **Do not supply the quality order number.** Passing one gives
   `Field 'Quality order' does not allow editing; Invalid specification of Quality order;
   Number sequence Inve_172 does not allow change to a higher number.`
   F&O assigns it from the number sequence and returns it on the created record.
2. **The reference must be real.** `Reference type` + `Reference number` + `Reference lot` have
   to point at an actual source line with inventory. Getting this wrong produces honest errors:
   `The value '000026' in field 'Reference number' is not found in the related table 'Purchase
   order lines'` and `No quantity available for item A0001`.

The successful payload cloned the reference of an existing open order:

```
mserp_itemnumber              A0001
mserp_inventorysiteid         2
mserp_warehouseid             24
mserp_inventoryquantity       1
mserp_qualitytestgroupid      Impedance
mserp_referencetype           200000002        (Purchase)
mserp_inventrefid             00000175         (the purchase order)
mserp_referenceinventorylotid 478937           (the inventory lot)
mserp_inventorystatusid       Available
mserp_dataareaid              usmf
```

**F&O generated the test lines itself** — each order came back with its `impedance measure`
line at sequence 10, `resultlinenumber` 1. That confirms the domain rule: the header creates the
lines from the test group.

All three probe orders were deleted afterwards; deletion works.

**So the Phase 1 conclusion that quality order creation is blocked by an Owner-dimension defect
is wrong.** It is buildable. What it needs is a source-document picker — the user chooses a
purchase order line, production order or inventory lot that actually has stock — which is
exactly what the demo app's four QO screens are for.

---

## 3. Attachments — one difference that matters, verified against our environment

They target the **same entity we do**, `PowerAppFileSavings`:

```
Patch(PowerAppFileSavings, Defaults(PowerAppFileSavings), {
    DisplayOrderNumber: lblOrderIdValue.Text,
    ImageVarchar: Substitute(JSON(PreviewImage.Image, JSONFormat.IncludeBinaryData), """", ""),
    FormName:     lblFormName.Text,
    TestSequence: Value(First(FileAttachCollection).TestSeq),
    TestId:       First(FileAttachCollection).DisplayName,
    LineNum:      Value(First(FileAttachCollection).LineNum),
    FileName:     AddMediaButton1.FileName,
    dataAreaId:   "USMF",
    TableRefId:   "0000"
})
```

Differences from what we built, and what to do about each:

| Their app | Ours | Verdict |
|---|---|---|
| `Substitute(JSON(...), """", "")` — strips **only the quotes**, so `ImageVarchar` keeps the full `data:image/jpeg;base64,...` prefix | We strip the prefix and send raw base64 | **Adopt theirs.** Probed: F&O accepts both, and the prefix is preserved on read-back. Since we cannot verify rendering over OData, matching the working reference is the lower-risk choice |
| `TableRefId: "0000"` — a constant | We send the quality order number | **Adopt theirs.** Probed and accepted. Phase 1 called this field required; it clearly just needs *something* |
| `addMedia` control (Add picture) — on a device this opens the camera or gallery | `Camera` control — live in-app capture | **Keep ours**, given "images taken from camera of the device". Theirs also allows a full-resolution gallery photo, which would blow the 1 MiB cap |
| `LineNum` from the QO line | We send 0 — our cache has no line number | **Adopt theirs.** `mserp_resultlinenumber` exists on `mserp_inventqualityorderlineresultentity`; add it to `cog_QualityTestLine` and the sync |
| No size check anywhere | We refuse >1,048,576 chars before queuing | **Keep ours** — they would hit the same wall with no warning |
| Direct `Patch` to F&O | Outbox + drain flow | **Keep ours** — theirs cannot work offline and has no retry or idempotency |

---

## 4. Non-conformance creation

```
Patch(AppsInventNonConformations, Defaults(AppsInventNonConformations), {
    InventNonConformanceID: "99",              <-- dummy; F&O assigns the real number
    InventNonConformanceType: ParmNCRefValue,
    InventRefId:  lblQualityOrdNum.Text,
    dataAreaId:   "USMF",
    InventTestProblemTypeId: cmb...Selected.'Problem type',
    NonConformanceDate: ...SelectedDate,
    Description:  DescInputInternal.Text        <-- exists on the POWERAPPS entity
})
```

Two things worth having:

- **They pass a dummy id `"99"` and F&O assigns the real number**, read back via
  `Last(NonConformanceTables).'Non conformance number'`. We generate `NC-yymmdd-<hex>` ourselves
  because the base entity assigns nothing. If the `POWERAPPS` entity behaves the same way through
  virtual entities, our whole numbering-scheme governance question (R7) disappears. **Worth
  probing** — it was never tested this way.
- **`Description` exists on `AppsInventNonConformations`** (the `POWERAPPS` entity) but not on the
  base entity we had to use. Our "there is nowhere to put a description" finding is a limitation
  of the *base* entity, not of F&O. If the POWERAPPS entity can be made to accept creates here,
  we get the manual's Description field back.

They also use `InventRefId` to hold the quality order number for an internal NC — the same choice
we made, independently.

---

## 5. What is reusable

**Directly reusable now** (no environment change needed):

1. `ImageVarchar` including the data-URI prefix, and `TableRefId: "0000"` — both probed and
   accepted in our environment.
2. `LineNum` sourced from `mserp_resultlinenumber` — add to the test-line cache.
3. `'Dimension number': "AllBlank"` as the quality order creation hypothesis.
4. The `"99"` dummy-id pattern for NC numbering, if the POWERAPPS entity accepts creates.

**Reusable only if `shared_dynamicsax` is fixed in our tenant:** their whole data layer. That is
a connector/tenant issue, not something to design around — but it is worth re-testing, because
if that connector works in `cus-con-sandbox` it collapses a lot of our machinery.

**Do not copy:** direct `Patch` to F&O with no queue, hardcoded `"USMF"` throughout, no size
guard, no idempotency, no offline story, and `Errors()` checked immediately after `Patch` as the
only error handling. Our outbox design is stronger on every one of those.

---

## 6. Recommended next steps

1. **Probe quality order creation** with `mserp_inventdimensionid = 'AllBlank'`. Highest value —
   it may reopen the one feature we wrote off. Needs a decision first, since it creates a real
   order.
2. **Switch our attachment payload to the data-URI form** and `TableRefId "0000"`. Small change,
   removes a rendering risk we cannot otherwise test.
3. **Add `mserp_resultlinenumber`** to `cog_QualityTestLine` and the sync, then send a real
   `LineNum`.
4. **Re-probe `POWERAPPSINVENTNONCONFORMATIONENTITY`** for create with a dummy id, to recover
   F&O-assigned numbering and the Description field.
5. **Re-test `shared_dynamicsax`** in `cus-con-sandbox`.
