# Quality Order Creation — Buildable, but Blocked by F&O Configuration

**QM-P2-010 · 2026-08-19 · `cus-con-sandbox`**

---

## 1. The short version

**The app side is solved. The environment is not.**

Everything needed to build a create screen is now known and available. But F&O rejects almost
every create in this environment because the **Owner inventory dimension is inactive** while
items' storage dimension groups include it. That is an F&O configuration matter and no app
change works around it.

**Recommendation: pause the build until an F&O consultant resolves the dimension setup.** The
screen itself is then straightforward — roughly 6-8 hours.

---

## 2. What creation actually requires

Established by probe, not documentation:

| Field | Value | Note |
|---|---|---|
| `mserp_qualityordernumber` | **omit it** | F&O assigns from number sequence `Inve_172`. Supplying one is rejected outright |
| `mserp_referencetype` | e.g. 200000002 Purchase | Any type works — this was never the blocker |
| `mserp_inventrefid` | the source document number | Not enough on its own |
| `mserp_referenceinventorylotid` | **the inventory lot** | Required. Without it: *"'000002' in field 'Reference number' is not found in the related table 'Purchase order lines'"* |
| `mserp_itemnumber`, `mserp_inventorysiteid`, `mserp_warehouseid`, `mserp_inventoryquantity` | from the source line | |
| `mserp_qualitytestgroupid` | a configured test group | |
| product dimensions | `configurationid`, `colorid`, `sizeid`, `styleid` | **Mandatory** for items that have them |

F&O generates the test lines itself once the header is created.

---

## 3. Where the picker data comes from

`PurchPurchaseOrderLineV2Entity` — **already generated** — carries everything:

```
mserp_purchaseordernumber   mserp_linenumber       mserp_itemnumber / itemname
mserp_inventorylotid   <-- the reference lot
mserp_receivingsiteid  mserp_receivingwarehouseid  mserp_orderedinventorystatusid
mserp_productconfigurationid / colorid / sizeid / styleid
mserp_purchaseorderlinestatus   mserp_orderedpurchasequantity
```

413 purchase order lines exist in `usmf`.

**Two entities were generated during this investigation and turned out not to be needed:**
`PurchPurchaseOrderLineEntity` (the non-V2 version — no lot column) and `InventTransCDSEntity`.
Both are additive and harmless, but neither is used.

---

## 4. Why it is blocked

### The demo app's field set, replicated exactly

The business confirmed the intended behaviour: **when the user picks a purchase order and line,
the dimensions are copied from the PO line**, and this works in `usdemo01`. That is correct, and
replicating it here changed the results — so the earlier claim that "nothing on the app side
changes the outcome" was too absolute.

What `QOPurchScreen` sends, copied from the line and its header:

```
'Item number'  Site  'Warehouse (WarehouseId)'  'Inventory status'  'Reference lot'
'Account selection'  <- the VENDOR, from the PO header. Easy to miss and it matters
'Reference number'   'Product name'   'Test group'   'Reference type (ReferenceType)'
'Dimension number': "AllBlank"
```

Note it does **not** send product dimensions.

Adding the vendor and `AllBlank` moved three of five items off the Owner error entirely:

| Item | demo field set, no product dims | demo field set + product dims |
|---|---|---|
| T0001 | `Size is a product dimension and must be specified` | `Owner is inactive` |
| T0004 | `Color is a product dimension and must be specified` | `Owner is inactive` |
| T0005 | `Color is a product dimension and must be specified` | `Owner is inactive` |
| T0002, T0003 | `Owner is inactive` | `Owner is inactive` |

### The catch-22

For an item with product dimensions, both paths fail **in this environment**:

- **Omit** the product dimensions -> F&O demands them.
- **Supply** them -> F&O resolves a full dimension set, which includes Owner, and Owner is
  inactive.

For an item without product dimensions (T0002, T0003) there is no path at all.

### So the difference is the environment, not the app

The demo works in `usdemo01` because **Owner is active there**, or those items' storage dimension
groups exclude it. The same field set in `cus-con-sandbox` cannot get past it.

The strongest evidence for the consultant is that **the error moves with the field set** — from
"Owner is inactive" to "Size must be specified" and back — which pins it to dimension resolution
rather than to a missing or malformed value.

The one create that ever succeeded reused an existing quality order's reference (item `A0001`,
PO `00000175`, lot `478937`) — and that lot is now marked by that order, so it cannot be reused:
*"Cannot change dimensions because existing mark would conflict."*

### Error taxonomy

| Error | Meaning | Fixable in the app? |
|---|---|---|
| `Owner is inactive and may consequently not be specified` | Item's storage dimension group includes Owner; Owner is disabled in F&O | **No** |
| `<dimension> is a product dimension and must consequently be specified` | Item has product dimensions | **Yes** — send them from the PO line |
| `Cannot change dimensions because existing mark would conflict` | That lot already has a quality order | Yes — filter used lots out of the picker |
| `No quantity available for item X` | Inventory-type needs real on-hand | Partly — only offer items with stock |

---

## 5. The record, corrected twice

This has now been misjudged in both directions and both times from a single item:

- **Phase 1:** "blocked by an Owner-dimension defect on the virtual entity path." Right about the
  symptom, wrong to call it a defect of the path.
- **Mobile phase:** "creation is not blocked, that diagnosis was wrong." Right that creation
  works, wrong to generalise — that test used `A0001`, one of the few items that succeeds.

**Both were true only of the item they tested.** Creation succeeds or fails per item, on whether
that item's inventory dimensions can be satisfied. In this environment most cannot.

