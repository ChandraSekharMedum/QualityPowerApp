# Power Automate flows

The app never touches F&O directly — these flows do. All are **Instant cloud flows** with a
**Power Apps (V2)** trigger, returning the uniform envelope `{ ok, number, message }` (write
flows) or `{ items }` (lookup flows, where `items` is a JSON‑string array).

## Flow list

| Flow | File | Trigger inputs (order matters) | Returns |
|------|------|--------------------------------|---------|
| `QO_CreateQualityOrder` | `QO_CreateQualityOrder.md` | company, source, account, refNo, operation, item, refLot, testGroup, qty, dimsJson | `{ok,number,message}` |
| `TR_SubmitTestResult` | `TR_SubmitTestResult.md` | company, qualityOrderNumber, linesJson, attachName, attachB64 | `{ok,number,message}` |
| `NC_CreateNonConformance` | `NC_CreateNonConformance.md` | company, ncType, dateIso, problemType, account, refNo, refLot, item, dimsJson, description, attachName, attachB64 | `{ok,number,message}` |
| `BD_GetBatch` | `BD_UpdateBatchDisposition.md` | company, item, batch | `{ok,number(=currentCode),message}` |
| `BD_UpdateBatchDisposition` | `BD_UpdateBatchDisposition.md` | company, item, batch, newCode | `{ok,number,message}` |
| `Lookup_Customers` / `Lookup_Vendors` / `Lookup_Items` / `Lookup_TestGroups` / `Lookup_ProblemTypes` / `Lookup_DispositionCodes` / `Lookup_QOTestLines` / order lookups | `lookups/README.md` | company (+ optional search) | `{ items }` |

## Connection & fallback (read `docs/Architecture.md` §3 first)

Each flow's F&O call uses **one** of two connectors — decide once, use the same everywhere:

1. **Fin & Ops Apps (Dynamics 365)** — `shared_dynamicsax`. Preferred when healthy. Actions:
   `GetItems` (read), `PostItem` (create), `PatchItem` (update), `ExecuteAction` (bound action).
2. **HTTP with Microsoft Entra ID** — `shared_webcontents`. Fallback when the F&O connector's
   apihub route is broken (`BadGateway/NotFound`). At connection‑create time set **Resource URI =
   your F&O base URL**. Then every call is a raw `InvokeHttp` to `/data/...?cross-company=true`.

Both are **premium** connectors.

### Universal rules (apply in every flow)
- Append `?cross-company=true` to every request URL.
- Put `dataAreaId` (lowercase, e.g. `usmf`) in the **body** of writes.
- For HTTP‑with‑Entra‑ID, `request/body` must be a **string** (build with `concat()`), never an
  object — otherwise F&O's `AxODataEntityDeserializer` returns 400.
- Dates → full ISO (`2026-07-13T00:00:00Z`); numbers → numeric, not string; field names → exact
  camel case from `$metadata`.
- Wrap the F&O call in `Scope` + `Configure run after` → a `Compose` that builds the error
  envelope, so failures return `{ ok:false, message: <F&O error> }` instead of throwing.

## The standard "Respond" shape

Add **Respond to a PowerApp or flow** with three text outputs: `ok` ("true"/"false" — the app
reads it as text and compares, or use a boolean output), `number`, `message`. Keep names stable;
the app binds `gRes.ok`, `gRes.number`, `gRes.message`.

> Tip: the app treats `gRes.ok` as truthy. If you output text, compare `gRes.ok = "true"` in the
> app, or add a real boolean output named `ok`. The screen specs assume a boolean `ok`.
