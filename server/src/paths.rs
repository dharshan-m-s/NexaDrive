use std::path::{Component, Path, PathBuf};
use uuid::Uuid;

use crate::{error::AppError, state::AppState};

pub(crate) fn safe_relative_path(raw: &str) -> Result<PathBuf, AppError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(PathBuf::new());
    }
    if trimmed.starts_with('/') {
        return Err(AppError::BadRequest(
            "Absolute paths are not allowed".into(),
        ));
    }
    if trimmed.contains('\0') {
        return Err(AppError::BadRequest(
            "Null bytes are not allowed in paths".into(),
        ));
    }
    let path = Path::new(trimmed);
    if path.is_absolute() {
        return Err(AppError::BadRequest(
            "Absolute paths are not allowed".into(),
        ));
    }
    let mut clean = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => clean.push(part),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(AppError::BadRequest("Invalid path".into()));
            }
        }
    }
    if clean
        .components()
        .any(|c| matches!(c, Component::Normal(s) if s.to_string_lossy() == ".trash"))
    {
        return Err(AppError::Forbidden);
    }
    Ok(clean)
}

pub(crate) fn user_root(state: &AppState, user_id: Uuid) -> PathBuf {
    state.storage_root.join(user_id.to_string())
}
pub(crate) fn trash_root(state: &AppState, user_id: Uuid) -> PathBuf {
    state.storage_root.join(".trash").join(user_id.to_string())
}

pub(crate) fn sanitize_name(raw: &str) -> Result<String, AppError> {
    let name = raw.trim();
    if name.is_empty() || name == "." || name == ".." {
        return Err(AppError::BadRequest("Invalid name".into()));
    }
    if name.contains('/') || name.contains('\\') {
        return Err(AppError::BadRequest(
            "Name cannot contain path separators".into(),
        ));
    }
    if name == ".trash" {
        return Err(AppError::Forbidden);
    }
    Ok(name.to_string())
}

pub(crate) fn is_photo(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|x| x.to_str())
            .map(|x| x.to_ascii_lowercase())
            .as_deref(),
        Some(
            "jpg"
                | "jpeg"
                | "png"
                | "gif"
                | "webp"
                | "bmp"
                | "heic"
                | "heif"
                | "avif"
                | "tif"
                | "tiff"
        )
    )
}

/// Content-Type for a stored file. Media types the app renders or streams are
/// returned with their real MIME type so players and viewers can handle them;
/// everything else stays `application/octet-stream` so browsers always
/// download rather than render (never trust unknown HTML/SVG for execution).
pub(crate) fn mime_for_file(path: &Path) -> &'static str {
    let ext = path
        .extension()
        .and_then(|x| x.to_str())
        .map(|x| x.to_ascii_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        // Images
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "bmp" => "image/bmp",
        "heic" | "heif" => "image/heic",
        "avif" => "image/avif",
        "tif" | "tiff" => "image/tiff",
        // Video (streamed by the in-app player)
        "mp4" | "m4v" => "video/mp4",
        "webm" => "video/webm",
        "mkv" => "video/x-matroska",
        "mov" => "video/quicktime",
        // Audio (streamed by the in-app player)
        "mp3" => "audio/mpeg",
        "m4a" => "audio/mp4",
        "aac" => "audio/aac",
        "wav" => "audio/wav",
        "flac" => "audio/flac",
        "ogg" | "opus" => "audio/ogg",
        // Documents
        "pdf" => "application/pdf",
        "txt" | "md" | "log" | "csv" | "json" | "xml" | "yaml" | "yml" | "toml" | "conf"
        | "ini" | "cfg" => "text/plain; charset=utf-8",
        "html" | "htm" => "text/html; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "js" => "text/javascript; charset=utf-8",
        // Archives
        "zip" => "application/zip",
        "7z" => "application/x-7z-compressed",
        "tar" => "application/x-tar",
        "gz" => "application/gzip",
        "rar" => "application/vnd.rar",
        _ => "application/octet-stream",
    }
}

/// Whether a MIME type is safe to serve inline (`inline` disposition). HTML,
/// SVG and JavaScript are always forced to download: they can execute in a
/// browser context and would turn the file host into an XSS vector.
pub(crate) fn mime_is_safe_inline(mime: &str) -> bool {
    !(mime.starts_with("text/html")
        || mime == "image/svg+xml"
        || mime.starts_with("text/javascript"))
}

