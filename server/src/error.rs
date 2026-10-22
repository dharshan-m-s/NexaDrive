use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use tracing::error;

#[derive(Debug, thiserror::Error)]
pub(crate) enum AppError {
    #[error("unauthorized")]
    Unauthorized,
    #[error("forbidden")]
    Forbidden,
    #[error("not found")]
    NotFound,
    #[error("conflict: {0}")]
    Conflict(String),
    /// A conflict that the client can act on. The machine-readable `code`
    /// lets the upload client tell "resume from a different offset" apart
    /// from "this file already exists".
    #[error("conflict: {message}")]
    ConflictCode { message: String, code: &'static str },
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("unsupported media type")]
    UnsupportedMedia,
    #[error("too many requests")]
    TooManyRequests,
    #[error("database error")]
    Database(#[from] sqlx::Error),
    #[error("io error")]
    Io(#[from] std::io::Error),
    #[error("internal error")]
    Internal,
    /// The server is at its concurrency limit for this operation. Clients treat
    /// this as retryable.
    #[error("service unavailable")]
    ServiceUnavailable,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, body) = match self {
            Self::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                serde_json::json!({"error": "Unauthorized"}),
            ),
            Self::Forbidden => (
                StatusCode::FORBIDDEN,
                serde_json::json!({"error": "Forbidden"}),
            ),
            Self::NotFound => (
                StatusCode::NOT_FOUND,
                serde_json::json!({"error": "Not found"}),
            ),
            Self::Conflict(message) => {
                (StatusCode::CONFLICT, serde_json::json!({"error": message}))
            }
            Self::ConflictCode { message, code } => (
                StatusCode::CONFLICT,
                serde_json::json!({"error": message, "code": code}),
            ),
            Self::BadRequest(message) => (
                StatusCode::BAD_REQUEST,
                serde_json::json!({"error": message}),
            ),
            Self::UnsupportedMedia => (
                StatusCode::UNSUPPORTED_MEDIA_TYPE,
                serde_json::json!({"error": "Unsupported image format"}),
            ),
            Self::TooManyRequests => (
                StatusCode::TOO_MANY_REQUESTS,
                serde_json::json!({"error": "Too many login attempts. Try again later."}),
            ),
            Self::ServiceUnavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                serde_json::json!({"error": "The server is busy. Try again shortly."}),
            ),
            Self::Database(source) => {
                // The client only ever sees a generic message, so the real cause
                // has to be recorded server-side or a 500 is unactionable.
                error!(error = %source, "database error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    serde_json::json!({"error": "Internal server error"}),
                )
            }
            Self::Io(source) => {
                error!(error = %source, "io error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    serde_json::json!({"error": "Internal server error"}),
                )
            }
            Self::Internal => {
                error!("internal error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    serde_json::json!({"error": "Internal server error"}),
                )
            }
        };
        (status, Json(body)).into_response()
    }
}
