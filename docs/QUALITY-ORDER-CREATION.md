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

Every purchase line tried was rejected:

```
Inventory dimension Owner is inactive and may consequently not be specified.
```

Tested across sites 1, 2 and 3 and a dozen items, with and without product dimensions, with and
without `Dimension number = "AllBlank"`, and with Owner explicitly blanked. **Nothing on the app
side changes the outcome.** The error is raised when F&O resolves the item's dimensions, not from
anything we send.

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

1. **Can the Owner inventory dimension be activated**, or removed from the storage dimension
   groups of the items quality inspects? This is the actual blocker.
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
