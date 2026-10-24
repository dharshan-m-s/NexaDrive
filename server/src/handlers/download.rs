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
    time::{Duration, Instant},
};
use tokio::{
    fs,
    io::{AsyncReadExt, AsyncSeekExt},
};
use tokio_util::io::ReaderStream;
use uuid::Uuid;

use crate::{
    error::AppError,
    handlers::admin::audit,
    models::{PathQuery, ThumbQuery},
    paths::{
        content_disposition, is_photo, mime_for_file, mime_is_safe_inline, parse_byte_range,
        safe_relative_path, user_root,
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

/// Serves a small JPEG thumbnail of an image, generated server-side and
/// kept in a bounded in-memory cache. This keeps mobile photo grids from
/// downloading full-resolution originals just to render previews.
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
    if !is_photo(&absolute) {
        return Err(AppError::BadRequest("Not an image".into()));
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
    let key = format!("{}:{}:{}", absolute.to_string_lossy(), modified_secs, max);

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

    // Decode explicitly (not image::open) so the EXIF orientation is applied:
    // phone photos store rotated pixels plus an orientation tag and would
    // otherwise produce sideways or wrongly-cropped previews.
    let mut reader = ImageReader::open(&absolute).map_err(|_| AppError::UnsupportedMedia)?;
    reader.no_limits();
    let mut decoder = reader
        .into_decoder()
        .map_err(|_| AppError::UnsupportedMedia)?;
    let orientation = decoder
        .orientation()
        .unwrap_or(image::metadata::Orientation::NoTransforms);
    let mut img =
        image::DynamicImage::from_decoder(decoder).map_err(|_| AppError::UnsupportedMedia)?;
    if orientation != image::metadata::Orientation::NoTransforms {
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
    let bytes = out.into_inner();

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
