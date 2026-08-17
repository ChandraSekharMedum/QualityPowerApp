# Phase 1 — Findings

| | |
|---|---|
| **Document** | QM-P1-001 |
| **Revision** | 0.2 — interim (write tests outstanding) |
| **Date** | 2026-08-14 |
| **Environment** | `cus-con-sandbox` |
| **Parent** | QM-ARCH-001 Rev 1.0 |

---

## 1. Summary

Six findings. Two **change the architecture**, one **confirms `D-07`**, one **improves on
an assumption in QM-EST-002**.

| # | Finding | Effect on the architecture |
|---|---|---|
| F1 | Unattended Dataverse write path works via pac's refresh token | Less human intervention than QM-EST-002 assumed |
| F2 | All 28 virtual entities generated; 34/34 exist and query, 29 return data | Task complete, no failures |
| F3 | **Direct virtual-entity create of quality orders is blocked** by a provider defect | **Confirms `D-07`**; raises X++ service priority |
| F4 | Web API returns enums as integers; FetchXML returns labels | New build gotcha; option set reference produced |
| F5 | **R1 RESOLVED** — `POWERAPPFILESAVINGENTITY` is the attachment path, and it is writeable | **Corrects §9**; risk closes |
| F6 | **Test result entity carries the tolerance bounds** | Verifies the §10 inspection-sheet design |

---

## 2. F1 — Unattended write path *(task 1, complete)*

A Dataverse token is extracted from the pac CLI MSAL cache
(`%LOCALAPPDATA%\Microsoft\PowerAppsCli\tokencache_msalv3.dat`) via Windows DPAPI under
the same user account. `WhoAmI` confirmed working.

**Correction to QM-EST-002.** That document listed interactive sign-in as a *recurring*
blocker because Conditional Access revokes tokens every 15–20 minutes. The short lifetime
is real — the first extracted token had **463 seconds** left — but `pac org who` silently
re-mints from the stored refresh token with no prompt. `dvlib.ps1` re-mints below 120
seconds and retries once on 401. Interactive auth is needed only when the **refresh**
token expires.

**Still genuinely blocked:** management-plane APIs. `api.powerplatform.com` and
`api.bap.microsoft.com` both return **401** with the cached tokens, so the linked F&O
instance URL could not be discovered. Reaching F&O OData directly needs an F&O-audience
token (interactive) or a Power Automate flow.

---

## 3. F2 — Virtual entity generation *(tasks 2 and 3, complete)*

Generation is a `PATCH` of `mserp_hasbeengenerated = true` on the catalogue row.

- All **28 targets resolved** — none missing from the catalogue.
- **28 of 28 patched, zero failures.**
- Each PATCH is **synchronous, ~2.6 minutes**. Full set ≈ 75 minutes wall-clock.
- Verification across all **34** tables (28 new + 6 pre-existing): **34/34 exist and are
  queryable; 29 return data.**

Naming: logical name is `mserp_` + lowercased physical name. **Read `EntitySetName` from
metadata rather than guessing the plural** — several are irregular.

### The five empty tables are all staging entities

`POWERAPPITEMBATCHTRACINGENTITY`, `POWERAPPSINVENTNONCONFORMATIONENTITY`,
`POWERAPPINVENTBATCHTMPENTITY`, `POWERAPPSIMAGESSTAGING`, `POWERAPPFILESAVINGENTITY`.

Empty is expected — these are **write targets**, not read views. Confirmed by metadata
(F5). This reframes the `POWERAPP*` family: it is not only the read layer the
architecture assumed, it is a **purpose-built read *and write* layer** for this app.

### Notable field counts

| Entity | Fields | Use |
|---|---:|---|
| `VendVendorV2Entity` | 309 | Vendor picker — select explicitly, never bind whole |
| `POWERAPPSPRODTABLEENTITY` | 80 | Production order picker |
| `POWERAPPSINVENTLOCATION` | 75 | Location picker |
| `InventQualityOrderHeaderEntity` | 66 | QO header |
| `POWERAPPPRODBATCHORDERCOPRODUCTENTITY` | 52 | Co-product |
| `POWERAPPSPRODPRODUCTIONORDERROUTEOPERATIONENTITY` | 48 | Route operation |

