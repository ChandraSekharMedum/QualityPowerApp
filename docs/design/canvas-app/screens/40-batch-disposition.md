# Screens: `scrBDScan` + `scrBDConfirm` (Manage Batch Disposition — manual §4.4)

Scan the item barcode and the batch barcode, view the current disposition code, choose a new
code, and confirm. Submits `BD_UpdateBatchDisposition`.

> ⚠️ The **barcode scanner control is not supported in a web browser** (stated in the manual).
> Use the Power Apps **mobile** app for this feature. Provide the manual‑entry fallback below so
> the screen still works on the web for testing.

---

## `scrBDScan` — scan item + batch

| Control | Type | Key properties |
|---|---|---|
| `cmpHeader` | component | Title = "Batch Disposition" |
| `bcsItem` | Barcode reader (Insert → Media → Barcode reader) | `OnScan = Set(gBD, Patch(gBD,{itemNumber: bcsItem.Value}))` |
| `lblItemVal` | Label | `Text = "Item: " & Coalesce(gBD.itemNumber, "—")` |
| `btnScanItem` | Button | Text = "Item Scan"; `OnSelect = Reset(bcsItem)` (re‑arm) |
| `txtItemManual` | Text input | fallback; `OnChange = Set(gBD, Patch(gBD,{itemNumber: txtItemManual.Text}))`; `Visible =` a "manual entry" toggle |
| `bcsBatch` | Barcode reader | `OnScan = Set(gBD, Patch(gBD,{batchNumber: bcsBatch.Value}))` |
| `lblBatchVal` | Label | `Text = "Batch: " & Coalesce(gBD.batchNumber, "—")` |
| `btnScanBatch` | Button | Text = "Batch Scan"; `OnSelect = Reset(bcsBatch)` |
| `btnBDNext` | Button | Text = "OK"; DisplayMode = if both scanned; OnSelect below |

Initialize `gBD` on screen `OnVisible`:
```
If(IsBlank(gBD), Set(gBD, { itemNumber: "", batchNumber: "", currentCode: "", newCode: "" }))
```

`btnBDNext.OnSelect` — look up the current disposition code, then go to confirm:
```
Set(gBusy, true);
Set(gLookup, BD_GetBatch.Run(gCompany.code, gBD.itemNumber, gBD.batchNumber));
Set(gBusy, false);
If( gLookup.ok,
    Set(gBD, Patch(gBD, { currentCode: gLookup.number }));   // flow returns current code in `number`
    Navigate(scrBDConfirm, ScreenTransition.Cover),
    Notify(gLookup.message, NotificationType.Error)
)
```

---

## `scrBDConfirm` — review + set new code

| Control | Type | Key properties |
|---|---|---|
| `lblItem2` | Label | `Text = "Item Number: " & gBD.itemNumber` (read‑only) |
| `lblBatch2` | Label | `Text = "Batch Number: " & gBD.batchNumber` |
| `lblCurrent` | Label | `Text = "Current disposition: " & gBD.currentCode` |
| `cmbNewCode` | ComboBox | `Items = colDispositionCodes`; DisplayFields `name`; SearchFields `code` |
| `btnRescan` | Button | Text = "Re-scan"; `OnSelect = Navigate(scrBDScan, ScreenTransition.UnCover)` |
| `btnConfirm` | Button | Text = "Confirm"; `DisplayMode = If(IsBlank(cmbNewCode.Selected), Disabled, Edit)`; OnSelect below |

### `btnConfirm.OnSelect`
```
Set(gBusy, true);
Set(gRes,
    BD_UpdateBatchDisposition.Run(
        gCompany.code,
        gBD.itemNumber,
        gBD.batchNumber,
        cmbNewCode.Selected.code
    )
);
Set(gBusy, false);
If( gRes.ok,
    Set(gSuccess, { title: "Disposition updated", number: gBD.batchNumber & " → " & cmbNewCode.Selected.code, backTo: "scrHome" });
    Set(gBD, Blank());
    Navigate(scrSuccess, ScreenTransition.Cover),
    Notify(gRes.message, NotificationType.Error)
)
```
