# Embedded SQLite deployment

NexaDrive 1.1 uses an embedded SQLite database instead of PostgreSQL.

## Why

- No database daemon is required.
- No PostgreSQL service remains active while NexaDrive is stopped.
- Database files live on the NexaDrive data disk and can be mounted/unmounted with the rest of the application data.
- WAL mode allows concurrent readers while a single writer is active.
- A busy timeout reduces transient `database is locked` failures.
- SQLite is not exposed over the network.

## Files

Typical server layout:

```text
nexadrive/
├── data/
│   ├── nexadrive.db
│   ├── nexadrive.db-wal
│   └── nexadrive.db-shm
└── storage/
    ├── <user UUID>/
    └── .trash/
```

Always stop NexaDrive before unmounting the data filesystem. The server closes the SQLite pool during process shutdown, releasing the database handles.

## Backups

Restic creates a transactionally consistent SQLite snapshot before backing up. The live database is not directly copied while it may be changing.

Do not delete the `data` directory while NexaDrive is running.
