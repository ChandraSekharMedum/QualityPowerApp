# Reusable components

Build these as **canvas components** (Tree view → Components → New component) so every screen
shares one definition. Referenced by all screen specs.

---

## `cmpHeader` — top app bar (replaces the manual's Home/Back/Forward/Refresh menu)

Height 64. Fill `gTheme.Primary`. Custom output properties let each screen configure it.

| Custom property | Type | Purpose |
|---|---|---|
| `Title` (input, text) | text | Screen title shown centered. |
| `ShowBack` (input, boolean) | boolean | Show the back chevron. |
| `OnBack` (input, behavior) | behavior | What the back button does (usually `Back()`). |
| `OnRefresh` (input, behavior) | behavior | Refresh action for this screen (re-pull data). |

Layout inside the component:
- `icoHome` (Icon.Home, left) — `OnSelect = Navigate(scrHome, ScreenTransition.Fade)`.
- `icoBack` (Icon.Back) — `Visible = cmpHeader.ShowBack`; `OnSelect = cmpHeader.OnBack`.
- `lblTitle` (Label) — `Text = cmpHeader.Title`; color `gTheme.OnPrimary`; size `gTheme.SizeTitle`.
- `icoRefresh` (Icon.Reload, right) — `OnSelect = cmpHeader.OnRefresh`.
- `lblCompany` (Label, small, under title) — `Text = gCompany.code`; tap → `Navigate(scrSettings)`.

> The manual's separate Home / Back / Forward / Refresh buttons are consolidated here. "Forward"
> is dropped — modern navigation is Back + explicit action buttons, not a browser-style forward.

---

## `cmpNav` — bottom navigation (Home screen only, optional elsewhere)

4 items mirroring the home tiles (QO / TR / NC / BD). Each `OnSelect = Navigate(<target>)`.
Active item tinted `gTheme.Accent`. Keep height 56.

---

## `cmpLookup` — type-ahead combo box wired to a lookup flow

Wraps a `ComboBox` so screens don't each re-implement search-as-you-type against F&O.

| Custom property | Type | Purpose |
|---|---|---|
| `FlowName` (input, text) | text | Which lookup flow to call (documentation only — see note). |
| `Items` (input, table) | table | The cached/queried table to show. |
| `Placeholder` (input, text) | text | Hint text. |
| `Selected` (output, record) | record | The chosen row. |

> Power Fx can't call a flow chosen dynamically by name, so in practice make `cmpLookup` a
> **presentation** wrapper (styling + search box) and pass it an already-fetched `Items` table.
> The screen owns the `Flow.Run(...)` call and feeds results in. This keeps one consistent combo
> style everywhere while respecting Power Fx's static-binding rules.

Style: Fill `gTheme.Surface`, border `gTheme.Border`, radius `gTheme.RadiusSm`, selected chip
`gTheme.PrimaryTint`.

---

## `cmpField` — labeled field wrapper

A container with a caption label (`gTheme.SizeLabel`, `gTheme.InkSoft`) above a slot for the
input control, with consistent 8px spacing and an optional red required-asterisk. Use for every
form field so QO/NC/TR forms line up perfectly.

---

## `cmpBusy` — full-screen busy overlay

Semi-transparent scrim + spinner. `Visible = gBusy`. Prevents double-submits while a flow runs.
Place last (top of z-order) on every screen that calls a flow.
