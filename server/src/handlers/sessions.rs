use axum::{
    Json,
    extract::State,
    extract::{Extension, Query},
    http::HeaderMap,
};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{CurrentSessionId, bearer, token_hash},
    error::AppError,
    state::AppState,
};

use crate::models::{RevokeSessionResponse, SessionInfoResponse, SessionsListResponse};

pub(crate) async fn current_session(
    State(state): State<AppState>,
    Extension(user_id): Extension<Uuid>,
    headers: HeaderMap,
) -> Result<Json<SessionInfoResponse>, AppError> {
    let token = bearer(&headers).ok_or(AppError::Unauthorized)?;
    let hash = token_hash(&token);

    // Refresh last activity time on every successful read so the Sessions page
    // can show a meaningful "last used" without a separate heartbeat endpoint.
    {
        sqlx::query("UPDATE sessions SET last_activity_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND token_hash = $2")
            .bind(user_id)
            .bind(&hash)
            .execute(&state.db)
            .await?;
    }

    let row = sqlx::query(
        "SELECT s.id, s.created_at, s.last_activity_at, s.expires_at, s.device_name, s.platform \
         FROM sessions s WHERE s.user_id = $1 AND s.token_hash = $2",
    )
    .bind(user_id)
    .bind(&hash)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    Ok(Json(SessionInfoResponse {
        session_id: row.get("id"),
        created_at: row.get("created_at"),
        last_activity_at: row.get("last_activity_at"),
        expires_at: row.get("expires_at"),
        is_current: true,
        device_name: row.get("device_name"),
        platform: row.get("platform"),
    }))
}

pub(crate) async fn list_sessions(
    State(state): State<AppState>,
    Extension(user_id): Extension<Uuid>,
    Extension(current): Extension<CurrentSessionId>,
    Query(query): Query<crate::models::SessionsQuery>,
) -> Result<Json<SessionsListResponse>, AppError> {
    let include_current = query.include_current.unwrap_or(true);

    // "Is current" must be decided by the session that authenticated *this*
    // request, not by whichever row the database happens to return first —
    // a LIMIT 1 with no ORDER BY can flag someone else's session as the
    // caller's own.
    let rows = if include_current {
        sqlx::query(
            "SELECT s.id, s.created_at, s.last_activity_at, s.expires_at, \
             s.device_name, s.platform, \
             CASE WHEN s.id = $2 THEN 1 ELSE 0 END AS is_current \
             FROM sessions s WHERE s.user_id = $1 AND s.expires_at > CURRENT_TIMESTAMP \
             ORDER BY s.last_activity_at DESC",
        )
        .bind(user_id)
        .bind(current.0)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(
            "SELECT s.id, s.created_at, s.last_activity_at, s.expires_at, \
             s.device_name, s.platform, 0 AS is_current \
             FROM sessions s WHERE s.user_id = $1 AND s.expires_at > CURRENT_TIMESTAMP \
             ORDER BY s.last_activity_at DESC",
        )
        .bind(user_id)
        .fetch_all(&state.db)
        .await?
    };

    let sessions = rows
        .into_iter()
        .map(|r| SessionInfoResponse {
            session_id: r.get("id"),
            created_at: r.get("created_at"),
            last_activity_at: r.get("last_activity_at"),
            expires_at: r.get("expires_at"),
            is_current: r.get::<i64, _>("is_current") != 0,
            device_name: r.get("device_name"),
            platform: r.get("platform"),
        })
        .collect();

    Ok(Json(SessionsListResponse { sessions }))
}

pub(crate) async fn revoke_session(
    State(state): State<AppState>,
    Extension(user_id): Extension<Uuid>,
    Query(query): Query<crate::models::RevokeSessionQuery>,
) -> Result<Json<RevokeSessionResponse>, AppError> {
    let session_id = query
        .session_id
        .ok_or_else(|| AppError::BadRequest("session_id is required".into()))?;

    let affected = sqlx::query("DELETE FROM sessions WHERE id = $1 AND user_id = $2")
        .bind(session_id)
        .bind(user_id)
        .execute(&state.db)
        .await?;

    if affected.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    crate::handlers::admin::audit(
        &state.db,
        user_id,
        "revoke_session",
        Some(&session_id.to_string()),
    )
    .await?;

    Ok(Json(RevokeSessionResponse {
        revoked: affected.rows_affected() as u64,
    }))
}

pub(crate) async fn revoke_other_sessions(
    State(state): State<AppState>,
    Extension(user_id): Extension<Uuid>,
    Extension(current): Extension<CurrentSessionId>,
    Query(query): Query<crate::models::RevokeOtherSessionsQuery>,
) -> Result<Json<RevokeSessionResponse>, AppError> {
    let exclude_current = query.exclude_current.unwrap_or(true);

    // "Every session except mine" is anchored on the authenticated session id
    // carried in the request extensions; anything else risks revoking the
    // caller's own session instead of the others.
    let session_ids: Vec<Uuid> = if exclude_current {
        sqlx::query_scalar(
            "SELECT id FROM sessions WHERE user_id = $1 AND expires_at > CURRENT_TIMESTAMP \
             AND id <> $2",
        )
        .bind(user_id)
        .bind(current.0)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query_scalar(
            "SELECT id FROM sessions WHERE user_id = $1 AND expires_at > CURRENT_TIMESTAMP",
        )
        .bind(user_id)
        .fetch_all(&state.db)
        .await?
    };

    if session_ids.is_empty() {
        return Ok(Json(RevokeSessionResponse { revoked: 0 }));
    }

    for id in &session_ids {
        sqlx::query("DELETE FROM sessions WHERE id = $1 AND user_id = $2")
            .bind(id)
            .bind(user_id)
            .execute(&state.db)
            .await?;
    }

    crate::handlers::admin::audit(
        &state.db,
        user_id,
        "revoke_other_sessions",
        Some(&format!("{} sessions", session_ids.len())),
    )
    .await?;

    Ok(Json(RevokeSessionResponse {
        revoked: session_ids.len() as u64,
    }))
}

pub(crate) async fn sign_out_everywhere(
    State(state): State<AppState>,
    Extension(user_id): Extension<Uuid>,
) -> Result<Json<RevokeSessionResponse>, AppError> {
    let affected = sqlx::query("DELETE FROM sessions WHERE user_id = $1")
        .bind(user_id)
        .execute(&state.db)
        .await?;

    crate::handlers::admin::audit(&state.db, user_id, "sign_out_everywhere", None).await?;

    Ok(Json(RevokeSessionResponse {
        revoked: affected.rows_affected() as u64,
    }))
}

/// Revokes every session belonging to [user_id] without touching credentials.
///
/// Used by password changes and by administrative "sign out everywhere" flows
/// that are scoped to a single account. The calling handler must already have
/// verified authorization (for example that the acting admin is allowed to
/// revoke this account's sessions).
pub(crate) async fn revoke_all_for_user(
    db: &sqlx::sqlite::SqlitePool,
    user_id: Uuid,
    acted_by: Uuid,
    reason: &str,
) -> Result<u64, AppError> {
    let affected = sqlx::query("DELETE FROM sessions WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    crate::handlers::admin::audit(db, acted_by, reason, Some(&user_id.to_string())).await?;
    Ok(affected.rows_affected() as u64)
}
