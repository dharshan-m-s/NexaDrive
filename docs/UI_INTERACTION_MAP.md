# NexaDrive UI — Interaction Map

> Every reachable interaction in the current app, its trigger surface, and its
> effect. Line-accurate to 1.1.0. No redesign intent.

---

## 1. Navigation graph

```
LoginScreen
   │ pushReplacement (success) / pushAndRemoveUntil (logout, 401 clear)
   ▼
AppShell  (index 0..5 in-place swap; desktop sidebar / mobile bottom nav)
   0 Home                1 My files          2 Shared           3 Photos
   5 Settings            4 Trash (mobile bottom: via More sheet; desktop: sidebar)
   │
   ├─ push → TransfersScreen        (Home pending-tile, nav, More, Settings)
   ├─ push → SyncCenterScreen       (nav "Sync center", More, Settings)
   ├─ push → NotificationsScreen    (nav "Notifications", More, Settings)
   ├─ push → AdminUsersScreen       (Settings → Admin → Users)
   ├─ push → AuditLogScreen         (Settings → Admin → Audit log)
   └─ push → SharedBrowseScreen     (Shared → "Shared with me" row)
        └─ nested push (per folder) into the SAME SharedBrowseScreen instance (state update)
   from My files:
        └─ push → PhotoViewer         (image tap; dataset = all images of current folder)
             └─ showModalBottomSheet → FileShareSheet
        ├─ push → TextViewerScreen    (text tap)
        └─ push → Pdf/Audio/Video download screens (pdf / audio / video tap)
```

Deep links: none. There is no url-launcher / route table; server links copied to clipboard
are not clickable app deep-links (the share link `/api/share/<token>/download` is only
intended for external browsers). Back-gesture = Flutter default route pop (Android
predictive back uses `PopScope` only in UploadProgressDialog).

---

## 2. Shell-level interactions

| Gesture | On | Effect |
|---------|----|--------|
| Tap | SideNavItem (desktop) | `index = n`, cross-fade page (AnimatedSwitcher 200ms easeOut/in) |
| Tap | OneUiBottomNav destination | index 0–3 selects; **4 "More" opens modal sheet** (nav item never selected) |
| Tap | More sheet "Scan document" | pops sheet; **nothing else happens** (no camera) |
| Tap | More sheet "Trash"/"Settings" | pops sheet; sets `index = 4 / 5` |
| Tap | More sheet "Transfers/Sync center/Notifications" | pops sheet; pushes the target screen |
| Long-press | (none in shell) | — |
| System back | mobile | pops More sheet if open, else pops pushed routes; in-shell pages swap index with history? **no** — back on mobile at index>0 returns to whatever the OS does with a single-route Activity; page index is state, not a route (see §7 debt) |

## 3. Home
| Trigger | Effect |
|---------|--------|
| Tap storage tile | no-op (static card) |
| Tap Upload / New folder / Files tile | `onNavigate(1)` → My files |
| Tap Photo library tile | `onNavigate(3)` → Photos |
| Tap pending tile | push TransfersScreen |
| Tap "Open My files" (Recent) | `onNavigate(1)` |
| Pull-to-refresh | Home has NO RefreshIndicator |

## 4. My files — file browser
| Trigger | State | Effect |
|---------|-------|--------|
| Tap folder row | normal | navigate into folder (path state + reload; parent title becomes leaf) |
| Tap file row | normal | open via category matrix (PhotoViewer/Text/Download-to-view/unsupported sheet) |
| Tap row | selection | toggle selection |
| Long-press row | normal | enter selection mode (adds path) |
| Tap header list/grid | normal | toggle grid/list |
| Tap header new-folder | normal | New folder dialog → create at current path → reload |
| Tap header upload | normal | FilePicker multi → UploadProgressDialog → reload after close |
| Tap header up arrow | deep | back to My files root |
| Tap header close | selection | exit selection (clears set) |
| Tap "Back to My files" | selection+deep | exit selection AND jump to root |
| Tap breadcrumb | deep | jump to any ancestor path |
| Tap row ⋮ | normal | file menu sheet |
| Tap sheet Details/Share/Download/Move/Rename/Trash | — | opens respective surface / runs action |
| Tap selection-bar Trash/Move/Copy/Share/Save | selection | bulk action (dialogs where needed) |
| Tap selection-bar ✕ | selection | exit selection |
| Swipe (pull down) on list/grid | — | reload current path |
| Scroll | — | plain vertical ListView/GridView |

Selection mode rules: toggling items keeps the set; actions iterate `_selected` paths;
folder selection is allowed (move/copy/delete/share); share on N>0 lists entries;
"Save" downloads each sequentially (one save-picker per file).

## 5. Dialogs triggered from My files
- New folder: Enter submits; Create commits trimmed name; Cancel/Esc closes.
- Rename: prefilled; Enter/Rename commits trimmed; empty → ignored; conflicts → snackbar.
- Move to Trash: single → "Move <name> to trash?" / multi → "Move N items to trash?";
  Trash commits `batch(delete)`; Cancel closes.
- Remove share (from Shared "Mine"): same 2-option confirm.

