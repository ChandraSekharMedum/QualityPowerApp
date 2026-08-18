# Test Results Are Not Always Numeric

**QM-P2-006 · 2026-08-18 · `cus-con-sandbox`**

---

## 1. This is a defect in what we shipped, not just a missing feature

F&O quality tests come in two kinds. Our result sheet only implements one of them.

Of the 12 cached test lines in `usmf`, **7 are option tests**:

| Quality order | Test | `cog_variableid` | Lower | Upper | Unit |
|---|---|---|---|---|---|
| 000121 | Coil impedance | **`Pass\Fail`** | 0 | 0 | Option |
| 000121 | Cone weight | *(blank)* | 9.9 | 10.2 | g |
| 000094 | Concentration | *(blank)* | 10.0 | 30.0 | pct |
| 000120 | Enclosure measuring | **`Dimensions`** | 0 | 0 | |
| 000219 | impedance measure | **`Impedance`** | 0 | 0 | |
| 000119 | impedance measure | **`Pass\Fail`** | 0 | 0 | |

The result sheet currently renders every line as a numeric text box. On an option line it shows
"No numeric range", and because the verdict formula falls through to `"PASS"` whenever the
tolerance bounds are not greater than each other, **any value typed into an option line is
reported as PASS**. That is worse than not supporting it.

---

## 2. The discriminator is already in our cache

`cog_QualityTestLine.cog_variableid`:

- **blank** -> numeric test. Real `cog_lowerlimit` / `cog_upperlimit` and a unit.
- **populated** -> option test. Limits are 0/0 and the value names an outcome variable
  (`Pass\Fail`, `Dimensions`, `Impedance`).

No schema change and no new sync is needed to tell them apart.

---

## 3. The outcomes are already cached too

`cog_TestOutcome` exists, is **already an app data source** (`Test Outcomes (cache)`), and is
already populated — 8 rows for `usmf`:

| `cog_variableid` | `cog_outcomeid` | `cog_impliedresult` |
|---|---|---|
| `Impedance` | Accepted | 200000001 (pass) |
| `Impedance` | Too low | 200000000 (fail) |
| `Impedance` | Too big | 200000000 (fail) |
| `Dimensions` | Accepted | 200000001 (pass) |
| `Dimensions` | To small / To big | 200000000 (fail) |
| `Pass\Fail` | Pass | 200000001 (pass) |
| `Pass\Fail` | Fail | 200000000 (fail) |

Source entity: `mserp_powerappsinventtestvariableoutcomeentities`
(`testgroupid`, `testid`, `variableoutcomeid`, `outcomestatus`, `outcomedescription`).

So the whole feature needs **no new tables, no new data sources and no Studio round trip**.

---

## 4. How the demo app does it

`TestResultScreen`, one gallery row per test line:

```
Label:    Text = If(IsBlank(lblTestResultValueOutcome.Text), "Result Enter", "Outcome")
Numeric:  txtResultEnter   Visible = IsBlank(lblTestResultValueOutcome.Text)
Option:   cmbOutcome       Visible = !IsBlank(lblTestResultValueOutcome.Text)
          Items = Filter(CollectVariableOutcome,
                         ThisItem.'Sequence number' = TestSequence && ThisItem.Test = TestId)
```

where `CollectVariableOutcome` is loaded once per order:

```
ClearCollect(CollectVariableOutcome,
    Search(PowerAppsInventTestVariableOutcomes, Last(QualityOrderHeaders).'Test group', TestGroupId))
```

Saving keeps **both** fields and lets F&O use whichever applies:

```
ResultValue:  If(IsBlank(outcome), Value(txtResultEnter.Text), 0),
OutcomeValue: If(IsBlank(lblcmbOutcomeValue.Text), lblTestResultValueOutcome.Text, lblcmbOutcomeValue.Text)
...
Patch(QualityOrderLineResults, {
    'Quality order': ..., 'Sequence number': ..., 'Line number': ..., Test: ...,
    'Result value': ResultValue,      <- numeric, 0 for option tests
    Outcome:        OutcomeValue,     <- outcome id, blank for numeric tests
    Company: dataAreaId })
```

Their discriminator is "does this line already carry an Outcome". **Ours should be
`cog_variableid`**, which is more direct and works before any result exists.

---

## 5. The target fields exist in our environment

`mserp_inventqualityorderlineresultentity`:

| Field | Type | Create | Update | Use |
|---|---|---|---|---|
| `mserp_resultvalue` | Decimal | True | True | numeric result |
| `mserp_qualitytestvariableoutcomeid` | String | True | **True** | **option result** |
| `mserp_resultlinenumber` | Decimal | True | False | line number |
| `mserp_qmsresultnote` | String | True | True | free-text note — we are not using this yet |
| `mserp_testresult` | Picklist | **False** | **False** | F&O computes the verdict, as we already knew |

`mserp_qmsresultnote` is worth noting separately: it is the only free-text field we have found
anywhere in the quality write path, and it is updatable.

---

## 6. What to change

1. **`QMResultSheet`** — per row, switch on `IsBlank(ThisItem.cog_variableid)`:
   - blank: the numeric input and tolerance verdict we have now
   - populated: a picker over `Filter('Test Outcomes (cache)', cog_variableid = ThisItem.cog_variableid, cog_company = varOrder.cog_company)`
   - verdict for option lines comes from the selected outcome's `cog_impliedresult`, not from
     comparing numbers
2. **`cog_ResultEntry`** — add `cog_OutcomeId` alongside `cog_enteredvalue`.
3. **Submit payload** — carry `OutcomeId` per line.
4. **`cog_QM_DrainOutbox`** — set `mserp_qualitytestvariableoutcomeid` when `OutcomeId` is
   present, `mserp_resultvalue` otherwise.

The client-side verdict stays advisory either way: F&O recalculates it.
