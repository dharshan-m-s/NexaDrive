# Phase 10 audit / hardening pass

This pass validates the Phase 9 source tree and fixes defects discovered during static review.

## Correctness fixes

- Fixed stale Phase 9 `AppShell` methods that referenced undefined state and prevented Dart compilation.
- Replaced the no-op desktop `New` button with a useful action surface that directs the user to the Files actions.
- Replaced the remote sync delta cursor logic that incorrectly compared filesystem `modified_at` timestamps with the server sync cursor.
- Added `updated_at` to `sync_file_fingerprints`; deltas now use server-side change timestamps.
- Remote fingerprint rows update their `updated_at` only when the actual fingerprint/metadata changes, so unchanged files are not reported as deltas.
- Disabled users can no longer continue using already-issued bearer sessions.
- Resumable uploads now reject declared totals above `MAX_UPLOAD_BYTES`.
- Public share audit records no longer store the plaintext share token.

## UX review

The app keeps a Samsung One UI-inspired visual language: large headings, generous spacing, rounded surfaces, thumb-friendly controls on mobile, and a sidebar on desktop. The review also checks accessibility-oriented touch targets, hierarchy, responsive layouts, and consistent semantic use of Material 3 components.

Known non-blocking UX debt remains:

- Mobile navigation currently exposes six primary destinations; a future More pattern would be cleaner for very small screens.
- Quick Access cards on Home are currently visual shortcuts without navigation wiring.
- Appearance is currently system-following only; Settings should expose a real theme selector in a later polish pass.
- Some large screens contain dense administrative/sync controls and should eventually move to sectioned subtabs.

## Validation limitations

The audit environment does not contain Flutter/Dart or Rust/Cargo toolchains, so source-level validation is performed here and the repository's GitHub Actions CI remains the authoritative compiler/test gate.
