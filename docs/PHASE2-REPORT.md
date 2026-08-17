# Phase 2 — Progress Report

**Quality Management Canvas App · QM-P2-001 · Rev 1.0 · 2026-08-17 · `cus-con-sandbox`**

Scope: the persistence seam and the test-result journey. Quality order creation is deferred
to a later upgrade per the client's decision.

---

## 1. Headline

**The seam is built and proven end to end.** A result submitted into the Dataverse outbox
reaches F&O through a Power Automate flow in **about 12 seconds**, and F&O recalculates the
verdict on arrival.

It also overturns a Phase 1 assumption that would have shaped the rest of the build.

> **Dataverse-triggered flows self-arm.** Phase 1 concluded that flows could not be tested
> from here because `api.flow.microsoft.com` rejects every available token, so the
> documented `POST /start` could not be called. That requirement applies to **Skills**
> triggers. A flow with a **Dataverse webhook trigger fired 12 seconds after activation
> with no `/start` at all**. Flow work is not blocked.

---

## 2. What was built

### 2.1 Dataverse schema — 6 tables, 55 columns, 4 relationships

All in `QualityManagementApp`, publisher `cog`. Created, published and verified; zero
failures.

| Table | Role | Columns |
|---|---|---:|
| `cog_qualityorder` | Cached QO headers. Written by sync, read by the app | 14 |
| `cog_qualitytestline` | Cached test lines **including tolerance bounds** | 17 |
| `cog_testoutcome` | Cached qualitative outcome options | 8 |
| `cog_resultsheet` | Inspector's working sheet. Offline-capable | 11 |
| `cog_resultentry` | One entered result, with a file column for the photo | 12 |
| `cog_outbox` | Durable queue — the single record of intent | 14 |

Relationships: order → test lines, order → result sheet, sheet → entries, sheet → outbox.

**Design decision:** choice values are stored as **integers mirroring F&O's own option set
values**, not as Dataverse option sets. The Web API returns F&O enums as integers, so this
avoids a translation layer. Conventions are recorded in `scripts/schema.ps1`.

### 2.2 Sync — proven against real data

`Sync-QmCache.ps1` populates the cache from the virtual entities. Run against USMF:

```
Quality orders   6 source rows  -> 6 cached
Test lines      11 source rows  -> 11 cached, all linked to their parent order
Test outcomes    8 source rows  -> 8 cached
Failed           0
```

Tolerances came through intact — `Concentration` 10–30, `Cone weight` 9.9–10.2, with
instruments (`Measuring tape`, `Oscilloscope`). The cached data independently confirms the
verdict rule: QO `000001` value 27 inside 10–30 is Pass; QO `000094` value 5 is Fail.

### 2.3 Draft and outbox — worked example

`New-QmDraftDemo.ps1` produces the shape the app will create: a result sheet against a
cached order, one entry per test line with a **client-computed verdict from cached
tolerances**, a rolled-up sheet verdict, and a single outbox row carrying a correlation GUID.

```
 Coil impedance   seq 10  entered 1     limits 0-0        -> Pass
Cone weight       seq 20  entered 11.2  limits 9.9-10.2   -> Fail
sheet verdict: Fail
outbox: queued, 408 byte payload
```

### 2.4 Drain flow — built, activated, tested

`cog_QM_DrainOutbox`, active at `statecode=1 / statuscode=2`.

```
trigger  a row is created in cog_outbox
  1 Claim            status -> Submitting, attempts 1
  2 Parse payload    the JSON the app queued
  3 For each line    update the F&O result line via the virtual table
  4 Confirm          status -> Confirmed, stamp processed time
  X Flag             on failure, status -> Needs attention, capture the error
```

**End-to-end test.** Queued a payload setting `Cone weight` on QO `000122` to 10.0 against
limits 9.9–10.2, where it previously sat at 11 (Fail):

```
+12s  Confirmed
F&O:  Cone weight  value=10  testresult=200000001 (Pass)
```

The whole chain worked, and **F&O derived the Pass itself** — the flow only ever writes the
measured value. Original value restored to 11 / Fail afterwards.

---

## 3. Gotchas found

| # | Gotcha |
|---|---|
| G1 | **`entityName` on the Dataverse connector must be a literal, not an expression.** With `@body(...)?['TargetEntity']` the connector cannot resolve the entity schema and validation fails with `UpdateRecord is missing required property 'item'` |
| G2 | **`mserp_testresult` is not an exposed writable parameter** on the virtual table through the connector. Not a problem — F&O derives the verdict from the value anyway |
| G3 | **PowerShell:** `Write-Output` inside a function lands on the success stream and becomes part of the return value. A failure path that logged with `Write-Output` returned a truthy object, so 11 failed rows were counted as successes and the errors never printed. Use `Write-Warning` for diagnostics inside functions |
| G4 | Dataverse webhook triggers self-arm; Skills triggers need `POST /start`. Do not generalise the Phase 1 conclusion |

