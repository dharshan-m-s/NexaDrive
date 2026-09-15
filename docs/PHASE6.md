# Phase 6 — Sync

Phase 6 adds a restart-safe desktop sync layer while keeping NexaDrive's core storage model unchanged: normal files live on the filesystem and SQLite stores metadata.

## What is included

- Desktop sync folders for Windows, Linux and macOS.
- Per-device IDs stored server-side in `sync_devices`.
- Recursive remote sync manifest with SHA-256 checksums for files.
- Server tombstones in `sync_tombstones` for explicit deletions.
- Local sync baseline persisted in the client.
- Two-way reconciliation for local-only, remote-only, changed and deleted files.
- Conflict protection: when both sides changed the same file, the local version remains and the remote version is downloaded as a `.conflict-<timestamp>` copy.
- Downloads are streamed to a temporary file and renamed only after transfer completion.
- Local-to-remote uploads reuse the Phase 5 resumable 8 MiB transfer queue.
- Sync Center UI for choosing a folder, running sync, viewing status and conflict/error counts.

## Safety rules

A missing local or remote file is not blindly treated as a delete. The client compares it with the last successful baseline and the server's tombstone list before propagating deletion.

Two independently changed files are never silently overwritten. Users keep the local version while the remote version is preserved as a conflict copy.

Interrupted uploads remain in the durable Phase 5 transfer queue. Interrupted downloads leave a temporary file and do not replace the destination until the stream completes.

## Current scope

Full filesystem sync is intentionally a desktop feature. Android does not attempt arbitrary bidirectional filesystem synchronization because scoped storage and background-execution rules require a different native workflow. Android photo backup is the appropriate next mobile-specific sync feature.

## Known limitations

The current manifest scans and hashes every regular file. This is robust but can be expensive for very large libraries. A future phase can maintain server-side file fingerprints/revisions and return deltas without hashing the whole tree.

Conflict resolution is deliberately conservative: the app creates a conflict copy rather than offering a merge editor. A future Sync Center can add explicit Keep local / Keep remote / Keep both actions.
