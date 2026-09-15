# Security policy

## Reporting a vulnerability

If you discover a security issue, please open a private security advisory on
GitHub **instead of** filing a public issue. Include:

- steps to reproduce
- your assessment of severity and impact
- any suggested fix (optional)

We aim to acknowledge reports within 72 hours and release a fix (or a
mitigation) as soon as practical. Coordinated disclosure is appreciated but
not strictly required.

## Security design

NexaDrive is designed for private, single-family deployments behind Tailscale
or a trusted reverse proxy. It is **not** hardened for public-facing exposure
to untrusted networks.

Key security properties:

- Passwords are hashed with Argon2id (never stored in plaintext).
- Session tokens are stored hashed (SHA-256) on the server.
- The server binds to `127.0.0.1` by default; the SQLite database never
  listens on the network.
- Public-share secrets are only returned at creation time and are never stored
  in plaintext after migration.
- Upload downloads are streamed; full-image thumbnails are generated
  server-side and cached only for opt-in, short-lived HTTP responses.
- Security headers (`X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`, `Cache-Control: no-store`) are set on every response.

See `docs/SECURITY_AUDIT.md` for the detailed hardening checklist and
`docs/APP_QA_CHECKLIST.md` for the client-side QA results.

## Recommendations

- Use Tailscale Serve or a TLS-terminating reverse proxy in front of the
  server; the built-in HTTP listener is not HTTPS.
- Rotate the admin password after the initial deployment.
- Keep `server/.env` and any `key.properties` out of version control (the
  root `.gitignore` enforces this for git, but be mindful of backups or
  CI logs).
- Review `docs/DEPLOYMENT.md` for filesystem permissions, environment file
  locations and Restic backup guidance.
