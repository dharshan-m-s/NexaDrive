# NexaDrive — Final Production Readiness Report

Generated against the working tree at `/mnt/data3/nexadrive`.
Companion document: `docs/FINAL_ENGINEERING_AUDIT.md` (screen-by-screen status).

Status labels: **VERIFIED** · **BUILD VERIFIED** · **FIXED** · **PARTIAL** ·
**ENVIRONMENT BLOCKED** · **NOT TESTED**.

---

## 1. Executive summary

This pass attacked the largest known unknown: the sync engine had **no** end-to-end
coverage, and every prior statement about it rested on reading the code. It now has
**26 deterministic tests** against an in-process fake server, and writing them found
**three genuine defects**, including one where a file deleted on one device was
silently resurrected on another, and one where sync was quietly driving the user's
manual transfer queue — retrying transfers the user had never asked it to touch and
leaving permanent rows behind.

Alongside that: the admin **Users** screen, the **Update Center**, and the **login**
layout were restructured against reproduced defects rather than restyled; the
**duplicate sync device** root cause was fixed on both client and server; and the
"yellow/green underlines" were established as Flutter's debug baseline visualisation
rather than a typography bug.

There is no performance, load, security-penetration, or multi-device convergence
evidence in this report, because none was produced. The backend was read and traced,
not modified, except where a reproduced defect demanded it.

## 2. Build and test results

| Command | Result | Status |
| --- | --- | --- |
| `flutter analyze` | No issues found | VERIFIED |
| `flutter test` | 266 passed / 0 failed | VERIFIED |
| `flutter build linux --debug` | OK | BUILD VERIFIED |
| `flutter build linux --release` | OK | BUILD VERIFIED |
| `flutter build apk --debug` | OK | BUILD VERIFIED |
| `flutter build apk --release` | OK, 65.3 MB | BUILD VERIFIED |
| `cargo fmt --check` | clean | VERIFIED |
| `cargo clippy --all-targets --all-features -- -D warnings` | 0 warnings | VERIFIED |
| `cargo test` | 42 passed / 0 failed | VERIFIED |
| `cargo build --release` | OK | BUILD VERIFIED |

## 3. Users screen

Reproduced defects, not guesses:

- A **failed** request rendered as `0 accounts`, indistinguishable from a wiped user
  table. Six distinct states now exist; a count only ever comes from a successful
  response.
- **Blocked accounts were administratively unreachable.** `OneUiGroupTile(enabled:
  false)` kills `ListTile.onTap`, and the trailing buttons were `onPressed: null`
  with the tooltip *"Deleted user"*. A blocked user could not be unblocked, edited,
  re-quota'd or deleted from the app at all.
- A **quota could be set but never cleared** — the empty field sent nothing, which
  the server reads as "leave unchanged". `clear_quota` is now sent.
- The list **could not scroll**, and pull-to-refresh did nothing.
- The **protected administrator** is protected in three layers: UI, `admin_user_rules.dart`,
  and the server (authoritative). A refused action shows the server's human-readable
  reason instead of failing silently.
- Delete went through a confirmation flow rather than a single tap.

Two further bugs were caught by the new tests rather than by reading: a **7.9 px
`RenderFlex` overflow** on the role dropdown at 390 dp, and the empty state's dead
vertical space (root cause: `OneUiEmptyState` centring itself — see §5).

Status: FIXED. Not verified: any layout below 360 dp width, and tablet master–detail.

## 4. Update Center

The 16 required states were audited: 14 already existed and were preserved. The real
gap was **paused**. That is now a genuine resumable download — `Range: bytes=N-`,
re-hashing the partial so the SHA-256 still covers the whole file, and rejecting a
checkpoint that disagrees with what is on disk. The `.part` file and its checkpoint
survive cancellation. Controls are Pause / Resume / Discard, and a golden test caught
that a **paused** download was rendering an *indeterminate* bar — animating forever
and reading as "still working" — when its progress is known and static. FIXED.

