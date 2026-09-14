# Screens: `scrQOMenu` + `scrQO_Form` (Quality Order — manual §4.1)

Create a quality order for one of **7 sources**. One menu + one adaptive form (fields show/hide
by source) instead of 7 near‑identical screens. Submits the `QO_CreateQualityOrder` flow.

---

## `scrQOMenu` — pick the source

- `cmpHeader` — `Title = "Quality Order"`, `ShowBack = true`, `OnBack = Back()`.
- `galQOSources` — gallery over `colQOSources` (the 7 rows from App.OnStart).

| Control | Type | Key properties |
|---|---|---|
| `galQOSources` | Gallery (vertical) | `Items = colQOSources` |
| `icoSrc` | Icon | `Icon = ThisItem.icon`; Color = `gTheme.Primary` |
| `lblSrc` | Label | `Text = ThisItem.label`; Size = `gTheme.SizeH2` |
| `icoChevron` | Icon.ChevronRight | Color = `gTheme.InkSoft` |

`galQOSources` item `OnSelect`:
```
Set(gQOSource, ThisItem.key);
// fresh empty record for the form
Set(gQO, {
    referenceType: ThisItem.key, accountNum: "", referenceNumber: "",
    operationNumber: "", itemNumber: "", referenceLot: "",
    testGroupId: "", quantity: 0,
    dims: { InventSiteId:"", InventLocationId:"", wMSLocationId:"", InventBatchId:"",
            configId:"", InventColorId:"", InventSizeId:"", InventStyleId:"",
            inventStatusId:"", licensePlateId:"" }
});
Navigate(scrQO_Form, ScreenTransition.Cover)
```

---

## `scrQO_Form` — adaptive create form

Header shows the chosen source: `cmpHeader.Title = "Quality Order · " & gQOSource`.

### Field visibility by source (mirrors `FnO-Data-Model.md` §B)

