# NexaDrive documentation index

This directory accumulated a lot of writing over the project's build-out. This
index separates what is **current** (describes the code as it is now) from what is
**historical** (a point-in-time snapshot, kept as a record of how the project got
here rather than as a specification).

If a historical document and the source disagree, the source wins.

## Reference — current

Read these first. They describe behaviour that exists today.

| Document | Covers |
| --- | --- |
| [`API.md`](API.md) | The complete HTTP contract: every route, parameters, status codes, path-safety rules. |
| [`DEPLOYMENT.md`](DEPLOYMENT.md) | Server deployment, filesystem layout, systemd, Tailscale Serve / reverse proxy, `/mnt/data3`-style data placement. |
| [`SECURITY.md`](SECURITY.md) | The security model and the product rules that constrain it. |
| [`SQLITE.md`](SQLITE.md) | Embedded SQLite deployment (WAL, busy timeout, why there is no DB daemon). |
| [`UPDATE_SYSTEM.md`](UPDATE_SYSTEM.md) | Updater architecture, manifest schema, checksum/allowlist security model. |
| [`UPDATER_TROUBLESHOOTING.md`](UPDATER_TROUBLESHOOTING.md) | Diagnosing and fixing updater failures. |
| [`PLATFORM_SUPPORT.md`](PLATFORM_SUPPORT.md) | Supported platforms, install types, per-platform update flows. |
| [`RELEASE_PROCESS.md`](RELEASE_PROCESS.md) | How a release is dispatched, built, verified and published. |
| [`GITHUB_ACTIONS.md`](GITHUB_ACTIONS.md) | What each CI and release workflow job does, and which secrets it needs. |
| [`FILE_FORMAT_SUPPORT.md`](FILE_FORMAT_SUPPORT.md) | Which file types render, preview or download. |
| [`APP_QA_CHECKLIST.md`](APP_QA_CHECKLIST.md) | Manual QA pass for the client. |
| [`../app/doc/diagnostics/`](../app/doc/diagnostics/) | Root-cause write-ups for specific reported bugs. |

## Design system — current

The One UI-inspired visual language and its tokens. These describe the shared
widgets under `app/lib/core/design` and `app/lib/ui/widgets`.

| Document | Covers |
| --- | --- |
| [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md) | Principles, surfaces, colour roles, typography. |
| [`COMPONENT_LIBRARY.md`](COMPONENT_LIBRARY.md) | The `OneUi*` primitives. |
| [`UI_DESIGN_TOKENS.md`](UI_DESIGN_TOKENS.md) | Exact token values. |
| [`UI_SCREEN_SPECIFICATION.md`](UI_SCREEN_SPECIFICATION.md) | Screen-by-screen layout specification. |
| [`SCREEN_SPECIFICATIONS.md`](SCREEN_SPECIFICATIONS.md) | Older, shorter screen notes — superseded by the above where they overlap. |
| [`RESPONSIVE_LAYOUT.md`](RESPONSIVE_LAYOUT.md) | Breakpoints and adaptive behaviour. |
| [`INTERACTION_MOTION.md`](INTERACTION_MOTION.md) | Motion and transition rules. |

## Historical — point-in-time records

These were accurate when written and are **not** maintained. Several overlap or
directly contradict each other (there are eight successive "final audit"
reports). They are kept because they document the reasoning and the evidence
behind past decisions; they should not be read as current specifications.

- `AUDIT.md`, `FINAL_AUDIT.md`, `FINAL_PRODUCTION_AUDIT.md`,
  `FINAL_PRODUCTION_QA.md`, `FINAL_PRODUCTION_READINESS_REPORT.md`,
  `FINAL_REPOSITORY_AUDIT.md`, `FINAL_ENGINEERING_AUDIT.md`,
  `../ENGINEERING_REPORT.md` — audit snapshots from successive hardening passes.
- `PHASE3.md` … `PHASE9.md`, `PHASE10_AUDIT.md` — incremental build logs.
- `FINAL_RELEASE.md`, `RELEASES.md`, `ROADMAP.md` — release/roadmap notes.
- `SECURITY_AUDIT.md` — the long-form security audit behind `SECURITY.md`.
- `PERFORMANCE_AUDIT.md`, `UI_PERFORMANCE_AUDIT.md`, `UI_ACCESSIBILITY_AUDIT.md`,
  `UI_RESPONSIVE_AUDIT.md`, `UI_INTERACTION_MAP.md`, `UI_REVERSE_ENGINEERING.md`,
  `UI_COMPONENT_INVENTORY.md`, `UI_REDESIGN_AUDIT.md`,
  `NEXADRIVE_CURRENT_UI_COMPLETE_INVENTORY.md`, `ONE_UI_REDESIGN_REPORT.md`,
  `ONE_UI_REFERENCE_NOTES.md`, `VERIFICATION_A11Y.md` — the UI
  reverse-engineering and redesign passes.

If you want the repository to hold only current documentation, this third group
is the list to remove; every file in it is still available in git history.
