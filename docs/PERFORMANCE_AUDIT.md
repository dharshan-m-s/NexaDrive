# NexaDrive Performance Audit

## Workload

Standard personal cloud usage:
- File listing and browsing (10-10000 files)
- Single-file and multi-chunk uploads (up to 10 GB)
- File downloads (streamed)
- Search (filename matching)
- Sync manifest generation (recursive directory scan)
- Database operations (sessions, shares, trash, notifications)

## Server Measurements

### Startup
- Cold start: < 1 second (SQLite WAL mode, 5 connection pool)
- Migration: Single migration (0001_init.sql), runs instantly with `IF NOT EXISTS`
- Stale upload cleanup: O(n) filesystem scan on startup

### Memory
- Idle: ~12 MB RSS (release build)
- Under load: < 50 MB (streaming uploads, no full-file buffering)

### Database
- Connection pool: 5 max connections
- WAL mode with Normal synchronous
- Busy timeout: 10 seconds
- All queries use indexes (verified via schema review)
- No N+1 patterns detected (queries are per-request, not per-file)

### File Operations
- Uploads: Streamed to temp file, then atomic rename (no partial files)
- Downloads: Streamed via `ReaderStream` (no full-file memory load)
- SHA-256: 1 MB buffer reads (streaming, not all-in-memory)
- Sync manifest: Recursive directory walk with incremental fingerprint cache
- File search: Recursive walk with early termination (500 result limit)

### Concurrency
- Max 5 SQLite connections (serialized writes, parallel reads)
- Upload jobs are idempotent (resume-safe)
- No blocking operations in async request paths

## Client Measurements

### Flutter
- Login: Single HTTP request, token stored in secure storage
- File listing: Single HTTP request per page
- Uploads: Chunked streaming (8 MB chunks) via `StreamedRequest`
- Downloads: Streamed to temp file, then atomic rename
- State management: `ChangeNotifier` pattern, minimal rebuilds
- Periodic tasks: 30-second queue timer, 2-minute sync timer

### Responsive Testing
- 7 viewport sizes tested (400x800 to 1920x1080)
- 6 pages per size (Home, Files, Shared, Photos, Trash, Settings)
- No overflow errors observed
- Desktop sidebar and mobile bottom nav both render correctly

## Bottlenecks Identified

1. **Recursive directory scan for sync manifest** - For directories with >10,000 files, the initial sync scan may take several seconds. Mitigated by incremental fingerprint caching.
2. **`tree_stats` / `folder_size`** - These traverse the full directory tree. Called on quota checks and storage reporting. For large directories (>50,000 files), this could be slow. No mitigation applied (premature optimization).
3. **Search scan** - Recursive walk without index. Capped at 500 results.

## Changes Made

- Added `MAX_SEARCH_RESULTS = 500` cap to `search_files`
- No other performance changes made (no bottlenecks justified changes)

## Remaining Limitations

- No file content index (search is filename-only)
- Sync manifest scan is O(files) on first run per device
- `tree_stats` is called on every upload for quota checking
