# Build Guide

End‑to‑end build order for the Quality Management canvas app on D365 F&O. ~½ day for someone
familiar with Power Platform (longer if F&O entities need enabling).

**Architecture:** Canvas App → Power Automate flows → F&O OData. See `Architecture.md`.

---

## STEP 0 — F&O prep (do this first; it gates everything)

1. Record your **F&O base URL** and **legal‑entity codes** in `FnO-Data-Model.md` §G.
2. In F&O **Data management → Data entities**, confirm each entity in `FnO-Data-Model.md` is
   present and **enabled for OData**. Search `$metadata` for anything marked *(confirm)*.
3. **Decide the create paths** for quality orders, test‑result submit, and NC create — a plain
   entity or a bound action. If a create entity is missing, have an F&O developer publish the
   recommended custom integration entity. Write the chosen path into §G.
4. Ensure the **integration/service account** has an F&O user mapping + a security role with
   read/write on the quality entities.
5. Pick the **attachment target** (`DocuRefEntity` or Dataverse) — §F.

## STEP 1 — Connection

Create the F&O connection you'll use in all flows (Architecture §3):
- **Fin & Ops Apps (Dynamics 365)** connection, **or**
- **HTTP with Microsoft Entra ID** connection with **Resource URI = your F&O base URL** (fallback).

Prefer a **service account** so the integration outlives staff changes.

## STEP 2 — Build the lookup flows

Follow `flows/lookups/README.md`. Build the small cached ones first (`Lookup_TestGroups`,
`Lookup_ProblemTypes`, `Lookup_DispositionCodes`) so `App.OnStart` works, then the
query‑as‑you‑type ones. Test each returns JSON in **Run → Test**.

## STEP 3 — Build the write flows

In order: `QO_CreateQualityOrder` → `TR_SubmitTestResult` → `NC_CreateNonConformance` →
`BD_GetBatch` + `BD_UpdateBatchDisposition`. Each file lists trigger inputs (in order), the F&O
action, response outputs, and a catch branch. **Test each flow standalone** before wiring the app.

## STEP 4 — Build the app

1. `make.powerapps.com` → **Create → Blank canvas app → Phone** → name `QualityManagement`.
2. Add the **components** in `canvas-app/app/components.md` (header, nav, lookup, field, busy).
3. Paste `canvas-app/app/theme.fx` then `App.OnStart.fx` into **App → OnStart**.
4. Add data: **Power Automate → Add flow** for every flow the app calls (all of Step 2 & 3).
5. Build each screen from `canvas-app/screens/*.md` — add controls, paste the Power Fx. Keep the
   `.Run()` argument order identical to each flow's trigger inputs.
6. Run **App → OnStart** (⋯ → Run OnStart) once so collections populate while authoring.

## STEP 5 — Test (see `deploy/checklist.md` for the full matrix)

Use **Power Apps mobile** for barcode features. Walk each function once against a known F&O
record; confirm the record in F&O and that `scrSuccess` shows the returned number.

## STEP 6 — Publish & share

**File → Save → Publish.** Share the app with users; grant them the flow connections and the
premium license. Add **flow co‑owners** (or use a service‑account connection) so flows don't break
when the author leaves.

## STEP 7 (optional) — Package for ALM

`solution/pac-commands.md` — put the app + flows + connection references in a Dataverse solution
and version it in this repo for dev→test→prod movement.

---

## Gotchas (the ones that actually bite)

- **`.Run()` argument order** must equal the flow's trigger input order — exactly.
- **`cross-company=true` + lowercase `dataAreaId`** on every F&O call, or you silently hit the
  wrong/empty company.
- **Bare dates** break F&O's deserializer — the app already sends full ISO for NC dates.
- **Numbers as numbers** — `qty`, `resultQuantity` must be numeric in the flow body, not quoted.
- **Barcode = mobile only** — the batch‑disposition scan won't work in a browser (manual note);
  the manual‑entry fallback covers web testing.
- **F&O connector apihub broken?** Switch those flows to **HTTP‑with‑Entra‑ID** — the app doesn't
  change (Architecture §3).
- **Quality‑order create has no standard entity** in many versions — don't skip STEP 0.3.
