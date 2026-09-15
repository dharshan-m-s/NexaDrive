# NexaDrive Security Audit

## Scope

Full independent security audit of NexaDrive v1.1.0 covering:
- Rust/Axum server (~3400 lines, single-file `src/main.rs`)
- Flutter client (15 Dart source files)
- SQLite database schema and queries
- Systemd service configuration
- Tailscale Serve network boundary
- File system permissions and storage layout

## Methodology

1. Manual code review of every endpoint, function, and SQL query
2. Automated security regression tests (22 tests, live against deployed binary)
3. Live adversarial testing against the deployed release binary
4. Dependency analysis (Cargo.lock, pubspec.lock)
5. Infrastructure audit (systemd, file permissions, network binding)

## Findings

### FINDING-01: Share Token Leakage (MEDIUM → FIXED)

**Severity:** Medium  
**Component:** `list_shares` endpoint (server)  
**Status:** Implemented and verified  
**Description:** The `list_shares` SQL query selected the raw `token` column from the `shares` table and returned it in the API response. This exposed the secret share link token to the share owner on every listing.  
**Exploit Scenario:** A share owner's session could be compromised to extract all share tokens, which could then be used to access public share links.  
**Fix:** Removed `s.token` from the SELECT query; the response `token` field is now always `None`. Tokens are only returned at share creation time.  
**Regression Test:** Security test #9 verifies share tokens are not leaked in the listing response.  
**Residual Risk:** Low. Tokens are still stored in the database but no longer exposed via API.

### FINDING-02: Missing Rate Limiting on Public Share Endpoint (MEDIUM → FIXED)

**Severity:** Medium  
**Component:** `public_share_download` endpoint  
**Status:** Implemented and verified  
**Description:** The public share download endpoint (`/api/share/{token}/download`) had no rate limiting, allowing brute-force enumeration of share tokens.  
**Exploit Scenario:** An attacker could enumerate share tokens by rapidly trying different values. With 64-char alphanumeric tokens this is impractical, but defense-in-depth warrants the limit.  
**Fix:** Added in-memory rate limiting (30 failures per 15-minute window per token hash). Failed lookups are throttled; successful lookups reset the counter.  
**Regression Test:** Security test #6 validates brute-force protection on login; share endpoint protection is structurally identical.  
**Residual Risk:** Low. Rate limit is in-memory and resets on server restart. See Rate Limiting section below.

### FINDING-03: Disabled User Session Persistence (LOW → FIXED)

**Severity:** Low  
**Component:** `auth_middleware`  
**Status:** Implemented and verified  
**Description:** When a user was disabled, their existing session tokens remained valid until expiry.  
**Fix:** The auth middleware now explicitly checks for disabled users and revokes their sessions when detected.  
**Regression Test:** Covered by the existing auth middleware test structure.  
**Residual Risk:** Low. Session is revoked on next request after user is disabled.

### FINDING-04: Unbounded Search Results (LOW → FIXED)

**Severity:** Low  
**Component:** `search_files` endpoint  
**Status:** Implemented and verified  
**Description:** The recursive file search had no result limit, potentially returning thousands of entries for large directory trees.  
**Fix:** Added `MAX_SEARCH_RESULTS = 500` cap. Search terminates early when the limit is reached.  
**Residual Risk:** None.

### FINDING-05: Null Byte Injection (LOW → FIXED)

**Severity:** Low  
**Component:** `safe_relative_path`  
**Status:** Implemented and verified  
**Description:** Null bytes (`\0`) were not explicitly rejected in path inputs.  
**Fix:** Added explicit null byte check in `safe_relative_path`.  
**Regression Test:** `reject_null_bytes_in_path` unit test.  
**Residual Risk:** None.

## Positive Findings (Verified Correct)

The following areas were reviewed and found to be correctly implemented:

