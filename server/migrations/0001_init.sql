CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user',
    disabled BOOLEAN NOT NULL DEFAULT FALSE,
    quota_bytes BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS sessions_token_hash_idx ON sessions(token_hash);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS audit_logs_user_created_idx ON audit_logs(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS trash_items (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    original_path TEXT NOT NULL,
    trash_path TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('file', 'folder')),
    size_bytes BIGINT NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS trash_items_user_deleted_idx ON trash_items(user_id, deleted_at DESC);

CREATE TABLE IF NOT EXISTS shares (
    id UUID PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    permission TEXT NOT NULL CHECK (permission IN ('read','write')),
    is_link BOOLEAN NOT NULL DEFAULT FALSE,
    token TEXT UNIQUE,
    token_hash TEXT UNIQUE,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (
        (is_link = TRUE AND recipient_user_id IS NULL AND token_hash IS NOT NULL AND token IS NULL)
        OR
        (is_link = FALSE AND recipient_user_id IS NOT NULL AND token_hash IS NULL AND token IS NULL)
    )
);
CREATE INDEX IF NOT EXISTS shares_recipient_idx ON shares(recipient_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS shares_owner_idx ON shares(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS shares_token_hash_idx ON shares(token_hash);

CREATE TABLE IF NOT EXISTS upload_jobs (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    size_bytes BIGINT NOT NULL DEFAULT 0,
    status TEXT NOT NULL CHECK (status IN ('receiving','staging','completed','failed')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bytes_received BIGINT NOT NULL DEFAULT 0,
    total_bytes BIGINT,
    checksum_sha256 TEXT,
    last_error TEXT
);
CREATE INDEX IF NOT EXISTS upload_jobs_user_status_idx ON upload_jobs(user_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS upload_jobs_resume_idx ON upload_jobs(user_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS sync_devices (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sync_tombstones (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, path)
);
CREATE INDEX IF NOT EXISTS sync_tombstones_user_deleted_idx ON sync_tombstones(user_id, deleted_at DESC);

CREATE TABLE IF NOT EXISTS sync_file_fingerprints (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('file','folder')),
    size_bytes BIGINT NOT NULL DEFAULT 0,
    modified_at TIMESTAMPTZ,
    sha256 TEXT,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, path)
);
CREATE INDEX IF NOT EXISTS sync_file_fingerprints_seen_idx ON sync_file_fingerprints(user_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS sync_file_fingerprints_created_idx ON sync_file_fingerprints(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS sync_file_fingerprints_updated_idx ON sync_file_fingerprints(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('info','warning','error')) DEFAULT 'info',
    read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS notifications_user_created_idx ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_user_unread_idx ON notifications(user_id, read, created_at DESC);
