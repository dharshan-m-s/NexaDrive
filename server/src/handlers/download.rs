use axum::{
    body::Body,
    extract::{Query, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use image::{ImageDecoder, ImageReader, codecs::jpeg::JpegEncoder};
use std::{
    io::Cursor,
    path::Path,
    process::Stdio,
    time::{Duration, Instant},
};
use tokio::{
    fs,
    io::{AsyncReadExt, AsyncSeekExt},
    time::timeout,
};
use tokio_util::io::ReaderStream;
use uuid::Uuid;

use crate::{
    error::AppError,
    handlers::admin::audit,
    models::{PathQuery, ThumbQuery},
    paths::{
        content_disposition, is_pdf, is_photo, is_video, mime_for_file, mime_is_safe_inline,
        parse_byte_range, safe_relative_path, user_root,
    },
    state::{AppState, CachedThumb},
};

pub(crate) async fn download_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<PathQuery>,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    let relative = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    let absolute = user_root(&state, user_id).join(&relative);
    let file = fs::File::open(&absolute)
        .await
        .map_err(|_| AppError::NotFound)?;
    let metadata = file.metadata().await?;
    if !metadata.is_file() {
        return Err(AppError::BadRequest("Not a file".into()));
    }
    let name = relative
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .replace('"', "'")
        .replace(['\r', '\n'], "_");
    audit(
        &state.db,
        user_id,
        "download",
        Some(&relative.to_string_lossy()),
    )
    .await?;
    let requested_range = headers
        .get(header::RANGE)
        .and_then(|v| v.to_str().ok())
        .map(str::to_string);
    Ok(file_response(file, &metadata, &name, requested_range.as_deref()).await)
}

/// Builds the HTTP response for a stored file: real Content-Type, correct
/// disposition (inline for safe media so players can stream, attachment
/// otherwise), and single-range support so video/audio seeking works. The
/// body always streams from disk — nothing is buffered whole.
pub(crate) async fn file_response(
    file: fs::File,
    metadata: &std::fs::Metadata,
    name: &str,
    range_header: Option<&str>,
) -> Response {
    let size = metadata.len();
    let mime = mime_for_file(Path::new(name));
    let disposition = content_disposition(name, mime_is_safe_inline(mime));

    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_str(mime).unwrap_or(HeaderValue::from_static("application/octet-stream")),
    );
    headers.insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&disposition).unwrap_or(HeaderValue::from_static("attachment")),
    );

    match range_header.map(|h| parse_byte_range(Some(h), size)) {
        Some(Ok(Some(range))) => {
            headers.insert(
                header::CONTENT_RANGE,
                HeaderValue::from_str(&format!("bytes {}-{}/{}", range.start, range.end, size))
                    .unwrap_or(HeaderValue::from_static("bytes */*")),
            );
            let length = range.end - range.start + 1;
            headers.insert(
                header::CONTENT_LENGTH,
                HeaderValue::from_str(&length.to_string()).unwrap_or(HeaderValue::from_static("0")),
            );
            let mut file = file;
            if file
                .seek(std::io::SeekFrom::Start(range.start))
                .await
                .is_err()
            {
                return AppError::Io(std::io::Error::other("seek failed")).into_response();
            }
            let stream = async_stream_range(file, range.start, length);
            (
                StatusCode::PARTIAL_CONTENT,
                headers,
                Body::from_stream(stream),
            )
                .into_response()
        }
        Some(Err(())) => {
            // Unsatisfiable or unsupported range: 416 with the full extent.
            headers.remove(header::CONTENT_DISPOSITION);
            headers.insert(
                header::CONTENT_RANGE,
                HeaderValue::from_str(&format!("bytes */{}", size))
                    .unwrap_or(HeaderValue::from_static("bytes */*")),
            );
            (StatusCode::RANGE_NOT_SATISFIABLE, headers).into_response()
        }
        _ => {
            headers.insert(
                header::CONTENT_LENGTH,
                HeaderValue::from_str(&size.to_string()).unwrap_or(HeaderValue::from_static("0")),
            );
            (headers, Body::from_stream(ReaderStream::new(file))).into_response()
        }
    }
}

/// Streams [start, start+length) from an open file with a bounded chunk size.
fn async_stream_range(
    file: fs::File,
    start: u64,
    length: u64,
) -> impl futures_util::Stream<Item = Result<Vec<u8>, std::io::Error>> {
    const CHUNK: u64 = 256 * 1024;
    futures_util::stream::unfold(
        (file, start, length),
        |(mut file, pos, remaining)| async move {
            if remaining == 0 {
                return None;
            }
            let want = remaining.min(CHUNK) as usize;
            let mut buf = vec![0u8; want];
            match file.read_exact(&mut buf).await {
                Ok(n) => {
                    let got = n as u64;
                    let next_pos = pos + got;
                    let next_remaining = remaining.saturating_sub(got);
                    buf.truncate(n);
                    Some((Ok(buf), (file, next_pos, next_remaining)))
                }
                Err(e) => Some((Err(e), (file, pos, 0))),
            }
        },
    )
}

