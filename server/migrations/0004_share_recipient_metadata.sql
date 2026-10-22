-- Allow the sharing UI to show who has access and when, while keeping the row
-- honest about whether the recipient is a named user or a public link.
ALTER TABLE shares ADD COLUMN recipient_name TEXT;

-- Backfill instead of defaulting: SQLite rejects ADD COLUMN with a
-- non-constant default such as CURRENT_TIMESTAMP. New rows always supply
-- granted_at explicitly, so the column only needs a value for legacy rows.
ALTER TABLE shares ADD COLUMN granted_at TIMESTAMPTZ;
UPDATE shares SET granted_at = created_at WHERE granted_at IS NULL;

-- Optional human-readable label for a public link, so the owner can tell two
-- link shares apart in the same folder without storing the token itself.
ALTER TABLE shares ADD COLUMN link_label TEXT;

-- Fast lookups when the owner manages recipients for a path.
CREATE INDEX IF NOT EXISTS shares_owner_path_recipient_idx
    ON shares(owner_id, path, recipient_user_id);
