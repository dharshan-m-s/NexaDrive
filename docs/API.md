# NexaDrive API contract

Base URL is whatever the client was configured with (`PUBLIC_URL` server-side, or
the address typed at sign-in). All endpoints are JSON unless stated otherwise.

Authenticated endpoints require:

```text
Authorization: Bearer <session-token>
```

## Error shape

Every failure returns the HTTP status with a single JSON object:

```json
{ "error": "human readable reason" }
```

| Status | Meaning |
| --- | --- |
| 400 | Bad request — the input was rejected (validation, unsafe path, missing field) |
| 401 | Unauthorized — missing, expired, or revoked session |
| 403 | Forbidden — authenticated, but not allowed (admin-only route, reserved path) |
| 404 | Not found — the resource does not exist |
| 409 | Conflict — e.g. the username is already taken |
| 415 | Unsupported media — no thumbnail can be generated for this file |
| 429 | Too many requests — login throttling |
| 500 | Internal server error — the detail is logged server-side, never returned |

The API version reported by `GET /api/server/status` is a *contract* version,
separate from the release version. It only changes when the request/response
shapes change.

## Endpoint index

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | none | Liveness probe |
| GET | `/api/server/status` | none | Instance id, start time, versions, public URL |
| POST | `/api/auth/login` | none | Exchange credentials for a session token |
| GET | `/api/share/{token}/download` | none | Public share download |
| POST | `/api/auth/logout` | bearer | Revoke the current session |
| GET | `/api/me` | bearer | The signed-in account |
| GET | `/api/files` | bearer | List a folder |
| DELETE | `/api/files` | bearer | Move an item to Trash |
| GET | `/api/files/search` | bearer | Recursive name search |
| GET | `/api/files/download` | bearer | Stream a file (range-aware) |
| GET | `/api/files/thumbnail` | bearer | Server-generated JPEG preview |
| POST | `/api/files/upload` | bearer | Multipart upload (idempotent by `upload_id`) |
| POST | `/api/files/rename` | bearer | Rename in place |
| POST | `/api/files/move` | bearer | Move into a folder |
| POST | `/api/files/copy` | bearer | Copy into a folder |
| POST | `/api/files/batch` | bearer | Apply one action to many paths |
| POST | `/api/folders` | bearer | Create a folder |
| GET | `/api/uploads/status` | bearer | Durable upload state |
| POST | `/api/uploads/chunk` | bearer | Resumable chunk upload |
| GET | `/api/storage` | bearer | Used bytes and file count |
| GET | `/api/trash` | bearer | List trashed items |
| POST | `/api/trash/restore` | bearer | Restore a trashed item |
| DELETE | `/api/trash` | bearer | Permanently delete a trashed item |
| GET | `/api/photos` | bearer | Recursively list recognised photos |
| GET | `/api/shares` | bearer | Shares created by the caller |
| POST | `/api/shares` | bearer | Create a share or a public link |
| DELETE | `/api/shares` | bearer | Revoke a share |
| GET | `/api/shared` | bearer | Items shared *with* the caller |
| GET | `/api/shared/items` | bearer | Browse a shared folder |
| GET | `/api/shared/download` | bearer | Download through a named share |
| POST | `/api/shared/action` | bearer | Write into a share with `write` permission |
| GET | `/api/sync/manifest` | bearer | Full manifest + checksums + tombstones |
| GET | `/api/sync/delta` | bearer | Only what changed after a cursor |
| POST | `/api/sync/delete` | bearer | Delete through sync (records a tombstone) |
| GET | `/api/sync/devices` | bearer | Linked devices |
| PATCH | `/api/sync/devices` | bearer | Rename a linked device |
| DELETE | `/api/sync/devices` | bearer | Unlink a device |
| GET | `/api/notifications` | bearer | Notifications |
| POST | `/api/notifications/read` | bearer | Mark one, or all, as read |
| GET | `/api/admin/users` | admin | List accounts |
| POST | `/api/admin/users` | admin | Create an account |
| PUT | `/api/admin/users/{id}` | admin | Update an account |
| DELETE | `/api/admin/users/{id}` | admin | Delete an account and its data |
| POST | `/api/admin/users/{id}/revoke-sessions` | admin | Force a sign-out |
| GET | `/api/admin/audit` | admin | Audit log |
| GET | `/api/backup/status` | admin | Restic availability and configuration |
| POST | `/api/backup/run` | admin | Take a snapshot |
| GET | `/api/backup/snapshots` | admin | List snapshots |
| POST | `/api/backup/restore` | admin | Restore a snapshot |
| POST | `/api/backup/check` | admin | Verify repository integrity |

## Path safety

Every `path`-style parameter is resolved by the same rules, and violating any of
them is a `400` (or `403` for the reserved Trash path):