---

## 3a. R11 is dead — generation runs on the SUPPORTED layout

The app shell was created in Studio on 2026-08-17 and the diagnostic run.

**Root cause of the Phase 1 failure confirmed exactly.** The Studio-authored app reports
`MSAppStructureVersion 2.4.0` — precisely the minimum the `SourceCode` unpacker demands.
Phase 1's seed came from `pac canvas create`, which emits `2.0`, so it was rejected. Nothing
was wrong with the layout; the generator was the problem.

| Test | Result |
|---|---|
| `unpack --layout SourceCode` on the Studio app | **Succeeded** |
| `pack --layout SourceCode` unchanged | **Succeeded** — 13,007 -> 13,102 bytes |
| Hand-author two controls, pack | **Succeeded** — 13,361 bytes |
| Unpack again, verify | **Every control and property intact** |

**The `SourceCode` layout is also far better to generate into.** Compare the scaffolding:

| | Experimental (deprecated) | SourceCode (supported) |
|---|---|---|
| Screen source | `.fx.yaml`, ~2.8 KB | `.pa.yaml`, ~0.7 KB |
| Theme | `Themes.json`, **138.9 KB** | bundled in `.msapr` |
| Editor state | 13–24 KB **per screen** | one `_EditorState.pa.yaml`, 0.6 KB |
| Files to manage | 12 | **4** |

Everything except the three small YAML files is bundled into a single `studio.msapr`
container, which pack and unpack manage. Only the YAML needs authoring.

**R9a and R11 are both closed.** The dependency on the deprecated `Experimental` layout is
gone. One caveat stands: pack prints *"Canvas apps packed using yaml SourceCode must be
validated first by opening the app for edit within the Power Apps studio"* — packing works,
but a Studio open is expected before a generated app is trusted in production.

## 3b. Screen generation and publishing — the loop is closed

With the app shell created in Studio and the six data sources added, the remaining question
was whether a generated screen could be pushed back. It can.

**Data sources confirmed present.** The app grew from 13,007 to **77,014 bytes** and
`DataSources.json` from 25 bytes to **1.17 MB**. Power Fx references the tables by their
plural display names, so they need quoting: `'Quality Orders (cache)'`.

**Screen generated.** `QMResultSheet.pa.yaml`, 7,976 bytes — the inspection-sheet layout from
`D-08` in treatment A per `D-09`: order picker, context strip, a gallery over the cached test
lines showing each test with its tolerance range and instrument, an inline value entry, and a
verdict computed live from `cog_lowerlimit` / `cog_upperlimit`.

**Publishing solved.** `pac canvas` has no upload verb, but the app is a solution component
(type 300), so:

```
export the live solution  ->  swap the .msapp payload  ->  bump the version
   ->  re-zip  ->  pac solution import --force-overwrite --publish-changes
```

Result: solution `0.1.0.0 -> 0.1.1.0`, app version stamped `2026-08-17T05:16:56Z`, status
Ready. Downloading from the environment afterwards returns `QMResultSheet.pa.yaml` byte for
byte with every binding intact.

