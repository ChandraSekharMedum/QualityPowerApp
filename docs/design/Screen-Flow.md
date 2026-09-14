# Screen Flow & Inventory

## Navigation map

```
scrSplash (App.OnStart cache warm)
   │
   ▼
scrHome ──────────────────────────────────────────────┐  (4 tiles + bottom nav)
   ├─► scrQOMenu ──► scrQO_Form  ──► scrSuccess         │
   │      (pick 1 of 7 sources: the form adapts)        │
   ├─► scrTRMenu ──► scrTR_Select ─► scrTR_Grid ──► scrSuccess
   │      (pick source → pick order → enter results)    │
   ├─► scrNCMenu ──► scrNC_Form  ──► scrSuccess         │
   │      (pick 1 of 6 sources: the form adapts)        │
   └─► scrBDScan ──► scrBDConfirm ─► scrSuccess         │
          (scan item + batch → change code)             │
                                                        │
scrSettings (company picker, refresh caches) ◄──────────┘
```

Global chrome (from the manual's "Commonly used menus"): **Home**, **Back**, **Forward**,
**Refresh** live in a reusable header component (`cmpHeader`) on every screen except splash.

## Screen inventory

| Screen | File (spec + Power Fx) | Purpose |
|--------|------------------------|---------|
| `scrSplash` | `screens/00-home.md` | Warm caches, route to Home. |
| `scrHome` | `screens/00-home.md` | 4 function tiles + bottom nav. |
| `scrQOMenu` | `screens/10-quality-order.md` | Choose one of 7 quality‑order sources. |
| `scrQO_Form` | `screens/10-quality-order.md` | Adaptive create form; submits `QO_CreateQualityOrder`. |
| `scrTRMenu` | `screens/20-test-results.md` | Choose one of 7 test‑result sources. |
| `scrTR_Select` | `screens/20-test-results.md` | Pick item/test group/quality order. |
| `scrTR_Grid` | `screens/20-test-results.md` | Enter outcomes per test line + attachment; submits `TR_SubmitTestResult`. |
| `scrNCMenu` | `screens/30-create-nc.md` | Choose one of 6 NC sources. |
| `scrNC_Form` | `screens/30-create-nc.md` | Adaptive NC form + attachment; submits `NC_CreateNonConformance`. |
| `scrBDScan` | `screens/40-batch-disposition.md` | Scan item + batch barcodes. |
| `scrBDConfirm` | `screens/40-batch-disposition.md` | Show current code, pick new code; submits `BD_UpdateBatchDisposition`. |
| `scrSuccess` | `screens/90-shared.md` | Uniform confirmation (number + open/another). |
| `scrSettings` | `screens/90-shared.md` | Company picker + cache refresh. |

## Adaptive‑form pattern (why 7 sources ≠ 7 screens)

Quality Order and Create NC each have many sources that share ~80% of their fields. Instead of
14 near‑duplicate screens, each uses **one** form screen whose fields show/hide based on
`gQOSource` / `gNCSource`. This is the modern redesign choice — fewer screens, one place to fix a
bug, consistent layout. Field visibility rules are in the respective screen spec files and mirror
the per‑source tables in `FnO-Data-Model.md`.