---

## 4. F3 — Quality order creation *(task 4, R2)*

### 4.1 Virtual entity POST reaches F&O

First attempt returned:

```
400  0x80048d0b  "No quantity available for item D0004."
```

Not a read-only rejection — **F&O business logic executing**, with the error code and a
human-readable message surfaced cleanly through OData. That is exactly the error channel
the app needs to show an inspector.

### 4.2 Quality orders attach to an inventory lot

**No `Inventory` reference type quality orders exist in any company.** Quality orders are
normally raised by F&O's quality association engine against an inventory transaction.
A known-good record (QO `000122`, USMF) shows the decisive fields:

```
mserp_referenceinventorylotid = 009512
mserp_inventdimensionid       = 000250
mserp_inventrefid             = P000152
```

This matches the manual exactly — "Reference lot … Inventory dimensions and
Identification are automatically populated after selecting Reference lot". The app must
let the user pick a **reference lot**, not merely an item plus dimensions.

### 4.3 The blocker

| Payload | Result |
|---|---|
| item + site + warehouse, no lot | `No quantity available for item M0001.` |
| lot + item, no product dimension | `Inventory dimension Configuration is a product dimension and must consequently be specified.` |
| lot + item + configuration, no site | `Inventory dimension Site is mandatory and must consequently be specified.` |
| lot + item + configuration + site | `Inventory dimension Owner is inactive and may consequently not be specified.` |

Site is mandatory, but supplying **any** storage dimension makes the provider send the
**full storage dimension set including `Owner`** — inactive in USMF — which F&O rejects.
No payload satisfies both. `Owner` can be neither omitted nor supplied.

**Conclusion: direct virtual-entity create of quality orders is not viable here.** This
confirms `D-07` — writes go through Power Automate and `shared_dynamicsax`, which composes
the dimension set correctly — and raises the X++ custom service in §12 from *probably* to
**strongly indicated** for quality order creation.

The designed write path is **not yet tested**; it needs a flow, which needs a connection
created interactively.

### 4.4 The F&O connector path is ALSO closed — R2 complete

The designed write path (`D-07`: Power Automate + `shared_dynamicsax`) was built and tested.
A new connection reference (`cog_QMConnRef_FnO`) and a new flow were created in
`QualityManagementApp`, using an existing connection owned by the current user.

Activation failed at connector validation:

```
InvalidOpenApiFlow -> DynamicOperationRequestClientFailure
  The dynamic operation request to API 'dynamicsax' operation 'GetTable'
  failed with status code 'NotFound'.
```

A control test isolates the cause. Same connection, same flow shape, only the table changed:

| `table` parameter | `GetTable` result |
|---|---|
| `InventorySitesOnHandV2` (proven in `cog_FINC01_InventoryClose`) | **Resolved** — validation passed |
| `InventQualityOrderHeaderEntity` | **NotFound** |
| `InventQualityOrderHeaderEntities` | **NotFound** |
| `InventQualityOrderHeaders` | **NotFound** |
| `InventQualityOrderLineResultEntities` | **NotFound** |

The connection and its apihub binding are healthy — a known-good table resolves. **The
quality entities are simply not exposed as public OData entities in this F&O instance.**

### 4.5 R2 conclusion: both write paths are closed for creation

| Path | Status for creating a quality order |
|---|---|
| Virtual entity POST | **Blocked** — site is mandatory, but supplying it forces the inactive `Owner` dimension |
| F&O connector via Power Automate | **Blocked** — entity not exposed to the connector |

Note what still **works**, proven in this phase:

| Operation | Path | Status |
|---|---|---|
| Read anything | virtual entities | 34 tables verified |
| **Write test results** | `InventQualityOrderLineResultEntity` | **Works, persists, verdict auto-recalculates** |
| **Write attachments** | `POWERAPPFILESAVINGENTITY` | **Works, persists** |

