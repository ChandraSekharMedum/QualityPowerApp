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

`mserp_formname` caps at **20 characters**. `InventQualityOrder` is 18 and is accepted.

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

## 3. F&O consumes staged rows on a timer — about 15 minutes

This is the finding most likely to generate a support call, so it is worth stating plainly.

A probe row was created and polled every 30 seconds:

```
  still present at 2, 4, 6, 8, 10, 12 min
  CONSUMED after about 13.5 minutes (404)
```

`POWERAPPFILESAVINGENTITY` is a **staging** entity. F&O runs a periodic job that picks up staged
files, turns them into document attachments, and deletes the staging row. Consequences:

- **`ACCEPTED` in the app means F&O took the file, not that it is visible in F&O yet.** The
  screen says `ACCEPTED`, not `ATTACHED`, and tells the inspector to allow about 15 minutes.
- **The staging entity is not a record of what is attached.** Query it and you see only what has
  not been processed yet. That is why `cog_Attachment` keeps the app's own record, and why the
  "Photos for this order" list reads from Dataverse rather than F&O.

An earlier read of the staging entity returned zero rows while rows demonstrably existed, then
returned them correctly minutes later. Treat reads of this entity as eventually consistent.

---

## 4. Still unverified — needs one human check

**Whether F&O renders these as document attachments on the quality order.** There is no
`DocuRefEntity`, `DocuValueEntity` or `DocumentAttachmentEntity` in the catalogue — all four
candidate names 404 — so this cannot be confirmed over OData by any means available.

The evidence is strong but indirect: the write is accepted, the payload persists, and the row is
consumed by an F&O job on a schedule, which is precisely what a staging entity does when it is
working.

**Someone needs to open quality order `000121` in the F&O client and look at Attachments once.**
Until that happens, treat the feature as proven up to F&O's door and unproven inside it.

---

## 5. How it is wired

```
Camera capture
  -> JSON(photo, JSONFormat.IncludeBinaryData) gives "data:image/jpeg;base64,XXXX"
  -> strip to the base64
  -> cog_Attachment row  +  cog_Outbox row (operationtype 3)
  -> cog_QM_DrainAttachment
  -> POWERAPPFILESAVINGENTITY
  -> F&O periodic job  ->  document attachment
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
