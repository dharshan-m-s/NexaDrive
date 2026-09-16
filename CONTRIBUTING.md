# Contributing to NexaDrive

Thanks for your interest in NexaDrive. This guide covers the development
workflow and conventions used in the repository.

## First steps

1. Fork and clone the repo.
2. Install the prerequisites:
   - **Flutter** 3.47.2 (`flutter --version`)
   - **Rust stable** (`rustup default stable`)
3. Build and test locally (see "Local validation" below).

## Repository layout

```
server/   — Rust/Axum API server
app/      — Flutter (Android / Linux / Windows) client
deploy/   — systemd service unit + installer
scripts/  — helper scripts (start, stop, backup, packaging)
docs/     — internal engineering docs, audit reports, specs
```

## Local validation

Run these before pushing. CI will fail on any of these.

### Server

```bash
cd server
cargo fmt --check        # formatting
cargo clippy --all-targets -- -D warnings   # lint (no warnings)
cargo test               # unit tests
```

### Client

```bash
cd app
flutter pub get
flutter analyze          # static analysis
flutter test             # unit tests
```

## Branching and commits

- `main` is the release-ready branch. Pushes and PRs target `main`.
- Keep commits focused and messages concise. Match the existing style:
  imperative mood, no trailing period, lowercase.
- CI runs on every push/PR to `main`.

## Pull requests

1. Ensure `cargo fmt`, `clippy -D warnings`, `flutter analyze` and all
   tests pass locally.
2. Open a PR against `main`.
3. CI must be green before merging.
4. Describe *what* and *why* in the PR description; include screenshots for
   UI changes.

## Releasing

Releases are created from the **GitHub Actions UI** — no tag-pushing is needed.
Open **Actions → Release → Run workflow**, type the version you want to ship
(e.g. `1.6.0`), choose whether it is a prerelease, and run it. The workflow
validates the version, builds every format, and publishes the GitHub Release.

```bash
# Local pre-release smoke test (no release is published):
cd app && flutter build linux --release && cd ..
scripts/package-linux.sh 1.6.0 dist
scripts/update-manifest.sh 1.6.0 0 dist
python3 scripts/verify-update-manifest.py dist/nexadrive-update-manifest.json
```

## Code style

- **Rust:** `cargo fmt` is authoritative; `clippy -D warnings` is enforced.
- **Dart/Flutter:** follow the effective Dart style guide; `flutter analyze`
  must pass with no issues.
- **Bash:** `set -euo pipefail` in all scripts; quote all variable
  expansions; prefer `[[ ]]` over `[ ]` in Bash.

## Security

Never commit `server/.env`, keystores, tokens, passwords, or real LAN IPs
to the repository. The root `.gitignore` and CI guardrails help, but
final responsibility is the author's. See `SECURITY.md` for the
vulnerability reporting process.

## License

By contributing you agree that your contributions will be licensed under the
MIT License (see `LICENSE`).