- paths are **relative** to the caller's own storage root — a leading `/`, a
  Windows drive prefix, or a `..` segment is refused;
- NUL bytes are refused;
- `.trash` is reserved for the server's trash area and is never readable or
  writable through the file API;
- a user can only ever reach their own UUID subtree, so there is no
  cross-account file access by construction.

## Authentication

### POST `/api/auth/login`

```json
{ "username": "admin", "password": "..." }
```

Returns the session token and the account:

```json
{
  "token": "...",
  "user": { "id": "...", "username": "admin", "display_name": "Administrator", "role": "admin" }
}
```

Usernames are matched case-insensitively. Repeated failures are throttled per
account: 10 failed attempts within a 15-minute window make further attempts
return `429` until the window expires. The throttle is keyed on the account
being attacked, never on a client-supplied forwarding header, so a spoofed
header cannot be used to bypass it.

### POST `/api/auth/logout`

Deletes the current session row. The token is unusable afterwards.

### GET `/api/me`

Returns the signed-in account, re-read from the database (so a role change or a
block takes effect without re-login).

## Files

### GET `/api/files?path=Documents`

Returns the direct children of a folder.

```json
[{ "name": "report.pdf", "path": "Documents/report.pdf", "kind": "file",
   "size": 12345, "modified_at": "2026-09-16T10:00:00Z" }]
```

Symlinks are skipped rather than followed.

### GET `/api/files/search?q=report`

Recursively searches within the caller's storage root by file/folder name.
Capped at 500 results.

### POST `/api/folders`

```json
{ "path": "Documents/New folder" }
```

### POST `/api/files/upload`

Multipart fields:

- `path`: destination folder
- `upload_id`: client-generated id, idempotent across retries
- `file`: file bytes

Uploads are staged and flushed before atomic placement. A restart recovery pass
reconciles unfinished upload jobs with the filesystem, and stale staging is
cleaned up on startup.

### GET `/api/uploads/status?upload_id=<uuid>`

Returns the durable state of an upload so a client that lost its connection can
resume instead of starting over.

### POST `/api/uploads/chunk`

Resumable chunked upload for large files and flaky links. Query parameters:
`upload_id`, `path`, `name`, `offset`, `total`; the body is the chunk.

### GET `/api/files/download?path=Documents/report.pdf`

Streams the stored file with its real `Content-Type`. `Accept-Ranges: bytes` is
advertised and a single `Range` header is honoured with `206 Partial Content`; an
unsatisfiable range returns `416` with `Content-Range: bytes */<size>`.

Only media that is safe to render inline (images, video, audio, PDF, plain text)
is served with `Content-Disposition: inline`. HTML, SVG and JavaScript are always
`attachment`, so a file host can never become an XSS vector.

### GET `/api/files/thumbnail?path=&max=`

Server-generated JPEG preview. Returns `415` when no thumbnail can be produced
for that format, so the client can fall back to a full download. Thumbnails are
the one response allowed private browser caching.

### DELETE `/api/files?path=Documents/report.pdf`

Moves the item into the caller's Trash rather than deleting it outright.

### POST `/api/files/rename`

```json
{ "source": "Documents/old.pdf", "name": "new.pdf" }
```

Returns `{ "path": "<new path>" }`.

### POST `/api/files/move`

```json
{ "source": "Documents/report.pdf", "destination": "Archive" }
```

Returns `{ "path": "<new path>" }`.

### POST `/api/files/copy`

```json
{ "source": "Documents/report.pdf", "destination": "Archive" }
```

Returns `{ "path": "<new path>" }`.

### POST `/api/files/batch`

```json
{ "action": "delete", "paths": ["a.txt", "b.pdf"], "destination": "Archive" }
```

`destination` is required for `move`/`copy`. A batch is limited to 100 paths per
request. Returns the list of paths the action actually touched.

## Storage

### GET `/api/storage`

Returns aggregate used bytes and file count for the caller's storage, plus the
account's quota when one is set.

## Trash

- `GET /api/trash` — list trashed items.
- `POST /api/trash/restore?id=<uuid>` — restore an item to its original location.
- `DELETE /api/trash?id=<uuid>` — permanently remove an item.

## Photos

### GET `/api/photos`

Recursively lists recognised photo files for the caller.

## Sharing

### POST `/api/shares`

Accepts `path`, `permission` (`read` | `write`) and an optional `username`.

- With `username`: a direct share with another account.
- Without: a public link, returned with a one-time `token`. The token is stored
  only as a SHA-256 hash, so a database leak does not hand out working links.

A **directory cannot be shared as a public link** — a link resolves to a single
file download, so the request is rejected with `400` rather than handing out a
URL that can never work. Share the folder with a named user instead; recipients
browse it through `GET /api/shared/items`.

