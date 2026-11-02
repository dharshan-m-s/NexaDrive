# File format support

NexaDrive renders what it can in-app and gives a clean download flow for
everything else. This page is the honest scope — no pretend support.

## Dependencies policy

The app is built from a small, offline-cached dependency set. The pub cache
does **not** include `pdf`, `video_player`, or `audioplayers`, and adding new
packages was out of scope. Therefore:

- PDFs, video and audio are **download-first**: the app explains why and saves
  the file for your device's reader/player.
- Images and text are rendered in-app.

## In-app viewing

| Category | Rendering |
|---|---|
| Images | Telegram-style `PhotoViewer`: full-bleed, swipeable, zoom, share, download/save. Thumbnails streamed via the API. |
| Text (txt, md, log, json, xml, config, source code) | `TextViewerScreen`: downloads the file and renders wrapped monospace text in-app. |

## Download-and-open flows

| Category | Behavior |
|---|---|
| PDF | `PdfViewerScreen` extends `DownloadToViewScreen` — "PDF files open best in a dedicated PDF reader." Saves via the OS file picker. |
| Video | `VideoPlayerScreen` — download and play with your device player. |
| Audio | `AudioPlayerScreen` — download the track and play with your device player. |
| Documents, archives, other | Files browser shows a bottom sheet: "Download it and open it with another app." |

`DownloadToViewScreen` (lib/ui/widgets/download_to_view.dart) is the shared
implementation: it shows success/error feedback and hands the downloaded file
to the platform save location.

## How each format maps

`FileKind` (lib/core/utils/file_kind.dart) groups files by extension into a
One UI-neutral `Category`:

- image: jpg, jpeg, png, gif, webp, bmp, heic/heif, tif/tiff
- video: mp4, mov, mkv, webm, avi, m4v, 3gp
- audio: mp3, aac, m4a, wav, flac, ogg, opus, aiff, wma
- pdf, text (many), document (doc(x), odt, rtf, pages), sheet (xls(x), ods, csv),
  slides (ppt(x), odp, key), archive (zip, tar, gz, tgz, 7z, rar, bz2, xz, zst)
- unknown → neutral "File"

## Future work

- Bundle a PDF renderer once an offline `pdf` package can be vendored.
- Add `video_player`/`audioplayers` for in-app playback when the dependency
  set allows it (requires networked package resolution or vendored artifacts).