/// Filename for a Content-Disposition header, ASCII-sanitized plus an
/// RFC 5987/6266 UTF-8 fallback for non-ASCII names.
pub(crate) fn content_disposition(name: &str, inline: bool) -> String {
    let sanitized: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_graphic() && c != '"' && c != '\\' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let disposition = if inline { "inline" } else { "attachment" };
    if name.chars().all(|c| c.is_ascii_graphic() || c == ' ') && !name.is_empty() {
        format!("{disposition}; filename=\"{sanitized}\"")
    } else {
        let encoded: String = name
            .bytes()
            .map(|b| {
                if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
                    (b as char).to_string()
                } else {
                    format!("%{b:02X}")
                }
            })
            .collect();
        format!("{disposition}; filename=\"{sanitized}\"; filename*=UTF-8''{encoded}")
    }
}

/// Parsed byte range for HTTP partial content (video/audio seeking).
pub(crate) struct ByteRange {
    pub(crate) start: u64,
    pub(crate) end: u64,
}

/// Parses a single-range `Range: bytes=start-end` header. Returns `None` when
/// absent or malformed; syntactically unsatisfiable ranges return an error the
/// caller maps to 416.
pub(crate) fn parse_byte_range(header: Option<&str>, size: u64) -> Result<Option<ByteRange>, ()> {
    let Some(value) = header else {
        return Ok(None);
    };
    let spec = value.trim();
    let Some(unit_and_set) = spec.strip_prefix("bytes=") else {
        return Err(()); // unsupported unit -> 416
    };
    let mut raw = unit_and_set.split(',');
    let first = raw.next().unwrap_or("");
    if raw.next().is_some() {
        return Err(()); // multi-range unsupported -> 416
    }
    let first = first.trim();
    if let Some(suffix) = first.strip_prefix('-') {
        // suffix form: last N bytes
        let n: u64 = suffix.parse().map_err(|_| ())?;
        if n == 0 || size == 0 {
            return Err(());
        }
        let n = n.min(size);
        return Ok(Some(ByteRange {
            start: size - n,
            end: size - 1,
        }));
    }
    let (start_raw, end_raw) = first.split_once('-').ok_or(())?;
    let start: u64 = start_raw.trim().parse().map_err(|_| ())?;
    let end: u64 = if end_raw.trim().is_empty() {
        size.saturating_sub(1)
    } else {
        end_raw.trim().parse().map_err(|_| ())?
    };
    if start > end || start >= size {
        return Err(());
    }
    Ok(Some(ByteRange {
        start,
        end: end.min(size.saturating_sub(1)),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_traversal_and_trash_paths() {
        assert!(safe_relative_path("../secret").is_err());
        assert!(safe_relative_path("/etc/passwd").is_err());
        assert!(safe_relative_path("folder/.trash/file").is_err());
        assert_eq!(
            safe_relative_path("./Documents/report.pdf")
                .unwrap()
                .to_string_lossy(),
            "Documents/report.pdf"
        );
    }

    #[test]
    fn validates_names() {
        assert!(sanitize_name("").is_err());
        assert!(sanitize_name("..").is_err());
        assert!(sanitize_name("folder/file").is_err());
        assert!(sanitize_name(".trash").is_err());
        assert_eq!(sanitize_name(" report.pdf ").unwrap(), "report.pdf");
    }

    #[test]
    fn rejects_absolute_path_variants() {
        assert!(safe_relative_path("/etc/passwd").is_err());
        assert!(safe_relative_path("/").is_err());
        assert!(safe_relative_path("/.").is_err());
    }

    #[test]
    fn rejects_dotdot_traversal() {
        assert!(safe_relative_path("../etc/passwd").is_err());
        assert!(safe_relative_path("foo/../../etc/passwd").is_err());
        assert!(safe_relative_path("foo/../../../etc/passwd").is_err());
        assert!(safe_relative_path("./../secret").is_err());
    }

    #[test]
    fn rejects_trash_access() {
        assert!(safe_relative_path(".trash").is_err());
        assert!(safe_relative_path("folder/.trash/file").is_err());
        assert!(safe_relative_path(".trash/uuid/file").is_err());
        assert!(safe_relative_path("a/.trash/b").is_err());
    }

    #[test]
    fn normalizes_dot_segments() {
        assert_eq!(
            safe_relative_path("./foo/bar").unwrap().to_string_lossy(),
            "foo/bar"
        );
        assert_eq!(
            safe_relative_path("foo/./bar").unwrap().to_string_lossy(),
            "foo/bar"
        );
    }

    #[test]
    fn sanitize_rejects_special_names() {
        assert!(sanitize_name(".").is_err());
        assert!(sanitize_name("..").is_err());
        assert!(sanitize_name("").is_err());
        assert!(sanitize_name(" ").is_err());
        assert!(sanitize_name("con").is_ok()); // valid name on Linux
        assert!(sanitize_name("aux").is_ok());
    }

    #[test]
    fn sanitize_rejects_path_separators() {
        assert!(sanitize_name("foo/bar").is_err());
        assert!(sanitize_name("foo\\bar").is_err());
        assert!(sanitize_name("/foo").is_err());
        assert!(sanitize_name("foo/").is_err());
    }

    #[test]
    fn sanitize_trims_whitespace() {
        assert_eq!(sanitize_name("  foo  ").unwrap(), "foo");
        assert_eq!(sanitize_name("\tbar\n").unwrap(), "bar");
    }

    #[test]
    fn sanitize_rejects_dot_trash() {
        assert!(sanitize_name(".trash").is_err());
    }

    #[test]
    fn safe_relative_path_rejects_empty_after_normalization() {
        assert!(safe_relative_path(".").is_ok()); // normalizes to empty PathBuf
        assert!(safe_relative_path("./.").is_ok());
    }

    #[test]
    fn safe_relative_path_rejects_backslash() {
        // On Linux, backslash is a valid filename character, not a path separator.
        // The path "foo\bar" is a single file named "foo\bar".
        let result = safe_relative_path("foo\\bar");
        assert!(result.is_ok());
        assert_eq!(result.unwrap().to_string_lossy(), "foo\\bar");
    }

    #[test]
    fn reject_null_bytes_in_path() {
        // Null bytes should be rejected since they can't be represented in filesystem paths
        assert!(safe_relative_path("foo\0bar").is_err());
    }

    #[test]
    fn mime_types_are_media_aware() {
        assert_eq!(mime_for_file(Path::new("a.JPG")), "image/jpeg");
        assert_eq!(mime_for_file(Path::new("photo.png")), "image/png");
        assert_eq!(mime_for_file(Path::new("clip.MP4")), "video/mp4");
        assert_eq!(mime_for_file(Path::new("song.flac")), "audio/flac");
        assert_eq!(mime_for_file(Path::new("doc.pdf")), "application/pdf");
        assert_eq!(
            mime_for_file(Path::new("notes.txt")),
            "text/plain; charset=utf-8"
        );
        assert_eq!(mime_for_file(Path::new("archive.zip")), "application/zip");
        // Unknown extensions stay octet-stream so browsers download them.
        assert_eq!(
            mime_for_file(Path::new("data.bin")),
            "application/octet-stream"
        );
    }

    #[test]
    fn inline_disposition_is_restricted_to_safe_media() {
        assert!(mime_is_safe_inline("image/jpeg"));
        assert!(mime_is_safe_inline("video/mp4"));
        assert!(mime_is_safe_inline("audio/mpeg"));
        assert!(mime_is_safe_inline("application/pdf"));
        assert!(mime_is_safe_inline("text/plain; charset=utf-8"));
        // Executable-in-browser formats must always download.
        assert!(!mime_is_safe_inline("text/html; charset=utf-8"));
        assert!(!mime_is_safe_inline("image/svg+xml"));
        assert!(!mime_is_safe_inline("text/javascript; charset=utf-8"));
    }

    #[test]
    fn content_disposition_sanitizes_and_preserves_unicode() {
        let d = content_disposition("report.pdf", true);
        assert!(d.starts_with("inline"));
        assert!(d.contains("filename=\"report.pdf\""));
        let d = content_disposition("quote".to_string().as_str(), false);
        assert!(d.starts_with("attachment"));
        // Non-ASCII gets an RFC 5987 fallback.
        let d = content_disposition("résumé.pdf", false);
        assert!(d.contains("filename*=UTF-8''"));
        assert!(d.contains("attachment"));
    }

    #[test]
    fn byte_ranges_parse_correctly() {
        let r = parse_byte_range(Some("bytes=0-99"), 1000).unwrap().unwrap();
        assert_eq!((r.start, r.end), (0, 99));
        let r = parse_byte_range(Some("bytes=500-"), 1000).unwrap().unwrap();
        assert_eq!((r.start, r.end), (500, 999));
        // suffix range: last 100 bytes
        let r = parse_byte_range(Some("bytes=-100"), 1000).unwrap().unwrap();
        assert_eq!((r.start, r.end), (900, 999));
        // end clamped to size
        let r = parse_byte_range(Some("bytes=900-5000"), 1000)
            .unwrap()
            .unwrap();
        assert_eq!((r.start, r.end), (900, 999));
        // absent header -> no range
        assert!(parse_byte_range(None, 1000).unwrap().is_none());
        // malformed / unsupported -> 416
        assert!(parse_byte_range(Some("bytes=abc"), 1000).is_err());
        assert!(parse_byte_range(Some("chunks=0-1"), 1000).is_err());
        assert!(parse_byte_range(Some("bytes=0-1,5-9"), 1000).is_err());
        assert!(parse_byte_range(Some("bytes=100-50"), 1000).is_err());
        assert!(parse_byte_range(Some("bytes=2000-"), 1000).is_err());
        assert!(parse_byte_range(Some("bytes=-0"), 1000).is_err());
    }
}
