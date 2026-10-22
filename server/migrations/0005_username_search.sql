-- Speed up authenticated username lookups for the sharing picker without
-- opening up a generic username enumeration endpoint.
CREATE INDEX IF NOT EXISTS users_username_case_idx
    ON users (LOWER(username));

-- The sharing picker only needs to resolve a username to a user id and a
-- minimal display handle. Other profile fields stay out of this path.
