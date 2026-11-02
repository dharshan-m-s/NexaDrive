# NexaDrive Premium UI Redesign — Coverage and Scope

**Branch:** `beta`  
**Design direction:** One UI-inspired visual hierarchy and card composition, with native iOS interaction discipline.  
**Glass rule:** Preserve optical Liquid Glass for the floating navigation dock and transient controls/sheets. Keep persistent content surfaces tonal, readable and data-led.

This document is the explicit coverage register for the current redesign. A page is not considered redesigned merely because its title color or typography changed. Shared components are counted as applied where the screen actually uses them.

## 1. Screen-by-screen coverage

| Screen / route | Redesign applied | Notes |
|---|---|---|
| Login | Brand mark, layered identity treatment and grouped credential surface | Existing authentication, 2FA and session behavior preserved. |
| Home | Storage overview hero and quick-action tiles | Storage overview remains the entry point to Storage Insights; no Storage Insights card was added to More. |
| Storage Insights | Dedicated analytics page and data-driven chart surfaces | Charts continue to represent actual storage data; chart gradients are data visualization, not decorative card fills. |
| My files | Custom page header/action area, thumbnail-led grid cards and type-led file artwork | Existing list/grid, folder navigation, selection, upload and file actions retained. |
| File details | Contextual sheet header and shared action-row treatment | Existing metadata and actions retained. |
| File properties | Contextual sheet identity and shared sheet surface | Existing property data and actions retained. |
| Share sheet | Contextual share icon/header and shared action treatment | Existing share-link and recipient behavior retained. |
| Shared | Page identity, grouped-list and list-row surface system | Existing With me / Shared by me behavior retained. |
| Shared folder browse | Folder-specific page identity and shared navigation controls | Existing folder browsing and permissions behavior retained. |
| Photos | Page identity, selection/list surfaces and shared file visual language | Existing photo grouping and selection behavior retained. |
| Photo viewer | Immersive full-bleed presentation, optical top/bottom controls and filename/position context | Existing swipe, zoom, save, share and Trash actions retained. |
| Trash | Page identity and a neutral content surface for recovery summary | Static summary is no longer presented as a glass content card. Restore/permanent-delete behavior retained. |
| Transfers | Page identity, shared status/progress components and transfer dialog metrics | Existing queue and upload/download behavior retained. |
| Sync Center | Page identity and status-panel hierarchy | Existing device sync and conflict behavior retained. |
| Notifications | Page identity and grouped list/empty-state language | Existing read/unread behavior retained. |
| Settings | Profile identity panel and shared list surfaces | Appearance, account, admin and sign-out behavior retained. |
| Security | Page identity and shared status/list surfaces | Session and device actions retained. |
| Update Center | Page identity and shared content surfaces | Existing updater workflow retained. |
| Admin Users | Page identity, shared list/status components and contextual sheet headers | User management rules and controller behavior are unchanged. |
| Audit Log | Page identity and shared event-list surfaces | Audit data and filtering behavior retained. |
| Search | Refined search field, shared file result cards and purpose-built idle/no-result states | Existing server-backed search behavior retained. |
| Scanner | Optical camera controls, filmstrip thumbnails and a clearer shutter ring | Camera capture and scan flow retained. |
| Scan Edit | Transient glass filter/action controls and refined preview framing | Crop/filter/export behavior retained. |
| Scan Pages | Refined page-card edges and transient glass action controls | Reordering/page management behavior retained. |
| Crop Overlay | L-shaped crop grips, midpoint affordances and color-aware repainting | Normalized crop coordinates and existing drag semantics retained. |
| PDF Viewer | Document-specific toolbar identity and optical transient controls | Uses the existing PDF renderer where supported; platform fallback retained. |
| Text Viewer | Shared page header identity and content surfaces | Existing text rendering behavior retained. |
| Audio Player | Purpose-built non-gradient artwork and dedicated audio page identity | Authenticated streaming and seek behavior retained. |
| Video Player | Dedicated video page identity and existing player-control hierarchy | Authenticated streaming, seeking and platform fallback retained. |
| Download-to-open fallback | Rebuilt as a proper page with a centered file surface and responsive scrolling | Existing save/progress/error behavior retained. |
| Folder picker | Destination-focused header, folder identity and clear confirmation affordance | Existing path navigation and folder selection retained. |
| Upload progress dialog | Animated progress and DONE / ACTIVE / ISSUES metrics | Upload queue remains the source of truth; closing the dialog does not stop uploads. |

### Logic-only files

These files are part of the screen architecture but are not visual screens and therefore were not cosmetically redesigned:

- `admin_user_rules.dart` — authorization and user-rule logic.
- `users_controller.dart` — admin user state and operations.

## 2. Reusable component coverage