## 6. Photo viewer
| Gesture | Effect |
|---------|--------|
| Tap | no-op (no chrome toggle — AppBar & bottom bar always visible) `[EST]` |
| Horizontal swipe | PageView to next/prev photo; `_onPageChanged` prefetches ±1; counter updates |
| Pinch / pan | InteractiveViewer zoom ≤ 5×, pan within bounds; no double-tap-to-zoom, no rotation |
| Tap Download / Save to My files | FilePicker.saveFile → downloadToFile → snackbar "Saved to <path>" |
| Tap Share | FileShareSheet bottom sheet for current photo |
| System back | pops viewer to previous screen |

## 7. Shared
- With me: tap row → load `sharedItems(shareId, '')` → push SharedBrowseScreen (state.new);
  nested folder taps mutate the SAME screen's path state (no stack entry per folder).
- Shared browse: up arrow (one level), folder rows drill-down, file rows download.
- Mine: tap → none (only trailing delete). Delete → Remove share confirm.
- Both tabs re-load on `load()`; segmented toggle reloads nothing (same cached list is
  filtered client-side via `_mine` — `shared()` and `shares()` are both fetched upfront).

## 8. Photos screen
- Tap tile → PhotoViewer at index; tap refresh; pull-to-refresh reloads list + rewarm
  thumbnails (first 40). Grid scroll is plain vertical.

## 9. Trash
- Restore: direct (no confirm). Delete forever: confirm → perma-delete.
- Tap row body: no-op. Pull-to-refresh.

## 10. Settings
- Appearance → dialog (System/Light/Dark) → `session.setThemeMode` (persists, hot-swaps
  MaterialApp themeMode via ListenableBuilder).
- Connected to → copy address (clipboard + snackbar) / Done.
- Users/Audit log push admin screens (role-gated render at build).
- Sign out → confirm → `api.logout()` (server + clear) then pushAndRemoveUntil Login.
- 401 anywhere (any screen) → `onUnauthorized` → toast "Session expired. Please sign in
  again.", clear session, root to Login. Guarded to run once.

## 11. Transfers
- Process queue button runs `TransferQueue.process` (resume multi-chunk).
- Row pause (uploading): `queue.pause(id)` then re-process.
- Row retry (failed): `queue.reset(id)` then re-process.
- Row remove (any non-active): dialog confirmed; verified delete of queue item.
- Clear completed: sweep button.
- Tap row text: no navigation (only row trailing actions are interactive).

## 12. Sync center
- Choose → native folder picker → set folder (persists).
- Unlink → clears folder.
- Sync now → runs sync; progress line updates via callback; snackbar summary on >0.
- Revoke device → API delete + local removal.

## 13. Notifications
- Mark read on unread rows; Mark-all-read; segmented All/Unread reloads the API.

## 14. Admin
- Users: lock toggle enable/disable; New user dialog with Create (username/display/pass
  ≥8/role/quota GB). Audit: refresh.

## 15. Text viewer / PDF / Video / Audio
- Text: SelectableText (long-press to copy `[EST]`), autoscroll with page; no links.
- PDF/Video/Audio: single Download button → save picker → "Saved to …". No players.

---

## 16. Motion inventory (exact durations/curves)

| Motion | Animation | Duration | Curve |
|--------|-----------|----------|-------|
| Page swap (shell index + cross-fade) | `_PageHost` AnimatedSwitcher | 200 ms | out = easeIn, in = easeOut |
| Storage usage bar (appears) | TweenAnimationBuilder 0→fraction | `normal` 300 ms | `standard` Cubic(0.25,0.1,0.3,1) |
| Upload dialog status swap | AnimatedSwitcher | 180 ms hardcoded (not AppMotion) | default |
| Sheet show (/hide) | Material showModalBottomSheet | platform default `[EST]` ~250/200 | Material curve `[EST]` |
| Dialog show | showDialog | platform default `[EST]` | platform |
| Press ripple | InkSparkle / InkWell | Material `[EST]` ~200 | splash |
| Pull-to-refresh | RefreshIndicator | Material ~145/200 fps clamp `[EST]` | spring, system |
| Page route push/pop | FadeForwards (Android/Linux/Win), Zoom (iOS/macOS) | Material defaults `[EST]` | per builder |

Debt: the 200 ms cross-fade and 180 ms status swap are hardcoded `Duration` literals and
do NOT source from `AppMotion`; sheets/dialogs use Material default motion rather than
the One UI enter/exit tokens; InteractiveViewer zoom uses Flutter default springiness.
`AppMotion` helpers (`defaultSwitcher`, `resolve`) exist but are largely unused (`[EST]`):
source search shows `AppMotion` imported only in `home_screen.dart`.

---

## 17. Missing / dead interactions (checked, factual)

- **Camera / document scanner: NOT implemented.** "Scan document" tile pops with no
  action; pubspec has no camera dependency.
- No in-app PDF/video/audio playback; download-first only.
- Home has no pull-to-refresh; photo viewer has no chrome-hide / double-tap zoom; file
  list has no swipe-to-remove, no drag-and-drop reorder (relevant only to folder moves —
  move is menu/selection driven); no context menu right-click on desktop (deselected —
  `showFilesMenuFor` exists but is only used for image preview in shared flows);
- `showFilesMenuFor` is effectively dead API surface for its menu purpose — it only
  opens the photo viewer (`files_screen.dart:947`).
- `FileEntry.pinned` / `offlineAvailable` fields exist in the model and details sheet
  has an "Offline / Available on this device" branch, but no client action sets them
  (no pin UI, no offline storage) — the branch is unreachable in practice `[EST]`.
- No search UI at all (`/api/files/search` handler exists server-side; nothing calls it).