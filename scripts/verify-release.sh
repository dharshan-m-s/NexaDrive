#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
required=(
  app/pubspec.yaml
  app/lib/main.dart
  app/lib/ui/shell/app_shell.dart
  app/lib/services/api.dart
  app/lib/services/session.dart
  app/lib/services/sync_service.dart
  app/lib/services/transfer_queue.dart
  server/Cargo.toml
  server/src/main.rs
  deploy/nexadrive-server.service
  .github/workflows/ci.yml
  .github/workflows/release.yml
  docs/FINAL_RELEASE.md
)
for f in "${required[@]}"; do test -f "$f" || { echo "missing: $f" >&2; exit 1; }; done
python3 - <<'PY'
from pathlib import Path
import re
m=Path('server/migrations')
files=sorted(m.glob('*.sql'))
nums=[int(x.stem.split('_',1)[0]) for x in files]
assert nums == list(range(1, max(nums)+1)), nums
for f in files:
    text=f.read_text()
    assert not text.lstrip().startswith(('use axum::','import ','class ')), f
main=Path('server/src/main.rs').read_text()
assert 'SqlitePool' in main
assert 'SqliteConnectOptions' in main
assert 'DATABASE_PATH' in main
assert 'SqliteJournalMode::Wal' in main
assert 'VACUUM INTO' in main
assert 'token_hash' in main
assert 'ensure_quota' in main
import sqlite3
con=sqlite3.connect(':memory:')
con.executescript(Path('server/migrations/0001_init.sql').read_text())
expected={'users','sessions','audit_logs','trash_items','shares','upload_jobs','sync_devices','sync_tombstones','sync_file_fingerprints','notifications'}
actual={r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
assert expected <= actual, (expected-actual)
print(f'OK: {len(files)} SQLite migration(s); schema and final project structure are present.')
PY
printf 'release verification: PASS\n'
