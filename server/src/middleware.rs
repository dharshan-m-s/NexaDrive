use std::time::Instant;

use axum::{
    extract::{Request, State},
    http::{HeaderValue, header},
    middleware,
    response::Response,
};

use crate::state::AppState;
use tracing::info;

/// Records request count, error count and latency into the process metrics.
/// Placed outermost so it observes every response, including rejections.
pub(crate) async fn track_metrics(
    State(state): State<AppState>,
    request: Request,
    next: middleware::Next,
) -> Response {
    let started = Instant::now();
    let method = request.method().clone();
    let path = request.uri().path().to_owned();
    let content_length = request
        .headers()
        .get(header::CONTENT_LENGTH)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u64>().ok());
    let response = next.run(request).await;
    if path == "/api/uploads/chunk" || !response.status().is_success() {
        info!(
            %method,
            %path,
            status = response.status().as_u16(),
            content_length,
            elapsed_ms = started.elapsed().as_millis() as u64,
            "http request completed"
        );
    }
    state
        .metrics
        .record(response.status().as_u16(), started.elapsed());
    response
}

pub(crate) async fn security_headers(request: Request, next: middleware::Next) -> Response {
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    // Thumbnails opt in to a private browser-cache policy via an internal
    // marker; every other response stays strictly non-cacheable.
    let cacheable_thumbnail = headers
        .get("x-nexadrive-cacheable")
        .map(|v| v == "thumbnail")
        .unwrap_or(false);
    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    headers.insert("x-frame-options", HeaderValue::from_static("DENY"));
    headers.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    headers.insert(
        "permissions-policy",
        HeaderValue::from_static("camera=(), microphone=(), geolocation=()"),
    );
    if cacheable_thumbnail {
        headers.remove("x-nexadrive-cacheable");
        headers.insert(
            header::CACHE_CONTROL,
            HeaderValue::from_static("private, max-age=86400"),
        );
    } else {
        headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
        headers.insert(header::PRAGMA, HeaderValue::from_static("no-cache"));
    }
    response
}