const THUMB_CACHE_MAX_ENTRIES: usize = 1024;
/// A 2048 px preview is a few hundred KB, so the entry ceiling alone could
/// pin hundreds of megabytes. The byte budget keeps the cache useful on a
/// small server.
const THUMB_CACHE_MAX_BYTES: usize = 128 * 1024 * 1024;
const THUMB_CACHE_TTL: Duration = Duration::from_secs(600);
/// External preview generators are optional. A slow or hostile file must never
/// pin a request, so they run under a hard timeout and kill-on-drop.
const THUMB_TOOL_TIMEOUT: Duration = Duration::from_secs(20);
const THUMB_TOOL_MAX_STDOUT: usize = 8 * 1024 * 1024;

/// Serves a small JPEG thumbnail, generated server-side and kept in a bounded
/// in-memory cache. Images are decoded in-process; video and PDF previews use
/// optional system tools (`ffmpeg` / `pdftoppm`) and degrade to 415 when those
/// tools are unavailable. Clients keep full-resolution originals off the wire.
pub(crate) async fn thumbnail(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<ThumbQuery>,
) -> Result<Response, AppError> {
    let relative = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    if relative.as_os_str().is_empty() {
        return Err(AppError::BadRequest("path is required".into()));
    }
    let absolute = user_root(&state, user_id).join(&relative);
    let file = fs::File::open(&absolute)
        .await
        .map_err(|_| AppError::NotFound)?;
    let metadata = file.metadata().await?;
    if !metadata.is_file() {
        return Err(AppError::BadRequest("Not a file".into()));
    }
    let photo = is_photo(&absolute);
    let video = is_video(&absolute);
    let pdf = is_pdf(&absolute);
    if !(photo || video || pdf) {
        return Err(AppError::BadRequest(
            "Preview is not available for this file type".into(),
        ));
    }
    // 512 is the grid size. The photo viewer asks for a larger, still bounded
    // preview (2048) instead of downloading and decoding the full original.
    let max = query.max.unwrap_or(512).clamp(32, 2048);
    let modified_secs = metadata
        .modified()
        .ok()
        .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // The generator is part of the cache key so switching tools or adding
    // video/PDF support cannot serve a stale preview for the same path.
    let generator = if photo {
        "image"
    } else if video {
        "video-ffmpeg"
    } else {
        "pdf-pdftoppm"
    };
    let key = format!(
        "{}:{}:{}:{}",
        absolute.to_string_lossy(),
        modified_secs,
        max,
        generator
    );

    {
        let mut guard = state.thumb_cache.lock().map_err(|_| AppError::Internal)?;
        if let Some(hit) = guard.get(&key) {
            let bytes = hit.bytes.clone();
            return Ok(thumb_response(bytes));
        }
        if guard.len() > THUMB_CACHE_MAX_ENTRIES {
            let now = Instant::now();
            guard.retain(|_, cached| now.duration_since(cached.generated) < THUMB_CACHE_TTL);
        }
    }

    let bytes = if photo {
        // Decode explicitly (not image::open) so the EXIF orientation is
        // applied: phone photos store rotated pixels plus an orientation tag
        // and would otherwise produce sideways or wrongly-cropped previews.
        let mut reader = ImageReader::open(&absolute).map_err(|_| AppError::UnsupportedMedia)?;
        reader.no_limits();
        let mut decoder = reader
            .into_decoder()
            .map_err(|_| AppError::UnsupportedMedia)?;
        let orientation = decoder
            .orientation()
            .unwrap_or(image::metadata::Orientation::NoTransforms);
        let img =
            image::DynamicImage::from_decoder(decoder).map_err(|_| AppError::UnsupportedMedia)?;
        encode_thumbnail(img, max, Some(orientation))?
    } else if video {
        video_thumbnail(&absolute.to_string_lossy(), max).await?
    } else {
        pdf_thumbnail(&absolute.to_string_lossy(), max).await?
    };

    {
        let mut guard = state.thumb_cache.lock().map_err(|_| AppError::Internal)?;
        guard.insert(
            key,
            CachedThumb {
                generated: Instant::now(),
                bytes: bytes.clone(),
            },
        );
        if guard.len() > THUMB_CACHE_MAX_ENTRIES {
            let now = Instant::now();
            guard.retain(|_, cached| now.duration_since(cached.generated) < THUMB_CACHE_TTL);
        }
        let mut total: usize = guard.values().map(|cached| cached.bytes.len()).sum();
        if total > THUMB_CACHE_MAX_BYTES {
            let mut oldest: Vec<(String, Instant)> = guard
                .iter()
                .map(|(key, cached)| (key.clone(), cached.generated))
                .collect();
            oldest.sort_by_key(|(_, generated)| *generated);
            for (key, _) in oldest {
                if total <= THUMB_CACHE_MAX_BYTES {
                    break;
                }
                if let Some(removed) = guard.remove(&key) {
                    total = total.saturating_sub(removed.bytes.len());
                }
            }
        }
    }
    Ok(thumb_response(bytes))
}