> **Gotcha G5 — this one cost a failed import.** `[ZipFile]::CreateFromDirectory` on .NET
> Framework writes **backslash** path separators into the archive. The solution importer
> matches entries by forward-slash path and fails with *"Xaml file is missing from import zip
> file"* for anything in a subfolder — in this case the drain flow's JSON. Build the archive
> entry by entry and replace `\` with `/`.

> **Safety note.** Always export the live solution and swap the payload. Never hand-build a
> solution zip against a live solution name — an earlier attempt used a minimal
> `customizations.xml` which, with `--force-overwrite`, could have stripped the 34 entities
> and both connection references. It failed before applying, but the risk was real.

**What this changes.** Screen work now needs no human step at all. The only human involvement
was the one-off app shell and data sources. Generate, pack, import, verify — all scripted.

## 3c. Screens built and published

Solution `0.1.2.0`. All generated from `.pa.yaml` and published without a human step.

| Screen | Size | What it does |
|---|---:|---|
| `QMHome` | 5.2 KB | Module tiles, live online/offline strip, queued-item banner. Quality order and NC tiles shown but **disabled** with "later release" |
| `QMOrderList` | 6.2 KB | Searchable, filterable list over the cache — order number, item or product; "Open only" toggle; status pills. Sets `varOrder` and navigates |
| `QMResultSheet` | 12.1 KB | The inspection sheet. All tests in one grid with tolerance and instrument, inline entry, **live verdict from cached bounds**, rolled-up order verdict, and a working submit |
| `QMQueue` | 6.8 KB | The outbox made legible — queued / sending / confirmed / needs attention, with the F&O error and a Retry that requeues |

### The submit is wired end to end

`RS_SubmitButton.OnSelect` writes a draft sheet, one entry per completed test, and a single
outbox row whose payload carries `TargetRecordId` per line. `cog_QM_DrainOutbox` then writes
to F&O — measured at ~12 seconds in §2.4.

It never calls F&O directly, which is what makes it work offline. To supply the target ids,
`cog_targetrecordid` was added to `cog_qualitytestline` and populated during sync by matching
order + test + sequence against `mserp_inventqualityorderlineresultentity`. **11 of 11 lines
resolved.**

### Deliberately not built

`Batch disposition` and `Create NC` screens were left out rather than shipped as dead UI:

- **NC creation** is blocked by the same rule as quality orders — `POST` returns
  `0x80048d02 Not found`; NCs are raised from a parent context.
- **Batch disposition** has an unproven write path. `POWERAPPSPDSDISPOSITIONMASTERENTITY` is
  generated but was never probed, and disposition codes are not yet cached.

Both need a Phase 1-style write probe before any UI is worth building.

### Studio validation — passed on the second attempt

The first published build failed to open in Studio with **39 `PA2108` errors**. Two distinct
bugs, both now fixed and confirmed by the client opening the app cleanly:

**1. Classic versus modern controls.** `Button`, `TextInput` and `Checkbox` all have modern
counterparts, so an unprefixed `Control:` resolves to the **modern** control — which has no
`Fill`, `Color`, `Size` or `HintText`. `Label` and `Rectangle` did not error because
`Rectangle` has no modern version and both resolved classic.

The fix is the namespace prefix the schema pattern allows
(`^([A-Z][a-zA-Z0-9]*/)?[A-Z][a-zA-Z0-9]*...`):

| Use | Not |
|---|---|
| `Control: Classic/Button` | `Control: Button` |
| `Control: Classic/TextInput` | `Control: TextInput` |
| `Control: Classic/CheckBox` | `Control: Checkbox` |
| `Control: Label`, `Control: Rectangle`, `Control: Gallery` | *(fine unprefixed)* |

**2. Encoding.** Repairing the first bug through `Get-Content` / `Out-File` mangled every
middle-dot separator to `Â·` and the em-dashes to `€` and `"` — PowerShell's cp1252 round
trip, the same failure the project standard already documents for `.ps1` files. **The
ASCII-only rule extends to `.pa.yaml`.** `tools/Publish-CanvasApp.ps1` now hard-fails on
non-ASCII before packing rather than leaving it to be noticed later.

**Still unverified:** the app opens and edits cleanly, but that is a *design-time* check.
The submit formula has not been exercised at runtime.

### No static validation available

`pac canvas validate` reports *"no longer supported"* in CLI 2.9.3. `pack` checks YAML
structure but not Power Fx semantics, so **formula errors will only surface when the app is
opened in Studio or played.** That is now the main reason a human pass is still required.

## 4. Not done

| Item | State |
|---|---|
| **Sync flow** | Logic proven as `Sync-QmCache.ps1` against real data, but **not yet authored as a flow**. The authoring pattern is now established; a `Recurrence` trigger may not self-arm the way the Dataverse trigger did — test that when building it |
| **Canvas app** | Blocked. Phase 1 (R9) established that generation requires an existing app to unpack, and **no canvas apps exist in this environment**. A human must create the app shell in Studio once |
| **Attachment drain** | The `POWERAPPFILESAVINGENTITY` write is proven from Phase 1 but is not yet wired into the drain flow |
| **Offline profile** | Phase 3 work, as planned |

---

## 5. Human steps needed

1. **Create the canvas app shell in Power Apps Studio** and add the Dataverse data sources.
   This is the only hard blocker on screen work. Once it exists, download and unpack it and
   screen generation can proceed.
2. **While doing so, run `pac canvas unpack --layout SourceCode` against it** and report
   whether it succeeds. That settles R11 — whether the generation path can move off the
   deprecated `Experimental` layout.
3. Nothing else. Schema, sync and drain need no human intervention.

---

## 6. State of the environment

`QualityManagementApp` now contains:

| Component | Count |
|---|---:|
| Entities | 34 (28 F&O virtual + 6 new `cog_` tables) |
| Connection references | 2 (`cog_QMConnRef_FnO`, `cog_QMConnRef_Dataverse`) |
| Cloud flows | 1 (`cog_QM_DrainOutbox`, active) |

All new objects. No existing Dataverse object was modified.

**Data:** cache tables hold 6 orders, 11 test lines and 8 outcomes from USMF. One demo
result sheet, its entries and outbox rows remain as worked examples. The one F&O value
touched during the drain test was restored to its original.

---

## 7. Next

With the seam proven, the remaining Phase 2 work is the sync flow and then the screens. The
screens are the larger piece and they wait on one thing only — an app shell existing in
Studio. Everything behind them is now working.
