# QualityManagementApp — Deployment Prerequisites

| | |
|---|---|
| **Solution** | `QualityManagementApp` |
| **Publisher** | ColumbusGlobal (`cog`) |
| **Version** | 0.1.0.0 |
| **Source environment** | `cus-con-sandbox` |
| **Status** | Phase 1 — grows as Phase 2 adds components |

This document records everything a **target environment** needs that the solution package
does not carry. Update it whenever a component is added that has an external dependency.

---

## 1. F&O virtual entities — regenerate, do not import

The solution contains **28 F&O virtual entities** (ComponentType 1). These are generated
by the Finance and Operations virtual entity provider from the **target environment's own**
F&O entity catalogue. They are `IsManaged = True` and provider-owned.

> **Do not rely on the package to create them.** Virtual tables are bound to the F&O
> instance linked to that environment. Regenerate them in the target before importing.

### How

```powershell
# 1. Authenticate against the target environment
pac auth create --environment <target-env-url>

# 2. Dry run — confirms all 28 exist in the target's F&O catalogue
.\phase1\scripts\Invoke-EntityGeneration.ps1 -WhatIf

# 3. Generate. Each PATCH is synchronous at roughly 2.6 minutes,
#    so budget about 75 minutes for the full set.
.\phase1\scripts\Invoke-EntityGeneration.ps1 -BatchSize 6 -PauseSeconds 15

# 4. Verify all tables exist, query, and return data
.\phase1\scripts\Test-GeneratedEntities.ps1
```

If any entity is reported `NOT IN CATALOGUE`, the target F&O instance is missing that data
entity — usually a version or module difference. Resolve before importing the solution.

---

## 2. Six shared entities — required but deliberately NOT in the solution

The app also depends on six virtual entities that are **not** solution components. They
were already generated in the source environment and are shared with other solutions
(`VendVendorV2Entity` alone is used by `msdyn_FnoInvoiceCaptureFNOIntegration`,
`MicrosoftOperationsERPVE` and `Default`). Including them would make this solution a
co-owner of components other workloads depend on.

**These must be generated in the target environment before import:**

| F&O entity | Virtual table | Used by |
|---|---|---|
| `InventQualityOrderHeaderEntity` | `mserp_inventqualityorderheaderentity` | Quality order header, all seven types |
| `InventQualityOrderLineResultEntity` | `mserp_inventqualityorderlineresultentity` | Test result lines |
| `INVENTNONCONFORMANCETABLEENTITY` | `mserp_inventnonconformancetableentity` | Non-conformance, all six types |
| `POWERAPPSINVENTQUARANTINEORDERENTITY` | `mserp_powerappsinventquarantineorderentity` | Quarantine quality order |
| `POWERAPPITEMBATCHTRACINGENTITY` | `mserp_powerappitembatchtracingentity` | Batch disposition lookup |
| `VendVendorV2Entity` | `mserp_vendvendorv2entity` | Vendor picker (309 fields — always `$select`) |

To generate them, add their names to `$script:EntityTargets` in
`phase1\scripts\entity-targets.ps1` and run the generation script, or switch
`mserp_hasbeengenerated` in the maker portal.

---

## 3. Environment prerequisites

| Requirement | Detail |
|---|---|
| **F&O virtual entity provider** | `MicrosoftOperationsERPVE` must be installed (v2.20.3417.1 in source) |
| **Linked F&O instance** | Environment must be F&O-linked; virtual entities resolve against it |
| **Publisher** | `ColumbusGlobal` / prefix `cog` must exist, or import will create it |
| **Standard Quality management** | Must be configured in F&O — test groups, tests, item sampling, quality associations |
| **Legal entities** | At least one with quality configuration. Source testing used `USMF` and `USPI` |

---

## 4. Connection references

*(none yet — added in Phase 2)*

Phase 2 will introduce `shared_commondataserviceforapps` and `shared_dynamicsax`.
Both must be rebound to target-environment connections after import.

---

## 5. Environment variables

*(none yet — added in Phase 2)*

Phase 2 will introduce the F&O base URL, sync cadence, cache retention and feature flags.

---

## 6. Known constraints carried from Phase 1

| # | Constraint |
|---|---|
| 1 | **Direct virtual-entity create of quality orders does not work.** Supplying any storage dimension makes the provider send the full set including `Owner`, which is inactive in USMF and rejected; omitting site fails with "Site is mandatory". Writes must go through Power Automate and `shared_dynamicsax`. |
| 2 | **Never set both `mserp_dataareaid` and `mserp_dataAreaId_id`** on the same write — "the same external field was defined by more than one logical field". |
| 3 | **The Web API returns enums as integers; FetchXML returns labels.** See `output/OPTION-SETS.md`. |
| 4 | **`RemoveSolutionComponent` is unusable via the Web API** — it declares a `SolutionComponent` parameter in CSDL but the platform handler demands `ComponentId`, and direct delete of `solutioncomponent` rows is blocked. To remove a component, use the maker portal, or drop and recreate the unmanaged solution. |
| 5 | Access tokens are revoked within ~15–20 minutes by Conditional Access. All tooling must re-mint on 401. |
