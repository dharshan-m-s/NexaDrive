use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use sqlx::{Row, sqlite::SqlitePool};
use std::collections::HashMap;
use uuid::Uuid;

use crate::{
    error::AppError,
    models::{NotificationReadRequest, NotificationResponse},
    state::AppState,
};

pub(crate) async fn list_notifications(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<Json<Vec<NotificationResponse>>, AppError> {
    let unread = query.get("unread").map(|v| v == "true").unwrap_or(false);
    let rows = if unread {
        sqlx::query("SELECT id,kind,title,message,severity,read,created_at FROM notifications WHERE user_id=$1 AND read=FALSE ORDER BY created_at DESC LIMIT 100").bind(user_id).fetch_all(&state.db).await?
    } else {
        sqlx::query("SELECT id,kind,title,message,severity,read,created_at FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100").bind(user_id).fetch_all(&state.db).await?
    };
    Ok(Json(
        rows.into_iter()
            .map(|r| NotificationResponse {
                id: r.get("id"),
                kind: r.get("kind"),
                title: r.get("title"),
                message: r.get("message"),
                severity: r.get("severity"),
                read: r.get("read"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

pub(crate) async fn mark_notifications_read(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<NotificationReadRequest>,
) -> Result<StatusCode, AppError> {
    if payload.all.unwrap_or(false) {
        sqlx::query("UPDATE notifications SET read=TRUE WHERE user_id=$1")
            .bind(user_id)
            .execute(&state.db)
            .await?;
    } else if let Some(id) = payload.id {
        sqlx::query("UPDATE notifications SET read=TRUE WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .execute(&state.db)
            .await?;
    } else {
        return Err(AppError::BadRequest(
            "Provide a notification id or all=true".into(),
        ));
    }
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn create_notification(
    db: &SqlitePool,
    user_id: Uuid,
    kind: &str,
    title: &str,
    message: &str,
    severity: &str,
) -> Result<(), AppError> {
    sqlx::query("INSERT INTO notifications(id,user_id,kind,title,message,severity) VALUES($1,$2,$3,$4,$5,$6)")
        .bind(Uuid::new_v4()).bind(user_id).bind(kind).bind(title).bind(message).bind(severity).execute(db).await?;
    Ok(())
}
