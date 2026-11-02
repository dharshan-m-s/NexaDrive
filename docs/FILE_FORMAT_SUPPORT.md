# File format support

This document describes the behavior implemented in the current Flutter source.
The viewer behavior is platform-aware: a format can render in-app on one
platform and use the shared save/open fallback on another.

## In-app viewing

| Category | Current implementation | Important behavior |
|---|---|---|
| Images | `PhotoViewer` | Full-bleed swipeable viewer, pinch/pan zoom, progressive thumbnail-to-original loading, share, save and move-to-Trash actions. |
| Text-like files | `TextViewerScreen` | In-app text preview with wrapped monospace content and file metadata. |
| PDF | `PdfViewerScreen` using `pdfx` | In-app PDF rendering with pinch zoom and page navigation on supported platforms. Linux desktop falls back to the shared download/open flow when the renderer is unavailable. |
| Audio | `AudioPlayerScreen` using `audioplayers` | Authenticated streaming through the loopback-only `MediaProxy`; range requests support seeking without first writing the complete track to the device. |
| Video | `VideoPlayerScreen` using `video_player` | Authenticated streaming with byte-range seeking. Platforms without a supported playback backend use the download/open fallback. |

## Download-and-open fallback

Documents, spreadsheets, presentations, archives and unknown formats use
`DownloadToViewScreen` to save a copy to a user-selected platform location.
The fallback reports progress, success and errors; it does not pretend that
those formats are edited or rendered inside NexaDrive.

## Extension mapping

`FileKind` in `app/lib/core/utils/file_kind.dart` maps extensions into these
visual categories:

- **Image:** jpg, jpeg, png, gif, webp, bmp, heic/heif, tif/tiff
- **Video:** mp4, mov, mkv, webm, avi, m4v, 3gp
- **Audio:** mp3, aac, m4a, wav, flac, ogg, opus, aiff, wma
- **PDF**
- **Text:** txt, md, log, json, xml, config and supported source/text extensions
- **Document:** doc, docx, odt, rtf and pages
- **Sheet:** xls, xlsx, ods and csv
- **Slides:** ppt, pptx, odp and key
- **Archive:** zip, tar, gz, tgz, 7z, rar, bz2, xz and zst
- **Unknown:** neutral generic-file treatment

The visual category is not a promise that every file type has an in-app editor.

## Media and storage behavior

- Audio is proxied with the authenticated session; media bytes are not copied
  into a second application-managed media library.
- Video playback uses the server's range-capable stream so long clips do not
  need a full download before the first frame.
- PDF rendering uses the platform renderer where supported and does not change
  the server's stored original.
- The UI redesign does not change server storage roots, SQLite records,
  upload chunking, sync state, or file ownership.

## Deliberately not added by this UI pass

This work is a UI/UX redesign, not a new document/media product. It does not
introduce a document editor, PDF annotation/signature tools, OCR or searchable
scan text, subtitle editing, chapter markers, embedded audio-tag editing, or
new server-side conversion endpoints. Existing viewer and fallback behavior
remains the source of truth for each format.
