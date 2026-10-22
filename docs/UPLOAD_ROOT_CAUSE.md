# Upload reliability — root cause report

Investigated on 2026-10-22 against the current tree (`dbec7eb`) with a live
server (`127.0.0.1:8099`, isolated database + storage root) and the Flutter
client's own `TransferQueue` code path.

The failure is **not** one bug. There are two independent clusters: a
client-side scalability defect that produces the reported symptom (screen
exits / Upload button dies), and three server-side defects that corrupt data
and fail bulk uploads outright.

---

## A. Client (Flutter) — the primary cause of the reported symptom

### A1 — The queue persists to `SharedPreferences` with a full-list read **and**
### full-list write per operation → O(n²) in CPU *and* disk I/O

`TransferQueue.enqueueLocalPath` (`app/lib/services/transfer_queue.dart:95`)
does `await items()` (JSON-decode the entire list) and then `await _save(list)`
(JSON-encode the entire list + `SharedPreferences.setString`).
`UploadProgressDialog.show` (`app/lib/ui/widgets/upload_progress_dialog.dart:36`)
enqueues **one file at a time, before any UI is shown**.

Measured with the in-memory preferences mock (so a real device is strictly
worse — every `setString` is a platform-channel round trip plus a rewrite of
the preferences file):

| files | enqueue time |
|-------|--------------|
| 100   | 138 ms       |
| 250   | 413 ms       |
| 500   | 1 476 ms     |
| 1 000 | **5 879 ms** |

4× the files ⇒ 42× the time. At 1 000 files the payload is a ~300 KB JSON
blob rewritten 1 000 times, with no dialog on screen and no progress
indication. On Android this is a textbook ANR: the platform shows "app isn't
responding" and then kills the process. **This is the "app navigates back or
exits the upload screen".**

### A2 — The same full-list rewrite happens on every chunk and every poll

`_uploadItem` calls `persist()` after each 8 MB chunk, and `persist` saves the
whole list (`transfer_queue.dart:284`). `UploadProgressDialog._refresh` polls
`SharedPreferences` every 700 ms and calls `setState`, rebuilding the whole
dialog.

### A3 — Uploads run strictly one file at a time

`TransferQueue.process()` (`transfer_queue.dart:267`) is a sequential `for`
loop. There is no concurrency at all.

### A4 — `TransferQueue` is instantiated per call site, so its guards do not work

`UploadProgressDialog.show`, `TransfersScreen`, `HomeScreen`, `AppShell` and
`BackgroundTransferService` each construct their own `TransferQueue`. The
`_processing` re-entrancy flag (`transfer_queue.dart:268`) and the `_paused`
set (`transfer_queue.dart:70`) are **per instance**:

* Tapping Upload twice creates two independent processors over the same
  persisted list → duplicate jobs for the same files.
* The Android `workmanager` background task runs in a **separate process**
  against the same preferences file → lost updates (last writer wins over the
  whole list).
* Pause state is dropped whenever the instance is dropped.

### A5 — `process()` drives the entire persisted queue, not the jobs the dialog owns

`process()` iterates every item in the shared list (`transfer_queue.dart:271`),
so opening the upload dialog for one file re-drives every unfinished job from
previous sessions — combined with A4 that produces duplicate submissions.

### A6 — `TransferItem.copyWith` cannot distinguish "no change" from "clear"

`copyWith({String? status, String? error, ...})` always assigns
`error: error` (`transfer_queue.dart:59`), so `copyWith(status: 'uploading')`
silently discards a recorded failure reason.

### A7 — Cancel is O(n²) *and* destructive

`UploadProgressDialog._cancel` (`upload_progress_dialog.dart:151`) calls
`queue.remove(id)` per item, and each `remove` is a full list read + write.
At 1 000 items the Cancel button appears to hang for minutes.

### A8 — Back-navigation while uploading deletes the whole batch

`PopScope(canPop: !isActive)` with
`onPopInvokedWithResult: (didPop, _) { if (!didPop) _cancel(); }`
(`upload_progress_dialog.dart:211`) means the system back gesture runs the
destructive `_cancel()` path (A7) instead of leaving the jobs paused.

### A9 — An empty job list counts as "finished"

`_isDone([])` is vacuously `true` (`upload_progress_dialog.dart:126`), so if
the shared list was cleared (or the ids no longer match) the dialog
immediately shows "Upload finished with issues" and can be dismissed — the
upload screen "exits" on its own.

