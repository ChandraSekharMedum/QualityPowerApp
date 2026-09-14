# Quality Management — Power Apps Canvas App (D365 F&O)

A **Power Apps Canvas app** (phone/tablet) that lets shop-floor and quality staff run the
Quality Management process against **Dynamics 365 Finance & Operations (F&O)**: create quality
orders, enter test results, raise non-conformances (NC), and change batch disposition codes.
The app **reads reference data from F&O and writes transactions back to F&O**.

> Rebuilt from `Quality Management App-User Manual-V3.docx`. The manual's screenshots are used
> only as a functional reference — the UI here is a clean, modern redesign (see
> `canvas-app/app/theme.fx`).

## What the app does (from the manual)

| # | Home tile | Purpose | Writes to F&O |
|---|-----------|---------|---------------|
| 1 | **Quality Order** | Create a quality order for 7 sources: Sales, Purchase, Inventory, Production, Route Operation, Co‑Product Production, Quarantine. | ✅ creates quality order |
| 2 | **Enter Test Results** | View a quality order's test lines and record pass/fail outcomes + attachment. | ✅ updates test results / validates order |
| 3 | **Create NC** | Raise a non‑conformance for 6 sources: Internal, Customer, Vendor, Service, Production, Co‑product. | ✅ creates NC order |
| 4 | **Manage Batch Disposition** | Scan item + batch barcodes and change the batch disposition code. | ✅ updates batch disposition |

## Architecture (one line)

**Canvas App (UI + barcode) → Power Automate flows → D365 F&O OData (`/data`, `cross-company=true`).**

Reads (dropdown lookups) and writes (transactions) both go through Power Automate flows so the
app stays portable and the F&O auth/token handling lives in one place. See
`docs/Architecture.md` for the full rationale and the direct‑connector alternative.

```
┌────────────────────┐   .Run(args)    ┌─────────────────────┐   OData /data   ┌───────────────┐
│  Canvas app        │ ──────────────► │  Power Automate      │ ──────────────► │  D365 F&O     │
│  (screens, barcode)│ ◄────────────── │  flows (per action)  │ ◄────────────── │  entities +   │
│                    │   JSON result   │                      │   201 / rows    │  actions      │
└────────────────────┘                 └─────────────────────┘                 └───────────────┘
```

## Repository layout

| Path | What it is |
|------|-----------|
| `docs/Architecture.md` | Components, data flow, connection decision, security. |
| `docs/FnO-Data-Model.md` | **The F&O contract** — every OData entity, key fields, actions, and gotchas the app depends on. Read this before building flows. |
| `docs/Screen-Flow.md` | Navigation map + full screen inventory. |
| `docs/Build-Guide.md` | Step‑by‑step build order (F&O prep → flows → app → test → publish). |
| `canvas-app/app/theme.fx` | Design tokens (colors, spacing, type) used by every screen. |
| `canvas-app/app/App.OnStart.fx` | App startup: collections, globals, cached lookups. |
| `canvas-app/app/components.md` | Reusable components (app header, bottom nav, lookup combo). |
| `canvas-app/screens/*.md` | One spec file per functional area — controls table + copy‑paste Power Fx. |
| `canvas-app/controls.md` | Naming conventions + control inventory. |
| `flows/*.md` | One Power Automate flow definition per write action + shared lookup flows. |
| `solution/pac-commands.md` | Package app + flows into a Dataverse solution for source control / ALM. |
| `deploy/checklist.md` | End‑to‑end execution checklist. |

## Build order (short version)

1. **F&O prep** — confirm/enable the OData entities + actions in `docs/FnO-Data-Model.md`; note the environment URL and legal‑entity (`dataAreaId`) codes.
2. **Connection** — create the F&O connection (connector or HTTP‑with‑Entra‑ID; see Architecture).
3. **Flows** — build the flows in `flows/` (lookups first, then the 4 write flows).
4. **App** — build screens from `canvas-app/screens/`, wire the flows, paste the Power Fx.
5. **Test & publish** — `deploy/checklist.md`.

## Prerequisites

- Power Apps + Power Automate with a **premium** plan (the F&O / Dataverse and HTTP‑with‑Entra‑ID
  connectors are premium).
- A D365 F&O environment where you have a mapped system user with read/write on the quality
  entities, and the environment's `.operations.dynamics.com` base URL.
- Power Apps mobile app on devices that will scan barcodes (barcode control is **not** supported
  in a web browser — noted in the manual).
