# NexaDrive UI — Performance Audit (current build)

> Fact-based account of the performance-relevant machinery in 1.1.0 and the
> measurable risks. Marked **[EST]** where a magnitude is inferred, not measured.

---

## 1. Image pipeline

### 1.1 Memory (`main.dart`)
- `PaintingBinding.instance.imageCache.maximumSizeBytes = 384 << 20` (384 MiB),
  `maximumSize = 400` entries. This is a deliberate lift so decoded thumbnails/full
  images stay hot across screens.

### 1.2 Photos grid
- Fetch `/api/photos` → list of all photos (server path list only).
- After first build, **first 40 thumbnails prefetched sequentially** (`for … await
  _loadThumb`): each hits `ThumbnailCache.readSync` first (disk), else
  `/api/files/thumbnail?max=512`; 415 → full-download fallback (HEIC/AVIF).
- Build-time resolution: thumbnails checked from in-memory `_thumbCache`
  (a `Map<String, Uint8List>`) then sync disk read — no await in build → no flicker
  when cached.
- Tile renders `Image.memory(bytes, fit: cover, gaplessPlayback: true)`.
- No `Image.memory` cacheWidth/cacheHeight set → each 512px JPEG decodes at 512px
  (`[EST]` ~1.3 MiB RGBA each in the 768×768? no — 512×512×4 ≈ 1 MiB), ~40 tiles ≈
  40-50 MiB before cache-pressure; with 384 MiB cap that's absorbed but the grid
  rebuilds on every setState (each `_loadThumb` completion triggers `setState` → whole
  grid rebuilds; first-40 loop = up to 40 discrete rebuilds `[EST]`).

### 1.3 Photo viewer
- Full originals downloaded on demand into an **in-memory map** (`_fullCache`), rpled
  by `setState` (whole page rebuild per image). Prefetches `current±1`.
- A 12 MP JPEG (~3-8 MB file → ~24-48 MB decoded RGBA) × 3 cached = significant but
  bounded memory; page cache is cleared on dispose. **No cacheWidth rescale** for
  viewer images, no downsampling to screen DPI → 12 MP decode per page switch (full
  original `Image.memory` inside `InteractiveViewer` maxScale 5 needs full res by
  design, but decode cost per swipe is ~100-200 ms `[EST]` on mid-range).
- Loading indicator: centered spinner while bytes absent; `Image.memory` decode also
  builds the frame (decode happens on UI thread by default; `Image.memory` uses the
  codec which runs on IO thread in engine — acceptable `[EST]`).

### 1.4 Sync reads at build
- `readSync` file IO on the UI thread in itemBuilder — 40 tiles, each possibly a disk
  readSync per rebuild. Synchronous disk reads per frame can jank on storage-backed
  decode (`[EST]` medium risk on first scroll).

### 1.5 Thumbnail cache eviction
- LRU-ish by "open() prunes oldest mtime beyond 512 entries + beyond 7 days"; key =
  md5(`serverUrl|path`) — safe multi-server, 40-byte keys.

---

## 2. Upload engine (UI-visible)

- `TransferQueue` chunks at **8 MiB**, resumable via `/api/uploads/chunk?
  offset&total` + poll of `/api/uploads/status`. Progress = transferred/size.
- `UploadProgressDialog`: enqueues each picked file then `showDialog`; polls the
  queue **every 700 ms** (`Timer.periodic`) + `onChanged` from process.
  - Per-row `LinearProgressIndicator` rebuilds on each poll; dialog is modal so
    rebuild cost is small; a large queue (50 files) = 50 rows re-layout / 700 ms.
  - Dialog is `width: 380` fixed with a `Flexible` ListView — long queues scroll.
- `_cancel` removes all non-completed uploadIds (server keeps orphaned sessions
  `[EST]`).
- `AppShell` queue timer: **every 30 s** `TransferQueue.process` if any item is not
  `completed` (whether queued/uploading) → background polling of an active upload even
  during photo viewing; debounced enough.
- `BackgroundTransferService`: Android-only periodic 15-min workmanager
  (`networkType connected`, `requiresBatteryNotLow`), so phone uploads continue after
  app death with battery awareness — but 15-min cadence means big file chunks advance
  slowly when app is backgrounded `[EST]`.

---

## 3. Network / request hygiene

