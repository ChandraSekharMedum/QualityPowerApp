# A New Phone App, Thin Slice: Test Results + Attachments

**QM-P2-008 · 2026-08-18 · analysis only, nothing changed**

Question: park the current app, build a new phone app in the same solution, starting with test
result entry and photo attachment against a test result. Is that quickly achievable?

---

## 1. Yes — and this is the best-shaped slice in the whole backlog

**Roughly 16–19 hours of build plus about 5 hours of human time. Call it two to three working
days.**

The reason it is quick is not optimism about the UI. It is that **this slice has no back end left
to build**. Both features are already proven end to end in production-shaped code:

| Feature | Back end state |
|---|---|
| Test result entry | `cog_ResultSheet`, `cog_ResultEntry`, `cog_Outbox`, `cog_QM_DrainOutbox` — proven, F&O recalculates the verdict |
| Attachment vs test result | `cog_Attachment`, `cog_QM_DrainAttachment` — **proven twice, confirmed in 15s each time** |
| Order + line cache | `cog_QualityOrder`, `cog_QualityTestLine`, `cog_QM_SyncCache`, `cog_QM_SyncTestLines` — populated and syncing |

**Nothing in the data layer or the flows changes.** The flows trigger on Dataverse rows, not on
the app, so a second app writing the same rows is invisible to them. No flow edits, no schema
edits, no new F&O work. The slice is purely screens.

---

## 2. Why this slice in particular dodges the hard problem

§5 of the form-factor analysis flagged the one real unknown: canvas screens do not scroll, so a
tall form needs a scroll container or a wizard, and new control templates have cost us two
PA2108 rounds.

**That problem barely applies here.** Both main screens are gallery-driven, and galleries scroll
natively:

- Order list — a gallery
- Test result entry — a gallery of test lines
- Attachment capture — the only stacked form, and camera + preview + name + button fits inside
  1136px of phone height in a single column with room to spare

So the slice can be built entirely from control templates this app already uses and that are
already proven in Studio: `Label`, `Rectangle`, `Gallery`, `Classic/Button`, `Classic/TextInput`,
`Classic/CheckBox`, `Camera`, `Image`. **No new templates, no spike.**

Measured exposure from the current screens: `QMOrderList` and `QMResultSheet` have **zero**
positions outside a 640px phone — they were built width-relative. Only `QMAttachments` (25) needs
genuine restacking, and it is 31 controls.

---

## 3. One concrete blocker in our own tooling

`Export-Solution.ps1:38` and `Publish-CanvasApp.ps1:61` both do:

```powershell
Get-ChildItem "...\CanvasApps" -Filter '*.msapp' | Select-Object -First 1
```

**With two canvas apps in the solution, both scripts silently pick whichever comes first** — so a
publish aimed at the phone app could overwrite the tablet app's payload, or vice versa. Given
this pipeline has already cost us one wiped data source, that is not a risk to leave in place.

Fix: parameterise both by app name and fail loudly if the named app is not found, plus a second
`canvas-src` folder per app. **2–3 hours, and it must be done first.**

The post-import data-source guard added earlier needs the same treatment — it currently compares
"the first app" before and after.

---

## 4. Human steps that cannot be automated

| Step | Who | Time |
|---|---|---|
| Create the new canvas app in Studio, phone layout, add to the solution | You | 0.25 h |
| Add data sources — **7 of them** (see below) | You | 0.5 h |
| Open in Studio to validate Power Fx after each publish | You | 0.5 h |
| Real-device testing — camera, permissions, offline, sunlight | You | 3 h |

Data sources the slice needs: `Quality Orders (cache)`, `Quality Test Lines (cache)`,
`Test Outcomes (cache)`, `Result Sheets (draft)`, `Result Entries (draft)`, `Outbox`,
`Attachments (draft)`.

**The data-source step is the one that has bitten us repeatedly.** Do it once, immediately after
creating the app, then let me export before I publish anything.

---

## 5. Effort

| Work | Claude | Human |
|---|---:|---:|
| Parameterise publish/export tooling by app name | 2.5 | – |
| Create app + add 7 data sources | – | 0.75 |
| Order picker screen (phone) | 2 | – |
| Test result entry screen (phone) | 4 | – |
| **Option-type results, built in from the start** | 3 | – |
| Attachment screen (phone, single column) | 4 | – |
| Publish + validation cycles | 2 | 0.5 |
| Device testing and UAT | – | 3–4 |
| **Total** | **17.5** | **4.25–5.25** |

Range **16–19 Claude hours**.

---

## 6. Build the option-test handling in now, not later

`docs/TEST-RESULT-TYPES.md` found that **7 of 12 cached test lines are option tests**, and that
the current result sheet reports PASS for anything typed into them. That is a live defect.

The fix rewrites the result-sheet row template — which is exactly what a phone layout rewrites.
Building the new screen numeric-only and then fixing it is paying for the same template twice.
Included above at 3 hours; skipping it saves 3 hours now and costs more later, plus it ships a
known-wrong verdict.

Everything it needs already exists: `cog_variableid` on the cached line is the discriminator, and
`cog_TestOutcome` is already populated with implied pass/fail.

---

## 7. What parking the old app does and does not cost

**Costs nothing operationally.** Both apps live in the same solution, share the same tables and
flows, and the parked app keeps working exactly as it does today. It stays available as the
fallback — the same instinct as keeping the earlier form-design version.

**The one ongoing cost:** while both exist, any table or flow change has to be considered against
both. In practice that is small, because the parked app is frozen — but it is not zero, and if
the phone app supersedes it entirely the tablet app should eventually be deleted rather than left
to rot.

---

## 8. What I would want answered before starting

1. **Phone only, or phone and tablet?** For *this slice* it barely matters — the answer is the
   same screens either way. It matters for what comes after.
2. **Does the phone app need the NC screen and quality order creation eventually,** or is it
   deliberately the inspector's "record results and photograph defects" app, with the fuller
   functions staying on tablet or in F&O? That changes whether the wizard question from the
   form-factor analysis ever has to be answered at all.

Neither blocks starting. The slice is the same work under either answer.

---

## 9. Honest risks

- **Camera behaviour on a real phone is untested.** The `Camera` control is in the published
  tablet app but has never been exercised on a device. Photo dimensions vary by device, and the
  1 MiB F&O cap is real — the size guard is built, but whether typical phone captures land under
  it is genuinely unknown until someone tries. This is the single biggest unknown in the slice.
- **The `Camera` control template itself is unproven in Studio.** It was published but the app has
  not been opened in Studio since. If it errors, that is one publish cycle to fix.
- **7 data sources is the most we have ever added at once.** Every previous round of this has cost
  a round trip.
