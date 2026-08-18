# Mobile App — Online Design

**QM-P2-009 · 2026-08-18 · design, nothing built**

Supersedes the offline assumptions in `MOBILE-SLICE-ANALYSIS.md` for the mobile app only. The
tablet app is unchanged and keeps its offline design.

---

## 1. Dropping offline removes most of the architecture, not just a feature

The offline requirement (D-02) is what created the cache-and-forward layer. Without it the mobile
app talks to F&O directly and **the entire middle tier disappears for this app**:

| Offline design | Online design |
|---|---|
| `cog_QualityOrder`, `cog_QualityTestLine`, `cog_TestOutcome` caches | read F&O virtual tables live |
| `cog_ResultSheet`, `cog_ResultEntry` drafts | none — edit the F&O row directly |
| `cog_Outbox` + payload JSON + correlation ids | none — `Patch()` and read `Errors()` |
| `cog_QM_SyncCache`, `cog_QM_SyncTestLines` | none |
| `cog_QM_DrainOutbox`, `cog_QM_DrainAttachment` | none |
| Queue screen, retry, duplicate detection | inline success/failure on the screen |
| Sync lag and stale-cache handling | always current |

**5 flows and 10 tables become 0 and 0** for the mobile app. The tablet app continues to use them
untouched.

---

## 2. It also deletes an entire class of bug

The worst defect in this project was QO 000219 sitting in the queue: the client submitted
`"TargetRecordId":""` because it held a pre-sync copy of the line. The fix needed a server-side
resolution step in the flow *and* a `Refresh()` on screen entry.

**Online, that bug cannot exist.** The gallery item *is* the F&O record, so submitting is:

```
Patch(LineResults, ThisItem, { 'Result value': ... })
```

There is no id to resolve, no cache to be stale, and no correlation to track.

---

## 3. Data sources — 5 F&O virtual tables, no `cog_` tables at all

All verified present and readable in `cus-con-sandbox`:

| Entity | Role |
|---|---|
| `mserp_inventqualityorderheaderentities` | order picker |
| `mserp_powerappinventqolineentities` | test lines **with tolerances and the option-test discriminator** |
| `mserp_inventqualityorderlineresultentities` | the result rows to write |
| `mserp_powerappsinventtestvariableoutcomeentities` | outcome choices for option tests |
| `mserp_powerappfilesavingentities` | photo attachments |

They join cleanly: `mserp_powerappinventqolineentities.mserp_qualityorderid` **is the quality
order number** (verified — `'000119'`, `'000121'`), matching
`mserp_inventqualityorderlineresultentities.mserp_qualityordernumber`, with `testid` +
`testsequence` identifying the line.

One entity now supplies everything the result sheet needs per line — `lowerlimit`, `upperlimit`,
`standardvalue`, `testunitid`, `testinstrumentid` **and `variableid`**. The option-test
discriminator that `docs/TEST-RESULT-TYPES.md` had to derive from a cache column comes straight
from F&O.

---

## 4. Measured, not assumed

| Check | Result |
|---|---|
| Quality order headers, all companies | **86** |
| `usmf` open orders, server-filtered | **1** |
| Line result rows, all | **157** |
| Filtered + sorted read latency | **~1.0 s** |

Delegation is a non-issue at this scale — everything is far below the 500-row default and the
2000-row maximum. **This is a pilot-scale observation, not a production guarantee:** if open
orders ever exceed 500, virtual-table delegation support becomes a real constraint and the order
picker would need a server-side filter that actually delegates. Worth re-checking against
production volumes before go-live.

---

## 5. What we give up, and how each is handled

| Lost with offline | Handling |
|---|---|
| Working in a dead spot | Accepted — this is the customer's decision |
| Idempotency via correlation id | Disable the submit button while the write is in flight; a direct `Patch` is a single round trip, so the exposure is one double-tap, not a stuck queue |
| Retry from a queue | `Errors()` after `Patch` surfaces F&O's own message immediately; the inspector retries by pressing submit again — better feedback than the queue gave |
| Audit trail of every attempt | The outbox was that trail. If the business wants submission history, that is now an explicit ask, not a free side effect |
| Tolerance of slow networks | Each screen hits F&O (~1 s per read observed). On poor cellular this will feel slower than the cached tablet app |

The 1 MiB attachment cap and F&O's ~15-minute attachment processing job are **unchanged** — those
are F&O-side and have nothing to do with offline.

---

## 6. Screens

Three, phone-first, all gallery-driven so they scroll natively:

1. **Order picker** — `Filter(QualityOrderHeaders, dataareaid = company, status = open)`, search by
   order or item.
2. **Test result entry** — gallery over `PowerAppInventQOLines` for the order. Per row, switch on
   `IsBlank(ThisItem.mserp_variableid)`:
   - blank -> numeric input, verdict from the tolerance bounds
   - populated -> outcome picker from `PowerAppsInventTestVariableOutcomes` filtered by variable
   Submit does `ForAll` over the edited rows, patching the matching result row.
3. **Photo capture** — `Camera`, size guard against the 1 MiB cap, single `Patch` to
   `PowerAppFileSavings` with the order, test id and sequence.

Option-type results are built in from the start, not retrofitted.

---

## 7. Effort — lower than the offline slice

| Work | Claude | Human |
|---|---:|---:|
| Create app in Studio, phone layout, add 5 data sources | – | 0.75 |
| Order picker | 2 | – |
| Test result entry, incl. option-type results | 5 | – |
| Photo capture | 3.5 | – |
| Publish + validation cycles | 2 | 0.5 |
| Device testing and UAT | – | 3–4 |
| **Total** | **12.5** | **4.25–5.25** |

Down from 17.5 Claude hours, because the payload-building, draft-writing and correlation
plumbing all vanish. **Two days.**

---

## 8. The tooling fix may no longer be needed

The two-apps-in-one-solution problem — `Export-Solution.ps1:38` and `Publish-CanvasApp.ps1:61`
both taking the *first* `.msapp` — only exists if both apps share a solution.

**The online mobile app shares nothing with the tablet app.** No tables, no flows, no connection
references. So it can live in **its own solution**, and then:

- both scripts keep working unchanged, because each solution holds exactly one canvas app
  (they are already parameterised by `-SolutionName`)
- the tablet app cannot be touched by a mobile publish, by construction rather than by a guard
- the two have independent version histories

**Recommendation: separate solution.** It removes the 2.5 h tooling change, removes the risk of a
mobile publish overwriting the parked app, and is cleaner ALM. If you would rather keep one
solution, the tooling fix goes back on the list.

---

## 9. The one thing to prove first

**Canvas `Patch()` against an F&O virtual table is unproven.** We have proven writes to these
entities two ways — the Dataverse Web API directly, and the Dataverse connector inside a flow —
and the canvas connector uses the same Web API underneath, so it should behave identically. It
has never actually been done from a canvas app in this environment.

Cheapest way to retire it, before any layout work: add
`mserp_inventqualityorderlineresultentities` as a data source, put one button on a blank screen
that patches a result value, and watch F&O recalculate the verdict. **Thirty minutes, and it
de-risks the whole design.**

If it fails, the fallback is the tablet app's pattern — write to a staging table and let a flow
push it — which costs back roughly 4 hours and one flow, still without the cache or the queue.

Second unknown, unchanged from before: **camera behaviour on a real device**, and whether typical
captures land under the 1 MiB cap.
