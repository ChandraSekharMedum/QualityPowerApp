# Screens: `scrTRMenu` + `scrTR_Select` + `scrTR_Grid` (Enter Test Results — manual §4.2)

View a quality order's test lines and record outcomes (pass/fail + result value) with an optional
image attachment. 7 sources reuse the same flow. Submits `TR_SubmitTestResult`.

---

## `scrTRMenu` — pick source
Identical pattern to `scrQOMenu` but sets `gTRSource` and navigates to `scrTR_Select`.
```
// galTRSources item OnSelect
Set(gTRSource, ThisItem.key);
Navigate(scrTR_Select, ScreenTransition.Cover)
```
(Uses `colQOSources` — the same 7 sources.)

---

## `scrTR_Select` — choose item / test group / quality order

| Control | Type | Key properties |
|---|---|---|
| `cmbItemTR` | ComboBox | `Items = ForAll(Table(ParseJSON(Lookup_Items.Run(gCompany.code, cmbItemTR.SearchText).items)) As r, {ItemNumber:Text(r.Value.ItemNumber), ProductName:Text(r.Value.ProductName)})` |
| `lblProduct` | Label | `Text = cmbItemTR.Selected.ProductName` (auto after item pick) |
| `cmbTestGroupTR` | ComboBox | `Items = colTestGroups` |
| `cmbQO` | ComboBox | `Items =` open quality orders for the item/source (lookup flow) |
| `btnLoad` | Button | Text = "Load test lines"; OnSelect below |

`btnLoad.OnSelect` — pull the order's test lines into an editable collection:
```
Set(gTR, { qualityOrderNumber: cmbQO.Selected.QualityOrderNumber,
           quantity: cmbQO.Selected.Quantity, refType: gTRSource,
           refNo: cmbQO.Selected.ReferenceNumber, itemNumber: cmbItemTR.Selected.ItemNumber });
Set(gBusy, true);
ClearCollect(colTRLines,
    ForAll(Table(ParseJSON(Lookup_QOTestLines.Run(gCompany.code, gTR.qualityOrderNumber).items)) As r,
        { seq: Value(r.Value.QualityOrderSequenceNumber),   // part of the result key
          testId: Text(r.Value.QualityTestId), test: Text(r.Value.QualityTestId),
          outcome: "Fail",                         // manual: default is Fail (InventTestOutcomeStatus)
          resultQuantity: 0 }
    )
);
Set(gBusy, false);
Navigate(scrTR_Grid, ScreenTransition.Cover)
```

---

## `scrTR_Grid` — enter outcomes per test line + attachment

Top summary card (read‑only, from `gTR`): Quality order, Quantity, Ref Type, Ref No.

### Editable grid
| Control | Type | Key properties |
|---|---|---|
| `galTRLines` | Gallery over `colTRLines` | edit in place |
| `lblTest` | Label | `Text = ThisItem.test` |
| `ddOutcome` | Dropdown | `Items = ["Pass","Fail"]`; `Default = ThisItem.outcome`; `OnChange = Patch(colTRLines, ThisItem, {outcome: ddOutcome.Selected.Value})` |
| `txtResult` | Text input (Number) | `Default = ThisItem.resultQuantity`; `OnChange = Patch(colTRLines, ThisItem, {resultQuantity: Value(txtResult.Text)})` |
| `icoPassFail` | Icon | Color = `If(ThisItem.outcome="Pass", gTheme.Pass, gTheme.Fail)` |

### Attachment (manual: "Tap or click to add a picture")
| Control | Type | Key properties |
|---|---|---|
| `conAttach` | Container | header "Attachment" |
| `addPic` | Add picture control (or Camera) | captures an image |
| `imgPreview` | Image | `Image = addPic.Media`; `Visible = !IsBlank(addPic.Media)` |

### `btnSaveSubmit.OnSelect`
```
Set(gBusy, true);
Set(gRes,
    TR_SubmitTestResult.Run(
        gCompany.code,
        gTR.qualityOrderNumber,
        // lines as JSON array
        JSON(colTRLines, JSONFormat.Compact),
        // attachment (optional): name + base64 (JSON() of an image yields a data URL; strip prefix in the flow)
        If(IsBlank(addPic.Media), "", "sample.jpg"),
        If(IsBlank(addPic.Media), "", Substitute(JSON(addPic.Media, JSONFormat.IncludeBinaryData), """", ""))
    )
);
Set(gBusy, false);
If( gRes.ok,
    Set(gSuccess, { title: "Test results submitted", number: gTR.qualityOrderNumber, backTo: "scrHome" });
    Navigate(scrSuccess, ScreenTransition.Cover),
    Notify(gRes.message, NotificationType.Error)
)
```

> Note on images: `JSON(media, JSONFormat.IncludeBinaryData)` returns a `data:...;base64,XXXX`
> string. Send it as‑is and let the flow split on `base64,` — simpler and less error‑prone than
> trying to strip the prefix in Power Fx. (The `Substitute` above just removes wrapping quotes.)
