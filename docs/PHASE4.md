# Phase 4 — Photos, Durable Transfers & Recovery

## Photos
- Dedicated Photos page.
- Recursive photo discovery by extension.
- Gallery and full-screen viewer.
- Original files remain in normal filesystem storage.
- Photo support is a presentation layer; NexaDrive does not restrict other file types.

## Durable transfers
Every client upload receives a stable UUID `upload_id` and is persisted in a local transfer queue.

The server records upload state in SQLite:
- `receiving`: upload has started.
- `staging`: bytes are fully written and synced to the temporary file.
- `completed`: the final file has been atomically moved into place.
- `failed`: recovery found no completed final file.

Retries reuse the same `upload_id`. If the server already completed that upload, it returns the completed result without requiring the file to be transferred again.

## Power loss / restart recovery
Uploads are first written to a temporary path and `sync_all()` is called before the final rename. On server startup NexaDrive checks unfinished upload jobs. If the final file exists, the job is recovered as completed; otherwise it is marked failed and the client can retry it.

The server also exposes a boot `instance_id`. The client compares it with the last known value and informs the user when the server has restarted, which covers cases such as power loss followed by recovery.

## File types
NexaDrive does not whitelist MIME types. Any normal filesystem file can be stored as long as it fits the configured HTTP upload limit (`MAX_UPLOAD_BYTES`, default 10 GiB). Unsupported preview formats remain ordinary downloadable files.

## Important limitation
A powered-off server cannot send a notification while it is offline. The client therefore reports the outage when it cannot reach the server and reports a restart on the next successful connection. Persistent queued uploads are retried then.
