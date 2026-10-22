//! Loopback-only administration console.
//!
//! This module owns the dashboard's HTTP surface: the JSON API under
//! `/api/console/*`, a strict Host/Origin guard, a console-specific Content
//! Security Policy, and a small static file server for the built SPA. It is
//! intentionally separate from the public client API in `routes.rs`; the two
//! run on different listeners and share no session model (the console uses a
//! cookie + CSRF double-submit, the clients use bearer tokens).

pub(crate) mod api;
pub(crate) mod session;

use std::path::{Component, Path, PathBuf};

use axum::{
    Router,
    body::Body,
    extract::{Request, State},
    http::{HeaderValue, Method, StatusCode, header},
    middleware,
    response::{IntoResponse, Response},
    routing::{delete, get, post},
};

use crate::state::AppState;

/// Builds the console router. Every route except health and sign-in sits behind
/// `require_console_admin`.
pub(crate) fn router(state: AppState) -> Router {
    let protected = Router::new()
        .route("/api/console/session", get(session::session_info))
        .route("/api/console/logout", post(session::logout))
        .route("/api/console/overview", get(api::overview))
        .route("/api/console/metrics", get(api::metrics_history))
        .route("/api/console/sessions", get(api::list_all_sessions))
        .route(
            "/api/console/sessions/revoke-all",
            post(api::revoke_all_sessions),
        )
        .route("/api/console/sessions/{id}", delete(api::revoke_session))
        .route("/api/console/shares", get(api::list_all_shares))
        .route("/api/console/shares/{id}", delete(api::revoke_share))
        .route("/api/console/audit", get(api::audit_log))
        .route("/api/console/storage", get(api::storage_summary))
        .route("/api/console/storage/browse", get(api::browse))
        .route(
            "/api/console/storage/integrity",
            get(api::storage_integrity),
        )
        .route("/api/console/service", get(api::service_status))
        .route("/api/console/service/logs", get(api::service_logs))
        .route("/api/console/service/restart", post(api::service_restart))
        .route("/api/console/database/integrity", get(api::db_integrity))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            session::require_console_admin,
        ));

    let public = Router::new()
        .route("/api/console/health", get(api::console_health))
        .route("/api/console/login", post(session::login));

    public
        .merge(protected)
        .fallback(get(static_handler))
        .with_state(state)
        // Applied outermost-last: host_guard runs before console_headers.
        .layer(middleware::from_fn(console_headers))
        .layer(middleware::from_fn(host_guard))
}

// --------------------------------------------------------------- guards

/// Rejects any request whose `Host` is not a loopback name. Even though the
/// console can only bind a loopback socket, this is defense in depth: a
/// reverse proxy or a mis-set `Host` header must never reach the control plane.
/// For state-changing methods a present `Origin` must also be loopback.
async fn host_guard(request: Request, next: middleware::Next) -> Response {
    let headers = request.headers();
    let host_ok = headers
        .get(header::HOST)
        .and_then(|v| v.to_str().ok())
        .map(host_is_loopback)
        .unwrap_or(false);
    if !host_ok {
        return (StatusCode::FORBIDDEN, "console is loopback-only").into_response();
    }
    let method = request.method().clone();
    if !matches!(method, Method::GET | Method::HEAD | Method::OPTIONS)
        && let Some(origin) = headers.get(header::ORIGIN).and_then(|v| v.to_str().ok())
        && !origin_is_loopback(origin)
    {
        return (StatusCode::FORBIDDEN, "cross-origin request rejected").into_response();
    }
    next.run(request).await
}

fn host_is_loopback(host: &str) -> bool {
    let host = host.trim();
    let name = if let Some(rest) = host.strip_prefix('[') {
        match rest.split_once(']') {
            Some((h, _)) => h,
            None => return false,
        }
    } else {
        match host.rsplit_once(':') {
            Some((h, _)) => h,
            None => host,
        }
    };
    matches!(name, "127.0.0.1" | "localhost" | "::1")
}

fn origin_is_loopback(origin: &str) -> bool {
    let rest = origin.split_once("://").map(|(_, r)| r).unwrap_or(origin);
    let host = rest.split('/').next().unwrap_or(rest);
    host_is_loopback(host)
}

/// Console responses get a strict CSP and the standard hardening headers.
async fn console_headers(request: Request, next: middleware::Next) -> Response {
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    headers.insert(
        header::CONTENT_SECURITY_POLICY,
        HeaderValue::from_static(
            "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; \
             img-src 'self' data:; font-src 'self'; connect-src 'self'; base-uri 'none'; \
             form-action 'none'; frame-ancestors 'none'",
        ),
    );
    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    headers.insert("x-frame-options", HeaderValue::from_static("DENY"));
    headers.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    response
}

// --------------------------------------------------------------- static SPA