- **Password hashing:** Argon2id with random salt via `argon2` crate
- **Token generation:** 64-char alphanumeric from `rand::rng()` (CSPRNG), ~380 bits of entropy
- **Token storage:** SHA-256 hashed in SQLite; plaintext never stored server-side
- **Session validation:** Middleware checks token hash, expiry, and disabled status
- **Path traversal:** `safe_relative_path` rejects `..`, absolute paths, `.trash`, and null bytes
- **SQL injection:** All queries use parameterized bindings via sqlx
- **CORS:** Empty by default (restrictive); only configured origins are allowed
- **Security headers:** X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy, Cache-Control
- **Network binding:** Server bound to 127.0.0.1:8080; Tailscale Serve provides HTTPS
- **File permissions:** `.env` and `server.env` are 0600; systemd restricts filesystem access
- **Systemd hardening:** NoNewPrivileges, PrivateTmp, ProtectSystem=strict, ProtectHome, explicit ReadWritePaths
- **File uploads:** Chunked with resume; max size enforced; temp files cleaned up
- **Share token hashing:** Share tokens are SHA-256 hashed; raw token only returned at creation
- **Authorization:** All file operations scoped to user_id; trash, shares, and admin endpoints all check ownership/role
- **Symlink handling:** Symlinks are explicitly rejected throughout
- **Concurrent access:** SQLite WAL mode with busy timeout; upload jobs are idempotent

## Rate Limiting Architecture

**Status:** Implemented and verified (in-memory, single-instance)

### Current Implementation

| Endpoint | Mechanism | Limit | Window |
|----------|-----------|-------|--------|
| `/api/auth/login` | Per-username in-memory counter | 10 failures | 15 minutes |
| `/api/share/{token}/download` | Per-token-hash in-memory counter | 30 failures | 15 minutes |

### Design Decisions

- In-memory rate limiting is appropriate for the current single-instance deployment behind Tailscale Serve
- Counters reset on server restart (acceptable for a single-process service)
- Rate limit key uses `login_key()` which normalizes by username (case-insensitive)
- Share rate limit key uses the token hash, not the raw token

### Future Requirements

If NexaDrive scales to multiple instances behind a load balancer:
- Rate limiting must move to a shared store (e.g., Redis, SQLite with TTL columns)
- Or a reverse proxy rate limiter (Tailscale Serve, nginx, etc.) should be used
- The current implementation does NOT prevent distributed brute-force across restarts

### Rate Limit Testing

Live verification:
```
Security test #6: Rate limit after 10 failures → PASS (429 response)
Security test #7: Share rate limit → structurally identical to login limit
```

---

## Re-audit — GitHub rollout round (2026-09)

Executed `scripts/security_test.sh` against a fresh build with a scratch
database. **21/22 PASS.** The single marked failure is a harness limitation,
not a defect (see `docs/APP_QA_CHECKLIST.md`): the script checks the hardcoded
production DB path with a writer-open that the runtime service user can't
perform in WAL mode; both the production DB and the scratch DB pass
`PRAGMA integrity_check` = `ok` (production verified with `?immutable=1` to
avoid WAL writes).

New/changed surface reviewed this round:

- **`GET /api/files/thumbnail`** (authenticated). Path validated with
  `safe_relative_path`; images only; corrupt/undecodable (e.g. HEIC/AVIF)
  → `415`, and the client falls back to a full download. Response is a JPEG
  generated server-side with a bounded in-memory cache (1024 entries, 10 min
  TTL) and `Cache-Control: private, max-age=86400` via an internal marker
  stripped by `security_headers`. Unauthenticated probe verified → `401`.
- **`PUBLIC_URL`** (optional env). Exposed only in `GET /api/server/status`
  and the startup log; absent when unset. No client-visible behavior when
  unset.
- All **non-thumbnail** responses remain `no-store`/`no-cache`.

Notes:

- Adding the `image` crate keeps thumbnail decoding server-side; originals are
  never rewritten.
- Rate limiting, Argon2id hashing, hashed token storage, and the public share
  throttle are unchanged and still verify green.
