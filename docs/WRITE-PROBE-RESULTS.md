# Write Probe Results — Batch Disposition and Non-Conformance

**QM-P2-002 · 2026-08-17 · `cus-con-sandbox`**

Probes run before building the two remaining screens, so neither gets built on an
assumption. One result **corrects a Phase 1 conclusion**.

---

## 1. Summary

| Feature | Verdict | Buildable? |
|---|---|---|
| **Non-conformance creation** | **WORKS** on the base entity | **Yes** — Phase 1 was wrong |
| **Batch disposition change** | **Blocked** — F&O refuses the field update | No, not over OData |

---

## 2. Non-conformance creation — Phase 1 was wrong

Phase 1 concluded NC creation was impossible. That conclusion came from testing
**`POWERAPPSINVENTNONCONFORMATIONENTITY`** only, which returns `0x80048d02 Not found` on
POST. The **base entity was never tried**.

`mserp_inventnonconformancetableentities` accepts creates:

| Type | Value | Result |
|---|---|---|
| Internal | `200000000` | **Created** — `PH2-NC-01` |
| Vendor | `200000002` | **Created** — `PH2-NC-02` |
| Customer | `200000001` | **Created** — `PH2-NC-11` (needed problem type `Concentration`) |
| Service request | `200000003` | Rejected — combination rule |
| Production | `200000004` | Rejected — combination rule |
| Co-product production | `200000005` | Rejected — combination rule |

All three creates persisted and were read back. F&O set
`mserp_inventnonconformanceapproval` to `200000000` (New) itself. Test records deleted
afterwards — deletion also works.

### The rejection is configuration, not a technical block

```
The specified combination of non conformance type and problem type is not valid
```

`usmf` has only three problem types — `Deviating Impedance`, `Enclosure`, `Concentration` —
and F&O restricts which are valid per NC type. `Enclosure` works for Internal and Vendor but
not Customer; `Concentration` works for Customer. None of the three satisfies Service
request, Production or Co-product production, so those types have no usable problem type
configured in this environment.

**That is an F&O setup question for the SMEs, not a defect.**

### The app cannot pre-filter the picker

There is **no mapping entity** — the catalogue holds nothing linking problem types to NC
types, and `INVENTPROBLEMTYPEDATAENTITY` exposes only `problemtypeid` and `description` with
no NC-type field. So the valid combinations are not readable over OData.

Three options for the screen:

1. **Offer all problem types and surface F&O's rejection** — the message is clear and
   actionable, and the outbox already displays F&O errors. Cheapest, and honest.
2. **Configure the valid combinations in Dataverse** as a small reference table the SMEs
   maintain. Better UX, needs upkeep and can drift from F&O.
3. **Expose the F&O setup table** as a data entity. Correct but needs X++.

Option 1 is recommended for the pilot, with option 3 noted if inspectors find the trial and
error irritating.

### Required fields

`mserp_inventnonconformanceid`, `mserp_inventtestproblemtypeid`, `mserp_itemid`,
`mserp_nonconformancedate`. Note the **id must be supplied** — F&O does not assign it from a
number sequence on this entity, so the app needs its own scheme. Set
`mserp_vendaccount` for Vendor and `mserp_custaccount` for Customer or Service request.

`mserp_custaccount` exists on the base entity but **not** on
`POWERAPPSINVENTNONCONFORMATIONENTITY`, which is another reason to use the base entity.

### Two optional fields, one of which is a trap

Probed while building the screen:

| Field | `IsValidForCreate` | POST behaviour | In the screen? |
|---|---|---|---|
| `mserp_rush` (No / Yes) | True | Persists | **Yes** — a Rush checkbox |
| `mserp_unitid` | **False** | **Accepted, then silently discarded** — reads back `''` | **No** |

`mserp_unitid` is the same silent-discard pattern seen on the `POWERAPP*` quality order line
entities: the POST returns 201 and the value simply is not there. F&O derives the unit from the
item. The Dataverse connector is stricter than the OData endpoint and rejects the field outright
with `WorkflowOperationParametersExtraParameter`, which is the more honest of the two failures.

A quantity input with no unit input is therefore correct, not an omission.

### `mserp_inventrefid` is a lookup wearing a text column's clothes

