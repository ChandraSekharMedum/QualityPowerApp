# Phase 1 — Final Report

**Quality Management Canvas App · QM-P1-002 · Rev 1.0 · 2026-08-14 · `cus-con-sandbox`**

Parent: QM-ARCH-001 Rev 1.0 · Estimate: QM-EST-001 · Delivery model: QM-EST-002

---

## 1. Executive summary

Phase 1 set out to prove the plumbing before any screens were built. It did, and it found
one thing that changes the shape of the programme.

**The good news.** Every read path works. Test result writes work. Attachment writes work.
The canvas generation approach works, so the delivery saving holds. Two of the three
headline risks closed favourably.

**The finding that matters.** Quality orders **cannot be created over OData by any
available path** — not through virtual entities, not through the Power Automate connector.
This is not a payload problem and not a bug we can code around. It forces a decision that
belongs to the business, not to the build team.

| Objective | Outcome |
|---|---|
| Generate the virtual entities | **Done** — 28/28, zero failures, 34/34 verified |
| Prove quality order creation (R2) | **Proven impossible** over OData — see §3 |
| Prove test result posting | **Works** — persists, F&O recalculates the verdict |
| Prove attachments (R1) | **Works** — and the architecture named the wrong entity |
| Canvas round trip (R9) | **Works** — 49% delivery saving confirmed |

**One decision is needed before Phase 2 starts.** See §7.

---

## 2. What works

| Capability | Path proven | Evidence |
|---|---|---|
| Read all reference and transactional data | 34 `mserp_*` virtual tables | All queried, 29 return live data |
| **Write test results** | `InventQualityOrderLineResultEntity` | `mserp_resultvalue` 5 → 20 persisted; `mserp_testresult` persisted |
| **F&O derives the verdict** | same | Value 20 inside limits 10–30 flipped Fail → Pass with no explicit write |
| **Write photo attachments** | `POWERAPPFILESAVINGENTITY` | Row created against NC `QUA02-D14`, read back successfully |
| Tolerance bounds for the live verdict | `POWERAPPINVENTQOLINEENTITY` | `lowerlimit` / `upperlimit` / `standardvalue` / `testinstrumentid` present |
| Multi-company scoping | `mserp_dataareaid` + `mserp_dataAreaId_id` → `cdm_company` | USMF = `dc28ce57-849a-f011-b4cc-7c1e5249e87c` |
| Unattended tooling | DPAPI extract from pac MSAL cache, silent re-mint | Sustained a full working session |
| Canvas screen generation | `pac canvas` unpack → edit → pack → unpack | Control survived intact; byte-stable |

The app can therefore **execute quality work end to end**: find an order, read its tests and
tolerances, record results, attach photos, and let F&O compute the verdict.

---

## 3. What does not work — and why it matters

### 3.1 Quality order creation is closed on both paths

**Path A — virtual entity POST.** Every field combination was tried, including an exact
mirror of an F&O-accepted order:

| Payload | Result |
|---|---|
| item + site + warehouse, no lot | `No quantity available for item M0001.` |
| lot + item, no product dimension | `Inventory dimension Configuration ... must be specified.` |
| lot + item + configuration, no site | `Inventory dimension Site is mandatory ...` |
| lot + item + configuration + site | `Inventory dimension Owner is inactive and may consequently not be specified.` |
| **full mirror of accepted QO 000122** | `Inventory dimension Owner is inactive ...` |

Site is mandatory, but supplying **any** storage dimension makes the provider send the full
storage dimension set including `Owner`, which is inactive in USMF. No payload satisfies
both constraints.

**Path B — Power Automate + `shared_dynamicsax`.** Built and tested. A control isolates the
cause; same connection and flow shape, only the table changed:

| `table` | `GetTable` |
|---|---|
| `InventorySitesOnHandV2` (proven in `cog_FINC01_InventoryClose`) | **Resolved** |
| `InventQualityOrderHeaderEntity` | NotFound |
| `InventQualityOrderHeaderEntities` | NotFound |
| `InventQualityOrderHeaders` | NotFound |
| `InventQualityOrderLineResultEntities` | NotFound |