---

## 6. What to ask the F&O consultant

1. **Can the Owner inventory dimension be activated in `cus-con-sandbox`**, or removed from the
   storage dimension groups of the items quality inspects? This is the actual blocker, and it is
   the one difference from `usdemo01`, where the same approach works. Evidence to hand over: the
   rejection changes from "Owner is inactive" to "Size is a product dimension and must be
   specified" purely by varying which fields we send, which places it in dimension resolution.
2. Which reference type do inspectors use in practice — purchase receipt, production, or
   inventory? It decides which picker gets built.
3. Should the picker hide lots that already carry a quality order, or show them greyed with a
   reason?

---

## 7. Effort once unblocked

| Work | Estimate |
|---|---|
| Purchase order line picker, sourced from the V2 entity | 3 h |
| Create screen: quantity, test group, product dimensions carried from the line | 3 h |
| Outbox integration so a create queues like everything else, with F&O's rejection surfaced | 2 h |
| **Total** | **~8 h** |

Nothing in that estimate is speculative — the data source is proven and the create is proven. It
is waiting on the environment, not on design.

---

## 8. Correction: creation is PROVEN WORKING through the app path

**QM-P3-001 · 2026-08-20 · `cus-con-sandbox`**

Sections 1, 4 and 6 above say the build should pause until an F&O consultant activates the
Owner dimension. **That recommendation is withdrawn.** A quality order was created end to end
through the real app path on 2026-08-20:

```
F&O quality order 000420
  item        M9201          test group  Enclosure
  ref lot     012312         ref id      00000041   (PO line 2)
  vendor      US-104         qty         2
  site / wh   5 / 51         status      200000000
```

Queued as an outbox row (operationtype 4), drained by `cog_QM_DrainQualityOrder`, confirmed
in **18 seconds**. F&O assigned `000420` from sequence `Inve_172` as predicted.

### What section 4 got right, and what it got wrong

Right: the field set. Sending the vendor as `mserp_publicaccountrelation` and
`mserp_inventdimensionid = "AllBlank"` is exactly what makes the create acceptable, and this
create used precisely that set with no product dimensions (M9201 has none).

Wrong: the generalisation. "F&O rejects almost every create in this environment" was drawn
from five items, T0001-T0005. M9201 is not one of them and it succeeds. Section 5 already
warned that this had been misjudged in both directions from a single item -- and section 1
then did it a third time, in the pessimistic direction.

**The per-item conclusion in section 5 is the durable one.** Creation succeeds or fails per
item on whether that item's inventory dimensions can be satisfied. Some items in this
environment can. The consultant question in section 6 is still worth asking, because items
whose storage dimension group includes Owner will still fail -- but it is no longer a
blocker on building or shipping the screen.

### Test groups are per-company and must be filtered

First attempt failed with:

```
The value 'CreamTest' in field 'Test group' is not found in the related table 'Test groups'.
```

`CreamTest` is real, but not in `usmf`. `InventQualityTestGroupEntity` filtered to `usmf`
returns exactly four: `Concentrat`, `Cone`, `Enclosure`, `Impedance`.

`QMCreateOrder` sources its picker from
`Distinct(Filter('Quality Orders (cache)', cog_company = varQoCompany), cog_testgroupid)`,
which returns those same four -- so the screen is correct. **The company filter is
load-bearing**; without it the picker offers other companies' groups and every create fails
this validation. A dedicated `cog_TestGroup` cache would additionally surface groups not yet
used by any cached order, and is the clean upgrade if that gap matters.

### Two flow-authoring traps, both silent

Both cost real time and neither produces a useful error.

1. **Never reference an action inside a `Scope` from outside it.** `Flag_needs_attention` is
   a sibling of `Process_the_submission`, so `outputs('Create_the_quality_order')` is illegal
   there. Dataverse still reports the flow `1/2 Activated`, but Power Automate refuses to
   register the trigger. The flow simply never fires and outbox rows sit at Queued with
   `attempts=0` -- indistinguishable from the lost-webhook symptom `Repair-FlowTriggers.ps1`
   documents, and a deactivate/reactivate cycle does NOT fix it. Use
   `result('<ScopeName>')` instead.

2. **`where()` and `filter()` do not exist** in the workflow definition language. Only
   `first`, `last`, `take`, `skip`, `union` and friends. An unknown function SAVES cleanly
   and the trigger arms, then the action fails at runtime and the outbox row strands at
   Sending (status 3) forever -- claimed but never resolved, so nothing retries it.

The working expression takes the create out of the scope result by position:

```
coalesce(last(result('Process_the_submission'))?['outputs']?['body'],
         result('Process_the_submission'))
```

`last()` is correct because the scope runs `Parse_payload` then the create.

### Put the F&O reason first, not the payload echo

`string(result('Process_the_submission'))` leads with the echoed payload and every HTTP
response header. Against `cog_lasterror`'s 3900-character cap the actual rejection was pushed
off the end entirely, so the queue screen showed the user a wall of cookies. Taking the
create's `outputs.body` puts F&O's sentence first, which is how the `CreamTest` error above
became readable at all.

### The optimistic hide must be reversible

`QMCreateOrder` sets `cog_hasqualityorder = 1` on queue so two inspectors cannot book the
same lot. When F&O refuses, that hiding is wrong. The flow's failure branch carries
`POLineId` in the payload and resets the flag, verified on the `CreamTest` failure above.
Without it a refused line stays invisible until the next sync -- which recomputes the flag
from real F&O orders, but could be hours away and looks like the line vanished.
