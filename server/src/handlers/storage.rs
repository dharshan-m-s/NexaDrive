use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use sqlx::Row;
use std::path::{Path, PathBuf};
use tokio::fs;
use uuid::Uuid;

use crate::{
    error::AppError,
    handlers::admin::audit,
    models::{IdQuery, StorageResponse, TrashEntry},
    paths::{safe_relative_path, trash_root, user_root},
    state::AppState,
};

pub(crate) async fn list_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<TrashEntry>>, AppError> {
    let rows = sqlx::query("SELECT id, name, original_path, kind, size_bytes, deleted_at FROM trash_items WHERE user_id=$1 ORDER BY deleted_at DESC")
        .bind(user_id).fetch_all(&state.db).await?;
    let items = rows
        .into_iter()
        .map(|r| TrashEntry {
            id: r.get("id"),
            name: r.get("name"),
            original_path: r.get("original_path"),
            kind: r.get("kind"),
            size: r.get("size_bytes"),
            deleted_at: r.get("deleted_at"),
        })
        .collect();
    Ok(Json(items))
}

pub(crate) async fn restore_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<IdQuery>,
) -> Result<StatusCode, AppError> {
    let id = query
        .id
        .ok_or_else(|| AppError::BadRequest("Trash id is required".into()))?;
    let row =
        sqlx::query("SELECT original_path, trash_path FROM trash_items WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
    let original: String = row.get("original_path");
    let trash_path: String = row.get("trash_path");
    let relative = safe_relative_path(&original)?;
    let destination = user_root(&state, user_id).join(&relative);
    if destination.exists() {
        return Err(AppError::Conflict(
            "An item already exists at the original location".into(),
        ));
    }
    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent).await?;
    }
    fs::rename(&trash_path, &destination).await?;
    sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
        .bind(user_id)
        .bind(&original)
        .execute(&state.db)
        .await?;
    sqlx::query("DELETE FROM trash_items WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    audit(&state.db, user_id, "restore", Some(&original)).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn permanently_delete_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<IdQuery>,
) -> Result<StatusCode, AppError> {
    let id = query
        .id
        .ok_or_else(|| AppError::BadRequest("Trash id is required".into()))?;
    let row =
        sqlx::query("SELECT trash_path, original_path FROM trash_items WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
    let trash_path: String = row.get("trash_path");
    let original: String = row.get("original_path");
    let candidate = PathBuf::from(&trash_path);
    let allowed_root = trash_root(&state, user_id);
    if !candidate.starts_with(&allowed_root) {
        return Err(AppError::Forbidden);
    }
    if candidate.is_dir() {
        fs::remove_dir_all(&candidate).await?;
    } else if candidate.exists() {
        fs::remove_file(&candidate).await?;
    }
    sqlx::query("DELETE FROM trash_items WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    audit(&state.db, user_id, "permanent_delete", Some(&original)).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn storage(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<StorageResponse>, AppError> {
    let root = user_root(&state, user_id);
    fs::create_dir_all(&root).await?;
    let (used, count) = tree_stats(&root).await?;
    Ok(Json(StorageResponse {
        used_bytes: used,
        file_count: count,
    }))
}

pub(crate) async fn folder_size(path: &Path) -> Result<u64, AppError> {
    Ok(tree_stats(path).await?.0)
}

pub(crate) async fn tree_stats(root: &Path) -> Result<(u64, u64), AppError> {
    let mut stack = vec![root.to_path_buf()];
    let mut used = 0u64;
    let mut count = 0u64;
    while let Some(dir) = stack.pop() {
        // The tree changes underneath a walk (files are uploaded, renamed or
        // deleted while it runs), so a directory that disappears mid-walk is
        // not an error: it simply contributes nothing.
        let mut entries = match fs::read_dir(dir).await {
            Ok(entries) => entries,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => return Err(AppError::Io(e)),
        };
        while let Some(entry) = entries.next_entry().await? {
            let ft = match entry.file_type().await {
                Ok(ft) => ft,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                Err(e) => return Err(AppError::Io(e)),
            };
            if ft.is_symlink() {
                continue;
            }
            if ft.is_dir() {
                stack.push(entry.path());
            } else if ft.is_file() {
                let name = entry.file_name().to_string_lossy().to_string();
                // Partially uploaded files are not user data yet.
                if crate::handlers::upload::is_staging_name(&name) {
                    continue;
                }
                let metadata = match entry.metadata().await {
                    Ok(metadata) => metadata,
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(AppError::Io(e)),
                };
                used = used.saturating_add(metadata.len());
                count += 1;
            }
        }
    }
    Ok((used, count))
}
