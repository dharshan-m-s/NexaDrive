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
- `platform` — one of `android`, `windows`, `linux`, `macos` (normalised
  server-side; anything else is dropped rather than stored)

The response contains `device_id`, `server_time`, `entries`, and `tombstones`. Clients should persist `server_time` as the next cursor only after local reconciliation succeeds.

### Sync devices

- `GET /api/sync/devices` — devices linked to the account, newest activity
  first. Each entry carries `id`, `name`, `platform`, `last_seen_at` and
  `created_at`.
- `PATCH /api/sync/devices` — body `{ "id": "<uuid>", "name": "..." }`
  renames a linked device (1-64 characters). Only the caller's own devices
  are reachable; a rename never resurrects a revoked device.
- `DELETE /api/sync/devices?id=<uuid>` — unlinks a device. The next sync from
  that machine re-registers it under a fresh id, so a revoke never leaves a
  client permanently unable to sync.

### Content types and range requests

`GET /api/files/download` (and the public share download) return the stored
file with its real `Content-Type`. `Accept-Ranges: bytes` is advertised and a
single `Range` header is honoured with `206 Partial Content`; an unsatisfiable
range returns `416` with `Content-Range: bytes */<size>`.

Only media that is safe to render inline (images, video, audio, PDF, plain
text) is served with `Content-Disposition: inline`. HTML, SVG and JavaScript
are always `attachment`, so a file host can never become an XSS vector.

### Sharing

`POST /api/shares` accepts `path`, `permission` (`read` | `write`) and an
optional `username`.

- With `username`: a direct share with another account.
- Without: a public link, returned with a one-time `token`. The token is
  stored only as a SHA-256 hash.

A **directory cannot be shared as a public link** — a link resolves to a
single file download, so the request is rejected with `400` rather than
handing out a URL that can never work. Share the folder with a named user
instead; recipients browse it through `GET /api/shared/items`.

Deleting a share (`DELETE /api/shares?id=`) removes the row outright, so a
revoked link immediately stops resolving.

### POST `/api/backup/check`

Admin-only Restic verification. The server runs `restic check --read-data-subset=5%` and returns `{ "verified": true, "output": "..." }` on success. Failures create a persistent notification.

## Phase 9 — background transfer worker

The Flutter client schedules a unique 15-minute Android Workmanager task when a signed-in session exists. The worker processes the existing durable resumable upload queue and never re-uploads chunks already acknowledged by the server.
