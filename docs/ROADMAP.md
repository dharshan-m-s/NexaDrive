# NexaDrive roadmap

## Phase 1 — hardened foundation (complete)
- Rust/Axum API
- SQLite metadata
- Argon2id authentication
- Secure client token storage
- One UI-inspired responsive Flutter shell
- Files: list/upload/download/create folder
- Streaming server transfers
- Trash: restore and permanent delete
- systemd deployment
- Tailscale-ready private access
- Basic path/symlink protection

## Phase 2 — file management (complete)
- Rename, move, copy
- Server-side recursive search
- File-type aware icons/presentation
- Persisted grid/list preference
- Batch delete/move/copy actions
- Responsive selection mode
- Better contextual actions

## Phase 3 — users, sharing and permissions
- User administration
- Read/write/share permissions
- Shared links
- Device/session management
- Audit log viewer

## Phase 4 — completed
- Dedicated Photos gallery and viewer.
- Durable transfer queue with idempotent upload IDs.
- Power-loss/restart recovery for interrupted uploads.
- Server restart detection and user notification.
- Multi-file upload queue.
- File-type agnostic storage with configurable 10 GiB default HTTP upload limit.

## Phase 5 — photos
- Timeline/grid
- Full-screen viewer
- Albums
- Android photo backup

## Phase 5 — advanced transfers
- Resumable/chunked uploads
- Background queues
- Retry/resume
- Large-file UX

## Phase 6 — sync
- Desktop sync
- Offline changes
- Conflict handling

## Phase 7 — versioning and backups
- File versions
- Restic integration
- Restore workflows

## Phase 8 — distribution
- Signed GitHub releases
- Windows/Linux installers
- Android release builds
- Safe update notifications

## Final release baseline
- Effective per-user quota enforcement.
- Public share token hashing and legacy migration.
- Persistent System/Light/Dark appearance selection.
- Final security/deployment documentation.

## Phase 9 completed

- Incremental sync cursors/delta endpoint.
- Safe external-deletion tombstone detection.
- Restic backup verification.
- Android background upload worker with Workmanager.
- Automated GitHub Release builds for server, Android, Windows and Linux.
