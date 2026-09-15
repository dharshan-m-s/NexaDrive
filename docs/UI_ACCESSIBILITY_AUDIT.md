# NexaDrive UI — Accessibility Audit (current build)

> Fact-based audit of the 1.1.0 UI. Ratios computed from hex via WCAG relative
> luminance (sRGB, gamma-space math); all marked values are **[computed]**.
> Structural notes are statements of code facts, not opinions.

WCAG quick-reference thresholds: AA normal text 4.5:1 · AA large text 3.0:1 ·
UI/non-text 3.0:1 · AAA normal 7.0:1.

---

## 1. Color-contrast matrix (computed from AppColors)

### Light mode
| Foreground | On | Ratio | Verdict |
|-----------|----|-------|---------|
| textPrimary #1A1C1E | surface/background (#FFFFFF/#F7F8FA) | 16.1–17.0:1 | AAA+ |
| textSecondary #5B5F66 | backgrounds (#FFFFFF/#F2F3F5) | 5.8–6.4:1 | AA+ |
| textTertiary #8A9099 | background #F7F8FA | 3.0:1 | **fails AA text (~borderline)** |
| textTertiary #8A9099 | surface #FFFFFF | 3.2:1 | **fails AA text (passes large)** |
| textTertiary #8A9099 | surfaceAlt #F2F3F5 (`listHeader` on inputs) | 2.9:1 | **fails 3.0 non-text too** |
| accent #0B87D0 | white (links/outlined/text buttons, labelText) | 3.9:1 | **fails AA normal text (16-14px)**; passes large |
| white (textOnPrimary) | accent #0B87D0 (FilledButton) | 3.9:1 | **fails AA normal text (button 16px w600)** |
| onAccentContainer #0A5E8F | accentContainer #E1F1FA | 6.0:1 | AA+ |
| accent #0B87D0 | accentContainer #E1F1FA (selected NAV label/icon) | 3.4:1 | icon ok (3.0); **label 11px fails AA** |
| success #23641E / error #B3261E / warning #B25E00 | white | ~6.5 / 6.5 / ~4.4* | AA (warning ≈4.4 marginal `[EST]`) |
| textPrimary | accentContainer #E1F1FA (unread notif) | 14.8:1 | AAA |

### Dark mode
| Foreground | On | Ratio | Verdict |
|-----------|----|-------|---------|
| textPrimary #F6F7F8 | #000000 | ~17.6:1 `[EST]` | AAA |
| textSecondary #B8BDC3 | #000000 / surface #1D1E1F | 11 / 8.7:1 `[EST]` | AAA/AA |
| textTertiary #7D838C | pure black | 5.5:1 | AA |
| textTertiary #7D838C | surface #1D1E1F | 4.4:1 | **fails AA (borderline)** |
| textTertiary #7D838C | surfaceAlt #232425 | 4.1:1 | **fails AA** |
| accentDark #6CC4F7 | #000000 | ~10.4:1 `[EST]` | AAA |
| textOnPrimaryDark #001D33 | accentDark #6CC4F7 | 8.9:1 | AAA |
| onAccentContainer #9AD4F7 | accentContainer #123A55 | 7.5:1 | AAA |
| accentDark | accentContainer #123A55 (selected NAV label) | 6.2:1 | AA+ |
| error #FF5449 / success #7BD46A | #000000 | ~9.4 / ~9.2 `[EST]` | AAA |

### Gaps that matter (single list)
1. **Light accent-on-white text = 3.9:1** → TextButton, OutlinedButton, links,
   floating labels, breadcrumb ancestors (accent), pending-tile "Your files are safe."
   (warning ~4.4:1) — all below AA for normal text. The README of the palette itself
   says accent should be used for text/icon emphasis; contrast is the trade-off.
2. **Light 11px selected nav-bar label** accent on accentContainer = 3.4:1 → below 4.5.
3. **Tertiary cascade** (12/13px metadata, list headers, waiting state, sync subtitles):
   2.9–3.2:1 light, 4.1–4.4:1 dark — sub-AA for the sizes actually used.
4. Disabled FilledButton: accent@40% over white with white@80% text ≈ 1.7:1
   `[EST composite]` (exempt from WCAG but nearly invisible bound to `disabled`).

---

## 2. Touch-target audit (48dp guideline)

| Control | Actual hit area | OK? |
|---------|-----------------|-----|
| IconButton (header, list, shells, sheets) | Material default **48×48** | Yes |
| Filled/Outlined/TextButton | min 64×48 (buttons often 48–52 tall) | Yes |
| Login Sign in | 56 tall | Yes |
| _SelectionBar actions | ~48–56 | Yes |
| _SheetAction rows | 52 | Yes |
| _SheetTile rows | 60 | Yes |
| OneUiGroupTile/FileTile rows | minTileHeight 60 | Yes |
| Folder row InkWell | padding v10 + icon+2 lines ≈ **~46–50** `[EST]` | Borderline |
| **Breadcrumb crumbs** | `GestureDetector` wraps only the Text node (12px line) → **<20px tall hit area** `[EST]` | **No** |
| Grid tile (photo/file) | full tile (≥ ~120×120) | Yes |
| PhotoViewer bottom bar | IconButton 48 | Yes |
| Empty-state "Open My files" / retry buttons | FilledButton≥48 | Yes |

Breadcrumb (files_screen `_Breadcrumb`: crumb = GestureDetector→Center→Container→Text),
doesn't add padding/material ink → smallest target in the app.

---

## 3. Color-independent encoding (checked)

