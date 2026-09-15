# NexaDrive API contract

Authenticated endpoints use:

`Authorization: Bearer <token>`

## Login

POST `/api/auth/login`

```json
{"username":"admin","password":"..."}
```

## Files

GET `/api/files?path=Documents`

Returns the direct children of a folder.

GET `/api/files/search?q=report`

Searches recursively within the authenticated user's storage root by file/folder name.

POST `/api/folders`

```json
{"path":"Documents/New folder"}
```

POST `/api/files/upload`

Multipart fields:

- `path`: destination folder
- `file`: file bytes

GET `/api/files/download?path=Documents/report.pdf`

Streams a file to the client.

DELETE `/api/files?path=Documents/report.pdf`

Moves the item into the user's Trash rather than permanently deleting it.

## File management

POST `/api/files/rename`

```json
{"source":"Documents/old.pdf","name":"new.pdf"}
```

POST `/api/files/move`

```json
{"source":"Documents/report.pdf","destination":"Archive"}
```

POST `/api/files/copy`

```json
{"source":"Documents/report.pdf","destination":"Archive"}
```

POST `/api/files/batch`

```json
{"action":"delete","paths":["a.txt","b.pdf"]}
```

For move/copy, include `destination` as the destination folder. A batch is limited to 100 paths per request.

## Trash

GET `/api/trash`

POST `/api/trash/restore?id=<uuid>`

DELETE `/api/trash?id=<uuid>`

The last endpoint permanently removes an item from Trash.

## Storage

GET `/api/storage`

Returns aggregate used bytes and file count for the authenticated user's storage.

## Phase 4 transfer/recovery endpoints

- `GET /api/server/status` — returns the current server boot instance ID and start time.
- `GET /api/uploads/status?upload_id=<uuid>` — returns durable upload state for the authenticated user.
- `GET /api/photos` — recursively lists recognized photo files for the authenticated user.
- `POST /api/files/upload` — accepts `path`, `upload_id`, and `file` multipart fields. `upload_id` is idempotent across retries.

Uploads are staged and synced before atomic placement. A restart recovery pass reconciles unfinished upload jobs with the filesystem.


## Phase 6 — Sync

### GET `/api/sync/manifest`
Authenticated endpoint. Optional `device_id` identifies an existing desktop device. A first call creates a device ID. Returns the complete user file manifest, SHA-256 checksums for files, and server tombstones.

### POST `/api/sync/delete`
Authenticated endpoint. Body: `{ "path": "Documents/example.pdf" }`. Moves the target to the user's trash and records a sync tombstone so deletion can be reconciled safely.


### Phase 7 backup endpoints
- `GET /api/backup/status` — admin-only Restic configuration/availability status.
- `POST /api/backup/run` — admin-only snapshot; JSON `{ "prune": true|false }` optionally runs configured retention cleanup.

### Phase 7 sync manifest optimization
`GET /api/sync/manifest` now uses server-side file fingerprints to avoid re-hashing unchanged files (size + modified time are checked before SHA-256).

## Phase 9 — incremental sync and backup verification

### GET `/api/sync/delta?since=<RFC3339>`

Returns only server entries created or modified after the supplied cursor plus deletion tombstones created after the cursor. The server still performs an authoritative filesystem scan so files changed outside NexaDrive are discovered.

Optional query parameters:

- `device_id`
- `device_name`

The response contains `device_id`, `server_time`, `entries`, and `tombstones`. Clients should persist `server_time` as the next cursor only after local reconciliation succeeds.

### POST `/api/backup/check`

Admin-only Restic verification. The server runs `restic check --read-data-subset=5%` and returns `{ "verified": true, "output": "..." }` on success. Failures create a persistent notification.

## Phase 9 — background transfer worker

The Flutter client schedules a unique 15-minute Android Workmanager task when a signed-in session exists. The worker processes the existing durable resumable upload queue and never re-uploads chunks already acknowledged by the server.