| Component | Redesign / treatment |
|---|---|
| `nexa_action_bar.dart` | Contextual glass bar retained; semantic action pills gain clearer outlines. |
| `nexa_avatar.dart` | Theme-correct initials, two-character initials and visible network-image fallback. |
| `nexa_badge.dart` | Count/label badges gain a restrained outline. |
| `nexa_bottom_nav.dart` | Existing optical Liquid Glass dock intentionally preserved. |
| `nexa_button.dart` | Filled, outlined, text and icon actions gain consistent tonal press overlays. |
| `nexa_chip.dart` | More generous chip touch/visual padding. |
| `nexa_components.dart` | Export barrel; visual implementation remains in the canonical component files. |
| `nexa_confirmation.dart` | Export barrel; the underlying confirmation dialog is redesigned in `nexa_sheet.dart`. |
| `nexa_divider.dart` | Retained as a simple token-driven separator; no extra decoration added. |
| `nexa_empty_state.dart` | Layered, paper-like illustration replaces the generic icon square. |
| `nexa_error_state.dart` | Layered error illustration and semantic error container. |
| `nexa_file_tile.dart` | Category-tinted list icons, real image thumbnails in grid cards, type-led fallback artwork and animated selection. |
| `nexa_focus_block.dart` | Larger tonal icon wells and clearer title hierarchy. |
| `nexa_grouped_list.dart` | More confident grouped surface radius and redesigned page-container header. |
| `nexa_hero.dart` | Data-first storage hero, usage ring and animated usage bar; decorative gradient wash removed. |
| `nexa_liquid_glass.dart` | Existing optical renderer intentionally preserved; no blur-only replacement. |
| `nexa_list_tile.dart` | Category/semantic icon wells use solid tonal fills and crisp outlines, not repeated gradients. |
| `nexa_loading_state.dart` | Skeleton breathing uses a dedicated ambient motion token and stops for reduced-motion users. |
| `nexa_page.dart` | Shared page identity icon, responsive title hierarchy, solid page canvas and no blanket glass wrapping around every header control. |
| `nexa_progress.dart` | Progress track receives a clearer default visual weight. |
| `nexa_search_field.dart` | Rounded inset control with a visible resting edge. |
| `nexa_sheet.dart` | Contextual sheet-header icons and icon-led confirmation dialogs; transient sheet glass retained. |
| `nexa_status_pod.dart` | Larger semantic icon well and stronger title/subtitle hierarchy. |
| `nexa_surface.dart` / `nexa_surfaces.dart` | Canonical surface becomes stateful, with tonal press feedback and reduced-motion-aware scale. |
| `nexa_text_field.dart` | Refined field edge/radius and corrected focus feedback when an external FocusNode is supplied. |
| `download_to_view.dart` | Rebuilt as a NexaPage-based fallback page. |
| `folder_picker.dart` | Destination-first header and clearer folder confirmation control. |
| `upload_progress_dialog.dart` | Animated progress and compact transfer metrics. |

## 3. Design-system files

- `app_colors.dart` — existing semantic indigo, porcelain/graphite, status and surface tokens retained.
- `app_dimensions.dart` — shared spacing and shape tokens remain authoritative.
- `app_motion.dart` — One UI visual restraint plus native iOS interaction guidance; dedicated ambient skeleton token and reduced-motion resolution.
- `app_shadows.dart` — shared elevation tokens retained.
- `app_theme.dart` — design guidance aligned to One UI-inspired hierarchy and native iOS interaction discipline.
- `app_transitions.dart` — existing route-transition system retained.
- `app_typography.dart` — existing typography scale remains authoritative.
- `nexa_surfaces.dart` — the single surface hierarchy and tactile press behavior.

## 4. Intentionally preserved

These are not omissions; changing them would regress a previously approved or functionally specialized system:

- The Android optical Liquid Glass renderer and Impeller path.
- The floating bottom navigation dock and its travelling glass selection indicator.
- Immersive camera, photo and media viewing interaction models.
- Existing routes, API contracts, server authorization, SQLite schema, upload queue, sync engine, media proxy and storage paths.
- Existing file-operation semantics and platform-specific fallbacks.
- The temporary formatter auto-commit workflow and its trigger file were removed; the repository's standard CI format gate remains authoritative.

Persistent content cards are not turned into glass. Glass is reserved for navigation and transient controls/sheets.

## 5. Not introduced by this UI redesign

This pass does not add new product capabilities or pretend that unsupported operations exist. In particular, it does not introduce:

- A document editor for DOCX/XLSX/PPTX formats.
- PDF annotation, signature or markup tools.
- OCR or searchable text extraction from scans.
- Subtitle editing, chapter markers or embedded audio-tag editing.
- New server-side conversion, indexing or media-processing endpoints.
- New database tables, storage locations or data migration behavior.

The current viewer/platform support is documented separately in `FILE_FORMAT_SUPPORT.md`.

## 6. Verification record

The redesign is source-updated on `beta`. GitHub Actions CI must finish against the final consolidated beta commit before the work is described as verified. A repository-only edit is not a substitute for a successful Flutter analyze/test/build run.
