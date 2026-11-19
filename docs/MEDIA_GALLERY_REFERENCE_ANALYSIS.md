# Media gallery reference analysis (internal)

This note records the product patterns studied for the NexaDrive gallery and
file-browser redesign. It is an internal design record: no source code, assets,
dependencies or platform chrome were copied from the reference apps. Everything
adopted below is expressed with NexaDrive's own Material 3 `App*` tokens and
`Nexa*` components.

## References studied

- Ente Photos
- Immich
- Aves
- Filebrowser Quantum (`filebrowser_mobile`)
- CrispCloud
- shutr
- Waydir
- NFile
- Current Google Photos behavior reporting and official Google Photos help

## Patterns adopted

### Gallery structure

- Dense, edge-to-edge media grid with a very small gutter. NexaDrive uses
  `AppDimens.space2` and a user-selectable column count (3 by default).
- Month grouping, newest first, with a compact count badge. This comes from
  Immich, Aves and shutr date bucketing, rebuilt with `AppTextStyle` and M3
  tonal roles.
- Selection replaces browsing context with a contextual action surface:
  close, count, select-all, share and destructive trash. This follows the
  common pattern in Ente, Immich and CrispCloud while keeping NexaDrive's
  floating pill mounted.
- A destructive selection action always asks for confirmation before the
  batch request. Moving to Trash uses `showNexaConfirmation(..., isDestructive:
  true)`.
- Media tiles distinguish photos, videos and PDFs with a semantic label and a
  small type badge. The thumbnail endpoint now renders first-frame/first-page
  JPEGs for videos and PDFs when the server has `ffmpeg` / `pdftoppm`; otherwise
  the type badge and glyph remain the honest fallback.

### Viewer routing

- Images continue to use the existing full-resolution `PhotoViewer`, but it now
  receives only image siblings so swiping cannot land on a PDF or video.
- Videos and PDFs use the app's single `FileOpener`, which already routes to
  `VideoPlayerScreen` and `PdfViewerScreen`. No second viewing path was added.

### Files and transfers

- Files keeps one compact title row: search plus a single overflow menu.
  Upload, new folder, scan, sort and view switching live in that menu.
- File and transfer rows are flat, grouped M3 surfaces with dividers rather
  than one elevated card per row.
- Completed transfers are transient: the manager prunes them from memory and
  the journal, and the screen filters them immediately.

### Motion and feedback

- The floating pill remains the NexaDrive signature. It is narrowed to
  `AppDimens.bottomNavMaxWidth`, uses near-critical spring damping, a plain
  travelling tonal indicator, and a Material state-layer press response.
- Motion is interruptible and starts from the live animation value. Reduced
  motion still resolves through `AppMotion`, so springs become snaps and
  transitions become short fades.
- The velocity-based rubber stretch and icon scale pop were removed: they read
  as a "jelly" effect on a small navigation control.

## Explicitly not adopted

- No custom navigation packages, icon fonts, glass materials, per-app color
  systems or copied shadows.
- No opaque platform navigation chrome, iOS toolbars or One UI conventions.
- No hardcoded colors, radii, durations or destructive red literals in screens.
- No new dependencies.

## Outcome

The resulting interface uses one authoritative design system and preserves all
existing backend contracts and user data flows while matching the reference
apps' useful interaction patterns: dense media browsing, predictable
selection, compact chrome, flat rows and calm physical motion.
