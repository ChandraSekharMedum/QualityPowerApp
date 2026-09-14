# Screens: `scrSplash` + `scrHome`

## `scrSplash`

Minimal launch screen while `App.OnStart` warms caches. (OnStart ends with `Navigate(scrHome)`,
so this is only visible if you route via a timer; optional.)

| Control | Type | Key properties |
|---|---|---|
| `conSplash` | Container | Fill = `gTheme.Primary`; fill screen |
| `lblBrand` | Label | Text = "Quality Management"; Color = `gTheme.OnPrimary`; Size = `gTheme.SizeDisplay`; FontWeight = Bold |
| `lblBooting` | Label | Text = "Connecting to Dynamics 365…"; Color = `gTheme.OnPrimary` |
| `spnSplash` | Icon.Reload (rotating) or a Spinner | Visible = true |

---

## `scrHome`

The manual's 4‑option landing screen, rendered as a responsive tile **gallery** from
`colHomeTiles` (defined in theme.fx) — data‑driven so adding a 5th function later is a one‑row
change, not a redesign.

### Layout
- `cmpHeader` — `Title = "Quality Management"`, `ShowBack = false`, `OnRefresh = Reload caches` (re-run the lookup flows).
- Greeting: `lblHi` — `Text = "Hi, " & gUser.name`.
- `galHome` — 2‑column flexible‑height gallery over `colHomeTiles`.

### Controls

| Control | Type | Key properties |
|---|---|---|
| `galHome` | Gallery (vertical, 2 cols via WrapCount = 2) | `Items = colHomeTiles`; TemplateSize ~ 180 |
| `conTile` (in template) | Container | Fill = `gTheme.Surface`; radius = `gTheme.Radius`; DropShadow; `OnSelect =` see below |
| `icoTile` | Icon | `Icon = ThisItem.icon`; Color = `ThisItem.color`; Size 40 |
| `lblTileTitle` | Label | `Text = ThisItem.title`; Size = `gTheme.SizeH2`; Bold |
| `lblTileSub` | Label | `Text = ThisItem.sub`; Color = `gTheme.InkSoft`; Size = `gTheme.SizeLabel` |
| `barTile` | Rectangle | left accent bar; Fill = `ThisItem.color` |

### `conTile.OnSelect` (data‑driven navigation)
```
Switch(ThisItem.target,
    "scrQOMenu", Navigate(scrQOMenu, ScreenTransition.Cover),
    "scrTRMenu", Navigate(scrTRMenu, ScreenTransition.Cover),
    "scrNCMenu", Navigate(scrNCMenu, ScreenTransition.Cover),
    "scrBDScan", Navigate(scrBDScan, ScreenTransition.Cover)
)
```
> `Navigate` targets must be static screen names, so we `Switch` on the tile's `target` string
> rather than navigating to a variable. Keeps the tiles data‑driven while staying valid Power Fx.

### `cmpHeader.OnRefresh` on Home (re‑warm caches)
```
Set(gBusy, true);
ClearCollect(colTestGroups,
    ForAll(Table(ParseJSON(Lookup_TestGroups.Run(gCompany.code).items)) As r,
        { id: Text(r.Value.QualityTestGroupId), name: Text(r.Value.Description) }));
ClearCollect(colProblemTypes,
    ForAll(Table(ParseJSON(Lookup_ProblemTypes.Run(gCompany.code).items)) As r,
        { id: Text(r.Value.ProblemTypeId), name: Text(r.Value.Description) }));
ClearCollect(colDispositionCodes,
    ForAll(Table(ParseJSON(Lookup_DispositionCodes.Run(gCompany.code).items)) As r,
        { code: Text(r.Value.DispositionCode), name: Text(r.Value.Description) }));
Set(gBusy, false);
Notify("Reference data refreshed", NotificationType.Success)
```