No update history is shown, because no endpoint provides one; inventing it was
rejected. Status: PARTIAL.

## 5. The debug-baseline underlines

Not typography. `RenderBox.debugPaintBaselines` paints amber (ideographic) and green
(alphabetic) baselines inside `assert(() { … }())`, so release builds cannot draw them.
Proven by rendering both reported screens with the flag off and on: 83 green-family and
116 amber-family blends with it on, **zero** of either with it off. `lib/` has no
`debugPaint*` and no `TextDecoration`. A guard test now fails the build if a debug-paint
flag is ever enabled. VERIFIED.

## 6. Login

An integration run flagged a hit-test target outside the render tree. Reproduced
deterministically:

| Viewport | "Sign in" bottom | Overflow |
| --- | --- | --- |
| 1280×464 | y=538 | **74 px past the fold** |
| 640×360 | y=538 | **178 px past the fold** |

`SingleChildScrollView` made it technically scrollable while leaving the primary action
off-screen with no affordance. Below 620 px the fields now scroll and the button pins to
the visible area, which also keeps Sign in above the on-screen keyboard. 9 tests. FIXED.

## 7. Sync engine

See `docs/FINAL_ENGINEERING_AUDIT.md` §4 for the full matrix and the three fixed
defects. Summary: a remote deletion was undone on the next sync; a remote delete without
a tombstone dropped the baseline silently; and sync drove the user's manual transfer
queue, which both polluted it permanently and silently retried a *failed* upload as a
side effect of the next file.

VERIFIED (26 tests) as a deterministic single-client matrix.
NOT TESTED: live two-device convergence, clock skew, real network interruption.

## 8. Device management

The duplicate-row root cause was already fixed in the preceding pass and is unchanged:
identity is now created **locally, before any request**, memoised through one shared
future, and `sync()` is guarded process-wide; the server adopts an unknown id verbatim
(so a concurrent-first-sync collision is success, not a duplicate), never hijacks an id
owned by another account, and reuses an existing row for the same name+platform when no
id is supplied. Covered by 7 identity tests here (including that two concurrent first
syncs produce exactly one manifest/delta call and one announced id) plus 6 server tests.

**No device-linking flow was implemented.** The brief asks for a device-code flow; that
needs a server-side endpoint which does not exist, and building fake UI for it was
explicitly ruled out. Status: NOT TESTED / not implemented.

## 9. Images

The decode policy was root-caused in the preceding pass (`image_decode_policy.dart`
plus a dedicated decoder): thumbnails are decoded to their target size while the
full-screen viewer decodes at an extent-appropriate resolution rather than a thumbnail's,
so the blur is not a widget-size or `filterQuality` artefact. Covered by
`image_decode_policy_test.dart` and `image_pipeline_test.dart`. FIXED (policy level).
NOT TESTED: 4K / DSLR / WebP runtime rendering — no sample media or device here.

## 10. Server

| Area | Status |
| --- | --- |
| Sync device identity (adopt unknown id, no hijack, collision = success) | FIXED + 6 tests |
| Account-protection policy as a pure, fully branch-tested function | FIXED + tests |
| Session-revocation endpoint | FIXED |
| Streaming, Range, resumable uploads, SQLite tuning, backup/restic, CORS, headers, rate limits | REVIEWED — read and traced, not modified |
| Live read-only probes (401 on protected routes, 404 on share, security headers present) | VERIFIED |

No index, query plan, streaming path or backup procedure was altered. They were not
measured under load, and changing load-bearing code without the ability to load-test
would be risk without evidence. No performance claim is made.

## 11. CI/CD and the release channel

Audited, unchanged. The release APK is **debug-key signed** because `key.properties` is
absent: the build script deliberately falls back so `--release` does not hard-fail.
That is acceptable for local testing and **must not** become the production mechanism —
CI must sign with a keystore held in secrets. No key or credential is in the tree.
PARTIAL (documentation only).

