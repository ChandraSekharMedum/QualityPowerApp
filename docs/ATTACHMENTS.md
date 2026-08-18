# Photo Attachments on Test Results

**QM-P2-004 · 2026-08-17 · `cus-con-sandbox`**

Everything below was probed against the live environment, not inferred. Where something is
still unverified it says so.

---

## 1. It works, and against test result lines specifically

Phase 1 proved `POWERAPPFILESAVINGENTITY` accepts a write against a **non-conformance**. It had
never been tried against a **quality order test result**, which is what this feature needs. That
was the first thing probed, and it works:

```
POST mserp_powerappfilesavingentities
  mserp_tablerefid          = 000121          (the quality order)
  mserp_displayordernumber  = 000121
  mserp_testid              = ' Coil impedance'
  mserp_testsequence        = 10
  mserp_linenum             = 1
  mserp_filename            = probe.png
  mserp_formname            = InventQualityOrder
  mserp_imagevarchar        = <base64>
  mserp_dataareaid          = usmf
-> 201, read back with every field intact including the payload
```

`mserp_formname` caps at **20 characters**. `InventQualityOrder` is 18 and is accepted — but
"accepted" turned out to mean only that the row was stored. **It must be `Quality`** for the file
to actually attach; see §2a. Reading the 20-character cap as the only constraint on this field
cost a full round of testing.

---

## 2. The size cap is exact, and it is the binding constraint

| Base64 length | Result |
|---|---|
| 65,536 | accepted, intact |
| 262,144 | accepted, intact |
| **1,048,576** | **accepted, intact** |
| 4,194,304 | **rejected** — `The length of the 'mserp_imagevarchar' attribute ... exceeded the maximum allowed length` |

So the ceiling is **1 MiB of base64, about 786 KB of image**.

Dataverse memo columns cap at exactly the same 1,048,576 characters, so `cog_Attachment.cog_Base64`
is sized to match and the two limits can never disagree.

**The screen enforces this before queuing.** An oversized photo is refused at capture with the
measured size shown, rather than being accepted and then rejected by F&O minutes later when the
inspector has moved on. A device camera photo typically lands well inside the limit; the guard is
for the exception, not the rule.

---

## 2a. PROVEN 2026-08-18 — what F&O actually requires

Four staging rows created together, identical but for the fields under test, then checked by eye
in the F&O client on QO 000219:

| | `FormName` | `TableRefId` | Test line | Consumed | **Attached in F&O** |
|---|---|---|---|---|---|
| A | `Quality` | `0000` | yes | seconds | **YES** |
| B | `Quality` | `000219` | yes | seconds | **YES** |
| C | `InventQualityOrder` | `0000` | yes | seconds | **NO** |
| D | `Quality` | `0000` | **no** | never | NO |

**Two independent requirements, and each was found the hard way:**

1. **The row must identify a test line** (`TestId` + `TestSequence` + `LineNum`). Without one F&O
   never picks the row up at all — D sat unprocessed indefinitely. There is no whole-order photo.
2. **`FormName` must be `Quality`.** C was consumed just like A and B, and produced no attachment.

`TableRefId` is irrelevant — `0000` and a real order number behave identically. Both apps send
`0000`.

### Consumption is a misleading signal in both directions

- A row disappearing does **not** mean the file was attached (C disappeared and attached nothing).
- A row lingering does **not** mean processing is pending (D was going nowhere).

Rows F&O can act on are processed in **seconds**. Anything slower means it is not going to happen.
This is the single most misread signal in this whole feature — see §3.

---

## 3. The "13.5 minute delay" was a misreading, twice

**Corrected twice.** This section first claimed F&O attaches photos on a ~15 minute job. That was
wrong and reached the app's on-screen text. It was then over-corrected to "attachment is
immediate" on a single report from a different environment, which was also wrong. §2a settles it
with a controlled probe: rows F&O can act on are processed in seconds, and rows it cannot are
never processed at all.

What was actually measured: a probe row was created and polled every 30 seconds.

```
  still present at 2, 4, 6, 8, 10, 12 min
  GONE after about 13.5 minutes (404)
```

The row disappearing is the **staging row being cleaned up**. That is a different event from the
attachment being created, and nothing in the measurement links the two. The write itself returns
in about a second.

**What is actually true** (§2a): a row F&O can act on is processed within seconds. A row it cannot
place — no test line — is never picked up, and the disappearance seen at ~13.5 minutes was
routine tidying of rows that were going nowhere.

Two things that remain true regardless:

- **The staging entity is not a record of what is attached.** Query it and you see only rows not
  yet cleaned up.
- Reads of it are eventually consistent — one read returned zero rows while rows demonstrably
  existed, then returned them correctly minutes later.

**Lesson worth keeping:** "the row vanished" answers *when the row vanished*, not *when the work
completed*. Do not put an inferred timing in front of a user as if it were measured.

---

## 4. CONFIRMED — F&O renders these as attachments

**2026-08-18.** `PROBE-A` and `PROBE-B` were both seen on QO 000219 in the F&O client. `PROBE-C`
was not. So the feature works end to end with the settings in §2a.

This could never be confirmed over OData: there is no `DocuRefEntity`, `DocuValueEntity` or
`DocumentAttachmentEntity` in the catalogue — all four candidate names 404. Every automated signal
available (write accepted, payload persisted, staging row consumed) was present for `PROBE-C` too,
and `PROBE-C` attached nothing. **A human looking at the record was the only way to tell the
difference**, and no amount of further probing would have substituted for it.

---

## 5. How it is wired

```
Camera capture
  -> JSON(photo, JSONFormat.IncludeBinaryData) gives "data:image/jpeg;base64,XXXX"
  -> strip to the base64
  -> cog_Attachment row  +  cog_Outbox row (operationtype 3)
  -> cog_QM_DrainAttachment
  -> POWERAPPFILESAVINGENTITY
  -> F&O creates the document attachment on insert
```

**Why base64 text rather than a Dataverse file or image column.** The F&O target takes base64
text. A file column would force the flow to download the binary and re-encode it — an extra
failure point for no gain. Text also survives offline cleanly, which file columns do not reliably
do, and D-02 requires capture to work offline.

**Why the outbox payload carries no row id.** The drain flow finds the attachment by correlation
id. That avoids reading a Dataverse primary key back out of `Patch()` in Power Fx, and the
correlation id is already on both rows because the idempotency design needs it there. The flow
terminates with `AttachmentMissing` if no row carries the correlation, rather than posting an
empty image.

**`cog_linenum` is always 0.** The cached test lines carry no F&O line number, so the result is
identified by order plus test id plus test sequence. If attachments need to bind to a specific
result line rather than a test, the line number has to come from somewhere — currently it does
not exist in the cache.

---

## 6. Scope note

This is **camera capture only**, which is what was asked for. Attaching an existing file from the
device is not built. The F&O column is `mserp_imagevarchar` and the entity is image-oriented, so
whether it accepts a PDF or a document is unprobed — do not assume it does.

---

## 7. End-to-end results

| Test | Path | Result |
|---|---|---|
| Direct write to F&O against a test line | OData | Created, read back intact |
| Through the outbox, payload with row id | app → flow → F&O | **Confirmed, 15s** |
| Through the outbox, correlation lookup | app → flow → F&O | **Confirmed, 15s** |

All probe records deleted afterwards, except those F&O had already consumed.
