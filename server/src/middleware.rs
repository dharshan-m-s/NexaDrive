use axum::{
    extract::Request,
    http::{HeaderValue, header},
    middleware,
    response::Response,
};

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
