# Moving from Tablet to Phone — Impact and Effort

**QM-P2-007 · 2026-08-18 · analysis only, nothing changed**

---

## 1. The short answer

**Smaller than it sounds. The back end does not move at all, and 4 of the 6 screens are already
close to phone-ready.** The work concentrates in two screens built after the layout got wide.

| | |
|---|---|
| Back end change | **None** |
| Screens needing a full re-layout | **2 of 6** |
| Screens needing light adjustment | **4 of 6** |
| Estimated build | **20–28 h** with Claude, plus 6–10 h of human testing and sign-off |

---

## 2. What does not change

This is the majority of the system by both value and risk, and a form-factor change does not
touch any of it:

- **10 Dataverse tables** — quality orders, test lines, outcomes, result sheets, result entries,
  outbox, problem types, accounts, items, attachments
- **5 Power Automate flows** — `SyncCache`, `SyncTestLines`, `DrainOutbox`,
  `DrainNonConformance`, `DrainAttachment`
- **The whole F&O integration** — every entity, every field mapping, the 1 MiB attachment cap,
  the number-sequence behaviour, the verdict recalculation
- **The offline design** — outbox, correlation-id idempotency, draft tables, retry
- **The publish pipeline and its guards**

Only the presentation layer moves. That matters for the estimate: the parts that took the longest
to get right and carry the most risk are untouched.

---

## 3. Where the app is today, and what a phone actually does to it

```
DocumentLayoutWidth        1366
DocumentLayoutHeight       768
DocumentLayoutOrientation  landscape
DocumentLayoutScaleToFit   True
DocumentLayoutLockOrientation  False
```

Because `ScaleToFit` is on and orientation is not locked, **the app already runs on a phone
today — it just scales the 1366-wide canvas down to roughly 640**. That is a factor of about
0.47, so a 9pt label renders near 4pt. It technically works and is unusable for data entry. Worth
knowing before anyone demos it on a phone by accident.

A phone layout is 640 x 1136 portrait: **half the width, but 48% more height**. So the fix is
mostly "unstack horizontally, restack vertically", and there is room to do it.

---

## 4. Measured exposure, screen by screen

Counted from the current source — controls, absolute coordinates, and positions that fall outside
a 640px-wide phone:

| Screen | Controls | Abs X/Y | Beyond 640 | Galleries | 2nd column | Verdict |
|---|---:|---:|---:|---:|---:|---|
| **QMCreateNC** | 55 | 110 | **40** | 5 | 13 | **Full re-layout** |
| **QMAttachments** | 31 | 62 | **25** | 2 | 9 | **Full re-layout** |
| QMResultSheet | 15 | 25 | 0 | 1 | 0 | Row template only |
| QMOrderList | 14 | 23 | 0 | 1 | 0 | Light |
| QMQueue | 12 | 19 | 0 | 1 | 0 | Light |
| QMHome | 8 | 13 | 0 | 0 | 0 | Light |
| **Total** | **135** | **252** | **65** | **10** | **22** | |

**All 65 out-of-bounds positions sit in two screens.** The four earlier screens were built
single-column with `Parent.Width`-relative widths (`Parent.Width - 32`, `(Parent.Width - 44) / 2`,
`Parent.TemplateWidth - 130`), so they reflow on their own. That was not foresight about phones —
it happened to be the cleaner way to write them — but it pays off here.

`QMCreateNC` and `QMAttachments` were built two-column at x=700 because the landscape canvas
invited it. Those columns have to become vertical sections.

---

## 5. The one real technical unknown

**Canvas screens do not scroll.** Today every screen fits inside 768px of height by design. On a
phone, `QMCreateNC` has seven sections that will not fit in 1136px stacked, so it needs one of:

1. **A scrollable screen** — introduces a container control this app has never used. Given
   PA2108 has bitten us twice on control templates, budget a publish cycle to prove the template
   name before building on it.
2. **A step-by-step wizard** — type → company → source → item → problem type → review, one step
   per view with next/back. More work, better on a phone, and it suits a gloved inspector.
3. **A gallery-driven form** — reuses a template we know works, but awkward for mixed inputs.

**Recommendation: the wizard for `QMCreateNC`, a scrollable screen for `QMAttachments`.** The NC
form is the only screen with enough fields to justify a wizard, and stepping through it is a
better phone experience than a long scroll anyway.

---

## 6. What gets *better* on a phone

Not everything is cost:

- **Camera capture.** `QMAttachments` was built around the device camera. A phone is the right
  device for it; on a tablet it is awkward and on a desktop it is close to useless.
- **Offline.** The whole outbox design exists because inspectors work away from a desk. A phone
  in a pocket is the form factor that design was for.
- **The single-column screens get simpler**, not more complex — the result sheet row is currently
  spread across a wide row with a lot of dead space in the middle.

---

## 7. Effort

Assumes phone-only (option A in §8). Claude hours are build time; human hours are the steps only
a person can do.

| Work | Claude | Human |
|---|---:|---:|
| App display settings change (Studio) | – | 0.5 |
| QMHome | 1 | – |
| QMOrderList | 1.5 | – |
| QMQueue | 1.5 | – |
| QMResultSheet — row template restack | 3 | – |
| **QMCreateNC — rebuild as a wizard** | 8 | – |
| **QMAttachments — rebuild single column** | 5 | – |
| Scroll/wizard container spike (prove the template) | 2 | – |
| Publish + Studio validation cycles | 2 | 1 |
| Device testing — camera, offline, gloves, sunlight | – | 4 |
| UAT and sign-off | – | 2–4 |
| **Total** | **24** | **7.5–9.5** |

Range **20–28 Claude hours** depending on how much the wizard flow is reworked with the SMEs.

**Where human intervention is unavoidable:** the display-settings change in Studio, adding any new
data source, validating Power Fx in Studio (`pac canvas validate` is retired), and all real-device
testing. Nothing else needs a person.

---

## 8. Three ways to do it

| Option | Effort | Trade-off |
|---|---:|---|
| **A. Phone only** — re-layout in place, retire the tablet layout | **24 h** | Cheapest and cleanest. If anyone still wants a tablet, it scales *up* acceptably (unlike down) |
| **B. Responsive, one app for both** — disable ScaleToFit, layout containers, `Parent.Width` breakpoints throughout | **40–50 h** | Serves both properly and future-proofs desktop. Rewrites all 6 screens, including the 4 that would otherwise be nearly free, and containers are new ground for this app |
| **C. Separate phone app** sharing the same tables and flows | **30 h** | Fastest to a good phone experience without touching the tablet app. Two apps to maintain forever — every future change done twice. Not recommended |

**Recommendation: A.** The customer asked for phone. A phone layout scaled up on a tablet is
acceptable; the reverse is what we have now and is not. Option B is the right call only if a
desktop or tablet audience is genuinely committed to, not merely possible.

---

## 9. Timing

The best moment to do this is **now, before the option-test fix and the quality-order screen**.
Both of those add controls; adding them to the wide layout and then re-laying them out is paying
twice. The option-test change alters the result sheet row template, which is exactly one of the
things a phone layout rewrites.

Sequencing suggestion:

1. Form-factor change (this analysis)
2. Option-test results fix — into the new row template, not the old one
3. Quality order creation screen — built phone-first from the start

---

## 10. What this analysis does not cover

- **Whether the customer means "phone only" or "phone as well as tablet".** That single answer
  moves the estimate from 24 h to 40–50 h. It should be asked before anything starts.
- Barcode scanning, which a phone makes plausible and which the manual may assume.
- Whether inspectors wear gloves, which changes minimum touch-target sizing and could add
  rework late if discovered during UAT.