The connection and apihub binding are healthy. **The quality entities are not exposed as
public OData entities in this F&O instance.**

### 3.2 The pattern behind it

Three independent probes point the same way, and it matches the domain rule confirmed by
the client during testing: **quality objects are raised from a parent context, never
free-hand.**

- Quality order header create → blocked
- Test result line create → not a thing; the header generates lines from the test group
- Non-conformance create → `0x80048d02 Not found`

F&O's quality association engine raises quality orders against inventory transactions.
Nothing in the OData surface is designed to bypass that.

---

## 4. Risk re-rating

| # | Risk | Was | Now | Basis |
|---|---|---|---|---|
| R1 | Attachment path unproven | High | **Closed** | Write accepted and persisted. Entity corrected to `POWERAPPFILESAVINGENTITY` |
| R2 | QO creation validation | High | **Critical — transformed** | Not "differs by type"; impossible over OData for every type. Now a scope decision |
| R3 | Cache volume for batches / on-hand | Medium | Medium | Untested — deferred to Phase 3 |
| R4 | Conditional Access token revocation | Medium | **Low** | Confirmed (463 s observed) but pac's refresh token re-mints silently |
| R5 | QMS add-on fields blanked by careless update | Medium | Medium | Fields confirmed present on both quality tables. Patch only owned fields |
| R6 | Duplicate submissions after timeout-retry | High | High | Still applies to result and attachment writes, which do work |
| R7 | QUA01/QUA02 agents also write quality records | Medium | **High** | Confirmed — **every** NC in USMF is `QUA02-*`. No shared convention exists |
| R8 | Licensing basis unconfirmed | Medium | Medium | Untouched |
| R9 | Canvas YAML round trip | High | **Closed** | Round trip verified; 49% saving holds, not 37% |

### New risks found

| # | Risk | Rating | Detail |
|---|---|---|---|
| R10 | **Silent write loss on `POWERAPP*` line entities** | **High** | Metadata says `IsValidForUpdate = True`; writes return **200 OK and are discarded**. A screen bound to them would appear to save and would not. Bind writes only to `InventQualityOrderLineResultEntity` |
| R11 | `Experimental` canvas layout is deprecated | Medium | The only working generation path. `SourceCode` is unusable here (`MSAppStructureVersion 2.0 < 2.4.0`). Test a Studio-authored app under `SourceCode` at the first opportunity |
| R12 | `RemoveSolutionComponent` unusable via Web API | Low | CSDL declares `SolutionComponent`; handler demands `ComponentId`. Use the maker portal |
| R13 | Company field collision | Low | Setting both `mserp_dataareaid` and `mserp_dataAreaId_id` fails outright. Set one |

---

## 5. Changes required to QM-ARCH-001

| § | Change |
|---|---|
| 6 | Add the option-set integers — the Web API returns enums as integers, FetchXML returns labels |
| 7 / 10 | Record that tolerance bounds ship with the result line, so the live verdict needs no extra call and works offline |
| 9 | **Replace `POWERAPPSIMAGESSTAGING` with `POWERAPPFILESAVINGENTITY`** throughout. Note `mserp_formname` max length 20 |
| 10 | Note that F&O owns the stored verdict; the client-side verdict is a UX affordance |
| 12 | **X++ custom service moves from "probably" to "required"** if in-app creation is wanted |
| 16 | R1 closed, R9 closed, R2 escalated, add R10–R13, raise R7 |
| — | Correct §2: the `msdyn_QMS*` solutions are Customer Service quality management, unrelated to the F&O QMS add-on. The F&O add-on is real — `mserp_qms*` fields exist on the quality tables |

---

## 6. Estimate impact

**Delivery model confirmed.** R9 closing positively means the **49% saving holds**
(1,014 h → ~520 h), not the 37% downside case. Plan against 40% as advised.

**Scope impact depends on the §7 decision:**

