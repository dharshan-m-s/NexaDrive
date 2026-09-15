# Phase 5 — Resumable transfer system

Phase 5 upgrades NexaDrive transfers from whole-file retries to durable, resumable chunked uploads.

## Behavior

- Default chunk size: 8 MiB.
- Each transfer has a stable UUID.
- The server stores `bytes_received` and `total_bytes` in SQLite.
- Each chunk must start at the server-confirmed offset.
- Chunks are written to a staging file and `sync_all()` is called before progress is committed.
- Completion uses an atomic rename and records a SHA-256 checksum.
- SQLite advisory locking serializes retries for the same upload ID.
- If the client restarts, it queries `/api/uploads/status` and resumes from the confirmed offset.
- If the server restarts, unfinished jobs are reconciled during startup.
- A completed upload ID is idempotent: retrying it does not retransmit the file.
- The client queue persists locally and retains failed items for retry.
- Queue items can be paused/resumed while the application is running.

## API

`POST /api/uploads/chunk`

Query parameters:

- `upload_id`
- `path`
- `name`
- `offset`
- `total`

The request body is exactly one chunk. `Content-Length` must match the chunk length.

`GET /api/uploads/status?upload_id=...`

Returns status, confirmed bytes, total bytes, checksum (when complete), and the last error.

## Power-loss model

The design uses a staging file, disk synchronization, durable database progress, and atomic final placement. A power failure can still lose the very latest uncommitted chunk, but the client/server resume protocol never assumes unconfirmed bytes were received. Already confirmed bytes are not uploaded again.

## Background operation

Desktop clients can continue processing while the application process remains alive. Android background execution is deliberately left as a platform-specific follow-up because Android's background execution rules require a native worker/foreground-service policy; the queue itself is already durable and restartable.
