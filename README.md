# Quality Management App — D365 F&O

Power Apps canvas app for D365 Finance & Operations Quality Management, rebuilt from
*Quality Management App — User Manual V3*.

| | |
|---|---|
| **Solution** | `QualityManagementApp` |
| **Publisher** | ColumbusGlobal (`cog`) |
| **Dev environment** | `cus-con-sandbox` |
| **Source of truth** | `solution/QualityManagementApp/src` — **not** the exported `.zip` |

---

## A note on Git integration

Power Platform's **native** Git integration (the "Connect to Git" experience in
make.powerapps.com) supports **Azure DevOps repositories only** — see
[the overview](https://learn.microsoft.com/en-us/power-platform/alm/git-integration/overview),
which opens: *"...using an Azure DevOps Git repository."*

This repository is on GitHub, so it uses the **CLI-based ALM pattern** instead: export the
solution, unpack it to source, commit. That is fully supported tooling and is the pattern
Columbus already uses on other engagements. The practical difference is that syncing is a
deliberate command rather than a button in the maker portal.

---

## Layout

```
solution/QualityManagementApp/
  src/                  unpacked solution (SolutionPackager, packagetype Both)
    Entities/           6 cog_ tables + 28 F&O virtual entities
    CanvasApps/         the app as a binary .msapp
    Workflows/          cog_QM_DrainOutbox
    Other/              solution manifest, customizations, connection references
  canvas-src/           canvas app unpacked to .pa.yaml -- REVIEWABLE DIFFS
    Src/*.pa.yaml       one file per screen

tools/                  export, unpack, pack, import, and the Dataverse helper
docs/                   architecture and phase reports
```

**Why `canvas-src/` exists.** `pac solution unpack` stores a canvas app as a binary
`.msapp`, which produces no useful diff. The app is additionally unpacked to `.pa.yaml` so
screen changes are reviewable in pull requests. `canvas-src/` is **generated** — the
`.msapp` inside `src/CanvasApps/` remains authoritative for deployment.

---

## Working on the app

### Pull the environment into source

```powershell
.\tools\Export-Solution.ps1
```

Exports the solution, unpacks it to `src/`, and refreshes `canvas-src/`.

### Change a screen

Edit the `.pa.yaml` under `canvas-src/Src/`, then:

```powershell
.\tools\Publish-CanvasApp.ps1
```

Packs the YAML back into the `.msapp`, swaps it into an exported solution, and imports.

### Constraints that bite

| # | Constraint |
|---|---|
| 1 | **Classic vs modern controls.** `Button`, `TextInput` and `Checkbox` resolve to *modern* controls, which have no `Fill`/`Color`/`Size`/`HintText`. Use `Classic/Button`, `Classic/TextInput`, `Classic/CheckBox`. `Label` and `Rectangle` are fine unprefixed. |
| 2 | **ASCII only in `.pa.yaml`.** Non-ASCII separators get mangled through PowerShell's cp1252 round-trip. This extends the existing ASCII-only rule for `.ps1` files. |
| 3 | **`pac canvas validate` is retired.** `pack` checks YAML structure but not Power Fx semantics. Errors surface only when the app is opened in Studio. Open it after any screen change. |
| 4 | **Microsoft documents `.pa.yaml` as read-only.** Editing works in practice — this repo is built that way — but it is outside the supported path. See `docs/PHASE2-REPORT.md`. |
| 5 | **Solution zips need forward-slash paths.** `[ZipFile]::CreateFromDirectory` on .NET Framework writes backslashes and the importer fails with *"Xaml file is missing from import zip file"*. |

---

## Deploying to another environment

See `docs/IMPORT-INSTRUCTIONS.md`. In short, the 28 F&O virtual entities must be
**regenerated in the target** before import — they bind to that environment's own F&O
instance and cannot simply be imported.

---

## Status

Phase 2. The persistence seam works end to end: an inspector's submission lands in the
Dataverse outbox and reaches F&O in about 12 seconds, where F&O recalculates the verdict.

**Deferred to a later release:** quality order and non-conformance creation. Phase 1 proved
neither can be created over OData — the virtual entity path is blocked by an inactive `Owner`
dimension, and the quality entities are not exposed to the F&O connector. See
`docs/PHASE1-REPORT.md`.
