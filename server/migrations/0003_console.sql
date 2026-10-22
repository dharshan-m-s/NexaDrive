-- Additive migration for the localhost-only administration console and for
-- richer session/audit metadata. Every statement here is non-destructive:
-- columns are added with NULL/constant defaults, existing rows are preserved,
-- and no table is dropped or rewritten. The console never runs this against a
-- fresh database only — it runs once at server startup exactly like 0001/0002.

-- ---------------------------------------------------------------------------
-- Session activity + client metadata.
-- `last_activity_at` lets the app (and the console) show an idle-aware session
-- list. Legacy rows are backfilled from their creation time so the value is
-- always present once this migration has run. Client metadata is optional and
-- supplied by the client at login; it is never trusted for authorization.
-- ---------------------------------------------------------------------------
ALTER TABLE sessions ADD COLUMN last_activity_at TIMESTAMPTZ;
UPDATE sessions SET last_activity_at = created_at WHERE last_activity_at IS NULL;
ALTER TABLE sessions ADD COLUMN device_name TEXT;
ALTER TABLE sessions ADD COLUMN platform TEXT;

CREATE INDEX IF NOT EXISTS sessions_user_activity_idx
    ON sessions(user_id, last_activity_at DESC);
-- Session listing also filters/orders by expiry; folded in from the parallel
-- `sessions_metadata` migration that this consolidated 0003 replaces.
CREATE INDEX IF NOT EXISTS sessions_user_expires_idx
    ON sessions(user_id, expires_at);

-- ---------------------------------------------------------------------------
-- Console sessions: opaque, localhost-only administrator sessions used by the
-- dashboard. Tokens are stored only as SHA-256 hashes; the CSRF secret is
-- stored hashed as well. These rows are independent from the bearer `sessions`
-- table so a dashboard sign-in can be revoked without touching client devices.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS console_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    csrf_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS console_sessions_token_hash_idx ON console_sessions(token_hash);
CREATE INDEX IF NOT EXISTS console_sessions_user_idx ON console_sessions(user_id, expires_at DESC);

-- ---------------------------------------------------------------------------
-- Richer audit records. `target` names the object acted on, `outcome` records
-- success/denied/failed, and `detail` holds a short non-secret explanation.
-- The existing `path` column keeps its old meaning for file actions.
-- ---------------------------------------------------------------------------
ALTER TABLE audit_logs ADD COLUMN target TEXT;
ALTER TABLE audit_logs ADD COLUMN outcome TEXT;
ALTER TABLE audit_logs ADD COLUMN detail TEXT;