It looks like a free-text reference. It is not:

```
RefId = "QO-TEST"   -> 0x80048d0b  The value 'QO-TEST' in field 'Reference number' is not valid
RefId = "000120"    -> accepted, reads back '000120'      (a real quality order number)
RefId = ""          -> accepted
```

Two neighbouring fields are stricter still and reject a quality order number outright:
`mserp_inventtestinfostatref` ("not found in the related table 'Non conformance'") and
`mserp_inventtransidref` ("not found in the related table 'Inventory transactions
originator'").

So the screen prefills Reference from the selected quality order — a value proven valid — and
tells the inspector F&O validates anything else. **There is no field on this entity that will
accept arbitrary text**, which is worth knowing before anyone promises the SMEs a comments box.

### End-to-end results through the outbox

| Type | Account | Rush | Reference | Result |
|---|---|---|---|---|
| Vendor `200000002` | `US-105` | - | blank | **Confirmed, 15s** |
| Customer `200000001` | `US-002` | Yes | blank | **Confirmed, 15s** |
| Internal `200000000` | - | No | `000120` | **Confirmed, 15s** |

`mserp_rush` and `mserp_custaccount` both read back correctly, and F&O set approval to New
(`200000000`) on each. All probe records were deleted afterwards.

---

## 3. Batch disposition — blocked

The disposition code lives on `InventBatchEntity` as `mserp_pdsdispositioncode`. Dataverse
metadata reports `IsValidForUpdate = True`. F&O disagrees:

```
PATCH mserp_inventbatchentities(...)  { mserp_pdsdispositioncode: 'Avail' }
-> 400  update not allowed for field 'InventBatchEntity.PdsDispositionCode'
```

An explicit refusal, which is at least better than the silent discard seen on the
`POWERAPP*` quality order line entities.

### No alternative path exists

The catalogue was searched for `DISPOSITION`, `BATCHDISPO`, `BATCHATTRIB` and `PDSBATCH`:

| Entity | Why it does not help |
|---|---|
| `POWERAPPSPDSDISPOSITIONMASTERENTITY` | The code **master** — defines codes, does not assign them |
| `PdsItemBatchAttributeEntity`, `...ValueEntity`, `...ValueV2Entity` | Batch **attributes** (quality characteristics such as pH) — a different concept |
| `ReturnDispositionCodeEntity`, `WHSSourceSystemDispositionCodeEntity` | Unrelated dispositions (returns, warehouse inbound) |

Available codes in `usmf` are `Avail` and `Unavail`; `usp2` also has `Block` and `BlockPro`.
Reading them works fine — only the assignment is blocked.

### Why this is the same pattern as quality orders

Changing a batch disposition is a **business action**, not a field write: it recalculates
inventory availability and can block picking, reservation and shipping. F&O keeps that
behind its own logic rather than exposing it as an updatable column — the same reason
quality order creation is refused.

**Options are the familiar two:** an X++ custom service, or drop the feature and have
inspectors change disposition in F&O.

---

## 4. Effect on scope

| Screen | Was | Now |
|---|---|---|
| **Create NC** (6 types) | Deferred, thought impossible | **Buildable** — 3 of 6 types work today; the other 3 need F&O problem-type setup |
| **Batch disposition** | Unprobed | **Not buildable** over OData. Needs X++ or stays out |

This partially reverses the §7 recommendation in `PHASE1-REPORT.md`. Quality order creation
remains blocked, but **non-conformance creation does not** — so the "reduce scope" option is
now narrower than it looked.

---

## 5. Recommended next steps

1. **Ask the SMEs which NC types they actually raise.** If Internal, Vendor and Customer
   cover it, the screen is buildable now. If they need Production or Service request, an F&O
   consultant must configure problem types for those types first — a setup task, not
   development.
2. **Confirm the NC numbering scheme.** F&O does not assign the id, so the app must. Whether
   it should follow the F&O number sequence, or use a prefixed scheme like the existing
   `QUA02-*` agent records, is a governance decision tied to `R7`.
3. **Decide on batch disposition:** commission the X++ service, or leave it in F&O. Given
   the manual describes it as a scan-and-change floor task, dropping it is a real loss —
   worth putting to the business rather than quietly deferring.
