# Phase 9 — production sync, background transfers and releases

Phase 9 turns the Phase 8 foundation into a more operationally complete client/server release.

## Incremental sync

The server now exposes `GET /api/sync/delta?since=<RFC3339>` in addition to the full manifest. The client keeps a `lastServerSyncAt` cursor and reconstructs its last-known remote view from the durable sync baseline before applying the delta.

The authoritative server scan still notices files changed outside the NexaDrive API. Cached fingerprints prevent SHA-256 work for files whose size and modification time are unchanged. Missing fingerprint rows become tombstones, and a recreated path clears its tombstone.

This reduces response size for normal syncs while retaining the safety of a full filesystem reconciliation scan.

## Backup verification and restore

`POST /api/backup/check` performs a Restic verification using a 5% data subset. Failures generate a persistent notification. Restore remains non-destructive: a snapshot is materialized into `.restic-restores/<timestamp>-<snapshot-id>` rather than replacing live files.

The Sync Center now exposes **Verify backup** alongside backup and restore controls.

## Background transfers

The Flutter client integrates Workmanager 0.10.9 for durable periodic background transfer processing. A 15-minute worker runs when network connectivity is available and the battery is not low. It reuses the Phase 5 resumable transfer queue, so completed chunks are not re-uploaded after interruption.

On Android, Workmanager can execute Dart work while the app is closed. The exact execution time remains OS-managed; long-running foreground-service transfers are intentionally not enabled by default.

The compact repository does not commit generated Android/Windows/Linux project shells. `scripts/bootstrap-platforms.sh` generates them locally, and the release workflow generates the platform shell needed for each build.

## Release automation

Tagging a release such as `v0.2.0` triggers `.github/workflows/release.yml`, which builds:

- Linux x86_64 server package
- Android release APK
- Windows x64 package
- Linux x64 desktop package

The workflow publishes these artifacts to the GitHub Release automatically.

For a local release, run:

```bash
./scripts/release-local.sh 0.2.0
```

Review the commit/tag before pushing when using an automated release script in a real repository.