So the app can execute quality work end to end. What it cannot do over OData is **create**
quality orders or non-conformances — which is consistent with the domain rule confirmed
three times over: quality objects are raised from a parent context by F&O.

### 4.6 The decision this forces

This is now a business question, not a technical one:

1. **Add an X++ custom service** exposing quality order creation. §12 moves from "probably"
   to **required** if in-app creation is wanted. Needs an F&O developer.
2. **Or reduce scope** — F&O's quality association engine raises the orders, and the app
   finds, executes and records results against them. This drops the seven creation screens
   entirely, a substantial reduction, but it contradicts the V3 manual which clearly
   describes creating all seven types.

Put to the QA SMEs before Phase 2 commits to the creation screens.

### 4.7 New build gotcha

```
The same external field was defined by more than one logical field, which is not supported.
LogicalFields:[mserp_dataareaid_id, mserp_dataareaid]  ExternalField: dataAreaId  Action: Create
```

Set the company string **or** the lookup, never both. Lookup navigation property is
`mserp_dataAreaId_id` (note capitalisation) → `cdm_company`; USMF is
`dc28ce57-849a-f011-b4cc-7c1e5249e87c`.

---

## 5. F4 — Option sets *(task 9, complete)*

Web API returns enums as **integers**; FetchXML returns **labels**. Full mapping in
`output/OPTION-SETS.md`.

### `mserp_referencetype` — the seven manual types, plus four more

| Value | Label | | Value | Label |
|---|---|---|---|---|
| `200000000` | Inventory | | `200000006` | Co-product production |
| `200000001` | Sales | | `200000007` | Goods in transit order |
| `200000002` | Purchase | | `200000008` | Inbound shipment order |
| `200000003` | Production | | `200000009` | Sales return |
| `200000004` | Quarantine | | `200000010` | Transfer |
| `200000005` | Route operation | | | |

The four extra types are not in the V3 manual — worth a scope decision, since they are
nearly free if the creation component is configuration-driven.

| Attribute | Values |
|---|---|
| `mserp_qualityorderstatus` | `200000000` Open, `200000001` Fail, `200000002` Pass |
| `mserp_testresult` | `200000000` Fail, `200000001` Pass |
| `mserp_inventnonconformancetype` | `200000000` Internal … `200000005` Co-product production — exactly the manual's six |
| `mserp_inventnonconformanceapproval` | `200000000` New, `200000001` Approved, `200000002` Refused |

---

## 6. F5 — R1 RESOLVED, and §9 corrected *(task 6)*

**The architecture named the wrong entity.** §9 proposed routing photos through
`POWERAPPSIMAGESSTAGING`. That entity is for **product images**, not quality attachments:

```
mserp_displayproductnumber, mserp_imagevarchar, mserp_thumbnailsize, mserp_dataareaid
```

The correct entity is **`POWERAPPFILESAVINGENTITY`**, and it is a far better fit than
assumed. **Every field is `IsValidForCreate = True`:**

| Field | Type | Required | Purpose |
|---|---|---|---|
| `mserp_imagevarchar` | Memo | — | Base64 image payload |
| `mserp_filename` | String | — | File name |
| `mserp_formname` | String | — | Originating F&O form context |
| `mserp_tablerefid` | String | **ApplicationRequired** | Record the file attaches to |
| `mserp_inventnonconformanceid` | String | — | **Attaches directly to a non-conformance** |
| `mserp_testid` | String | — | **Attaches to a specific test** |
| `mserp_testsequence` | Integer | — | Test sequence within the order |
| `mserp_linenum` | Decimal | — | Result line |
| `mserp_displayordernumber` | String | — | Order number |

This entity attaches an image to a **non-conformance**, to a **specific test result line**,
or to a generic record reference — exactly the three cases the manual describes.

**R1 downgrades from "highest-uncertainty, may need redesign" to "path identified,
write test outstanding".** The §12 fallback ("a small custom entity writing directly to
`DocuRef`") is very likely unnecessary.

> **Caveat.** Metadata permits create; that is not proof F&O accepts the write. F3 showed
> metadata can allow a create that business logic then blocks. The write test is the next
> step and needs sign-off to create records.