### DELETE `/api/shares?id=<uuid>`

Removes the row outright, so a revoked link immediately stops resolving.

### GET `/api/share/{token}/download`

The unauthenticated endpoint behind a public link. Repeated failures against the
same token are throttled.

### GET `/api/shared` · GET `/api/shared/items` · GET `/api/shared/download` · POST `/api/shared/action`

The recipient-side surface: what is shared with the caller, browsing a shared
folder, downloading from it, and writing into it when the share grants `write`.

## Sync

Desktop sync is a manifest/delta protocol so a client never has to walk the whole
tree to find changes.

### GET `/api/sync/manifest`

Optional `device_id` identifies an existing desktop device; a first call creates
one. Returns the complete user file manifest, SHA-256 checksums, and server
tombstones. Unchanged files are detected by size + modified time before any
re-hashing, so a repeat sync does not re-hash the whole library.

### GET `/api/sync/delta?since=<RFC3339>`

Returns only server entries created or modified after the cursor, plus deletion
tombstones created after it. The server still performs an authoritative
filesystem scan, so files changed outside NexaDrive are discovered.

Optional query parameters: `device_id`, `device_name`, and `platform` (one of
`android`, `windows`, `linux`, `macos`; anything else is dropped rather than
stored).

The response contains `device_id`, `server_time`, `entries` and `tombstones`.
Clients should persist `server_time` as the next cursor only after local
reconciliation succeeds.

### POST `/api/sync/delete`

```json
{ "path": "Documents/example.pdf" }
```

Moves the target to Trash and records a tombstone so the deletion reconciles
safely on every device.

### Sync devices

- `GET /api/sync/devices` — devices linked to the account, newest activity first.
  Each entry carries `id`, `name`, `platform`, `last_seen_at`, `created_at`.
- `PATCH /api/sync/devices` — body `{ "id": "<uuid>", "name": "..." }` renames a
  linked device (1–64 characters). Only the caller's own devices are reachable,
  and a rename never resurrects a revoked device.
- `DELETE /api/sync/devices?id=<uuid>` — unlinks a device. The next sync from that
  machine re-registers under a fresh id, so a revoke never leaves a client
  permanently unable to sync.

## Notifications

- `GET /api/notifications?unread=true|false` — newest first, capped at 100.
- `POST /api/notifications/read` — body `{ "id": "<uuid>" }` for one, or
  `{ "all": true }` for every unread notification.

## Administration

All admin routes require the `admin` role; a non-admin gets `403`.

### GET `/api/admin/users`

Lists accounts with `id`, `username`, `display_name`, `role`, `disabled` and
`quota_bytes` (`null` = unlimited).

### POST `/api/admin/users`

```json
{ "username": "grace", "display_name": "Grace Hopper",
  "password": "...", "role": "user", "quota_bytes": 10737418240 }
```

Validation: username 3–64 characters, non-empty display name, password at least
10 characters, `role` one of `user`/`admin`, quota non-negative. A duplicate
username is a `409`.

### PUT `/api/admin/users/{id}`

Partial update. Omitted fields are left untouched. `disabled: true` blocks
sign-in without deleting data; setting `password` signs that user out everywhere.
Because an absent `quota_bytes` means "leave unchanged", clearing a quota back to
unlimited is a distinct flag: `{ "clear_quota": true }`.

The last active administrator cannot be demoted, blocked or deleted, and an
administrator cannot delete or block their own account. These refusals are
enforced here regardless of what the client offers to show.

### DELETE `/api/admin/users/{id}`

Permanently removes the account, its files, shares, trash and sessions. There is
no undo.

### POST `/api/admin/users/{id}/revoke-sessions`

Ends every active session for that account without touching the password — used
for a lost or shared device.

### GET `/api/admin/audit?limit=`

Returns recent audit entries. Non-admin callers get `403`.

## Backups (Restic)

Optional; requires `restic` plus the `RESTIC_*` environment variables. When
Restic is not configured these routes report that clearly instead of failing
obscurely.

- `GET /api/backup/status` — is Restic available, and how is it configured.
- `POST /api/backup/run` — take a snapshot. `{ "prune": true }` also applies the
  configured retention policy.
- `GET /api/backup/snapshots` — list snapshots.
- `POST /api/backup/restore` — `{ "snapshot_id": "..." }`.
- `POST /api/backup/check` — runs `restic check --read-data-subset=5%` and
  returns `{ "verified": true, "output": "..." }`. A failure raises a persistent
  notification so it is not missed.

## Background transfer worker

The Flutter client schedules a unique 15-minute Android Workmanager task when a
signed-in session exists. The worker drains the durable resumable upload queue
and never re-uploads chunks the server has already acknowledged.
