# Phase 7 — Efficient Sync, Conflict Resolution and Restic Backups

Phase 7 keeps the Phase 6 filesystem-sync model but makes repeat syncs cheaper and gives users explicit conflict choices.

## Efficient sync manifests

The server now keeps `sync_file_fingerprints` in SQLite. For each remote file, the server compares size and modification time to the cached fingerprint. It only recomputes SHA-256 when those attributes changed (or when the fingerprint is missing). This avoids re-hashing an unchanged library on every sync.

The cache is metadata only. The real file remains a normal file under the user's storage directory.

## Conflict resolution

A conflict remains active until the user resolves it. The Sync Center provides:

- Keep local — uploads the local version and removes the conflict copy.
- Keep remote — downloads the remote version over the local version and removes the conflict copy.
- Keep both — keeps the local version and its conflict copy, then marks the conflict resolved.

NexaDrive does not silently choose a side.

## Backup integration

Phase 7 adds optional Restic integration on the server. Configure:

- `RESTIC_REPOSITORY`
- `RESTIC_PASSWORD_FILE`
- optionally `RESTIC_BIN` if `restic` is not on PATH

The admin-only backup status endpoint checks configuration and Restic availability. The admin-only backup action creates a Restic snapshot of the NexaDrive storage root while excluding `.trash` and temporary upload files. Optional retention cleanup keeps the last 7 snapshots, 14 daily, 8 weekly and 12 monthly snapshots.

No file contents are moved into SQLite. Restic reads the ordinary filesystem storage directly.

## Recovery model

- Uploads continue to use Phase 5 resumable chunks.
- Sync downloads use temporary files and atomic replacement.
- Conflicts preserve both versions until the user resolves them.
- Tombstones remain the source of truth for intentional deletions.
- Restic snapshots provide a separate rollback path for the storage filesystem.