- Every page re-fetches on mount/pull (no caching of list JSON except in-memory state).
- `SharedScreen` fires `shared()` + `shares()` in `Future.wait` (parallel).
- `HomeScreen` fires `storage()` + queue read in parallel.
- Thumbnail HTTP: `Cache-Control: private, max-age=86400` on thumbnails (server
  marks non-cacheable responses `no-store`); `Api` uses a fresh `http.Client()` per
  shell (not retried `[EST]`).
- Loop protection: `load()` in photos prefetch has an in-flight guard only via
  `_thumbCache.containsKey`; no duplicate-download coalescing beyond that map; grid
  scroll doesn't trigger new prefetches beyond the preloaded 40 → scrolling to photo
  60 shows placeholder until each opens (`[EST]` cold area).

---

## 4. Layout/list perf

- Lists are plain `ListView.builder`/`GridView.builder` (lazy) — good for
  multi-thousand item folders.
- **Whole-list rebuilds** on: each `setState` after loads; Photos grid rebuilds on every
  prefetch completion; Files grid/list rebuild trivially.
- File tiles hold no heavy decorations; `RefreshIndicator` wraps all reloadable lists
  (adds an overlay per list item build? no — RefreshIndicator is between scrollable
  and content, negligible).
- Selection mode toggling rebuilds the entire list each tap (setState with a set diff —
  fine for < 1000 rows `[EST]`).
- Sorting is in-memory O(n log n) on display (folders-first + compare), computed per
  build (`_sorted` getter called in build) — for 10k files this is a per-build cost on
  every setState `[EST]`; memoization is absent.

---

## 5. Timers & lifecycle

- 30s shell queue timer keeps a live transmutable timer in AppShell (cancelled on
  dispose). LifecycleObserver: on `resumed` → `_resumeQueue()` + `_autoSync()`.
- `_checkServerAndQueue` on first post-frame: 1 status call + queue process.
- `_autoSync` is guarded by `_syncRunning` flag and desktop-only; conflict>0/errors>0
  → snackbar toast.

---

## 6. Measured/tested ground truth

- `flutter analyze` clean; `flutter test` 17 passed (widget + unit).
- Integration suite runs against the live Tailscale server at 7 sizes; `upload_test`
  pushes 20 MB through the 8 MiB chunker (SHA-256 byte-identical round-trip) — the
  chunk path is exercised and correct.
- Server thumbnail endpoint (2026-09-11 addition) bounded: in-memory 1024-entry /
  10-min TTL, JPEG q84, max dimension from `max` param — verified on scratch 8081.
- `capture_test.dart` renders RepaintBoundary PNGs (DPR 1) for the docs — no jank
  measurement harness exists (no binding.frameTimings analytics in repo).

---

## 7. Risk register (prioritized)

| # | Risk | Evidence | Severity |
|---|------|----------|----------|
| 1 | Photo grid = N discrete full-grid rebuilds when warming first 40 thumbs | `setState` inside `_loadThumb` per image | Medium (long lists) |
| 2 | Viewer full-original decode on UI-default codec at 12MP, no cacheWidth | `Image.memory(bytes…)` un-dimensioned | Medium |
| 3 | sync `readSync` file IO during itemBuilder | `thumbnail_cache.dart` readSync in `photos_screen` | Low-Med |
| 4 | per-build `_sorted` O(n log n) on Files when list large | `_sorted` getter in build | Low |
| 5 | 30s timer calls process() on any non-completed item even mid-upload | `app_shell._resumeQueue` | Low |
| 6 | Background upload cadence 15 min → slow big-file progress in background | `background_transfer_service` | Low (by design) |
| 7 | Sheet/dialog frames use `BackdropFilter` (photo bar) — GPU cost on large images | photo_viewer 12/12 blur | Low |

---

## 8. No-regression guardrails for a redesign

- Keep `imageCache` lift; never drop below ~256 MiB without re-measuring Photos.
- Preserve 8 MiB chunk resume, `transfer_queue_v2` key, and the 700 ms dialog poll
  contract (UI contract in `upload_test`).
- Keep `ThumbnailCache` key scheme (`md5(server|path)`) — changing it orphans users'
  cached thumbs; prune 7-day/512 stays.
- If Photos grid tiles get `cacheWidth: 512`-style hints, keep `max:512` server param
  (don't bump bandwidth).
- Any new list must be a `ListView.builder`; any new fetch loop must coalesce; any new
  animation must source durations from `AppMotion` (single motion source).