### `POWERAPPSINVENTNONCONFORMATIONENTITY` is the NC write entity

Also fully writeable: `mserp_inventnonconformanceid` (required),
`mserp_inventnonconformancetype` (create-only), `mserp_inventtestproblemtypeid`
(required), `mserp_nonconformancedate` (required), `mserp_inventrefid`,
`mserp_inventtransidref`, `mserp_inventtranstype`, `mserp_testdefectqty`,
`mserp_vendaccount`, `mserp_description`.

**Note:** it exposes `mserp_vendaccount` but **no `custaccount`**. Customer, Service
request and Internal NC types may need a different path. Flag for the build.

---

## 6a. F5 CONFIRMED BY WRITE — R1 is closed *(task 6, complete)*

`POWERAPPFILESAVINGENTITY` **accepts and persists** an attachment write. Verified against a
real non-conformance in USMF.

```
POST mserp_powerappfilesavingentities
  mserp_tablerefid             = QUA02-D14
  mserp_inventnonconformanceid = QUA02-D14
  mserp_filename               = phase1-probe.png
  mserp_formname               = NonConformance
  mserp_imagevarchar           = <base64 PNG>
  mserp_dataareaid             = usmf
-> 201, id 00011023-0000-0000-0000-005001000000
-> read back successfully: the row persists
```

**Field constraint found:** `mserp_formname` is capped at **20 characters**
(`InventNonConformanceTable` at 25 was rejected with a clean validation error).

**R1 closes.** The §12 fallback — a custom X++ entity writing to `DocuRef` — is not needed.

*Not verified:* whether F&O surfaces the staged image as a document attachment on the NC in
the F&O client. There is no `DocuRefEntity` in the catalogue to check programmatically.
**Confirm visually in F&O once** before signing off the attachment design.

## 7. F6 — Test results: read tolerances from one entity, write results to another *(task 5, complete)*

`POWERAPPINVENTQOLINEENTITY` is the test-result write entity, and it supplies exactly what
the §10 inspection-sheet design needs:

| Field | Purpose |
|---|---|
| `mserp_qualityorderid`, `mserp_testid`, `mserp_testsequence` | Composite key, create-only, all ApplicationRequired |
| `mserp_testresult` | Pass / Fail picklist, updatable |
| `mserp_pdsorderlineresult` | The entered result value |
| `mserp_lowerlimit`, `mserp_upperlimit` | **Tolerance bounds** |
| `mserp_lowertolerance`, `mserp_uppertolerance`, `mserp_standardvalue` | Tolerance detail and target |
| `mserp_testinstrumentid` | Instrument, e.g. `PhMeter01` |
| `mserp_variableid`, `mserp_variableoutcomeidstandard` | Qualitative outcome list |
| `mserp_testunitid` | Unit symbol (read-only) |

**This verifies the §10 design assumption.** The live pass/fail verdict computed as the
inspector types is achievable because the bounds come down with the line — no extra call,
and it works offline once cached.

`INVENTQUALITYORDERLINEENTITYPOWERAPP` is a parallel entity with more verbose naming and
percentage-based limits.

### Write testing — and an important correction

> **Domain rule (confirmed by the client): the header creates the lines.** Test result
> lines are never authored manually. F&O generates them from the test group when the
> quality order header is created. The app only ever **updates results** on lines that
> already exist.

Write tests against the same USMF line (QO `000094`, test `Concentration`, seq 10):

| Entity | Field written | Accepted | Persisted |
|---|---|---|---|
| `POWERAPPINVENTQOLINEENTITY` | `mserp_testresult` | 200 OK | **No** |
| `INVENTQUALITYORDERLINEENTITYPOWERAPP` | `mserp_qualitytestresultvalue` | 200 OK | **No** |
| **`InventQualityOrderLineResultEntity`** | `mserp_resultvalue` | 200 OK | **Yes** — 5 -> 20 |
| **`InventQualityOrderLineResultEntity`** | `mserp_testresult` | 200 OK | **Yes** |

