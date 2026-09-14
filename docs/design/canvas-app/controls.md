# Control naming conventions & inventory

## Naming prefixes

| Prefix | Control |
|--------|---------|
| `scr` | Screen |
| `cmp` | Canvas component |
| `lbl` | Label |
| `txt` | Text input |
| `cmb` | Combo box (lookup) |
| `dd`  | Dropdown |
| `dp`  | Date picker |
| `btn` | Button |
| `ico` | Icon |
| `gal` | Gallery |
| `con` | Container / group |
| `img` | Image |
| `bcs` | Barcode scanner |
| `frm` | Form (rarely — this app uses custom cards, not Edit forms, for adaptive layouts) |

## Globals & collections (single source of truth)

| Name | Set in | Meaning |
|------|--------|---------|
| `gTheme` | theme.fx | design tokens |
| `gCompany` | App.OnStart | active legal entity `{code,name}` |
| `gUser` | App.OnStart | current user |
| `gBusy` | per action | true while a flow runs (drives `cmpBusy`) |
| `gRes` | per action | last flow result `{ok,number,message}` |
| `gQOSource` / `gNCSource` / `gTRSource` | menu screens | chosen source key |
| `gQO` / `gNC` / `gBD` | form screens | the record being built |
| `colTestGroups`, `colProblemTypes`, `colDispositionCodes` | App.OnStart | cached lookups |
| `colQOSources`, `colNCSources`, `colHomeTiles` | App.OnStart / theme | menu data |
| `colTRLines` | scrTR_Grid | editable test-result lines |

## Result-envelope handling (used everywhere)

Every submit button follows this exact shape so behavior is uniform (see any screen spec):
```
UpdateContext({ });                         // (screen-local resets if needed)
Set(gBusy, true);
Set(gRes, SomeFlow.Run( ...typed args... ));
Set(gBusy, false);
If( gRes.ok,
    Notify(gRes.message, NotificationType.Success); Navigate(scrSuccess, ScreenTransition.Cover),
    Notify(gRes.message, NotificationType.Error)
)
```