- Selection: checkbox/radio icon-shaped + accent border 1.5/1.8 + tile tint → 3 cues. OK.
- Notification unread: container fill + icon color + **font weight w600 vs w400** + a
  trailing button. Not color-only. OK.
- File type: category icon **+** tint **+** subtitle text (size/Folder/File). OK.
- Share permission: SegmentedButton with text labels. OK.
- Upload statuses: icon + title + progress + text. OK.
- Trash/restore/secondary icons: all carry `tooltip` (semantics). OK.
- Theme mode: text labels in dialog. OK.

---

## 4. Semantics & TalkBack

- Built on Material (`ListTile`, `NavigationBar`, `FilledButton`, `IconButton`, …) so
  the standard semantics tree, traversal order, and platform announcements come free.
- Icon-only buttons all have `tooltip` → exposed as semantics label.
- Login fields set `autofillHints` (url/username/password) + input actions + enter submit.
- **Gaps:**
  - Photo grid tiles expose no semantic label (just "Image"/blank). Viewer image no
    long description.
  - `InteractiveViewer` zoom affordance unlabeled.
  - Breadcrumb items are plain `Text` inside GestureDetector → screen readers announce
    only the label, no "button" role, no tap action.
  - Selection-mode state is conveyed only visually (title swaps to "N items"); no
    `Semantics(liveRegion)` announcement, no explicit "selection mode" semantics.
  - Upload dialog progress aria: per-file bars are plain LinearProgressIndicator
    (Material gives value semantics), but the "Uploading…" status row is an
    AnimatedSwitcher without live-region semantics.
  - File rows don't include the role/tooltip of the ⋮ menu in the row's own semantics
    (the IconButton is separate – acceptable).

---

## 5. Keyboard & focus (desktop path)

- All Material controls are focusable; Tab order follows tree order (header actions →
  body rows → selection bar). Sidebar items and icon buttons reachable.
- **Gaps:** breadcrumbs are GestureDetector-only → no Tab focus, no Enter activation.
  Photo grid tiles are GestureDetector-only (no focus/enter); viewer actions are buttons.
  Long-press-only entry into selection mode (i.e., no keyboard accelerator for
  multi-select) — on Windows/Linux the only multi-select path is mouse long-press.
- No custom shortcuts; Ctrl+F (search), Ctrl+A (select all), Delete (trash) not mapped.
  Search endpoint exists (`/api/files/search`) but no search UI at all.

---

## 6. Reduced motion

- `AppMotion.reducedMotion(ctx)` / `resolve(ctx, d)` exist but **no caller found** in
  the widget tree (`[EST]` grep-sourced). Home's TweenAnimationBuilder uses
  `AppMotion.normal` unconditionally; the shell page cross-fade is a raw 200 ms.
- Material sheets/dialogs/RefreshIndicator/route transitions follow the engine's
  platform disable-animations settings automatically — so Android "Remove animations"
  only partially flattens the app (raw AnimatedSwitcher + progress tweens continue).

---

## 7. Text scaling & font size

- All text uses the system font with fixed logical px; Flutter scales by
  `textScaler`/platform font scale (Samsung One: 1.0…2.0+). Height/leading stays.
- **Fixed-height containers are not scale-aware:**
  `_SheetAction` height 52, `_SheetTile` height 60 (but status tiles use ListTile
  minTileHeight which can grow), `_BarAction` column, `_TransferRow` paddings,
  `_StorageTile` loading height 96, `_Breadcrumb` container height 40, one-line
  ellipsis everywhere (row title/caption `maxLines:1`) — at 1.3–2.0× scale, list rows
  will clip or ellipsize; none of the screens tested this path.
- `maxLines:1` + ellipsis on rowTitle/caption means long file names / sync paths
  truncate at default scale already (by design; no hover-expand).

---

## 8. Platform compliance quick notes

- Login card is scrollable (keyboard-safe), single column, presentational-only brand
  image (icon → semantics "cloud"). OK.
- Bottom sheet drag handle present (`showDragHandle:true`) → gesture affordance.
- Dialogs are all barrier-dismissible (`showDialog` default) except the upload dialog
  (`barrierDismissible:false`, PopScope back-cancel) — intentional modal.
- Status feedback: all async ops end in snackbar or empty/error state; no silent
  failures observed in code paths (transfers row shows inline error text).
- Focus/scroll traps: none found; sheets are single-scroll; photo PageView is
  horizontal paging — a horizontal swipe list inside vertical autoscroll region only
  on Photos grid, which is vertical → no conflict.

---

## 9. Top accessibility fixes a future design spec should call for (fact-backed)

1. Raise the light-theme accent-on-white text path (links/buttons/labels) to ≥4.5:1 —
   either darken `accent` for text roles or add an `onSurfaceLink`/`onSurfacePrimaryText`
   token. Do NOT change the FileKind/filled-button fills without re-auditing ratios in §1.
2. Tertiary gray: either darken (light → ~#6E747D, dark → ~#9AA1AA `[EST]`) or upgrade
   tiers when used for 12–13px informational text; currently sub-AA in both modes.
3. Give breadcrumbs proper `TextButton` hit area + focus + role semantics.
4. Add semantics to photo tiles, `liveRegion` to upload status, and selection-mode
   announcements; keyboard multi-select on desktop.
5. Make fixed-height `_SheetAction/_SheetTile/_BarAction/_TransferRow/_Breadcrumb`
   use content margins that grow with `textScaleFactor` (e.g. `MediaQuery.textScalerOf`).