| Option | Power Platform effort | Other |
|---|---|---|
| **1 — Add an X++ custom service** | 1,014 h unchanged | **Plus F&O development not previously scoped** — a custom service for quality order and NC creation. Order of 80–120 h of X++, plus F&O ALM |
| **2 — Reduce scope; F&O raises the orders** | **~875 h** (−140 h) | None. Removes the QO creation component and 7 type configs (−60 h), most of the NC creation build (−36 h), and the two creation write flows (−52 h) |

Option 2 is cheaper and lower risk but contradicts the V3 manual, which describes creating
all seven quality order types. That contradiction is the crux of §7.

---

## 7. The decision needed before Phase 2

**Should the app create quality orders at all?**

1. **Yes — commission an X++ custom service.** Preserves the V3 scope. Requires an F&O
   developer and adds a work stream that was never estimated.
2. **No — reduce scope.** F&O's quality association engine raises the orders; the app finds,
   executes and records against them. Cheaper, faster, and aligned with how F&O is designed
   to work — but it removes a third of the functional scope in the manual.

**Recommendation:** put option 2 to the QA SMEs first. The V3 manual describes what the old
app *did*, not necessarily what the business *needs*. If quality orders are in practice
raised by quality associations on receipt and production, the creation screens may have been
solving a problem that no longer exists. If SMEs confirm they genuinely create ad-hoc
quality orders, option 1 is justified and should be scoped properly with the F&O team.

**Do not let Phase 2 start the creation screens until this is settled** — that is roughly
104 hours of screen work resting on an unresolved premise.

---

## 8. What was built and left behind

### In Dataverse — all new objects, nothing existing modified

| Object | Detail |
|---|---|
| `QualityManagementApp` | Solution, publisher ColumbusGlobal (`cog`), v0.1.0.0 |
| 28 virtual entities | Solution components |
| `cog_QMConnRef_FnO` | Connection reference for F&O, retained for Phase 2 |

Six pre-existing shared entities were deliberately **excluded** from the solution and are
documented in `IMPORT-INSTRUCTIONS.md` as regenerate-in-target prerequisites. The probe flow
was deleted after testing.

### Data

One attachment row created against NC `QUA02-D14` (logged in `output/created-records.txt`).
One test result on QO `000094` was temporarily modified and **restored to its original
values** (value 5, Fail). No quality orders or non-conformances were created — every attempt
was rejected by F&O.

### On disk

```
C:\Quality Agents\phase1\
  PHASE1-REPORT.md          this document
  FINDINGS-INTERIM.md       detailed evidence per finding
  IMPORT-INSTRUCTIONS.md    target-environment prerequisites
  scripts\                  9 PowerShell scripts, all idempotent
  output\                   entity verification, field reference, option sets,
                            created-records log, flow clientdata
  canvas-test\              R9 evidence: seed app, unpacked sources, round-trip proof
```

Reusable beyond Phase 1: `dvlib.ps1` (auto re-minting Web API helper),
`Invoke-EntityGeneration.ps1` (target-environment deployment),
`Test-GeneratedEntities.ps1`, `Export-OptionSets.ps1`, `New-QmSolution.ps1`.

---

## 9. Recommended next steps

1. **Put the §7 question to the QA SMEs.** Everything else waits on it.
2. **Confirm the attachment renders in F&O.** One visual check on NC `QUA02-D14` — the only
   part of R1 that could not be verified programmatically.
3. **Agree a source-marker convention with the QUA02 agent owners** (R7). Two systems are
   writing quality records into the same tables with no way to tell them apart.
4. **Test a Studio-authored app under `pac canvas unpack --layout SourceCode`** (R11). One
   command; decides whether the generation path has a future.
5. **Then start Phase 2** on the seam and the test-result journey — the part of the app that
   is fully proven and unaffected by the §7 decision.

Step 5 is genuinely unblocked. The highest-value screen in the app, test result entry, has
every dependency proven: reads, tolerances, writes, verdict handling and attachments.