fn encode_thumbnail(
    mut img: image::DynamicImage,
    max: u32,
    orientation: Option<image::metadata::Orientation>,
) -> Result<Vec<u8>, AppError> {
    if let Some(orientation) =
        orientation.filter(|orientation| *orientation != image::metadata::Orientation::NoTransforms)
    {
        img.apply_orientation(orientation);
    }
    let thumb = img.thumbnail(max, max);
    // Grid thumbnails are small enough that 84 is visually lossless; the
    // viewer's larger preview gets a higher quality so zooming does not show
    // JPEG blocking.
    let quality = if max > 1024 { 90 } else { 84 };
    let mut out = Cursor::new(Vec::new());
    thumb
        .write_with_encoder(JpegEncoder::new_with_quality(&mut out, quality))
        .map_err(|_| AppError::Internal)?;
    Ok(out.into_inner())
}

/// Runs an optional preview generator with fixed argv (never a shell).
async fn run_preview_tool(
    program: &'static str,
    args: &[&str],
) -> Result<std::process::Output, AppError> {
    let mut command = tokio::process::Command::new(program);
    command
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .stdout(Stdio::piped())
        .kill_on_drop(true);
    timeout(THUMB_TOOL_TIMEOUT, command.output())
        .await
        .map_err(|_| AppError::UnsupportedMedia)?
        .map_err(|_| AppError::UnsupportedMedia)
}

/// Normalizes an external tool's first frame into the same bounded JPEG format
/// as in-process image previews.
fn decode_thumbnail_frame(bytes: Vec<u8>, max: u32) -> Result<Vec<u8>, AppError> {
    if bytes.is_empty() || bytes.len() > THUMB_TOOL_MAX_STDOUT {
        return Err(AppError::UnsupportedMedia);
    }
    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| AppError::UnsupportedMedia)?;
    reader.no_limits();
    let mut decoder = reader
        .into_decoder()
        .map_err(|_| AppError::UnsupportedMedia)?;
    let orientation = decoder
        .orientation()
        .unwrap_or(image::metadata::Orientation::NoTransforms);
    let img = image::DynamicImage::from_decoder(decoder).map_err(|_| AppError::UnsupportedMedia)?;
    encode_thumbnail(img, max, Some(orientation))
}

/// ffmpeg writes a single MJPEG frame to stdout.
async fn video_thumbnail(path: &str, max: u32) -> Result<Vec<u8>, AppError> {
    let output = run_preview_tool(
        "ffmpeg",
        &[
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            path,
            "-frames:v",
            "1",
            "-an",
            "-sn",
            "-dn",
            "-f",
            "image2pipe",
            "-vcodec",
            "mjpeg",
            "pipe:1",
        ],
    )
    .await?;
    if !output.status.success() {
        return Err(AppError::UnsupportedMedia);
    }
    decode_thumbnail_frame(output.stdout, max)
}

/// pdftoppm writes to files, not stdout, so render into a private temporary
/// directory and remove it on every path. The prefix is a fresh UUID and no
/// user-controlled string ever reaches an argv element or shell.
async fn pdf_thumbnail(path: &str, max: u32) -> Result<Vec<u8>, AppError> {
    let dir = std::env::temp_dir().join(format!("nexadrive-thumb-{}", Uuid::new_v4()));
    fs::create_dir(&dir)
        .await
        .map_err(|_| AppError::UnsupportedMedia)?;
    let prefix = dir.join("page");
    let prefix_arg = prefix.to_string_lossy().to_string();
    let max_arg = max.to_string();

    let result = async {
        let output = run_preview_tool(
            "pdftoppm",
            &[
                "-f",
                "1",
                "-l",
                "1",
                "-singlefile",
                "-scale-to",
                &max_arg,
                "-jpeg",
                path,
                &prefix_arg,
            ],
        )
        .await?;
        if !output.status.success() {
            return Err(AppError::UnsupportedMedia);
        }
        let bytes = fs::read(dir.join("page.jpg"))
            .await
            .map_err(|_| AppError::UnsupportedMedia)?;
        decode_thumbnail_frame(bytes, max)
    }
    .await;

    let _ = fs::remove_dir_all(&dir).await;
    result
}

fn thumb_response(bytes: Vec<u8>) -> Response {
    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("image/jpeg"));
    headers.insert(
        header::CONTENT_LENGTH,
        HeaderValue::from_str(&bytes.len().to_string()).unwrap(),
    );
    // security_headers replaces the global no-store with a private cache
    // policy when it sees this marker, and strips the marker itself.
    headers.insert(
        "x-nexadrive-cacheable",
        HeaderValue::from_static("thumbnail"),
    );
    (headers, Body::from(bytes)).into_response()
}
