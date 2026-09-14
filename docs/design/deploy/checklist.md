# Execution checklist

Work top to bottom. See `docs/Build-Guide.md` for detail on each block.

## A. F&O prep  ← DO THIS FIRST
Entities already **verified** against live `$metadata` (see `docs/FnO-Data-Model.md`) — the items
below are the few things left to confirm on this environment.
- [x] F&O base URL: `https://cus-con-sandbox.sandbox.operations.dynamics.com`
- [x] Create paths confirmed: QO=`QualityOrderHeaders`, TR=`QualityOrderLineResults`, NC=`AppsInventNonConformations`, Batch=`PowerAppInventBatches`.
- [ ] Record legal‑entity codes (`dataAreaId`, lowercase) via a live read: __________________
- [ ] **Verify NC customer‑resolution**: does a live Customer NC on `AppsInventNonConformations` resolve the customer from `InventRefId`? If not, switch to `NonConformanceTables`. ______
- [ ] Choose **attachment target** (`DocuRefEntity` / Dataverse): __________________
- [ ] Service/integration account has F&O user mapping + read/write role.

## B. Connection
- [ ] Create F&O connection (Fin & Ops connector **or** HTTP‑with‑Entra‑ID, Resource URI = base URL).
- [ ] Prefer a service account. Record connection name: __________________

## C. Lookup flows
- [ ] `Lookup_TestGroups`, `Lookup_ProblemTypes`, `Lookup_DispositionCodes` (cached at OnStart).
- [ ] `Lookup_Customers`, `Lookup_Vendors`, `Lookup_Items`.
- [ ] Order lookups: Sales, Purchase, Production, Route ops, Quarantine, RefLots.
- [ ] `Lookup_QualityOrders`, `Lookup_QOTestLines`.
- [ ] Inventory lookups: Sites, Warehouses, Statuses, License plates.
- [ ] Each tested (returns JSON in Run → Test).

## D. Write flows (test each standalone)
- [ ] `QO_CreateQualityOrder` → creates a quality order in F&O.
- [ ] `TR_SubmitTestResult` → writes outcomes (+ attachment).
- [ ] `NC_CreateNonConformance` → creates an NC (+ attachment).
- [ ] `BD_GetBatch` → returns current disposition code.
- [ ] `BD_UpdateBatchDisposition` → changes the code in F&O.

## E. App
- [ ] Blank **phone** canvas app `QualityManagement`.
- [ ] Components built (header, nav, lookup, field, busy).
- [ ] `theme.fx` + `App.OnStart.fx` pasted into App.OnStart; OnStart run once.
- [ ] All flows added via Power Automate menu.
- [ ] Screens built from `canvas-app/screens/*.md`; `.Run()` arg order matches each flow.

## F. Functional test matrix (against known F&O data)
- [ ] **Quality Order** — create one of each: Sales, Purchase, Inventory, Production, Route, Co‑product, Quarantine. Each appears in F&O.
- [ ] **Test Results** — load an order, set Pass + Fail, attach a photo, submit. Verified in F&O.
- [ ] **Create NC** — create Internal, Customer, Vendor, Service, Production, Co‑product. Each appears in F&O.
- [ ] **Batch Disposition** (mobile) — scan item + batch, change code, confirm. Verified in F&O.
- [ ] Company switch in Settings routes writes to the right `dataAreaId`.
- [ ] Error path: submit an invalid record → app shows the flow's error message, no crash.

## G. Publish
- [ ] File → Save → Publish.
- [ ] Share app with users; grant flow connections + premium license.
- [ ] Flow co‑owners / service‑account connection set.
- [ ] Tell users: barcode scanning requires the **mobile** app.

## H. (Optional) ALM
- [ ] Package app + flows + connection references into a solution (`solution/pac-commands.md`).
- [ ] Export managed + unmanaged; commit to this repo.