async fn static_handler(State(state): State<AppState>, request: Request) -> Response {
    let path = request.uri().path();
    if path.starts_with("/api/") {
        return (
            StatusCode::NOT_FOUND,
            axum::Json(serde_json::json!({"error": "Not found"})),
        )
            .into_response();
    }

    let dist = &state.config.console_dist_dir;
    let rel = match safe_static_path(path) {
        Ok(p) => p,
        Err(()) => return (StatusCode::BAD_REQUEST, "Bad path").into_response(),
    };

    let mut file_path = dist.join(&rel);
    if !is_file_inside(&file_path, dist).await {
        file_path = dist.join("index.html");
    }

    match tokio::fs::read(&file_path).await {
        Ok(bytes) => {
            let is_index = file_path
                .file_name()
                .map(|n| n == "index.html")
                .unwrap_or(false);
            let mut response = Response::new(Body::from(bytes));
            response.headers_mut().insert(
                header::CONTENT_TYPE,
                HeaderValue::from_static(static_mime(&file_path)),
            );
            response.headers_mut().insert(
                header::CACHE_CONTROL,
                HeaderValue::from_static(if is_index {
                    "no-store"
                } else {
                    "public, max-age=31536000, immutable"
                }),
            );
            response
        }
        Err(_) => (
            StatusCode::SERVICE_UNAVAILABLE,
            "NexaDrive dashboard is not built. Run `npm run build` in dashboard/ and restart the server.",
        )
            .into_response(),
    }
}

/// Resolves a request path to a safe relative path under the dist directory,
/// rejecting traversal (including percent-encoded separators). An empty path
/// maps to `index.html`.
fn safe_static_path(uri_path: &str) -> Result<PathBuf, ()> {
    let decoded = percent_decode(uri_path.trim_start_matches('/'));
    if decoded.contains('\0') {
        return Err(());
    }
    let mut clean = PathBuf::new();
    for component in Path::new(&decoded).components() {
        match component {
            Component::Normal(part) => clean.push(part),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => return Err(()),
        }
    }
    if clean.as_os_str().is_empty() {
        clean.push("index.html");
    }
    Ok(clean)
}

fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hi = (bytes[i + 1] as char).to_digit(16);
            let lo = (bytes[i + 2] as char).to_digit(16);
            if let (Some(hi), Some(lo)) = (hi, lo) {
                out.push((hi * 16 + lo) as u8);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

async fn is_file_inside(path: &Path, dist: &Path) -> bool {
    let meta = match tokio::fs::symlink_metadata(path).await {
        Ok(m) => m,
        Err(_) => return false,
    };
    if !meta.file_type().is_file() {
        return false;
    }
    match (
        tokio::fs::canonicalize(path).await,
        tokio::fs::canonicalize(dist).await,
    ) {
        (Ok(p), Ok(d)) => p.starts_with(d),
        _ => false,
    }
}

fn static_mime(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .as_deref()
    {
        Some("html") => "text/html; charset=utf-8",
        Some("js" | "mjs") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json" | "map") => "application/json; charset=utf-8",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("ico") => "image/x-icon",
        Some("woff2") => "font/woff2",
        Some("woff") => "font/woff",
        Some("wasm") => "application/wasm",
        Some("txt") => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_guard_accepts_loopback_only() {
        assert!(host_is_loopback("127.0.0.1:8090"));
        assert!(host_is_loopback("localhost:8090"));
        assert!(host_is_loopback("localhost"));
        assert!(host_is_loopback("[::1]:8090"));
        assert!(!host_is_loopback("0.0.0.0:8090"));
        assert!(!host_is_loopback("evil.example.com"));
        assert!(!host_is_loopback("100.64.0.1:8090"));
    }

    #[test]
    fn origin_guard_accepts_loopback_only() {
        assert!(origin_is_loopback("http://127.0.0.1:8090"));
        assert!(origin_is_loopback("http://localhost:8090"));
        assert!(!origin_is_loopback("https://evil.example.com"));
        assert!(!origin_is_loopback("http://192.168.1.5:8090"));
    }

    #[test]
    fn static_paths_reject_traversal() {
        assert_eq!(
            safe_static_path("/assets/app.js").unwrap(),
            PathBuf::from("assets/app.js")
        );
        assert_eq!(safe_static_path("/").unwrap(), PathBuf::from("index.html"));
        assert!(safe_static_path("/../etc/passwd").is_err());
        assert!(safe_static_path("/%2e%2e/etc/passwd").is_err());
        assert!(safe_static_path("/a/../../b").is_err());
    }

    #[test]
    fn static_mime_known_types() {
        assert!(static_mime(Path::new("index.html")).starts_with("text/html"));
        assert!(static_mime(Path::new("app.js")).starts_with("text/javascript"));
        assert_eq!(
            static_mime(Path::new("unknown.bin")),
            "application/octet-stream"
        );
    }

    #[test]
    fn percent_decode_handles_encoding() {
        assert_eq!(percent_decode("a%20b"), "a b");
        assert_eq!(percent_decode("%2e%2e"), "..");
        assert_eq!(percent_decode("plain"), "plain");
    }
}
