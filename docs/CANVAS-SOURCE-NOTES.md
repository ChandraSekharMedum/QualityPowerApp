# Canvas Source Notes

**QM-P2-003 · 2026-08-17 · `cus-con-sandbox`**

Hard-won rules for editing this app as source. Every one of these cost a failed publish or a
debugging session first.

---

## 1. Comments in `.pa.yaml` do not survive

`tools\Export-Solution.ps1` regenerates `canvas-src\Src\*.pa.yaml` from the live app. That
round trip:

- **strips every comment**
- versions the control templates (`Label` becomes `Label@2.5.1`)
- alphabetises properties within each control

So a comment written into a screen file lives only until the next export. **Design rationale
belongs in `docs\`, not in the YAML** — the YAML is a diffable rendering of the app, not the
authoritative source. (The `.msapp` is authoritative; see §2.)

Git history still holds the stripped comments if you need the original reasoning:
`git log -p -- solution/QualityManagementApp/canvas-src/Src/`.

---

## 2. Data sources live in the `.msapr`, and only Studio can add them

`canvas-src` contains `Src\*.pa.yaml` **plus** `cog_qualitymanagement_a469f_DocumentUri.msapr`.
That `.msapr` is a zip, and inside it `msapp\References\DataSources.json` holds every data
source — currently 8 Dataverse tables, each with a ~160 KB serialised metadata blob.

Consequences:

- **Adding a data source is a Studio-only step.** Hand-forging the metadata blob is not worth
  the risk; ask for the table to be added in Studio, then Save and Publish.
- **After anyone adds one, run `Export-Solution.ps1` before the next `Publish-CanvasApp.ps1`.**
  Publish packs `canvas-src` and overwrites the live app. Without a fresh export, the local
  `.msapr` has no record of the new data source, and the import **silently deletes it** along
  with every formula that referenced it. No error, no warning.

`Publish-CanvasApp.ps1` step 3 now guards this: it compares the exported app's Dataverse data
sources against the packed ones and refuses the import if any would be lost.

Current data sources:

| Name in formulas | Table |
|---|---|
| `Quality Orders (cache)` | `cog_qualityorder` |
| `Quality Test Lines (cache)` | `cog_qualitytestline` |
| `Test Outcomes (cache)` | `cog_testoutcome` |
| `Result Sheets (draft)` | `cog_resultsheet` |
| `Result Entries (draft)` | `cog_resultentry` |
| `Outbox` | `cog_outbox` |
| `Problem Types (cache)` | `cog_problemtype` |
| `Accounts (cache)` | `cog_account` |

---

## 3. Unprefixed controls resolve to MODERN, which breaks classic properties

Writing `Control: Button` gets the modern button, which has no `Fill`, and Studio refuses to
open the app with 39 errors like:

```
PA2108  Unknown property 'Fill' for control type 'Button'
```

Use the classic templates explicitly: **`Classic/Button`, `Classic/TextInput`,
`Classic/CheckBox`**. `Label`, `Rectangle` and `Gallery` are fine unprefixed.

Untested template names are a real risk — a wrong one costs a full publish cycle plus a Studio
round trip to discover. The NC screen deliberately uses **galleries rather than dropdowns or
combo boxes** for the company, problem-type and account pickers for exactly this reason: it
reuses only templates already proven in this app.

---

## 4. Put `OnSelect` on the Gallery, not on the row rectangle

Gallery children ascend by z-index, so a `Rectangle` declared first sits *underneath* every
label in the template. An `OnSelect` on that rectangle only fires where a tap misses the text —
which reads as intermittent selection, and is what made the order list feel broken.

Row selection goes on the **gallery's** `OnSelect`.

---

## 5. ASCII only

PowerShell's cp1252 round trip mangles non-ASCII: `·` became `Â·`, em dashes became `€` or `"`.
`Publish-CanvasApp.ps1` step 0 hard-fails on any non-ASCII character in the screen source. Use
`-` and `--`, never typographic dashes.

---

## 6. `pac canvas pack` checks syntax, not semantics

Pack will happily produce a `.msapp` from YAML with unresolvable names or type errors, and
`pac canvas validate` is retired. **Formula errors surface only when the app is opened in
Studio.** That is why the publish script ends by telling you to open it.

---

## 7. Screen design decisions worth remembering

### QMCreateNC

| Decision | Why |
|---|---|
| Only Internal, Customer, Vendor offered | The other three NC types have no valid problem type configured in this environment. F&O setup gap, not a defect. |
| No Description input | The base entity has no description column, and no other field accepts arbitrary text. See `WRITE-PROBE-RESULTS.md`. |
| No unit input | `mserp_unitid` is `IsValidForCreate = False` and F&O discards a posted value silently. |
| Problem types not filtered by NC type | F&O restricts the valid pairs and publishes no mapping entity. The screen offers all of them and surfaces F&O's rejection on the queue row. |
| Reference prefilled from the quality order | `mserp_inventrefid` is a lookup — a real order number is accepted, arbitrary text is rejected. |
| NC number generated client-side, `NC-yymmdd-<6 hex>` | F&O assigns no number sequence on this entity, and D-02 requires the screen to work offline, so the id cannot be fetched at submit time. **Open governance question under R7.** |
| Company picker sourced from cached quality orders | Those are the legal entities the inspector actually has quality work in, and both problem types and accounts are company-scoped in F&O. |
| Selection tracked as scalars (`varNcAccountNumber`) not records | A `Set(var, Blank())` record has no type, so `var.field` fails to compile. Scalars avoid the whole problem. |
| `Text(Year(Today()), "0000")`, never bare `Text(Year(...))` | Unformatted `Text()` on a number can emit a thousands separator — `"2,026"` — which would corrupt both the id and the ISO date. |

### QMResultSheet

Verdict is computed client-side from cached tolerance bounds so it works offline, but it is a
UX affordance only: **F&O recalculates the stored verdict** from the submitted value.

---

## 8. Every solution import breaks the flow webhooks

The import leaves flows reading `statecode 1 / statuscode 2` while their Dataverse webhook
registration is gone. They silently stop firing and outbox rows sit at Queued with no error.

`Publish-CanvasApp.ps1` step 6 runs `Repair-FlowTriggers.ps1` for this reason, and it is
mandatory after **any** import. A flow reading 1/2 is not evidence its trigger fires — only a
real round trip is.