The two `POWERAPP*` line entities are **read projections**. Consistent with the domain rule
above, they are not write targets — which is correct behaviour, not a defect. Note the trap
for the build: their metadata advertises `IsValidForUpdate = True` and they **return 200 OK
while silently discarding the write**. A screen bound to them would appear to save and
would not.

### F&O recalculates the verdict

Writing `mserp_resultvalue = 20` (inside limits 10–30) against a line previously at value 5
flipped `mserp_testresult` from **Fail to Pass automatically**, with no explicit write.

So the app does not have to compute the stored verdict — F&O derives it from the value
against the tolerance. The client-side live verdict in §10 remains valuable for immediate
feedback before submit, but it is a **UX affordance, not the system of record**.

### Resulting design

| Purpose | Entity |
|---|---|
| **Read** the test list, tolerances, instrument, target value | `POWERAPPINVENTQOLINEENTITY` (`mserp_lowerlimit`, `mserp_upperlimit`, `mserp_standardvalue`, `mserp_testinstrumentid`) |
| **Write** the entered result and outcome | `InventQualityOrderLineResultEntity` (`mserp_resultvalue`, `mserp_testresult`) |

The base result entity does **not** carry tolerance bounds, which is why both are needed.

**All test data was restored** — QO `000094` is back to value 5, testresult Fail.

### Non-conformance creation is also parent-driven

`POWERAPPSINVENTNONCONFORMATIONENTITY` accepts `GET` but returns
`0x80048d02 "Not found"` on `POST`, for both Internal and Vendor types. Consistent with the
same model as quality orders and lines: **NCs are raised from a parent context** — a quality
order or inventory transaction — not created free-hand over OData.

---

## 7a. Solution — created retrospectively