## 12. Known limitations

1. **No Android runtime testing.** No device or emulator. Both APKs build; nothing ran.
   ENVIRONMENT BLOCKED.
2. **No authenticated live-server flows.** Signing in as the production admin writes a
   session row and an audit entry into the live database, so it was deliberately not
   done. ENVIRONMENT BLOCKED pending your go-ahead.
3. **Sync convergence is single-client only.** NOT TESTED.
4. **Per-screen restructure is incomplete.** 4 screens restructured; the remainder keep
   their layout and inherit the shared-widget fixes. PARTIAL — this is the largest
   remaining gap.
5. **No device-linking flow**, no update history, no tablet master–detail. NOT IMPLEMENTED.
6. **No performance, load, or penetration testing** was performed. NOT TESTED.
7. Scanner screens were not exercised at all. NOT TESTED.

## 13. Archive

`dist/NexaDrive-production-review-20260918.zip` — see the delivery message for size,
file count and SHA-256. Contains source, config and docs only: no database, no WAL/SHM,
no `server/.env`, no keystore, no secrets, no `build/`, no `.dart_tool/`, no
`server/target/`.

---

## 14. Server activation — RUN THESE COMMANDS AFTER YOU APPROVE THE BUILD

**Nothing below has been executed.** The new binary is staged at
`server/target/release/nexadrive-server` and the running process still holds the old one.

```bash
# 1. Pre-flight: the data partition must be mounted and writable.
mountpoint -q /mnt/data3 && echo "MOUNTED" || echo "STOP: /mnt/data3 not mounted"
touch /mnt/data3/nexadrive/.preflight && rm /mnt/data3/nexadrive/.preflight && echo "WRITABLE"

# 2. Back up the database before touching anything (online-safe copy).
DB=/mnt/data3/nexadrive/data/nexadrive.db
STAMP=$(date +%Y%m%d-%H%M%S)
sqlite3 "$DB" ".backup '/mnt/data3/nexadrive/backups/nexadrive-$STAMP.db'"
sqlite3 "/mnt/data3/nexadrive/backups/nexadrive-$STAMP.db" "PRAGMA integrity_check;"
ls -la "/mnt/data3/nexadrive/backups/nexadrive-$STAMP.db"

# 3. Confirm the staged binary is the freshly built one.
ls -la /mnt/data3/nexadrive/server/target/release/nexadrive-server
sha256sum /mnt/data3/nexadrive/server/target/release/nexadrive-server

# 4. Stop the service and confirm the process is gone.
sudo systemctl stop nexadrive.service
systemctl is-active nexadrive.service || true
pgrep -af nexadrive-server || echo "process stopped"

# 5. Start the new binary.
sudo systemctl start nexadrive.service
systemctl status nexadrive.service --no-pager

# 6. Confirm the running process is the new binary.
systemctl show nexadrive.service -p MainPID -p ExecStart
sudo lsof -p "$(systemctl show nexadrive.service -p MainPID --value)" | grep -m1 nexadrive-server

# 7. Logs.
journalctl -u nexadrive.service -n 100 --no-pager
journalctl -u nexadrive.service -f

# 8. Health.
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/health
curl -sS http://127.0.0.1:8080/health

# 9. Tailscale endpoint (adjust the hostname to your existing Serve hostname).
tailscale serve status
curl -sS -o /dev/null -w '%{http_code}\n' https://<your-tailnet-host>/
```

### Rollback

```bash
sudo systemctl stop nexadrive.service
cp /mnt/data3/nexadrive/backups/nexadrive-$STAMP.db /mnt/data3/nexadrive/data/nexadrive.db
sudo systemctl start nexadrive.service
```

`nexadrive.service` reads `/etc/nexadrive/server.env`. Neither that file nor the
Tailscale configuration was read, changed, or included in the archive.
