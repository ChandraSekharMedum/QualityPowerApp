# Screens: `scrSuccess` + `scrSettings` (shared)

## `scrSuccess` — uniform confirmation

Every write action lands here. Reads `gSuccess = { title, number, backTo }`.

| Control | Type | Key properties |
|---|---|---|
| `conCard` | Container | centered card; Fill = `gTheme.Surface`; radius = `gTheme.Radius` |
| `icoDone` | Icon.CheckBadge | Color = `gTheme.Pass`; Size 72 |
| `lblDone` | Label | `Text = gSuccess.title`; Size = `gTheme.SizeTitle`; Bold |
| `lblNumber` | Label | `Text = gSuccess.number`; Size = `gTheme.SizeH2`; Color = `gTheme.Primary` |
| `btnAnother` | Button | Text = "Create another"; `OnSelect = Back()` (returns to the form) |
| `btnHome` | Button | Text = "Home"; `OnSelect = Navigate(scrHome, ScreenTransition.Cover)` |

---

## `scrSettings` — company picker + cache refresh

| Control | Type | Key properties |
|---|---|---|
| `ddCompany` | Dropdown | `Items = colCompanies`; `Default = gCompany.name`; `OnChange = Set(gCompany, ddCompany.Selected)` |
| `lblCompanyHint` | Label | `Text = "Writes go to legal entity: " & gCompany.code` |
| `btnRefreshAll` | Button | Text = "Refresh reference data"; OnSelect = re‑run the 3 lookup flows (see `00-home.md`) |
| `lblUser` | Label | `Text = gUser.name & "  (" & gUser.email & ")"` |
| `lblLoadErr` | Label | `Visible = !IsBlank(gLoadErr)`; Color = `gTheme.Warn`; `Text = gLoadErr` |
| `btnBackSettings` | Button | Text = "Done"; `OnSelect = Back()` |

> Changing the company clears source‑specific caches that are company‑scoped. If you cache
> orders/batches per company, also `Clear()` those collections in `ddCompany.OnChange`.