**Gap found on review.** No solution existed for this work, and the 28 generated virtual
entities were sitting in the **Default** solution — against §13 ("nothing is created in the
default solution"). Partly unavoidable: generation is a `PATCH` on the F&O catalogue row
and that operation has no `MSCRM.SolutionUniqueName` equivalent, so the provider decides
placement. It should still have been flagged at the time.

Now created:

| | |
|---|---|
| Unique name | `QualityManagementApp` |
| Friendly name | Quality Management App |
| Publisher | ColumbusGlobal (`cog`), `c7d563c3-c45a-f111-bec7-000d3a582429` |
| Version | 0.1.0.0 |
| Solution id | `6d5e7d9b-fe97-f111-8075-000d3a1b0dc8` |
| Components | **28** entities (ComponentType 1) — Phase 1 generated only |

### Scope of the solution: 28, not 34

Six entities were generated before Phase 1 and are **shared with other solutions** —
`VendVendorV2Entity` alone belongs to `msdyn_FnoInvoiceCaptureFNOIntegration`,
`MicrosoftOperationsERPVE` and `Default`. They were briefly added to make the manifest
complete, then **deliberately removed** so this solution never co-owns components other
workloads depend on. They are recorded in `IMPORT-INSTRUCTIONS.md` §2 as a prerequisite to
regenerate in a target environment.

Verified afterwards: all six are back to exactly their pre-Phase-1 solution membership.

> **Note on shared membership.** Adding a component to an *unmanaged* solution is a view
> over it, not ownership — it does not modify the entity or affect other consumers. The
> real risk is at managed export/import into a target, which is why the six are documented
> as a prerequisite rather than packaged.

### Platform gotcha: `RemoveSolutionComponent` is unusable via the Web API

Removing the six took four attempts and none of the documented approaches worked:

| Attempt | Result |
|---|---|
| `ComponentId` parameter | `The parameter 'ComponentId' is not a valid parameter for RemoveSolutionComponent` |
| `ObjectId` parameter | `The parameter 'ObjectId' is not a valid parameter...` |
| `SolutionComponent` entity reference (per CSDL) | `Required field 'ComponentId' is missing for RequestName='RemoveSolutionComponent'` |
| `DELETE /solutioncomponents(id)` | `The 'Delete' method does not support entities of type 'solutioncomponent'` |

The CSDL declares `SolutionComponent` (type `mscrm.solutioncomponent`) while the platform
handler demands `ComponentId` — the two disagree. Note the asymmetry with
`AddSolutionComponent`, which takes `ComponentId` as `Edm.Guid`.

`pac solution` has `add-solution-component` but **no remove**.

**Workaround used:** delete and recreate the unmanaged solution. Deleting an unmanaged
solution removes only the container — verified that all entities survived. For a solution
with real components this would be destructive, so use the maker portal instead once
Phase 2 components exist.

**Caveat carried forward:** the 28 are provider-generated and `IsManaged = True`.
`AddSolutionComponent` accepted them, but that is not proof they export and import
cleanly. **Test an export before relying on it**; `Invoke-EntityGeneration.ps1` is the
fallback deployment path, since virtual tables depend on the target F&O catalogue.

From here, every Phase 2 component — cache/draft/outbox tables, flows, environment
variables, connection references, the app itself — goes into this solution at creation
time, with the `MSCRM.SolutionUniqueName` header on every Web API write.

## 7b. F7 — R9 ANSWERED: canvas round trip works *(task 7, complete)*

**Verdict: screen generation is viable. The 49% saving holds, not the 37% downside — but
it runs on a deprecated code path and requires a seed app.**

### What was tested

| # | Test | Result |
|---|---|---|
| 1 | Hand-author source from scratch, `SourceCode` layout | **FAIL** — `System.FormatException`. Tool states: *"Canvas apps packed using yaml SourceCode must be validated first by opening the app for edit within the Power Apps studio."* |
| 2 | Hand-author from scratch, `Experimental` layout | **FAIL** after 4 iterations. Errors degrade from clean validation (`missing CanvasManifest.json`, then `manifest version must be 0.30`) to `PA3001 Internal error` to an unhandled `JsonException` |
| 3 | Unpack a real app, `SourceCode` layout | **FAIL** — `MSAppStructureVersion 2.0 is below the minimum supported version 2.4.0` |
| 4 | Unpack a real app, `Experimental` layout | **PASS** |
| 5 | Repack unchanged | **PASS** — byte-identical, 14,795 -> 14,795 |
| 6 | Hand-edit a screen, repack | **PASS** — only `Warning PA2001: Checksum mismatch... If this was intentional, ignore this warning`. 14,795 -> 14,941 |
| 7 | Unpack the modified app, verify the control | **PASS** — control present, every property intact |

No canvas apps exist in this environment, so the seed was generated with
`pac canvas create` from an existing custom connector.

### Why hand-authoring from scratch fails

The screen source is small and clean; the scaffolding around it is not.

| File | Size | Hand-authorable? |
|---|---:|---|
| `Src\HomeScreen_Screen.fx.yaml` | 2.8 KB | **Yes** — clean declarative Power Fx |
| `Src\Themes.json` | **138.9 KB** | No — a 300-byte hand-written version crashed the tool |
| `Src\EditorState\*.editorstate.json` | 13–24 KB per screen | No — 5–10x the screen source itself |
| `Entropy\checksum.json`, `Entropy.json` | 3.3 KB | No |
| `ControlTemplates.json`, `CanvasManifest.json` | 3 KB | Partly |

### What the screen source looks like

Exactly the kind of declarative structure that generates well:

```yaml
HomeScreen_VerticalContainer As groupContainer.verticalAutoLayoutContainer:
    LayoutAlignItems: =LayoutAlignItems.Center
    LayoutGap: =20
    QM_Verdict_Label As label:
        Color: =RGBA(156, 31, 23, 1)
        Fill: =RGBA(247, 227, 225, 1)
        Text: ="Order verdict: Fail - 1 of 4"
```

### The viable workflow

1. **Human** creates the app shell in Power Apps Studio, adds data sources and connections.
2. `pac canvas download` then `unpack --layout Experimental`.
3. **Claude** generates and edits the `.fx.yaml` screen sources.
4. `pac canvas pack` — the checksum warning is expected and benign.
5. **Human** opens in Studio to verify rendering and interaction.

Both human bookends were already costed in QM-EST-002, so the screens workstream saving of
**42% stands** and the overall **49%** holds.

### New risks

| # | Risk |
|---|---|
| R9a | The only working path, the `Experimental` layout, is **deprecated** — "will be removed in a future release". `pac canvas create` is deprecated too. |
| R9b | The supported `SourceCode` layout is **unusable in this toolchain version** — it requires `MSAppStructureVersion >= 2.4.0` while `pac canvas create` emits 2.0. |

> **Open question, and it matters.** The seed came from `pac canvas create` (structure
> version 2.0). An app authored in **Studio** today would likely be 2.4+ and might unpack
> cleanly under `SourceCode`, removing R9a and R9b entirely. This could not be tested —
> there are no canvas apps in this environment. Resolve it the moment the first app shell
> is created in Phase 2: unpack it with `--layout SourceCode`. That one command decides
> whether the generation path has a future or is running on borrowed time.

## 8. Status against the Phase 1 plan

| Task | Status |
|---|---|
| 1 · Establish Dataverse write path | **Complete** |
| 2 · Generate virtual entities | **Complete** — 28/28, 0 failures |
| 3 · Verify tables and field shapes | **Complete** — 34/34 verified |
| 4 · Probe QO create (R2) | **Complete** — both write paths closed; forces a scope decision |
| 5 · Probe test result posting | Entity identified and characterised; write test outstanding |
| 6 · Validate attachments (R1) | **Path identified and corrected**; write test outstanding |
| 7 · Canvas round trip (R9) | **Complete** — generation viable; 49% saving holds |
| 8 · Findings report | This document |
| 9 · Option set extraction | **Complete** (unplanned, essential) |

---

## 9. Changes needed to QM-ARCH-001

1. **§9 — replace `POWERAPPSIMAGESSTAGING` with `POWERAPPFILESAVINGENTITY`** throughout,
   and add the field table from §6 above.
2. **§6 — add the option set integers**; every enum filter and write uses them.
3. **§7/§10 — record that tolerance bounds ship with the result line**, so the live verdict
   needs no extra call and works offline.
4. **§12 — raise the X++ custom service for quality order creation** from "probably" to
   "strongly indicated", citing the Owner-dimension defect.
5. **§16 — R1 downgrade to low**, add a new risk for the Owner-dimension provider defect,
   add the `custaccount` gap on the NC entity.
6. **QM-EST-002 §3** — soften the recurring interactive-auth blocker.

---

## 10. What is needed from you

1. **A Power Automate connection to F&O** (`shared_dynamicsax`), created interactively.
   Without it the designed write path cannot be tested and tasks 4 and 5 cannot close.
2. **Sign-off to create test records.** **Nothing has been written to F&O so far** — every
   create attempt was rejected by validation. The remaining write tests (attachment, NC,
   test result) would create real records in USMF.
3. **Scope decision on the four extra reference types** — Goods in transit, Inbound
   shipment, Sales return, Transfer.

---

## 11. Artefacts

```
C:\Quality Agents\phase1\
  scripts\  Get-DataverseToken.ps1       DPAPI token extraction
            dvlib.ps1                    Web API helper, auto re-mint, 401 retry
            entity-targets.ps1           The 28 target entities, annotated
            Invoke-EntityGeneration.ps1  Idempotent generation with -WhatIf
            Test-GeneratedEntities.ps1   Verification and field-shape capture
            Export-OptionSets.ps1        Option set extraction
            Find-FnoUrl.ps1              F&O URL discovery (unsuccessful, documented)
            New-QmSolution.ps1           Idempotent solution creation + component add
            Remove-SharedEntities.ps1    Component removal (documents the broken API)
  IMPORT-INSTRUCTIONS.md                 Target-environment prerequisites
  output\   entity-resolution.json       All 28 resolved
            entity-generation.json       28 patched, 0 failures
            entity-verification.json     34/34 verified
            entity-field-shapes.json     Field lists for 29 tables
            FIELD-REFERENCE.md           Human-readable field reference
            OPTION-SETS.md               Option set build reference
            option-sets.json
  FINDINGS-INTERIM.md                    This document
```
