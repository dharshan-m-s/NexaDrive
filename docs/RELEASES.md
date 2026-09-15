# NexaDrive release and update model

NexaDrive uses GitHub Releases as the distribution channel for self-hosted builds.

The repository deliberately keeps generated Flutter platform directories out of the core source archive. Generate them with `scripts/bootstrap-platforms.sh` during local development, or let the release workflow generate the required shell automatically.

Release artifacts are produced from tags matching `v*`. The server artifact contains the Rust binary, SQL migrations, systemd service, and installation helper. Desktop and Android artifacts are published directly to the GitHub Release.

For server upgrades, stop the current service, replace the binary and migration directory from the release package, then start the service again. SQL migrations are applied automatically by the server on startup.

For desktop upgrades, install the newer release package over the previous version while preserving the user's local sync folder and application data. The sync state is intentionally stored separately from the release binary.

For Android, install the newer APK over the existing package so secure session storage and app-private queue state remain associated with the same application ID.