| Field (control) | Sales | Purchase | Inventory | Production | Route | Co‑Prod | Quarantine |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Account (`cmbAccount`) | ✅ cust | ✅ vend | — | — | — | — | — |
| Reference number (`cmbRefNo`) | ✅ SO | ✅ PO | — | ✅ Prod | ✅ Prod | ✅ Prod+co | ✅ Quar |
| Operation (`cmbOperation`) | — | — | — | — | ✅ | — | — |
| Reference lot (`cmbRefLot`) | ✅ | ✅ | — | — | — | — | — |
| Item number (`cmbItem`) | auto | auto | ✅ | auto | auto | auto | auto |
| Site/Whse/Loc/LP/Status/Config/Color/Size/Style | — | — | ✅ all | — | — | — | — |
| Inventory dims (read‑only display `conDims`) | auto | auto | — | auto | auto | auto | auto |
| Test group (`cmbTestGroup`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Quantity (`txtQty`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

Implement each with `Visible =` a helper, e.g.:
- `cmbAccount.Visible = gQOSource in ["Sales","Purchase"]`
- `cmbOperation.Visible = gQOSource = "RouteOperation"`
- `conInventoryDims.Visible = gQOSource = "Inventory"`   (the full manual manual‑entry block)
- `conDimsAuto.Visible = !(gQOSource in ["Inventory"])`   (read‑only auto‑populated block)

### Controls (key ones)

| Control | Type | Key properties |
|---|---|---|
| `cmbAccount` | ComboBox | Items = customers or vendors (see below); `OnChange` → clear dependent fields |
| `cmbRefNo` | ComboBox | Items = orders for the account/type (lookup flow, query‑as‑you‑type) |
| `cmbOperation` | ComboBox | Items = route ops for the production order |
| `cmbRefLot` | ComboBox | Items = lots/lines for the reference; `OnChange` auto‑fills item + dims |
| `cmbItem` | ComboBox | Items = `ReleasedProductsV2` (Inventory source: user picks; else read‑only) |
| `conInventoryDims` | Container | Site/Warehouse/Location/LicensePlate/Status/Config/Color/Size/Style combos |
| `conDimsAuto` | Container | read‑only labels bound to `gQO.dims.*` |
| `cmbTestGroup` | ComboBox | `Items = colTestGroups`; DisplayFields `name` |
| `txtQty` | Text input (Number) | `Default = gQO.quantity` |
| `lblQOError` | Label | Color = `gTheme.Fail`; `Visible = !IsBlank(gQOErr)`; `Text = gQOErr` |
| `btnSubmit` | Button | Text = "Submit"; see OnSelect |
| `cmpBusy` | component | Visible = gBusy |

### Account lookup (Sales vs Purchase)
```
// cmbAccount.Items
If(gQOSource = "Sales",
   ForAll(Table(ParseJSON(Lookup_Customers.Run(gCompany.code, cmbAccount.SearchText).items)) As r,
       { id: Text(r.Value.CustomerAccount), name: Text(r.Value.OrganizationName) }),
   ForAll(Table(ParseJSON(Lookup_Vendors.Run(gCompany.code, cmbAccount.SearchText).items)) As r,
       { id: Text(r.Value.VendorAccountNumber), name: Text(r.Value.VendorOrganizationName) })
)
```

### Reference‑lot auto‑fill (Sales/Purchase)
```
// cmbRefLot.OnChange — pull item + inventory dims for the picked lot/line
With({ d: cmbRefLot.Selected },
    Set(gQO, Patch(gQO, {
        itemNumber: d.ItemNumber,
        referenceLot: d.InventLotId,
        dims: { InventSiteId: d.InventSiteId, InventLocationId: d.InventLocationId,
                wMSLocationId: d.wMSLocationId, InventBatchId: d.InventBatchId,
                configId: d.configId, InventColorId: d.InventColorId,
                InventSizeId: d.InventSizeId, InventStyleId: d.InventStyleId,
                inventStatusId: gQO.dims.inventStatusId, licensePlateId: gQO.dims.licensePlateId }
    }))
)
```

### Validation helper (screen `OnVisible` sets nothing; compute at submit)
```
// btnSubmit.DisplayMode
If( IsBlank(cmbTestGroup.Selected) || Value(txtQty.Text) <= 0
    || (gQOSource in ["Sales","Purchase"] && IsBlank(cmbAccount.Selected))
    || (gQOSource in ["Sales","Purchase","Production","RouteOperation","CoProduct","Quarantine"] && IsBlank(cmbRefNo.Selected))
    || (gQOSource = "RouteOperation" && IsBlank(cmbOperation.Selected))
    || (gQOSource = "Inventory" && IsBlank(cmbItem.Selected)),
    DisplayMode.Disabled, DisplayMode.Edit )
```

### `btnSubmit.OnSelect`
```
Set(gQOErr, "");
Set(gBusy, true);
Set(gRes,
    QO_CreateQualityOrder.Run(
        gCompany.code,
        gQOSource,
        Coalesce(cmbAccount.Selected.id, ""),
        Coalesce(cmbRefNo.Selected.id, ""),
        Coalesce(cmbOperation.Selected.OperationNumber, ""),
        Coalesce(cmbItem.Selected.ItemNumber, gQO.itemNumber),
        Coalesce(cmbRefLot.Selected.InventLotId, gQO.referenceLot),
        cmbTestGroup.Selected.id,
        Value(txtQty.Text),
        // inventory dims as a JSON string (Inventory source uses the manual combos)
        JSON(
            If(gQOSource = "Inventory",
               { InventSiteId: cmbSite.Selected.SiteId, InventLocationId: cmbWhse.Selected.WarehouseId,
                 wMSLocationId: cmbLocation.Selected.wMSLocationId, licensePlateId: cmbLP.Selected.LicensePlateNumber,
                 inventStatusId: cmbStatus.Selected.InventoryStatusId, configId: cmbConfig.Selected.configId,
                 InventColorId: cmbColor.Selected.InventColorId, InventSizeId: cmbSize.Selected.InventSizeId,
                 InventStyleId: cmbStyle.Selected.InventStyleId },
               gQO.dims),
            JSONFormat.Compact
        )
    )
);
Set(gBusy, false);
If( gRes.ok,
    Notify(gRes.message, NotificationType.Success);
    Set(gSuccess, { title: "Quality order created", number: gRes.number, backTo: "scrHome" });
    Navigate(scrSuccess, ScreenTransition.Cover),
    Set(gQOErr, gRes.message); Notify(gRes.message, NotificationType.Error)
)
```

> Flow arg order is a contract with `QO_CreateQualityOrder` — keep it identical to
> `flows/QO_CreateQualityOrder.md`.
