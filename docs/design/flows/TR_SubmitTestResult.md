# Flow: `TR_SubmitTestResult`

Records outcomes for a quality order's test lines and (optionally) attaches an image.
**Instant cloud flow**, **Power Apps (V2)** trigger.

> ✅ **Confirmed against live metadata.** The app **reads** lines from
> `InventQualityOrderLinesPowerApp` (key `dataAreaId,QualityOrderNumber,QualityOrderSequenceNumber`)
> and this flow **writes** to `QualityOrderLineResults` (key
> `dataAreaId,QualityOrderNumber,QualityOrderSequenceNumber,QualityTestId,ResultLineNumber`).
> `TestResult` is the `InventTestOutcomeStatus` enum (`Pass`/`Fail`). See `docs/FnO-Data-Model.md` §C.

## Trigger inputs (exact order)

| # | Name | Type | Example |
|---|------|------|---------|
| 1 | `company` | Text | `usmf` |
| 2 | `qualityOrderNumber` | Text | `QO-000123` |
| 3 | `linesJson` | Text | `[{"seq":1,"testId":"PH","outcome":"Pass","resultQuantity":7.2},...]` |
| 4 | `attachName` | Text | `sample.jpg` (or blank) |
| 5 | `attachB64` | Text | `data:image/jpeg;base64,....` (or blank) |

> The app must carry **`seq`** (`QualityOrderSequenceNumber`) per line from the read — it's part of
> the result key. The `scrTR_Grid` line collection includes it.

## Actions

### 1. Parse `linesJson`
**Parse JSON** — Content = `triggerBody()['text_2']`. Schema = array of
`{ seq (integer), testId (string), outcome (string), resultQuantity (number) }`.

### 2. `Init vFailures` = 0
**Initialize variable** (Integer) — counts lines that failed to write.

### 3. Scope: `Save lines`
**Apply to each** over `body('Parse_linesJson')`:
- **Create/Update a row** (`PostItem`/`PatchItem`) — or `InvokeHttp` — on `QualityOrderLineResults`:
  ```
  table: QualityOrderLineResults
  cross-company: true
  item: {
    "dataAreaId": "@{triggerBody()['text']}",
    "QualityOrderNumber": "@{triggerBody()['text_1']}",
    "QualityOrderSequenceNumber": @{items('Apply_to_each')?['seq']},
    "QualityTestId": "@{items('Apply_to_each')?['testId']}",
    "ResultLineNumber": 1,
    "TestResult": "@{items('Apply_to_each')?['outcome']}",          // 'Pass' | 'Fail'
    "ResultInventoryQuantity": @{items('Apply_to_each')?['resultQuantity']}
  }
  ```
- **Configure run after** on a small `Increment vFailures` action so one bad line doesn't abort
  the loop but is counted.

> After writing results you typically **validate** the quality order so F&O rolls up the outcome.
> If your process requires it, add a PATCH to `QualityOrderHeaders` / the validation path once all
> lines are written. Confirm the intended lifecycle with a live order.

### 4. Optional attachment
**Condition**: `attachName` is not blank →
- Split the data URL: `last(split(triggerBody()['text_4'], 'base64,'))` gives the raw base64.
- Post to your attachment target (see `docs/FnO-Data-Model.md` §F): `DocuRefEntity` create, or a
  Dataverse "Add a row" with a file column, referencing `qualityOrderNumber`.

### 5. Respond
- If `vFailures = 0`: `ok=true`, `number = qualityOrderNumber`, `message = "Test results submitted"`.
- Else: `ok=false`, `number = qualityOrderNumber`,
  `message = concat(vFailures, ' test line(s) failed to save')`.
- Catch (Scope failed): `ok=false`, `message = 'Submit failed. Check run history.'`.

## Test
Load a quality order in the app, set one Pass and one Fail, add a photo, Save & Submit. Verify the
outcomes and attachment in F&O against the quality order.
