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
