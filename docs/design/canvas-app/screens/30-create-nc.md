# Screens: `scrNCMenu` + `scrNC_Form` (Create NC — manual §4.3)

Raise a non‑conformance for one of **6 sources**. One menu + one adaptive form. Submits
`NC_CreateNonConformance`. Attachment supported (manual §4.3 "File attachment").

---

## `scrNCMenu` — pick source
Gallery over `colNCSources` (6 rows). Item `OnSelect`:
```
Set(gNCSource, ThisItem.key);
Set(gNC, {
    ncType: ThisItem.key, date: Today(), problemTypeId: "", accountNum: "",
    referenceNumber: "", referenceLot: "", itemNumber: "", description: "",
    dims: { InventSiteId:"", InventLocationId:"", InventBatchId:"" }
});
Navigate(scrNC_Form, ScreenTransition.Cover)
```

---

## `scrNC_Form` — adaptive NC form

`cmpHeader.Title = "Create NC · " & gNCSource`.

### Field visibility by source (mirrors `FnO-Data-Model.md` §D)

| Field (control) | Internal | Customer | Vendor | Service | Production | Co‑product |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| Date (`dpDate`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Problem type (`cmbProblem`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Account (`cmbAccountNC`) | — | ✅ cust | ✅ vend | ✅ cust | — | — |
| Reference number (`cmbRefNoNC`) | ✅ QO | ✅ SO | ✅ PO | ✅ SO | ✅ Prod | ✅ Batch |
| Reference lot (`cmbRefLotNC`) | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| Description (`txtDesc`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dims (read‑only `conDimsNC`) | auto | auto | auto | auto | auto | auto |

Visibility formulas:
- `cmbAccountNC.Visible = gNCSource in ["Customer","Vendor","Service"]`
- `cmbRefLotNC.Visible = gNCSource in ["Internal","Customer","Vendor","Service","CoProduct"]`
- account is a **customer** for Customer/Service, a **vendor** for Vendor.

### Controls

| Control | Type | Key properties |
|---|---|---|
| `dpDate` | Date picker | `DefaultDate = Today()` |
| `cmbProblem` | ComboBox | `Items = colProblemTypes` |
| `cmbAccountNC` | ComboBox | customers or vendors by source (same pattern as QO account) |
| `cmbRefNoNC` | ComboBox | orders by source (lookup flow, query‑as‑you‑type) |
| `cmbRefLotNC` | ComboBox | lots for the reference; `OnChange` auto‑fills item + dims into `gNC` |
| `conDimsNC` | Container | read‑only labels bound to `gNC.dims.*` + `gNC.itemNumber` |
| `txtDesc` | Text input (MultiLine) | `HintText = "Describe the non-conformance"` |
| `addPicNC` | Add picture | optional image |
| `imgPreviewNC` | Image | `Image = addPicNC.Media` |
| `btnOK` | Button | Text = "OK"; OnSelect below |

### `btnOK.DisplayMode` (required fields)
```
If( IsBlank(cmbProblem.Selected) || IsBlank(cmbRefNoNC.Selected)
    || (gNCSource in ["Customer","Vendor","Service"] && IsBlank(cmbAccountNC.Selected)),
    DisplayMode.Disabled, DisplayMode.Edit )
```

### `btnOK.OnSelect`
```
Set(gBusy, true);
Set(gRes,
    NC_CreateNonConformance.Run(
        gCompany.code,
        gNCSource,
        Text(dpDate.SelectedDate, "yyyy-mm-ddThh:mm:ssZ"),   // full ISO — bare dates break F&O deserializer
        cmbProblem.Selected.id,
        Coalesce(cmbAccountNC.Selected.id, ""),
        cmbRefNoNC.Selected.id,
        Coalesce(cmbRefLotNC.Selected.InventLotId, ""),
        Coalesce(cmbRefLotNC.Selected.ItemNumber, gNC.itemNumber),
        JSON(gNC.dims, JSONFormat.Compact),
        txtDesc.Text,
        If(IsBlank(addPicNC.Media), "", "nc.jpg"),
        If(IsBlank(addPicNC.Media), "", JSON(addPicNC.Media, JSONFormat.IncludeBinaryData))
    )
);
Set(gBusy, false);
If( gRes.ok,
    Set(gSuccess, { title: "Non-conformance created", number: gRes.number, backTo: "scrHome" });
    Navigate(scrSuccess, ScreenTransition.Cover),
    Notify(gRes.message, NotificationType.Error)
)
```