### A10 — A request timeout does not cancel the request

`Api._TimedClient.send` (`app/lib/services/api.dart:30`) applies
`.timeout(...)` to the *future* only. When it fires, the socket and the file
stream keep running: the server keeps receiving the chunk and advances
`bytes_received`, while the client believes the chunk failed. The next
attempt then gets `409 Resume from offset N`, and `TransferQueue.isTransient`
(`transfer_queue.dart:164`) does **not** classify 409 as transient — so a
transient network blip permanently fails the file.

### A11 — No batch selection and no folder selection at all

`FilePicker.pickFiles()` is called without `allowMultiple: true`
(`app/lib/ui/screens/files/files_screen.dart:208`), so the UI cannot even
select more than one file, and there is no directory-picking path.

---

## B. Server (Rust) — separate, independently reproducible defects

### B1 — **Silent data corruption** when an upload is resumed after a server
### restart (critical)

`cleanup_stale_uploads` deletes every staging file at startup
(`server/src/handlers/upload.rs:414`) and `recover_upload_jobs` marks the job
`failed` (`upload.rs:378`), but `upload_chunk` still accepts a chunk whose
offset equals the recorded `bytes_received` (`upload.rs:276`). The handler
then finds no staging file, creates a fresh one and seeks to the offset
(`upload.rs:288`) — producing a hole of NUL bytes.

Verified end to end: a 192 608-byte file uploaded in three 64 KiB chunks
across a server restart was stored with **65 536 NUL bytes** where the first
chunk should be. The server answered `status: completed` with a checksum of
the *corrupt* data, so the client had no way to detect it.

### B2 — The quota check walks the entire storage tree once per upload → O(n²),
### and it fails outright under concurrency

`ensure_quota` → `tree_stats` (`server/src/handlers/storage.rs:134`) walks the
user's whole tree on every new upload job when a quota is configured. The
walk is not resilient to the tree changing underneath it (`read_dir` /
`entry.metadata()` → `ENOENT`), and that error is mapped to a generic 500.

Verified: 1 000 uploads with a quota set → **8 failed with HTTP 500**; the
identical run with the quota cleared → **1 000/1 000 succeeded**. Timing with
3 000 files already stored: **27 ms per upload** (a full tree walk each).

### B3 — Staging files are visible to the user

`list_files` (`server/src/handlers/files.rs:34`) and `tree_stats` do not filter
the `*nexadrive-upload-*` staging artifacts, so a partial upload shows up in
the file list as `photo.nexadrive-upload-<uuid>` and counts against the quota.

### B4 — Finalisation is not atomic

`if absolute.exists() { fs::remove_file(&absolute) }` then `fs::rename`
(`upload.rs:324`) leaves a window where the destination does not exist; a
crash in that window loses the previous file. `rename` already replaces
atomically on POSIX.

### B5 — No server-side concurrency limit

Nothing bounds simultaneous upload streams; each holds a task, a file handle
and an `fsync` per chunk.

### B6 — `upload_jobs` is never pruned

The table grows without bound.

### B7 — 500 responses carried no detail and were not logged

`AppError::Database`/`Io` both collapsed into a generic "Internal server
error" with nothing written to the log (`server/src/error.rs`), which is why
B2 was undiagnosable from the server side. (Fixed as part of this work: the
underlying cause is now logged.)

---

## Summary of the failure point

The reported symptom ("multiple files → app leaves the upload screen → Upload
button stops responding") is **A1 + A9 + A4** on the client: an O(n²) queue
that never shows UI while it fills, a vacuous "finished" test, and per-call-site
guards that let two processors fight over one list. The 500s that a bulk
upload hits are **B2** on the server. The silent corruption users would
eventually report from resumed uploads is **B1**.

## What the fix must do

1. Replace the O(n²) preferences-backed queue with a persistent, file-backed
   upload manager that has a single owner, a bounded worker pool and throttled
   progress notifications.
2. Give the server a staging-file integrity check so a chunk can never be
   written past the end of the staging file, make staging survive a restart,
   and stop the per-upload full-tree quota walk.
3. Add a resumable protocol that is actually resumable, plus safe retry
   semantics.
4. Add directory selection with hierarchy preservation, per platform.
